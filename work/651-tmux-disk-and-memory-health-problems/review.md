APPROVE — 634a59f (health need: stable first-seen `at`).

Read the diff only; did not run the suite from this seat.

- Fix is right: `health/0` stamped `at: utc_now` on every read, so any verdict or dismissal was older than its item. `health_since/1` keeps first-seen per problem in persistent_term and drops it when the problem clears, so a reappearing problem gets a fresh time and resurfaces past an old dismissal.
- persistent_term is written only when the problem set changes (rare). Concurrent first reads can race to write the same value, which is harmless.
- Tests pin settle, dismiss and fail-open on health items. The fail-open test pokes `{Needs, :health_since}` with atom keys matching `vital_problems/1` (:tmux/:disk/:mem). The module is `async: false` and on_exit erases the term, so the global state stays contained.
- The test.exs reorder puts the comment back above its own config line.

No blocking findings.