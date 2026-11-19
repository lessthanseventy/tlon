defmodule Mix.Tasks.Server.Eval do
  @shortdoc "Run the server's steering evals (worklines slice 0) — --deterministic for the offline gate set"
  @moduledoc """
  #{@shortdoc}.

  Loads every scenario in `evals/` and runs it against its own Postgres database
  (`tlon_eval_<pid>`, dropped and recreated per run) — never the live or dev-scratch one,
  whatever `TLON_DATABASE` the shell carries. The run starts by dropping the `tlon_eval_<pid>`
  databases of dead pids, without force so one in use refuses (a gate killed before its teardown), and ends by stopping the app, then
  dropping its own; a teardown that fails says so in one line and leaves the verdict alone. Deterministic scenarios are plain
  asserts; judged scenarios go through the LLM judge (`Server.Eval.Judge.Claude`, cheap alias)
  and gate on a ≥3.5 average. `--deterministic` skips the judged set — the fast, offline mode
  `mix precommit` runs. Exits nonzero on any failure.
  """
  use Mix.Task
  use Boundary, classify_to: Server

  @drop_timeout to_timeout(minute: 3)

  @impl Mix.Task
  def run(argv) do
    mode = Server.Eval.mode(argv)

    # This boots in :dev, where runtime.exs trusts the ambient TLON_START_* env — exactly what
    # an agent session bound to the live service has set, for its OWN MCP connection. Without
    # this, server:check's eval step inherits them and tries to rebind the live service's own
    # ports (:eaddrinuse) — the same env this eval already isolates its db against. Before
    # ecto.drop, not after: that's the first Mix.Task.run call, so it's the one that triggers
    # "loadconfig" (runtime.exs) — on the ambient env if this ran any later, locking in
    # :start_mcp etc. before Application.put_env could ever override it back.
    for name <- ~w(TLON_START_MCP TLON_START_WEB TLON_START_OBAN TLON_START_SWITCHBOARD TLON_START_ATTENTION),
        do: System.put_env(name, "0")

    # its own database, whatever this shell inherited: a coworker's session carries the service's
    # TLON_DATABASE, and the scenarios open threads. Named with this OS process's pid, not a bare
    # "tlon_eval": two worklines' gates (or this one run twice, per the operator's "green twice"
    # ask) land on the same Postgres server, and a shared name raced ecto.drop/create between
    # them — one's :already_up, the other's tables mid-drop under it.
    eval_db = "tlon_eval_#{System.pid()}"
    System.delete_env("TLON_DATABASE_URL")
    System.put_env("TLON_DATABASE", eval_db)
    Mix.Task.run("ecto.drop", ["--quiet", "--force-drop"])
    Enum.each(stale_databases(), &drop(&1, false))
    Mix.Task.run("ecto.create", ["--quiet"])

    # dropped again when the run ends, red or raised: the pid is fresh every run, so the drop above
    # never finds the last run's database.
    try do
      Mix.Task.run("ecto.migrate", ["--quiet"])
      Mix.Task.run("app.start")
      Logger.configure(level: :warning)

      report = "evals" |> Server.Eval.load() |> Server.Eval.run(mode: mode)
      Mix.shell().info(Server.Eval.scorecard(report))
      if not report.ok?, do: Mix.raise("server.eval failed")
    after
      # the app's repo pool reconnects to a database being force-dropped and slows the drop
      Application.stop(:server)
      drop(eval_db, true)
    end
  end

  # ecto.drop's adapter call reads :timeout from the repo config, 15s by default: a drop
  # interrupted on a busy box leaves an "invalid" database. A failed drop is said, never raised:
  # it must not turn a passed eval red nor hide a failed one.
  # The sweep drops without force: a pid dead only from here (another PID namespace or user) may
  # be a live run, and a database with a connection refuses the drop.
  defp drop(database, force?) do
    config = Keyword.merge(Server.Repo.config(), database: database, force_drop: force?, timeout: @drop_timeout)

    case Ecto.Adapters.Postgres.storage_down(config) do
      result when result in [:ok, {:error, :already_down}] -> :ok
      {:error, reason} -> Mix.shell().error("server.eval: could not drop #{database}: #{inspect(reason)}")
    end
  end

  defp stale_databases do
    config = Keyword.merge(Server.Repo.config(), database: "postgres")
    {:ok, conn} = config |> Keyword.drop([:name, :log, :pool, :pool_size]) |> Postgrex.start_link()
    %{rows: rows} = Postgrex.query!(conn, "SELECT datname FROM pg_database WHERE datname LIKE 'tlon\\_eval\\_%'", [])
    GenServer.stop(conn)
    rows |> List.flatten() |> Server.Eval.stale_databases(&os_pid_alive?/1)
  end

  defp os_pid_alive?(pid), do: File.exists?("/proc/#{pid}")
end
