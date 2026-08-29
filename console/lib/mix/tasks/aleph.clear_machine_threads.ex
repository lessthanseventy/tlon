defmodule Mix.Tasks.Console.ClearMachineThreads do
  @shortdoc "Clean-slate: delete every MACHINE-scope thread + its messages from the dev db"
  @moduledoc """
  A clean-slate reset: machine threads are disposable, so clear them ONCE, by hand, so the only
  pre-existing machine thread the cockpit finds afterward is the standing coworker's (opened fresh on
  the next `aleph:run`) — not stale leaves that `ensure_thread_sessions` would spawn windows for.

  Boots funes as a READER (no MCP, no switchboard — this is a one-shot script, not a live
  service), against `TLON_DB`, then deletes every `scope == "machine"` thread and its messages via
  `Server.Channel.clear_machine_threads/0`. Project-scope threads are never touched. Prints how
  many threads/messages it cleared.
  """
  use Mix.Task
  use Boundary, classify_to: Console

  alias Server.Channel

  @requirements ["app.config"]

  @impl Mix.Task
  def run(_args) do
    # READER role: no MCP, no switchboard — a one-shot script never wants to bind :4041.
    Application.put_env(:server, :start_mcp, false)
    Application.put_env(:server, :start_switchboard, false)

    case Application.ensure_all_started(:server) do
      {:ok, _apps} ->
        {:ok, %{threads: threads, messages: messages}} = Channel.clear_machine_threads()

        Mix.shell().info("aleph:clear-machine-threads — cleared #{threads} machine thread(s), #{messages} message(s).")

      {:error, reason} ->
        Mix.shell().error("aleph:clear-machine-threads could not boot funes: #{inspect(reason)}")
    end
  end
end
