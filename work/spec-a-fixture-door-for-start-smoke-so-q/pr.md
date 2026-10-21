smoke: a fixture door for `start_smoke` (#494)

QA couldn't drive a verb whose state a fresh smoke db lacks (a Need, a refused tool). `start_smoke`
now takes `fixtures: [name]`: named seed sets from a closed catalog in the candidate build,
`Server.Smoke.Fixtures` (option A, operator's choice). Its first set is `tool_denied_need`.

- `Server.Smoke.Fixtures.apply/1` runs a set through the server's own contexts, and refuses any
  database not named `tlon_smoke_*`.
- `Smoke.start/5` checks names by grammar only (the candidate's catalog is what knows them).
  `Jobs.Smoke` exports `TLON_SMOKE_FIXTURES`, and `release-smoke.sh` rpc's each set into the smoke
  node after the flags. A name the build doesn't have fails the smoke.
- QA's role brief and `server/AGENTS.md` describe the argument.

Closes #494.

Checked: new tests in `smoke/fixtures_test.exs` (the catalog, the Need seeded, an unknown name
and a non-smoke db both refused), `jobs/smoke_test.exs` (args carried and omitted, a bad name
refused, env passed to the script) and `release_smoke_script_test.exs` (rpc stub: seeded, unknown
fails, URL mode with no node fails). Each was run red first. `menard run check --in server`:
1938 tests, 0 failures. Not run: a real `release:smoke` with `TLON_SMOKE_FIXTURES`, because this
seat's sandbox can't run it. It gets proven live by QA (`start_smoke` with
`fixtures: ["tool_denied_need"]`, then the Need driven).
