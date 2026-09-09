defmodule Server.Repo.Migrations.WorkspacePolicy do
  @moduledoc false
  use Ecto.Migration

  # What a coworker may do in a workspace (UX slice 5). Keyed workspace × agent: "can write here"
  # is a fact about the pairing.
  #
  # Every column is nullable and nil means INHERIT — the nix-owned capability still decides.
  # `ask_default` absorbs yolo and `model` the driver override from
  # `~/.config/console/config.json`, which was keyed by profile name machine-wide; console imports
  # that file once so an existing override is not lost.
  def up do
    execute("""
    CREATE TABLE workspace_policy (
      id INTEGER PRIMARY KEY,
      workspace_id INTEGER NOT NULL REFERENCES workspace(id) ON DELETE CASCADE,
      agent_id INTEGER NOT NULL REFERENCES agent(id) ON DELETE CASCADE,
      allowed_paths TEXT,
      network TEXT CHECK (network IS NULL OR network IN ('allow','deny')),
      shell TEXT CHECK (shell IS NULL OR shell IN ('allow','ask','deny')),
      ask_default TEXT CHECK (ask_default IS NULL OR ask_default IN ('ask','allow')),
      model TEXT,
      created_at TEXT NOT NULL,
      UNIQUE (workspace_id, agent_id)
    )
    """)

    execute("CREATE INDEX workspace_policy_workspace ON workspace_policy (workspace_id)")
  end

  def down, do: execute("DROP TABLE workspace_policy")
end
