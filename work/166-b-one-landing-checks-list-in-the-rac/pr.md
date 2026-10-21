#166 B: one LANDING & CHECKS list in the rack, plus pending restart shown

The rack card (`H`) had two sections, CHECKS QUEUE and MERGE QUEUE. It now has one LANDING & CHECKS list (`office/kit/rack.ts` `queueItems`): the running check, the waiters in the server's order (`Room.checks/0` is in ticket order since #166 A), the landing, the queued, then a scheduled restart (`/settings` `restart_pending`, fetched with the health card). Everything is status: no top-bar edit, no new Need kind.

Closes ticket #557.

Checked: `test/rack.test.ts` (pure list) and `test/rack-card.test.ts` (real TUI against a stub server) went red first, then green; `bun test` in office 806 pass, 0 fail; `tsc --noEmit` clean. office/AGENTS.md line on the checks queue updated.
