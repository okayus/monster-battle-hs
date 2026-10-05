{-# LANGUAGE OverloadedStrings #-}

-- | Generated creation/wardrobe histories run on both interpreters. Clocks
-- are fixed, so list ordering breaks ties by ID on the model and SQLite.
module LooksSpec (spec) where

import Control.Monad (foldM_)
import Data.Aeson (Object, Value, eitherDecode, object, (.:), (.=))
import Data.Aeson.Types (parseEither)
import Data.ByteString.Lazy qualified as LBS
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Test.Hspec hiding (after)
import Test.Hspec.QuickCheck (prop)
import Test.QuickCheck hiding (again)

import Mba.Auth (localUser)
import Mba.Decision.Internal (SkinSummary (..), StoredSkin (..))
import Mba.Looks (chooseLook, drawingById, lookOf)
import Mba.Model qualified as Model
import Mba.Skins (drawSkin, sourceById, wearableSkins)
import Mba.Sprite (toRenderable)
import Mba.Sprite.Json (jsonText, parseAppearance, parseSkin, renderableJson, skinJson)
import Mba.Sqlite qualified as Sqlite
import SkinContractSpec (recipe, skinInput)
import Support (fresh, withDb)

data Action = Draw Bool | Wear Text (Maybe Text) [Text] deriving (Show)

action :: Gen Action
action =
  frequency
    [(2, Draw <$> arbitrary), (5, Wear <$> sid <*> oneof [pure Nothing, Just <$> sid] <*> colours)]
 where
  sid = elements ["skin-1", "skin-2", "skin-3", "player-default", "species-moss", "missing"]
  colours = elements [[], ["skin"], ["hair"], ["hat"], ["unused"], ["skin", "hair"]]

seededModel :: IO Model.Model
seededModel = do
  entries <- LBS.readFile "seed/skins.json" >>= either fail pure . eitherDecode :: IO [Object]
  rows <- traverse row entries
  pure fresh{Model.modelSkins = Map.fromList rows}
 where
  row o = do
    (sid, source) <-
      either fail pure (parseEither (\v -> (,) <$> v .: "id" <*> v .: "source") o) :: IO (Text, Value)
    skin <- either (fail . show) pure (parseSkin source)
    name <- either fail pure (parseEither (\v -> v .: "source" >>= (.: "name")) o)
    let drawing = toRenderable skin
    pure
      ( sid
      , StoredSkin
          (SkinSummary sid name Nothing False)
          (jsonText (skinJson skin))
          (jsonText (renderableJson drawing))
          drawing
      )

spec :: Spec
spec = prop
  "matches SQLite after every generated draw/wardrobe request, preserves refusals, and repeats PUT idempotently"
  $ forAll (resize 30 (listOf action))
  $ \actions -> ioProperty $ withDb $ \db _ -> do
    initial <- seededModel
    let ids = ["skin-" <> T.pack (show n) | n <- [1 :: Int ..]]
        step (model, supply) command = do
          (next, remaining) <- case command of
            Draw alternative -> do
              skin <- either (fail . show) pure (parseSkin (skinInput alternative))
              let decision = drawSkin localUser skin
                  (expected, after, unused) = Model.create supply decision model
              Sqlite.create db decision `shouldReturn` expected
              take 1 unused `shouldBe` take 1 (drop 1 supply)
              pure (after, unused)
            Wear sid hair colours -> do
              checked <-
                either
                  (fail . show)
                  pure
                  (parseAppearance (recipe sid (maybe (object []) (\s -> object ["hair" .= s]) hair) colours))
              let decision = chooseLook localUser checked
                  (expected, after) = Model.perform decision model
                  (again, twice) = Model.perform decision after
              Sqlite.perform db decision `shouldReturn` expected
              Sqlite.perform db decision `shouldReturn` again
              twice `shouldBe` after
              case expected of
                Left _ -> after `shouldBe` model
                Right _ -> pure ()
              pure (after, supply)
          Sqlite.query db (lookOf localUser) `shouldReturn` Model.query (lookOf localUser) next
          Sqlite.query db wearableSkins `shouldReturn` Model.query wearableSkins next
          let checkSkin sid = do
                Sqlite.query db (sourceById sid) `shouldReturn` Model.query (sourceById sid) next
                Sqlite.query db (drawingById sid) `shouldReturn` Model.query (drawingById sid) next
          mapM_ checkSkin ["skin-1", "skin-2", "species-moss", "missing"]
          pure (next, remaining)
    foldM_ step (initial, ids) actions
    pure True
