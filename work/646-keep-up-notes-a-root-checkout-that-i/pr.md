keep_up notes a root checkout that is off main (#646)

Closes #646.

`Publish.follow_main/2` returned `:skipped` for a checkout on another branch, which `keep_up` treated
as nothing: the root checkout sat on a merged branch for 5 days unnoticed. It now returns
`{:off_main, branch}`, and `KeepUp.drifted/2` posts one keyed rollout note (`{:off_main, repo}`) naming
the branch. The checkout is still left alone (a session may be working there). The note is cleared when
main is back and level or drifted (the drift note takes over).

How it was checked:

- New tests went red first: `follow_main` answered `:skipped`; no note was set for an off-main repo.
- `menard run test --in server` on `keep_up_test.exs` + `workline_publish_test.exs`: 68 tests, 0 failures.
  Three existing keep_up fixtures that used a "feature" branch to dodge following now report `main`.
- Full gate not run in the seat (no checks queue); verify runs it.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
