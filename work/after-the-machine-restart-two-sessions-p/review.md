# Review — after-the-machine-restart-two-sessions-p (round 1)

**Verdict: request_changes** — the fix is right and small; two cheap gaps send it back, both docs-only.

## What I verified

- `Server.Orphans.holders/3` matches whole env entries (`want -- split == []`), so `TLON_THREAD=2621` cannot match seat 262; it skips the BEAM's own pid and unreadable `/proc` entries. The launcher really exports exactly `TLON_THREAD`/`TLON_AUTHOR` (`lib/server/mcp/spawn.ex:149`, `adapters/claude-code/launch.sh:50`), unquoted once the shell evals them, so the match strings are correct.
- Wiring sits after `:absent <- running(...)` in `Arbiter.Tmux.spawn` (`lib/server/arbiter/tmux.ex:56`). Both spawn doors (`Switchboard` and the coordination tool) go through `Arbiter.spawn`, so every coworker respawn passes it. Note the fix does not depend on the inferred "kill-window leaves the harness alive" cause: any local process still holding the seat's env is retired, whether its window vanished or `running/4` simply failed to match it. Good.
- Test config pins `proc_dir: "/nonexistent"`, and `arbiter_tmux_test` is `async: false`, so the temporary `put_env` cannot race another module. Verify's `mise run check` passed on this branch (brief, 17:30:15Z); I did not rerun it.

## Blocking

1. **`issue #33` is not named anywhere.** The sheriff (#7392) asked for it in `pr.md` and a commit message so the landing resolves the issue; emma (#7405) deferred it until verify finished. Approving now hands the branch to the merge gate with no chance to add it. Add a line to `pr.md` ("Resolves issue #33.") and put `issue #33` in that commit's message.

2. **`config/test.exs` comments now describe the wrong lines.** The `mix format` commit (a549f75, Quokka sorts config) moved `release_root`/`souls_dir` under the consult-mirror comment, leaving the PM comment above nothing. Stable fix (already in sorted order, so the formatter leaves it):

```
 # The PM's release desk acts on the tlon checkout (Server.Release.PM): a test hands it a throwaway
 # repo, so one that forgets can never cut a release of the real one.
-# The consult mirror is off in tests: the pure maybe_mirror tests call it directly, and the
-# round-trip test starts it explicitly. An always-on subscriber would double-mirror.
 config :server, release_root: "/nonexistent/tlon-test-release"
 config :server, souls_dir: Path.join(System.tmp_dir!(), "tlon-test-souls-unset")
+# The consult mirror is off in tests: the pure maybe_mirror tests call it directly, and the
+# round-trip test starts it explicitly. An always-on subscriber would double-mirror.
 config :server, start_consult_mirror: false
```

## Non-blocking (filed as follow-ups)

- Crew windows (`Server.Crew.Tmux.open_window`) do not call `Orphans.retire`, so a killed reviewer window's survivor can still twin.
- `retire/3` sends SIGTERM once and opens the new window at once: no wait, no SIGKILL escalation, and only a server log line. The ticket's fallback ("at least say on the thread that two are live") is not met; a notice on the thread when a holder is retired would give the operator the evidence the log now hides.
- The "machine restarted mid-turn" notice is still addressed by handle (emma's own caveat). With one process per seat it reaches the right session, but the addressing is still by handle.
