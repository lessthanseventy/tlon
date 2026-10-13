Closes ticket #286 — two sessions per coworker handle acting at once after a restart.

**Why.** A window the server kills (`kill-window` = SIGHUP) can leave its harness process alive.
Tokens are stateless and wakes are keyed by (thread, handle), so that survivor and the respawn both
resolve to the one live session and both drain wakes. Nothing server-side could tell them apart.

**What.** `Server.Orphans` finds processes whose environment holds `TLON_THREAD`+`TLON_AUTHOR` for a
seat (via `/proc/*/environ`) and SIGTERMs them; `Arbiter.Tmux.spawn` calls it once the seat is
known windowless, before opening the new window. One seat, one process taking wakes.

**Unverified.** The surviving-process cause is inferred from the code and the incident's
Claude-Session trailers; it could not be observed from the sandbox. Not covered: a survivor under a
*different* thread/handle env, and the "restarted mid-turn" notice still addresses by handle.

**Checked.** `menard run test --in server`: 1624 tests, 0 failures (new: `orphans_test.exs`, a spawn
test in `arbiter_tmux_test.exs`).

Resolves issue #33 (ticket #286).
