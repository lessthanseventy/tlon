# Spec — Toy step 12, slice 1: the pet store over the existing two slots (ticket #68, thread 266)

Andrew: *"a pet store? for species both here and across the galaxy/multiverse."*

**Status:** draft. One decision is open with the operator (**D-a**, ask #7514); everything else is pinned
here as a default and says so. A different answer to D-a changes §3 only.

**Scope.** Slice 1 of four: the store as its own view, adopting into the two slots that already exist
(`cat`, `dog` in `kit/pets.ts`). Out, as separate tickets: species batches (slice 2), pet accessories
(slice 3), N pets at once (slice 4). The store is not in the toy design doc, so this spec is the design.

## 1 · What it is
A **store** view in the office, the hall's shape (`kit/hall.ts` pure candidate, `tui/hall.ts` card rows):
browse species, see one seeded candidate at a time, name it, adopt it. Reached with `P` from home
(next to `h`, the hall); `esc` leaves and keeps the current roll.

Card: the species' sprite in its `sit` and `walk` frames (or `sit` twice for a species with no walk),
species, the slot it would fill, name, temperament (the three axes, `dots`), and one line in the
species' voice (`previewOf`).

## 2 · Keys
| key | does |
|---|---|
| ← / → | previous / next **species** (the shelf) |
| ↑ | pass: the next seed — a fresh look and temperament within the species; locked rows carry over |
| ↓ | back: the previous seed |
| tab / shift-tab | move between rows (name, temperament axes) |
| space | lock/unlock the row so a pass keeps it |
| e | rename |
| ⏎ | adopt (§3) |
| esc | leave the store |

## 3 · Adopt (D-a, the one open decision)
A species has a **family** (`SLOT_SPECIES`): cat/rabbit/bird → the `cat` slot, dog → the `dog` slot.
Adopting writes the candidate into the slot its family belongs to.

**D-a, default (1) — adopt replaces the slot's occupant.** The old pet leaves by the door; the slot holds
one pet. Chosen because slots are one-pet and a bigger slot model is slice 4. A confirm line names who
leaves ("Nina leaves by the door. adopt Biscuit?", answered y / n like every confirm in the office). The alternatives, if Andrew picks them:
(2) keep the old pet on a shelf/history — needs a slot-model rewrite, out of this slice; (3) refuse unless
the slot is empty — but both slots always hold a pet (`DEFAULT_PETS`), so the store could never adopt.

Adoption writes `{ name, species, temperament }` into that slot's entry in `pets.json` through the
existing `savePets` read-merge-write. The room follows through the existing poll of `pets.json`
(`followPets`); the replaced pet simply stops being drawn. No sim change.

## 4 · Species (the pipeline, proven on three)
A species is **data**: a frame set in `SPECIES_ART` (`sit`, optional `walk`, `sleep`, `play`, the same
keys the cat slot already draws), a voice pack in `SPECIES_VOICE`, a base behaviour table in
`SPECIES_BASE`, and one `SLOT_SPECIES` entry. Never a branch in the drawing code.

Slice 1 ships three, to prove the path:
- **hamster** — earthly, cat slot; has `walk`.
- **pet rock** — no `walk` (it never moves): `walk` falls back to `sit`; temperament barely matters.
- **A Bao A Qu** — Borges (*Book of Imaginary Beings*), cat slot; `walk` only slowly, climbs.

`SPECIES` grows by these three; `Species` stays derived from it. Every species shares the cat slot's
places (no per-species home tile; that is later). Missing frame keys fall back to `sit`, so a species
can ship with the minimum.

## 5 · The roll
`roll(species, seed, locks, taken)`: a pure function of its arguments, no I/O, no model — the hall's rule.
- **Look**: a seeded variation within the species (a palette shift of the species' fur/body letters),
  never a different sprite.
- **Name**: seeded from a short list minus names the other slot's pet and any pile use; an exhausted list
  falls back to a seeded original. Non-empty and trimmed (`resolveSlot` already refuses blank).
- **Temperament**: three axes, each `clampAxis(-2..2)`, seeded. A named temperament is an option, not
  required.
- **Seed**: `store:<n>`. The store's file holds seed + locks + species + edits, never the rendered card.

## 6 · Persistence and the sandbox (D-b)
- `store.json` (`TLON_STORE`, next to `hall.json`), polled like it: current species, seed, locks, edits.
- **The sandbox adopts to a sandbox pets path only, never the toy's `pets.json`.** Today `PETS_PATH` in
  `tui/pets.ts` is not sandbox-aware: the pet card's `S` and the poll both use it, so a sandbox save would
  reach the machine's file. The slice fixes that first, in its own commit with its own test: in
  `--sandbox`, the pets path is `$TMPDIR/tlon-sandbox/pets.json` (`TLON_PETS` still wins), the same
  rule `HALL` and looks follow.
- The store reads and writes only the path the TUI resolved; `kit/store.ts` takes no path.

## 7 · What is kept (D-c)
Nothing of the replaced pet: `pets.json` holds one pet per slot and no history. The adopt confirm is the
only record, and `esc` there changes nothing. (A shelf is D-a option 2, not this slice.)

## 8 · Seams, not built
- Slice 2 adds species by adding data rows (§4) — the test that every `SPECIES` entry has art, voice and
  a slot is the guard.
- Slice 3 accessories: a separate overlay set at pet width reusing `parts.ts`'s `Part`/dial shape, not
  its human rows; the card gets a row, the file an `accessories` field.
- Slice 4 N pets: replaces `SLOT_SPECIES` with a pets list; the store's adopt becomes an append.

## 9 · Checks (definition of done), written first
1. `office/test/store.test.ts` (new): same `(species, seed, locks)` → identical candidate; a pass keeps
   locked rows; names avoid the other slot's pet and the pile; the temperament axes stay in −2..2; a
   species' family decides its slot (hamster/A Bao A Qu/rock → `cat`; dog → `dog`).
2. `office/test/pets.test.ts`: every `SPECIES` entry has art with `sit`, a voice pack that falls back
   to Nina's lines for a missing occasion, and exactly one slot; `resolvePets` accepts a new species only
   in its own slot.
3. Adopt, pure: adopting hamster into `cat` returns a `PetsFile` with that slot replaced, the other slot
   untouched; adopting dog into `cat` is refused.
4. Sandbox, no real file: with `--sandbox` the resolved pets path is under `tlon-sandbox/`; an adopt test
   points `TLON_PETS` at a temp dir and asserts the real `~/.config/tlon/pets.json` is never opened.
5. `test/wcag.test.ts` still passes with the store view: labels 4.5:1, no state by colour alone, every
   action by key.
6. `mise run office:check` green; the card seen once in `mise run office:sandbox` (a screenshot or a
   `drive-office` read-back goes on the thread).

## 10 · Plan order (for the plan stage)
(1) sandbox-aware pets path (§6, own commit) → (2) `kit/store.ts` pure roll + tests → (3) the three
species as data + tests → (4) `tui/store.ts` rows + keys + hook-in to `main.ts` (a hook-in only; stay
clear of #255's `rooms/wide.ts`) → (5) adopt + confirm → (6) doc sync: `office/AGENTS.md` names the store
beside the hall.
