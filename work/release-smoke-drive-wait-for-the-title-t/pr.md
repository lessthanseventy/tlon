release-smoke: the office drive waits for the title, not a fixed 2 s

`scripts/release-smoke.sh` drove the office on a fixed `OFFICE_WAIT=2`. A cold TUI can take its
first snapshot later than that, so the find of the smoke's thread missed it (ticket #453, issue #24).
The drive now waits for the title before `/` and for the thread's header after `Enter`, when the
drive supports `wait:TEXT` (the same gate the existing header wait uses).

Closes #453 (smoke side only; the office/test/refresh side #452 is held).

Checked: `menard run test --in server test/server/release_smoke_script_test.exs` → 23/23 ok, the new
test red before the change (no title wait before the find) and green after. `mise run check` not yet
run from this sandbox (checks queue refused); see the thread.
