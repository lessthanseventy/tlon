defmodule Mix.Tasks.Server.Doctor do
  @shortdoc "The 2am report: integrity_check, schema, tables; --export <dir> dumps every table as JSONL"
  @moduledoc """
  #{@shortdoc}.

  `--export <dir>` writes one `<table>.jsonl` per table (`Server.Doctor.export/1`) — the escape
  hatch that makes a broken db repairable with a text editor. The report still runs first, and
  the exit code still reflects it.
  """
  use Mix.Task
  use Boundary, classify_to: Server

  @impl Mix.Task
  def run(args) do
    {opts, _rest} = OptionParser.parse!(args, strict: [export: :string])
    Mix.Task.run("app.start")
    r = Server.Doctor.report()
    Mix.shell().info("integrity: #{r.integrity}")
    Mix.shell().info("tables:    #{Enum.join(r.tables, ", ")}")
    Mix.shell().info("migrations: #{r.pending} pending")

    if dir = opts[:export] do
      paths = Server.Doctor.export(dir)
      Mix.shell().info("exported:  #{length(paths)} table(s) to #{dir}")
    end

    if r.integrity != "ok" or r.pending > 0, do: exit({:shutdown, 1})
  end
end
