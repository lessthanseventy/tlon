APPROVE

Reviewed `git diff main...HEAD` (3 commits, office only). I read the diff and the call sites. I did not re-run the suites. The thread record shows `mise run check` passing (exit 0) on the earlier two commits. The third commit is one line in `tui/main.ts`.

**Commit 1: mailbox on the street tile**
- `paintMailboxTile` stays inside the 12px tile.
- `paintTile` and `renderHome` take an optional `mail` argument, so existing callers are unchanged.
- `tui/main.ts` passes `mailbox(needs)`, and `needs` is refreshed on poll.
- Tests cover letters, flag state, street-only, tile bounds and `renderHome` passing `mail` through.

**Commit 2: `catLetter`**
- It reuses the `catErrand` path with a `"letter"` kind, plus voice lines and the ✉ emote.
- The `wide.test.ts` test mirrors the existing cheer test.

**Commit 3: menu wiring (`0907fc3`)**
- This closes my earlier non-blocking note that `catLetter` had no caller.
- It adds menu item `l`, "Nina carries a letter", shown only when `busy().length`, like `g`. It runs through the same `cheer` helper.
- Key `l` does not collide with any other key in that menu, and `catLetter(name): boolean` matches the `catCheer` signature.
- Nothing tests the menu item itself. The kit-level test covers `catLetter`.

No blocking findings.