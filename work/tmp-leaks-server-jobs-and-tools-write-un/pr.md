# /tmp leaks: test writers use a dir the run cleans

Refs #560 (folds #553). The suite's writers that left entries in the shared tmp dir now use a dir they remove, or already did; three writers stay open (below).

## What changed

- `office/test/cast-file.test.ts`: each `cast-file-` dir is removed after its case, as `whimsy-file.test.ts` does. Measured before: 5 new dirs per run (30 → 35). After: 0 (35 → 35).
- `server/test/server/maintain_test.exs`, `server/test/server/office/needs_test.exs`: the `maintain-quiet-*`, `needs-quiet-*` and `needs-pause-*` config files are written to `server/tmp/`, which the suite removes before and after a run. `test_helper.exs` creates that dir up front. Measured before: `maintain-quiet` +1 per run (32 → 33). After: 33 → 33; `needs-quiet` 39 → 39, `needs-pause` 39 → 39.

## Per prefix

| prefix | writer | state |
| --- | --- | --- |
| `cast-file-` | office/test/cast-file.test.ts | fixed (aa7773e) |
| `maintain-quiet-` | server/test/server/maintain_test.exs | fixed (e706af3) |
| `needs-quiet-`, `needs-pause-` | server/test/server/office/needs_test.exs | fixed (e706af3) |
| `hall-` | office/test/hall.test.ts (cleans after each case) | no new writes: 150 → 150 over the run; the 150 are pre-#549 leftovers |
| `whimsy-` | office/test/whimsy-file.test.ts (cleans after each case) | no new writes: 69 → 69; the 69 are pre-fix leftovers |
| `tlon-smoke-job-*.log` | server/lib/server/jobs/smoke.ex | OPEN: the log's path is posted to the thread for the operator to read, so removing it after a run breaks the link. Needs a persistent dir chosen by the operator. |
| `menard-format-*.log` | menard repo, not tlon | OPEN: needs its own route (#473). |
| `srt-mux-*.sock` | Claude Code's sandbox | OPEN, out of scope. |

Entries already in the tmp dir are not deleted here; that is the operator's call.

## How it was checked

- `~/projects/menard/bin/menard run check --in server`: `{"ok":true,"tests":1982,"failed":0,"failures":[]}`.
- `bun test test/cast-file.test.ts` (office): 6 pass, 0 fail.
- `bun test test/hall.test.ts test/whimsy-file.test.ts` (office): 35 pass, 0 fail.
- `mise run check` was not run from this seat: the checks queue needs an unsandboxed shell (`/run/user/1000/tlon-checks.lock`). The server gate above is the same gate's server part.
