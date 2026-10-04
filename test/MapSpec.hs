-- | The rules of maps and walking. Pure: no model, no database.
module MapSpec (spec) where

import Test.Hspec

import Mba.Map
import Support

spec :: Spec
spec = do
  describe "tileAt" $
    it "is Nothing off the map; x = width does not wrap round to the next row" $ do
      tileAt starter (Position 15 1) `shouldBe` Just Tree
      tileAt starter (Position 16 1) `shouldBe` Nothing
      tileAt starter (Position (-1) 1) `shouldBe` Nothing
      tileAt starter (Position 1 12) `shouldBe` Nothing

  describe "canStandOn" $
    it "a path and grass; not a tree, water, or off the map" $
      map
        (canStandOn starter)
        [Position 1 1, firstTile Grass, firstTile Tree, firstTile Water, Position 16 1]
        `shouldBe` [True, True, False, False, False]

  describe "step" $
    it "moves where the way is open, and stays where it is blocked" $ do
      step starter East (Position 1 1) `shouldBe` Position 2 1
      step starter North (Position 1 1) `shouldBe` Position 1 1 -- the border of trees
      step starter East (Position 10 3) `shouldBe` Position 10 3 -- water
  describe "canWalkTo" $ do
    it "the far corner of the map, in one go: how long the walk is is not asked" $
      canWalkTo starter (Position 1 1) (Position 14 10) `shouldBe` True
    it "not past a wall" $
      canWalkTo rooms (Position 0 1) (Position 4 0) `shouldBe` False
    it "but the same tile from the other side of it" $
      canWalkTo rooms (Position 2 1) (Position 4 0) `shouldBe` True
    it "not from, nor to, a tile nobody can stand on" $ do
      canWalkTo rooms (Position 1 0) (Position 2 0) `shouldBe` False
      canWalkTo rooms (Position 2 0) (Position 1 0) `shouldBe` False
