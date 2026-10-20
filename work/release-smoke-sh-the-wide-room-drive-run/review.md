# review — release-smoke-sh-the-wide-room-drive-run

verdict: approve

## what's on the branch

Two commits:

- **ec1d37e** `smoke: the wide-room drive runs with no playerctl player` — the fix for #459. `scripts/release-smoke.sh` only: the wide-room drive runs with a `playerctl` shim (exits 1) first on PATH, so the stereo stays at "no signal" whatever the host is playing.
- **2ad387d** `office: the hall's taken-name test gets its own tmux socket` — a flake fix that unblocked verify: the second hall-hire test reused the first test's tmux socket right after `kill-server`.

## ec1d37e — the playerctl shim

Mechanic verified by reading the code, each link confirmed:

- `office/tui/main.ts:982-983` — `pollPlayer()` runs `playerctl metadata`; on any non-zero exit it calls `rm.setPlayer(null)`.
- `office/rooms/wide.ts:933` — draws `"no signal"` when `this.player` is null.
- The shim (`#!/bin/sh; exit 1`) makes every `playerctl` call exit 1, so the stereo reads "no signal". Correct.
- PATH propagation: `office-drive.sh` runs the TUI under tmux `new-session`, which inherits the parent env, so `PATH="$noplayer:$PATH"` reaches `bun` and its `Bun.spawnSync(["playerctl",...])`. Sound.
- Surgical scope: the shim is built and cleaned around the wide-room drive only (lines 212-215). `rm -rf "$noplayer"` runs even on a failed drive (the script has no `set -e`), so no leak on failure; an interrupted run leaks one mktemp dir in `$TMPDIR` — acceptable.
- `bash -n` clean. `release_smoke_script_test` passes (24) but does not exercise the shim — the wide-room step is mock-free in that suite — so the shim is proven by code reading + the live smoke, not the unit suite.

## 2ad387d — the hall-hire socket fix

- Sound: the second test kills the first server (line 58, on the old socket), then reassigns `socket` to a fresh name; `launch`/`tmux` close over the `let socket`, so the second test runs on its own server. `afterAll` kills the surviving (hall-taken) server.
- Honest caveat from the builder: no red run was captured (30/30 clean probes, CPU-load attempt denied), so this is a fix for the most likely race, not a root-caused one. The full office suite is green (779 pass). Low risk — an isolated socket can only make the test more robust, not less.
- Minor cleanup regression (follow-up): `afterAll` removes only the current `socket`'s tmux socket file (line 30); the first test's `tlon-office-hall-hire-${pid}` socket file is no longer cleaned.

## verify debt — the live smoke was never recorded

The tech lead's verify spec (#9772) required a live `mise run release:smoke`, unsandboxed with music playing: red on origin/main, green on this branch, both `record_check`'d. The operator handed both runs to Uqbar (#9786). No result was posted — the thread has no exit codes from that run, and no `record_check` for it exists. The verify stage passed (`mise run check`, green), but that is the full gate, not the live smoke; it does not exercise the shim against a real playing player.

The fix is mechanically certain from the code and low-risk. But the specific end-to-end proof the tech lead asked for is missing, and only the operator/Uqbar can produce it (host music + an unsandboxed run). I'm approving the code — it is correct — and flagging this so the operator can decide whether to hold the merge for the live smoke or accept the code-reading proof.

## follow-ups

1. **Live smoke red→green for #459 never recorded.** Handed to Uqbar (#9786); no exit codes posted, no `record_check`. Operator/Uqbar to run `mise run release:smoke` unsandboxed with host music on origin/main (red at the wide-room step) and on this branch (green), `record_check` both. The verify stage's `mise run check` does not exercise the shim against a playing player.
2. **hall-hire.test.ts leaks the first test's tmux socket file.** `afterAll` (line 30) removes only the current socket's file; after 2ad387d reassigns `socket`, the first test's `tlon-office-hall-hire-${pid}` socket file in `TMUX_TMPDIR` is no longer cleaned. Remove both.