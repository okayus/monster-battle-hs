module Main (main) where

import Test.Hspec

import FixtureSpec qualified
import HttpSpec qualified
import MapSpec qualified
import ReadContractSpec qualified
import SavesSpec qualified
import SqliteSpec qualified
import TypeErrorSpec qualified

main :: IO ()
main = hspec $ do
  describe "TS movement fixtures" FixtureSpec.spec
  describe "stored read contracts" ReadContractSpec.spec
  describe "Mba.Map" MapSpec.spec
  describe "Mba.Saves (on the model)" SavesSpec.spec
  describe "the decision type" TypeErrorSpec.spec
  describe "Mba.Sqlite" SqliteSpec.spec
  describe "Mba.Http" HttpSpec.spec
