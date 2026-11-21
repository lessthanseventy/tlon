Plan this ticket for a builder who has never seen the codebase.

TICKET: "When a workline lands, the house says so: the server raises an alert `landed` naming the
thread and its PR, and the house shows it as a banner for five seconds."

What you know about the code:

- `server/lib/server/workline/publish.ex` pushes a landed branch and opens its PR; it returns
  `{:ok, %{thread_id, pr}}`.
- `server/lib/server/alerts.ex` holds `Alerts.raise/1` (`%{kind, title, body, actions}`) and
  `Alerts.list/0`; the operator API serves the list at `GET /api/alerts`
  (`server/lib/server/mcp/operator_api.ex`).
- The house is a Godot project (GDScript) under `house/`; `house/main.gd` polls `/api/alerts` and
  `house/sidebar.gd` draws a banner for `{title, body, ttl_ms}`. Its tests are the logic checks in
  `house/logic.gd` (`mise run house:check`).
- Elixir tests live in `server/test/server/`; `mise run server:test` runs them.

Write the plan: numbered tasks, each with the files it touches, the failing test it starts with, the
change, and the command that proves it done.
