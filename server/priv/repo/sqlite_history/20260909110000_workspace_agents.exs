defmodule Server.Repo.Migrations.WorkspaceAgents do
  @moduledoc false
  use Ecto.Migration

  # The workspace model as tables, part two (UX slice 5, 2026-09-09): the ROSTER — the standing
  # bench of coworkers a workspace employs — stops being a JSON list of `{archetype, name}` and
  # becomes `workspace_agent` rows pointing at the `agent` table that was always the durable
  # identity. The bench and the agent table were two benches; now there is one.
  #
  # `archetype`, not `role`: the design sketched `role`, but `archetype` is the word the registry
  # (`Console.Profiles.archetypes/0`), the roster prompt's ring, the templates and twenty readers
  # already use. A synonym for a concept that already has a name is drift, not precision. It lives
  # on the JOIN, not on the agent, because the same coworker can be a builder here and a reviewer
  # in the next workspace.
  #
  # **The `-machine` suffix retires.** `Channel.designated_lead/1` registered a roster coworker's
  # agent lazily as `"<name>-machine"` while mentions, tmux windows and the profile registry all
  # used the bare `<name>` — one identity in two shapes, with something forced to strip or append
  # at every boundary. The agent's name IS the handle now. This migration renames the existing
  # `*-machine` rows, skipping any whose bare name is already taken (a collision means the bare
  # agent is the real one, and silently merging two identities would be worse than leaving one
  # oddly named).
  #
  # A LIVE COWORKER MUST BE RESPAWNED after this: its shell holds `FUNES_*` env naming the old
  # handle, and nothing rewrites another process's environment.
  def up do
    now = "strftime('%Y-%m-%dT%H:%M:%SZ', 'now')"

    execute("""
    UPDATE agent SET name = substr(name, 1, length(name) - 8)
    WHERE name LIKE '%-machine'
      AND NOT EXISTS (SELECT 1 FROM agent b WHERE b.name = substr(agent.name, 1, length(agent.name) - 8))
    """)

    execute("""
    CREATE TABLE workspace_agent (
      id INTEGER PRIMARY KEY,
      workspace_id INTEGER NOT NULL REFERENCES workspace(id) ON DELETE CASCADE,
      agent_id INTEGER NOT NULL REFERENCES agent(id) ON DELETE CASCADE,
      archetype TEXT,
      sort INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      UNIQUE (workspace_id, agent_id)
    )
    """)

    execute("CREATE INDEX workspace_agent_workspace ON workspace_agent (workspace_id)")
    execute("CREATE INDEX workspace_agent_agent ON workspace_agent (agent_id)")

    # Every roster entry that names a coworker with no agent row yet gets one — eagerly, because a
    # bench you cannot point at is not a bench. `mandate` defaults to the archetype and `engine` to
    # local, matching what the lazy registration used to supply.
    execute("""
    INSERT OR IGNORE INTO agent (name, mandate, engine, created_at)
    SELECT json_extract(j.value, '$.name'),
           COALESCE(json_extract(j.value, '$.archetype'), 'general'),
           'local',
           #{now}
    FROM workspace w, json_each(w.roster) j
    WHERE json_valid(w.roster) AND json_type(w.roster) = 'array'
      AND json_extract(j.value, '$.name') IS NOT NULL
    """)

    execute("""
    INSERT OR IGNORE INTO workspace_agent (workspace_id, agent_id, archetype, sort, created_at)
    SELECT w.id, a.id, json_extract(j.value, '$.archetype'), j.key, #{now}
    FROM workspace w, json_each(w.roster) j
    JOIN agent a ON a.name = json_extract(j.value, '$.name')
    WHERE json_valid(w.roster) AND json_type(w.roster) = 'array'
    """)

    execute("ALTER TABLE workspace DROP COLUMN roster")
  end

  # The agents themselves are NOT deleted and NOT re-suffixed: `down` restores the column that was
  # lost, not identities that other tables (session, thread) still point at by id.
  def down do
    execute("ALTER TABLE workspace ADD COLUMN roster TEXT")

    execute("""
    UPDATE workspace SET roster = COALESCE((
      SELECT json_group_array(json_object('archetype', e.archetype, 'name', e.name)) FROM (
        SELECT wa.archetype AS archetype, a.name AS name
        FROM workspace_agent wa JOIN agent a ON a.id = wa.agent_id
        WHERE wa.workspace_id = workspace.id
        ORDER BY wa.sort ASC, wa.id ASC
      ) e
    ), '[]')
    """)

    execute("DROP TABLE workspace_agent")
  end
end
