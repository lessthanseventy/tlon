# APPROVE — sessions-outlive-server-stop-and-tmux-re

## Verdict

**Approve.** The fix is correct, minimal, and well-scoped; the gate passes. Two non-blocking follow-ups filed below.

## What the change does

At each staffing pass, `end_predating_tmux/1` asks the workspace's tmux server for its `#{start_time}` and ends every still-open session whose `started_at` predates it and that carries a `pane_ref`. tmux renumbers panes from `%0` on every server start, so a session that began under a previous tmux server is pointing at a reused id — a wake routed by that `pane_ref` would land in the wrong seat. Ending it is the fix.

## Why it's correct

- **The comparison is conservative-safe.** No pane survives a tmux server restart (ids are reused from `%0`), so any session with `started_at < tmux start_time` is definitively stale. A session that started after the server cannot predate it, so live sessions are never touched in steady state.
- **Runs every pass, not just at boot.** This is stricter than the ticket's "at boot" wording and correctly handles a tmux-only restart (operator killing tmux without `server:stop`). Cheap: one `display-message` + one bounded query per pass.
- **Ordering is right.** Called after the reap/sweep chain, before `resume_interrupted` and `end_windowless`. `Staff.interrupted/1` filters `is_nil(ended_at)`, so a session ended here is not resumed or re-ended downstream.
- **No `thinking_since` guard.** Unlike `end_windowless`, this ends mid-turn predating sessions too — correct, since the pane is gone regardless of warmth. This is the load-bearing behavioural difference.
- **Safe degradation.** `Tmux.server_started/2` returns `nil` on any fault or unparseable output; `end_predating_tmux` then ends nothing, matching the module's "a tmux that can't be asked skips the pass" contract.
- **Comment is load-bearing, no devlog.** States the why (pane-id reuse) without incident narration.

## Follow-ups (non-blocking)

1. **Test overclaims "even mid-turn".** The new test creates `dead` via `session!("borges", here.id, 30)`, which defaults `thinking? = false` — idle, not mid-turn. The behaviour that distinguishes `end_predating_tmux` from `end_windowless` is precisely that it ends mid-turn predating sessions (no `is_nil(s.thinking_since)` guard). That branch is unexercised; a regression adding the guard would pass the suite. Add a `dead` variant with `thinking?: true` and assert it is ended.
2. **`server_started` nil path untested.** No test covers tmux up (`list-windows` succeeds) but `display-message #{start_time}` failing or returning unparseable output (e.g. a tmux build without `start_time`). Degrades safely to "ends nothing" by design, but the nil branch has no coverage.