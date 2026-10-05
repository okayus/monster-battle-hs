{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

-- | The tables in SQLite, and the decisions run on them in production.
--
-- Two jobs. At boot, 'migrate' runs TS 版's migration files as they are, and
-- 'seed' puts in what every game starts with. During a request, 'perform'
-- runs a decision in one transaction: it answers the decision's questions
-- with SELECTs and, if the decision settles, 'commit' writes what it said.
-- 'commit' is the only thing that writes during a request.
--
-- Every decision runs under one lock. Warp serves requests on many threads,
-- and Node's single thread no longer keeps one request's reading and writing
-- apart from another's (docs/01-design.md §直列にする).
--
-- @
-- db <- open (pure 0) (pure "new-id") ":memory:"
-- applied <- migrate db "migrations" 0
-- seed db localUser 0
-- perform db (savePosition localUser wanted)
-- @
module Mba.Sqlite (
  Db,
  open,
  close,
  migrate,
  seed,
  tables,
  perform,
  create,
  query,
)
where

import Control.Concurrent.MVar (MVar, newMVar, withMVar)
import Data.Aeson (Value, decodeStrict, eitherDecodeStrict, encode, toJSON, withObject, (.:))
import Data.Aeson.Types (parseEither)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.Foldable (for_, toList, traverse_)
import Data.Int (Int64)
import Data.List (isSuffixOf, sort)
import Data.Maybe (listToMaybe)
import Data.Sequence qualified as Seq
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding (decodeUtf8, encodeUtf8)
import Database.SQLite.Simple qualified as SQL
import Database.SQLite3 qualified as Direct
import System.Directory (listDirectory)
import System.FilePath ((</>))

import Mba.Appearance (Appearance (..), Colour (..))
import Mba.Decision (
  Change (..),
  Creation,
  Decision,
  Phase (..),
  Query (..),
  SkinSummary (..),
  userIdText,
 )
import Mba.Decision.Internal (UserId (..))
import Mba.Decision.Run qualified as Run
import Mba.Map
import Mba.Maps (starterMap)
import Mba.Sprite (Skin, resolvedAppearance, skinName, toRenderable)
import Mba.Sprite.Json (colourJson, jsonText, parseSkin, readRenderable, renderableJson, skinJson)

data Db = Db
  { dbConnection :: !SQL.Connection
  , dbLock :: !(MVar ())
  , dbNewId :: !(IO Text)
  , dbClock :: !(IO Int64)
  -- ^ Unix seconds. Handed in by Main, which is the only one with a real clock.
  }

-- | Opens the database: a file, or @:memory:@ for the tests.
open :: IO Int64 -> IO Text -> FilePath -> IO Db
open clock newId path = do
  conn <- SQL.open path
  SQL.execute_ conn "PRAGMA journal_mode = WAL"
  SQL.execute_ conn "PRAGMA foreign_keys = ON"
  lock <- newMVar ()
  pure (Db conn lock newId clock)

close :: Db -> IO ()
close = SQL.close . dbConnection

--------------------------------------------------------------------------------
-- At boot
--------------------------------------------------------------------------------

-- | Runs every @.sql@ file in the directory, in name order, once each — the
-- same files and the same @_migrations@ table as TS 版's @runMigrations@.
-- Returns how many ran now.
--
-- A file holds several statements. 'SQL.execute_' would run the first and
-- quietly drop the rest, so each file goes to SQLite whole, through
-- @sqlite3_exec@ ('Direct.exec').
migrate :: Db -> FilePath -> Int64 -> IO Int
migrate db dir nowMs = do
  SQL.execute_
    conn
    "CREATE TABLE IF NOT EXISTS _migrations (name TEXT PRIMARY KEY, applied_at INTEGER NOT NULL)"
  done <- map SQL.fromOnly <$> SQL.query_ conn "SELECT name FROM _migrations"
  files <- sort . filter (".sql" `isSuffixOf`) <$> listDirectory dir
  let todo = filter (`notElem` done) files
  for_ todo $ \file -> do
    sql <- decodeUtf8 <$> BS.readFile (dir </> file)
    SQL.withTransaction conn $ do
      Direct.exec (SQL.connectionHandle conn) sql
      SQL.execute conn "INSERT INTO _migrations (name, applied_at) VALUES (?, ?)" (file, nowMs)
  pure (length todo)
 where
  conn = dbConnection db

-- | What every game starts with: the local user, who is the admin, and the
-- starter map and four skins. Runs at every boot, without overwriting them.
--
-- Not yet: TS 版 also seeds monsters, species and moves here. They come with
-- the slices that use them.
seed :: Db -> UserId -> Int64 -> IO ()
seed db user now = do
  start <- either (fail . T.unpack) pure starterMap
  assets <- BS.readFile "seed/skins.json"
  values <- either fail pure (eitherDecodeStrict assets :: Either String [Value])
  skins <- traverse seedSkin values
  SQL.withTransaction conn $ do
    SQL.execute
      conn
      "INSERT INTO users (id, display_name, is_admin, created_at) VALUES (?, ?, 1, ?) \
      \ON CONFLICT (id) DO UPDATE SET is_admin = 1"
      (userIdText user, "プレイヤー" :: Text, now)
    SQL.execute
      conn
      "INSERT INTO maps (id, name, width, height, tiles, spawn_x, spawn_y) VALUES (?, ?, ?, ?, ?, ?, ?) \
      \ON CONFLICT DO NOTHING"
      (mapRow start)
    for_ skins $ \(sid, skin) -> writeSkin True conn now sid Nothing skin
 where
  conn = dbConnection db
  mapRow m =
    let MapId mid = mapId m
        Position sx sy = mapSpawn m
     in (mid, mapName m, mapWidth m, mapHeight m, tilesJson m, sx, sy)
  tilesJson = decodeUtf8 . LBS.toStrict . encode . map tileName . toList . mapTiles

-- | Seed source passes the same boundary as an editor submission. The TS
-- drawing alongside it is an oracle for tests, not the production renderer.
seedSkin :: Value -> IO (Text, Skin)
seedSkin value = either fail pure $ do
  (sid, source) <-
    parseEither (withObject "seed skin" $ \o -> (,) <$> o .: "id" <*> o .: "source") value
  skin <- either (Left . show) Right (parseSkin source)
  pure (sid, skin)

writeSkin :: Bool -> SQL.Connection -> Int64 -> Text -> Maybe UserId -> Skin -> IO ()
writeSkin initial conn now sid owner skin =
  SQL.execute
    conn
    ( SQL.Query
        ( "INSERT INTO skins (id, owner_id, name, format_version, source, renderable, created_at) VALUES (?, ?, ?, 1, ?, ?, ?)"
            <> if initial then " ON CONFLICT DO NOTHING" else ""
        )
    )
    ( sid
    , userIdText <$> owner
    , skinName skin
    , jsonText (skinJson skin)
    , jsonText (renderableJson (toRenderable skin))
    , now
    )

-- | The tables there are, by name: what the migrations made.
tables :: Db -> IO [Text]
tables db =
  map SQL.fromOnly
    <$> SQL.query_ (dbConnection db) "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name"

--------------------------------------------------------------------------------
-- During a request
--------------------------------------------------------------------------------

-- | Runs a decision that settles: reads, decides and commits in one
-- transaction, under the lock. A refusal writes nothing.
perform :: Db -> Decision e 'Reading 'Settled a -> IO (Either e a)
perform db d = withMVar (dbLock db) $ \_ ->
  SQL.withImmediateTransaction conn $ do
    decided <- Run.decide (answer conn) d
    case decided of
      Left e -> pure (Left e)
      Right (a, changes) -> do
        now <- dbClock db
        commit conn now changes
        pure (Right a)
 where
  conn = dbConnection db

-- | A creation gets its IDs from the composition root, inside the same
-- transaction as its queries and writes.
create :: Db -> Creation e 'Reading 'Settled a -> IO (Either e a)
create db d = withMVar (dbLock db) $ \_ -> SQL.withImmediateTransaction (dbConnection db) $ do
  result <- Run.create (dbNewId db) (answer (dbConnection db)) d
  case result of
    Left e -> pure (Left e)
    Right (a, changes) -> do
      now <- dbClock db
      commit (dbConnection db) now changes
      pure (Right a)

-- | Runs a question, under the same lock, so that all it reads is one state.
query :: Db -> Decision e 'Reading 'Reading a -> IO (Either e a)
query db d = withMVar (dbLock db) $ \_ ->
  SQL.withTransaction (dbConnection db) (Run.query (answer (dbConnection db)) d)

-- | One equation per question.
answer :: SQL.Connection -> Query a -> IO a
answer conn (FindMap (MapId mid)) = do
  rows <-
    SQL.query
      conn
      "SELECT id, name, width, height, tiles, spawn_x, spawn_y FROM maps \
      \WHERE id = ? AND retired_at IS NULL"
      (SQL.Only mid)
  traverse gameMap (listToMaybe rows)
answer conn (FindSave user) = do
  rows <-
    SQL.query conn "SELECT map_id, x, y FROM saves WHERE user_id = ?" (SQL.Only (userIdText user))
  pure (listToMaybe [SaveData (MapId m) (Position x y) | (m, x, y) <- rows])
answer conn (FindAppearance user) = do
  rows <-
    SQL.query
      conn
      "SELECT skin_id, part_overrides, colour_overrides FROM appearances WHERE user_id = ?"
      (SQL.Only (userIdText user))
  traverse storedAppearance (listToMaybe rows)
answer conn (FindDrawing sid) = do
  rows <- SQL.query conn "SELECT renderable FROM skins WHERE id = ?" (SQL.Only sid)
  pure (SQL.fromOnly <$> listToMaybe rows)
answer conn (FindSource sid) = do
  rows <- SQL.query conn "SELECT source FROM skins WHERE id = ?" (SQL.Only sid)
  pure (SQL.fromOnly <$> listToMaybe rows)
answer conn (FindWearable sid) = do
  rows <-
    SQL.query conn "SELECT renderable FROM skins WHERE id = ? AND retired_at IS NULL" (SQL.Only sid)
  traverse
    ( \(SQL.Only raw) -> either fail pure (eitherDecodeStrict (encodeUtf8 raw) >>= parseEither readRenderable)
    )
    (listToMaybe rows)
answer conn ListSkins = do
  rows <-
    SQL.query_
      conn
      "SELECT id, name, owner_id, retired_at IS NOT NULL FROM skins ORDER BY created_at, id"
  pure
    [ SkinSummary sid name (UserId <$> owner) (retired /= (0 :: Int))
    | (sid, name, owner, retired) <- rows
    ]

-- | Storage is trusted: invalid JSON here is a bug, not a client refusal.
storedAppearance :: (Text, Text, Text) -> IO Appearance
storedAppearance (sid, parts, colours) = either fail pure $ do
  ps <- eitherDecodeStrict (encodeUtf8 parts)
  cs <- eitherDecodeStrict (encodeUtf8 colours)
  entries <-
    traverse (parseEither (withObject "colour" $ \o -> Colour <$> o .: "id" <*> o .: "hex")) cs
  pure (Appearance sid ps entries)

-- | A row of @maps@. What is in the table was put there by this code, so a
-- row that does not read is a bug, and it fails loudly (a 500).
gameMap :: (Text, Text, Int, Int, Text, Int, Int) -> IO GameMap
gameMap (mid, name, width, height, tiles, sx, sy) =
  case traverse tileNamed =<< decodeStrict (encodeUtf8 tiles) of
    Just ts -> pure (GameMap (MapId mid) name width height (Seq.fromList ts) (Position sx sy))
    Nothing -> fail ("the tiles of map " <> T.unpack mid <> " do not read")

-- | Writes what a decision said should change. One equation per change.
commit :: SQL.Connection -> Int64 -> [Change] -> IO ()
commit conn now = traverse_ write
 where
  write (PlayerPlaced user (SaveData (MapId mid) (Position x y))) =
    SQL.execute
      conn
      "INSERT INTO saves (user_id, map_id, x, y, updated_at) VALUES (?, ?, ?, ?, ?) \
      \ON CONFLICT (user_id) DO UPDATE SET \
      \map_id = excluded.map_id, x = excluded.x, y = excluded.y, updated_at = excluded.updated_at"
      (userIdText user, mid, x, y, now)
  write (SkinDrawn sid owner skin) = writeSkin False conn now sid (Just owner) skin
  write (LookChosen user resolved) =
    let look = resolvedAppearance resolved
     in SQL.execute
          conn
          "INSERT INTO appearances (user_id, skin_id, part_overrides, colour_overrides, updated_at) VALUES (?, ?, ?, ?, ?) ON CONFLICT (user_id) DO UPDATE SET skin_id = excluded.skin_id, part_overrides = excluded.part_overrides, colour_overrides = excluded.colour_overrides, updated_at = excluded.updated_at"
          ( userIdText user
          , appearanceSkin look
          , jsonText (toJSON (appearanceParts look))
          , jsonText (toJSON (map colourJson (appearanceColours look)))
          , now
          )
