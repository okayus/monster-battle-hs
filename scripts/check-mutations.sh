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
sed -i "s/Ask :: Query a -> Program c e 'Reading 'Reading a/Ask :: Query a -> Program c e i i a/" src/decision/Mba/Decision/Internal.hs
sed -i "s/ask :: Query a -> Program c e 'Reading 'Reading a/ask :: Query a -> Program c e i i a/" src/decision/Mba/Decision.hs
expect_failure 'allow asking after settling' 'asking after settling'
cp decision.original src/decision/Mba/Decision.hs
cp internal.original src/decision/Mba/Decision/Internal.hs

sed -i "s/NewId :: Program 'WithIds e 'Reading 'Reading Text/NewId :: Program 'WithIds e i i Text/" src/decision/Mba/Decision/Internal.hs
sed -i "s/newId :: Creation e 'Reading 'Reading Text/newId :: Creation e i i Text/" src/decision/Mba/Decision.hs
expect_failure 'allow generating an ID after settling' 'generating an ID after settling'
cp decision.original src/decision/Mba/Decision.hs
cp internal.original src/decision/Mba/Decision/Internal.hs

cp src/decision/Mba/Decision/Run.hs run.original
sed -i "s/NewId :: Program 'WithIds e/NewId :: Program c e/" src/decision/Mba/Decision/Internal.hs
sed -i "s/newId :: Creation e/newId :: Program c e/" src/decision/Mba/Decision.hs
sed -i '/case supplies of/a\    NoIds -> pure (Right (mempty, []))' src/decision/Mba/Decision/Run.hs
expect_failure 'allow a GET to generate IDs' 'a GET that generates an ID'
cp decision.original src/decision/Mba/Decision.hs
cp internal.original src/decision/Mba/Decision/Internal.hs
cp run.original src/decision/Mba/Decision/Run.hs

cp src/domain/Mba/Map.hs map.original
sed -i 's/isWalkable Water = False/isWalkable Water = True/' src/domain/Mba/Map.hs
expect_failure 'allow walking on water' 'matches all 1,738 TS'
cp map.original src/domain/Mba/Map.hs

cp src/decision/Mba/Looks.hs looks.original
sed -i 's/D.ask (FindAppearance user)/D.pure Nothing/' src/decision/Mba/Looks.hs
expect_failure 'ignore the stored appearance' 'reads the stored recipe'
cp looks.original src/decision/Mba/Looks.hs

cp src/domain/Mba/Sprite.hs sprite.original
sed -i 's/Set.notMember i used/False/' src/domain/Mba/Sprite.hs
expect_failure 'allow overriding unused palette entries' 'checks only painted colours after swapping parts'
cp sprite.original src/domain/Mba/Sprite.hs

sed -i 's/Rect x y w h index : done/Rect x y 1 h index : done/' src/domain/Mba/Sprite.hs
expect_failure 'discard merged rectangle width' 'merges all 32 TS drawings'
cp sprite.original src/domain/Mba/Sprite.hs

cp src/codec/Mba/Sprite/Json.hs json.original
sed -i 's/bytes > 65536/bytes > 1000000/' src/codec/Mba/Sprite/Json.hs
expect_failure 'skip the reserialized size cap' 'separates wire size from JSON reserialization size'
cp json.original src/codec/Mba/Sprite/Json.hs

cp src/http/Mba/Http.hs http.original
sed -i 's/Get (AppearanceReply <$> lookOf user)/Get (appearanceJson <$> lookOf user)/; s/fmap AppearanceReply \. chooseLook user/fmap appearanceJson . chooseLook user/' src/http/Mba/Http.hs
expect_failure 'lose the wardrobe recipe key order' 'preserves the key order displayed'
cp http.original src/http/Mba/Http.hs
