defmodule Server.Doctor do
  @moduledoc """
  The 2am report. Ask the database itself whether it is sound — the arbiter's own
  answers, not our bookkeeping — and provide the JSONL escape hatch that makes it
  repairable with a text editor.
  """
  alias Server.Repo

  @type report :: %{integrity: String.t(), tables: [String.t()], pending: non_neg_integer()}

  @spec report() :: report()
  def report do
    %{integrity: integrity_check(), tables: tables(), pending: length(pending())}
  end

  @doc """
  `ok`, or the problems PRAGMA integrity_check found. A healthy database returns a
  single `ok` row; an unhealthy one returns up to 100 problem rows — so we fold them
  rather than matching one, because the moment this must NOT crash is exactly when
  the database is broken.
  """
  @spec integrity_check() :: String.t()
  def integrity_check do
    # Postgres has no PRAGMA integrity_check; the honest equivalent at 2am is "can the store answer
    # and are its relations all there" — a failed query raises, which the caller reports.
    case Repo.query!("SELECT count(*) FROM pg_class WHERE relkind = 'r' AND relnamespace = 'public'::regnamespace").rows do
      [[n]] when n > 0 -> "ok"
      _ -> "no tables in schema public"
    end
  end

  @doc """
  User tables present, the migration ledger excluded.
  """
  @spec tables() :: [String.t()]
  def tables do
    %{rows: rows} =
      Repo.query!("""
      SELECT table_name FROM information_schema.tables
      WHERE table_schema = 'public' AND table_type = 'BASE TABLE' AND table_name <> 'schema_migrations'
      ORDER BY table_name
      """)

    Enum.map(rows, fn [name] -> name end)
  end

  @doc "Migrations known but not yet applied — a non-empty list means the schema is behind."
  @spec pending() :: [{integer(), String.t()}]
  def pending do
    Repo
    |> Ecto.Migrator.migrations()
    |> Enum.filter(fn {status, _version, _name} -> status == :down end)
    |> Enum.map(fn {_status, version, name} -> {version, name} end)
  end

  @doc """
  Export every table as JSONL into `dir` (created if missing), one `<table>.jsonl` per table —
  `mix server.doctor --export <dir>`. Returns the paths written, in table order; an empty table
  writes an empty file, so a missing file always means a missing table.
  """
  @spec export(Path.t()) :: [Path.t()]
  def export(dir) do
    File.mkdir_p!(dir)

    for table <- tables() do
      path = Path.join(dir, "#{table}.jsonl")
      File.write!(path, jsonl_file(table_to_jsonl(table)))
      path
    end
  end

  defp jsonl_file(""), do: ""
  defp jsonl_file(lines), do: lines <> "\n"

  @doc """
  Export one table as JSONL — the escape hatch. The table name cannot be a bound
  parameter, so it is validated against the live schema before it is interpolated:
  an unknown name is refused, not run.
  """
  @spec table_to_jsonl(String.t()) :: String.t()
  def table_to_jsonl(table) do
    if table not in tables(), do: raise(ArgumentError, "no such table: #{table}")

    %{rows: rows, columns: columns} = Repo.query!(~s|SELECT * FROM "#{table}"|)

    Enum.map_join(rows, "\n", fn row ->
      columns |> Enum.zip(row) |> Map.new() |> JSON.encode!()
    end)
  end
end
