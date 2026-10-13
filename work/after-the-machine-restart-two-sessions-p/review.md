# Review — after-the-machine-restart-two-sessions-p (round 2)

**Verdict: approve.**

## What changed since round 1 (b82c53f)

`git diff b82c53f..HEAD -- . ':!work/…'` is only `server/config/test.exs`: the consult-mirror comment moved back over `start_consult_mirror`, leaving the PM comment over `release_root`/`souls_dir`. That is the exact patch round 1 proposed, and the keys stay in sorted order, so the formatter leaves it. No code change.

`pr.md` now ends "Resolves issue #33 (ticket #286)." and commit 5ad5a47's subject names issue #33, so the landing can resolve the issue. Both round-1 blockers are closed.

## Still holds from round 1

- `Server.Orphans.holders/3` matches whole env entries, skips the BEAM's own pid and unreadable `/proc` entries; the launcher exports exactly `TLON_THREAD`/`TLON_AUTHOR`.
- Wiring sits after `:absent <- running(...)` in `Arbiter.Tmux.spawn`; both spawn doors go through it.
- Test config pins `proc_dir: "/nonexistent"`; `arbiter_tmux_test` is `async: false`.
- Verify's `mise run check` passed on 5ad5a47 (brief, 17:49:41Z, exit 0). I did not rerun it.

## Non-blocking (filed as follow-ups)

- Crew windows (`Server.Crew.Tmux.open_window`) do not call `Orphans.retire`, so a killed reviewer window's survivor can still twin.
- `retire/3` sends SIGTERM once with no wait, no SIGKILL escalation, and only a server log line; the ticket's fallback ("say on the thread that two are live") is not met.
- The "machine restarted mid-turn" notice is still addressed by handle.
