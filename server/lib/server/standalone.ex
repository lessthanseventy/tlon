defmodule Server.Standalone do
  @moduledoc """
  The standalone binary — the release wrapped by Burrito into one executable per platform
  (`mise run server:package`) — and what it does with its command line. With nothing, or
  `serve`, it is the service: it migrates the store, boots with the service's defaults
  (`config/runtime.exs` turns every `TLON_START_*` on under Burrito), and stays up until
  signalled. Outside that binary `boot/0` does nothing: the systemd service and the dev nodes
  start as they always have.
  """

  @usage """
  usage: tlon [serve]   migrate the store, then serve until signalled (the default)
         tlon help      this
  Configured like the service, by TLON_* environment variables: TLON_DATABASE or
  TLON_DATABASE_URL, TLON_MCP_PORT (4040), TLON_WEB_PORT (4042), TLON_START_*=0 to turn a part off.
  Needs Postgres and tmux on the machine.
  """

  @doc "What a command line asks for."
  @spec command([String.t()]) :: :serve | :help | {:unknown, String.t()}
  def command([]), do: :serve
  def command(["serve"]), do: :serve
  def command([h | _]) when h in ~w(help --help -h), do: :help
  def command([other | _]), do: {:unknown, other}

  @doc "Run the standalone binary's command, at application start; a no-op anywhere else."
  @spec boot() :: :ok
  def boot do
    if System.get_env("__BURRITO") == "1", do: run(command(Burrito.Util.Args.argv()))
    :ok
  end

  defp run(:serve) do
    Server.Release.migrate()
    # Burrito boots through Elixir's CLI, which halts once it has nothing left to run; this hook
    # runs just before that halt and holds the VM up. A SIGTERM still stops it cleanly.
    System.at_exit(fn _ -> Process.sleep(:infinity) end)
  end

  defp run(:help) do
    IO.puts(@usage)
    System.halt(0)
  end

  defp run({:unknown, c}) do
    IO.puts(:stderr, "tlon: no command `#{c}`\n\n" <> @usage)
    System.halt(2)
  end
end
