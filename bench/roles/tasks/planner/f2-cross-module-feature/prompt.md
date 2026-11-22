Plan this ticket for a builder who has never seen the codebase.

TICKET: "When a workline lands, the house says so: the server's `landed` alert names the thread and
its PR, and the house shows it as a banner for five seconds."

What you know about the code:

- `server/lib/server/workline/publish.ex` pushes a landed branch and opens its PR; `publish` returns
  `{:ok, pr_url}` (or `{:auto_refused, pr_url, why}`, `:none`, `{:error, why}`).
- `server/lib/server/workline/landing.ex`: when GitHub merges that PR, `merged/2` records the
  landing's `work_landed` event, the PR's URL as `"evidence"` in its `detail`. `landed_since/1` reads
  those events as `[%{id, thread_id, title, created_at}]`.
- `server/lib/server/alerts.ex` holds `Alerts.list/0`, which reads, and `Alerts.build/4`, which makes
  the alerts, each `%{key, level, kind, title, body, at, thread_id, link, actions}`. A `landed` alert
  is already one of them: one per row of `landed_since/1`, titled by `landed_title/1`
  (`#185 landed — <title>`), its `link` nil, so it names the thread and not the PR. The operator API
  serves the list at `GET /api/alerts` (`server/lib/server/mcp/operator_api.ex`).
- The house is a Godot project (GDScript) under `house/`. `house/main.gd` polls `GET /api/home` every
  5 s (`_poll`, answered in `_on_polled`) and reads nothing from `/api/alerts`. `house/sidebar.gd`
  draws the banner strip (`_banner_update`): one row at a time, a ringing reminder, then a reply line
  (`reply_text` in `house/home.gd`, shown while `reply_left` seconds remain), then the day's slip.
  Its tests are the logic checks in `house/logic.gd` (`mise run house:check`).
- Elixir tests live in `server/test/server/`; `mise run server:test` runs them.

Write the plan: numbered tasks, each with the files it touches, the failing test it starts with, the
change, and the command that proves it done.
