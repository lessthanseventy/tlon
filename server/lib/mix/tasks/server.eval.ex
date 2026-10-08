defmodule Mix.Tasks.Server.Eval do
  @shortdoc "Run the server's steering evals (worklines slice 0) — --deterministic for the offline gate set"
  @moduledoc """
  #{@shortdoc}.

  Loads every scenario in `evals/` and runs it against its own Postgres database
  (`tlon_eval_<pid>`, dropped and recreated per run) — never the live or dev-scratch one,
  whatever `TLON_DATABASE` the shell carries. Deterministic scenarios are plain
  asserts; judged scenarios go through the LLM judge (`Server.Eval.Judge.Claude`, cheap alias)
  and gate on a ≥3.5 average. `--deterministic` skips the judged set — the fast, offline mode
  `mix precommit` runs. Exits nonzero on any failure.
  """
  use Mix.Task
  use Boundary, classify_to: Server

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
    Mix.Task.run("ecto.create", ["--quiet"])
    Mix.Task.run("ecto.migrate", ["--quiet"])
    Mix.Task.run("app.start")
    Logger.configure(level: :warning)

    report = "evals" |> Server.Eval.load() |> Server.Eval.run(mode: mode)
    Mix.shell().info(Server.Eval.scorecard(report))
    if !report.ok?, do: Mix.raise("server.eval failed")
  end
end
