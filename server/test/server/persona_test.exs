defmodule Server.PersonaTest do
  # A seat's persona: generated off the render path by a stand-in model CLI (a script that echoes
  # the prompt's seed into its backstory and counts its calls), stored on the seat, read back.
  use ExUnit.Case, async: false

  alias Server.Persona

  setup do
    Server.TestDB.clean!()
    {:ok, ws} = Server.Workspaces.register(%{name: "Machine"})
    {:ok, _} = Server.Workspaces.seat(ws.id, %{name: "lonnrot", archetype: "reviewer"})
    {:ok, _} = Server.Workspaces.seat(ws.id, %{name: "newcomer", archetype: "builder"})

    dir = Path.join(System.tmp_dir!(), "persona-#{System.pid()}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    cli = Path.join(dir, "model")
    calls = Path.join(dir, "calls")

    File.write!(cli, """
    #!/bin/sh
    echo x >> #{calls}
    seed=$(echo "$2" | grep -o 'Seed: [0-9]*' | cut -d' ' -f2)
    echo "{\\"backstory\\": \\"born under seed $seed\\", \\"quirks\\": {\\"desk_object\\": \\"a magnifying glass\\", \\"hobby\\": \\"chess\\", \\"catchphrase\\": \\"Elementary.\\", \\"pet_peeve\\": \\"loose ends\\"}, \\"voice\\": \\"reads like case notes\\"}"
    """)

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

  test "nothing is stored until a persona is generated", %{ws: ws} do
    assert Persona.get(ws.id, "lonnrot") == nil
  end

  test "generate stores a persona with its seed, readable without a model call", %{ws: ws, calls: calls} do
    assert {:ok, p} = Persona.generate(ws.id, "lonnrot", seed: 42)
    assert %{"seed" => 42, "source" => "model", "voice" => "reads like case notes"} = p
    assert p["backstory"] == "born under seed 42"
    assert p["quirks"]["catchphrase"] == "Elementary."
    assert Persona.get(ws.id, "lonnrot") == p
    assert count(calls) == 1
  end

  test "reroll draws a new seed and records it", %{ws: ws} do
    {:ok, a} = Persona.generate(ws.id, "lonnrot", seed: 42)
    assert {:ok, b} = Persona.reroll(ws.id, "lonnrot")
    assert b["seed"] != a["seed"]
    assert b["backstory"] == "born under seed #{b["seed"]}"
    assert Persona.get(ws.id, "lonnrot") == b
  end

  test "the same seed gives the same persona", %{ws: ws} do
    {:ok, a} = Persona.generate(ws.id, "lonnrot", seed: 7)
    {:ok, b} = Persona.generate(ws.id, "lonnrot", seed: 7)
    assert a == b
  end

  test "a failing call falls back to the §2 voice table, stored as a fallback", %{ws: ws, cli: cli} do
    File.write!(cli, "#!/bin/sh\nexit 3\n")
    assert {:ok, p} = Persona.generate(ws.id, "lonnrot", seed: 1)
    assert %{"source" => "fallback", "voice" => "a detective; reviews read like case notes"} = p
    assert is_binary(p["backstory"]) and is_map(p["quirks"])
  end

  test "a seat the table doesn't know falls back on its archetype", %{ws: ws, cli: cli} do
    File.write!(cli, "#!/bin/sh\nexit 3\n")
    assert {:ok, %{"source" => "fallback", "voice" => voice}} = Persona.generate(ws.id, "newcomer", seed: 1)
    assert is_binary(voice) and voice != ""
  end

  test "the daily cap stops calls; the seat gets the fallback", %{ws: ws, calls: calls} do
    Application.put_env(:server, :generator_daily_cap, 1)
    assert {:ok, %{"source" => "model"}} = Persona.generate(ws.id, "lonnrot", seed: 1)
    assert {:ok, %{"source" => "fallback"}} = Persona.generate(ws.id, "newcomer", seed: 1)
    assert count(calls) == 1
  end

  test "banter off in the settings file means no call", %{ws: ws, calls: calls} do
    path = Path.join(System.tmp_dir!(), "tlon-config-#{System.pid()}-#{System.unique_integer([:positive])}.json")
    File.write!(path, ~s({"banter": false}))
    Application.put_env(:server, :operator_config_path, path)

    on_exit(fn ->
      Application.put_env(:server, :operator_config_path, "/nonexistent/tlon-test-config.json")
      File.rm(path)
    end)

    assert {:ok, %{"source" => "fallback"}} = Persona.generate(ws.id, "lonnrot", seed: 1)
    assert count(calls) == 0
  end

  test "ensure generates once and then reads", %{ws: ws, calls: calls} do
    {:ok, a} = Persona.ensure(ws.id, "lonnrot")
    {:ok, b} = Persona.ensure(ws.id, "lonnrot")
    assert a == b
    assert count(calls) == 1
  end

  test "an unknown seat is an error", %{ws: ws} do
    assert {:error, :no_seat} = Persona.generate(ws.id, "nobody", seed: 1)
  end

  test "edit changes the named fields, keeps the seed, and marks it edited", %{ws: ws} do
    {:ok, a} = Persona.generate(ws.id, "lonnrot", seed: 42)

    assert {:ok, b} =
             Persona.edit(ws.id, "lonnrot", %{
               "voice" => "terse",
               "quirks" => %{"hobby" => "go"},
               "seed" => 9,
               "nope" => 1
             })

    assert b["voice"] == "terse" and b["seed"] == 42 and b["edited"] == true
    assert b["quirks"]["hobby"] == "go" and b["quirks"]["catchphrase"] == a["quirks"]["catchphrase"]
    refute Map.has_key?(b, "nope")
    assert Persona.get(ws.id, "lonnrot") == b
  end

  test "edit keeps only string values and ignores a non-map quirks", %{ws: ws} do
    {:ok, a} = Persona.generate(ws.id, "lonnrot", seed: 42)
    assert {:ok, b} = Persona.edit(ws.id, "lonnrot", %{"backstory" => 5, "voice" => "  calm  ", "quirks" => "x"})
    assert b["backstory"] == a["backstory"]
    assert b["voice"] == "calm"
    assert b["quirks"] == a["quirks"]
    assert {:ok, c} = Persona.edit(ws.id, "lonnrot", %{"quirks" => %{"hobby" => 7, "catchphrase" => "Aha."}})
    assert c["quirks"]["hobby"] == a["quirks"]["hobby"] and c["quirks"]["catchphrase"] == "Aha."
  end

  test "reroll keeps the stored persona when the generator gave no model one", %{ws: ws, cli: cli} do
    {:ok, a} = Persona.generate(ws.id, "lonnrot", seed: 42)
    File.write!(cli, "#!/bin/sh\nexit 3\n")
    assert {:error, :generator_unavailable} = Persona.reroll(ws.id, "lonnrot")
    assert Persona.get(ws.id, "lonnrot") == a
  end

  test "the office snapshot's bench carries the seat's persona", %{ws: ws} do
    seat = fn -> Enum.find(Server.Office.status().bench, &(&1.name == "lonnrot")) end
    assert seat.().persona == nil
    {:ok, p} = Persona.generate(ws.id, "lonnrot", seed: 3)
    assert seat.().persona == p
  end
end
