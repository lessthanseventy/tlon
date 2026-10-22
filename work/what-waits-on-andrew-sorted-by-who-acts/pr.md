# What waits on Andrew, sorted by who acts (#167)

An item reaches the operator's phone only if it has an answer he must give. Information goes to the answering machine. What the crew owns goes on the sheriff's clipboard.

**Server**
- `Needs.kinds/0` and `surface/1` route each of the 18 kinds to phone, machine or clipboard. `surface/1` has no catch-all clause, so a new kind can't reach the list unrouted.
- Every item now carries `surface`. Clipboard rows also carry `owner` (the thread's lead) and `tracking` (the workline's slug, or the ticket an issue names).
- `grouped/1` returns `{phone, machine, clipboard, counts}`. The machine shows an item until it is heard (`hear/1`, recorded in the new `need_heard` table) or for at most a day.
- Routes: `GET /api/office/needs?by=surface` serves the grouped body, and `POST /api/office/needs/heard` marks items heard. The bare `GET /api/office/needs` still returns the flat list, because the claude-code adapter and the office's test stubs read it as an array.

**Office**
- The top bar shows one count, `☎ N waiting on you`, which rings (☎/☏) while N > 0. The terminal bell rings only for a new phone item.
- The room gets an answering machine that blinks for unheard items; opening it marks them heard. The sheriff's clipboard replaces the beacon by the door and lists this workspace's clipboard rows as `owner · tracking · title`.
- The inbox (`i`) is grouped into PHONE, MACHINE and CLIPBOARD sections, and the decide card goes phone first.
- The `Needs` moduledoc and `office/AGENTS.md` are updated to match.

pr_blocked, publish_failed and release_failed go on the clipboard provisionally, as the spec says, until the operator answers ask #11491.

**Checked**
- The 2026-10-10 state (four issues and two mentions) gives phone 0, machine 2, clipboard 4 (`needs_test.exs`).
- `menard run check --in server`: 2008 tests, 0 failures, after rebasing onto origin/main 0a5b7db.
- In `office/`: `bun test` ran 813 tests with 0 failures; `tsc --noEmit` is clean; golden frames re-hashed; the machine's placement checked by eye on a render.

**Open**
- The home view's mailbox (`kit/mailbox.ts`) still raises its flag on `level == "blocking"`, not on the phone.
- The entry's WAITING ON YOU section still lists every item.

Closes #167.
