{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QualifiedDo #-}
{-# OPTIONS_GHC -fdefer-type-errors -Wno-deferred-type-errors #-}

-- | What must not compile.
--
-- Each decision below breaks a rule the indices hold, and is a type error.
-- With @-fdefer-type-errors@, GHC compiles this module anyway and turns each
-- error into a 'TypeError' thrown when the ill-typed part is reached — and
-- running a decision reaches all of it. So "it does not compile" becomes a
-- test that runs.
--
-- Loosen the types — let 'D.ask' keep any index instead of 'Reading — and
-- the first of these compiles, runs, throws nothing, and its test fails.
--
-- The flag is for this module only. Anywhere else a type error stays an
-- error.
module TypeErrorSpec (spec) where

import Control.Exception (TypeError (..), evaluate)
import Data.Aeson (object)
import Data.List (isInfixOf)
import Test.Hspec

import Data.Text (Text)
import Mba.Appearance (defaultAppearance)
import Mba.Auth (localUser)
import Mba.Decision (Change (..), Creation, Decision, Phase (..), Query (..))
import Mba.Decision qualified as D
import Mba.Map
import Mba.Maps (startMapId)
import Mba.Model qualified as Model
import Mba.Refusal (Refusal (..))
import Support (fresh)

home :: SaveData
home = SaveData startMapId (Position 1 1)

-- | Asks after settling: what it would read is the state from before its own
-- changes.
askAfterSettling :: Decision Refusal 'Reading 'Settled (Maybe SaveData)
askAfterSettling = D.do
  D.settle [PlayerPlaced localUser home]
  D.ask (FindSave localUser)

-- | Says what should change twice.
settlingTwice :: Decision Refusal 'Reading 'Settled ()
settlingTwice = D.do
  D.settle [PlayerPlaced localUser home]
  D.settle [PlayerPlaced localUser home]

-- | Refuses after saying what changes: by then the answer was yes.
refusingAfterSettling :: Decision Refusal 'Reading 'Settled ()
refusingAfterSettling = D.do
  D.settle [PlayerPlaced localUser home]
  D.refuse NotFound

-- | A question — what a GET runs — that says what should change.
getThatWrites :: Decision Refusal 'Reading 'Reading ()
getThatWrites = D.settle [PlayerPlaced localUser home]

getThatCreatesId :: Decision Refusal 'Reading 'Reading Text
getThatCreatesId = D.newId

idAfterSettling :: Creation Refusal 'Reading 'Settled Text
idAfterSettling = D.do
  D.settle []
  D.newId

unresolvedLook :: Change
unresolvedLook = LookChosen localUser defaultAppearance

unvalidatedSkin :: Change
unvalidatedSkin = SkinDrawn "id" localUser (object [])

spec :: Spec
spec = describe "does not compile" $ do
  it "asking after settling" $ doesNotCompile (fst (Model.perform askAfterSettling fresh))
  it "settling twice" $ doesNotCompile (fst (Model.perform settlingTwice fresh))
  it "refusing after settling" $ doesNotCompile (fst (Model.perform refusingAfterSettling fresh))
  it "a GET that says what should change" $ doesNotCompile (Model.query getThatWrites fresh)
  it "a GET that generates an ID" $
    evaluate (either (const ()) (const ()) (Model.query getThatCreatesId fresh)) `shouldThrow` aboutIds
  it "generating an ID after settling" $
    let (result, _, _) = Model.create ["id"] idAfterSettling fresh in doesNotCompile result
  it "committing an unresolved appearance" $
    evaluate unresolvedLook `shouldThrow` about "ResolvedAppearance"
  it "committing an unvalidated skin" $
    evaluate unvalidatedSkin `shouldThrow` about "Skin"

-- | Running it throws the type error that GHC deferred — about the phases.
doesNotCompile :: Either Refusal a -> Expectation
doesNotCompile result = evaluate (either (const ()) (const ()) result) `shouldThrow` aboutPhases
 where
  aboutPhases (TypeError message) = "Settled" `isInfixOf` message || "Reading" `isInfixOf` message

aboutIds :: TypeError -> Bool
aboutIds (TypeError message) = "WithIds" `isInfixOf` message || "WithoutIds" `isInfixOf` message

about :: String -> TypeError -> Bool
about name (TypeError message) = name `isInfixOf` message
