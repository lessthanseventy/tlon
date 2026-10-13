APPROVE. Note: no free reviewer is at the builder's grade (greybeard); this review is by tzinacan at a lower grade — weigh accordingly.

Read: kit/store.ts, tui/store.ts, main.ts wiring, kit/pets.ts (species/slotOf/shade), tui/pets.ts (sandbox-aware pets path). Ran `bun test` in office/: 547 pass, 6 fail + 1 error — all tmux-driven tests (terminal/reroll/refresh) failing on tmux socket "Operation not permitted" / EROFS under my sandbox; unrelated to this diff, but I could not see them green here, so the gate run is the authority.

Checked and fine:
- roll() is pure/seeded; candidateOf+carry re-render the same card after restart; a locked name that is now taken re-rolls rather than duplicating.
- adopt() refuses wrong-slot species / empty name; savePets read-merges the slot, so shade/temperament land without clobbering.
- Confirm (ask2) gates the occupant leaving; the sandbox no longer writes the real pets.json.
- STORE_VIEW_ROWS (8) matches storeRows' 8 rows; tab-stepping and space-lock are safe on non-lockable rows.

Non-blocking: storeTaken() excludes the replaced occupant's name from "taken", so a roll may reuse it — harmless, it leaves.