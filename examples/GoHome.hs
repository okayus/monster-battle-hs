{-# LANGUAGE DataKinds #-}
{-# LANGUAGE QualifiedDo #-}

-- | A request that says what should be: "the player is at the start".
--
-- When it already holds, there is nothing to change, and the decision says
-- so with an empty list. Run it twice and the second run changes nothing:
-- @u ∘ u = u@. (Compare @PUT /api/save@, which TS 版 writes even when the
-- player has not moved: the state after two is the same, but the second
-- list is not empty.)
--
-- The battle slice will have the real use for this: a lost battle puts the
-- player back at the start.
module GoHome (goHome) where

import Mba.Decision (Change (..), Decision, Phase (..), Query (..), UserId)
import Mba.Decision qualified as D
import Mba.Map
import Mba.Maps (startMapId)
import Mba.Refusal (Refusal (..))
import Mba.Saves (whereIs)

goHome :: UserId -> Decision Refusal 'Reading 'Settled SaveData
goHome user = D.do
  current <- whereIs user
  start <- D.ask (FindMap startMapId)
  home <- D.orRefuse NoStartMap (fmap (SaveData startMapId . mapSpawn) start)
  if current == home
    then D.settle []
    else D.settle [PlayerPlaced user home]
  D.pure home
