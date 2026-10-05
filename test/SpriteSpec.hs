{-# LANGUAGE OverloadedStrings #-}

-- | Cross-language oracles for the boundary and pure drawing algorithms.
module SpriteSpec (spec) where

import Control.Monad (unless)
import Data.Aeson
import Data.Aeson.Types (parseEither)
import Data.ByteString qualified as BS
import Data.Foldable (for_)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding (encodeUtf8)
import Mba.Http.Refusal (refusal)
import Mba.Json.JavaScript (jsonBytes)
import Mba.Refusal (Refusal (InvalidSprite))
import Mba.Sprite
import Mba.Sprite.Json
import Test.Hspec

load :: IO Object
load = BS.readFile "test/fixtures/sprite.json" >>= either fail pure . eitherDecodeStrict

-- Each field is parsed with an explicit fixture schema. A missing field
-- fails setup; an empty array cannot quietly make these tests pass.
cases :: FromJSON a => Object -> Key -> IO a
cases root key = either fail pure (parseEither (.: key) root)

result :: (a -> Value) -> Either SpriteError a -> Value
result encodeValue = either rejected (\v -> object ["ok" .= True, "value" .= encodeValue v])
 where
  rejected problem =
    let (_, kind, fields) = refusal (InvalidSprite problem)
     in object ["ok" .= False, "error" .= object (("kind" .= kind) : fields)]

same :: (Eq a, Show a) => Text -> a -> a -> Expectation
same label actual expected =
  unless
    (actual == expected)
    (expectationFailure (T.unpack label <> ": expected " <> show expected <> ", got " <> show actual))

spec :: Spec
spec = beforeAll load $ do
  it "matches 83 TS skin validation cases, including ordering and UTF-16" $ \root -> do
    entries <- cases root "skinCases" :: IO [Object]
    length entries `shouldBe` 83
    for_ entries $ \entry -> do
      label <- cases entry "label"
      input <- cases entry "input"
      expected <- cases entry "result"
      same label (result skinJson (parseSkin input)) expected

  it "matches 30 TS appearance validation and normalization cases" $ \root -> do
    entries <- cases root "appearanceCases" :: IO [Object]
    length entries `shouldBe` 30
    for_ entries $ \entry -> do
      label <- cases entry "label"
      input <- cases entry "input"
      expected <- cases entry "result"
      same label (result (appearanceJson . parsedAppearance) (parseAppearance input)) expected

  it "merges all 32 TS drawings identically, across parts and animation frames" $ \root -> do
    entries <- cases root "drawings" :: IO [Object]
    length entries `shouldBe` 32
    for_ (zip [0 :: Int ..] entries) $ \(i, entry) -> do
      source <- cases entry "source"
      skin <- either (fail . show) pure (parseSkin source)
      expected <- cases entry "renderable"
      same (T.pack (show i)) (renderableJson (toRenderable skin)) expected

  it "composes 12 TS recipes and reports only colours actually painted" $ \root -> do
    entries <- cases root "compositions" :: IO [Object]
    length entries `shouldBe` 12
    for_ entries $ \entry -> do
      input <- cases entry "appearance"
      appearance <- either (fail . show) (pure . parsedAppearance) (parseAppearance input)
      rawSkins <- cases entry "skins" :: IO (Map.Map Text Value)
      skins <- traverse (either fail pure . parseEither readRenderable) rawSkins
      expected <- cases entry "result"
      expectedColours <- cases entry "colours"
      let drawing = composeAppearance appearance skins
      maybe Null renderableJson drawing `shouldBe` expected
      toJSON (maybe [] (map colourJson . coloursOf) drawing) `shouldBe` expectedColours

  it "counts 216 JSON sizes like JavaScript, including doubles and control escapes" $ \root -> do
    entries <- cases root "sizes" :: IO [Object]
    length entries `shouldBe` 216
    for_ entries $ \entry -> do
      raw <- cases entry "raw"
      expected <- cases entry "expected"
      value <- either fail pure (eitherDecodeStrict (encodeUtf8 raw))
      same raw (jsonBytes value) expected

  it "derives all four seed skins exactly as TS does" $ \_ -> do
    entries <- BS.readFile "seed/skins.json" >>= either fail pure . eitherDecodeStrict :: IO [Object]
    length entries `shouldBe` 4
    for_ entries $ \entry -> do
      sid <- cases entry "id"
      source <- cases entry "source"
      skin <- either (fail . show) pure (parseSkin source)
      expected <- cases entry "renderable"
      same sid (renderableJson (toRenderable skin)) expected
