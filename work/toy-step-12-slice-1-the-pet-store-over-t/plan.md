# Plan — Toy step 12, slice 1: the pet store over the two existing slots (ticket #68, thread 266)

Implements `spec.md` (same dir). Everything is in `office/` (TypeScript, bun). Run commands from `office/`.
**Gate per task:** `bun test <file>` then `bun run typecheck`. **Gate before the PR:** `mise run office:check`
(frozen install, typecheck, tests at 03:00 and 15:00). One commit per task; each commit ends with
`Co-Authored-By: <your model> <noreply@…>` (repo law). Test first: write the test, see it red, then the code.

## Read once (what the code already is)
- `kit/pets.ts` — `SPECIES`, `SLOT_SPECIES` (cat: cat/rabbit/bird, dog: dog), `PetSetting`, `resolvePets`, `previewOf`, `dots`.
- `kit/sprites.ts` — `CAT`/`RABBIT`/`BIRD` frame sets (rows of letters: `k` fur, `e` eye, `c` eye shut, `t` tail, `w` edge, `p` pink), `SPECIES_ART`, `hash`.
- `kit/voices.ts` `SPECIES_VOICE`+`bucketFor`; `kit/temperament.ts` `SPECIES_BASE`+`speciesBase`; `kit/draw.ts` `drawCat`.
- `kit/hall.ts` + `tui/hall.ts` + `main.ts` `case "hall"` — the shape the store copies. `tui/pets.ts` — `savePets` read-merge-write.
- The room only applies the **cat slot** (`Sim.setPets` sets `cat` name/species/temperament; Argos' name is fixed). So the store's shelf is the **cat-slot species**; `dog` is not shelved (adopting a dog would write a file the room ignores). Spec §3's "dog → dog slot" stays true in `slotOf`/`adopt`; the shelf just doesn't offer it yet. *This is the one deviation from the spec; flagged on the thread.*
- `main.ts` already has `ask2(label, run)` (a y/n confirm) — the adopt confirm uses it, so the key is `y`, not ⏎/esc as spec §3 sketched.

## Task 1 — the pets path knows the sandbox (own commit, spec §6)
Files: `tui/pets.ts`, `tui/main.ts` (one line), `test/petsfile.test.ts`.

Test first, append to `test/petsfile.test.ts` (`import { inSandbox, loadPets, petsPath, savePets } from "../tui/pets"`):
```ts
describe("which pets.json", () => {
  test("the sandbox gets a file of its own, TLON_PETS still wins", () => {
    expect(petsPath(true, {}, "/home/u", "/tmp/x")).toBe("/tmp/x/tlon-sandbox/pets.json")
    expect(petsPath(false, {}, "/home/u", "/tmp/x")).toBe("/home/u/.config/tlon/pets.json")
    expect(petsPath(false, { XDG_CONFIG_HOME: "/xdg" }, "/home/u")).toBe("/xdg/tlon/pets.json")
    expect(petsPath(true, { TLON_PETS: "/p.json" })).toBe("/p.json")
  })
  test("--sandbox or OFFICE_SANDBOX=1", () => {
    expect(inSandbox(["bun", "main.ts", "--sandbox"], {})).toBe(true)
    expect(inSandbox([], { OFFICE_SANDBOX: "1" })).toBe(true)
    expect(inSandbox([], {})).toBe(false)
  })
})
```
Code, `tui/pets.ts` — replace the `PETS_PATH` definition and the header comment, add `tmpdir` import:
```ts
// pets.json: yours, like looks.json. `TLON_PETS` to point elsewhere; the sandbox keeps its own under $TMPDIR/tlon-sandbox.
import { mkdirSync, readFileSync, writeFileSync } from "node:fs"
import { homedir, tmpdir } from "node:os"
import { dirname, join } from "node:path"
import type { PetsFile } from "../kit/pets"

export const inSandbox = (argv: readonly string[] = process.argv, env: Record<string, string | undefined> = process.env) =>
  argv.includes("--sandbox") || env.OFFICE_SANDBOX === "1"

export function petsPath(sandbox: boolean, env: Record<string, string | undefined> = process.env, home = homedir(), tmp = tmpdir()): string {
  if (env.TLON_PETS) return env.TLON_PETS
  return sandbox ? join(tmp, "tlon-sandbox/pets.json") : join(env.XDG_CONFIG_HOME ?? join(home, ".config"), "tlon/pets.json")
}

export const PETS_PATH = petsPath(inSandbox())
```
`tui/main.ts` line ~85: `const SANDBOX = inSandbox()`; extend the import at line 43 to `import { inSandbox, loadPets, PETS_PATH, savePets } from "./pets"`.
Done = `bun test test/petsfile.test.ts` green, typecheck green. Commit: `office: pets.json follows --sandbox (the pet card's S no longer writes the real file)`.

## Task 2 — a species is data: the lookups stop naming rabbit and bird
Files: `kit/pets.ts`, `kit/sprites.ts`, `kit/voices.ts`, `kit/temperament.ts`, `kit/sim.ts`, `kit/draw.ts`, `tui/main.ts` (one line), `test/pets.test.ts`. No new species yet; behaviour unchanged.

Test first, append to `test/pets.test.ts` (add `slotOf`, `SPECIES`, `SLOT_SPECIES` to the `../kit/pets` import, `bucketFor` to the `../kit/voices` import):
```ts
describe("every species is data", () => {
  test("art, exactly one slot, a destination table, a voice that falls back to Nina", () => {
    for (const sp of SPECIES) {
      const slot = slotOf(sp)
      expect({ sp, slots: ["cat", "dog"].filter((s) => (SLOT_SPECIES as Record<string, readonly string[]>)[s]!.includes(sp)).length }).toEqual({ sp, slots: 1 })
      if (slot !== "cat") continue
      const art = (SPECIES_ART as Record<string, Record<string, string[][]>>)[sp]!
      for (const pose of ["sit", "blink", "groom", "walk", "sleep", "stretch", "play"]) expect({ sp, pose, ok: art[pose]!.length > 0 }).toEqual({ sp, pose, ok: true })
      expect(Object.values(speciesBase(sp)).reduce((a, b) => a + b, 0)).toBeCloseTo(1, 10)
      const neutral = { warmth: 0, wits: 0, energy: 0 }
      expect(bucketFor("typing", neutral, () => 0, sp)).toBe(bucketFor("typing", neutral, () => 0, "cat"))
    }
  })
  test("a pose a species does not draw falls back to its sit, at any index", () => {
    const art = fillArt({ sit: [["kk"]] })
    expect(art.walk).toBe(art.sit)
  })
})
```
(`bucketFor("typing", …)` — pick any occasion no species voices; if `typing` is not a `NINA` key use one that is: `grep -n "^  [a-z]*:" kit/voices.ts | head`. The assertion is "a species voice missing the occasion gives Nina's bucket".) Add `fillArt` to the `../kit/sprites` import. Red: `slotOf`/`fillArt` don't exist.

Code:
- `kit/pets.ts`: `export const SLOT_SPECIES`; add after it
```ts
export type CatSpecies = (typeof SLOT_SPECIES.cat)[number]
/** the slot a species lives in, or undefined for a name no slot holds */
export const slotOf = (sp: string): "cat" | "dog" | undefined => (["cat", "dog"] as const).find((s) => (SLOT_SPECIES[s] as readonly string[]).includes(sp))
```
- `kit/sprites.ts`, above `SPECIES_ART`:
```ts
type Frames = string[][]
type Poses = { sit: Frames; blink: Frames; groom: Frames; walk: Frames; sleep: Frames; stretch: Frames; play: Frames }
/** a species may ship with `sit` alone: every pose it does not draw is its sit, and drawCat indexes frames modulo their count */
export const fillArt = (a: { sit: Frames } & Partial<Poses>): Poses => ({
  sit: a.sit, blink: a.blink ?? a.sit, groom: a.groom ?? a.sit, walk: a.walk ?? a.sit,
  sleep: a.sleep ?? a.sit, stretch: a.stretch ?? a.sit, play: a.play ?? a.sit,
})
```
- `kit/draw.ts` `drawCat`: `const rows0 = frames[i]!` → `const rows0 = frames[i % frames.length]!`.
- `kit/voices.ts`: change the `SPECIES_VOICE` annotation to `satisfies Record<string, { sassy: Record<string, readonly string[]>; sweet: Record<string, readonly string[]> }>` (drop the `Record<"rabbit" | "bird", …>` annotation so keys infer), and in `bucketFor`: `const own = (SPECIES_VOICE as Record<string, { sassy: Record<string, readonly string[]>; sweet: Record<string, readonly string[]> } | undefined>)[species]`.
- `kit/temperament.ts`: same move for `SPECIES_BASE` (`satisfies Record<string, Record<Dest, number>>`) and `speciesBase = (sp: string) => (SPECIES_BASE as Record<string, Record<Dest, number> | undefined>)[sp] ?? CAT_BASE`.
- `kit/sim.ts`: `Cat.species: CatSpecies` (`import type { CatSpecies } from "./pets"`).
- `tui/main.ts:1500`: `cycleVal(["cat","rabbit","bird"] as const, draft.species as "cat")` → `cycleVal(SLOT_SPECIES.cat, draft.species as CatSpecies)` (import `SLOT_SPECIES`, `type CatSpecies` from `../kit/pets`).
Existing test "every species has the frames drawCat reads": change its loop to assert the exact counts only for `["cat", "rabbit", "bird", "hamster", "baoaqu"].includes(sp)` and `length > 0` for the rest (the rock ships `sit` only).
Done = `bun test test/pets.test.ts test/voices.test.ts test/temperament.test.ts` green + typecheck. Commit: `office: a pet species is data — slotOf, fillArt, lookups keyed by name`.

## Task 3 — hamster (earthly, has walk)
Files: `kit/pets.ts`, `kit/sprites.ts`, `kit/voices.ts`, `kit/temperament.ts`, `test/pets.test.ts`.

Test first (in the "every species is data" describe's neighbour):
```ts
test("hamster ships: shelved, cat slot, draws in the room", () => {
  expect(SPECIES).toContain("hamster")
  expect(slotOf("hamster")).toBe("cat")
  expect(resolvePets({ cat: { species: "hamster" } }).cat.species).toBe("hamster")
  expect(bucketFor("pet", { warmth: 0, wits: 0, energy: 0 }, () => 0, "hamster")).toBe(SPECIES_VOICE.hamster.sassy.pet!)
  chance(0.999, () => {
    const room = new WideRoom(560), a = viewOf(office({ thinking: false }), 1)
    room.setPets(resolvePets({ cat: { species: "hamster" } }))
    for (let i = 0; i < 120; i++) { room.step(a); room.render(a, focus, measure) }
  })
})
```
Code:
- `kit/pets.ts`: `export const SPECIES = ["cat", "dog", "rabbit", "bird", "hamster"] as const`; `SLOT_SPECIES.cat` gains `"hamster"`.
- `kit/sprites.ts`, after `BIRD`:
```ts
// a hamster, facing right: k fur, w cheek and belly, e eye, p nose
const HAMSTER_SIT = [".......k.k", ".....kkkkk", "....kkkekk", "...kwwkkkp", "..kkwwwkkk", "..kkkkkkk.", "...kkkkkk.", "....k..k.."]
const swapLast = (rows: string[], last: string) => [...rows.slice(0, -1), last]
const hamsterSit = [HAMSTER_SIT, [".......kk.", ...HAMSTER_SIT.slice(1)], HAMSTER_SIT]
export const HAMSTER = {
  sit: hamsterSit,
  blink: [shut(HAMSTER_SIT)],
  groom: [shut(HAMSTER_SIT), shut(hamsterSit[1]!)],
  walk: [HAMSTER_SIT, swapLast(HAMSTER_SIT, "...k..k..."), HAMSTER_SIT, swapLast(HAMSTER_SIT, "...k..k...")],
  sleep: [["..........", "...kkkkk..", "..kkkkkkk.", ".kkkckkkkp", ".kkkkkkkkk", "..kkkkkkk."], ["..........", "..........", "..kkkkkkk.", ".kkkckkkkp", ".kkkkkkkkk", "..kkkkkkk."]],
  play: [hop(HAMSTER_SIT), HAMSTER_SIT],
  stretch: [hop(HAMSTER_SIT)],
}
```
  (every frame is 10 wide — the existing "every frame is a rectangle" test checks it.) Add `hamster: HAMSTER` to `SPECIES_ART`.
- `kit/voices.ts` `SPECIES_VOICE`: add
```ts
  hamster: {
    sassy: {
      pet: ["The cheeks are not for squeezing.", "Careful. I am storing something in there."],
      muse: ["The wheel has not moved me. I move the wheel.", "It is 3am. I have been up since 2."],
      wake: ["Is it night? It is always night.", "I was not asleep. I was in a burrow of the mind."],
      done: ["Done. Seeds. Now.", "Finished. I am hiding the proof in my cheek."],
    },
    sweet: {
      pet: ["*tiny sneeze* Again, please.", "So warm. I will keep this hand."],
      muse: ["Everyone is so big and so kind.", "I filled the cheeks with good feelings."],
      wake: ["Oh! Hello! I made a nest of your sleeve.", "Good morning, giants."],
      done: ["You did it! I did a lap of the wheel.", "Hooray! Seeds for everyone."],
    },
  },
```
- `kit/temperament.ts` `SPECIES_BASE`: `hamster: { play: 0.3, nap: 0.25, spot: 0.25, litter: 0.1, desk: 0.05, perch: 0.05 }`.
Done = `bun test test/pets.test.ts test/sprites.test.ts` green + typecheck. Commit: `office: the hamster — a species as data`.

## Task 4 — pet rock (no walk frames)
Same files as task 3.
Test: same shape, `"rock"`; plus `expect(SPECIES_ART.rock.walk).toBe(SPECIES_ART.rock.sit)` (the fallback) and `Object.values(speciesBase("rock"))` has `nap` ≥ 0.8.
Code:
- `SPECIES` += `"rock"`; `SLOT_SPECIES.cat` += `"rock"`.
- `kit/sprites.ts`: 
```ts
// a pet rock: k stone, e eyes, c eyes shut. It ships `sit` and a blink; every other pose is its sit (fillArt).
const ROCK_SIT = ["...kkkkk..", "..kkkkkkk.", ".kkekkekk.", ".kkkkkkkkk", "kkkkkkkkkk"]
export const ROCK = fillArt({ sit: [ROCK_SIT], blink: [shut(ROCK_SIT)] })
```
  `fillArt` is declared before `SPECIES_ART`; place `ROCK` after it, and `rock: ROCK` in `SPECIES_ART`.
- `SPECIES_VOICE.rock`: sassy `pet: ["...", "Stone. Silent. Still here."]`, `muse: ["...", "I have been a rock for four billion years."]`, `wake: ["...", "(the rock does not wake. it was never asleep.)"]`, `done: ["...", "(a rock is proud of you, in a way you cannot measure)"]`; sweet `pet: ["...", "(warmer than before. only slightly.)"]`, `muse: ["(a good rock sits.)"]`, `wake: ["(still a rock)"]`, `done: ["(it has chosen to stay near you)"]`.
- `SPECIES_BASE.rock = { nap: 0.8, spot: 0.06, play: 0.04, desk: 0.04, litter: 0.03, perch: 0.03 }` (it barely moves).
Done = `bun test test/pets.test.ts` + typecheck. Commit: `office: the pet rock — a species with a single pose`.

## Task 5 — A Bao A Qu (Borges, slow climber)
Same files. Test as task 3 with `"baoaqu"`; assert `SPECIES_ART.baoaqu.sit.length === 3`, `walk.length === 4` (the existing exact-count test now covers it too).
Code:
- `SPECIES` += `"baoaqu"`; `SLOT_SPECIES.cat` += `"baoaqu"`.
- `kit/sprites.ts`:
```ts
// A Bao A Qu (Borges, "The Book of Imaginary Beings"): a cloth-like creature that wakes on the stairs. k body, w the light in it,
// e eye, p mouth, t the fringe it trails.
const BAO_SIT = ["....kkk....", "...kkekp...", "...kkkkk...", "..kwwwwwk..", ".kkwwwwwkk.", ".kkkkkkkkk.", "kkkkkkkkkkk", "tt.t.t.t.tt"]
const baoSit = [BAO_SIT, swapLast(BAO_SIT, ".tt.t.t.tt."), BAO_SIT]
export const BAOAQU = {
  sit: baoSit,
  blink: [shut(BAO_SIT)],
  groom: [shut(BAO_SIT), shut(baoSit[1]!)],
  walk: [BAO_SIT, swapLast(BAO_SIT, ".tt.t.t.tt."), BAO_SIT, swapLast(BAO_SIT, ".tt.t.t.tt.")],
  sleep: [["...........", "...........", "....kkkkk..", "..kkkckkkp.", ".kwwwwwwwk.", "tkkkkkkkkkt"], ["...........", "...........", "...kkkkkk..", "..kkkckkkp.", ".kwwwwwwwk.", "tkkkkkkkkkt"]],
  play: [hop(BAO_SIT), BAO_SIT],
  stretch: [hop(BAO_SIT)],
}
```
  `swapLast` is task 3's helper. Add `baoaqu: BAOAQU` to `SPECIES_ART`.
- `SPECIES_VOICE.baoaqu`: sassy `pet: ["Climb me and I will glow. Barely.", "I only come alive on the stairs."]`, `muse: ["The Tower of Victory is the only honest place.", "I am the colour of whoever climbs me. Today, grey."]`, `wake: ["Someone is on the stairs. Oh. No.", "I was waiting. Slowly."]`, `done: ["Done. I felt that one in the fringe.", "Finished. Now carry me upstairs."]`; sweet `pet: ["*glows, a little*", "Oh. You're climbing. Do keep going."]`, `muse: ["I turn the colour of kind people.", "Some days the stairs are short and I am glad."]`, `wake: ["Good morning. I am nearly blue.", "Oh, you came up. Hello."]`, `done: ["You did it. I am nearly gold.", "Well climbed."]`.
- `SPECIES_BASE.baoaqu = { perch: 0.45, spot: 0.2, nap: 0.15, play: 0.1, desk: 0.05, litter: 0.05 }`.
Done = `bun test test/pets.test.ts` + typecheck. Commit: `office: A Bao A Qu — Borges' imaginary beast, a species as data`.

## Task 6 — shade: the seeded look within a species (spec §5 "look")
Files: `kit/pets.ts`, `kit/draw.ts`, `kit/sim.ts`, `test/pets.test.ts`.
A shade is `0..3`, a lighter fur for `k`/`t`; it is persisted per slot as `shade` and never a different sprite.
Test first:
```ts
test("a shade lightens the fur and never leaves 0..3", () => {
  expect(furOf(0)).toBe(ROLE.fieldInk)
  expect(new Set([0, 1, 2, 3].map(furOf)).size).toBe(4)
  expect(resolvePets({ cat: { shade: 2 } }).cat.shade).toBe(2)
  expect(resolvePets({ cat: { shade: 9 } }).cat.shade).toBe(0)
  expect(resolvePets({ cat: { shade: 1.5 } } as never).cat.shade).toBe(0)
  expect(resolvePets(undefined).dog.shade).toBe(0)
})
```
(`furOf` from `../kit/draw`, `ROLE` from `../kit/palette`.) Code:
- `kit/pets.ts`: `export const SHADES = 4`; `PetSetting` gains `shade?: number`; `resolveSlot` returns `shade: Number.isInteger(f.shade) && f.shade! >= 0 && f.shade! < SHADES ? f.shade! : (base.shade ?? 0)`.
- `kit/draw.ts`: `export const furOf = (shade: number) => (shade > 0 ? tint(ROLE.prose, ROLE.fieldInk, [0, 0.15, 0.3, 0.45][shade]!) : ROLE.fieldInk)`; in `drawCat`: `const fur = furOf(c.shade ?? 0)` and use `k: fur, t: fur` in the colour map (was `ROLE.fieldInk` twice).
- `kit/sim.ts`: `Cat` gains `shade?: number`; `setPets` also sets `this.cat.shade = p.cat.shade ?? 0`.
Done = `bun test test/pets.test.ts test/sim.test.ts` + typecheck. Commit: `office: a pet's shade — a seeded fur within the species`.

## Task 7 — `kit/store.ts`: the pure candidate (spec §5, §3 adopt)
File: new `kit/store.ts`, new `test/store.test.ts`.

Test first, `test/store.test.ts`:
```ts
import { expect, test } from "bun:test"
import { mkdtempSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { adopt, back, candidateOf, emptyStore, loadStore, pass, rename, roll, saveStore, SHELF, shelve, toggleLock } from "../kit/store"
import { resolvePets } from "../kit/pets"
import { loadPets, savePets } from "../tui/pets"

const s0 = { ...emptyStore(), species: "hamster" as const }
test("the same (species, seed, taken) is the same candidate", () => {
  expect(roll("hamster", "store:3", [])).toEqual(roll("hamster", "store:3", []))
  expect(roll("hamster", "store:3", []).name).toBeTruthy()
})
test("the axes stay in -2..2 and the shade in 0..3, over many seeds", () => {
  for (let n = 1; n < 200; n++) {
    const c = roll("rock", `store:${n}`, [])
    for (const a of Object.values(c.temperament)) expect(a >= -2 && a <= 2 && Number.isInteger(a)).toBe(true)
    expect(c.shade >= 0 && c.shade <= 3).toBe(true)
  }
})
test("names skip the taken ones", () => {
  const c = roll("hamster", "store:1", [])
  expect(roll("hamster", "store:1", [c.name]).name).not.toBe(c.name)
})
test("a pass keeps a locked row and moves the rest; back returns to the earlier seed", () => {
  const c0 = candidateOf(toggleLock(toggleLock(s0, "name"), "warmth"), [])
  const s1 = pass(toggleLock(toggleLock(s0, "name"), "warmth"), [])
  const c1 = candidateOf(s1, [])
  expect(c1.name).toBe(c0.name)
  expect(c1.temperament.warmth).toBe(c0.temperament.warmth)
  expect(s1.seed).toBe("store:2")
  expect(back(s1, []).seed).toBe("store:1")
  expect(back(s0, []).seed).toBe("store:1")
})
test("a locked name that is now taken is dropped, not kept", () => {
  const locked = toggleLock(s0, "name"), c = candidateOf(locked, [])
  expect(candidateOf(pass(locked, [c.name]), [c.name]).name).not.toBe(c.name)
})
test("shelve walks the cat-slot species and wraps; locks carry", () => {
  expect(SHELF).toContain("hamster")
  expect(SHELF).not.toContain("dog")
  let s = s0
  for (let i = 0; i < SHELF.length; i++) s = shelve(s, 1, [])
  expect(s.species).toBe("hamster")
  const named = rename(toggleLock(s0, "name"), "Biscuit")
  expect(candidateOf(shelve(named, 1, []), []).name).toBe("Biscuit")
})
test("adopt writes one slot; a species outside the slot is refused", () => {
  const c = candidateOf(rename(s0, "Biscuit"), [])
  expect(adopt(c, "cat")).toEqual({ cat: { name: "Biscuit", species: "hamster", temperament: c.temperament, shade: c.shade } })
  expect(adopt(c, "dog")).toBeNull()
  expect(adopt({ ...c, name: "  " }, "cat")).toBeNull()
})
test("an adopt through savePets replaces the cat and leaves the dog", () => {
  const dir = mkdtempSync(join(tmpdir(), "store-")), path = join(dir, "pets.json")
  try {
    savePets({ dog: { name: "Argos" } }, path)
    savePets(adopt(candidateOf(rename(s0, "Biscuit"), []), "cat")!, path)
    const p = resolvePets(loadPets(path))
    expect(p.cat.name).toBe("Biscuit"); expect(p.cat.species).toBe("hamster")
    expect(p.dog.name).toBe("Argos")
  } finally { rmSync(dir, { recursive: true, force: true }) }
})
test("store.json round-trips and a damaged one is the empty store", () => {
  const dir = mkdtempSync(join(tmpdir(), "store-")), path = join(dir, "store.json")
  try {
    const s = rename(toggleLock(pass(s0, []), "shade"), "Mochi")
    saveStore(path, s)
    expect(loadStore(path)).toEqual(s)
    saveStore(path, { ...s, species: "dog" } as never)
    expect(loadStore(path).species).toBe("cat")
    expect(loadStore(join(dir, "none.json"))).toEqual(emptyStore())
  } finally { rmSync(dir, { recursive: true, force: true }) }
})
```
Code, `kit/store.ts`:
```ts
// The pet store's candidate: a pure function of (species, seed, taken); store.json keeps only the species, seed, locks and
// edits, never the rendered card. roll() does no I/O and calls no model. kit/hall.ts is the same shape for people.
import { mkdirSync, readFileSync, writeFileSync } from "node:fs"
import { dirname } from "node:path"
import { SHADES, SLOT_SPECIES, SPECIES, slotOf, type PetsFile, type Species } from "./pets"
import { hash } from "./sprites"
import { clampAxis, type Temperament } from "./temperament"

export const NAMES = ["Biscuit", "Pumpkin", "Mochi", "Pebble", "Juniper", "Clementine", "Otto", "Waffles", "Sprout", "Nutmeg", "Pixel", "Marble", "Tofu", "Maple", "Sesame", "Basil"] as const
export type StoreRow = "name" | "warmth" | "wits" | "energy" | "shade"
export const STORE_ROWS: readonly StoreRow[] = ["name", "warmth", "wits", "energy", "shade"]
export type Candidate = { seed: string; species: Species; name: string; temperament: Temperament; shade: number }
export type Overrides = { name?: string; shade?: number; temperament?: Partial<Temperament> }
export type Store = { species: Species; seed: string; locks: StoreRow[]; overrides: Overrides }

/** what the store offers: the species the room's cat slot draws (the dog slot is Argos', not shelved) */
export const SHELF: readonly Species[] = SPECIES.filter((s) => slotOf(s) === "cat")
const LABEL: Record<string, string> = { rock: "pet rock", baoaqu: "A Bao A Qu" }
export const labelOf = (sp: string) => LABEL[sp] ?? sp

export const emptyStore = (): Store => ({ species: "cat", seed: "store:1", locks: [], overrides: {} })
const seedN = (seed: string) => Number(/^store:(\d+)$/.exec(seed)?.[1] ?? 0)

export function roll(species: Species, seed: string, taken: readonly string[]): Candidate {
  const h = (k: string) => hash(`${species}:${seed}:${k}`)
  const free = NAMES.filter((n) => !taken.includes(n))
  const name = free.length ? free[h("name") % free.length]! : `pet-${(h("n") % 9000) + 1000}`
  const axis = (k: string) => clampAxis((h(k) % 5) - 2)
  return { seed, species, name, temperament: { warmth: axis("warmth"), wits: axis("wits"), energy: axis("energy") }, shade: h("shade") % SHADES }
}

export function candidateOf(s: Store, taken: readonly string[]): Candidate {
  const c = roll(s.species, s.seed, taken), o = s.overrides
  return { ...c, name: o.name ?? c.name, shade: o.shade ?? c.shade, temperament: { ...c.temperament, ...o.temperament } }
}

/** what a lock keeps goes into the next overrides, so the stored store re-renders the same card after a restart */
function carry(s: Store, taken: readonly string[]): Overrides {
  const c = candidateOf(s, taken), o: Overrides = {}
  for (const r of s.locks) {
    if (r === "name") { if (!taken.includes(c.name)) o.name = c.name }
    else if (r === "shade") o.shade = c.shade
    else o.temperament = { ...o.temperament, [r]: c.temperament[r] }
  }
  return o
}

export const pass = (s: Store, taken: readonly string[]): Store => ({ ...s, seed: `store:${seedN(s.seed) + 1}`, overrides: carry(s, taken) })
export const back = (s: Store, taken: readonly string[]): Store => ({ ...s, seed: `store:${Math.max(1, seedN(s.seed) - 1)}`, overrides: carry(s, taken) })
export function shelve(s: Store, step: 1 | -1, taken: readonly string[]): Store {
  const i = SHELF.indexOf(s.species), species = SHELF[(i + step + SHELF.length) % SHELF.length]!
  return { ...s, species, overrides: carry(s, taken) }
}
export const toggleLock = (s: Store, r: StoreRow): Store => ({ ...s, locks: s.locks.includes(r) ? s.locks.filter((x) => x !== r) : [...s.locks, r] })
export const rename = (s: Store, name: string): Store => ({ ...s, overrides: { ...s.overrides, name } })

/** the pets.json fragment that adopts `c` into `slot` (replacing its occupant), or null: not that slot's species, or no name */
export function adopt(c: Candidate, slot: "cat" | "dog"): PetsFile | null {
  if (!(SLOT_SPECIES[slot] as readonly string[]).includes(c.species) || !c.name.trim()) return null
  return { [slot]: { name: c.name.trim(), species: c.species, temperament: { ...c.temperament }, shade: c.shade } }
}

function cleanOverrides(raw: unknown): Overrides {
  const r = (raw && typeof raw === "object" ? raw : {}) as Record<string, unknown>, o: Overrides = {}
  if (typeof r.name === "string" && r.name.trim()) o.name = r.name.trim()
  if (Number.isInteger(r.shade) && (r.shade as number) >= 0 && (r.shade as number) < SHADES) o.shade = r.shade as number
  if (r.temperament && typeof r.temperament === "object") {
    const t = r.temperament as Record<string, unknown>, out: Partial<Temperament> = {}
    for (const a of ["warmth", "wits", "energy"] as const) if (a in t) out[a] = clampAxis(Number(t[a]) || 0)
    if (Object.keys(out).length) o.temperament = out
  }
  return o
}

export function loadStore(path: string): Store {
  try {
    const j = JSON.parse(readFileSync(path, "utf8")), d = emptyStore()
    return {
      species: SHELF.includes(j.species) ? j.species : d.species,
      seed: typeof j.seed === "string" && /^store:\d+$/.test(j.seed) ? j.seed : d.seed,
      locks: Array.isArray(j.locks) ? STORE_ROWS.filter((r) => j.locks.includes(r)) : [],
      overrides: cleanOverrides(j.overrides),
    }
  } catch { return emptyStore() }
}

export function saveStore(path: string, s: Store): void {
  mkdirSync(dirname(path), { recursive: true })
  writeFileSync(path, JSON.stringify(s, null, 2) + "\n")
}
```
(`loadStore` returns `overrides: {}` as `{}` for the round-trip test: the test's `rename(...)` + shade lock after one pass yields `overrides: { shade, name }` — property order irrelevant to `toEqual`.) Add the staleness guard test to `test/store.test.ts`: `expect(SHELF.every((sp) => slotOf(sp) === "cat")).toBe(true)`.
Done = `bun test test/store.test.ts` green + typecheck. Commit: `office: kit/store — the pet store's seeded candidate, shelf and adopt`.

## Task 8 — `tui/store.ts`: the card as rows
Files: `tui/hall.ts` (export `halfBlocks` — one word), new `tui/store.ts`, new `test/store-view.test.ts`.
Test first:
```ts
import { expect, test } from "bun:test"
import { candidateOf, emptyStore, shelve } from "../kit/store"
import { STORE_VIEW_ROWS, storeRows, stepStoreRow } from "../tui/store"

const text = (r: { segs: { s: string }[] }) => r.segs.map((s) => s.s).join("")
const card = (sp: "hamster" | "rock" | "baoaqu" | "cat" = "hamster") => candidateOf({ ...emptyStore(), species: sp }, [])
test("one row per line of the card: species, slot, name, three axes, shade, a line in its voice", () => {
  const rows = storeRows(card(), ["warmth"], "Nina", "Seeds. Now.")
  expect(rows).toHaveLength(STORE_VIEW_ROWS)
  expect(rows.map((r) => r.lock)).toEqual([null, null, "name", "warmth", "wits", "energy", "shade", null])
  expect(text(rows[1]!)).toContain("cat slot")
  expect(text(rows[1]!)).toContain("Nina leaves by the door")
  expect(text(rows[3]!)).toContain("locked")
  expect(text(rows[2]!)).not.toContain("locked")
  expect(text(rows[7]!)).toContain("Seeds. Now.")
})
test("every shelved species draws, sit beside walk, in half-blocks; a rock sits twice", () => {
  for (const sp of ["cat", "hamster", "rock", "baoaqu"] as const) {
    const rows = storeRows(card(sp), [], "Nina", "")
    expect({ sp, drawn: rows.some((r) => r.segs.some((s) => s.s === "▀" || s.s === "▄")) }).toEqual({ sp, drawn: true })
  }
})
test("stepStoreRow wraps both ways", () => {
  expect(stepStoreRow(0, -1)).toBe(STORE_VIEW_ROWS - 1)
  expect(stepStoreRow(STORE_VIEW_ROWS - 1, 1)).toBe(0)
})
```
Code, `tui/store.ts`:
```ts
// The pet store's card as rows: the species' sit and walk frames (half-block pixels) beside one row per field.
// Pure — main.ts owns the keys and the state. tui/hall.ts is the same shape for people.
import { furOf } from "../kit/draw"
import { ROLE } from "../kit/palette"
import { dots, SHADES, slotOf } from "../kit/pets"
import { SPECIES_ART } from "../kit/sprites"
import { labelOf, type Candidate, type StoreRow } from "../kit/store"
import { halfBlocks } from "./hall"
import type { Seg } from "./term"

export type StoreViewRow = { segs: Seg[]; lock: StoreRow | null }
export const STORE_VIEW_ROWS = 8
export const stepStoreRow = (i: number, d: number) => (i + d + STORE_VIEW_ROWS) % STORE_VIEW_ROWS

/** halfBlocks folds two pixel rows to a cell; an odd-height frame gets an empty row under it */
const even = (rows: string[]) => (rows.length % 2 ? [...rows, ".".repeat(rows[0]!.length)] : rows)

/** `occupant` is who the adopt would replace; `line` one line in the species' voice (previewOf) */
export function storeRows(c: Candidate, locks: readonly StoreRow[], occupant: string, line: string): StoreViewRow[] {
  const art = SPECIES_ART[c.species as keyof typeof SPECIES_ART], fur = furOf(c.shade)
  const paint = { k: fur, t: fur, e: ROLE.body, c: ROLE.inactive, w: ROLE.edge, p: ROLE.attention }
  const views = [art.sit[0]!, art.walk[0]!].map((f) => halfBlocks(even(f), paint))
  const left = (i: number): Seg[] => views.flatMap((v, n) => [...(n ? [{ s: "  " }] : []), ...(v[i] ?? [{ s: " ".repeat(v[0]?.length ?? 0) }])])
  const label = (l: string, v: string, locked: boolean): Seg[] => [
    { s: l.padEnd(11), fg: ROLE.inactive }, { s: v }, ...(locked ? [{ s: "  locked", fg: ROLE.meta }] : []),
  ]
  const lockable = (r: StoreRow, l: string, v: string) => ({ segs: label(l, v, locks.includes(r)), lock: r as StoreRow | null })
  const body: StoreViewRow[] = [
    { segs: label("species", labelOf(c.species), false), lock: null },
    { segs: label("slot", `the ${slotOf(c.species)} slot — ${occupant} leaves by the door`, false), lock: null },
    lockable("name", "name", c.name),
    ...(["warmth", "wits", "energy"] as const).map((a) => lockable(a, a, dots(c.temperament[a]))),
    lockable("shade", "shade", `${c.shade + 1} of ${SHADES}`),
    { segs: label("says", line, false), lock: null },
  ]
  return body.map((r, i) => ({ ...r, segs: [...left(i), { s: "   " }, ...r.segs] }))
}
```
`tui/hall.ts`: `function halfBlocks` → `export function halfBlocks`. Colour is never the only signal: the locked state is the word `locked`, the shade the number (`test/wcag.test.ts` rules).
Done = `bun test test/store-view.test.ts test/hall-view.test.ts test/wcag.test.ts` green + typecheck. Commit: `office: tui/store — the pet store card as rows`.

## Task 9 — the view and its keys in `tui/main.ts` (hook-in only)
File: `tui/main.ts`. Stay clear of #255's `rooms/wide.ts`. No new unit test (main.ts is the TUI loop; its parts are tested in 7–8); verify by typecheck + the live read-back below.
Edits, in file order:
1. Imports: `import { adopt, back as storeBack, candidateOf as storeCandidate, loadStore, pass as storePass, rename, saveStore, shelve, toggleLock as storeToggle, type Store } from "../kit/store"`; `import { stepStoreRow, STORE_VIEW_ROWS, storeRows } from "./store"`; add `slotOf` to the `../kit/pets` import. (`STORE_VIEW_ROWS` is only needed if used for clamping; drop it if unused — `noUnusedLocals` is on.)
2. `Mode`: `| { kind: "hall" } | { kind: "hall-pile" } | { kind: "store" }`.
3. After `const HALL = …`: `const STORE = process.env.TLON_STORE ?? join(CONFIG, "store.json")`.
4. After `hallHire()`:
```ts
let store: Store = loadStore(STORE), storeSeen = hallSignature(STORE)
/** names a new pet must not take: the bench's and the dog's */
const storeTaken = () => [...all.bench.map((b) => b.name), (petsNow ?? resolvePets(loadPets())).dog.name]
function storeSet(s: Store) { store = s; saveStore(STORE, s); storeSeen = hallSignature(STORE) }
/** a hand edit of store.json shows up on the next poll; true when it did */
function followStore(): boolean {
  const seen = hallSignature(STORE)
  if (seen === storeSeen) return false
  storeSeen = seen; store = loadStore(STORE)
  return true
}
```
5. Home actions, after the `h` hall action: `{ key: "P", label: "the pet store", run: () => open({ kind: "store" }) },`
6. `detail()`, next to `case "hall"`:
```ts
    case "store": {
      const taken = storeTaken(), c = storeCandidate(store, taken), slot = slotOf(c.species) ?? "cat"
      const occupant = (petsNow ?? resolvePets(loadPets()))[slot]
      const rows: Row[] = storeRows(c, store.locks, occupant.name, previewOf({ name: c.name, species: c.species, temperament: c.temperament }, previewTick).line).map((r) => ({
        segs: r.segs,
        open: r.lock ? () => { storeSet(storeToggle(store, r.lock!)); draw() } : undefined,
      }))
      return {
        title: `PET STORE · ${store.seed}`, rows,
        actions: [
          { key: "left", label: "previous species", run: () => { storeSet(shelve(store, -1, storeTaken())); draw() } },
          { key: "right", label: "next species", run: () => { storeSet(shelve(store, 1, storeTaken())); draw() } },
          { key: "up", label: "pass", run: () => { storeSet(storePass(store, storeTaken())); draw() } },
          { key: "down", label: "back", run: () => { storeSet(storeBack(store, storeTaken())); draw() } },
          { key: "space", label: "lock / unlock the row", run: () => rows[sel]?.open?.() },
          { key: "e", label: "rename", run: () => ask("name", (s) => { if (s.trim()) { storeSet(rename(store, s.trim())); draw() } }, { text: c.name }) },
          back1,
        ],
      }
    }
```
   Adopt (`enter`) arrives in task 10. `previewTick` is the card clock the pet card already advances; if it only ticks on the pet card, reuse the same `every()` that advances it (`grep -n previewTick tui/main.ts`) by also advancing while `mode.kind === "store"`.
7. `onKey`: `if (mode.kind === "hall" && (k === "tab" || k === "backtab")) {…}` → add a twin line below it for `"store"` using `stepStoreRow`.
8. The poll: `…|| followHall()) {` → `…|| followHall() || followStore()) {`.
Done = typecheck green and `bun test` green (nothing else moves). Live: `mise run office:sandbox`, `P`: the card draws the cat; `→` shows hamster, pet rock, A Bao A Qu; `↑`/`↓` change the seed; `space` on the name row shows `locked`; `esc` leaves. (Use the `drive-office` skill to read the screen back headlessly.) Commit: `office: the pet store view — P from home, browse and roll`.

## Task 10 — adopt, with the confirm (spec §3)
File: `tui/main.ts`.
Add after `followStore()`:
```ts
/** ⏎: adopt the shown candidate into its slot; the occupant leaves by the door, once the operator says y */
function storeAdopt() {
  const taken = storeTaken(), c = storeCandidate(store, taken), slot = slotOf(c.species)
  const file = slot ? adopt(c, slot) : null
  if (!slot || !file) { status = `${c.name} can't be adopted here`; return draw() }
  const old = (petsNow ?? resolvePets(loadPets()))[slot].name
  ask2(`${old} leaves by the door. adopt ${c.name}?`, () => {
    savePets(file)
    petsSeen = ""; followPets(); roomChanged = true
    storeSet(storePass(store, [...taken, c.name]))
    status = `adopted ${c.name}`
    draw()
  })
}
```
and in the store's `actions`, before `back1`: `{ key: "enter", label: "adopt", run: storeAdopt },`. (`own` is checked before the default `enter` handling, so ⏎ adopts; row `open` stays on `space`.) `savePets(file)` uses `PETS_PATH`, which is the sandbox file in `--sandbox` (task 1).
Live check, headless (`drive-office`): `mise run office:sandbox`, `P`, `→` (hamster), `enter`, `y`; then `cat $TMPDIR/tlon-sandbox/pets.json` shows `"species": "hamster"` with the rolled name, and `~/.config/tlon/pets.json` is unchanged (`stat` its mtime before and after). Post the read-back on the thread.
Done = typecheck + `bun test` green and the read-back above. Commit: `office: adopt from the pet store — the slot's occupant leaves by the door`.

## Task 11 — docs in sync, and the gate
Files: `office/AGENTS.md`.
- After the hiring-hall paragraph (the one ending "…`Server.Soul.create`, souls-step-2) is not built yet."), add:
  `The pet store (`P` from home; `kit/store.ts` the pure candidate — `roll(species, seed, taken)`, seeded, no model, no I/O — `tui/store.ts` its card rows): ←/→ the shelf (the cat slot's species: cat, rabbit, bird, hamster, pet rock, A Bao A Qu), ↑ pass, ↓ back, space locks a row, `e` renames, ⏎ adopts into the species' slot — the occupant leaves by the door (one pet per slot, no history). `store.json` (`TLON_STORE`) holds species + seed + locks + edits. A new species is data: frames in `SPECIES_ART`, a `SPECIES_VOICE` pack, a `SPECIES_BASE` row and a `SLOT_SPECIES` entry (`fillArt` lets it ship `sit` alone).`
- In the sandbox sentence: "keeps its looks, souls and hall" → "keeps its looks, souls, hall, pets and store".
Done = `mise run office:check` green (both clock hours), then `mise run check`. Commit: `office: AGENTS.md names the pet store beside the hall`.

## Spec checks → tasks
(1) store.test.ts → 7 · (2) species guard → 2–5 · (3) adopt pure → 7 · (4) sandbox path → 1 + 10 live · (5) wcag → 8 · (6) gate + card seen once → 9–11.

## Out (unchanged from the spec)
Species batches (slice 2), pet accessories (3), N pets (4), per-species home tiles, shelving the dog, a replaced-pet history.
