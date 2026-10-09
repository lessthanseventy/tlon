VERDICT: approve

Read: git diff main...HEAD (2 commits; roles.ex, runner.ex, 2 test files, README row, results JSON). Gate evidence on the thread: `mise run check` exit 0 (9 passed · 0 failed). I did not re-run it.

What I checked
- stream-json + --verbose: `parse_output` still finds the final `type: result` line, and a timeout-killed run (no result) falls back to usage summed from streamed assistant events. The new test covers that fallback, including a non-assistant init line.
- Per-task test DB: `TLON_TEST_DATABASE` is unique per run and sanitised to `[a-z0-9_]`. It goes to both the role's shell and the check, and is dropped with `--force` after grading and in the reference-check path. This closes the "workdir `.git` makes config/test.exs hit the live tlon_test" hole.
- Beam wipe: only `server/_build/*/lib/server` (the app's own beams) is removed; deps' beams stay, and the test asserts both.
- Timeout: `"senior" => 1800` keyed on task.set; builder stays at 900.
- README row/result match the commit message (6/6, $1.627).

Non-blocking
- `drop_database/1` raises `:enoent` if `dropdb` isn't on PATH, which would kill a bench run after grading and lose the result. Guard or ignore.
- `timeout_s/1` doc says "half an hour for a sourced (senior) task" but the key is `task.set`, not `task.source`. Reword.
- The `parse_output` @doc has one overlong line; the formatter apparently accepts it.