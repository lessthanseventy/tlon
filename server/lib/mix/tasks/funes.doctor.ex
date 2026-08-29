defmodule Mix.Tasks.Server.Doctor do
  @shortdoc "The 2am report: integrity_check, schema, tables"
  @moduledoc @shortdoc
  use Mix.Task
  use Boundary, classify_to: Server

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")
    r = Server.Doctor.report()
    Mix.shell().info("integrity: #{r.integrity}")
    Mix.shell().info("tables:    #{Enum.join(r.tables, ", ")}")
    Mix.shell().info("migrations: #{r.pending} pending")
    if r.integrity != "ok" or r.pending > 0, do: exit({:shutdown, 1})
  end
end
