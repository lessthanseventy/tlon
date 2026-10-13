# Toy step 12, slice 1: the pet store over the two existing slots

Closes ticket #68 (slice 1 of 4; thread 266).

A `P` from home opens the pet store: browse every species (←/→; the dog adopts into the dog slot, which is pets.json only — the room still draws Argos), roll a seeded look and
temperament (↑ pass, ↓ back, space locks a row, `e` renames), and ⏎ adopts it into the species' slot.
The occupant leaves by the door (operator's decision D-a: replace; one pet per slot, no history).
`store.json` holds species + seed + locks + edits, never the rendered card; the room follows the adopt
through the existing `pets.json` poll.

What changed, one commit each:
- `pets.json` follows `--sandbox` (the pet card's `S` used to write the real file from the sandbox).
- A pet species is data: `slotOf`, `fillArt`, and the voice/destination lookups keyed by name instead
  of branching on rabbit/bird. Three new species prove the path: hamster, pet rock (ships `sit` alone),
  A Bao A Qu.
- `shade`: a seeded fur within the species (0..3), persisted per slot, drawn by `furOf`.
- `kit/store.ts` (pure: `roll`, `candidateOf`, `pass`/`back`/`shelve`, locks carry, `adopt`) and
  `tui/store.ts` (the card rows, sit beside walk in half-blocks; locked state is the word, never colour).
- The view and its keys in `tui/main.ts`; adopt behind the existing y/n confirm.
- `previewOf` now passes the species to `bucketFor`, so the card's line is in the species' voice.
- `office/AGENTS.md` names the store beside the hall.

Checked: `bun test` per file red→green on every commit, `bun run typecheck`, `mise run office:check`,
`mise run check`. Live, headless (`OFFICE_SANDBOX=1 mise run office:drive`): the card draws every shelved
species; pass bumps the seed and keeps the locked row; ⏎ shows "Nina leaves by the door. adopt Marble?",
`y` writes `$TMPDIR/tlon-sandbox/pets.json` and the real `~/.config/tlon/pets.json` mtime is unchanged.
