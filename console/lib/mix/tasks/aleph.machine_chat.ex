defmodule Mix.Tasks.Console.MachineChat do
  @shortdoc "The Tlön machine-chat tab — machine threads as foldable, interactive blocks (a tmux tab)"
  @moduledoc """
  The interactive Tlön machine-chat — "Overview for the Tlön space": the machine-scope threads
  (`Server.Channel.machine_threads/1`) rendered as **foldable blocks** with author-turn grouping
  inside each, plus `z`-zoom to full-pane. console opens this as the `chat` window (a tmux tab in the
  Tlön strip, next to `pi`/`claude`); run it by hand from `modules/aleph` for the same view anywhere.

  Keys: `↑↓`/`jk` move the selected block · `Enter`/`Space` fold↔unfold · `z` zoom · `Esc` back ·
  `PgUp`/`PgDn` scroll · `q` quit.

  ## Why it POLLS the db

  A SEPARATE OS process from the cockpit, so `Server.Bus` (node-local `Phoenix.PubSub`) is out of
  reach; it reads the one thing the two share — the SQLite file at `TLON_DB`, carried into the Tlön
  tmux session env — polling for new messages. Reader role: no MCP, no switchboard, so it never
  binds :4041 (the cockpit already does) and Ecto's per-query logs are silenced.
  """
  use Mix.Task
  use Boundary, classify_to: Console

  @requirements ["app.config"]

  @impl Mix.Task
  def run(_args) do
    # READER role: no MCP, no switchboard. Override before the app starts so `Server.Application`
    # reads the false and never binds :4041.
    Application.put_env(:server, :start_mcp, false)
    Application.put_env(:server, :start_switchboard, false)

    # A human-facing TUI, not a service log: silence Ecto's per-query lines and server boot chatter.
    Application.put_env(:server, Server.Repo, Keyword.put(Application.get_env(:server, Server.Repo, []), :log, false))
    Logger.configure(level: :warning)

    case Application.ensure_all_started(:server) do
      {:ok, _apps} ->
        Console.MachineChat.Loop.run()

      {:error, reason} ->
        Mix.shell().error("console.machine_chat could not boot server: #{inspect(reason)}")
    end
  end
end
