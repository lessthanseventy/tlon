Bug report: a drifted main files a new inbox note on every check, and files it at the wrong person.

`Server.Jobs.KeepUp` (a periodic job) notices a repo whose local main has commits origin/main doesn't.
Today each check files a fresh note for the operator (the text changes with the commit count, so the
dedupe never matches: ficciones piled up four in an hour), and the note belongs to the crew, not him.

Fix it, test-first, and commit. Make `Server.Jobs.KeepUp.drifted(repo, level)` public (hidden from the
docs is fine); `level` is `{:diverged, n}` or anything else (main is level / forwarded). It must:

- for a repo **no project owns**: keep exactly one pending operator note per repo
  (`Server.Rollout.pending/0`) whose text names the repo and carries the *latest* count as `"N commit"`.
  A second check with a different count replaces the text in place; when main is level again the note
  is gone. (`Server.Rollout` needs a keyed note that can be replaced and cleared; its notes are a list
  of `%{id, text, at}` maps, dismissed with `Server.Rollout.dismiss/1`.)
- for a repo **a project owns** (`Server.Projects.primary_repo_path/1` of one of the workspace's projects
  equals the repo): the operator hears nothing (no pending note). Instead one ticket is filed in that
  workspace titled `land local main's N commits` (`commit` singular when N is 1) with a label naming the
  repo, and one message is posted once, as author `"tlon"`, on that workspace's lobby thread
  (`Server.Channel.machine_thread/1`) naming the repo and the count. A later check with a new count
  updates the open ticket's title and body and posts nothing more. When main is level again the ticket
  is closed (`status: "done"`).


The project is the Elixir/Phoenix app under `server/` (`cd server && mix test <file>` runs a test file).
