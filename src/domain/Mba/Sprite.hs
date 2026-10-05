{-# LANGUAGE OverloadedStrings #-}

-- | Validated skins and their pure drawing rules. Construction belongs to
-- the boundary; renderers never repeat its checks.
--
-- @
-- toRenderable skin -- merge cells once, when storing the drawing
-- @
module Mba.Sprite (
  Skin,
  skinName,
  skinPalette,
  skinParts,
  Part,
  partSlot,
  partFrames,
  Frame,
  frameDuration,
  frameCells,
  Slot (..),
  slots,
  slotName,
  slotNamed,
  Rect (..),
  RenderedFrame (..),
  Renderable (..),
  toRenderable,
  composeAppearance,
  coloursOf,
  skinsNamedBy,
  ParsedAppearance,
  parsedAppearance,
  SpriteError (..),
  ResolvedAppearance,
  resolvedAppearance,
  resolveAppearance,
) where

import Data.Foldable (toList, traverse_)
import Data.List (foldl', nub)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Sequence qualified as Seq
import Data.Set qualified as Set
import Data.Text (Text)
import Mba.Appearance
import Mba.Sprite.Internal

skinName :: Skin -> Text
skinName (Skin name _ _) = name
skinPalette :: Skin -> [Colour]
skinPalette (Skin _ palette _) = toList palette
skinParts :: Skin -> [Part]
skinParts (Skin _ _ parts) = parts
partSlot :: Part -> Slot
partSlot (Part slot _) = slot
partFrames :: Part -> [Frame]
partFrames (Part _ frames) = toList frames
frameDuration :: Frame -> Int
frameDuration (Frame duration _) = duration
frameCells :: Frame -> [(Int, Int)]
frameCells (Frame _ cells) = cells

slots :: [Slot]
slots = [minBound .. maxBound]
slotName :: Slot -> Text
slotName Body = "body"
slotName Shirt = "shirt"
slotName Pants = "pants"
slotName Shoes = "shoes"
slotName Hair = "hair"
slotNamed :: Text -> Maybe Slot
slotNamed name = lookup name [(slotName s, s) | s <- slots]

toRenderable :: Skin -> Renderable
toRenderable skin =
  Renderable
    (skinPalette skin)
    [(partSlot p, map render (partFrames p)) | p <- skinParts skin]
 where
  render frame = RenderedFrame (frameDuration frame) (rectangles (frameCells frame))

-- | Greedy row-first merging, exactly as the browser does it. The validated
-- runs make a 16×16 grid; every nontransparent cell is taken once.
rectangles :: [(Int, Int)] -> [Rect]
rectangles runs = reverse (snd (foldl' visit (Set.empty, []) [0 .. 255]))
 where
  grid = Seq.fromList (concatMap (\(index, count) -> replicate count index) runs)
  cell = Seq.index grid
  visit state@(taken, done) i
    | Set.member i taken || cell i == 0 = state
    | otherwise =
        let x = i `mod` 16
            y = i `div` 16
            index = cell i
            free at = Set.notMember at taken && cell at == index
            w = length (takeWhile (\dx -> free (i + dx)) [0 .. 15 - x])
            h = length (takeWhile (\dy -> all (\dx -> free (i + dy * 16 + dx)) [0 .. w - 1]) [0 .. 15 - y])
            used = [i + dy * 16 + dx | dy <- [0 .. h - 1], dx <- [0 .. w - 1]]
         in (foldr Set.insert taken used, Rect x y w h index : done)

skinsNamedBy :: Appearance -> [Text]
skinsNamedBy look =
  nub
    ( appearanceSkin look
        : [sid | slot <- slots, Just sid <- [Map.lookup (slotName slot) (appearanceParts look)]]
    )

composeAppearance :: Appearance -> Map Text Renderable -> Maybe Renderable
composeAppearance look skins = do
  worn <- Map.lookup (appearanceSkin look) skins
  let choose slot =
        let sid = Map.findWithDefault (appearanceSkin look) (slotName slot) (appearanceParts look)
         in case Map.lookup sid skins of
              Just drawing -> (sid, drawing)
              Nothing -> (appearanceSkin look, worn)
      add (palette, parts, offsets) slot =
        let (sid, Renderable colours source) = choose slot
         in case lookup slot source of
              Nothing -> (palette, parts, offsets)
              Just frames ->
                let offset = Map.findWithDefault (length palette) sid offsets
                    next = if Map.member sid offsets then palette else palette <> colours
                    shift (RenderedFrame duration rects) =
                      RenderedFrame
                        duration
                        [Rect x y w h (i + offset) | Rect x y w h i <- rects]
                 in (next, parts <> [(slot, map shift frames)], Map.insert sid offset offsets)
      (combinedPalette, combinedParts, _) = foldl' add ([], [], Map.empty) slots
  pure (Renderable combinedPalette combinedParts)

coloursOf :: Renderable -> [Colour]
coloursOf (Renderable palette parts) = reverse (snd (foldl' collect (Set.empty, []) (zip [1 ..] palette)))
 where
  used = Set.fromList [i | (_, frames) <- parts, RenderedFrame _ rects <- frames, Rect _ _ _ _ i <- rects]
  collect state@(seen, found) (i, colour)
    | Set.notMember i used || Set.member (colourId colour) seen = state
    | otherwise = (Set.insert (colourId colour) seen, colour : found)

-- | A recipe whose skin references and painted colours have been resolved.
-- Its constructor is hidden, so a parsed recipe alone cannot be committed.
resolveAppearance ::
  ParsedAppearance -> Map Text Renderable -> Either SpriteError ResolvedAppearance
resolveAppearance checked skins = do
  let look = parsedAppearance checked
  traverse_
    (\sid -> if Map.member sid skins then Right () else Left (UnknownSkin sid))
    (skinsNamedBy look)
  drawing <- maybe (Left (UnknownSkin (appearanceSkin look))) Right (composeAppearance look skins)
  let painted = Set.fromList (map colourId (coloursOf drawing))
  traverse_
    ( \colour ->
        if Set.member (colourId colour) painted then Right () else Left (UnknownColour (colourId colour))
    )
    (appearanceColours look)
  pure (ResolvedAppearance look)
