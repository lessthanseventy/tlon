Plan this ticket for a builder who has never seen the codebase.

TICKET: "tickets get a required `kind` column (`ticket` | `epic`, default `ticket`), CHECK-constrained
in the database, so epics can be told apart from work."

What you know about the code:

- The store is Postgres through Ecto; migrations live in `server/priv/repo/migrations/` and the
  always-up service runs `Server.Release.migrate/0` on boot, against a live table of ~400 tickets.
- `server/lib/server/ticket.ex` is the schema (`create_changeset/1`, `update_changeset/2`);
  `server/lib/server/tickets.ex` is the context (`file/1`, `list/2`, `start_thread/2`).
- The doctor (`mise run server:doctor`) reports pending migrations and exports the store as JSONL.
- Elixir tests live in `server/test/server/`; `mise run server:test` runs them, each run on its own
  fresh test database.

Write the plan: numbered tasks, each with the files it touches, the failing test it starts with, the
change, and the command that proves it done.
