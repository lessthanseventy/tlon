# Operator API hire: soul name guard and first-draft soul

Closes #412.

- **A name the soul guard refuses is refused on this door.** `POST /api/workspaces/:id/coworkers`
  (`Server.MCP.OperatorAPI.hire/2`, used by the office) checks `Soul.valid_name?/1` before
  `Workspaces.seat`, and answers 422 with the CLI's wording. A capitalised name like `Sonny` is no
  longer seated; `sonny` still is.
- **The guard is not in `Workspaces.seat`.** The switchboard tests seat `Dana` and `Tertius` on
  purpose; a guard there would break them.
- **An API hire gets a soul.** The hire calls `Soul.after_hire/2` (persona + first-draft soul), as the
  CLI's hire does, in place of a bare `Server.Persona.ensure`.

Checked:

- RED: `gateway_test.exs` "workspaces: create, hire, …" — `POST` hire `Sonny` returned `201`
  (`{201, %{"name" => "Sonny", ...}}`), failing the new `422` assertion.
- GREEN: `menard run test --in server test/server/mcp/gateway_test.exs` — 57 tests, 0 failures.
- `menard run check --in server` — 2263 tests, 0 failures, exit 0.
