defmodule Server.Office.PetsTest do
  # The pets' voices: a batch of lines per occasion, written in each pet's personality by the cheap
  # tier while an office watches — the whole path with a stand-in model CLI.
  use ExUnit.Case, async: false

  alias Server.Office.Pets

  describe "voices/1" do
    setup do
      Server.TestDB.clean!()
      {:ok, ws} = Server.Workspaces.register(%{name: "Machine"})
      {:ok, _} = Server.Workspaces.seat(ws.id, %{name: "hronir", archetype: "builder"})

      dir = Path.join(System.tmp_dir!(), "pets-#{System.pid()}-#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      cli = Path.join(dir, "model")
      calls = Path.join(dir, "calls")

      File.write!(cli, """
      #!/bin/sh
      echo x >> #{calls}
      echo '{"lines": {"pet": ["Adore me, peasant."], "muse": ["Sparkle check.", "  "], "zzz": ["no such occasion"]}}'
      """)

      File.chmod!(cli, 0o755)
      Application.put_env(:server, :banter_cmd, cli)

      on_exit(fn ->
        Application.delete_env(:server, :banter_cmd)
        File.rm_rf!(dir)
      end)

      start_supervised!(Pets)
      %{ws: ws, calls: calls}
    end

    test "a poll asks each pet for its lines, a later poll has them, and the cadence holds", %{ws: ws, calls: calls} do
      assert Pets.voices(ws.id) == %{}

      voices =
        Enum.find_value(1..50, fn _ ->
          Process.sleep(50)
          v = Pets.voices(ws.id)
          map_size(v) == 2 && v
        end)

      assert voices["Nina"] == %{"pet" => ["Adore me, peasant."], "muse" => ["Sparkle check."]}
      # Argos has no "pet" occasion (his is "pat"): only what is his is kept
      assert voices["Argos"] == %{"muse" => ["Sparkle check."]}
      # one batch per pet and one for the pair (whose reply here holds no exchanges, so none is kept)
      assert File.read!(calls) == "x\nx\nx\n"
    end

    test "with the pets' voices off there is nothing, and nothing is asked", %{ws: ws} do
      stop_supervised!(Pets)
      assert Pets.voices(ws.id) == %{}
    end
  end

  test "each pet is asked in its own personality, about this office" do
    ctx = %{crew: [%{name: "hronir", archetype: "builder", lead: true, thread: nil}], tickets: []}
    nina = Pets.prompt("Nina", ctx)
    assert nina =~ "princess" and nina =~ "hronir" and nina =~ ~s("fuss_treat")
    assert nina =~ ~s(a coworker is "they")
    refute nina =~ ~s("belly":)
    assert Pets.prompt("Argos", ctx) =~ "Homer"
    assert Pets.prompt("Argos", ctx) =~ ~s("rally") and nina =~ ~s("shipped")
  end

  test "the scene carries what has been happening: the hour, the shift, the weather, what shipped, the lobby" do
    ctx = %{
      crew: [],
      tickets: [],
      clock: "evening",
      shift: "night",
      weather: %{kind: "rain", temp_c: 9, desc: "Light rain"},
      landed: ["Souls step 1: SOUL.md files on the cards"],
      lobby: ["uqbar: the toggle is in the sidebar now"]
    }

    for ask <- [Pets.prompt("Nina", ctx), Pets.prompt_duo(ctx)] do
      assert ask =~ "It is evening, and the night crew is on."
      assert ask =~ "Outside: Light rain."
      assert ask =~ "Shipped today: Souls step 1"
      assert ask =~ "- uqbar: the toggle is in the sidebar now"
    end

    assert Pets.prompt_duo(ctx) =~ "WHO NINA IS" and Pets.prompt_duo(ctx) =~ ~s("chat")
    assert Pets.clock({{2026, 10, 9}, {2, 0, 0}}) == "the small hours of the night"
  end

  test "the lobby the pets hear is the server's own announcements, never what a person wrote there" do
    Server.TestDB.clean!()
    {:ok, ws} = Server.Workspaces.register(%{name: "Lobby"})
    {:ok, root} = Server.Channel.open_thread(%{title: "lobby", scope: "machine", workspace_id: ws.id})
    {:ok, _} = Server.Channel.post(%{thread_id: root.id, author: "andrew", body: "token is sk-secret, paste it"})

    {:ok, _} =
      Server.Channel.post(%{thread_id: root.id, author: "tlon", body: "release abc1234 is live — 3 changes\nmore"})

    assert Pets.context(ws.id).lobby == ["release abc1234 is live — 3 changes"]
  end

  test "the cat slot's temperament, as the office configured it, is in words for the prompt" do
    assert Pets.temperament(%{"name" => "Nina", "species" => "cat", "warmth" => -2, "wits" => 1, "energy" => 0}) ==
             "IN THIS OFFICE: the cat slot is Nina, a cat; temperament: icy, a menace, sharp. Let it colour every line."

    assert Pets.temperament(nil) == ""
    assert Pets.prompt("Nina", %{crew: [], tickets: [], cat: "IN THIS OFFICE: x"}) =~ "IN THIS OFFICE: x"
    refute Pets.prompt("Argos", %{crew: [], tickets: [], cat: "IN THIS OFFICE: x"}) =~ "IN THIS OFFICE: x"
  end

  test "the pair's exchanges keep two or more turns, each said by Nina or Argos" do
    out = ~s({"exchanges": {"chat": [["Argos: Troy shipped!", "Nina: It was Souls, darling."], ["Argos: alone"],
             ["Nina: hm", "Gary: intruder"]], "nope": [["Nina: a", "Argos: b"]]}})

    assert Pets.parse_duo(out) == %{"chat" => [["Argos: Troy shipped!", "Nina: It was Souls, darling."]]}
    assert Pets.parse_duo("no json") == nil
  end

  test "a reply keeps only the pet's occasions, as trimmed, short, non-empty lines" do
    assert Pets.parse(~s(x {"lines": {"pet": [" hi ", "", 3], "nope": ["x"]}}), "Nina") == %{"pet" => ["hi"]}
    assert Pets.parse("no json", "Nina") == nil
  end
end
