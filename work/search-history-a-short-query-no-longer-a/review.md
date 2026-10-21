# review — search-history-a-short-query-no-longer-a

**Verdict: approve.**

The fix addresses the real cause. `Search.history/3`'s meaning pass decoded and scored every
embedded message on the channel (~105MB, growing with the corpus), so a short query with weak
BM25 hits left the most rows for an unbounded Elixir cosine scan that could outrun the tool's
time budget and surface as "Internal error". The change bounds that pass to the newest 2,000
embedded messages (`semantic_window:`, `ORDER BY id DESC LIMIT $1` — PK-indexed, no sort) and
adds a per-query `timeout:` (default 10s, or `:search_timeout`) that turns an overrun into a
named `{:error, :timeout}`. The only caller, `Server.MCP.Tool.SearchHistory`, renders that as
`search_history timed out on "<q>": try fewer or rarer words` — never "Internal error".

Spec compliance: the scan is bounded with no vector index and no migration (within the stop
line); the timeout returns a readable named error; RED-then-GREEN tests cover the window, the
timeout, and the tool surface. `facts/2` is unchanged in behavior (its `count` now carries a
fixed 10s timeout — harmless). Gate green on the branch (1985 tests, 0 fail). The tradeoff the
tech lead flagged — messages older than the newest 2,000 embedded are findable by words only,
not meaning — is stated in `pr.md` and agreed intended (#11486–#11488); no moduledoc line
required.

## findings (non-blocking)

### guard the `e.postgres.code` access in the rescue
`history/3`'s rescue does `e.postgres.code == :query_canceled`. A `Postgrex.Error` can carry
`postgres: nil` (non-server errors), and that path would raise a `KeyError` inside the rescue
instead of reraising cleanly. Guard it: `e.postgres && e.postgres.code == :query_canceled`. The
canceled path is the one exercised, so this is latent, not live.

### a connection error is not a timeout
The rescue maps every `DBConnection.ConnectionError` to `{:error, :timeout}`, which the tool
renders as "try fewer or rarer words". A pool checkout failure or dropped connection is a DB
problem, not a too-broad query — harmless (the user retries) but mislabeled. Consider a distinct
message for the connection path, or one that doesn't blame the query.