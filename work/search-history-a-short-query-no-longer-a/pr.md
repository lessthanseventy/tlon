search_history: bound the meaning pass and name a timeout (closes #305, #260)

`Search.history/3` read and JSON-decoded every embedded message (~9KB each, ~105MB on the live
channel) on every query, so cost grew with the channel and a query could outrun the tool's budget
and answer "Internal error".

- The meaning pass now scores only the newest 2,000 embedded messages (`semantic_window:`); older
  messages are still found by their words.
- Each query is bounded (`timeout:` / `:search_timeout`, default 10s); a search that outruns it
  returns `{:error, :timeout}`, and `search_history` answers `timed out on "<query>": try fewer or
  rarer words`.

Tests (red before, green after): `search_test.exs` window and timeout; `search_tools_test.exs`
tool error. Not measured: before/after wall time on the live corpus. Out of scope: #258.
