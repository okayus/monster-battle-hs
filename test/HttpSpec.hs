{-# LANGUAGE OverloadedStrings #-}

-- | The HTTP contract, over SQLite in memory: paths, statuses, bodies.
--
-- From TS 版's save.test.ts, the cases that need nothing but the starter
-- map. Those that need a second map are in SavesSpec, on the model.
module HttpSpec (spec) where

import Control.Monad ((>=>))
import Data.Aeson (Object, Value (..), decode, object, (.:), (.=))
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Aeson.Types (Pair, parseMaybe)
import Data.ByteString (ByteString)
import Data.ByteString.Lazy qualified as LBS
import Data.Foldable (for_)
import Data.Text (Text)
import Network.HTTP.Types
import Network.Wai (Application, RequestBodyLength (..), requestBodyLength, requestMethod)
import Network.Wai.Test
import Test.Hspec

import Mba.Http (Env (..), app)
import Support

withApp :: (Application -> IO a) -> IO a
withApp act = withDb $ \db applied -> act (app (Env db applied "no-web" "no-admin"))

get :: ByteString -> Session SResponse
get = request . setPath defaultRequest

-- | A body that says how long it is, as a browser sends one.
send :: Method -> ByteString -> LBS.ByteString -> Session SResponse
send method path body = srequest (SRequest (setPath req path) body)
 where
  req =
    defaultRequest
      { requestMethod = method
      , requestBodyLength = KnownLength (fromIntegral (LBS.length body))
      }

-- | A body that does not say how long it is: chunked.
sendChunked :: Method -> ByteString -> LBS.ByteString -> Session SResponse
sendChunked method path =
  srequest
    . SRequest (setPath defaultRequest{requestMethod = method, requestBodyLength = ChunkedBody} path)

saved :: Int -> Int -> Value
saved x y = object ["mapId" .= ("start" :: Text), "position" .= object ["x" .= x, "y" .= y]]

refused :: Text -> [Pair] -> Value
refused kind fields = object ["error" .= object (("kind" .= kind) : fields)]

-- | The status, and the body as JSON.
answers :: (Status, Value) -> SResponse -> Expectation
answers (status, body) r = (simpleStatus r, decode (simpleBody r)) `shouldBe` (status, Just body)

spec :: Spec
spec = around withApp $ do
  describe "GET /api/health" $
    it "is ok, and says how many migrations this boot ran" $
      runSession (get "/api/health")
        >=> answers (status200, object ["status" .= ("ok" :: Text), "migrationsApplied" .= (9 :: Int)])

  describe "GET /api/save" $
    it "starts a player with no save at the starter map's spawn" $
      runSession (get "/api/save") >=> answers (status200, saved 1 1)

  describe "PUT /api/save" $ do
    it "stores a position, echoes it, and GET answers with it" $ \a -> do
      runSession (send methodPut "/api/save" "{\"mapId\":\"start\",\"position\":{\"x\":4,\"y\":2}}") a
        >>= answers (status200, saved 4 2)
      runSession (get "/api/save") a >>= answers (status200, saved 4 2)

    it "answers with what it checked, not with the body: fields it does not know are gone" $
      runSession
        (send methodPut "/api/save" "{\"mapId\":\"start\",\"position\":{\"x\":4,\"y\":2},\"userId\":\"x\"}")
        >=> answers (status200, saved 4 2)

    it "refuses a tile nobody can stand on with 400, and keeps the save it had" $ \a -> do
      runSession (send methodPut "/api/save" "{\"mapId\":\"start\",\"position\":{\"x\":0,\"y\":0}}") a
        >>= answers
          ( status400
          , refused
              "cannot_stand"
              ["mapId" .= ("start" :: Text), "position" .= object ["x" .= (0 :: Int), "y" .= (0 :: Int)]]
          )
      runSession (get "/api/save") a >>= answers (status200, saved 1 1)

    it "refuses a map that is not there" $
      runSession (send methodPut "/api/save" "{\"mapId\":\"no-such-map\",\"position\":{\"x\":1,\"y\":1}}")
        >=> answers (status400, refused "unknown_map" ["mapId" .= ("no-such-map" :: Text)])

    describe "says where a body is malformed: the first field that is wrong"
      $ for_
        [ ("no position", "{\"mapId\":\"start\"}", "$.position")
        , ("no map id", "{\"position\":{\"x\":1,\"y\":1}}", "$.mapId")
        ,
          ( "a coordinate that is a string"
          , "{\"mapId\":\"start\",\"position\":{\"x\":\"1\",\"y\":1}}"
          , "$.position.x"
          )
        ,
          ( "a coordinate between tiles"
          , "{\"mapId\":\"start\",\"position\":{\"x\":1,\"y\":1.5}}"
          , "$.position.y"
          )
        , ("a body that is not an object", "null", "$")
        ]
      $ \(label, body, at) ->
        it label $
          runSession (send methodPut "/api/save" body)
            >=> answers (status400, refused "malformed" ["at" .= (at :: Text)])

    it "refuses a body that is not JSON" $
      runSession (send methodPut "/api/save" "{ not json") >=> answers (status400, refused "bad_json" [])

    it "refuses with 413 a body far larger than any save, before reading it" $
      runSession (send methodPut "/api/save" (LBS.replicate 2000 32))
        >=> answers (status413, refused "body_too_large" ["max" .= (1024 :: Int)])

    it "and one that does not say how long it is, as soon as it passes the limit" $
      runSession (sendChunked methodPut "/api/save" (LBS.replicate 2000 32))
        >=> answers (status413, refused "body_too_large" ["max" .= (1024 :: Int)])

  describe "GET /api/maps/:id" $ do
    it "the starter map, as the map screen reads it" $ \a -> do
      r <- runSession (get "/api/maps/start") a
      simpleStatus r `shouldBe` status200
      let body = decode (simpleBody r) :: Maybe Object
          field k = body >>= KeyMap.lookup k
      map field ["id", "name", "width", "height", "spawn", "exits"]
        `shouldBe` map
          Just
          [ String "start"
          , String "はじまりの草原"
          , Number 16
          , Number 12
          , object ["x" .= (1 :: Int), "y" .= (1 :: Int)]
          , Array mempty
          ]
      let tiles = body >>= parseMaybe (.: "tiles") :: Maybe [Text]
      fmap (\ts -> (length ts, take 2 (drop 16 ts))) tiles `shouldBe` Just (192, ["tree", "path"])

    it "404 for a map that is not there" $
      runSession (get "/api/maps/nowhere") >=> answers (status404, refused "not_found" [])

  describe "a path or a method with nothing there" $ do
    it "404 under /api" $ \a ->
      (simpleStatus <$> runSession (get "/api/no-such-route") a) `shouldReturn` status404
    it "404, not 405, for a method the path does not take" $ \a -> do
      (simpleStatus <$> runSession (send methodPost "/api/save" "{}") a) `shouldReturn` status404
      (simpleStatus <$> runSession (send methodDelete "/api/maps/start" "") a) `shouldReturn` status404
