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
  query,
)
where

import Data.Bifunctor (second)

import Mba.Decision.Internal

-- | How to answer any question, in some monad.
type Answers m = forall x. Query x -> m x

-- | Runs a decision that says what should change: the refusal, or the answer
-- and the changes for a commit to write.
decide :: Monad m => Answers m -> Decision e 'Reading 'Settled a -> m (Either e (a, [Change]))
decide = run

-- | Runs a question. There is nothing to commit: its type ends in 'Reading,
-- and no 'Settle' does.
query :: Monad m => Answers m -> Decision e 'Reading 'Reading a -> m (Either e a)
query answers d = fmap fst <$> run answers d

-- | One equation per constructor.
run :: forall m e i j a. Monad m => Answers m -> Decision e i j a -> m (Either e (a, [Change]))
run answers = go
 where
  go :: Decision e i' j' b -> m (Either e (b, [Change]))
  go (Pure a) = pure (Right (a, []))
  go (Bind m k) = do
    first <- go m
    case first of
      Left e -> pure (Left e)
      Right (a, before) -> do
        next <- go (k a)
        pure (fmap (second (before <>)) next)
  go (Ask q) = (\a -> Right (a, [])) <$> answers q
  go (Refuse e) = pure (Left e)
  go (Settle changes) = pure (Right ((), changes))
