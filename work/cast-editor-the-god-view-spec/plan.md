# Plan — toy step 10, the cast editor (ticket #66; spec: `spec.md` beside this)

Decisions are in the spec; this file is only the how. **Do not start until toy step 7 (#277) has landed**
(it edits `office/tui/main.ts` and `tui/sandbox.ts` too). Rebase onto main first, then re-check the
key-collision step in T3. Accessories are out (#531). Name and archetype stay read-only.

Everything is under `office/`. Run tests from there: `bun test test/<file>` (one file) and, at the end,
`mise run check` (the gate; a coworker seat runs `menard run check --in server` / its module check instead
and advances — verify runs the full gate). Commit each task alone, test first. Commit trailer:
`Co-Authored-By: <your model> <noreply@anthropic.com>`.

What already exists and is REUSED (do not rewrite):
- `tui/main.ts` `seatActions(b)` (~l.932): model picker (`seat.M`), persona picker (`seat.E`: reroll / edit voice), unseat (`seat.-`, `ask2` confirm → `data.unseat`).
- `saveLook(name, draft)` (~l.116) writes `looks.json`; the `look` mode (`{kind:"look", name}`) is the look card whose `look.r` rolls with `rollLook`.
- `whimsyRows(whim)` / `whimsyTitle` / `resetToPreset` (`tui/whimsy-card.ts`) and the `case "whimsy"` card (~l.1594) = the Office tab.
- `kit/hall.ts` `roll(seed, {taken, vocab})`, `Vocab`, `hallVocab()` (main.ts ~l.170: GRADES/SPECIALTIES constants).
- `loadSouls/soulsSignature` (`tui/souls.ts`), `SOULS` dir const, `openDump()` (~l.2483) = how this TUI opens `$EDITOR` in its own tmux (`zoomOn`).

---

## T1 — `cast.json` store (pure I/O module)

Files: `office/kit/cast.ts` (new), `office/test/cast-file.test.ts` (new).

Test first (`test/cast-file.test.ts`):
```ts
import { expect, test } from "bun:test"
import { mkdtempSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { castSignature, loadCast, saveCast, setTrait } from "../kit/cast"

const dir = () => mkdtempSync(join(tmpdir(), "cast-file-"))

test("a missing file is an empty cast", () => expect(loadCast(join(dir(), "cast.json"))).toEqual({}))
test("a garbled file is an empty cast", () => {
  const p = join(dir(), "cast.json"); writeFileSync(p, "{not json")
  expect(loadCast(p)).toEqual({})
})
test("round trip keeps grade and specialty by seat name", () => {
  const p = join(dir(), "sub", "cast.json")
  saveCast(p, setTrait(setTrait({}, "ada", "grade", "senior"), "ada", "specialty", "office"))
  expect(loadCast(p)).toEqual({ ada: { grade: "senior", specialty: "office" } })
})
test("a key that is not a legal seat name, and a non-string value, are dropped on load", () => {
  const p = join(dir(), "cast.json")
  writeFileSync(p, JSON.stringify({ "Bad Name": { grade: "x" }, ok: { grade: 3, specialty: "server" } }))
  expect(loadCast(p)).toEqual({ ok: { specialty: "server" } })
})
test("setTrait does not mutate", () => {
  const a = {}; setTrait(a, "ada", "grade", "junior"); expect(a).toEqual({})
})
test("signature changes when the file does, and is empty when absent", () => {
  const p = join(dir(), "cast.json")
  expect(castSignature(p)).toBe("")
  saveCast(p, { ada: { grade: "junior" } })
  expect(castSignature(p)).not.toBe("")
})
```
Run: `bun test test/cast-file.test.ts` → red (module missing).

Code (`kit/cast.ts`):
```ts
// cast.json: the office's own record of what the cast editor sets on a seat that the server has no field for
// (grade, specialty), keyed by seat name like looks.json. TLON_CAST points elsewhere; the sandbox keeps its own.
import { mkdirSync, readFileSync, statSync, writeFileSync } from "node:fs"
import { dirname } from "node:path"

export type Traits = { grade?: string; specialty?: string }
export type Cast = Record<string, Traits>

// Server.Soul's name check: the same key looks.json and souls/<name>.md use
const SEAT_NAME = /^[a-z0-9][a-z0-9_-]*$/

export function loadCast(path: string): Cast {
  try {
    const j = JSON.parse(readFileSync(path, "utf8")) as Record<string, Record<string, unknown>>
    const out: Cast = {}
    for (const [name, t] of Object.entries(j)) {
      if (!SEAT_NAME.test(name) || !t || typeof t !== "object") continue
      const traits: Traits = {}
      if (typeof t.grade === "string") traits.grade = t.grade
      if (typeof t.specialty === "string") traits.specialty = t.specialty
      if (Object.keys(traits).length) out[name] = traits
    }
    return out
  } catch { return {} }
}

export function saveCast(path: string, c: Cast): void {
  mkdirSync(dirname(path), { recursive: true })
  writeFileSync(path, JSON.stringify(c, null, 2) + "\n")
}

/** mtime and size; "" when absent, so a poll can tell an edit from a quiet file */
export function castSignature(path: string): string {
  try { const s = statSync(path); return `${s.mtimeMs}:${s.size}` } catch { return "" }
}

export const setTrait = (c: Cast, name: string, field: keyof Traits, value: string): Cast =>
  ({ ...c, [name]: { ...c[name], [field]: value } })
```
Done = `bun test test/cast-file.test.ts` green. Commit: `cast editor: cast.json, the office's grade and specialty per seat`.

## T2 — the cast view's pure rows and rerolls

Files: `office/tui/cast.ts` (new), `office/test/cast.test.ts` (new).

Test first (`test/cast.test.ts`):
```ts
import { expect, test } from "bun:test"
import { CAST_FIELDS, EDITABLE_HERE, castRows, nextTrait, rerollTrait } from "../tui/cast"

const vocab = { archetypes: ["builder", "reviewer"], grades: ["junior", "senior", "greybeard"], specialties: ["office", "server"] }
const seat = (name: string, extra = {}) => ({ name, archetype: "builder", model: null, voice: null, hasSoul: false, hasLook: false, ...extra })

test("one row per seat, one cell per field, in the spec's order", () => {
  const rows = castRows([seat("ada"), seat("bo")], {}, vocab)
  expect(rows.map(r => r.name)).toEqual(["ada", "bo"])
  expect(rows[0]!.cells.map(c => c.field)).toEqual([...CAST_FIELDS])
})
test("name and archetype are read-only; the rest are editable", () => {
  const cells = castRows([seat("ada")], {}, vocab)[0]!.cells
  expect(cells.filter(c => !c.editable).map(c => c.field)).toEqual(["name", "archetype"])
  expect(EDITABLE_HERE).toEqual(["look", "soul", "voice", "grade", "specialty", "model"])
})
test("grade and specialty come from cast.json, else say unset", () => {
  const cells = castRows([seat("ada")], { ada: { grade: "senior" } }, vocab)[0]!.cells
  expect(cells.find(c => c.field === "grade")!.value).toBe("senior")
  expect(cells.find(c => c.field === "specialty")!.value).toBe("unset")
})
test("voice, model, soul and look read as words", () => {
  const cells = castRows([seat("ada", { voice: "dry", model: "opus", hasSoul: true, hasLook: true })], {}, vocab)[0]!.cells
  const v = (f: string) => cells.find(c => c.field === f)!.value
  expect([v("voice"), v("model"), v("soul"), v("look")]).toEqual(["dry", "opus", "has a soul", "custom look"])
})
test("nextTrait cycles the vocabulary and wraps; an unknown current starts at the first", () => {
  expect(nextTrait(vocab.grades, "junior")).toBe("senior")
  expect(nextTrait(vocab.grades, "greybeard")).toBe("junior")
  expect(nextTrait(vocab.grades, "unset")).toBe("junior")
})
test("rerollTrait is deterministic, in the vocabulary, and reads the hall's own pick", () => {
  const a = rerollTrait("ada:1", "grade", vocab), b = rerollTrait("ada:1", "grade", vocab)
  expect(a).toBe(b)
  expect(vocab.grades).toContain(a)
  expect(vocab.specialties).toContain(rerollTrait("ada:1", "specialty", vocab))
})
```
Red first.

Code (`tui/cast.ts`) — pure, no I/O, no drawing:
```ts
// The cast editor's rows as data (the god view, spec.md): one row per seat, one cell per field. Pure, so it
// needs no terminal to test; main.ts draws it and wires each cell's key to the existing editor for that field.
import { roll, type Vocab } from "../kit/hall"
import type { Cast } from "../kit/cast"

export const CAST_FIELDS = ["name", "archetype", "look", "soul", "voice", "grade", "specialty", "model"] as const
export type CastField = (typeof CAST_FIELDS)[number]
/** the fields the editor changes; name and archetype have no server route, so they only show (spec §2) */
export const EDITABLE_HERE = ["look", "soul", "voice", "grade", "specialty", "model"] as const

export type CastSeat = { name: string; archetype: string | null; model: string | null; voice: string | null; hasSoul: boolean; hasLook: boolean }
export type CastCell = { field: CastField; value: string; editable: boolean }
export type CastRow = { name: string; cells: CastCell[] }

export function castRows(seats: readonly CastSeat[], cast: Cast, vocab: Vocab): CastRow[] {
  void vocab
  return seats.map((s) => {
    const value: Record<CastField, string> = {
      name: s.name, archetype: s.archetype ?? "none",
      look: s.hasLook ? "custom look" : "seeded look",
      soul: s.hasSoul ? "has a soul" : "no soul yet",
      voice: s.voice ?? "no persona",
      grade: cast[s.name]?.grade ?? "unset",
      specialty: cast[s.name]?.specialty ?? "unset",
      model: s.model ?? "the archetype's",
    }
    return { name: s.name, cells: CAST_FIELDS.map((field) => ({ field, value: value[field], editable: (EDITABLE_HERE as readonly string[]).includes(field) })) }
  })
}

/** the next entry of a vocabulary after `cur`, wrapping; a value not in it starts at the first */
export const nextTrait = (vocab: readonly string[], cur: string): string => vocab[(vocab.indexOf(cur) + 1) % vocab.length]!

/** a fresh grade or specialty from the hall's own generator: roll()'s fields are independent hashes of the seed, so reading one leaves the others as they were */
export const rerollTrait = (seed: string, field: "grade" | "specialty", vocab: Vocab): string =>
  roll(seed, { taken: [], vocab })[field]
```
(Drop the `void vocab` param if lint complains: then `castRows(seats, cast)`; update the test calls to match — keep signature `(seats, cast)` if you drop it.)
Done = `bun test test/cast.test.ts` green. Commit: `cast editor: the view's rows, and grade/specialty rerolls from the hall`.

## T3 — pull the seat verbs out of `seatActions`, so the cast view and the seat card share them

Pure refactor, behaviour unchanged. Files: `office/tui/main.ts` only. Guard: existing tests (`test/persona-reroll.test.ts`, `test/confirm.test.ts`, `test/navigation.test.ts`, `test/hall-hire.test.ts`) stay green — run them before and after.

In `main.ts` split the bodies of `seatActions` (l.~932) into named functions above it, each taking the `Coworker` and using `ws`/`view()` as now:
`pickModel(b)` (the `seat.M` body), `pickPersona(b)` (the `seat.E` body), `unseatAsk(b)` (the `seat.-` body). `seatActions` becomes `{ ...bind("seat.M"), run: () => pickModel(b) }` etc. Nothing else moves.
Done = the four tests above green. Commit: `office: the seat's model, persona and unseat verbs as functions, for the cast view to reuse`.

## T4 — the `cast` mode: People tab skeleton + Office tab, reachable

Files: `office/tui/keys.ts`, `office/tui/main.ts`, `office/test/cast-view.test.ts` (new; drive like `test/hall-view.test.ts` / `test/persona-reroll.test.ts`: real TUI in a private tmux socket against a stub server).

1. `keys.ts`: add `{ id: "home.G", scope: "card:home", key: "G", label: "the cast editor (god view)", verb: "cast" }` and a `card:cast` block: `cast.tab` key `tab` "people / office"; `cast.r` key `r` "reroll the field" verb `reroll`; `cast.e` key `e`… (see T5–T8 for each). **Check `G` is free**: `bun test test/keys.test.ts` fails on a collision (it also enforces one verb per key); if `G` collides, take the next free letter. Re-check after rebasing on #277 (it adds sandbox play keys).
2. `main.ts`: add `{ kind: "cast"; tab: "people" | "office" }` to `Mode` (l.65); `home.G` runs `open({ kind: "cast", tab: "people" })`; add `case "cast":` next to `case "hall":` (l.~1836). People tab: `castRows(seats, cast, hallVocab())` where `seats` = `view().bench` (and `shifts`) mapped to `CastSeat` (`voice: b.persona?.voice ?? null`, `model: b.model?.model ?? null`, `hasSoul: !!soulFor(b.name)`, `hasLook: !!overrideFor(b.name)`); one card `Row` per seat, `segs` = name padded + each cell value, `open` = nothing yet. Selected cell is a module `let castCol = 0`; `h/l` (or left/right) move it, bounded by `CAST_FIELDS.length`. Office tab: the same `rows` body as `case "whimsy"` (copy the call, do not fork `whimsyRows`).
   Add `let cast: Cast = loadCast(CAST)` with `const CAST = process.env.TLON_CAST ?? join(CONFIG, "cast.json")` beside `HALL`, and poll its signature the way `hallSeen` is (copy `hallSet`/poll shape: `castSet(c) { cast = c; saveCast(CAST, c); castSeen = castSignature(CAST) }`).
3. Test (`cast-view.test.ts`): stub `/office` with two bench seats; press `G`; the screen text contains both names and `unset`; `tab` shows `WACKINESS`; `esc` returns home. Use `OFFICE_TEXT=1`/the existing drive helpers the neighbouring tests use.

Legibility: every cell carries a word (never colour alone); `ROLE.key` for the lit cell as in `case "whimsy"`.
Done = `bun test test/cast-view.test.ts test/keys.test.ts` green. Commit: `cast editor: the view, its two tabs, and a key to open it`.

## T5 — model, voice, unseat cells (reuse T3's functions)

Files: `main.ts` (`case "cast"` only), `test/cast-view.test.ts`.
`⏎` on the lit cell of seat `b` dispatches by field: `model` → `pickModel(b)`; `voice` → `pickPersona(b)` (it offers reroll / make one / edit voice — the spec's voice reroll owner is the server persona, already behind it); `-` (existing `seat.-` binding, add `cast.-` in keys.ts with verb `remove` as `hall-pile.x` does) → `unseatAsk(b)`. Sandbox: the toy answers `data.unseat`/`retarget`/`persona` already via `tui/sandbox.ts` (`useFake`); office mode's `ask2` confirm is inside `unseatAsk`.
Tests (stub server records requests, as `persona-reroll.test.ts`): `⏎` on voice then choosing reroll POSTs `/persona` after `y`; `-` then `n` sends no DELETE, `-` then `y` sends `DELETE /seats/<id>`.
Commit: `cast editor: model, voice and unseat from the cast view`.

## T6 — grade and specialty cells (the only new write: cast.json)

Files: `main.ts`, `keys.ts`, `test/cast-view.test.ts`.
On the grade / specialty cell: `⏎` cycles via `nextTrait(hallVocab().grades|specialties, current)`; `r` (`cast.r`, verb `reroll`) sets `rerollTrait(`${name}:${castRolls++}`, field, hallVocab())` (module `let castRolls = 0`, as `rolls` for looks). Both end in `castSet(setTrait(cast, name, field, value))`. In `--sandbox` `CONFIG` is already `$TMPDIR/tlon-sandbox`, so the write cannot reach the operator's real file.
Tests: `⏎` on grade writes `cast.json` (set `TLON_CAST` to a temp path in the test env) with the next grade; `r` writes a value in the vocab; garbled file at start renders `unset`.
Commit: `cast editor: grade and specialty, kept in cast.json`.

## T7 — look cell, soul cell

Files: `main.ts`, `keys.ts`, `test/cast-view.test.ts`.
- look: `⏎` → `open({ kind: "look", name, from: mode })` (the existing look card and pixel editor; it saves via `saveLook`). `r` → `saveLook(name, { ...(overrideFor(name) ?? {}), ...rollLook(`${name}:${rolls++}`) }); roomChanged = true; draw()` (same call the card's `look.r` makes, but saved at once).
- soul: `⏎` → `openSoul(name)`: copy the shape of `openDump()` (l.~2483) for the file `join(SOULS, `${name}.md`)`: create it first with the hall's blank skeleton if absent, **never overwrite** (`writeFileSync(..., { flag: "wx" })` in try/catch, as `hallHire` does at l.~194); then `tmux new-session -d -s soul-<name> … sh -c <edit> <file>` and `zoomOn({ socket: OWN_TMUX, session, window: "soul" }, "the soul", () => { soulsSeen = "" })` so the next poll (`soulsSignature`) re-reads it. Share the `edit` shell string with `openDump` by lifting it to a module const `EDIT_SH` (one small extraction, same commit).
Tests: look `r` changes `looks.json` for that seat only and leaves other seats' entries; soul `⏎` creates `souls/<name>.md` once and a second `⏎` leaves its text intact (assert contents; do not assert the editor spawn).
Commit: `cast editor: the look and the soul from the cast view`.

## T8 — name and archetype: read-only, say how to change them

Files: `main.ts`, `test/cast-view.test.ts`.
`⏎` on a read-only cell sets `status = "rename/retype isn't a thing a seat can do — hire a new one from the hall (h)"` and draws. (No server route exists; adding one is a separate ticket.)
Test: `⏎` there changes no file and posts nothing; the status line carries the hint.
Commit: `cast editor: name and archetype show, and say how to change them`.

## T9 — sandbox isolation, help, docs

Files: `test/cast-view.test.ts` (or `test/sandbox.test.ts`), `office/AGENTS.md`, `docs/` only if a cast/toy doc exists (`grep -rn "hall.json" office/AGENTS.md docs | head`).
- Test: run the TUI with `--sandbox`, set `TLON_LOOKS`/`TLON_CAST` unset, press `G`, `⏎` on grade: assert nothing under the operator's `XDG_CONFIG_HOME/tlon` changed (point `XDG_CONFIG_HOME` at a temp dir and assert it stays empty) and `$TMPDIR/tlon-sandbox/cast.json` exists.
- Docs: add `cast.json` / `TLON_CAST` and the `cast` mode wherever `hall.json` / `TLON_HALL` are listed (the same commit: stale docs are worse than none).
- Live check with the `drive-office` skill: `G`, move to grade, `r`, `tab` to Office, `esc`; read the screen as text; quote it in `pr.md`.
Gate: `mise run check` green (names gate must find every module this plan names: `kit/cast.ts`, `tui/cast.ts`).
Commit: `cast editor: sandbox leaves the operator's files alone; docs`.

## Order and size

T1 → T2 → T3 → T4 → (T5, T6, T7, T8 in any order; each its own commit) → T9. T1–T2 touch no existing file, so they can start before #277 lands; T3 onward wait for it. The junior slices are T5, T6, T7, T8, one field each.
