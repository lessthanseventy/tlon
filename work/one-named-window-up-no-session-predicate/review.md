APPROVE. Right then: I read the diff against origin/main and did not run the suite myself.

- Behaviour is unchanged. Old rule: `live and sessioned`. New rule: `live and not (live and not seated?)`. By boolean algebra that is `live and seated?`, so #507 is a pure refactor.
- The `Coworker.window_only?/2` truth table is covered by its unit test, and the #514 office test covers the standing-thread case. A session on another thread leaves the seat idle, and one on the thread makes it a desk. The PR notes say the mutation check failed as expected; I did not rerun it.
- The comment removals in #513 are sound. The dropped text described the old `threads/5` and the warm-window rule, and it was stale.
- I did not check the server gate; the PR text defers it to the commit status.

Nit, not blocking (see follow_ups): at the call site the `live` argument is redundant, since `live and not window_only?(live, seated?)` just means `live and seated?`. The predicate reads as meaningful there, but it carries no extra logic.