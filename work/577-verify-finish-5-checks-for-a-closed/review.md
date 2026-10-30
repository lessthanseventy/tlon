APPROVE

Right then: the spots read plainly.

- `Verify.finish/5` (server/lib/server/jobs/verify.ex): the closed-thread clause now comes first, so a red or green result recorded after the workline closed is cancelled. It is neither moved to build nor reported to the sheriff. The old order let the `id > since` clause win and send a closed workline back to build.
- The docstring matches the new behaviour. The green-on-closed case now returns `{:cancel, _}` where it was `:ok`; the PR text says so.
- The new test covers the red-after-close case. It asserts `{:cancel, _}`, that stage and state are unchanged, and that the message count is unchanged. The existing "already closed" test still covers the other path.
- Nothing else is touched: no migration, dependency or gate change.

I read the diff only. I did not run the suite; the PR text reports 10 tests green on `verify_test.exs`.

No blocking findings.