defmodule Mix.Tasks.Server.Eval do
  @shortdoc "Run funes' steering evals (worklines slice 0) — --deterministic for the offline gate set"
  @moduledoc """
  #{@shortdoc}.

  Loads every scenario in `evals/` and runs it against an EPHEMERAL db (`.dev/funes_eval.db`,
  recreated per run) — never the live or dev-scratch db. Deterministic scenarios are plain
  asserts; judged scenarios go through the LLM judge (`Server.Eval.Judge.Claude`, cheap alias)
  and gate on a ≥3.5 average. `--deterministic` skips the judged set — the fast, offline mode
  `mix precommit` runs. Exits nonzero on any failure.
  """
  use Mix.Task
  use Boundary, classify_to: Server

  @eval_db ".dev/funes_eval.db"

  @impl Mix.Task
  def run(argv) do
    mode = Server.Eval.mode(argv)

    for suffix <- ["", "-wal", "-shm"], do: File.rm(@eval_db <> suffix)
    System.put_env("TLON_DB", Path.expand(@eval_db))
    Mix.Task.run("ecto.create", ["--quiet"])
    Mix.Task.run("ecto.migrate", ["--quiet"])
    Mix.Task.run("app.start")
    Logger.configure(level: :warning)

    report = "evals" |> Server.Eval.load() |> Server.Eval.run(mode: mode)
    Mix.shell().info(Server.Eval.scorecard(report))
    if !report.ok?, do: Mix.raise("funes.eval failed")
  end
end
