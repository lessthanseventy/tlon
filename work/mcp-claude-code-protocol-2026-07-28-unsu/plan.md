# Plan — MCP: Claude Code protocol 2026-07-28 unsupported (anubis_mcp 2.0.0→2.1.0)

Scope is a dependency bump, not new code — no unit test exists for "server now speaks protocol
2026-07-28" or "journalctl is quiet." The red/green check for each task is the exact command
listed under Verify; task 4's is a live-log observation, per the ticket's own bar.

## Task 1 — Confirm current pin, bump anubis_mcp, lock 2.1.0

Files: `server/mix.exs` (read only, no edit expected), `server/mix.lock` (changes).

Before state (already true, confirm it): `server/mix.lock` line 2 pins
`"anubis_mcp": {:hex, :anubis_mcp, "2.0.0", ...}`. `server/mix.exs:126` already reads
`{:anubis_mcp, "~> 2.0"}` — this constraint is hex-compatible with 2.1.0, so it does **not**
need editing. If a diff shows mix.exs needing a change to allow 2.1.0, stop and re-check the
version constraint math before proceeding (that would mean the spec's diagnosis was wrong).

Steps:
1. `cd server && mix deps.update anubis_mcp`
2. Inspect `git diff server/mix.lock` — the only expected change is the `anubis_mcp` entry's
   version string `"2.0.0"` → `"2.1.0"` (and its content hash). No other dependency should move.

Definition of done: `server/mix.lock`'s `anubis_mcp` entry reads version `"2.1.0"`; `mix.exs` is
untouched; no other lock entries changed.

Verify: `grep '"anubis_mcp"' server/mix.lock` shows `2.1.0`.

## Task 2 — Gate green, commit the bump

Files: `server/mix.lock` only (staged from Task 1).

Steps:
1. `~/projects/menard/bin/menard run check --in server` — must report `ok`. If it reports
   failures, read them (file:line, assertion diff) before touching anything else; a lock bump
   that breaks the gate means 2.1.0 changed a behavior the suite depends on, which is new
   information for this workline, not a detail to route around.
2. `git add server/mix.lock`
3. Commit: `workline: bump anubis_mcp 2.0.0 → 2.1.0 (adds MCP protocol 2026-07-28)` with the
   `Co-Authored-By` trailer for whichever model/harness runs this task.

Definition of done: gate passes; `server/mix.lock` bump is committed on
`work/mcp-claude-code-protocol-2026-07-28-unsu`.

Verify: `~/projects/menard/bin/menard run check --in server` exits reporting `ok`;
`git log --oneline -1 -- server/mix.lock` shows the new commit.

## Task 3 — Ship the bump to the live service

No file changes — this is a deploy step. Confirm with the operator before restarting a shared
service (this is the always-up `tlon` systemd unit other coworkers' MCP sessions depend on).

Steps:
1. `mise run server:release`
2. `mise run server:restart`
3. Note the restart timestamp (`systemctl --user status tlon` or the restart command's own
   output) — Task 4's log window starts here.

Definition of done: the live `tlon` service is running the build that contains anubis_mcp 2.1.0.

Verify: `mise run server:logs` (or `journalctl --user -u tlon -n 20`) shows a fresh startup
after the restart timestamp, no crash loop.

## Task 4 — Watch a fresh live window, close or spin off

No files — this is the ticket's acceptance bar, checked against real traffic (new Claude Code
MCP sessions negotiating against the restarted service).

Steps:
1. Wait for at least one fresh MCP session to connect and negotiate after the Task 3 restart
   (the next Claude Code coworker session startup qualifies).
2. `journalctl --user -u tlon --since "<Task 3 restart timestamp>"` — count occurrences of each
   of the three messages: `unsupported_protocol_version`, `sse_unknown_message` /
   `:read_timeout`, `sse_keepalive_failed`.
3. Branch on the result:
   - **`unsupported_protocol_version` count is 0, and the SSE pair is also 0**: bar met for all
     three. Nothing further to file — the SSE pair was a downstream symptom of the version
     mismatch, as the spec's "downstream symptom" reading predicted.
   - **`unsupported_protocol_version` count is 0, but the SSE pair is still nonzero**: this
     ticket's own scope (protocol-version mismatch) is fixed — close it on that basis, per
     spec.md §"Fix shape" step 5. Call `file_ticket` for the SSE idle-timeout/keepalive pair as
     its own issue (point it at spec.md §3's "separate bug" reading as the starting diagnosis),
     don't block this workline on it.
   - **`unsupported_protocol_version` count is still nonzero**: the bump did not take on the
     live service (check Task 3 actually restarted the right build — e.g. `mise run
     server:release` ran before `server:restart`, not after) or the diagnosis in spec.md is
     wrong. Do not advance past this task until it's 0.

Definition of done: a fresh live window after the Task 3 restart shows zero
`unsupported_protocol_version`; the SSE pair's outcome (cleared vs. filed as a new ticket) is
recorded in a message to the thread.

Verify: the `journalctl` command above, read against the restart timestamp — this is the
ticket's own bar, verbatim.
