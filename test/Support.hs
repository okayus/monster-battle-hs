{-# LANGUAGE OverloadedStrings #-}

-- | What the specs share: maps to walk on, a model, a fresh database.
module Support (
  -- * Maps
  starter,
  firstTile,
  rooms,
  roomsId,

  -- * The model and the database
  fresh,
  withDb,

  -- * Requests
  aSave,
  onTheStarterMap,
)
where

import Control.Exception (bracket)
import Data.Map.Strict qualified as Map
import Data.Sequence qualified as Seq
import Data.Text qualified as T
import Test.QuickCheck (Gen, choose, elements)

import Mba.Auth (localUser)
import Mba.Map
import Mba.Maps (mapFromArt, startMapId, starterMap)
import Mba.Model (Model (..))
import Mba.Sqlite (Db)
import Mba.Sqlite qualified as Sqlite

starter :: GameMap
starter = either (error . T.unpack) id starterMap

-- | The first tile of a kind on the starter map, in reading order.
firstTile :: Tile -> Position
firstTile t = case Seq.elemIndexL t (mapTiles starter) of
  Just i -> Position (i `mod` mapWidth starter) (i `div` mapWidth starter)
  Nothing -> error ("the starter map has no " <> show t)

-- | Two rooms with a wall of trees between them and no gap in it (TS 版's
-- save.test.ts):
--
-- @
--   01234
-- 0 .T..g    the left room: (0,0) and (0,1)
-- 1 \@T...    the right room: everything past the trees, with grass at (4,0)
-- @
rooms :: GameMap
rooms = either (error . T.unpack) id (mapFromArt roomsId "ふたつの部屋" [".T..g", "@T..."])

roomsId :: MapId
roomsId = MapId "rooms"

-- | The starter map, and nobody's save.
fresh :: Model
fresh = Model (Map.singleton startMapId starter) Map.empty Map.empty Map.empty

-- | A database brought up the way a boot does it — the migration files, then
-- the seed — so those are under test too. The clock is stopped.
withDb :: (Db -> Int -> IO a) -> IO a
withDb act = bracket (Sqlite.open (pure 1700000000) ":memory:") Sqlite.close $ \db -> do
  applied <- Sqlite.migrate db "migrations" 1700000000000
  Sqlite.seed db localUser 1700000000
  act db applied

-- | A save on one of these maps, at a position in these ranges.
aSave :: [MapId] -> (Int, Int) -> (Int, Int) -> Gen SaveData
aSave maps xs ys = SaveData <$> elements maps <*> (Position <$> choose xs <*> choose ys)

-- | Mostly on the starter map, now and then on one that is not there.
onTheStarterMap :: Gen SaveData
onTheStarterMap = aSave [startMapId, startMapId, startMapId, MapId "nowhere"] (-1, 16) (-1, 12)
