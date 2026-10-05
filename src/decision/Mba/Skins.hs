{-# LANGUAGE DataKinds #-}
{-# LANGUAGE QualifiedDo #-}

-- | Skin creation is a decision that may obtain an ID. A read cannot use
-- that operation, and only a validated Skin can be offered for storage.
--
-- @
-- drawSkin user skin -- new ID, one SkinDrawn change, then the ID as answer
-- @
module Mba.Skins (drawSkin, sourceById, wearableSkins) where

import Data.Text (Text)
import Mba.Decision
import Mba.Decision qualified as D
import Mba.Refusal (Refusal (..))
import Mba.Sprite (Skin)

drawSkin :: UserId -> Skin -> Creation Refusal 'Reading 'Settled Text
drawSkin user skin = D.do
  sid <- D.newId
  D.settle [SkinDrawn sid user skin]
  D.pure sid

sourceById :: Text -> Decision Refusal 'Reading 'Reading Text
sourceById sid = D.do
  source <- D.ask (FindSource sid)
  D.orRefuse NotFound source

wearableSkins :: Decision Refusal 'Reading 'Reading [SkinSummary]
wearableSkins = filter (not . summaryRetired) <$> D.ask ListSkins
