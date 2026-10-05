{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}

-- | What a decision means: one interpreter, and many ways to answer it.
--
-- 'Pure', 'Bind', 'Refuse' and 'Settle' are given their meaning here and
-- nowhere else, so they mean the same on every runner. What differs between
-- SQLite (production), the model (tests) and the demo is only how a question
-- is answered: the 'Answers' each of them passes in.
--
-- @
-- decide (Identity . Model.answer model) (savePosition user wanted)
--   -- Identity (Right (wanted, [PlayerPlaced user wanted]))
-- @
module Mba.Decision.Run (
  Answers,
  decide,
  create,
  query,
)
where

import Data.Bifunctor (second)
import Data.Text (Text)

import Mba.Decision.Internal

-- | How to answer any question, in some monad.
type Answers m = forall x. Query x -> m x

-- | Runs a decision that says what should change: the refusal, or the answer
-- and the changes for a commit to write.
decide :: Monad m => Answers m -> Decision e 'Reading 'Settled a -> m (Either e (a, [Change]))
decide = run NoIds

create ::
  Monad m => m Text -> Answers m -> Creation e 'Reading 'Settled a -> m (Either e (a, [Change]))
create ids = run (GenerateIds ids)

-- | Runs a question. There is nothing to commit: its type ends in 'Reading,
-- and no 'Settle' does.
query :: Monad m => Answers m -> Decision e 'Reading 'Reading a -> m (Either e a)
query answers d = fmap fst <$> run NoIds answers d

-- | One equation per constructor.
data Supplies m c where
  NoIds :: Supplies m 'WithoutIds
  GenerateIds :: m Text -> Supplies m 'WithIds

run ::
  forall m c e i j a.
  Monad m => Supplies m c -> Answers m -> Program c e i j a -> m (Either e (a, [Change]))
run supplies answers = go
 where
  go :: Program c e i' j' b -> m (Either e (b, [Change]))
  go (Pure a) = pure (Right (a, []))
  go (Bind m k) = do
    first <- go m
    case first of
      Left e -> pure (Left e)
      Right (a, before) -> do
        next <- go (k a)
        pure (fmap (second (before <>)) next)
  go (Ask q) = (\a -> Right (a, [])) <$> answers q
  go NewId = case supplies of
    GenerateIds action -> (\sid -> Right (sid, [])) <$> action
  go (Refuse e) = pure (Left e)
  go (Settle changes) = pure (Right ((), changes))
