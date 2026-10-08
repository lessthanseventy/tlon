# Dollies step 7 — pets and temperament (§5.2–5.3, §8 step 7)

Plan against origin/main. **Nothing here touches `Server.Life` or `/api/life`** (the life track,
#133/#177, is not on main). All work is `office/`; gate is `mise run office:check`
(typecheck + `bun test` at 03:00 and 15:00). Tests live in `office/test/*.test.ts` (bun:test).

## Scope calls (assumptions — say if wrong)

1. **Two slots, not a menagerie.** The room has one cat-family pet (`Sim.cat`) and one dog (Argos,
   `kit/pets.ts`). Step 7 makes the *cat slot* species-swappable (`cat | rabbit | bird`) and gives
   both slots a name + temperament from `pets.json`. A pet **array** (`menagerie`, `pond-life`, `cat-only`
   with 2 pets) and fish/duck/capybara need the tank/pond tiles + a multi-pet sim: **not step 7**,
   named open in PR 5's doc edit.
2. **The two new species are rabbit and bird** — they use only places the cat already has
   (`nap`, `play`, `perches`, `spots`), so no new tiles. (`bird` = perch-heavy; `rabbit` = sit/hop/sleep.)
3. **Axes this step:** warmth → voice bucket + `byYou` rate; energy → mode table + zoomies + fuss
   rate; wits → how often a walk is aimless (`spots`) + voice bucket. *Noticing a due routine* (needs
   Life) and *corkboard line pointedness* (server, `Server.Office.Banter`) are **blocked/later**. Stroll
   radius is dropped (YAGNI: no radius exists in `stepCat`).
4. **No file == today, byte for byte.** The Sim's unset temperament is `{0,0,0}` and its tables at that
   point equal today's thresholds, so `test/golden.json` does **not** move in any PR (prove each time:
   `git diff --stat test/golden.json` empty after `mise run office:golden`). `classic nina`
   (sassy, sharp, playful) is the named *preset* on the card; it is only applied when `pets.json` exists.
   This stack touches no floor rendering, so no floor-render PR ordering applies.
5. **Preview = text row, ticking** (cards are text rows, `Row.segs`; the look card draws no sprites).
   The preview is a pure function of (pet, tick) so it is unit-testable and drivable.

## Stack (each PR on the last, rebase-only, `gh stack`)

PR1 temperament core → PR2 voice buckets → PR3 pets.json + presets → PR4 pet card → PR5 species.
Each task below = one commit. Commit trailer per repo law.

---

## PR 1 — temperament core + the mode table (check: the 10k-tick test)

### T1.1 `office/kit/temperament.ts` (new) — test first

`office/test/temperament.test.ts`:

```ts
import { describe, expect, test } from "bun:test"
import { CAT_BASE, destWeights, pickDest, type Dest, type Temperament } from "../kit/temperament"

const T = (warmth: number, wits: number, energy: number): Temperament => ({ warmth, wits, energy })
const DESTS = Object.keys(CAT_BASE) as Dest[]

/** a seeded rng (mulberry32) so 10k ticks are the same ticks every run */
function rng(seed: number) { return () => { seed |= 0; seed = (seed + 0x6d2b79f5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296 } }
function share(t: Temperament, n = 10_000) {
  const r = rng(7), hits = Object.fromEntries(DESTS.map((d) => [d, 0])) as Record<Dest, number>
  for (let i = 0; i < n; i++) hits[pickDest(t, r())]++
  return Object.fromEntries(DESTS.map((d) => [d, hits[d] / n])) as Record<Dest, number>
}

describe("destWeights", () => {
  test("a neutral temperament is exactly today's table", () => {
    expect(destWeights(T(0, 0, 0))).toEqual(CAT_BASE)
  })
  test("always sums to 1 and stays positive across the whole cube", () => {
    for (const w of [-2, 0, 2]) for (const i of [-2, 0, 2]) for (const e of [-2, 0, 2]) {
      const ws = destWeights(T(w, i, e)), sum = Object.values(ws).reduce((a, b) => a + b, 0)
      expect(sum).toBeCloseTo(1, 10)
      for (const v of Object.values(ws)) expect(v).toBeGreaterThan(0)
    }
  })
})

describe("over 10k ticks the table moves the way the design says", () => {
  test("energy: lazy naps more and plays less than playful", () => {
    const lazy = share(T(0, 0, -2)), playful = share(T(0, 0, 2))
    expect(lazy.nap).toBeGreaterThan(playful.nap + 0.1)
    expect(playful.play).toBeGreaterThan(lazy.play + 0.05)
    expect(playful.perch).toBeGreaterThan(lazy.perch)
  })
  test("wits: dim wanders (spots) more than sharp", () => {
    expect(share(T(0, -2, 0)).spot).toBeGreaterThan(share(T(0, 2, 0)).spot + 0.05)
  })
  test("warmth and wits leave the nap/play balance alone", () => {
    const a = share(T(-2, 0, 0)), b = share(T(2, 0, 0))
    expect(Math.abs(a.nap - b.nap)).toBeLessThan(0.02)
    expect(Math.abs(a.play - b.play)).toBeLessThan(0.02)
  })
  test("the empirical share tracks the weights", () => {
    const t = T(1, -1, 2), w = destWeights(t), s = share(t)
    for (const d of DESTS) expect(Math.abs(s[d] - w[d])).toBeLessThan(0.02)
  })
})
```

Run (red — module missing): `~/projects/menard/bin/menard`-free office loop: `cd office && bun test test/temperament.test.ts`.

`office/kit/temperament.ts`:

```ts
// A pet's three axes (design §5.3), each -2..2. They are policy over the sim's chance tables, not
// new behaviours: a neutral temperament reproduces the tables exactly.
export type Temperament = { warmth: number; wits: number; energy: number }
export const AXES = ["warmth", "wits", "energy"] as const
export type Axis = (typeof AXES)[number]

/** where a pet walks to next, `stepCat`'s table in the order it is read */
export type Dest = "nap" | "desk" | "perch" | "play" | "litter" | "spot"
export const CAT_BASE: Record<Dest, number> = { nap: 0.45, desk: 0.1, perch: 0.15, play: 0.1, litter: 0.05, spot: 0.15 }

export const clampAxis = (n: number) => Math.max(-2, Math.min(2, Math.round(n)))
/** 1 at 0, 0.5..1.5 across the axis: every knob is this one function */
export const lean = (axis: number, strength = 0.25) => 1 + axis * strength

/** energy: lazy → nap, playful → play/perch; wits: dim → aimless `spot`. Normalised to sum 1. */
export function destWeights(t: Temperament, base: Record<Dest, number> = CAT_BASE): Record<Dest, number> {
  const w: Record<Dest, number> = {
    nap: base.nap * lean(-t.energy), desk: base.desk,
    perch: base.perch * lean(t.energy), play: base.play * lean(t.energy),
    litter: base.litter, spot: base.spot * lean(-t.wits),
  }
  const sum = Object.values(w).reduce((a, b) => a + b, 0)
  return Object.fromEntries(Object.entries(w).map(([k, v]) => [k, v / sum])) as Record<Dest, number>
}

/** `r` in [0,1): the cumulative walk over `destWeights` — with neutral weights, `stepCat`'s old thresholds */
export function pickDest(t: Temperament, r: number, base?: Record<Dest, number>): Dest {
  const w = destWeights(t, base)
  let acc = 0
  for (const d of Object.keys(w) as Dest[]) { acc += w[d]; if (r < acc) return d }
  return "spot"
}
```

Note: `CAT_BASE` sums to 1.00 and `toEqual` needs the neutral normalisation to be exact — if float
error breaks the first test, compare with `toBeCloseTo` per key (don't loosen the others).
Green: `bun test test/temperament.test.ts`. Commit `office: temperament axes and the destination table`.

### T1.2 wire `Sim.stepCat` to it — test first

`office/test/sim.test.ts` (append; reuse its existing room builder — read the file's top for the helper):
two tests via `chance()`-style fixed `Math.random`: with `r = 0.50` (inside `desk` at neutral:
.45–.55) the default cat walks to `plan.cat.desk`; a `lazy` cat (`energy -2`) at `r = 0.50` goes to
`nap` instead (nap weight 0.45·1.5/… ≥ 0.5). Needs a way to set the temperament: add
`setTemperament(t: Temperament)` on `Sim` (red: not a function).

`office/kit/sim.ts` edits:
- `import { pickDest, lean, type Temperament } from "./temperament"`
- field `protected temperament: Temperament = { warmth: 0, wits: 0, energy: 0 }` and
  `setTemperament(t: Temperament) { this.temperament = t }`.
- replace the `r < 0.45 ? p.nap : r < 0.55 ? p.desk : …` tail of the `const to = …` chain with
  `d = pickDest(this.temperament, r)` and `d === "nap" ? p.nap : d === "desk" ? p.desk : d === "perch" ? pick(p.perches) : d === "play" ? p.play : d === "litter" ? p.litter : pick(p.spots)`
  (the `cold`/`company` arms stay first). Reuse `r` — **no new `Math.random()` call**, which would shift a seeded
  sequence; at neutral it is then identical to the old thresholds.
- zoomies: `r < (nightOwl(...) ? 0.15 : 0.05) * lean(this.temperament.energy)`.
- fuss start: `Math.random() > 0.0015 * lean(this.temperament.energy)` (the `continue` guard).
- desk purr: `Math.random() < 0.02 * lean(this.temperament.warmth)`.

Done: `bun test` green incl. `wide.test.ts` golden (**unchanged `golden.json`** — prove with `git diff --stat test/golden.json` empty). Commit `office: the cat's day follows her temperament`.

---

## PR 2 — voice buckets (check: line pick test)

### T2.1 `kit/voices.ts` — test first
`office/test/voices.test.ts` (new):
```ts
import { describe, expect, test } from "bun:test"
import { bucketFor, NINA, SWEET } from "../kit/voices"
describe("bucketFor", () => {
  test("warmth picks sweet or sassy in proportion, 10k draws", () => {
    let sweet = 0; let s = 1; const r = () => ((s = (s * 48271) % 2147483647) / 2147483647)
    for (let i = 0; i < 10_000; i++) if (bucketFor("pet", { warmth: 2, wits: 0, energy: 0 }, r) === SWEET.pet) sweet++
    expect(sweet / 10_000).toBeGreaterThan(0.85)
  })
  test("neutral-warmth Nina, and the classic -2 warmth, never go sweet", () => {
    for (let i = 0; i < 200; i++) expect(bucketFor("pet", { warmth: -2, wits: 0, energy: 0 }, Math.random)).toBe(NINA.pet)
  })
  test("an occasion with no sweet bucket falls back to NINA's", () => {
    expect(bucketFor("web", { warmth: 2, wits: 0, energy: 0 }, () => 0)).toBe(NINA.web)
  })
})
```
Probability sweet = `(warmth + 2) / 4 * 0.9` capped so −2 → 0 exactly, +2 → 0.9; the default
`classic nina` has `warmth −2` so today's lines are untouched (neutral for **Nina** is not axis 0 —
that's why T1.2's `{0,0,0}` default is only the sim's *unset* value; PR3 sets Nina to classic).
`office/kit/voices.ts` adds:
```ts
export const SWEET: Partial<Record<keyof typeof NINA, readonly string[]>> = {
  pet: ["Oh, that's lovely. Don't stop.", "prrr... you're my favourite person.", "Yes please. Right there."],
  wake: ["Oh! Hello. Was I snoring?", "Mm. Good morning, everyone."],
  muse: ["I love it when everyone's here.", "The sunbeam is warm and so are you.", "Good day for a good nap."],
  done: ["Well done. Genuinely.", "Done! I knew you could."],
  cheer: ["{name}, you're doing so well.", "{name}! I believe in you. Truly."],
}
export function bucketFor(occasion: string, t: Temperament, rand: () => number): readonly string[] {
  const sassy = (NINA as Record<string, readonly string[]>)[occasion]!, sweet = (SWEET as Record<string, readonly string[]>)[occasion]
  return sweet && rand() < ((t.warmth + 2) / 4) * 0.9 ? sweet : sassy
}
```
(`import type { Temperament } from "./temperament"`.) Add `dim/sharp/lazy/playful` muse buckets only if
asked — the design names six buckets; this step ships `sassy`(=NINA)/`sweet` and a `MUSE_BY_AXIS`
of 4 lines each for the other four, picked in `muse` when `|axis| ≥ 1` (add the same style test).

### T2.2 use it in `Sim.line`'s `canned`
`catSay(this.line("Nina", occasion, NINA.x))` call sites pass `NINA.x` as canned. Minimal change: in
`Sim.line`, when `pet === "Nina"` and `canned === (NINA as any)[occasion]`, swap `canned` for
`bucketFor(occasion, this.temperament, Math.random)`. One edit, ~3 lines; no call site changes.
Test: `sim.test.ts` — with `warmth 2` and `Math.random → 0`, `room.pet()` says a `SWEET.pet` line.
Done: `bun test` green, golden unchanged. Commit `office: Nina's voice follows her warmth`.

---

## PR 3 — `pets.json`, presets, species table (check: round trip + live re-read)

### T3.1 `office/kit/pets.ts` additions — test first (`test/pets.test.ts`, append)
```ts
describe("pet presets", () => {
  test("absent file is the default preset: Nina classic, Argos", () => {
    expect(resolvePets(undefined)).toEqual(DEFAULT_PETS)
    expect(DEFAULT_PETS.cat.temperament).toEqual(TEMPERAMENTS.classic)
  })
  test("a file is a preset plus overrides — only the change is read", () => {
    const p = resolvePets({ preset: "nina-and-argos", cat: { temperament: "zen", name: "Mimi" } })
    expect(p.cat.name).toBe("Mimi"); expect(p.cat.temperament).toEqual(TEMPERAMENTS.zen); expect(p.dog.name).toBe("Argos")
  })
  test("axes are clamped and junk is ignored", () => {
    expect(resolvePets({ cat: { temperament: { warmth: 9, wits: "x", energy: -9 } } } as never).cat.temperament).toEqual({ warmth: 2, wits: 0, energy: -2 })
  })
})
```
Code (in `kit/pets.ts`):
```ts
import { clampAxis, type Temperament } from "./temperament"
export type Species = "cat" | "dog" | "rabbit" | "bird"           // grows with the roster, never ahead of it
export type PetSetting = { name: string; species: Species; temperament: Temperament }
export type PetsFile = { preset?: string; cat?: Partial<Omit<PetSetting, "temperament">> & { temperament?: string | Partial<Temperament> }; dog?: PetsFile["cat"] }
export type Pets = { cat: PetSetting; dog: PetSetting }

/** the six presets from §6; `menace`/`gremlin` etc. are named here so the card can cycle them */
export const TEMPERAMENTS: Record<string, Temperament> = {
  classic: { warmth: -2, wits: 1, energy: 1 },   // "classic nina": sassy, sharp, playful
  menace: { warmth: -2, wits: 2, energy: 2 },
  "golden retriever": { warmth: 2, wits: -2, energy: 2 },
  "old cat": { warmth: 2, wits: 2, energy: -2 },
  gremlin: { warmth: -1, wits: -2, energy: 2 },
  zen: { warmth: 1, wits: 1, energy: -1 },
}
export const DEFAULT_PETS: Pets = {
  cat: { name: CAT_NAME, species: "cat", temperament: TEMPERAMENTS.classic! },
  dog: { name: DOG_NAME, species: "dog", temperament: { warmth: 2, wits: -1, energy: 1 } },
}
export const PRESETS: Record<string, Pets> = { "nina-and-argos": DEFAULT_PETS }
export function resolvePets(f: PetsFile | undefined): Pets { /* base = PRESETS[f?.preset] ?? DEFAULT_PETS; per slot: name string, species in SPECIES, temperament string→TEMPERAMENTS else partial → clampAxis(Number(x)) with NaN→0 */ }
```
Write `resolvePets` fully (≈20 lines) in the commit; the test above is its spec. **Golden rule:** `classic` is not `{0,0,0}`, so `followPets` (T3.2) calls `setPets` only when `pets.json` exists; with no file the Sim keeps its unset `{0,0,0}` and goldens hold. Comment that on `followPets`.

Commit `office: pet presets and temperaments, resolved like looks`.

### T3.2 the file, live — `office/tui/pets.ts` (new), same shape as `tui/home.ts` + `followLooks`
Test `office/test/pets.test.ts` (append): `savePets` then `loadPets(path)` round-trips an override;
absent/garbage path → `undefined`. Code: `PETS_PATH = process.env.TLON_PETS ?? join(XDG_CONFIG_HOME ?? ~/.config, "tlon/pets.json")`;
`loadPets(path): PetsFile | undefined`; `savePets(file, path)` writes **only the override** (read-merge-write
like `saveLook`, `main.ts:64`). `tui/main.ts`: add `followPets()` beside `followLooks()` (line ~148;
same `realpath@mtime` seen-check, include it in the 1000 ms `setInterval` at ~1655) which calls
`room().setPets(resolvePets(loadPets()))`. `Sim.setPets({cat})` → `setTemperament(cat.temperament)` and sets the displayed cat name
(`CAT_NAME` uses in `draw.ts:214`, `sim.ts` `line("Nina",…)` → a `this.catName`). Done: file edit changes behaviour
within a second (T4 drives it). Commit `office: pets.json, polled live like looks.json`.

---

## PR 4 — the pet card + live preview (check: driven and read back — `drive-office` skill)

### T4.1 preview as a pure function — test first
`test/pets.test.ts`: `previewOf(setting, tick)` returns `{ mode: "sleep"|"sit"|"play"|"zoom"|"walk", line: string }`,
deterministic per (setting, tick, seed); a `{-2,·,-2}` pet over ticks 0..39 spends more of them asleep than a
`{·,·,+2}` pet; a `warmth −2` line ∈ `NINA.*`, a `warmth +2` one eventually ∈ `SWEET.*` (loop 200 seeds).
Code: `previewOf` in `kit/pets.ts` = `pickDest`→mode map (`nap→sleep, play→play, perch→sit, desk→sit, litter→sit,
spot→walk`) every 10 ticks + `bucketFor("muse"|"pet", …)` with a seeded rng (reuse the mulberry32 from the test as `kit/rng.ts` — extract, 1 caller more than the test is fine; do not export otherwise).

### T4.2 the card — `tui/main.ts` `case "pet"` and the `Mode` union
- Add axis helpers to `kit/pets.ts`: `dots(n)` → `"●●○○○"` style five-dot string (`-2..2` → position), `cycleAxis(n, ±1)` clamped.
- In `case "pet"` for `who: "cat"`, add `petDraft` (module `let petDraft: PetSetting | null`, like `lookDraft` at `main.ts:86`, cleared on close at `:272`) and rows (copy the look card's `field(...)` helper, `main.ts:1112`):
  `name` (a text input via `tui/editor.ts`, the finder's input; if that proves awkward in a row, defer rename to a follow-up and say so in the PR), `species` (cycle `SPECIES`), `temperament preset` (cycle `Object.keys(TEMPERAMENTS)`), then `warmth/wits/energy` rows (dim label, `dots`, `←/→` via `open:` cycling like the look rows; extend the key handler where look rows take arrows — grep `cycleVal`), and a **preview row** `{ segs: [dim("preview"), plain(mode glyph + " " + line)] }`.
- Preview ticks: while `mode.kind==="pet" && petDraft`, the existing 1 s `setInterval` (and the room's frame timer, whichever redraws cards) bumps `previewTick` and `draw()`s. If the card only redraws on input, add the redraw to the existing interval guarded by that condition (3 lines).
- Actions: `s` save (`savePets({preset, cat: {name, species, temperament: <preset name if untouched else axes>}})`, `back()`, `roomChanged = true`), keep the existing pat/zoomies/yarn/nap/cheer actions, plus `f` fork-as-full-file (§6) **only if** trivial; else not now.
- Argos' card gets no axes in step 7 (his table lives in `stepDog`; follow-up). `DEFAULT_PETS.dog.temperament` is data only.

### T4.3 drive it — `drive-office` skill
Script (verbatim in the PR body): start the TUI against a throwaway `TLON_PETS=$TMPDIR/pets.json`
(and `XDG_CONFIG_HOME` likewise), click Nina → `p`… read the screen back: the card shows `warmth ●○○○○`.
Press → on warmth until `●●●●●`; `preview` row text changes within ~3 s to a SWEET line (run up to 10 s); `s`;
`cat $TLON_PETS` shows `"warmth": 2`; the room's next Nina line is from `SWEET` (via `Pets` test hook or screen). Paste
screen captures as evidence. Also `test/tui.test.ts`: add one test that the `pet` card for `cat` lists the three axis rows and a `save` action (follow its existing card-shape tests).
Docs in this PR: `office/AGENTS.md` — add `kit/temperament.ts`, `pets.json` (`TLON_PETS`), the pet card, to the kit/TUI bullets. Commit `office: the pet card with a live preview`.

---

## PR 5 — two species: rabbit and bird (check: sprites + modes + one driven look)

### T5.1 species table, test first
`test/pets.test.ts`: every frame of `RABBIT` and `BIRD` is a rectangle (extend the existing "every frame is a rectangle" test to `SPECIES_ART`); each species has the frames `drawCat` reads: `sit[3] walk[4] sleep[2] play[2] stretch[1] groom[2] blink[1]` (reuse a frame by reference where the animal doesn't have the pose — a bird "stretches" by spreading `sit`); `speciesBase(sp)` returns a dest table summing to 1 (bird: `perch 0.5, nap 0.15, spot .15, play .1, desk .05, litter .05`; rabbit: `nap .3, play .2, spot .25, desk .1, litter .1, perch .05`; every weight stays > 0 — `destWeights` needs positives).

### T5.2 sprites in `kit/sprites.ts`, shape of `CAT`
Add `RABBIT_NAME = "Biscuit"`, `BIRD_NAME = "Pip"` defaults and `RABBIT`/`BIRD` frame sets keyed exactly like `CAT`,
using only the letters `drawCat` paints (`k` body, `e` eye, `c` shut eye, `t` tail, `w` curled, `p` pink, `g`/`j` accents).
~13×9 px each; draw by editing a copy of `CAT_SIT` (long ears: rows 0–2 of the head become `k.k`→ two tall `kk` columns; bird: round body, `p` beak, `t` tail). Draw, then **look at it** (below). `g`/`j` collar gems twinkle — omit those letters from the new art (no collar) so the twinkle block skips them (`findIndex` guard already exists).

### T5.3 route `drawCat` and `Sim` through the species
- `draw.ts:175 drawCat(sc, c, …)` gains `art = CAT` param → `ART[species]` with a `species` field on `Cat` (`Cat.species: Species`, default `"cat"`); keep the `CAT_NAME` tooltip as `${c.name}`.
- `Sim.setPets` sets `cat.species`, and `destWeights(this.temperament, speciesBase(species))` in `stepCat`.
- `pets.ts` `SPECIES_VOICE`: rabbit and bird use `NINA` buckets for now? **No** — a rabbit that talks like a cat is wrong. Ship 4 sassy + 4 sweet short lines each for `pet/muse/wake/done`; `Sim.line` already falls back to `canned`, so missing occasions are fine.
- `kit/pets.ts` `PRESETS`: add `cat-only`? (needs no change), skip `menagerie`/`pond-life` (blocked on a pet array + tank/pond tiles — **name open**: edit the design doc's §6 table row note in the same commit: "step 7 ships `nina-and-argos`; the rest after the pet array").

### T5.4 verify
`bun test` both clocks; `mise run office:golden` produces **no diff** for the default scene (cat slot unchanged);
`drive-office`: write `pets.json` `{"cat":{"species":"bird","name":"Pip"}}`, within a second the wide room shows a bird on the
perches (screenshot via the skill's recipe, read back the balloon text), then `rabbit`. Commit `office: a rabbit and a bird for the cat's slot`.

---

## Blocked / open (not step 7)
- **Blocked on life track (#133/#177):** a pet "noticing" a due routine (wits).
- **Server-side later:** coworker temperament (row, not file) and corkboard-line pointedness.
- **Later:** pet array + `menagerie`/`pond-life`/`none` presets; fish, duck, capybara (tank/pond tiles, step 3's tile work); Argos' axes; stroll radius.
- Dependencies between PRs: 2 needs 1 (`Temperament`); 3 needs 1+2; 4 needs 3; 5 needs 3 (4 not needed — could land in parallel with 4, but the stack is simpler linear).
