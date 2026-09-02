defmodule Console.Arbiter do
  @moduledoc """
  The arbiter backend for the console hub — how the server's switchboard actuates a wake now that sessions
  are embedded ghostty terminals console owns, not tmux panes. Configured as `config :server, :arbiter,
  Console.Arbiter`: server calls it through the behaviour seam (§8), never importing console — the
  dependency stays one-directional, server → nothing.

  - `wake(session, prompt)` — write the prompt into the session's terminal (keyed by its thread) so
    the harness takes a turn. Poking an agent is not a production write (§8): it SANITIZES the
    prompt to one clean line and appends Enter, rather than failing closed.
  - `spawn(exports)` — open a fresh terminal for the thread named in the env block (the cold-thread
    strand), the same `Console.Sessions.spawn_harness` the `s` verb uses.
  """
  @behaviour Server.Arbiter

  alias Console.Sessions
  alias Console.Terminal

  @impl Server.Arbiter
  def wake(%{thread_id: thread_id}, prompt) do
    case safe_terminal(thread_id) do
      nil -> {:error, :no_terminal}
      term -> Terminal.feed(term, sanitize(prompt) <> "\r")
    end
  end

  @impl Server.Arbiter
  def spawn(exports) do
    case thread_id(exports) do
      nil -> {:error, :no_thread_in_exports}
      thread_id -> safe_spawn_harness(thread_id, exports)
    end
  end

  # Sessions is supervised, the switchboard is not: a `Sessions.terminal/1` against a wedged or
  # torn-down registry exits (`:noproc`, or a 5s `:timeout` while `{:ensure}` blocks spawning a
  # terminal), which would otherwise propagate up and kill the hub — the ISSUES-panel
  # `GenServer.call(Console.Sessions, {:terminal, :machine}, 5000)`. Degrade to nil / {:error, ...}
  # so the switchboard leaves the message a pending durable row and retries once Sessions is live,
  # mirroring the cockpit's own `safe_terminal/1` guard.
  defp safe_terminal(thread_id) do
    Sessions.terminal(thread_id)
  catch
    :exit, _ -> nil
  end

  defp safe_spawn_harness(thread_id, exports) do
    Sessions.spawn_harness(thread_id, exports)
  catch
    :exit, _ -> {:error, :sessions_down}
  end

  @doc "Collapse a prompt to one clean line — control bytes → spaces, runs collapsed, trimmed."
  def sanitize(prompt) do
    prompt
    |> String.replace(~r/[[:cntrl:]]/, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  @doc "The thread id in an `export TLON_THREAD=\"N\"` block, or nil."
  def thread_id(exports) do
    case Regex.run(~r/TLON_THREAD="(\d+)"/, exports) do
      [_whole, id] -> String.to_integer(id)
      _ -> nil
    end
  end
end
