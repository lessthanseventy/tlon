release-smoke waits for a live holder of its commit lock instead of exiting 1.

A scheduled smoke that met a by-hand smoke of the same commit failed "already being smoked" (red on #189, main fine). Now a live holder is waited for with `flock -w TLON_SMOKE_LOCK_WAIT` (default 3600s; 0 = the old immediate refusal), then the run smokes and records its own ran-on. A holder that outlasts the bound fails "timed out waiting for (<holder>)". The gone-holder reclaim path is unchanged.

Closes ticket #603.

Checked: `menard run test --in server test/server/release_smoke_script_test.exs` — red first (both new tests), now 30 tests, 0 failures. Existing refusal tests pin `TLON_SMOKE_LOCK_WAIT=0`.
