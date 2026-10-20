release:smoke runs main's script, not the launching checkout's (#273)

`mise run release:smoke` now goes through `scripts/run-from-root.sh`, which execs the shared root
checkout's (kept at main) `release-smoke.sh`. A seat on an old base that has the wrapper no longer
smokes with its own old script (one-Escape drive, no lock, old sweep). Picked (a) over (b) and
combined with the root-checkout route: refusing a stale checkout only works where the guard already
exists (aad4dcc), and neither reaches a checkout too old to have the new task — that one needs a
rebase, which AGENTS.md now says. The nightly (schedule 4) runs in `.release`, so it also goes
through the wrapper.

Closes ticket #273. Also resolves ticket #430 (canvas_paint_test: no auto-gc on the scratch remote, so on_exit no longer races a detached gc).

Checked: `server/test/server/run_from_root_test.exs` — a worktree on an old base prints
`new-script work/x` (root's copy) — was red (wrapper missing), green now; `mix test` on it,
fresh_script and release_smoke_script tests: 27 passed; `mise run manual:check` clean. No real
smoke run (box shared; one at a time).
