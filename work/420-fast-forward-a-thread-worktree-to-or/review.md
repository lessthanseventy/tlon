# Review — workline 420-fast-forward-a-thread-worktree-to-or @ e82312e

**Verdict: approve.** Second round. Every finding of the first review (7c8a114) is fixed, the tech lead's wake-only call is in, and verify's `mise run check` passed on this tip (exit 0, 13:58:31Z; the gate ran on the branch checkout, so `tlon/check` was not posted — expected). No bench_contrast row in the CHECKS shown.

## The first round's findings, checked against the diff

1. **Status line woke or spawned the lead** — fixed. `say_once/4` now posts `kind: "notice"`, and the test asserts `[%{kind: "notice"}] = told`.
2. **Ahead line spoke when the branch was not behind main** — fixed. `tell_catch_up({:ahead, n}, …)` runs `rev-list --count HEAD..origin/main` and returns `:ok` on `"0"`; the test commits on top of main and asserts no line, then moves main and asserts exactly one.
3. **Hook mid-turn under a live pane** — fixed per hronir (msg #15362). `Server.worktree_for_thread/1` is pure again (ensure + mark_thread). The catch-up is `Server.catch_up_worktree/2`, called once from `Spawn.cwd_export/2`, and only when `agent.name not in Server.Outside.names()`: an outside citizen's `dir` is the repo root, and that guard is what keeps `merge --ff-only` off the live main checkout. The facade test does `refute File.exists?(NEW)` after `worktree_for_thread` on a behind checkout, then moves it through `catch_up_worktree`; `spawn_test.exs` moves it through `Spawn.join`.

Follow-ups from the first round:
- `tlon-reported` is reset on `:moved | :level` (`report_once?(wt, "level")`), and the dirty → clean → dirty test asserts the second line.
- `{:error, why}` from `catch_up/1` is logged at warning.
- The per-tool-call git cost is gone with the move: zero subprocesses outside a spawn.

## Spec compliance

- Detached HEAD → `:detached`, untouched (verify-frozen checkouts stay put).
- Dirty tree → `:dirty`, told once per state.
- Branch + clean + `merge-base --is-ancestor HEAD origin/main` → `merge --ff-only -q origin/main`.
- Own commits → `{:ahead, n}`, untouched, told once per tip (`ahead:<tip>:<n>`), and only when main has moved on.
- No fetch anywhere in the path; ancestry, not patch identity.
- No `origin/main` ref → `:level`, so a repo without a remote is a no-op.

## Checked, not findings

- `Server.Outside.names()` is evaluated twice in `cwd_export/2`; harmless, and not worth a round.
- `report_once?` compares before writing, so a level checkout does not rewrite the marker on every wake.
- pr.md names the design (wake-only, bench agents only), the ticket, and the tests run.