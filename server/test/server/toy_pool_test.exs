defmodule Server.ToyPoolTest do
  # The toy's generated pools — doorbell visitors, in-voice reactions per event, puns — written by a
  # stand-in model CLI, stored, and read back without a call.
  use ExUnit.Case, async: false

  alias Server.{Persona, ToyPool}

  @reply ~s({"backstory": "b", "quirks": {"desk_object": "a", "hobby": "b", "catchphrase": "c", "pet_peeve": "d"}, "voice": "v", "visitors": [{"name": "Mabel", "look_seed": 3, "line": "Cookies, anyone?"}], "reactions": {"zoo": ["Is that a goat?"], "duck": ["Hm."]}, "puns": ["I'd tell a UDP joke, but you might not get it."]})

  setup do
    Server.TestDB.clean!()
    {:ok, ws} = Server.Workspaces.register(%{name: "Machine"})
    {:ok, _} = Server.Workspaces.seat(ws.id, %{name: "lonnrot", archetype: "reviewer"})

    dir = Path.join(System.tmp_dir!(), "pool-#{System.pid()}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    cli = Path.join(dir, "model")
    calls = Path.join(dir, "calls")
    File.write!(cli, "#!/bin/sh\necho x >> #{calls}\ncat <<'END'\n#{@reply}\nEND\n")
    File.chmod!(cli, 0o755)
    Application.put_env(:server, :generator_cmd, cli)

    on_exit(fn ->
      Application.put_env(:server, :generator_cmd, "/nonexistent/tlon-test-generator")
      Application.delete_env(:server, :generator_daily_cap)
      File.rm_rf!(dir)
    end)

    %{ws: ws, calls: calls, cli: cli}
  end

  defp count(calls),
    do: if(File.exists?(calls), do: calls |> File.read!() |> String.split("\n", trim: true) |> length(), else: 0)

  test "an unfilled pool reads empty, with no call", %{ws: ws, calls: calls} do
    assert ToyPool.visitors(ws.id) == []
    assert ToyPool.puns(ws.id) == []
    assert ToyPool.reactions(ws.id, "lonnrot", "zoo") == []
    assert count(calls) == 0
  end

  test "visitors are refreshed, stored, and read back", %{ws: ws, calls: calls} do
    assert {:ok, [%{"name" => "Mabel", "look_seed" => 3, "line" => "Cookies, anyone?"}]} =
             ToyPool.refresh(ws.id, :visitors, seed: 5)

    assert [%{"name" => "Mabel"}] = ToyPool.visitors(ws.id)
    assert count(calls) == 1
  end

  test "the weekly refresh is a no-op while the pool is fresh", %{ws: ws, calls: calls} do
    assert {:ok, _} = ToyPool.refresh_due(ws.id, :visitors)
    assert {:ok, _} = ToyPool.refresh_due(ws.id, :visitors)
    assert count(calls) == 1

    ToyPool.age!(ws.id, :visitors, 8)
    assert {:ok, _} = ToyPool.refresh_due(ws.id, :visitors)
    assert count(calls) == 2
  end

  test "reactions are per seat and event", %{ws: ws} do
    assert {:ok, _} = ToyPool.refresh(ws.id, {:reactions, "lonnrot"}, seed: 1)
    assert ToyPool.reactions(ws.id, "lonnrot", "zoo") == ["Is that a goat?"]
    assert ToyPool.reactions(ws.id, "lonnrot", "meteor") == []
    assert ToyPool.reactions(ws.id, "yu", "zoo") == []
  end

  test "puns", %{ws: ws} do
    assert {:ok, [_]} = ToyPool.refresh(ws.id, :puns, seed: 1)
    assert [<<"I'd tell a UDP", _::binary>>] = ToyPool.puns(ws.id)
  end

  test "a failing call stores nothing and the pool stays as it was", %{ws: ws, cli: cli} do
    {:ok, _} = ToyPool.refresh(ws.id, :puns, seed: 1)
    File.write!(cli, "#!/bin/sh\nexit 3\n")
    assert {:error, _} = ToyPool.refresh(ws.id, :puns, seed: 2)
    assert [_] = ToyPool.puns(ws.id)
  end

  test "banter off means no call", %{ws: ws, calls: calls} do
    path = Path.join(System.tmp_dir!(), "tlon-config-#{System.pid()}-#{System.unique_integer([:positive])}.json")
    File.write!(path, ~s({"banter": false}))
    Application.put_env(:server, :operator_config_path, path)

    on_exit(fn ->
      Application.put_env(:server, :operator_config_path, "/nonexistent/tlon-test-config.json")
      File.rm(path)
    end)

    assert {:error, :off} = ToyPool.refresh(ws.id, :puns, seed: 1)
    assert count(calls) == 0
  end

  test "personas and pools share the one daily cap", %{ws: ws, calls: calls} do
    Application.put_env(:server, :generator_daily_cap, 2)
    assert {:ok, %{"source" => "model"}} = Persona.generate(ws.id, "lonnrot", seed: 1)
    assert {:ok, _} = ToyPool.refresh(ws.id, :puns, seed: 1)
    assert {:error, :capped} = ToyPool.refresh(ws.id, :visitors, seed: 1)
    assert count(calls) == 2
  end
end
