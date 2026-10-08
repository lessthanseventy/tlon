VERDICT: approve (hold the merge until #133 is on main)

Scope: office/ only — kit/life.ts, kit/types.ts, tui/data.ts, tui/main.ts, plus tests. I read the diff. I did not run the suite; I rely on the recorded `mise run check` pass and emma's report of 173 pass / 0 fail after the rebase.

Findings
1. Merge ordering (blocking for the merge, not for the code). origin/main has no `Server.Life` and no `/api/life` route. The endpoints and payload shapes (`LifeStatus`, `level_up`, `/life/:ws/routines`, `/life/:ws/quests`) are written against #133's design and are unverified against a real server. The client degrades safely until then: `life ?? {}` means no header and no `L` key. The merge gate should wait for #133, and the live `/api/life` check is still owed (learning #553).
2. Header never driven. `lifeHeader` is unit-tested only; no driven TUI screen has read it back (learning #554). Low risk because the function is pure.
3. Duplicated curve. `levelStart = 100·L²` in kit/life.ts mirrors the server's XP curve, but `LifeStatus.next_level_at` is already served. If the server curve changes, the header bar and the card diverge.
4. Silent failures. `loadCard` for "life" keeps the stale card on a null read (`?? lifeCard`), and `newRoutine` does not validate `every`, so a bad cron relies on the server's error toast. Acceptable.
5. Plan doc error. The plan's "899 fills the bar" case contradicts its own floor rule; the code is right (learning #555). Correct plan.md, not the code.

No security issues: all input goes through the existing `write` helper as JSON bodies, and the ids are numeric.