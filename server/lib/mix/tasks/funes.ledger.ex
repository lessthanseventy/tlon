defmodule Mix.Tasks.Server.Ledger do
  @shortdoc "The workline value ledger — stages, gates, advances, tallies (worklines slice 6)"
  @moduledoc """
  #{@shortdoc}. A read-model over rows the stage machine already writes; run against the
  db the caller points TLON_DB at (the mise task uses the dev scratch db, like funes:doctor).
  """
  use Mix.Task
  use Boundary, classify_to: Server

  alias Server.Workline.Ledger

  @impl Mix.Task
  def run(_argv) do
    Mix.Task.run("app.start")
    Logger.configure(level: :warning)
    Mix.shell().info(Ledger.render(Ledger.report()))
  end
end
