-- | Every reason the API says no.
--
-- A decision refuses with one of these and knows nothing of HTTP. The status
-- each one is said with is written down in one place, "Mba.Http.Refusal".
--
-- Simplified: one type for every refusal. TS 版 gives each decision its own
-- union of the kinds it can refuse with, so a decision's type says which
-- ones those are; here a decision's type says only that it can refuse.
module Mba.Refusal (Refusal (..)) where

import Data.Text (Text)

import Mba.Map (MapId, Position)
import Mba.Sprite (SpriteError)

data Refusal
  = -- | The body is not JSON.
    BadJson
  | InvalidSprite !SpriteError
  | -- | The body is JSON, but not of the shape asked for: where, as @$.position.x@.
    Malformed !Text
  | -- | The body is longer than this many bytes. Refused before it is read.
    BodyTooLarge !Int
  | NotFound
  | UnknownMap !MapId
  | -- | The map asked for, and the one the player is on.
    WrongMap !MapId !MapId
  | CannotStand !MapId !Position
  | Unreachable !MapId !Position
  | -- | There is no starter map. The fault is on this side.
    NoStartMap
  deriving (Show, Eq)
