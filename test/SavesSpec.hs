{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}

-- | The decisions about where a player is, run on the model: no database.
--
-- The model can put a player anywhere to begin with. TS 版's tests had to
-- make a map through the admin API and walk the player in through an exit;
-- here it is one line, so the cases that need a second map are tested before
-- the admin API or exits exist.
module SavesSpec (spec) where

import Data.Functor.Identity (Identity (..))
import Data.List (foldl')
import Data.Map.Strict qualified as Map
import Data.Sequence qualified as Seq
import Test.Hspec
import Test.Hspec.QuickCheck (prop)
import Test.QuickCheck

import GoHome (goHome)
import Mba.Auth (localUser)
import Mba.Decision (Change (..))
import Mba.Decision.Run (decide)
import Mba.Map
import Mba.Maps (startMapId)
import Mba.Model (Model (..))
import Mba.Model qualified as Model
import Mba.Refusal (Refusal (..))
import Mba.Saves (savePosition, whereIs)
import Support

-- | Puts the player somewhere, the way an earlier visit would have left them.
standingAt :: MapId -> Position -> Model -> Model
standingAt m at model = model{modelSaves = Map.insert localUser (SaveData m at) (modelSaves model)}

-- | Both maps, with the player in the left room, where they came in.
inTheLeftRoom :: Model
inTheLeftRoom = standingAt roomsId (Position 0 1) fresh{modelMaps = Map.insert roomsId rooms (modelMaps fresh)}

put :: SaveData -> Model -> (Either Refusal SaveData, Model)
put = Model.perform . savePosition localUser

refusal :: SaveData -> Model -> Either Refusal SaveData
refusal wanted = fst . put wanted

atSpawn :: SaveData
atSpawn = SaveData startMapId (Position 1 1)

spec :: Spec
spec = do
  describe "whereIs" $ do
    it "a player with no save is at the starter map's spawn" $
      Model.query (whereIs localUser) fresh `shouldBe` Right atSpawn
    it "a save on a tile that has since become a tree is not worth keeping: the spawn" $ do
      let saved = standingAt startMapId (firstTile Grass) fresh
          Position x y = firstTile Grass
          redrawn = starter{mapTiles = Seq.update (y * 16 + x) Tree (mapTiles starter)}
      Model.query (whereIs localUser) saved{modelMaps = Map.insert startMapId redrawn (modelMaps saved)}
        `shouldBe` Right atSpawn

  describe "savePosition" $ do
    it "answers with the position, and says that the player is there now" $ do
      let wanted = SaveData startMapId (firstTile Grass)
      runIdentity (decide (Identity . Model.answer fresh) (savePosition localUser wanted))
        `shouldBe` Right (wanted, [PlayerPlaced localUser wanted])

    it "refuses a map that is not there" $
      refusal (SaveData (MapId "nowhere") (Position 1 1)) fresh
        `shouldBe` Left (UnknownMap (MapId "nowhere"))

    it "refuses a tile nobody can stand on: a tree, water, past the edge, below zero" $
      [ refusal (SaveData startMapId p) fresh
      | p <- [firstTile Tree, firstTile Water, Position 16 0, Position (-1) 0]
      ]
        `shouldBe` [ Left (CannotStand startMapId p)
                   | p <- [firstTile Tree, firstTile Water, Position 16 0, Position (-1) 0]
                   ]

    it "refuses a position on a map the player is not on: that takes an exit" $
      refusal atSpawn inTheLeftRoom `shouldBe` Left (WrongMap startMapId roomsId)

    it "refuses grass on the far side of a wall" $
      refusal (SaveData roomsId (Position 4 0)) inTheLeftRoom
        `shouldBe` Left (Unreachable roomsId (Position 4 0))

    it "takes that very tile from a player on the same side of the wall" $
      refusal (SaveData roomsId (Position 4 0)) (standingAt roomsId (Position 2 1) inTheLeftRoom)
        `shouldBe` Right (SaveData roomsId (Position 4 0))

    it "says a tile cannot be stood on before it says it cannot be reached" $
      refusal (SaveData roomsId (Position 1 0)) inTheLeftRoom
        `shouldBe` Left (CannotStand roomsId (Position 1 0))

    it "leaves the tables as they were when it refuses" $
      snd (put (SaveData startMapId (firstTile Tree)) fresh) `shouldBe` fresh

  describe "goHome (examples/GoHome.hs)" $
    it "the second time, has nothing to change" $ do
      let away = snd (put (SaveData startMapId (Position 4 2)) fresh)
          home = snd (Model.perform (goHome localUser) away)
      runIdentity (decide (Identity . Model.answer home) (goHome localUser))
        `shouldBe` Right (atSpawn, [])

  describe "what always holds" $ do
    prop "wherever the player is, they could have walked there from where they came in" $
      forAll (listOf (aSave [roomsId, startMapId] (-1, 5) (-1, 2))) $ \puts ->
        let states = scanl (flip (\wanted -> snd . put wanted)) inTheLeftRoom puts
            reachable model = case Model.query (whereIs localUser) model of
              Right (SaveData m at) -> m == roomsId && canWalkTo rooms (Position 0 1) at
              Left _ -> False
         in all reachable states

    prop "the same PUT twice leaves the tables as once does" $
      forAll (listOf onTheStarterMap) $ \earlier -> forAll onTheStarterMap $ \wanted ->
        let start = foldl' (\model p -> snd (put p model)) fresh earlier
            afterOne = snd (put wanted start)
         in snd (put wanted afterOne) === afterOne
