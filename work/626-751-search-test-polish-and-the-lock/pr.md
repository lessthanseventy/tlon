Closes #626 and #751.

**#626 — search_test polish.** Three behaviour-free fixes in `server/test/server/search_test.exs`:
- The `assert_receive :locked` in the outruns-its-time test now has a 5s bound, matching the one already on the bounded-query tests.
- The idf check no longer matches a SQL comment. It asserts `idf AS MATERIALIZED` on the first ranking query captured from telemetry.
- Telemetry handlers are an exported `handle_query/4` instead of anonymous closures, and are detached `on_exit`, so a failing test cannot leak its handler.

**#751 — the lock holder's flake.** In the two for-loop tests the lock holder's self-release moved from 300ms to 5s. Under a loaded gate the 300ms release could fire before the query reached Postgres, so the query was not the one timing out. The release is still bounded, so an unbounded query still fails rather than hangs.

**How it was checked.**
- `menard run test --in server test/server/search_test.exs`: 18 tests, 0 failures, before and after.
- `menard run check --in server`: 2486 tests, 0 failures, credo clean.

Note: these are polish changes on already-green tests, so there was no red step to show. The #751 flake is not reproduced here; the fix removes the 300ms race by construction.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
