{-# LANGUAGE OverloadedStrings #-}

-- | Every refusal, the status it is said with, and how it is written: the
-- only place a status for an error is written down.
--
-- The body is always @{ "error": { "kind": …, … } }@, as in TS 版, so a
-- client can branch on the kind. 'refusal' is a total function: a refusal
-- added without a status here does not compile (@-Werror=incomplete-patterns@).
module Mba.Http.Refusal (
  refused,
  refusal,
)
where

import Data.Aeson (object, (.=))
import Data.Aeson.Types (Pair)
import Data.Text (Text)
import Network.HTTP.Types
import Network.Wai (Response)

import Mba.Http.Json (json, mapIdJson, positionJson)
import Mba.Refusal (Refusal (..))
import Mba.Sprite (SpriteError (..), slotName)

refused :: Refusal -> Response
refused r = json status (object ["error" .= object (("kind" .= kind) : fields)])
 where
  (status, kind, fields) = refusal r

-- | 400 the request is wrong, 404 there is no such thing, 413 the body is too
-- big to read, 500 the fault is on this side.
refusal :: Refusal -> (Status, Text, [Pair])
refusal r = case r of
  BadJson -> (status400, "bad_json", [])
  InvalidSprite problem -> let (kind, fields) = spriteError problem in (status400, kind, fields)
  Malformed at -> (status400, "malformed", ["at" .= at])
  BodyTooLarge limit -> (status413, "body_too_large", ["max" .= limit])
  NotFound -> (status404, "not_found", [])
  UnknownMap m -> (status400, "unknown_map", ["mapId" .= mapIdJson m])
  WrongMap m current -> (status400, "wrong_map", ["mapId" .= mapIdJson m, "current" .= mapIdJson current])
  CannotStand m p -> (status400, "cannot_stand", ["mapId" .= mapIdJson m, "position" .= positionJson p])
  Unreachable m p -> (status400, "unreachable", ["mapId" .= mapIdJson m, "position" .= positionJson p])
  NoStartMap -> (status500, "no_start_map", [])

spriteError :: SpriteError -> (Text, [Pair])
spriteError (Shape at) = ("malformed", ["at" .= at])
spriteError (TooLarge bytes limit) = ("too_large", ["bytes" .= bytes, "max" .= limit])
spriteError (TooMany what got limit) = ("too_many", ["what" .= what, "got" .= got, "max" .= limit])
spriteError (BadCellCount slot frame got) = ("bad_cell_count", ["slot" .= slotName slot, "frame" .= frame, "got" .= got])
spriteError (BadPaletteId cid) = ("bad_palette_id", ["id" .= cid])
spriteError (DuplicatePaletteId cid) = ("duplicate_palette_id", ["id" .= cid])
spriteError (BadHex hex) = ("bad_hex", ["hex" .= hex])
spriteError (BadPaletteIndex slot frame index) = ("bad_palette_index", ["slot" .= slotName slot, "frame" .= frame, "index" .= index])
spriteError (MissingSlot slot) = ("missing_slot", ["slot" .= slotName slot])
spriteError (UnknownSkin sid) = ("unknown_skin", ["skinId" .= sid])
spriteError (UnknownColour cid) = ("unknown_colour", ["id" .= cid])
