{-# LANGUAGE DataKinds #-}
{-# LANGUAGE QualifiedDo #-}

-- | Reading what a player wears, and the stored drawings the browser needs.
--
-- Asking for a look never writes a default row or repairs stored recipes.
-- Retired references are dropped only from the returned view.
--
-- @
-- Model.query (lookOf user) model -- Right defaultAppearance, until chosen
-- @
module Mba.Looks (
  lookOf,
  drawingById,
  chooseLook,
)
where

import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Text (Text)

import Mba.Appearance (Appearance (..), Colour (..), defaultAppearance)
import Mba.Decision (Change (..), Decision, Phase (..), Query (..), UserId)
import Mba.Decision qualified as D
import Mba.Refusal (Refusal (..))
import Mba.Sprite

lookOf :: UserId -> Decision Refusal 'Reading 'Reading Appearance
lookOf user = D.do
  found <- D.ask (FindAppearance user)
  let look = fromMaybe defaultAppearance found
  skins <- available (skinsNamedBy look)
  D.pure $
    if all (`Map.member` skins) (skinsNamedBy look)
      then look
      else
        if Map.notMember (appearanceSkin look) skins
          then defaultAppearance
          else
            let remaining = look{appearanceParts = Map.filter (`Map.member` skins) (appearanceParts look)}
                painted = maybe [] (map colourId . coloursOf) (composeAppearance remaining skins)
             in remaining{appearanceColours = filter ((`elem` painted) . colourId) (appearanceColours look)}

chooseLook :: UserId -> ParsedAppearance -> Decision Refusal 'Reading 'Settled Appearance
chooseLook user checked = D.do
  skins <- available (skinsNamedBy (parsedAppearance checked))
  resolved <- either (D.refuse . InvalidSprite) D.pure (resolveAppearance checked skins)
  D.settle [LookChosen user resolved]
  D.pure (resolvedAppearance resolved)

available :: [Text] -> Decision Refusal 'Reading 'Reading (Map.Map Text Renderable)
available [] = D.pure Map.empty
available (sid : rest) = D.do
  drawing <- D.ask (FindWearable sid)
  others <- available rest
  D.pure (maybe others (\d -> Map.insert sid d others) drawing)

-- | Drawings remain readable even after retirement: existing monsters
-- must still be drawable. There is no active-only filter on this query.
drawingById :: Text -> Decision Refusal 'Reading 'Reading Text
drawingById sid = D.do
  stored <- D.ask (FindDrawing sid)
  D.orRefuse NotFound stored
