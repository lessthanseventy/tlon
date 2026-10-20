drive_smoke: launch the office drive like the smoke job, from the smoke's build dir

`Server.Smoke.drive/2` ran `scripts/office-drive.sh` bare from the checkout, so its tmux shell put the
mise shims first and `bun` demanded trust for the checkout's mise.toml: no screen came back (#431).

- The drive now goes through `Jobs.Smoke.launch/1` (`mise exec -- bash`, `MISE_YES=1`), the one launcher the smoke job uses.
- `release-smoke.sh` prints its build dir on the hold line (`holding URL up (dir DIR)`); the job stores it in meta beside `url`; the drive runs the candidate's own script from it, falling back to the checkout for old holds.

Closes #431 once `drive_smoke(["/"])` returns a screen against a live held smoke after release (still to check).
Checked: `jobs/smoke_test.exs` red before (mise trust error), green after; with release_smoke_script_test 27 tests, 0 failed. The full server gate has 12 staffing_test failures that also fail on a clean tree (#432).
