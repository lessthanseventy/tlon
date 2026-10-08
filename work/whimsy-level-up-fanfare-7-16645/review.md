# Review — whimsy level-up fanfare (§7)

**VERDICT: APPROVE**

Reviewed `git diff main...HEAD` (7 files, +68/-3): `homeLevel` in life.ts, a `levelSeen` baseline plus a `levelUp` hook in sim.ts, the "level" channel in tv.ts, and the wide.ts override. This workline's spec.md isn't in the tree, so I checked against the goal ("level-up fanfare §7") and the commit messages only. I read the diff; I did not run the suite. The check results on the thread (office:check 191 pass, mise run check green) are daneri's.

## Findings (none blocking)
- The first snapshot only sets the baseline, so start-up doesn't fire a party. A null baseline stays null, and the wide test covers this.
- A snapshot with `ok:false` is replaced by lastGood before `homeLevel` runs, so a server blip can't fake a level change.
- tv.ts: `next()` called by the remote during the level channel re-inits the new show, and the level frames then reinit the idx show again when they end. This is harmless.
- Minor semantics: `homeLevel` takes the max across workspaces. A newly appearing higher-level workspace would trigger one fanfare, and a level that drops and then rises again re-triggers. Both are rare and acceptable.
- Unverified: the visual look of the TV. daneri says no TUI screenshot was taken. A glance with drive-office is worth doing eventually, but it is not a blocker.
- No golden moved. The tests were written first and cover `homeLevel`, `showLevel` and the wide-room party.
