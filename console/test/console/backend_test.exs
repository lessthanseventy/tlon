defmodule Console.BackendTest do
  use ExUnit.Case, async: true

  alias Console.Server.Channel

  # the one door: `Console.Backend.call/3` dispatches to the configured impl; the default is
  # Local (apply in this node) — the test env and `server:dev`
  test "Local backend applies in-node" do
    assert Console.Backend.impl() == Console.Backend.Local
    assert Console.Backend.call(String, :upcase, ["tlön"]) == "TLÖN"
  end

  # the facades mirror the server's contexts: every public function, same arity, routed
  # through the backend — a renamed server function fails to compile at its call site instead
  # of drifting
  test "facades mirror their targets' public functions" do
    for facade <- [
          Console.Server,
          Console.Server.Board,
          Channel,
          Console.Server.Dossier,
          Console.Server.Staff,
          Console.Server.Notes,
          Console.Server.Tickets,
          Console.Server.Workspaces,
          Console.Server.Doctor,
          Console.Server.Presence.Thinking,
          Console.Server.MCP.Spawn
        ] do
      target = facade.__target__()
      expected = for {f, a} <- target.__info__(:functions), not String.starts_with?(Atom.to_string(f), "__"), do: {f, a}
      mirrored = facade.__info__(:functions) -- [__target__: 0]
      assert Enum.sort(mirrored) == Enum.sort(expected), "#{inspect(facade)} drifted from #{inspect(target)}"
    end
  end

  # pure helpers stay in-node whatever the backend: operator?/1 is called per render
  test "local helpers bypass the backend" do
    Application.put_env(:console, :backend, Console.BackendTest.Boom)

    try do
      assert Channel.operator?("andrew") == Server.Channel.operator?("andrew")
      assert_raise RuntimeError, ~r/boom/, fn -> Channel.machine_threads() end
    after
      Application.delete_env(:console, :backend)
    end
  end

  defmodule Boom do
    @moduledoc false
    @behaviour Console.Backend

    def call(_m, _f, _a), do: raise("boom")
  end
end

defmodule Console.Backend.RemoteTest do
  use ExUnit.Case, async: false

  alias Console.Backend.Link
  alias Console.Backend.Remote

  # erpc to this very node works without distribution: the Remote impl's plumbing, minus the wire
  test "Remote calls over erpc to the configured node" do
    Application.put_env(:console, :server_node, node())

    try do
      assert Remote.call(String, :upcase, ["tlön"]) == "TLÖN"
      # a remote raise comes back as the same exception class
      assert_raise ArgumentError, fn -> Remote.call(String, :to_integer, ["x"]) end
    after
      Application.delete_env(:console, :server_node)
    end
  end

  # no such node: the erpc noconnection becomes ServerDown, which Console.Safe degrades
  test "an unreachable server node raises ServerDown" do
    Application.put_env(:console, :server_node, :"nobody@127.0.0.1")

    try do
      assert_raise Console.Backend.ServerDown, ~r/noconnection on Server.Board.brief\/1/, fn ->
        Remote.call(Server.Board, :brief, [1])
      end

      assert Console.Safe.value(fn -> Remote.call(Server.Board, :brief, [1]) end, :stale) == :stale
    after
      Application.delete_env(:console, :server_node)
    end
  end

  test "the cookie comes from the shared file" do
    dir = Path.join(System.tmp_dir!(), "tlon-cookie-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    System.put_env("TLON_COOKIE_FILE", Path.join(dir, "cookie"))

    try do
      assert Link.cookie() == nil
      File.write!(Path.join(dir, "cookie"), "s3cret\n")
      assert Link.cookie() == :s3cret
    after
      System.delete_env("TLON_COOKIE_FILE")
      File.rm_rf!(dir)
    end
  end
end
