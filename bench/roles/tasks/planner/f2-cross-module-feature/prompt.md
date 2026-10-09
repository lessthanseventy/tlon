Plan this ticket for a builder who has never seen the codebase.

TICKET: "When a workline lands, the office toasts it: the server raises an alert `landed` naming the
thread and its PR, and the office TUI shows it as a toast for five seconds."

What you know about the code:

- `server/lib/server/workline/publish.ex` pushes a landed branch and opens its PR; it returns
  `{:ok, %{thread_id, pr}}`.
- `server/lib/server/alerts.ex` holds `Alerts.raise/1` (`%{kind, title, body, actions}`) and
  `Alerts.list/0`; the operator API serves the list at `GET /api/alerts`
  (`server/lib/server/mcp/operator_api.ex`).
- The office TUI is TypeScript under `office/`; `office/kit/alerts.ts` polls `/api/alerts` and
  `office/kit/toast.ts` draws a toast for `{title, body, ttlMs}`. Its tests are `bun test` in
  `office/` (`mise run office:check`).
- Elixir tests live in `server/test/server/`; `mise run server:test` runs them.

Write the plan: numbered tasks, each with the files it touches, the failing test it starts with, the
change, and the command that proves it done.
