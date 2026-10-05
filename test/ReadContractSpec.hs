{-# LANGUAGE OverloadedStrings #-}

-- | HTTP contracts that need stored state changed independently of the API.
-- A second connection sets up edits and saves that future admin routes will make.
module ReadContractSpec (spec, withStoredApp, get, answers) where

import Control.Exception (bracket)
import Data.Aeson (Value, decode, encode, object, toJSON, (.=))
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString (ByteString)
import Data.ByteString.Lazy qualified as LBS
import Data.Foldable (toList)
import Data.Sequence qualified as Seq
import Data.Text (Text)
import Data.Text.Encoding (decodeUtf8, encodeUtf8)
import Database.SQLite.Simple qualified as SQL
import Network.HTTP.Types
import Network.Wai (Application, requestMethod)
import Network.Wai.Test
import System.Directory (getTemporaryDirectory, removeFile)
import System.IO (hClose, openTempFile)
import Test.Hspec

import Mba.Auth (localUser)
import Mba.Http (Env (..), app)
import Mba.Map
import Mba.Sqlite qualified as Sqlite
import Support (idSupply, rooms, starter)

withStoredApp :: ((Application, SQL.Connection, Sqlite.Db) -> IO a) -> IO a
withStoredApp act = bracket temporary removeFile $ \path -> do
  next <- idSupply
  bracket (Sqlite.open (pure 1700000000) next path) Sqlite.close $ \db -> do
    applied <- Sqlite.migrate db "migrations" 0
    Sqlite.seed db localUser 1700000000
    SQL.withConnection path $ \conn -> act (app (Env db applied "no-web" "no-admin"), conn, db)
 where
  temporary = do
    dir <- getTemporaryDirectory
    (path, handle) <- openTempFile dir "monster-battle-contract.db"
    hClose handle
    pure path

get :: Application -> ByteString -> IO SResponse
get a path = runSession (request (setPath defaultRequest path)) a

putSave :: Application -> Value -> IO SResponse
putSave a body =
  runSession
    (srequest (SRequest (setPath defaultRequest{requestMethod = methodPut} "/api/save") (encode body)))
    a

saved :: Text -> Int -> Int -> Value
saved mid x y = object ["mapId" .= mid, "position" .= object ["x" .= x, "y" .= y]]

jsonText :: Value -> Text
jsonText = decodeUtf8 . LBS.toStrict . encode

answers :: Status -> Value -> SResponse -> Expectation
answers status body r = (simpleStatus r, decode (simpleBody r)) `shouldBe` (status, Just body)

spec :: Spec
spec = around withStoredApp $ do
  describe "appearance and drawing reads" $ do
    it "returns the default recipe without creating an appearance or save" $ \(a, conn, _) -> do
      get a "/api/appearance"
        >>= answers
          status200
          (object ["skinId" .= ("player-default" :: Text), "parts" .= object [], "colours" .= ([] :: [Value])])
      get a "/api/save" >>= answers status200 (saved "start" 1 1)
      (SQL.query_ conn "SELECT count(*) FROM appearances" :: IO [SQL.Only Int])
        `shouldReturn` [SQL.Only 0]
      (SQL.query_ conn "SELECT count(*) FROM saves" :: IO [SQL.Only Int]) `shouldReturn` [SQL.Only 0]

    it "reads the stored recipe, including parts and colours" $ \(a, conn, _) -> do
      SQL.execute_
        conn
        "INSERT INTO appearances VALUES ('local', 'player-default', '{\"hair\":\"player-default\"}', '[{\"id\":\"hair\",\"hex\":\"#123456\"}]', 0)"
      get a "/api/appearance"
        >>= answers
          status200
          ( object
              [ "skinId" .= ("player-default" :: Text)
              , "parts" .= object ["hair" .= ("player-default" :: Text)]
              , "colours" .= [object ["id" .= ("hair" :: Text), "hex" .= ("#123456" :: Text)]]
              ]
          )

    it "serves the TS-generated drawing with the stored palette and every part" $ \(a, conn, _) -> do
      asset <- decode <$> LBS.readFile "seed/player-default.json"
      expected <- maybe (fail "missing seed drawing") pure (asset >>= KeyMap.lookup "renderable")
      get a "/api/skins/player-default" >>= answers status200 expected
      ( SQL.query_ conn "SELECT name, owner_id, format_version FROM skins WHERE id = 'player-default'" ::
          IO [(Text, Maybe Text, Int)]
        )
        `shouldReturn` [("はじめのすがた", Nothing, 1)]

    it "streams the stored JSON unchanged even when the skin is retired" $ \(a, conn, _) -> do
      let drawing = "{ \"formatVersion\": 1, \"palette\": [], \"parts\": [] }" :: Text
      SQL.execute
        conn
        "UPDATE skins SET renderable = ?, retired_at = 1 WHERE id = 'player-default'"
        (SQL.Only drawing)
      r <- get a "/api/skins/player-default"
      simpleStatus r `shouldBe` status200
      lookup hContentType (simpleHeaders r) `shouldBe` Just "application/json"
      simpleBody r `shouldBe` LBS.fromStrict (encodeUtf8 drawing)

    it "returns not_found for an unknown skin" $ \(a, _, _) ->
      get a "/api/skins/missing"
        >>= answers status404 (object ["error" .= object ["kind" .= ("not_found" :: Text)]])

    it "does not overwrite the default skin on another boot" $ \(_, conn, db) -> do
      SQL.execute_ conn "UPDATE skins SET name = 'edited', retired_at = 12 WHERE id = 'player-default'"
      Sqlite.seed db localUser 99
      ( SQL.query_ conn "SELECT name, retired_at, created_at FROM skins WHERE id = 'player-default'" ::
          IO [(Text, Int, Int)]
        )
        `shouldReturn` [("edited", 12, 1700000000)]

  describe "save contracts over SQLite and HTTP" $ do
    it "refuses another existing map before checking the requested tile" $ \(a, conn, _) -> do
      insertRooms conn
      putSave a (saved "rooms" 1 0)
        >>= answers
          status400
          ( object
              [ "error"
                  .= object
                    ["kind" .= ("wrong_map" :: Text), "mapId" .= ("rooms" :: Text), "current" .= ("start" :: Text)]
              ]
          )
      get a "/api/save" >>= answers status200 (saved "start" 1 1)

    it "cannot cross a wall, ignores a claimed origin, and preserves the last accepted save" $ \(a, conn, _) -> do
      insertRooms conn
      SQL.execute_ conn "INSERT INTO saves VALUES ('local', 'rooms', 0, 1, 0)"
      putSave a (saved "rooms" 0 0) >>= answers status200 (saved "rooms" 0 0)
      let wanted =
            object
              [ "mapId" .= ("rooms" :: Text)
              , "position" .= object ["x" .= (4 :: Int), "y" .= (0 :: Int)]
              , "from" .= object ["x" .= (2 :: Int), "y" .= (1 :: Int)]
              ]
      putSave a wanted
        >>= answers
          status400
          ( object
              [ "error"
                  .= object
                    [ "kind" .= ("unreachable" :: Text)
                    , "mapId" .= ("rooms" :: Text)
                    , "position" .= object ["x" .= (4 :: Int), "y" .= (0 :: Int)]
                    ]
              ]
          )
      get a "/api/save" >>= answers status200 (saved "rooms" 0 0)

    it "falls back after a saved tile is redrawn, without changing the row" $ \(a, conn, _) -> do
      putSave a (saved "start" 4 2) >>= answers status200 (saved "start" 4 2)
      let tiles = Seq.update (2 * mapWidth starter + 4) Tree (mapTiles starter)
      SQL.execute
        conn
        "UPDATE maps SET tiles = ? WHERE id = 'start'"
        (SQL.Only (jsonText (toJSONTiles tiles)))
      get a "/api/save" >>= answers status200 (saved "start" 1 1)
      (SQL.query_ conn "SELECT x, y FROM saves" :: IO [(Int, Int)]) `shouldReturn` [(4, 2)]

insertRooms :: SQL.Connection -> IO ()
insertRooms conn =
  SQL.execute
    conn
    "INSERT INTO maps (id, name, width, height, tiles, spawn_x, spawn_y) VALUES ('rooms', 'rooms', 5, 2, ?, 0, 1)"
    (SQL.Only (jsonText (toJSONTiles (mapTiles rooms))))

toJSONTiles :: Seq.Seq Tile -> Value
toJSONTiles = toJSON . map tileName . toList
