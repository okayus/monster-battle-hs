{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}

-- | The tables as a value, and decisions run on it.
--
-- The decisions that run on SQLite in production run here with no database
-- at all: 'answer' answers their questions from a 'Model', and 'commit'
-- applies what they say should change. That is what lets a test throw
-- hundreds of requests at a decision and check, after each one, what must
-- always hold — and then run the same requests on SQLite and compare
-- (docs/03-testing.md).
--
-- @
-- let (answered, after) = perform (savePosition user wanted) before
-- @
module Mba.Model (
  Model (..),
  answer,
  commit,
  perform,
  query,
)
where

import Data.Functor.Identity (Identity (..))
import Data.List (foldl')
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)

import Mba.Appearance (Appearance)
import Mba.Decision.Internal
import Mba.Decision.Run qualified as Run
import Mba.Map (GameMap, MapId, SaveData)

data Model = Model
  { modelMaps :: !(Map MapId GameMap)
  -- ^ The maps in use. A retired map is simply not here.
  , modelSaves :: !(Map UserId SaveData)
  , modelAppearances :: !(Map UserId Appearance)
  , modelDrawings :: !(Map Text Text)
  }
  deriving (Show, Eq)

-- | One equation per question.
answer :: Model -> Query a -> a
answer model (FindMap mid) = Map.lookup mid (modelMaps model)
answer model (FindSave user) = Map.lookup user (modelSaves model)
answer model (FindAppearance user) = Map.lookup user (modelAppearances model)
answer model (FindDrawing sid) = Map.lookup sid (modelDrawings model)

-- | One equation per change: the model's @Mba.Sqlite.commit@.
commit :: [Change] -> Model -> Model
commit changes model = foldl' apply model changes
 where
  apply m (PlayerPlaced user save) = m{modelSaves = Map.insert user save (modelSaves m)}

-- | Runs a decision that settles, and commits what it says. A refusal leaves
-- the model as it was.
perform :: Decision e 'Reading 'Settled a -> Model -> (Either e a, Model)
perform d model = case runIdentity (Run.decide (Identity . answer model) d) of
  Left e -> (Left e, model)
  Right (a, changes) -> (Right a, commit changes model)

-- | Runs a question.
query :: Decision e 'Reading 'Reading a -> Model -> Either e a
query d model = runIdentity (Run.query (Identity . answer model) d)
