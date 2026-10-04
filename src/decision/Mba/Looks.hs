{-# LANGUAGE DataKinds #-}
{-# LANGUAGE QualifiedDo #-}

-- | Reading what a player wears, and the stored drawings the browser needs.
--
-- Asking for a look never writes a default row. Retired-part recovery comes
-- with retirement; at this stage all stored recipes name available skins.
--
-- @
-- Model.query (lookOf user) model -- Right defaultAppearance, until chosen
-- @
module Mba.Looks (
  lookOf,
  drawingById,
)
where

import Data.Maybe (fromMaybe)
import Data.Text (Text)

import Mba.Appearance (Appearance, defaultAppearance)
import Mba.Decision (Decision, Phase (..), Query (..), UserId)
import Mba.Decision qualified as D
import Mba.Refusal (Refusal (..))

lookOf :: UserId -> Decision Refusal 'Reading 'Reading Appearance
lookOf user = fromMaybe defaultAppearance <$> D.ask (FindAppearance user)

-- | Drawings remain readable even after retirement: existing monsters
-- must still be drawable. There is no active-only filter on this query.
drawingById :: Text -> Decision Refusal 'Reading 'Reading Text
drawingById sid = D.do
  stored <- D.ask (FindDrawing sid)
  D.orRefuse NotFound stored
