# Review: intake-auto-start-and-continuation-nudge

**Verdict: request_changes**

Branch 391b280 vs origin/main: tests only, 40 lines (server/test/server/pause_test.exs, server/test/server/maintain_test.exs). No code change: main already gates `Intake.run` (intake.ex:24) and `Workline.Continuation.run` (continuation.ex:39) on `Pause.state() == :working` since 2bdf1d3 (#172). This PR pins the two paths pause_test did not cover: the 30-minute `start_stalled` fallback and the Maintain quiet-band sweep, each with its resume half. Server verify passed `mise run check` on the branch.

## Blocking

1. **maintain_test.exs:171-178 leaks the operator's real settings file into the rest of the suite.** The test sets a tmp `operator_config_path`, then `on_exit` calls `Application.delete_env` instead of restoring the value config/test.exs set (`/nonexistent/tlon-test-config.json`). Once deleted, `OperatorConfig.path/0` (operator_config.ex:153) falls back to `~/.config/tlon/config.json`. Every test that runs after it in the same VM (the module is `async: false`; module order is random) reads the operator's real pause state and `*_minutes` settings, and any later `Pause.pencils_down()` would write his real config. With pencils down set for real on this box, later `Intake.run` / `Continuation.run` tests go red. Fix: restore `prior` exactly as pause_test.exs:17-33 does.

2. **`work/intake-auto-start-and-continuation-nudge/pr.md` is not committed.** The build brief asked for it, and `Server.Workline.Publish` (publish.ex:171) uses it as the PR body, falling back to a plan/spec heading; this workline has neither, so the PR would publish with an empty description. A few lines: pinning tests only, fix already on main as 2bdf1d3 (#172), closes #179.

## Verified

- pause_test: a `todo` ticket 31 minutes stale, one seated builder; under pencils down `Intake.run` starts nothing and the ticket stays `todo`; after back_to_work it is promoted. Exercises `start_stalled` through the real gate.
- maintain_test: a `plan`-stage workline, `quiet_ms: 0`; no `↻ continue` while paused, one after resume. Exercises `sweep_quiet` → `Continuation.run(quiet: true)` through the real gate.
- Commit carries the model trailer (claude-sonnet-5-5) and the Tlon stamps.

## Not in scope

`staff_child`, `/api/tickets/:id/start` and `ticket-start` do not check Pause (fact #1639). A manager or operator start under pencils down is a different path from intake; filed as a follow-up, not folded in. If the live service predates 2bdf1d3, the #248/#250 starts under pencils down are explained by that alone and `server:restart` is the fix.