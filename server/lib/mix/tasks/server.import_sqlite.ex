defmodule Mix.Tasks.Server.ImportSqlite do
  @shortdoc "Copy the SQLite corpus (pre one-brain piece C) into the Postgres store, ids intact"
  @moduledoc """
  The one-shot cutover copy: `mix server.import_sqlite ~/.local/share/funes/wb.db`. Reads every
  domain table from the SQLite file through the exqlite NIF directly (no second Ecto repo), and
  inserts the rows into the configured Postgres Repo with their ids, converting what the engines
  disagree on: ISO TEXT timestamps → timestamptz, 0/1 → boolean. Parents before children; the
  sequences are set past the highest id at the end. Refuses to run into a Postgres with rows in
  `thread` — an import is never a merge.
  """
  use Mix.Task
  use Boundary, classify_to: Server

  alias Server.Repo

  # parents first; each entry: table, and the columns that are timestamps / booleans
  @tables [
    {"collection", [], []},
    {"agent", ~w(created_at), []},
    {"workspace", ~w(created_at), []},
    {"project", ~w(created_at), []},
    {"channel", ~w(created_at), []},
    {"thread", ~w(created_at), []},
    {"session", ~w(started_at ended_at last_active_at), []},
    {"message", ~w(created_at delivered_at), ~w(mirrored)},
    {"fact", ~w(created_at forgotten_at), []},
    {"issue", ~w(created_at), []},
    {"todo", ~w(created_at done_at), []},
    {"question", ~w(created_at resolved_at), []},
    {"habit", ~w(created_at approved_at), []},
    {"event", ~w(created_at), []},
    {"note", ~w(created_at updated_at), []},
    {"ticket", ~w(created_at updated_at closed_at), []},
    {"ticket_link", ~w(created_at), []},
    {"ticket_thread", ~w(created_at), []},
    {"workspace_repo", ~w(created_at), []},
    {"workspace_agent", ~w(created_at), []},
    {"workspace_policy", ~w(created_at), []},
    {"playbook", ~w(created_at updated_at), []}
  ]

  @impl true
  def run([path]) do
    Mix.Task.run("app.config")
    # the adapter's own apps, not the server app — a boot would start the switchboard and MCP too
    {:ok, _} = Application.ensure_all_started(:postgrex)
    {:ok, _} = Application.ensure_all_started(:ecto_sql)
    {:ok, _} = Application.ensure_all_started(:exqlite)
    {:ok, _} = Repo.start_link()

    %{rows: [[threads]]} = Repo.query!("SELECT count(*) FROM thread")

    if threads > 0,
      do: Mix.raise("Postgres already holds #{threads} thread(s) — an import is not a merge; drop and recreate first")

    {:ok, db} = Exqlite.Sqlite3.open(path, mode: :readonly)
    for spec <- @tables, do: copy_table(db, spec)
    :ok = Exqlite.Sqlite3.close(db)
  end

  def run(_), do: Mix.raise("usage: mix server.import_sqlite <path-to-wb.db>")

  defp copy_table(db, {table, times, bools}) do
    {cols, rows} = read(db, table)
    pg_cols = Enum.filter(cols, &(&1 in pg_columns(table)))
    idx = Enum.map(pg_cols, &Enum.find_index(cols, fn c -> c == &1 end))
    params = Enum.map_join(1..max(length(pg_cols), 1), ", ", &"$#{&1}")
    sql = ~s|INSERT INTO "#{table}" (#{Enum.map_join(pg_cols, ", ", &~s|"#{&1}"|)}) VALUES (#{params})|

    for row <- rows do
      values =
        idx |> Enum.map(&Enum.at(row, &1)) |> Enum.zip(pg_cols) |> Enum.map(fn {v, c} -> convert(v, c, times, bools) end)

      Repo.query!(sql, values)
    end

    if "id" in pg_cols and rows != [] do
      Repo.query!("SELECT setval(pg_get_serial_sequence('#{table}', 'id'), (SELECT max(id) FROM \"#{table}\"))")
    end

    Mix.shell().info("#{table}: #{length(rows)} row(s)")
  end

  defp read(db, table) do
    {:ok, stmt} = Exqlite.Sqlite3.prepare(db, ~s|SELECT * FROM "#{table}"|)
    {:ok, cols} = Exqlite.Sqlite3.columns(db, stmt)
    {:ok, rows} = Exqlite.Sqlite3.fetch_all(db, stmt)
    :ok = Exqlite.Sqlite3.release(db, stmt)
    {cols, rows}
  end

  defp pg_columns(table) do
    %{rows: rows} =
      Repo.query!(
        "SELECT column_name FROM information_schema.columns WHERE table_schema = 'public' AND table_name = $1 AND is_generated = 'NEVER'",
        [table]
      )

    Enum.map(rows, fn [c] -> c end)
  end

  defp convert(nil, _c, _t, _b), do: nil

  defp convert(v, c, times, bools) do
    cond do
      c in times and is_binary(v) -> parse_time(v)
      c in bools -> v in [1, "1", true, "true"]
      true -> v
    end
  end

  # SQLite held ISO8601 TEXT — with a zone (`…Z`) from Ecto, or a bare naive stamp from a hand fix
  defp parse_time(v) do
    case DateTime.from_iso8601(v) do
      {:ok, dt, _} -> dt
      _ -> v |> String.replace(" ", "T") |> NaiveDateTime.from_iso8601!() |> DateTime.from_naive!("Etc/UTC")
    end
  end
end
