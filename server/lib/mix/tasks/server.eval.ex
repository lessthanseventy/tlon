defmodule Mix.Tasks.Server.Eval do
  @shortdoc "Run the server's steering evals (worklines slice 0) — --deterministic for the offline gate set"
  @moduledoc """
  #{@shortdoc}.

  Loads every scenario in `evals/` and runs it against its own Postgres database (`tlon_eval`,
  dropped and recreated per run) — never the live or dev-scratch one, whatever `TLON_DATABASE`
  the shell carries. Deterministic scenarios are plain
  asserts; judged scenarios go through the LLM judge (`Server.Eval.Judge.Claude`, cheap alias)
  and gate on a ≥3.5 average. `--deterministic` skips the judged set — the fast, offline mode
  `mix precommit` runs. Exits nonzero on any failure.
  """
  use Mix.Task
  use Boundary, classify_to: Server

  @eval_db "tlon_eval"

  @impl Mix.Task
  def run(argv) do
    mode = Server.Eval.mode(argv)

    # its own database, whatever this shell inherited: a coworker's session carries the service's
    # TLON_DATABASE, and the scenarios open threads
    System.delete_env("TLON_DATABASE_URL")
    System.put_env("TLON_DATABASE", @eval_db)
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
