{-# LANGUAGE DataKinds #-}
{-# LANGUAGE QualifiedDo #-}

-- | Where a player is, as far as the server is concerned.
--
-- "No save yet" and "a save that no longer makes sense" are decided once, in
-- 'loadSave'. Storing a position is a decision: it reads, and says what
-- should change. It writes nothing.
--
-- @
-- savePosition user (SaveData startMapId (Position 4 2))
--   -- reads the map and the save, then settles [PlayerPlaced user …]
-- @
module Mba.Saves (
  loadSave,
  whereIs,
  savePosition,
)
where

import Mba.Decision (Change (..), Decision, Phase (..), Query (..), UserId)
import Mba.Decision qualified as D
import Mba.Map
import Mba.Maps (startMapId)
import Mba.Refusal (Refusal (..))

-- | Where a new game starts. 'Nothing' only if there is no starter map.
startingPoint :: Decision e 'Reading 'Reading (Maybe SaveData)
startingPoint = D.do
  start <- D.ask (FindMap startMapId)
  D.pure (fmap (\m -> SaveData (mapId m) (mapSpawn m)) start)

-- | The player's position, or the starting point if they have none worth
-- keeping: no save, or one on a map that is gone, or on a tile they cannot
-- stand on any more (the map was redrawn). Asking writes nothing.
loadSave :: UserId -> Decision e 'Reading 'Reading (Maybe SaveData)
loadSave user = D.do
  saved <- D.ask (FindSave user)
  case saved of
    Nothing -> startingPoint
    Just save -> D.do
      found <- D.ask (FindMap (saveMapId save))
      if maybe False (`canStandOn` saveAt save) found
        then D.pure (Just save)
        else startingPoint

-- | @GET /api/save@.
whereIs :: UserId -> Decision Refusal 'Reading 'Reading SaveData
whereIs user = D.do
  current <- loadSave user
  D.orRefuse NoStartMap current

-- | @PUT /api/save@: stores a position, if the player could have walked
-- there from where the server last had them. Which refusal comes first is
-- part of the contract, so the checks are in TS 版's order.
savePosition :: UserId -> SaveData -> Decision Refusal 'Reading 'Settled SaveData
savePosition user wanted@(SaveData mid at) = D.do
  found <- D.ask (FindMap mid)
  m <- D.orRefuse (UnknownMap mid) found
  -- Saving cannot change which map the player is on. That takes an exit.
  current <- whereIs user
  D.require (mid == saveMapId current) (WrongMap mid (saveMapId current))
  D.require (canStandOn m at) (CannotStand mid at)
  -- Measured from where the server has the player, not from anything the
  -- request says. How many steps, or how fast, is not asked.
  D.require (canWalkTo m (saveAt current) at) (Unreachable mid at)
  D.settle [PlayerPlaced user wanted]
  D.pure wanted
