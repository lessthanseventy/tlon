# run_verb: compile/test/check run in the mix project, not the worktree root

Closes #441.

`run_verb` passed `Menard.Run.result/3` the bare worktree root, so on a tlon-shaped tree `compile`/`test` died with mix's "Could not find a Mix.Project". `Server.Source.Tools.run/4` now takes `in:` (a path under the worktree, refused outside it by the same `resolve_all` rule as `files`); `run_verb` gets the matching optional `in` field. Without it: the root if it holds a `mix.exs`, else the one immediate subdirectory that does; zero or several candidates are refused, naming them ("pass in: <dir>"). `format` keeps the root (its args are root-relative files) unless `in` is given. Menard is untouched; `edit_clause`/`outline_file` stay root-relative.

Checked: `menard run test --in server test/server/source/tools_test.exs` — red first (compile still failing, `run/4` undefined), then 10 tests, 0 failures. New tests cover the subdirectory default, root-wins, explicit `in`, zero/several refusals and `in` escaping the worktree.
