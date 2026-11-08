defmodule Mix.Tasks.Server.Doctor do
  @shortdoc "The 2am report: integrity_check, schema, tables, erl_crash.dump; --export <dir> dumps every table as JSONL"
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

    # :dev's runtime.exs trusts the ambient TLON_START_*, and a session bound to the live service
    # carries them: booting on them rebinds its ports (:eaddrinuse). Before app.start, which is
    # what loads runtime.exs.
    for name <- ~w(TLON_START_MCP TLON_START_WEB TLON_START_OBAN TLON_START_SWITCHBOARD TLON_START_ATTENTION),
        do: System.put_env(name, "0")

    Mix.Task.run("app.start")
    r = Server.Doctor.report()
    Mix.shell().info("integrity: #{r.integrity}")
    Mix.shell().info("tables:    #{Enum.join(r.tables, ", ")}")
    Mix.shell().info("migrations: #{r.pending} pending")
    Mix.shell().info("crash dump: #{Server.Doctor.crash_dump()}")
    Mix.shell().info("git fetch:  #{Server.Doctor.git_fetch_urls()}")
    Mix.shell().info("git lock:   #{Server.Doctor.config_lock()}")
    Mix.shell().info("passes:     #{Server.Jobs.Passes.line()}")
    Mix.shell().info("mise trust: #{Server.Doctor.untrusted_checkouts()}")
    Mix.shell().info("worktrees:  #{Server.Doctor.worktree_size()}")

    if dir = opts[:export] do
      paths = Server.Doctor.export(dir)
      Mix.shell().info("exported:  #{length(paths)} table(s) to #{dir}")
    end

    if r.integrity != "ok" or r.pending > 0, do: exit({:shutdown, 1})
  end
end
