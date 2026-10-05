{-# LANGUAGE DataKinds #-}

-- | Writing decisions. Import this qualified, and write them with @D.do@:
--
-- @
-- {-\# LANGUAGE QualifiedDo \#-}
-- import qualified Mba.Decision as D
--
-- whereIs :: UserId -> Decision Refusal 'Reading 'Reading SaveData
-- whereIs user = D.do
--   current <- loadSave user
--   D.orRefuse NoStartMap current
-- @
--
-- The indices turn some programs into type errors:
--
-- @
-- bad user = D.do
--   D.settle [PlayerPlaced user home]
--   D.ask (FindSave user)   -- ask wants 'Reading, and the index is 'Settled
-- @
--
-- What this module does not export is the GADT's constructors. Decisions are
-- built from the functions below; "Mba.Decision.Run" gives them meaning.
module Mba.Decision (
  -- * Decisions
  Decision,
  Creation,
  Program,
  Ids (..),
  Phase (..),

  -- * What a decision can do
  ask,
  newId,
  refuse,
  settle,
  require,
  orRefuse,

  -- * What it asks about, and what it says
  Query (..),
  Change (..),
  SkinSummary (..),
  UserId,
  userIdText,

  -- * @D.do@
  pure,
  (>>=),
  (>>),
)
where

import Prelude hiding (pure, (>>), (>>=))

import Data.Text (Text)

import Mba.Decision.Internal

-- | Asks a question. Keeps the index at 'Reading.
ask :: Query a -> Program c e 'Reading 'Reading a
ask = Ask

-- | Available only to a creation, and only before settling.
newId :: Creation e 'Reading 'Reading Text
newId = NewId

-- | Ends the decision with a refusal. Only while reading: once the changes
-- are said, the answer is yes.
refuse :: e -> Program c e 'Reading j a
refuse = Refuse

-- | Says what should change. Once: the index moves to 'Settled, and nothing
-- that needs 'Reading can follow.
settle :: [Change] -> Program c e 'Reading 'Settled ()
settle = Settle

-- | Refuses with @e@ unless the condition holds.
require :: Bool -> e -> Program c e 'Reading 'Reading ()
require holds e = if holds then Pure () else Refuse e

-- | The value, or a refusal if there is none.
orRefuse :: e -> Maybe a -> Program c e 'Reading 'Reading a
orRefuse e = maybe (Refuse e) Pure

userIdText :: UserId -> Text
userIdText (UserId t) = t

-- | Changes nothing: the index stays where it is.
pure :: a -> Program c e i i a
pure = Pure

-- | The index runs on: from @i@ to @j@, then from @j@ to @k@.
(>>=) :: Program c e i j a -> (a -> Program c e j k b) -> Program c e i k b
(>>=) = Bind

(>>) :: Program c e i j a -> Program c e j k b -> Program c e i k b
m >> k = Bind m (const k)
