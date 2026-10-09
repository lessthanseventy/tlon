Ticket: when the keep-up job finds a repo's local `main` has diverged from origin/main it files a
fresh operator note on **every** check, so the operator's list fills with near-identical notes, and
nobody in the owning workspace hears of it. Make a drifted main one note per repo, routed to whoever
owns the repo.

`Server.Jobs.KeepUp.drifted(repo, level)` (`lib/server/jobs/keep_up.ex`) becomes public (`@doc false`).
`level` is `{:diverged, n}` (n local commits origin lacks) or anything else (main is level again).

- Rollout notes (`Server.Rollout`, `lib/server/rollout.ex`) gain a key: `Rollout.note(key, text)` files
  a note under `key`, and a note already filed under it has its text replaced in place;
  `Rollout.clear(key)` drops it. Both are casts. `Rollout.pending/0` is unchanged. Use `{:drift, repo}` as key.
- A repo **no project owns** (compare `Server.Projects.primary_repo_path/1` of each `Server.Project` with
  `repo`): `{:diverged, n}` → one keyed note, text "…<repo>…: local main has n commit(s) origin/main
  doesn't…"; a later count replaces it. Level → the note is cleared.
- A repo **a project owns**: the operator hears nothing. In that project's workspace, `{:diverged, n}`
  files ONE ticket (`Tickets.file/1`, title `"land local main's N commit(s)"` — "commit" or "commits"
  by N — label `"drift:<repo>"`) and ONE post by author `tlon` on the workspace's lobby
  (`Channel.machine_thread(ws_id)`) whose body contains the repo and "N commit". A later count updates the
  existing open ticket (title/body) and does not post again. Level → that ticket is set to `done`.

Add tests in `test/server/jobs/keep_up_test.exs`; keep `mix test` green.
