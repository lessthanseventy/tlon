Plan this ticket for a builder who has never seen the codebase.

TICKET: "`tlon-cli roster` should take `--json` and print the roster as a JSON array (one object per
coworker: name, archetype, state) instead of the table, so scripts can read it."

What you know about the code:

- `scripts/tlon-cli.sh` is a bash dispatcher; its `roster)` case runs
  `"$SERVER" rpc 'Server.Office.roster_table() |> IO.puts()'`.
- `server/lib/server/office.ex` has `roster_table/0`, which builds the table from `roster/0`, a list
  of `%{name, archetype, state}` maps.
- Elixir tests live in `server/test/server/`; `mise run server:test` runs them. The shell script has
  a bats suite, `scripts/test/tlon-cli.bats`, run by `mise run check`.

Write the plan: numbered tasks, each with the files it touches, the failing test it starts with, the
change, and the command that proves it done.
