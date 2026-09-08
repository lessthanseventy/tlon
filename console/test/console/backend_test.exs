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
