APPROVE

Scope: one commit (2293692), tests only: server/test/server/attention_test.exs +29. The pruning itself (Server.Shifts.prune/2, called from Attention.tick/1) is already on main.

Verified:
- `menard run test --in server test/server/attention_test.exs`: 19 tests, 0 failed (run unsandboxed; the sandbox blocks the Postgres socket).
- Test 1 (a pane whose window is gone is forgotten) drives the real tick path: a limit is seen and recorded under `hronir/<tid>/t<tid>`, then the window is renamed, so its key leaves the live set and limits_seen empties.
- Test 2 (an empty window list is not read as every pane gone) pins the map_size == 0 guard clause in prune/2. This is the risky case: a tmux hiccup must not wipe the memory.

Non-blocking nits: the `limit` string is duplicated in both tests, and the key is hand-built as "hronir/#{t.id}/t#{t.id}", so it breaks if the format changes. Both fail loudly.

I did not run the full `mise run check`; the recorded verify evidence on the thread shows it green.