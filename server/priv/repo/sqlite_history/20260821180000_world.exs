defmodule Server.Repo.Migrations.World do
  use Ecto.Migration

  # A world is a composition (worlds/orbis Slice 1): a git-tracked scope + roster +
  # knobs that aleph reads to drive its picker/survey/spawn. Compositions are DATA
  # (this table), capabilities are nix (the archetype profile templates) — disjoint,
  # so the two config truths never conflict.
  #
  # `type` and `scope` are CLOSED sets guarded by DB CHECKs (§10), never mirrored
  # app-side. `paths`/`roster`/`knobs` are JSON TEXT (Server.JSONColumn): paths a JSON
  # array of globs, roster a JSON array of {archetype,name,model?,knobs}, knobs a JSON
  # object. Plain SQL like `fact` — the CREATE a human reads at 2am is the point.
  def change do
    execute(
      """
      CREATE TABLE world (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL UNIQUE,
        type TEXT NOT NULL DEFAULT 'code' CHECK (type IN ('code','life','blank')),
        scope TEXT NOT NULL DEFAULT 'machine' CHECK (scope IN ('project','machine')),
        paths TEXT NOT NULL DEFAULT '[]',
        roster TEXT NOT NULL DEFAULT '[]',
        knobs TEXT NOT NULL DEFAULT '{}',
        created_at TEXT NOT NULL
      )
      """,
      "DROP TABLE world"
    )
  end
end
