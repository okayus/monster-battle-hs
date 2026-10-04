{-# LANGUAGE OverloadedStrings #-}

-- | JSON in and out: what the domain's values look like on the wire, and the
-- shape a request body must have.
--
-- Plain functions, not 'ToJSON' instances: the wire format is the HTTP
-- side's business, and instances here for the domain's types would be
-- orphans.
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

  -- * In
  saveShape,
)
where

import Data.Aeson (Object, Value (..), encode, object, (.=))
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Char (ord)
import Data.Foldable (toList)
import Data.Scientific (toBoundedInteger)
import Data.Text (Text)
import Data.Text qualified as T
import Network.HTTP.Types (Status, hContentType)
import Network.Wai (Response, responseLBS)

import Mba.Appearance
import Mba.Map

--------------------------------------------------------------------------------
-- Out
--------------------------------------------------------------------------------

json :: Status -> Value -> Response
json status body = responseLBS status [(hContentType, "application/json")] (encode body)

mapIdJson :: MapId -> Value
mapIdJson (MapId t) = String t

positionJson :: Position -> Value
positionJson (Position x y) = object ["x" .= x, "y" .= y]

saveJson :: SaveData -> Value
saveJson (SaveData m p) = object ["mapId" .= mapIdJson m, "position" .= positionJson p]

appearanceJson :: Appearance -> Value
appearanceJson look =
  object
    [ "skinId" .= appearanceSkin look
    , "parts" .= appearanceParts look
    , "colours" .= map colourJson (appearanceColours look)
    ]
 where
  colourJson (Colour cid hex) = object ["id" .= cid, "hex" .= hex]

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

utf16Length :: Text -> Int
utf16Length = T.foldl' (\n c -> n + if ord c > 0xFFFF then 2 else 1) 0
