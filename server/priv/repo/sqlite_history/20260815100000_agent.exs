defmodule Server.Repo.Migrations.Agent do
  use Ecto.Migration

  # 004 agent (aleph §3, §9.3). The durable identity that outlives everything: a
  # named role (Sandra, Robert), not a workspace. `name` is UNIQUE because a name
  # attaches to a role and must outlive the pane it ran in (§5b) — two agents
  # cannot share one, and the DB is the guard (§10). `mandate` is the brief; the
  # profile lives inline on the row, no role/type hierarchy until agents share one
  # (§3, don't-over-build).
  #
  # `engine` holds a STRENGTH REQUIREMENT — "deep reasoning", "cheap per turn",
  # "not the weights under review" — never a product or model name (§3, §8). No
  # CHECK enumerates the strengths: the vocabulary is open and resolved by the
  # local engine registry, so a closed set here would invent config the design
  # refuses to own.
  #
  # The five axes (Context, Sight, Hands, Trust, Sandbox, §3) are five named
  # columns — 2am-readable and per-axis queryable when routing eventually needs it,
  # without the premature normalization a grant table would be. All nullable: the
  # safe default is thin (Robert), and only name/mandate/engine are required.
  #
  # Plain SQL for the same reason as thread/message: SQLite needs the UNIQUE inline
  # and a CREATE TABLE a human can read at 2am is the point (§4).
  def change do
    execute(
      """
      CREATE TABLE agent (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL UNIQUE,
        mandate TEXT NOT NULL,
        engine TEXT NOT NULL,
        context TEXT,
        sight TEXT,
        hands TEXT,
        trust TEXT,
        sandbox TEXT,
        created_at TEXT NOT NULL
      )
      """,
      "DROP TABLE agent"
    )
  end
end
