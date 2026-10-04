{-# LANGUAGE OverloadedStrings #-}

-- | SQLite: the migrations, the seed, and the same decisions as on the model.
module SqliteSpec (spec) where

import Data.List (foldl')
import Test.Hspec
import Test.Hspec.QuickCheck (prop)
import Test.QuickCheck

import Mba.Auth (localUser)
import Mba.Model qualified as Model
import Mba.Saves (savePosition, whereIs)
import Mba.Sqlite qualified as Sqlite
import Support

spec :: Spec
spec = do
  describe "migrate" $ do
    it "runs TS 版's nine files — every statement in each — and makes its twelve tables" $
      withDb $ \db applied -> do
        applied `shouldBe` 9
        Sqlite.tables db
          `shouldReturn` [ "_migrations"
                         , "appearances"
                         , "battles"
                         , "map_encounters"
                         , "map_exits"
                         , "maps"
                         , "moves"
                         , "owned_monsters"
                         , "saves"
                         , "skins"
                         , "species"
                         , "species_moves"
                         , "users"
                         ]
    it "runs none of them a second time" $
      withDb $
        \db _ -> Sqlite.migrate db "migrations" 0 `shouldReturn` 0

  describe "seed" $
    it "can run at every boot" $
      withDb $ \db _ -> do
        Sqlite.seed db localUser 0
        Sqlite.query db (whereIs localUser) `shouldReturn` Model.query (whereIs localUser) fresh

  describe "against the model" $
    prop "answers each request as the model does, and ends in the same place" $
      forAll (listOf onTheStarterMap) $ \puts -> ioProperty $ withDb $ \db _ -> do
        answers <- traverse (Sqlite.perform db . savePosition localUser) puts
        end <- Sqlite.query db (whereIs localUser)
        let onModel (done, m) wanted =
              let (a, m') = Model.perform (savePosition localUser wanted) m in (done <> [a], m')
            (expected, model) = foldl' onModel ([], fresh) puts
        pure ((answers, end) === (expected, Model.query (whereIs localUser) model))
