Pause's settings writes log and return instead of raising. Closes #675.

**What changed**
- `Server.Pause` writes its settings through `write_setting/2`. A failed write (say, an unwritable settings directory) is logged and returned as `{:error, why}`. It used to be a `:ok =` match, so it raised out of pencils down, lights out, back to work and the auto pause.
- A failed pause write changes nothing: nobody is told, interrupted or resumed. `auto/1` writes its latch first and pauses only if that write lands. It returns `:ok` either way.
- `go/1`'s state change moved into `change/2`, which keeps the nesting within credo's limit.
- Public docs for `pencils_down/0`, `lights_out/0` and `back_to_work/0` name the `{:error, why}` return.

**Pinned by tests**
- The nil-`resets_at` latch: a window with no reset time fires once, and not again after `back_to_work`.
- The below-threshold no-op: nothing is latched, paused, enqueued or said, and no settings file is written.

**How it was checked**
- RED: the two write-failure tests failed with `MatchError` on `{:error, :enotdir}`. The two pins already passed.
- GREEN: `menard run test --in server test/server/pause_test.exs`: 25 tests, 0 failures.
- `menard run check --in server`: 2490 tests, 0 failures, exit 0.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
