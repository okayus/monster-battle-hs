// Run in the Node 24 fixtures service; see docs/03-testing.md.
// The reference seed must be git show 14251cc:apps/api/src/seed.ts.
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { stripTypeScriptTypes } from "node:module";
import vm from "node:vm";
import { step, canWalkTo } from "../frontend/packages/core/src/index.ts";
import { PART_SLOTS, SKIN_SPEC, packFrame, parseSkin, toRenderable } from "../frontend/packages/sprite/src/index.ts";

const root = new URL("../", import.meta.url);
const seed = await readFile(process.argv[2], "utf8");
// Only the pure player drawing definitions; the DB imports are never loaded.
const definitions = seed.slice(seed.indexOf("const PLAYER_PALETTE:"), seed.indexOf("function ensureDefaultSkin("));
if (!definitions.includes("function playerSkin(")) throw new Error("reference seed layout changed");
const helpers = seed.slice(seed.indexOf("const FRAME_MS ="), seed.indexOf("function monsterSkin("));
const context = vm.createContext({ PART_SLOTS, SKIN_SPEC, packFrame, parseSkin });
const source = vm.runInContext(stripTypeScriptTypes(`${helpers}\n${definitions}\nplayerSkin()`), context);
if (!source.ok) throw new Error(JSON.stringify(source.error));
const asset = { source: source.value, renderable: toRenderable(source.value) };
await mkdir(new URL("seed/", root), { recursive: true });
await writeFile(new URL("seed/player-default.json", root), JSON.stringify(asset, null, 2) + "\n");

const maps = [
  { width: 5, height: 2, tiles: ["path", "tree", "path", "path", "grass", "path", "tree", "path", "path", "path"] },
  { width: 3, height: 3, tiles: ["path", "grass", "water", "tree", "path", "grass", "water", "grass", "path"] },
  { width: 1, height: 1, tiles: ["path"] },
];
const fixtures = maps.map((map) => {
  const positions = [];
  for (let y = -1; y <= map.height; y++) {
    for (let x = -1; x <= map.width; x++) positions.push({ x, y });
  }
  const steps = positions.flatMap((from) => ["up", "down", "left", "right"].map((direction) => ({
    from, direction, to: step(from, direction, map),
  })));
  const walks = positions.flatMap((from) => positions.map((to) => ({ from, to, reachable: canWalkTo(map, from, to) })));
  return { map, steps, walks };
});
await mkdir(new URL("test/fixtures/", root), { recursive: true });
await writeFile(new URL("test/fixtures/movement.json", root), JSON.stringify(fixtures) + "\n");
console.log(`Generated default skin and ${fixtures.reduce((n, f) => n + f.steps.length + f.walks.length, 0)} movement cases from TS 14251cc.`);
