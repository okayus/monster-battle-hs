{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}

-- | The decision type and its constructors — for interpreters only.
--
-- A decision is a program that reads, and then either refuses or says what
-- should change. It is not 'IO'. All it can do is what the constructors
-- below say, and an interpreter ("Mba.Decision.Run") gives them meaning.
--
-- Code that writes decisions imports "Mba.Decision", which has the smart
-- constructors and not these. So does everything outside this library,
-- except the one module that makes a 'UserId' ("Mba.Auth").
module Mba.Decision.Internal (
  -- * Where a decision is
  Phase (..),

  -- * Decisions
  Decision,
  Creation,
  Program (..),
  Ids (..),

  -- * What a decision asks, and what it says
  Query (..),
  Change (..),
  UserId (..),
  SkinSummary (..),
  StoredSkin (..),
)
where

import Data.Kind (Type)
import Data.Text (Text)

import Mba.Appearance (Appearance)
import Mba.Map (GameMap, MapId, SaveData)
import Mba.Sprite (Renderable, ResolvedAppearance, Skin)

-- | Where a decision is in its one and only pass.
data Phase = Reading | Settled

-- | @Decision e i j a@ starts in phase @i@, ends in phase @j@, and refuses
-- with an @e@ or answers with an @a@.
--
-- The indices are what reject some programs. Asking keeps the index at
-- 'Reading', and only 'Settle' moves it on, so a decision cannot ask after it
-- has said what changes, nor say it twice; and a decision whose type ends in
-- 'Reading — a GET's — cannot say it at all.
data Ids = WithoutIds | WithIds

type Decision e i j a = Program 'WithoutIds e i j a
type Creation e i j a = Program 'WithIds e i j a

-- | ID capability and phase are independent: save updates cannot generate
-- IDs, while a creation can. GET interprets only WithoutIds/Reading.
type Program :: Ids -> Type -> Phase -> Phase -> Type -> Type
data Program c e i j a where
  Pure :: a -> Program c e i i a
  Bind :: Program c e i j a -> (a -> Program c e j k b) -> Program c e i k b
  Ask :: Query a -> Program c e 'Reading 'Reading a
  NewId :: Program 'WithIds e 'Reading 'Reading Text
  Refuse :: e -> Program c e 'Reading j a
  Settle :: [Change] -> Program c e 'Reading 'Settled ()

instance Functor (Program c e i j) where
  fmap f m = Bind m (Pure . f)

-- | A question about the tables. Each constructor says what its answer is,
-- so the interpreters need no casts to hand one back.
data Query a where
  -- | A map in use. A retired one is not there.
  FindMap :: MapId -> Query (Maybe GameMap)
  -- | The save as stored, if there is one: not yet whether it still makes sense.
  FindSave :: UserId -> Query (Maybe SaveData)
  -- | The stored recipe, if the player has chosen one.
  FindAppearance :: UserId -> Query (Maybe Appearance)
  -- | Render-ready JSON as stored, including retired skins.
  FindDrawing :: Text -> Query (Maybe Text)
  FindSource :: Text -> Query (Maybe Text)
  FindWearable :: Text -> Query (Maybe Renderable)
  ListSkins :: Query [SkinSummary]

data SkinSummary = SkinSummary
  { summaryId :: !Text
  , summaryName :: !Text
  , summaryOwner :: !(Maybe UserId)
  , summaryRetired :: !Bool
  }
  deriving (Show, Eq)

data StoredSkin = StoredSkin
  { storedSummary :: !SkinSummary
  , storedSource :: !Text
  , storedDrawing :: !Text
  , storedRenderable :: !Renderable
  }
  deriving (Show, Eq)

-- | What should change: a value, not SQL. Only @commit@ turns one into writes.
data Change
  = -- | The player is here now.
    PlayerPlaced !UserId !SaveData
  | SkinDrawn !Text !UserId !Skin
  | LookChosen !UserId !ResolvedAppearance
  deriving (Show, Eq)

-- | A user the server vouches for. "Mba.Decision" does not export the
-- constructor, so an id out of a request body or a path cannot be passed
-- where a user is wanted.
newtype UserId = UserId Text
  deriving (Show, Eq, Ord)
