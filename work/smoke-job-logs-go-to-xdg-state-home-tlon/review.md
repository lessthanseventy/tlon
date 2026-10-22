## approve — smoke-job logs go to XDG_STATE_HOME/tlon/smoke, pruned after 7 days

Reviewed b8364f0 against the brief's goal (the line has no spec.md/plan.md by design — the brief is the spec): *smoke-job logs go to `$XDG_STATE_HOME/tlon/smoke/` with a 7-day prune, not `/tmp` (#572)*. Verify already gated it (`mise run check` exit 0). The diff does exactly what was asked, nothing more.

**What I checked**
- `state_home/0` resolves `XDG_STATE_HOME` then falls back to `~/.local/state` — correct XDG behaviour. Log is now `tlon/smoke/smoke-job-<id>.log`, out of `System.tmp_dir!()`.
- `prune/1` runs at the top of `perform`, before the port opens and before this job's log exists. Best-effort `File.rm` on anything whose mtime is older than `@log_ttl` (7×86400); scoped to the smoke dir, errors swallowed by the `with`. Concurrency-safe: the queue is `smoke: 2`, two concurrent performs prune idempotently, and a log being written has mtime=now so it is never swept.
- Tests: setup points `XDG_STATE_HOME` at a pid+unique tmp dir (never the real `~/.local/state`) and restores/deletes on exit. The first new test proves the log lands in the state dir and not the OS tmp; the second backdates a file 8 days and proves it's pruned while a fresh one stays. Both assert on real assertions, not on setup.
- No stragglers reference the old `tlon-smoke-job-` tmp path; the moduledoc names no location, so it isn't stale.

**Findings**: none blocking, none worth filing as follow-ups. The change is correct, minimal, and surgical — only the log path and the prune, plus the tests that prove them.

Co-Authored-By: glm-5.2 <noreply@ollama.com>