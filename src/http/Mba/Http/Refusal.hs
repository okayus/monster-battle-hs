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

refused :: Refusal -> Response
refused r = json status (object ["error" .= object (("kind" .= kind) : fields)])
 where
  (status, kind, fields) = refusal r

-- | 400 the request is wrong, 404 there is no such thing, 413 the body is too
-- big to read, 500 the fault is on this side.
refusal :: Refusal -> (Status, Text, [Pair])
refusal r = case r of
  BadJson -> (status400, "bad_json", [])
  Malformed at -> (status400, "malformed", ["at" .= at])
  BodyTooLarge limit -> (status413, "body_too_large", ["max" .= limit])
  NotFound -> (status404, "not_found", [])
  UnknownMap m -> (status400, "unknown_map", ["mapId" .= mapIdJson m])
  WrongMap m current -> (status400, "wrong_map", ["mapId" .= mapIdJson m, "current" .= mapIdJson current])
  CannotStand m p -> (status400, "cannot_stand", ["mapId" .= mapIdJson m, "position" .= positionJson p])
  Unreachable m p -> (status400, "unreachable", ["mapId" .= mapIdJson m, "position" .= positionJson p])
  NoStartMap -> (status500, "no_start_map", [])
