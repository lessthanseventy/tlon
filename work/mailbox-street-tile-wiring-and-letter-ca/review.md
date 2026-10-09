APPROVE

Reviewed `git diff main...HEAD` (2 commits, 7 files, office only). I read the diff and the surrounding call sites. I did not re-run the suites. The thread record shows `mise run check` passing (exit 0).

**Commit 1: mailbox on the street tile**
- `paintMailboxTile` stays inside the 12px tile: the max x is x+11 and the min y is y. The "stays inside the tile" test checks this.
- `paintTile` and `renderHome` take an optional `mail` argument, so existing callers are untouched.
- `tui/main.ts` passes `mailbox(needs)`. `needs` is a module-level `data.Need[]` refreshed on poll, so the grid follows the queue.
- Tests cover letters, flag state, that only the street gets a mailbox, the tile bounds, and that `renderHome` carries `mail` through.

**Commit 2: `catLetter`**
- It reuses the `catErrand` path with a new `"letter"` kind, plus voice lines and the ✉ emote.
- The `wide.test.ts` test mirrors the existing cheer test.

**Not blocking**
- `catLetter` has no caller. `catCheer` is wired as a menu action at `tui/main.ts:1132`, and nothing offers "carry a letter". It is tested but unreachable by the operator. Wire it in a follow-up, for example a menu item shown when `needs.length > 0`, or make the cat do it herself.
