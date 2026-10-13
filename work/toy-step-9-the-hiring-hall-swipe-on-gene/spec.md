# Spec — Toy step 9: the hiring hall (ticket #65, thread 257)

Andrew: *"roll me up a person. tinder for AI generated SNES looking people."*

**Status:** draft on the recommended defaults. Decisions D1–D3 are asks to the operator
(#6910–#6912); a different answer changes only the section named, nothing else.

## 1 · What it is
A **hall** view in the office: one rolled candidate at a time, full-size. Everything on the card
derives from one **seed**, so any roll is reproducible.

Card: sprite (all three views), name, suggested archetype / grade / specialty, soul draft,
one-line pitch, and the parts rows (§3).

## 2 · Keys
| key | does |
|---|---|
| ← | pass: draw the next seed (a new roll; locked parts and locked fields carry over) |
| → | hire (§5) |
| ↑ | maybe: push the candidate onto the pile, then roll next |
| e | edit the look (existing look card/editor) or the soul text |
| s | draw the model soul + pitch for this seed (D2) |
| tab / shift-tab | move between the card's rows; `space` locks/unlocks the row's part |
| esc | leave the hall; the current roll is kept |

The maybe pile is browsed with `m` (↑/↓ pick, enter to bring one back as the current card, `x` drops it).

## 3 · The roll
- **Look**: `rollLook(seed)` (`office/kit/sprites.ts`) already draws body + parts from a seed. The hall
  adds skin/hair/outfit/palette roles from the same seed. Pure function of `(seed, locks)`; no model.
- **Accessories first**, one per slot (`head, eyes, mouth, neck, back, hand` = `SLOTS` in
  `kit/parts.ts`; the ticket's "face" is `eyes`+`mouth`). Each slot has its own cycling row (`PARTS` + `dials`),
  each lockable. A locked slot survives a pass.
- **Name**: seeded pick from a Borges-character list minus names already on any bench or in the pile;
  if exhausted, a seeded original name. Must match `^[a-z0-9][a-z0-9_-]*$` (Server.Soul's check).
- **Archetype / grade / specialty**: seeded from the roster vocabulary (`Server.Profiles`), a
  suggestion shown on the card, editable before hire.
- **Seed**: a string `hall:<n>`; the maybe pile and `hall.json` store the seed plus overrides, never the
  rendered result, so a pile entry always re-renders identically.

## 4 · Soul and pitch (D2, default A: on demand)
- The card shows a deterministic fallback pitch + soul skeleton instantly (no call). Pass/reroll never
  calls a model.
- `s`, or **hire**, draws the model soul + pitch for that seed through `Server.Generator`
  (daily cap, fallback to the handwritten text; the render path never calls it, per #59).
- The drawn text is cached on the candidate (in `hall.json` / the pile) so hiring writes exactly what
  the operator saw.

## 5 · Hire
One path, two modes:

| step | sandbox | office |
|---|---|---|
| confirm | none | **modal** (D1): name, archetype, grade, crew, "will be staffed work" |
| seat | pretend bench only (`tui/sandbox.ts`) | `Workspaces.seat(ws, %{name, archetype, grade, specialty, crew: "all"})` over the open workspace |
| persona | – | `Server.Persona.ensure(ws, name)` |
| soul | `souls/<name>.md` in the sandbox dir | **`Server.Soul.create(name, body)`** |
| look | `looks.json` entry | `looks.json` entry via existing `saveLook` |

- **Reuse, not a second writer.** #61's `Server.Soul.draft/2` needs an existing seat, which the hall
  does not have at roll time. Extract its exclusive write into `Server.Soul.create(name, body)`
  (`File.write(..., [:exclusive])`, `{:ok, :written | :exists}`, same `check_name`); `draft/2` calls it.
  The hall's body is the soul text from §4. An existing `souls/<name>.md` is never overwritten.
- **Order and failure**: seat first (the only step that can be refused), then persona, soul, look.
  A failed seat writes nothing. A soul/persona failure after the seat leaves a working seat and posts a
  toast; it must not crash (ticket #265 is this class).
- **Office effect** (D1 default): the seat lands on the bench at `crew: "all"`, on shift; `Workspaces.seat`
  already announces the workspace so the roster and board refresh; intake may staff them from the next
  tick. Nothing else (no auto-ticket, no intro thread).
- The hall reaches the server over the existing office HTTP API; **new endpoint**
  `POST /api/workspaces/:id/hire {name, archetype, grade, specialty, soul, persona_seed?}` doing the
  server-side steps in one transaction-ish call, so the TUI never writes souls itself.

## 6 · Persistence (D3, default A)
`~/.config/tlon/hall.json` (`TLON_HALL` overrides), next to `looks.json`: current seed + locks,
overrides, drawn soul text, and the pile. Per machine, hand-editable, polled like `looks.json`.
Sandbox uses its own file so a toy pile never shows up in the office.

## 7 · Seams, not built
- #66 cast editor: the candidate model (`{seed, locks, overrides, soul}`) and the look editor reuse are
  the seam; no god-view here.
- #68 pet store: the hall's card/rows/keys are written over a `Candidate` type so a species candidate
  can be a second kind later; no pets here.

## 8 · Out of scope
Firing, re-rolling an already-hired seat, editing an existing soul from the hall (the card already
edits), model-drawn sprite parts (#97), the weird parts catalogue (#98).

## 9 · Checks (definition of done)
1. `bun test` (office): same `(seed, locks)` → identical candidate; pass keeps locked slots; names
   exclude the bench and the pile; pile survives a `hall.json` round trip.
2. `mix test` (server): `Server.Soul.create/2` writes once and returns `:exists` the second time;
   `draft/2` unchanged; hire endpoint with a bad name returns an error and seats nobody.
3. Sandbox drive (`mise run office:drive`): ← ← ↑ → in the hall, then the new person is on the bench
   with a soul and a look; in office mode → shows the confirm and `esc` seats nobody.
4. `mise run check` green.

## 10 · Build order (for the plan stage)
1. `Server.Soul.create/2` extraction (+ test). 2. Hire endpoint + test. 3. `kit/hall.ts`: candidate,
roll, locks, names (pure, + tests). 4. `hall.json` load/save/poll. 5. Hall view + keys, sandbox first.
6. Office hire wiring + confirm modal. 7. Soul/pitch on demand. Each is its own commit.
