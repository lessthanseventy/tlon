# Review: intake-auto-start-and-continuation-nudge

**Verdict: approve**

Round 2, at 932fc27. Branch vs origin/main: tests only (server/test/server/pause_test.exs +19, server/test/server/maintain_test.exs +25) plus work/intake-auto-start-and-continuation-nudge/pr.md. No production code changes: main already gates `Intake.run` (intake.ex:24) and `Workline.Continuation.run` (continuation.ex:39) on `Pause.state() == :working` since 2bdf1d3 (#172). This PR pins the two paths pause_test did not cover: the 30-minute `start_stalled` fallback and the Maintain quiet-band sweep, each with its resume half.

## Round 1 findings, checked

1. **Fixed.** maintain_test.exs:173-182 now saves `prior = Application.get_env(:server, :operator_config_path)` before the `put_env` and restores it in `on_exit` (`delete_env` only when there was no prior). Identical to the pause_test.exs pattern. The suite no longer falls back to the operator's real `~/.config/tlon/config.json` after this test.
2. **Fixed.** pr.md committed: tests only, fix is 2bdf1d3 (#172), closes #179, names #262 as the gap not covered. Publish has a body.

Diff since 1cdbf25 outside work/: the 6-line on_exit change only.

## Evidence

- Server verify on the branch: `mise run check` exit 0 (recorded 2026-10-13T11:09:08Z, server:check 9 passed / 0 failed).
- Builder reports the full server suite on 932fc27: 1602 tests, 0 failures (ireneo, msg #6947). Not re-run by me.
- Commit carries the model trailer (claude-sonnet-5-5) and Tlon stamps.

## Not in scope, already tracked

`staff_child`, `/api/tickets/:id/start` and `ticket-start` do not check Pause (fact #1639). Tracked as ticket #262; my round-1 follow-up #267 is a duplicate of it, so no follow-up is re-filed here. If the live service predates 2bdf1d3, the #248/#250 starts under pencils down are explained by that alone and `server:restart` is the fix.
