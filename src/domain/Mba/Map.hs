{-# LANGUAGE OverloadedStrings #-}

-- | Maps, and walking on them: the rules the server shares with the browser.
--
-- The map half of TS 版's @packages/core@. Nothing here does I/O: this
-- library depends on @base@, @containers@ and @text@, and the build keeps it
-- that way.
--
-- Where TS 版 checks at run time, the types answer here. A tile is a sum
-- type, so whether it can be walked on is a total function. A coordinate is
-- an 'Int', so it is never @NaN@ or @0.5@: those were refused at the HTTP
-- edge, before anything here is asked.
--
-- @
-- canStandOn starter (Position 1 1)                   -- True: where a new game starts
-- canStandOn starter (Position 0 0)                   -- False: a tree
-- canWalkTo  starter (Position 1 1) (Position 14 10)  -- True: far, but there is a way
-- @
module Mba.Map (
  -- * Tiles
  Tile (..),
  tileName,
  tileNamed,
  isWalkable,

  -- * Maps
  MapId (..),
  Position (..),
  GameMap (..),
  SaveData (..),
  tileAt,
  canStandOn,

  -- * Walking
  Direction (..),
  step,
  canWalkTo,
)
where

import Data.Sequence (Seq)
import Data.Sequence qualified as Seq
import Data.Set qualified as Set
import Data.Text (Text)

--------------------------------------------------------------------------------
-- Tiles
--------------------------------------------------------------------------------

-- | What a map is made of. What is stored is the name ('tileName').
data Tile = Path | Grass | Tree | Water
  deriving (Show, Eq, Ord, Enum, Bounded)

tileName :: Tile -> Text
tileName Path = "path"
tileName Grass = "grass"
tileName Tree = "tree"
tileName Water = "water"

-- | The tile a stored name stands for.
tileNamed :: Text -> Maybe Tile
tileNamed name = lookup name [(tileName t, t) | t <- [minBound .. maxBound]]

-- | Derived from the tile, never stored. A total function: a new kind of
-- tile does not compile until it says whether it can be walked on.
isWalkable :: Tile -> Bool
isWalkable Path = True
isWalkable Grass = True
isWalkable Tree = False
isWalkable Water = False

--------------------------------------------------------------------------------
-- Maps
--------------------------------------------------------------------------------

newtype MapId = MapId Text
  deriving (Show, Eq, Ord)

-- | x across, y down, like rows on a screen.
data Position = Position !Int !Int
  deriving (Show, Eq, Ord)

-- | A map. The tiles are flat and row-major — the tile at (x, y) is at
-- @y * width + x@ — so a map whose rows differ in length cannot be written.
data GameMap = GameMap
  { mapId :: !MapId
  , mapName :: !Text
  , mapWidth :: !Int
  , mapHeight :: !Int
  , mapTiles :: !(Seq Tile)
  , mapSpawn :: !Position
  -- ^ Where a player with no save starts. Always a tile that can be stood on.
  }
  deriving (Show, Eq)

-- | Where a player is: what @/api/save@ reads and writes.
data SaveData = SaveData
  { saveMapId :: !MapId
  , saveAt :: !Position
  }
  deriving (Show, Eq)

-- | The tile at a position, or 'Nothing' off the map. The bounds check keeps
-- the flat tiles honest: without it, @x = width@ would read the first tile of
-- the next row.
tileAt :: GameMap -> Position -> Maybe Tile
tileAt m (Position x y)
  | x < 0 || y < 0 || x >= mapWidth m || y >= mapHeight m = Nothing
  | otherwise = Seq.lookup (y * mapWidth m + x) (mapTiles m)

-- | On the map, and on a tile that can be walked on.
canStandOn :: GameMap -> Position -> Bool
canStandOn m at = maybe False isWalkable (tileAt m at)

--------------------------------------------------------------------------------
-- Walking
--------------------------------------------------------------------------------

-- | TS 版's up, down, left and right. Not named so here: 'Left' and 'Right'
-- are 'Either's.
data Direction = North | South | West | East
  deriving (Show, Eq, Enum, Bounded)

-- | One step. Where the way is blocked, the player stays where they were.
step :: GameMap -> Direction -> Position -> Position
step m dir from@(Position x y) = if canStandOn m to then to else from
 where
  to = case dir of
    North -> Position x (y - 1)
    South -> Position x (y + 1)
    West -> Position (x - 1) y
    East -> Position (x + 1) y

-- | Whether some chain of 'step's leads from one position to the other. Not
-- how many steps, nor how fast: only whether there is a way. A flood fill;
-- a map has at most 32 × 32 tiles.
canWalkTo :: GameMap -> Position -> Position -> Bool
canWalkTo m from to = canStandOn m from && canStandOn m to && go (Set.singleton from) [from]
 where
  go _ [] = False
  go seen (here : rest)
    | here == to = True
    | otherwise =
        let next = [p | d <- [minBound .. maxBound], let p = step m d here, Set.notMember p seen]
         in go (foldr Set.insert seen next) (next <> rest)
