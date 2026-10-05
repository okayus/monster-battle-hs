{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}

-- | Runs requests one at a time on the model, and prints each stage:
-- 読む → 決める → 変更 → 書く.
--
-- The same decisions the server runs on SQLite. Here the questions are
-- answered from a value, and answered out loud.
module Main (main) where

import Data.Foldable (for_)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T

import GoHome (goHome)
import Mba.Auth (localUser)
import Mba.Decision (Change, Decision, Phase (..), Query (..))
import Mba.Decision.Run (decide)
import Mba.Map
import Mba.Maps (startMapId, starterMap)
import Mba.Model (Model (..), answer, commit)
import Mba.Refusal (Refusal)
import Mba.Saves (savePosition)

main :: IO ()
main = do
  let start = either (error . T.unpack) id starterMap
      empty = Model (Map.singleton startMapId start) Map.empty Map.empty Map.empty
      walked = SaveData startMapId (Position 4 2)

  heading "PUT /api/save  (4, 2)"
  (s1, _) <- request empty (savePosition localUser walked)
  heading "PUT /api/save  (4, 2)  もう一度"
  (s2, again) <- request s1 (savePosition localUser walked)
  verdict (s2 == s1 && not (null again)) "状態は 1 回目の後と同じ。変更の一覧は空ではない（TS 版と同じく、同じ位置でも書く）"

  heading "goHome  (examples/GoHome.hs)"
  (s3, _) <- request s2 (goHome localUser)
  heading "goHome  もう一度"
  (s4, nothing) <- request s3 (goHome localUser)
  verdict (s4 == s3 && null nothing) "2 回目の変更の一覧は空。u ∘ u = u"

  heading "PUT /api/save  (0, 0)  木の上"
  _ <- request s4 (savePosition localUser (SaveData startMapId (Position 0 0)))
  pure ()

-- | One request: the questions it asks as it asks them, then what it decided,
-- the changes it said, and the saves table after they are written.
request :: Show a => Model -> Decision Refusal 'Reading 'Settled a -> IO (Model, [Change])
request model d = do
  putStrLn "  読む"
  decided <- decide (loud model) d
  case decided of
    Left refusal -> do
      putStrLn ("  決める   断る: " <> show refusal)
      putStrLn "  変更     （断ったので無い）"
      pure (model, [])
    Right (a, changes) -> do
      putStrLn ("  決める   " <> show a)
      putStrLn ("  変更     " <> show changes)
      let after = commit changes model
      putStrLn "  書く     saves:"
      for_ (Map.toList (modelSaves after)) $ \(user, save) ->
        putStrLn ("             " <> show user <> " → " <> show save)
      pure (after, changes)

-- | Answers from the model, and prints the question and the answer.
loud :: Model -> Query a -> IO a
loud model q = do
  let a = answer model q
  putStrLn ("    " <> describe q a)
  pure a

-- | One equation per question.
describe :: Query a -> a -> String
describe (FindMap (MapId m)) found =
  "FindMap " <> show m <> "  → " <> maybe "Nothing" (T.unpack . mapName) found
describe (FindSave user) found = "FindSave " <> show user <> "  → " <> show found
describe (FindAppearance user) found = "FindAppearance " <> show user <> "  → " <> show found
describe (FindDrawing sid) found = "FindDrawing " <> show sid <> "  → " <> show found
describe (FindSource sid) found = "FindSource " <> show sid <> "  → " <> show found
describe (FindWearable sid) found = "FindWearable " <> show sid <> "  → " <> show found
describe ListSkins found = "ListSkins → " <> show found

heading :: String -> IO ()
heading title = putStrLn ("\n" <> title)

verdict :: Bool -> String -> IO ()
verdict holds text = putStrLn ((if holds then "  ✓ " else "  ✗ ") <> text)
