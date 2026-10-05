{-# LANGUAGE OverloadedStrings #-}

-- | JSON in and out: what the domain's values look like on the wire, and the
-- shape a request body must have.
--
-- The wire format belongs here, not to domain types. AppearanceReply wraps
-- a domain value so its ordered encoding needs no orphan instance.
--
-- Shape is not rules. 'saveShape' asks whether @x@ is an integer; whether a
-- player can stand there is the decision's to say (TS 版 docs/04 §層の分け方).
module Mba.Http.Json (
  -- * Out
  json,
  mapIdJson,
  positionJson,
  saveJson,
  mapJson,
  appearanceJson,
  AppearanceReply (..),

  -- * In
  saveShape,
)
where

import Data.Aeson (Object, ToJSON (..), Value (..), encode, object, (.=))
import Data.Aeson.Encoding qualified as Encoding
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Foldable (toList)
import Data.Map.Strict qualified as Map
import Data.Scientific (toBoundedInteger)
import Data.Text (Text)
import Network.HTTP.Types (Status, hContentType)
import Network.Wai (Response, responseLBS)

import Mba.Appearance (Appearance (..), Colour (..))
import Mba.Json.JavaScript (utf16Length)
import Mba.Map
import Mba.Sprite (slotName, slots)
import Mba.Sprite.Json (appearanceJson)

--------------------------------------------------------------------------------
-- Out
--------------------------------------------------------------------------------

json :: ToJSON a => Status -> a -> Response
json status body = responseLBS status [(hContentType, "application/json")] (encode body)

-- | The unchanged wardrobe displays JSON.stringify of its fetched recipe.
-- These keys therefore have visible order: skinId, parts, colours; colour
-- entries are id then hex, and overrides follow the canonical slot order.
newtype AppearanceReply = AppearanceReply Appearance

instance ToJSON AppearanceReply where
  toJSON (AppearanceReply look) = appearanceJson look
  toEncoding (AppearanceReply look) =
    Encoding.pairs
      ( "skinId" .= appearanceSkin look
          <> Encoding.pair "parts" (Encoding.pairs (foldMap part slots))
          <> Encoding.pair "colours" (Encoding.list colour (appearanceColours look))
      )
   where
    part slot =
      maybe mempty (Key.fromText (slotName slot) .=) (Map.lookup (slotName slot) (appearanceParts look))
    colour (Colour cid hex) = Encoding.pairs ("id" .= cid <> "hex" .= hex)

mapIdJson :: MapId -> Value
mapIdJson (MapId t) = String t

positionJson :: Position -> Value
positionJson (Position x y) = object ["x" .= x, "y" .= y]

saveJson :: SaveData -> Value
saveJson (SaveData m p) = object ["mapId" .= mapIdJson m, "position" .= positionJson p]

-- | Simplified: no exits yet. They come with the slice that travels through
-- them, and until then no map has any.
mapJson :: GameMap -> Value
mapJson m =
  object
    [ "id" .= mapIdJson (mapId m)
    , "name" .= mapName m
    , "width" .= mapWidth m
    , "height" .= mapHeight m
    , "tiles" .= map tileName (toList (mapTiles m))
    , "spawn" .= positionJson (mapSpawn m)
    , "exits" .= ([] :: [Value])
    ]

--------------------------------------------------------------------------------
-- In
--------------------------------------------------------------------------------

-- | The shape of a save, checked the way TS 版's zod schema checks it: field
-- by field, in the schema's order, and the first one that is wrong is where
-- the body is malformed (@Left "$.position.x"@).
saveShape :: Value -> Either Text SaveData
saveShape body = do
  o <- objectAt "$" (Just body)
  m <- mapIdAt "$.mapId" (KeyMap.lookup "mapId" o)
  p <- objectAt "$.position" (KeyMap.lookup "position" o)
  x <- intAt "$.position.x" (KeyMap.lookup "x" p)
  y <- intAt "$.position.y" (KeyMap.lookup "y" p)
  pure (SaveData (MapId m) (Position x y))

objectAt :: Text -> Maybe Value -> Either Text Object
objectAt _ (Just (Object o)) = Right o
objectAt at _ = Left at

-- | A string of 1 to 64, counted as JavaScript counts (UTF-16 units): zod's
-- @.min(1).max(64)@.
mapIdAt :: Text -> Maybe Value -> Either Text Text
mapIdAt _ (Just (String t)) | let n = utf16Length t, n >= 1, n <= 64 = Right t
mapIdAt at _ = Left at

-- | An integer, as zod 4's @.int()@ takes one: @1.0@ is, @0.5@ is not, and
-- neither is one past JavaScript's safe range.
intAt :: Text -> Maybe Value -> Either Text Int
intAt _ (Just (Number n)) | Just i <- toBoundedInteger n, abs i <= 9007199254740991 = Right i
intAt at _ = Left at
