#!/bin/sh
# Run with: docker compose run --rm --no-deps dev sh scripts/check-mutations.sh
# Every mutation is made in a disposable copy inside the container.
set -eu
scratch=$(mktemp -d /tmp/monster-battle-mutations.XXXXXX)
trap 'rm -rf "$scratch"' EXIT
cp -R src app demo examples test migrations seed monster-battle-hs.cabal cabal.project cabal.project.freeze README.md "$scratch/"
cd "$scratch"

expect_failure() {
  label=$1
  pattern=$2
  if cabal test all --offline --test-show-details=direct --test-options="--match \"$pattern\"" > result.log 2>&1; then
    cat result.log
    printf 'ERROR: mutation survived: %s\n' "$label"
    exit 1
  fi
  # A compilation or setup failure is not evidence that the assertion works.
  if ! grep -q '1 example, 1 failure' result.log; then
    cat result.log
    printf 'ERROR: did not reach the intended assertion: %s\n' "$label"
    exit 1
  fi
  printf 'Detected mutation: %s (1 example, 1 failure)\n' "$label"
}

cp src/decision/Mba/Decision.hs decision.original
cp src/decision/Mba/Decision/Internal.hs internal.original
sed -i "s/Ask :: Query a -> Decision e 'Reading 'Reading a/Ask :: Query a -> Decision e i i a/" src/decision/Mba/Decision/Internal.hs
sed -i "s/ask :: Query a -> Decision e 'Reading 'Reading a/ask :: Query a -> Decision e i i a/" src/decision/Mba/Decision.hs
expect_failure 'allow asking after settling' 'asking after settling'
cp decision.original src/decision/Mba/Decision.hs
cp internal.original src/decision/Mba/Decision/Internal.hs

cp src/domain/Mba/Map.hs map.original
sed -i 's/isWalkable Water = False/isWalkable Water = True/' src/domain/Mba/Map.hs
expect_failure 'allow walking on water' 'matches all 1,738 TS'
cp map.original src/domain/Mba/Map.hs

cp src/decision/Mba/Looks.hs looks.original
sed -i 's/lookOf user = fromMaybe defaultAppearance <$> D.ask (FindAppearance user)/lookOf _ = D.pure defaultAppearance/' src/decision/Mba/Looks.hs
expect_failure 'ignore the stored appearance' 'reads the stored recipe'
cp looks.original src/decision/Mba/Looks.hs
