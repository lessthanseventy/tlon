Smoke.start refuses an empty work/ ref (#489).

Before: with no ref and a thread whose slug is nil, `Smoke.start/4` queued a smoke on `work/`. The
`@ref` pattern also accepted a trailing `/`, so `work/` passed as an explicit ref too.

Now: no ref and no slug is refused with "no ref: ..." and nothing is queued. `@ref` must end in a
letter, digit, `.`, `_` or `-`, so a trailing `/` is "not a ref".

Checked: `menard run test --in server test/server/jobs/smoke_test.exs` went red on both new tests
(the nil slug queued `work/`; `work/` was accepted), then green at 8 tests, 0 failures.
