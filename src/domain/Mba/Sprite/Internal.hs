-- | Trusted constructors for the JSON boundary, not for decision authors.
module Mba.Sprite.Internal (
  Skin (..),
  Part (..),
  Frame (..),
  Slot (..),
  Rect (..),
  RenderedFrame (..),
  Renderable (..),
  ParsedAppearance (..),
  ResolvedAppearance (..),
  SpriteError (..),
) where

import Data.List.NonEmpty (NonEmpty)
import Data.Text (Text)
import Mba.Appearance (Appearance, Colour)

data Slot = Body | Shirt | Pants | Shoes | Hair
  deriving (Show, Eq, Ord, Enum, Bounded)

data Frame = Frame !Int ![(Int, Int)] deriving (Show, Eq)
data Part = Part !Slot !(NonEmpty Frame) deriving (Show, Eq)

-- | Only the boundary constructs these: all five slots, in draw order;
-- positive runs covering 256 cells, indices within the nonempty palette.
data Skin = Skin !Text !(NonEmpty Colour) ![Part] deriving (Show, Eq)

data Rect = Rect !Int !Int !Int !Int !Int deriving (Show, Eq)
data RenderedFrame = RenderedFrame !Int ![Rect] deriving (Show, Eq)
data Renderable = Renderable ![Colour] ![(Slot, [RenderedFrame])] deriving (Show, Eq)
newtype ParsedAppearance = ParsedAppearance {parsedAppearance :: Appearance} deriving (Show, Eq)
newtype ResolvedAppearance = ResolvedAppearance {resolvedAppearance :: Appearance}
  deriving (Show, Eq)

data SpriteError
  = Shape !Text
  | TooLarge !Int !Int
  | TooMany !Text !Int !Int
  | BadCellCount !Slot !Int !Double
  | BadPaletteId !Text
  | DuplicatePaletteId !Text
  | BadHex !Text
  | BadPaletteIndex !Slot !Int !Double
  | MissingSlot !Slot
  | UnknownSkin !Text
  | UnknownColour !Text
  deriving (Show, Eq)
