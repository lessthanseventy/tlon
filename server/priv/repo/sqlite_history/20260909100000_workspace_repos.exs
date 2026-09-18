defmodule Server.Repo.Migrations.WorkspaceRepos do
  @moduledoc false
  use Ecto.Migration

  # The workspace model as tables, part one (UX slice 5, 2026-09-09): the git-tracked scope stops
  # being a JSON list of strings the flake seeds by hand and becomes rows the CONFIG pane edits.
  #
  # `workspace.paths` held bare globs ("modules/*") and nothing else — there was nowhere to say
  # which remote a workspace tracks or what its default branch is, so `Console.Profiles` hardcodes
  # the one repo root in Elixir. `workspace_repo` is where that belongs. The existing globs migrate
  # in as `path` with `remote`/`default_branch` left NULL: a glob and a checkout root are not the
  # same thing, and inventing a remote for a scope glob would be a lie the operator then has to
  # find and undo. Nullable columns say "not answered yet"; the CONFIG pane is where they get
  # answered.
  #
  # `sort` keeps the list in the order the operator arranged it — a list that reshuffles itself on
  # every read is not a list anyone can edit. It ASCENDS, unlike the ticket board's: a new repo
  # appends at the bottom, which is what `paths ++ [entry]` did and what building up a list feels
  # like. (A ticket lands on top because an unseen capture is a lost capture; a repo has no such
  # urgency.)
  def up do
    execute("""
    CREATE TABLE workspace_repo (
      id INTEGER PRIMARY KEY,
      workspace_id INTEGER NOT NULL REFERENCES workspace(id) ON DELETE CASCADE,
      path TEXT NOT NULL,
      remote TEXT,
      default_branch TEXT,
      sort INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      UNIQUE (workspace_id, path)
    )
    """)

    execute("CREATE INDEX workspace_repo_workspace ON workspace_repo (workspace_id)")

    # Every existing glob becomes a row, in the order it sat in the JSON array. json_each is
    # SQLite's own reader for the column `Server.JSONColumn` wrote — no round trip through Elixir,
    # so the migration cannot disagree with the data it is migrating.
    execute("""
    INSERT INTO workspace_repo (workspace_id, path, sort, created_at)
    SELECT w.id, j.value, j.key, strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
    FROM workspace w, json_each(w.paths) j
    WHERE json_valid(w.paths) AND json_type(w.paths) = 'array' AND j.value <> ''
    """)

    execute("ALTER TABLE workspace DROP COLUMN paths")
  end

  def down do
    execute("ALTER TABLE workspace ADD COLUMN paths TEXT")

    execute("""
    UPDATE workspace SET paths = COALESCE((
      SELECT json_group_array(r.path) FROM (
        SELECT path FROM workspace_repo WHERE workspace_id = workspace.id ORDER BY sort ASC, id ASC
      ) r
    ), '[]')
    """)

    execute("DROP TABLE workspace_repo")
  end
end
