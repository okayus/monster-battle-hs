{-# LANGUAGE OverloadedStrings #-}

-- | The skin and appearance trust boundaries, in TS validation order.
-- Unknown fields contribute to the size cap, then disappear from the
-- rebuilt value. Only this module makes validated Skin/ParsedAppearance.
--
-- @
-- parseSkin body >>= pure . renderableJson . toRenderable
-- @
module Mba.Sprite.Json (
  parseSkin,
  parseAppearance,
  skinJson,
  renderableJson,
  appearanceJson,
  colourJson,
  readRenderable,
  jsonText,
) where

import Control.Monad (foldM, unless, when)
import Data.Aeson (Object, Value (..), encode, object, withObject, (.:), (.=))
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Aeson.Types (Parser)
import Data.ByteString.Lazy qualified as LBS
import Data.Char (isAsciiLower, isDigit, isHexDigit)
import Data.Foldable (toList)
import Data.List.NonEmpty qualified as NE
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Scientific (toRealFloat)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding (decodeUtf8)
import Mba.Appearance
import Mba.Json.JavaScript (jsonBytes, utf16Length)
import Mba.Sprite
import Mba.Sprite.Internal (Frame (..), ParsedAppearance (..), Part (..), Skin (..))

jsonText :: Value -> Text
jsonText = decodeUtf8 . LBS.toStrict . encode

parseSkin :: Value -> Either SpriteError Skin
parseSkin input = do
  let bytes = jsonBytes input
  when (bytes > 65536) (Left (TooLarge bytes 65536))
  root <- objectAt "$" input
  version <- intAt "$.formatVersion" (field "formatVersion" root)
  unless (version == 1) (Left (Shape "$.formatVersion"))
  name <- stringAt "$.name" (field "name" root)
  when (T.null name) (Left (Shape "$.name"))
  cap "name" 64 (utf16Length name)
  colours <- paletteAt "$.palette" "palette" True (field "palette" root)
  palette <- maybe (Left (Shape "$.palette")) Right (NE.nonEmpty colours)
  rawParts <- arrayAt "$.parts" (field "parts" root)
  cap "parts" 5 (length rawParts)
  bySlot <- foldM (parsePart (length colours)) Map.empty (zip [0 ..] rawParts)
  parts <- traverse (\slot -> maybe (Left (MissingSlot slot)) Right (Map.lookup slot bySlot)) slots
  pure (Skin name palette parts)

parsePart :: Int -> Map.Map Slot Part -> (Int, Value) -> Either SpriteError (Map.Map Slot Part)
parsePart paletteSize found (i, raw) = do
  let at = indexed "$.parts" i
  part <- objectAt at raw
  name <- stringAt (at <> ".slot") (field "slot" part)
  slot <- maybe (Left (Shape (at <> ".slot"))) Right (slotNamed name)
  when (Map.member slot found) (Left (Shape (at <> ".slot")))
  frames <- arrayAt (at <> ".frames") (field "frames" part)
  when (null frames) (Left (Shape (at <> ".frames")))
  cap (at <> ".frames") 8 (length frames)
  parsed <- traverse (parseFrame slot paletteSize (at <> ".frames")) (zip [0 ..] frames)
  nonempty <- maybe (Left (Shape (at <> ".frames"))) Right (NE.nonEmpty parsed)
  pure (Map.insert slot (Part slot nonempty) found)

parseFrame :: Slot -> Int -> Text -> (Int, Value) -> Either SpriteError Frame
parseFrame slot paletteSize path (f, raw) = do
  let at = indexed path f
  frame <- objectAt at raw
  duration <- intAt (at <> ".durationMs") (field "durationMs" frame)
  unless (duration > 0 && duration <= 10000) (Left (Shape (at <> ".durationMs")))
  cells <- arrayAt (at <> ".cells") (field "cells" frame)
  runs <- traverse (parseRun (at <> ".cells")) (zip [0 ..] cells)
  -- Sum in Double, in input order, just as JavaScript does; huge positive
  -- lengths are refused before converting them to bounded internal Ints.
  let total = foldl (\n (_, count) -> n + count) 0 runs
  unless (total == 256) (Left (BadCellCount slot f total))
  pure (Frame (round duration) [(round index, round count) | (index, count) <- runs])
 where
  parseRun at (c, rawRun) = do
    let here = indexed at c
    pair <- arrayAt here rawRun
    case pair of
      [indexValue, countValue] -> do
        index <- intAt (here <> "[0]") indexValue
        when (index < 0) (Left (Shape (here <> "[0]")))
        when (index > fromIntegral paletteSize) (Left (BadPaletteIndex slot f index))
        count <- intAt (here <> "[1]") countValue
        when (count <= 0) (Left (Shape (here <> "[1]")))
        pure (index, count)
      _ -> Left (Shape here)

parseAppearance :: Value -> Either SpriteError ParsedAppearance
parseAppearance input = do
  root <- objectAt "$" input
  sid <- skinIdAt "$.skinId" (field "skinId" root)
  rawParts <- objectAt "$.parts" (field "parts" root)
  unless
    (all (\key -> Key.toText key `elem` map slotName slots) (KeyMap.keys rawParts))
    (Left (Shape "$.parts"))
  parts <- foldM (part sid rawParts) Map.empty slots
  colours <- paletteAt "$.colours" "colours" False (field "colours" root)
  pure (ParsedAppearance (Appearance sid parts colours))
 where
  part sid raw found slot = case KeyMap.lookup (Key.fromText (slotName slot)) raw of
    Nothing -> Right found
    Just value -> do
      from <- skinIdAt ("$.parts." <> slotName slot) value
      pure (if from == sid then found else Map.insert (slotName slot) from found)

paletteAt :: Text -> Text -> Bool -> Value -> Either SpriteError [Colour]
paletteAt path what nonempty raw = do
  entries <- arrayAt path raw
  when (nonempty && null entries) (Left (Shape path))
  cap what 32 (length entries)
  reverse . snd <$> foldM entry (Set.empty, []) (zip [0 ..] entries)
 where
  entry (seen, found) (i, value) = do
    let at = indexed path i
    fields <- objectAt at value
    cid <- stringAt (at <> ".id") (field "id" fields)
    unless (not (T.null cid) && T.length cid <= 32 && T.all paletteChar cid) (Left (BadPaletteId cid))
    when (Set.member cid seen) (Left (DuplicatePaletteId cid))
    hex <- stringAt (at <> ".hex") (field "hex" fields)
    unless
      (T.length hex == 7 && T.take 1 hex == "#" && T.all isHexDigit (T.drop 1 hex))
      (Left (BadHex hex))
    pure (Set.insert cid seen, Colour cid hex : found)
  paletteChar c = isAsciiLower c || isDigit c || c == '-'

skinIdAt :: Text -> Value -> Either SpriteError Text
skinIdAt at value = do
  sid <- stringAt at value
  if T.null sid || utf16Length sid > 64 then Left (Shape at) else Right sid

cap :: Text -> Int -> Int -> Either SpriteError ()
cap what limit got = when (got > limit) (Left (TooMany what got limit))
indexed :: Text -> Int -> Text
indexed path i = path <> "[" <> T.pack (show i) <> "]"
field :: Key.Key -> Object -> Value
field key = fromMaybe Null . KeyMap.lookup key
objectAt :: Text -> Value -> Either SpriteError Object
objectAt _ (Object o) = Right o
objectAt at _ = Left (Shape at)
arrayAt :: Text -> Value -> Either SpriteError [Value]
arrayAt _ (Array a) = Right (toList a)
arrayAt at _ = Left (Shape at)
stringAt :: Text -> Value -> Either SpriteError Text
stringAt _ (String s) = Right s
stringAt at _ = Left (Shape at)
intAt :: Text -> Value -> Either SpriteError Double
intAt at (Number n)
  | let d = toRealFloat n, not (isInfinite d), fromInteger (truncate d) == d = Right d
  | otherwise = Left (Shape at)
intAt at _ = Left (Shape at)

colourJson :: Colour -> Value
colourJson (Colour cid hex) = object ["id" .= cid, "hex" .= hex]
appearanceJson :: Appearance -> Value
appearanceJson look =
  object
    [ "skinId" .= appearanceSkin look
    , "parts" .= appearanceParts look
    , "colours" .= map colourJson (appearanceColours look)
    ]
skinJson :: Skin -> Value
skinJson skin =
  object
    [ "formatVersion" .= (1 :: Int)
    , "name" .= skinName skin
    , "palette" .= map colourJson (skinPalette skin)
    , "parts"
        .= [ object ["slot" .= slotName (partSlot p), "frames" .= map frame (partFrames p)] | p <- skinParts skin
           ]
    ]
 where
  frame f = object ["durationMs" .= frameDuration f, "cells" .= [[i, n] | (i, n) <- frameCells f]]
renderableJson :: Renderable -> Value
renderableJson (Renderable palette parts) =
  object
    [ "formatVersion" .= (1 :: Int)
    , "palette" .= map colourJson palette
    , "parts"
        .= [object ["slot" .= slotName slot, "frames" .= map frame frames] | (slot, frames) <- parts]
    ]
 where
  frame (RenderedFrame duration rects) = object ["durationMs" .= duration, "rects" .= [[x, y, w, h, i] | Rect x y w h i <- rects]]

-- | Decode a drawing already derived by us. No user-facing revalidation.
readRenderable :: Value -> Parser Renderable
readRenderable = withObject "renderable" $ \o -> do
  palette <-
    o .: "palette" >>= traverse (withObject "colour" $ \c -> Colour <$> c .: "id" <*> c .: "hex")
  parts <-
    o .: "parts"
      >>= traverse
        ( withObject "part" $ \p -> do
            name <- p .: "slot"
            slot <- maybe (fail "unknown stored slot") pure (slotNamed name)
            frames <-
              p .: "frames"
                >>= traverse
                  ( withObject "frame" $ \f -> do
                      duration <- f .: "durationMs"
                      rects <- f .: "rects" >>= traverse readRect
                      pure (RenderedFrame duration rects)
                  )
            pure (slot, frames)
        )
  pure (Renderable palette parts)

readRect :: [Int] -> Parser Rect
readRect [x, y, w, h, i] = pure (Rect x y w h i)
readRect _ = fail "invalid stored rectangle"
