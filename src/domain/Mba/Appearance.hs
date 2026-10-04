{-# LANGUAGE OverloadedStrings #-}

-- | A player's look is a recipe, never a composed picture.
--
-- These values come from trusted storage. The boundary for accepting a new
-- recipe arrives with the appearance editing slice; no write API exists yet.
--
-- @
-- defaultAppearance == Appearance "player-default" mempty []
-- @
module Mba.Appearance (
  -- * Stored recipes
  Appearance (..),
  Colour (..),
  defaultSkinId,
  defaultAppearance,
)
where

import Data.Map.Strict (Map)
import Data.Text (Text)

data Colour = Colour
  { colourId :: !Text
  , colourHex :: !Text
  }
  deriving (Show, Eq)

data Appearance = Appearance
  { appearanceSkin :: !Text
  , appearanceParts :: !(Map Text Text)
  , appearanceColours :: ![Colour]
  }
  deriving (Show, Eq)

defaultSkinId :: Text
defaultSkinId = "player-default"

defaultAppearance :: Appearance
defaultAppearance = Appearance defaultSkinId mempty []
