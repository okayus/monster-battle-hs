{-# LANGUAGE OverloadedStrings #-}

-- | Editor and wardrobe contracts, through HTTP and independently read SQL.
module SkinContractSpec (spec, skinInput, recipe) where

import Data.Aeson (Object, Value (..), decode, encode, object, toJSON, (.:), (.=))
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Aeson.Types (Pair, parseEither)
import Data.ByteString (ByteString)
import Data.ByteString.Lazy qualified as LBS
import Data.Foldable (for_)
import Data.Text (Text)
import Data.Text qualified as T
import Database.SQLite.Simple qualified as SQL
import Network.HTTP.Types
import Network.Wai (Application, RequestBodyLength (..), requestBodyLength, requestMethod)
import Network.Wai.Test
import Test.Hspec

import ReadContractSpec (answers, get, withStoredApp)

names :: [Text]
names = ["body", "shirt", "pants", "shoes", "hair"]

-- Two skins share an unused palette entry, but paint different hair colours.
skinInput :: Bool -> Value
skinInput alternative =
  object
    [ "formatVersion" .= (1 :: Int)
    , "name" .= ("  fixture  " :: Text)
    , "palette"
        .= [ colour "skin" "#e8b98a"
           , colour (if alternative then "hat" else "hair") "#123456"
           , colour "unused" "#00ff00"
           ]
    , "parts"
        .= [ object ["slot" .= slot, "frames" .= [object ["durationMs" .= (120 :: Int), "cells" .= cells slot]]]
           | slot <- names
           ]
    ]
 where
  cells "body" = [[1, 16], [0, 240]] :: [[Int]]
  cells "hair" = [[2, 16], [0, 240]]
  cells _ = [[0, 256]]

colour :: Text -> Text -> Value
colour cid hex = object ["id" .= cid, "hex" .= hex]

recipe :: Text -> Value -> [Text] -> Value
recipe sid parts colours = object ["skinId" .= sid, "parts" .= parts, "colours" .= map (`colour` "#AAbbCC") colours]

patch :: [Pair] -> Value -> Value
patch fields (Object o) = Object (KeyMap.union (KeyMap.fromList fields) o)
patch _ v = v

send :: Application -> Method -> ByteString -> LBS.ByteString -> IO SResponse
send a method path body = runSession (srequest (SRequest req body)) a
 where
  req =
    setPath
      defaultRequest
        { requestMethod = method
        , requestBodyLength = KnownLength (fromIntegral (LBS.length body))
        }
      path

post :: Application -> Value -> IO SResponse
post a = send a methodPost "/api/skins" . encode
put :: Application -> Value -> IO SResponse
put a = send a methodPut "/api/appearance" . encode

draw :: Application -> Bool -> Text -> IO ()
draw a alternative sid = post a (skinInput alternative) >>= answers status201 (object ["id" .= sid])

refused :: Text -> [Pair] -> Value
refused kind fields = object ["error" .= object (("kind" .= kind) : fields)]

spec :: Spec
spec = around withStoredApp $ do
  describe "skin editor HTTP contracts" $ do
    it "stores canonical source, derives rectangles, and obtains IDs and ownership from the server" $ \(a, conn, _) -> do
      let source = skinInput False
          input =
            patch
              ["id" .= ("client" :: Text), "ownerId" .= ("someone-else" :: Text), "evil" .= ("<script>" :: Text)]
              source
      r <- post a input
      answers status201 (object ["id" .= ("skin-1" :: Text)]) r
      lookup hLocation (simpleHeaders r) `shouldBe` Just "/api/skins/skin-1"
      get a "/api/skins/skin-1/source" >>= answers status200 source
      ( SQL.query_ conn "SELECT id, owner_id, name, format_version FROM skins WHERE owner_id IS NOT NULL" ::
          IO [(Text, Text, Text, Int)]
        )
        `shouldReturn` [("skin-1", "local", "  fixture  ", 1)]
      let drawing =
            object
              [ "formatVersion" .= (1 :: Int)
              , "palette" .= [colour "skin" "#e8b98a", colour "hair" "#123456", colour "unused" "#00ff00"]
              , "parts"
                  .= [ object ["slot" .= slot, "frames" .= [object ["durationMs" .= (120 :: Int), "rects" .= rects slot]]]
                     | slot <- names
                     ]
              ]
          rects "body" = [[0, 0, 16, 1, 1]] :: [[Int]]
          rects "hair" = [[0, 0, 16, 1, 2]]
          rects _ = []
      get a "/api/skins/skin-1" >>= answers status200 drawing
      post a source >>= answers status201 (object ["id" .= ("skin-2" :: Text)])
      get a "/api/skins/skin-2" >>= answers status200 drawing

    it "rejects every TS invalid skin fixture without storing or consuming an ID" $ \(a, conn, _) -> do
      root <-
        LBS.readFile "test/fixtures/sprite.json" >>= maybe (fail "fixtures") pure . decode :: IO Object
      entries <- either fail pure (parseEither (.: "skinCases") root) :: IO [Object]
      for_ entries $ \entry -> do
        (input, outcome) <-
          either fail pure (parseEither (\o -> (,) <$> o .: "input" <*> o .: "result") entry) ::
            IO (Value, Object)
        case KeyMap.lookup "error" outcome of
          Just problem
            | LBS.length (encode input) <= 65536 ->
                post a input >>= answers status400 (object ["error" .= problem])
          _ -> pure ()
      (SQL.query_ conn "SELECT count(*) FROM skins WHERE owner_id IS NOT NULL" :: IO [SQL.Only Int])
        `shouldReturn` [SQL.Only 0]
      draw a False "skin-1"

    it "separates wire size from JSON reserialization size, before shape validation" $ \(a, _, _) -> do
      let wire = "{\"pad\":[" <> LBS.intercalate "," (replicate 4000 "1e20") <> "]}"
      send a methodPost "/api/skins" wire
        >>= answers status400 (refused "too_large" ["bytes" .= (88009 :: Int), "max" .= (65536 :: Int)])
      send a methodPost "/api/skins" "{broken" >>= answers status400 (refused "bad_json" [])
      draw a False "skin-1"

    it
      "lists names in creation order with mine, hides owners, and excludes retired skins only from the list"
      $ \(a, conn, _) -> do
        draw a False "skin-1"
        SQL.execute_
          conn
          "INSERT INTO users (id, display_name, created_at) VALUES ('another-player', 'other', 0)"
        SQL.execute_
          conn
          "INSERT INTO skins (id, owner_id, name, format_version, source, renderable, created_at) SELECT 'theirs', 'another-player', 'other', format_version, source, renderable, 1 FROM skins WHERE id = 'skin-1'"
        SQL.execute_ conn "UPDATE skins SET retired_at = 2 WHERE id = 'skin-1'"
        response <- get a "/api/skins"
        simpleStatus response `shouldBe` status200
        let summary sid name mine = object ["id" .= (sid :: Text), "name" .= (name :: Text), "mine" .= mine]
        answers
          status200
          ( toJSON
              [ summary "theirs" "other" False
              , summary "player-default" "はじめのすがた" False
              , summary "species-drop" "ヌマダマ" False
              , summary "species-moss" "モリダマ" False
              , summary "species-rock" "イワダマ" False
              ]
          )
          response
        get a "/api/skins/skin-1/source" >>= answers status200 (skinInput False)
        (simpleStatus <$> get a "/api/skins/skin-1") `shouldReturn` status200
        get a "/api/skins/missing/source" >>= answers status404 (refused "not_found" [])

  describe "appearance HTTP contracts" $ do
    it "preserves the key order displayed by the unchanged wardrobe" $ \(a, _, _) -> do
      draw a False "skin-1"
      draw a True "skin-2"
      let wanted = recipe "skin-1" (object ["shirt" .= ("skin-2" :: Text), "pants" .= ("skin-2" :: Text)]) ["hair"]
          wire =
            "{\"skinId\":\"skin-1\",\"parts\":{\"shirt\":\"skin-2\",\"pants\":\"skin-2\"},\"colours\":[{\"id\":\"hair\",\"hex\":\"#AAbbCC\"}]}"
      response <- put a wanted
      simpleStatus response `shouldBe` status200
      simpleBody response `shouldBe` wire
      (simpleBody <$> get a "/api/appearance") `shouldReturn` wire

    it "normalizes and replaces a recipe for the caller, without storing a drawing" $ \(a, conn, _) -> do
      draw a False "skin-1"
      draw a True "skin-2"
      let look = recipe "skin-1" (object ["hair" .= ("skin-2" :: Text)]) ["hat"]
          claimed =
            patch
              [ "userId" .= ("someone-else" :: Text)
              , "parts" .= object ["body" .= ("skin-1" :: Text), "hair" .= ("skin-2" :: Text)]
              ]
              look
      put a claimed >>= answers status200 look
      get a "/api/appearance" >>= answers status200 look
      rows <-
        SQL.query_ conn "SELECT user_id, skin_id, part_overrides, colour_overrides FROM appearances" ::
          IO [(Text, Text, Text, Text)]
      case rows of
        [(user, sid, parts, colours)] -> do
          (user, sid) `shouldBe` ("local", "skin-1")
          T.length (sid <> parts <> colours) `shouldSatisfy` (< 100)
          T.isInfixOf "rects" (parts <> colours) `shouldBe` False
        _ -> expectationFailure "expected one recipe"
      let replacement = recipe "species-moss" (object []) []
      put a replacement >>= answers status200 replacement
      put a replacement >>= answers status200 replacement
      get a "/api/appearance" >>= answers status200 replacement
      (SQL.query_ conn "SELECT count(*) FROM appearances" :: IO [SQL.Only Int])
        `shouldReturn` [SQL.Only 1]

    it "checks only painted colours after swapping parts, and preserves a chosen look on every refusal" $ \(a, _, _) -> do
      draw a False "skin-1"
      draw a True "skin-2"
      let look = recipe "skin-1" (object []) ["hair"]
      put a look >>= answers status200 look
      for_ ["hair", "unused", "no-colour"] $ \cid ->
        put a (recipe "skin-1" (object ["hair" .= ("skin-2" :: Text)]) [cid])
          >>= answers status400 (refused "unknown_colour" ["id" .= cid])
      put a (recipe "missing" (object []) ["unused"])
        >>= answers status400 (refused "unknown_skin" ["skinId" .= ("missing" :: Text)])
      put
        a
        (recipe "skin-1" (object ["body" .= ("gone-first" :: Text), "hair" .= ("gone-second" :: Text)]) [])
        >>= answers status400 (refused "unknown_skin" ["skinId" .= ("gone-first" :: Text)])
      get a "/api/appearance" >>= answers status200 look

    it "rejects the TS malformed recipe fixtures before looking up skins" $ \(a, conn, _) -> do
      root <-
        LBS.readFile "test/fixtures/sprite.json" >>= maybe (fail "fixtures") pure . decode :: IO Object
      entries <- either fail pure (parseEither (.: "appearanceCases") root) :: IO [Object]
      for_ entries $ \entry -> do
        (input, outcome) <-
          either fail pure (parseEither (\o -> (,) <$> o .: "input" <*> o .: "result") entry) ::
            IO (Value, Object)
        case KeyMap.lookup "error" outcome of
          Just problem -> put a input >>= answers status400 (object ["error" .= problem])
          _ -> pure ()
      (SQL.query_ conn "SELECT count(*) FROM appearances" :: IO [SQL.Only Int])
        `shouldReturn` [SQL.Only 0]

    it
      "drops retired parts and their colours on read, falls back for a retired base, and never repairs the stored row"
      $ \(a, conn, _) -> do
        draw a False "skin-1"
        draw a True "skin-2"
        let look = recipe "skin-1" (object ["hair" .= ("skin-2" :: Text)]) ["hat", "skin"]
        put a look >>= answers status200 look
        SQL.execute_ conn "UPDATE skins SET retired_at = 1 WHERE id = 'skin-2'"
        get a "/api/appearance" >>= answers status200 (recipe "skin-1" (object []) ["skin"])
        put a look >>= answers status400 (refused "unknown_skin" ["skinId" .= ("skin-2" :: Text)])
        SQL.execute_ conn "UPDATE skins SET retired_at = 1 WHERE id = 'skin-1'"
        get a "/api/appearance" >>= answers status200 (recipe "player-default" (object []) [])
        SQL.execute_ conn "UPDATE skins SET retired_at = NULL WHERE id IN ('skin-1', 'skin-2')"
        get a "/api/appearance" >>= answers status200 look

  describe "body limits and methods" $ do
    for_ [(methodPost, "/api/skins", 65536), (methodPut, "/api/appearance", 4096)] $ \(method, path, limit) ->
      it (show path <> " rejects both declared and streamed oversized bodies before JSON parsing") $ \(a, _, _) -> do
        let body = LBS.replicate (fromIntegral limit + 1) 32
            expected = refused "body_too_large" ["max" .= (limit :: Int)]
        send a method path body >>= answers status413 expected
        runSession
          ( srequest
              (SRequest (setPath defaultRequest{requestMethod = method, requestBodyLength = ChunkedBody} path) body)
          )
          a
          >>= answers status413 expected
    it "keeps unsupported methods and extra path segments at 404" $ \(a, _, _) ->
      for_
        [ (methodPut, "/api/skins")
        , (methodPost, "/api/appearance")
        , (methodDelete, "/api/skins/player-default")
        , (methodGet, "/api/skins/player-default/source/more")
        ]
        $ \(method, path) ->
          (simpleStatus <$> send a method path "{}") `shouldReturn` status404
