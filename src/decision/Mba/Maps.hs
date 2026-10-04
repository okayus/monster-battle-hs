{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QualifiedDo #-}

-- | Maps as the game reads them, and the map every game starts on.
--
-- @
-- mapById (MapId "start")    -- answers with the starter map
-- mapById (MapId "nowhere")  -- refuses: NotFound
-- @
module Mba.Maps (
  -- * Reading
  mapById,

  -- * The starter map
  startMapId,
  starterMap,
  mapFromArt,
)
where

import Control.Monad (unless)
import Data.Maybe (listToMaybe)
import Data.Sequence qualified as Seq
import Data.Text (Text)
import Data.Text qualified as T

import Mba.Decision (Decision, Phase (..), Query (..))
import Mba.Decision qualified as D
import Mba.Map
import Mba.Refusal (Refusal (..))

-- | @GET /api/maps/:id@. A retired map is not there, as far as the game is
-- concerned: 'FindMap' does not find one.
mapById :: MapId -> Decision Refusal 'Reading 'Reading GameMap
mapById mid = D.do
  found <- D.ask (FindMap mid)
  D.orRefuse NotFound found

-- | The map a player with no save starts on.
startMapId :: MapId
startMapId = MapId "start"

-- | Seeded at boot when it is missing, and never overwritten: once the admin
-- screen has edited it, the row is the truth and this is where it began.
starterMap :: Either Text GameMap
starterMap =
  mapFromArt
    startMapId
    "はじまりの草原"
    [ "TTTTTTTTTTTTTTTT"
    , "T@...gggg..wwwwT"
    , "T.TT.gggg..wwwwT"
    , "T.TT.......wwwwT"
    , "T......TT......T"
    , "Tggg...TT...gggT"
    , "Tggg........gggT"
    , "T....www.......T"
    , "T.TT.www..TTT..T"
    , "T.TT......TTT..T"
    , "T..............T"
    , "TTTTTTTTTTTTTTTT"
    ]

-- | Drawn rows to a map: @.@ path, @g@ grass, @T@ tree, @w@ water, and one
-- @\@@ where a new player starts, on a path. As text so that a change to a
-- map reads in a diff.
mapFromArt :: MapId -> Text -> [Text] -> Either Text GameMap
mapFromArt mid name rows = do
  let width = maybe 0 T.length (listToMaybe rows)
  unless (all ((== width) . T.length) rows) (Left "rows of different lengths")
  tiles <- traverse tile (concatMap T.unpack rows)
  case [Position x y | (y, row) <- zip [0 ..] rows, (x, '@') <- zip [0 ..] (T.unpack row)] of
    [spawn] -> Right (GameMap mid name width (length rows) (Seq.fromList tiles) spawn)
    spawns -> Left ("one spawn wanted, found " <> T.pack (show (length spawns)))
 where
  tile c = case c of
    '.' -> Right Path
    '@' -> Right Path
    'g' -> Right Grass
    'T' -> Right Tree
    'w' -> Right Water
    _ -> Left ("no tile is drawn as " <> T.singleton c)
