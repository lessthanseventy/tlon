APPROVE — #659 Room.vitals ETS cache

Read: `git show 2af0371 4c8ccb7`, plus a grep of the other callers of `vitals`. I did not run the suite. The pr.md reports the gate green at 2535 tests, and I have not checked that independently.

- **Table lifetime:** `init_vitals/0` is called from `Application.start/2` right after `Tool.init_fence/0`, so it has the same owner and lifetime as the fence table.
- **Read path:** the TTL check and the `:ets.insert` match the old `:persistent_term` semantics. `now` is injectable through the default argument. No `persistent_term.put` remains on this path, which is the point of the ticket.
- **Test:** `room_test.exs` is `async: false`, so the planted fake reading can't leak into other tests. `on_exit` deletes the row. It covers both sides of the 60s boundary (59_999 served from the table, 60_000 refreshed).
- **Other callers:** `needs.ex` calls `vitals/0` through the default argument, which still resolves. The `needs_test` override replaces the whole reading function, so it isn't affected.
- **Scope:** only vitals changes. pr.md names the other persistent_term TTL sites as a separate follow-up.

Nit, not blocking: the `@spec` now covers arity 1 only, so `vitals/0` has none.