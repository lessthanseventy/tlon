defmodule Mix.Tasks.Console.Eval do
  @shortdoc "Run console's steering evals (routing) — --deterministic for the offline gate set"
  @moduledoc """
  #{@shortdoc}.

  Loads every scenario in `evals/` and runs it through `Server.Eval`. The routing family is
  pure (staffing/triage/mention over a fixture cast), so no app boot and no db — just the
  compiled modules. `--deterministic` skips judged scenarios (none yet in this corpus); the
  precommit gate runs that mode. Exits nonzero on any failure.
  """
  use Mix.Task
  use Boundary, classify_to: Console

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("compile")
    mode = Server.Eval.mode(argv)

    report = "evals" |> Server.Eval.load() |> Server.Eval.run(mode: mode)
    Mix.shell().info(Server.Eval.scorecard(report))
    if !report.ok?, do: Mix.raise("console.eval failed")
  end
end
