# Toy step 10 — the cast editor, the god view (ticket #66)

Greybeard-grade spec. Touches no code. The build is HELD until toy step 7 (#277) lands: both edit
`office/tui/main.ts` and `tui/sandbox.ts`. Accessories (kit/parts.ts slots) are OUT: ticket #531.

## What it is

One view over every seat, opened from the office. Rows = the bench (+ shifts); columns = look, soul,
voice line, name, archetype, grade, specialty, model. Per field: edit in place, reroll, or open the
field's own editor. Plus unseat. A second tab holds the office settings (mode / whimsy / events).
Sandbox mode edits a toy cast only (`tui/sandbox.ts` world, `$TMPDIR/tlon-sandbox` config).

## Decisions (the three the tech lead asked for)

### 1. Who owns each field's reroll

| Field | Reroll owner | Notes |
|---|---|---|
| name | `kit/hall.ts` name generators (`freshName`) | must dodge `takenNames`; the soul-guard rule in hall.ts |
| look | `rollLook` (kit/looks.ts / sprites) | opens the existing look editor to tweak after |
| voice line | server persona reroll (`POST/PATCH …/persona`) | the only field the model writes |
| archetype, grade, specialty | `hall.roll(seed, ctx)` with the other fields locked | `roll` is whole-card; the cast editor calls it with `locks.fields` = all but the target and reads one field. **No new per-field generator** (YAGNI) |
| model | none | a choice from the profile's models, not a roll |
| soul | none | opens `$EDITOR` on the file |

### 2. Where an edit is written

| Field | Written to | Via |
|---|---|---|
| look | `looks.json` (`TLON_LOOKS`) | existing read-merge-write in main.ts |
| soul | `souls/<name>.md` | `$EDITOR`; `loadSouls` picks it up on its signature poll |
| voice line | server persona | `PATCH …/persona` |
| model | server seat | `PATCH /workspaces/:id/coworkers/:agent` |
| name, archetype | **not editable in place** | server has no route to rename a seat or change archetype; shown read-only, "reroll" = hire a new seat from the hall. Adding a route is a separate server ticket, not this one |
| grade, specialty | **`cast.json` next to `looks.json`** (`TLON_CAST`), keyed by seat name | OFFICE-ONLY, no server change |

Grade/specialty: the seat has neither field today (they exist only on hall `Candidate`; `hallHire`
posts just name + archetype). The operator was asked (#10659: server field / office file /
read-only) and had not answered when this was written. **Assumption: office file** — it makes the
ticket's "edit any in place" true with zero server work and is reversible (a later server slice
moves the keys out of `cast.json`). If the answer is "server", slice 6 below becomes a server slice
(migration + PATCH route + `hallHire` sending the fields).

### 3. Unseat

A **server call**: the existing `data.unseat(seat_id, name)` → `DELETE /seats/:seat` (key `-` on the
seat card, main.ts:961). The cast editor reuses it. Office mode asks first (`ask2`, as the card does);
sandbox mode skips the confirm and the toy answers locally. The agent itself stays; only the seat goes.

## Where the view lives

`main.ts` is 2.6k lines, so it gains one `cast` mode and nothing else.

- `office/tui/cast.ts` (new): pure rows + reducers — `castRows(state)`, `stepField`, `rerollField`,
  `castTabs`. No I/O, no drawing; unit-tested like `hall.ts` / `whimsy-card.ts`.
- `office/tui/cast-file.ts` or inside `store.ts`: `loadCast/saveCast` for `cast.json` (same shape
  rules as `loadHall`: tolerate missing/garbled file, atomic write).
- `main.ts`: `cast` mode entry key, draw call, key dispatch that delegates to `cast.ts`; wiring to
  `data.*` and `LOOKS`/`SOULS`. Nothing else.
- Tabs: **People** (above) and **Office**. Office renders `whimsyRows` from `tui/whimsy-card.ts`
  unchanged (mode/whimsy/events are already `kit/whimsy.ts` state, saved to office.json).
- Legibility (operator constraint): ComicShannsMono, sized up, amber on black; every state carries a
  glyph + word, never colour alone.

## Keys (proposed; final pick at build, must pass the keys.ts collision test)

`tab` switch tab · `j/k` seat · `h/l` field · `enter` edit/open field editor · `r` reroll field ·
`R` reroll whole row (name excluded for seated) · `-` unseat · `esc` back.

## Slices (junior-sized, one per field; each its own commit, test first)

0. `cast.ts` skeleton + mode in main.ts + tabs; Office tab = whimsy card. Test: rows for a toy cast.
1. look: `enter` opens existing look editor on the seat; `r` = `rollLook`; writes looks.json.
2. soul: `enter` spawns `$EDITOR` on `souls/<name>.md` (create from draft if absent); never overwritten.
3. voice line: show from persona; `r` calls persona reroll; `enter` edits text; PATCH.
4. model: cycle among the profile's models; PATCH coworkers/:agent.
5. unseat: `-` → confirm (office) / none (sandbox) → `data.unseat`.
6. grade + specialty: `cast.json` store; `r` = hall.roll with other fields locked; vocab from the
   roster vocabulary (ticket #290 — use the same source, do not copy hall's constants).
7. name + archetype: read-only rows, hint "hire from the hall (h) to change".

## Checks

- Unit (`bun test`, office/test): `cast.test.ts` rows/steps/reroll-with-locks (reroll of one field
  leaves the others equal to before); `cast-file` round-trip + garbled file; reroll name never in
  `takenNames`.
- Sandbox: edits in sandbox mode write only under `$TMPDIR/tlon-sandbox`, never the operator's
  looks.json (test sets `TLON_LOOKS` and asserts untouched).
- Live: `drive-office` skill — open cast, reroll a look, unseat in sandbox, read the screen as text.
- Gate: `mise run check` (names gate must find any new mise task / module this adds: none planned).

## Not in scope

Accessories/slots (#531); renaming a seat or changing archetype server-side; per-field reroll
generators; live editing of a running session's soul (a soul edit reaches banter next line, the brief
only at respawn — see souls step 3 §c).

## Open

1. (settled) Grade/specialty: office file `cast.json`, operator answer #10680; make it a server field when something there needs it.
2. Whether #277 changes `PLAY`/sandbox key space — re-check key collisions at build.
