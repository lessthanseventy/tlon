defmodule Server.Repo.Migrations.PostgresBaseline do
  use Ecto.Migration

  @moduledoc """
  The schema as it stood on SQLite at the cutover (one-brain piece C, 2026-09-18), as ONE
  Postgres baseline. The 43 SQLite migrations that built it are kept for the record in
  `priv/repo/sqlite_history/` and never run again; `mix server.import_sqlite` carries the rows
  across. Every CHECK the SQLite schema declared is kept — the DB is still the guard (§10).
  UNIQUE constraints carry Ecto's default names (`<table>_<cols>_index`) so every
  `unique_constraint/2` in the changesets keeps translating a violation into a changeset error.
  Two engine-shaped changes: timestamps are `timestamptz` (were ISO TEXT), and full-text search
  is a generated `tsvector` + GIN per searchable table (was FTS5 + triggers).
  """

  def up do
    execute """
    CREATE TABLE collection (
      source TEXT PRIMARY KEY,
      last_attempt TEXT, last_success TEXT, last_error TEXT
    )
    """

    execute """
    CREATE TABLE agent (
      id BIGSERIAL PRIMARY KEY,
      name TEXT NOT NULL CONSTRAINT agent_name_index UNIQUE,
      mandate TEXT NOT NULL,
      engine TEXT NOT NULL,
      context TEXT, sight TEXT, hands TEXT, trust TEXT, sandbox TEXT,
      created_at TIMESTAMPTZ NOT NULL
    )
    """

    execute """
    CREATE TABLE workspace (
      id BIGSERIAL PRIMARY KEY,
      name TEXT NOT NULL CONSTRAINT workspace_name_index UNIQUE,
      type TEXT NOT NULL DEFAULT 'code' CHECK (type IN ('code','life','blank')),
      scope TEXT NOT NULL DEFAULT 'machine' CHECK (scope IN ('project','machine')),
      knobs TEXT NOT NULL DEFAULT '{}',
      created_at TIMESTAMPTZ NOT NULL
    )
    """

    execute """
    CREATE TABLE project (
      id BIGSERIAL PRIMARY KEY,
      workspace_id BIGINT NOT NULL REFERENCES workspace(id),
      name TEXT NOT NULL,
      repos TEXT NOT NULL DEFAULT '[]',
      knobs TEXT NOT NULL DEFAULT '{}',
      created_at TIMESTAMPTZ NOT NULL,
      CONSTRAINT project_workspace_id_name_index UNIQUE (workspace_id, name)
    )
    """

    execute """
    CREATE TABLE channel (
      id BIGSERIAL PRIMARY KEY,
      workspace_id BIGINT NOT NULL REFERENCES workspace(id),
      name TEXT NOT NULL,
      kind TEXT NOT NULL DEFAULT 'topic' CHECK (kind IN ('general','topic')),
      created_at TIMESTAMPTZ NOT NULL,
      CONSTRAINT channel_workspace_id_name_index UNIQUE (workspace_id, name)
    )
    """

    execute """
    CREATE TABLE thread (
      id BIGSERIAL PRIMARY KEY,
      title TEXT NOT NULL,
      state TEXT NOT NULL DEFAULT 'open' CHECK (state IN ('open', 'closed')),
      created_at TIMESTAMPTZ NOT NULL,
      agent_id BIGINT REFERENCES agent(id),
      scope TEXT NOT NULL DEFAULT 'project' CHECK (scope IN ('project', 'machine')),
      stage TEXT CHECK (stage IN ('intent', 'spec', 'plan', 'build', 'verify', 'review', 'merged')),
      slug TEXT,
      born TEXT CHECK (born IN ('operator', 'machine')),
      awaiting TEXT,
      workspace_id BIGINT REFERENCES workspace(id),
      project_id BIGINT REFERENCES project(id),
      parent_thread_id BIGINT REFERENCES thread(id),
      channel_id BIGINT REFERENCES channel(id)
    )
    """

    execute "CREATE UNIQUE INDEX thread_slug_index ON thread (slug) WHERE slug IS NOT NULL"
    execute "CREATE INDEX thread_agent_id_index ON thread (agent_id)"

    execute """
    CREATE TABLE session (
      id BIGSERIAL PRIMARY KEY,
      agent_id BIGINT NOT NULL REFERENCES agent(id),
      thread_id BIGINT NOT NULL REFERENCES thread(id),
      pane_ref TEXT,
      started_at TIMESTAMPTZ NOT NULL,
      ended_at TIMESTAMPTZ,
      last_active_at TIMESTAMPTZ
    )
    """

    execute "CREATE INDEX session_thread_id_index ON session (thread_id)"
    execute "CREATE INDEX session_last_active_at_index ON session (last_active_at)"
    execute "CREATE UNIQUE INDEX session_one_live_per_thread_agent ON session (thread_id, agent_id) WHERE ended_at IS NULL"

    execute """
    CREATE TABLE message (
      id BIGSERIAL PRIMARY KEY,
      thread_id BIGINT NOT NULL REFERENCES thread(id),
      author TEXT NOT NULL,
      body TEXT NOT NULL,
      created_at TIMESTAMPTZ NOT NULL,
      delivered_at TIMESTAMPTZ,
      reply_to BIGINT REFERENCES message(id),
      consult_id BIGINT,
      origin_thread_id BIGINT,
      mirrored BOOLEAN NOT NULL DEFAULT false,
      body_tsv TSVECTOR GENERATED ALWAYS AS (to_tsvector('english', body)) STORED
    )
    """

    execute "CREATE INDEX message_thread_id_index ON message (thread_id)"
    execute "CREATE INDEX message_reply_to_index ON message (reply_to)"
    execute "CREATE INDEX message_undelivered ON message (id) WHERE delivered_at IS NULL"
    execute "CREATE INDEX message_consult_id_index ON message (consult_id) WHERE mirrored = false"
    execute "CREATE INDEX message_body_tsv_index ON message USING GIN (body_tsv)"

    execute """
    CREATE TABLE fact (
      id BIGSERIAL PRIMARY KEY,
      thread_id BIGINT REFERENCES thread(id),
      kind TEXT NOT NULL CHECK (kind IN ('decision', 'constraint', 'learned')),
      text TEXT NOT NULL,
      provenance TEXT NOT NULL CHECK (provenance IN ('stated', 'derived')),
      check_cmd TEXT,
      incident TEXT,
      supersedes BIGINT REFERENCES fact(id),
      taught TEXT,
      source_session_id BIGINT REFERENCES session(id),
      created_at TIMESTAMPTZ NOT NULL,
      embedding TEXT,
      embedding_model TEXT,
      intent TEXT,
      forgotten_at TIMESTAMPTZ,
      text_tsv TSVECTOR GENERATED ALWAYS AS (to_tsvector('english', text)) STORED
    )
    """

    execute "CREATE INDEX fact_thread_id_index ON fact (thread_id)"
    execute "CREATE INDEX fact_supersedes_index ON fact (supersedes)"
    execute "CREATE INDEX fact_text_tsv_index ON fact USING GIN (text_tsv)"

    execute """
    CREATE TABLE issue (
      id BIGSERIAL PRIMARY KEY,
      thread_id BIGINT REFERENCES thread(id),
      summary TEXT NOT NULL,
      evidence TEXT, resolution TEXT, found_by TEXT,
      state TEXT NOT NULL DEFAULT 'open' CHECK (state IN ('open', 'closed')),
      created_at TIMESTAMPTZ NOT NULL
    )
    """

    execute "CREATE INDEX issue_thread_id_index ON issue (thread_id)"

    execute """
    CREATE TABLE todo (
      id BIGSERIAL PRIMARY KEY,
      thread_id BIGINT NOT NULL REFERENCES thread(id),
      text TEXT NOT NULL,
      done_at TIMESTAMPTZ,
      created_at TIMESTAMPTZ NOT NULL
    )
    """

    execute "CREATE INDEX todo_thread_id_index ON todo (thread_id)"

    execute """
    CREATE TABLE question (
      id BIGSERIAL PRIMARY KEY,
      thread_id BIGINT NOT NULL REFERENCES thread(id),
      text TEXT NOT NULL,
      resolution TEXT,
      state TEXT NOT NULL DEFAULT 'open' CHECK (state IN ('open', 'resolved')),
      resolved_at TIMESTAMPTZ,
      created_at TIMESTAMPTZ NOT NULL
    )
    """

    execute "CREATE INDEX question_thread_id_index ON question (thread_id)"

    execute """
    CREATE TABLE habit (
      id BIGSERIAL PRIMARY KEY,
      text TEXT NOT NULL,
      rationale TEXT,
      state TEXT NOT NULL DEFAULT 'pending' CHECK (state IN ('pending', 'approved', 'rejected')),
      proposed_by TEXT NOT NULL,
      source_thread_id BIGINT REFERENCES thread(id),
      approved_at TIMESTAMPTZ,
      created_at TIMESTAMPTZ NOT NULL
    )
    """

    execute "CREATE INDEX habit_state_index ON habit (state)"

    execute """
    CREATE TABLE event (
      id BIGSERIAL PRIMARY KEY,
      thread_id BIGINT REFERENCES thread(id),
      kind TEXT NOT NULL CHECK (kind IN ('work_landed', 'command_approved', 'check_passed', 'check_failed', 'handoff_opened', 'cited', 'stage_advanced')),
      correlation TEXT,
      detail TEXT,
      created_at TIMESTAMPTZ NOT NULL
    )
    """

    execute "CREATE INDEX event_thread_id_index ON event (thread_id)"
    execute "CREATE INDEX event_correlation_index ON event (correlation)"
    execute "CREATE INDEX event_kind_index ON event (kind)"

    execute """
    CREATE TABLE note (
      id BIGSERIAL PRIMARY KEY,
      scope TEXT NOT NULL DEFAULT 'global' CHECK (scope IN ('global','workspace','project','thread')),
      scope_id BIGINT,
      body TEXT NOT NULL DEFAULT '',
      author TEXT,
      created_at TIMESTAMPTZ NOT NULL,
      updated_at TIMESTAMPTZ NOT NULL
    )
    """

    execute """
    CREATE TABLE ticket (
      id BIGSERIAL PRIMARY KEY,
      workspace_id BIGINT NOT NULL REFERENCES workspace(id),
      project_id BIGINT REFERENCES project(id),
      title TEXT NOT NULL,
      body TEXT NOT NULL DEFAULT '',
      status TEXT NOT NULL DEFAULT 'backlog' CHECK (status IN ('backlog','todo','doing','done')),
      priority TEXT NOT NULL DEFAULT 'med' CHECK (priority IN ('low','med','high')),
      labels TEXT NOT NULL DEFAULT '[]',
      assignee TEXT,
      backend TEXT NOT NULL DEFAULT 'local',
      external_key TEXT,
      external_url TEXT,
      created_at TIMESTAMPTZ NOT NULL,
      updated_at TIMESTAMPTZ NOT NULL,
      sort BIGINT NOT NULL DEFAULT 0,
      closed_at TIMESTAMPTZ
    )
    """

    execute """
    CREATE TABLE ticket_link (
      id BIGSERIAL PRIMARY KEY,
      from_id BIGINT NOT NULL REFERENCES ticket(id) ON DELETE CASCADE,
      to_id BIGINT NOT NULL REFERENCES ticket(id) ON DELETE CASCADE,
      kind TEXT NOT NULL CHECK (kind IN ('blocks','relates','duplicates','parent')),
      created_at TIMESTAMPTZ NOT NULL,
      CHECK (from_id <> to_id),
      CONSTRAINT ticket_link_from_id_to_id_kind_index UNIQUE (from_id, to_id, kind)
    )
    """

    execute "CREATE INDEX ticket_link_from ON ticket_link (from_id)"
    execute "CREATE INDEX ticket_link_to ON ticket_link (to_id)"

    execute """
    CREATE TABLE ticket_thread (
      id BIGSERIAL PRIMARY KEY,
      ticket_id BIGINT NOT NULL REFERENCES ticket(id) ON DELETE CASCADE,
      thread_id BIGINT NOT NULL REFERENCES thread(id) ON DELETE CASCADE,
      kind TEXT NOT NULL DEFAULT 'relates' CHECK (kind IN ('promoted','relates')),
      created_at TIMESTAMPTZ NOT NULL,
      CONSTRAINT ticket_thread_ticket_id_thread_id_kind_index UNIQUE (ticket_id, thread_id, kind)
    )
    """

    execute "CREATE INDEX ticket_thread_ticket ON ticket_thread (ticket_id)"
    execute "CREATE INDEX ticket_thread_thread ON ticket_thread (thread_id)"

    execute """
    CREATE TABLE workspace_repo (
      id BIGSERIAL PRIMARY KEY,
      workspace_id BIGINT NOT NULL REFERENCES workspace(id) ON DELETE CASCADE,
      path TEXT NOT NULL,
      remote TEXT,
      default_branch TEXT,
      sort BIGINT NOT NULL DEFAULT 0,
      created_at TIMESTAMPTZ NOT NULL,
      CONSTRAINT workspace_repo_workspace_id_path_index UNIQUE (workspace_id, path)
    )
    """

    execute "CREATE INDEX workspace_repo_workspace ON workspace_repo (workspace_id)"

    execute """
    CREATE TABLE workspace_agent (
      id BIGSERIAL PRIMARY KEY,
      workspace_id BIGINT NOT NULL REFERENCES workspace(id) ON DELETE CASCADE,
      agent_id BIGINT NOT NULL REFERENCES agent(id) ON DELETE CASCADE,
      archetype TEXT,
      sort BIGINT NOT NULL DEFAULT 0,
      created_at TIMESTAMPTZ NOT NULL,
      CONSTRAINT workspace_agent_workspace_id_agent_id_index UNIQUE (workspace_id, agent_id)
    )
    """

    execute "CREATE INDEX workspace_agent_workspace ON workspace_agent (workspace_id)"
    execute "CREATE INDEX workspace_agent_agent ON workspace_agent (agent_id)"

    execute """
    CREATE TABLE workspace_policy (
      id BIGSERIAL PRIMARY KEY,
      workspace_id BIGINT NOT NULL REFERENCES workspace(id) ON DELETE CASCADE,
      agent_id BIGINT NOT NULL REFERENCES agent(id) ON DELETE CASCADE,
      allowed_paths TEXT,
      network TEXT CHECK (network IS NULL OR network IN ('allow','deny')),
      shell TEXT CHECK (shell IS NULL OR shell IN ('allow','ask','deny')),
      ask_default TEXT CHECK (ask_default IS NULL OR ask_default IN ('ask','allow')),
      model TEXT,
      created_at TIMESTAMPTZ NOT NULL,
      CONSTRAINT workspace_policy_workspace_id_agent_id_index UNIQUE (workspace_id, agent_id)
    )
    """

    execute "CREATE INDEX workspace_policy_workspace ON workspace_policy (workspace_id)"

    execute """
    CREATE TABLE playbook (
      id BIGSERIAL PRIMARY KEY,
      name TEXT NOT NULL CONSTRAINT playbook_name_index UNIQUE,
      summary TEXT NOT NULL DEFAULT '',
      steps TEXT NOT NULL,
      success TEXT NOT NULL DEFAULT '',
      author TEXT,
      source_thread_id BIGINT REFERENCES thread(id),
      created_at TIMESTAMPTZ NOT NULL,
      updated_at TIMESTAMPTZ NOT NULL
    )
    """
  end

  def down do
    for t <- ~w(playbook workspace_policy workspace_agent workspace_repo ticket_thread ticket_link ticket note event habit question todo issue fact message session thread channel project workspace agent collection) do
      execute "DROP TABLE IF EXISTS #{t} CASCADE"
    end
  end
end
