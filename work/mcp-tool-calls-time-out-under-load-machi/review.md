# Review — mcp-tool-calls-time-out-under-load-machi

**Verdict: approve.**

Reviewed: `git diff main...HEAD` (8990d38, 0ef1c39, 5a85f34): `server/lib/server/board.ex`, `server/lib/server/recall.ex`, `server/test/server/board_test.exs`.

## Spec compliance

- **machine_overview never recalls.** Each row now reads `Dossier.open_todos_for_thread`, `Dossier.open_issues_for_thread`, `Channel.recent_messages` and `lead_name/1` directly, carrying lead, stage, awaiting, next, blockers, recent, the fields the meta agent uses. No `brief/1`, no `Recall.*` on the path. The regression test counts connections to a stub ollama listener and asserts 0.
- **Board.brief embeds once.** `recall_opts/1` calls the new `Recall.embed_query/1` once and passes `query_embedding:` to both `thread_learnings` and `thread_knowledge`. Test asserts 1 connection.

## Correctness

- `query_vector/1` now uses `Keyword.has_key?(opts, :query_embedding)`, so an explicit nil (embedder down, or blank query) short-circuits instead of falling back to a second embed. Board is the only caller that passes the key; `working_set_test` passes `[]`, truthy under both old and new logic; `Search.history` has its own `query_vector` and is untouched.
- `embed_query(nil)` returns nil, matching the old `recall_query` nil behaviour (uniform relevance).
- Test harness: `Server.Recall.Embedding.embed/2` reads `:endpoint`/`:timeout` from app env at call time, issues one `:httpc` request, no retry; `board_test` is `async: false`, so the `put_env`/restore is safe and the count is exact.

## Nits (no ticket)

- `count_embeds/1` waits 50 ms for the acceptor's `:embed_connection` message before counting. Fine in practice, but a `receive … after` on the first message would remove the timing assumption.

## Verification

I could not run the suite from this seat: the sandbox refuses the Postgres unix socket (`tcp connect (/run/postgresql/.s.PGSQL.5432): not owner - :eperm`). The server's verify stage ran `mise run check` on this branch and passed (CHECKS at 2026-10-13T03:41:11Z, exit 0); the builder reported `menard run check --in server` ok, 1570 tests, 0 failed. Those runs are the evidence.
