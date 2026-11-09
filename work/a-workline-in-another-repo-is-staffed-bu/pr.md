A lead whose spawn is refused now says so on its thread.

`Switchboard.maybe_spawn_absent` filtered `Spawn.join/3`'s `{:error, _}` out of its comprehension, so a refused checkout (worktree failure on the thread's repo) dropped the lead with no trace but the 1h stall alert. `join_exports/3` now posts the same "could not be seated" notice, with the reason, that a refused pane spawn already did.

Closes ticket #864 (workline #550). A test also pins that a thread in a second git repo spawns its lead in that repo's worktree (`TLON_CWD`): the non-tlon path itself works, the silence was the bug; the original #550 refusal reason is not recoverable from the logs.

Checked: `menard run test test/server/switchboard_test.exs` (67 tests, 0 failures; the refused-checkout test red first).
