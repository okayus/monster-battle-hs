{-# LANGUAGE OverloadedStrings #-}

-- | Golden cases produced by the unchanged TypeScript movement rules.
module FixtureSpec (spec) where

import Data.Aeson
import Data.Aeson.Types (Parser, parseEither)
import Data.ByteString qualified as BS
import Data.Foldable (for_)
import Data.Sequence qualified as Seq
import Data.Text (Text)
import Test.Hspec

import Mba.Map

data Fixture = Fixture GameMap [(Position, Direction, Position)] [(Position, Position, Bool)]

position :: Value -> Parser Position
position = withObject "position" $ \o -> Position <$> o .: "x" <*> o .: "y"

fixture :: Value -> Parser Fixture
fixture = withObject "fixture" $ \o -> do
  m <-
    o .: "map"
      >>= withObject
        "map"
        ( \v -> do
            w <- v .: "width"
            h <- v .: "height"
            names <- v .: "tiles"
            ts <- traverse (maybe (fail "unknown tile") pure . tileNamed) names
            pure (GameMap (MapId "fixture") "fixture" w h (Seq.fromList ts) (Position 0 0))
        )
  steps <-
    o .: "steps"
      >>= traverse
        ( withObject "step" $ \v -> do
            from <- v .: "from" >>= position
            dir <- v .: "direction" >>= direction
            to <- v .: "to" >>= position
            pure (from, dir, to)
        )
  walks <-
    o .: "walks"
      >>= traverse
        ( withObject "walk" $ \v -> do
            from <- v .: "from" >>= position
            to <- v .: "to" >>= position
            reachable <- v .: "reachable"
            pure (from, to, reachable)
        )
  pure (Fixture m steps walks)
 where
  direction :: Text -> Parser Direction
  direction name =
    maybe
      (fail "unknown direction")
      pure
      (lookup name [("up", North), ("down", South), ("left", West), ("right", East)])

spec :: Spec
spec = it "matches all 1,738 TS steps and reachability cases, including edges and separate rooms" $ do
  bytes <- BS.readFile "test/fixtures/movement.json"
  cases <- either fail pure (eitherDecodeStrict bytes >>= traverse (parseEither fixture))
  sum [length steps + length walks | Fixture _ steps walks <- cases] `shouldBe` 1738
  for_ cases $ \(Fixture m steps walks) -> do
    for_ steps $ \(from, dir, to) -> step m dir from `shouldBe` to
    for_ walks $ \(from, to, reachable) -> canWalkTo m from to `shouldBe` reachable
