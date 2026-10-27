APPROVE — Right then.

Diff: `OperatorAPI.hire/2` checks `Soul.valid_name?/1` before `Workspaces.seat`, answers 422 on a bad name, and swaps the bare `Persona.ensure` task for `Soul.after_hire/2`. I confirmed in `server/lib/server/soul.ex` that both exist and that `valid_name?/1` is `is_binary(name) and check_name(name) == :ok`. `after_hire/2` has the same persona-then-soul shape the CLI hire uses, and it is best-effort, so a model failure cannot fail the hire.

- Scope is tight: one function, one helper, one test. The guard stays out of `Workspaces.seat`, with the reason in the PR text.
- The test asserts a 422 for `Sonny`, asserts nothing was seated, then hires `sonny`.
- I did not run the suite. I rely on the PR's 2263 tests / 0 failures and 57 gateway tests / 0 failures, which are the builder's numbers.

Nits (non-blocking):
- The 422 text is hard-coded in the API, so it can drift from `Soul.check_name`'s own message. Reusing that message would be better.
- The test hires `sonny`, so `after_hire` spawns a soul draft, and the seat is deleted straight afterwards. If `draft` calls a model unstubbed in test, that may leave a stray task or a log warning. I did not check how `draft` behaves under test.