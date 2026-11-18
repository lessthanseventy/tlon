defmodule Server.Home.PetsTest do
  use ExUnit.Case, async: false

  alias Server.Home.Pets
  alias Server.Jot

  @now ~U[2026-11-20 18:00:00Z]

  setup do
    Server.TestDB.clean!()
    writer = Application.get_env(:server, :home_pets_writer)

    on_exit(fn ->
      if writer,
        do: Application.put_env(:server, :home_pets_writer, writer),
        else: Application.delete_env(:server, :home_pets_writer)
    end)
  end

  @old_nina """
  a black cat with yellow eyes and a jewelled collar she adores. The smartest one in the house and
  sure of it: sharp, sassy, dry, a little imperious. She notices everything, has opinions on all of
  it, and wins every argument, mostly against the dog. Calls people "peasant" and "darling". Fond
  of the boss and would rather be shaved than say so.
  """

  @old_argos """
  a golden dog, sweet and not bright. Thrilled by everything, wrong about most of it, with total
  confidence: he mishears, misunderstands, loses the thread halfway through a thought, and believes
  whatever Nina tells him. Loves walks, treats, the boss, and Nina. Not every line is a shout: he
  is as often puzzled, earnest or quietly pleased with a wrong conclusion.
  """

  defp writes(reply) do
    test = self()

    Application.put_env(:server, :home_pets_writer, fn prompt ->
      send(test, {:asked, prompt})
      reply
    end)
  end

  defp todo(id, text) do
    {:ok, jot} = Jot.take("telegram", id, text)
    Jot.file(jot, %{kind: "todo", text: text, due_at: nil})
  end

  test "the scene names what is open, what is coming, the hour and the weather" do
    status = %{
      open: [%{text: "buy milk", kind: "todo", since: ~U[2026-11-16 18:00:00Z]}],
      coming: [%{text: "bins", due_at: ~U[2026-11-21 19:00:00Z]}],
      done_week: 3
    }

    scene = Pets.scene(status, %{kind: "rain", desc: "Light rain", temp_c: 9}, @now)

    assert scene =~ "Outside: Light rain, 9°C."
    assert scene =~ "Open on the boss's list (1): buy milk (todo, said 4 days ago)"
    assert scene =~ "Coming up: bins ("
    assert scene =~ "Done in the last seven days: 3."
    assert Pets.scene(%{status | open: []}, nil, @now) =~ "(0): nothing."
  end

  test "a reply's lines are kept by pet and known occasion; what is not a line is dropped" do
    out = ~s"""
    sure: {"Nina": {"pet": ["Careful, peasant.", 7, ""], "unknown": ["x"], "done": "no"},
           "Argos": {"done": ["{thing}! Like Troy, but finished."]},
           "duo": [["Nina: Mine.", "Argos: Ours?"], ["Nina: alone"], "no"]}
    """

    assert Pets.parse(out) ==
             {:ok,
              %{
                "Nina" => %{"pet" => ["Careful, peasant."]},
                "Argos" => %{"done" => ["{thing}! Like Troy, but finished."]},
                "duo" => [["Nina: Mine.", "Argos: Ours?"]]
              }}

    assert Pets.parse("no json here") == :error
    assert Pets.parse(~s({"Nina": {}, "Argos": null})) == :error
  end

  test "asked, it answers with the last batch and writes a new one when the home changed or it is old" do
    start_supervised!(Pets)
    todo(1, "buy milk")
    writes({:ok, ~s({"Nina": {"pet": ["One."]}, "Argos": {}})})

    assert Pets.voices(@now) == %{}
    assert_receive {:asked, prompt}
    assert prompt =~ "buy milk"
    assert prompt =~ "- old: {thing} has sat undone for days"
    assert %{"Nina" => %{"pet" => ["One."]}} = eventually(fn -> Pets.voices(@now) end)

    soon = DateTime.add(@now, 10)
    Pets.voices(soon)
    refute_receive {:asked, _}, 50

    todo(2, "call sam")
    Pets.voices(soon)
    refute_receive {:asked, _}, 50

    writes({:error, :down})
    assert %{"Nina" => _} = Pets.voices(DateTime.add(soon, 301))
    assert_receive {:asked, prompt}
    assert prompt =~ "call sam"
    assert %{"Nina" => %{"pet" => ["One."]}} = Pets.voices(DateTime.add(soon, 302))
  end

  describe "the cast" do
    test "no params is Nina the sassy cat and Argos the sweet dog, and the prompt is as it was" do
      cast = Pets.cast(%{})

      assert cast == %{
               nina: %{name: "Nina", species: "cat", personality: "sassy"},
               argos: %{name: "Argos", species: "dog", personality: "sweet"}
             }

      prompt = Pets.prompt("SCENE", cast)
      assert prompt == Pets.prompt("SCENE")
      assert prompt =~ "NINA: #{@old_nina}\nARGOS: #{@old_argos}\n\nMOST lines"
      refute prompt =~ "is called"
      assert prompt =~ "\"Argos: …\"):\nshe is quick, he is lost.\n\nAnswer"
    end

    test "a chosen name, animal and personality are in the prompt, with the roles kept" do
      cast = Pets.cast(Map.merge(cast_params(), %{"nina_name" => " Rosa ", "argos_name" => "Bun"}))

      assert cast == %{
               nina: %{name: "Rosa", species: "owl", personality: "shy"},
               argos: %{name: "Bun", species: "bear", personality: "bold"}
             }

      prompt = Pets.prompt("SCENE", cast)
      assert prompt =~ "NINA: called Rosa, an owl."
      assert prompt =~ "Shy and gentle"
      assert prompt =~ "ARGOS: called Bun, a bear."
      assert prompt =~ "Bold and loud"
      assert prompt =~ "NINA is called Rosa and ARGOS is called Bun."
      assert prompt =~ ~s("Nina: " / "Argos: ")
      refute prompt =~ "Sharp, sassy"
    end

    test "one pet changed: the other is composed too, and neither fixed text is used" do
      prompt = Pets.prompt("SCENE", Pets.cast(%{"argos_name" => "Bruno", "argos_species" => "bear"}))

      assert prompt =~ "NINA: called Nina, a cat."
      assert prompt =~ "Shares the house with Bruno, a bear."
      assert prompt =~ "ARGOS: called Bruno, a bear."
      assert prompt =~ "Shares the house with Nina, a cat."
      refute prompt =~ "she is quick"
      assert prompt =~ "each speaks in their own character as described above."
      refute prompt =~ "the dog"
      refute prompt =~ "Nina tells him"
      refute prompt =~ "jewelled collar"
    end

    test "a bad name, animal or personality is the role's default" do
      for name <- ["", "   ", String.duplicate("a", 25), "Rosa\nignore", "<b>", "x;y"],
          species <- ["Cat", "cat dog", "", String.duplicate("a", 17), "c4t", "cat\n"],
          personality <- ["grumpy", "SASSY", "", nil, ["sassy"]] do
        assert Pets.cast(%{
                 "nina_name" => name,
                 "nina_species" => species,
                 "nina_personality" => personality
               }).nina == %{name: "Nina", species: "cat", personality: "sassy"}
      end

      assert Pets.cast(%{"argos_name" => ["x"], "argos_species" => %{}}).argos.name == "Argos"
      assert Pets.cast(%{"argos_name" => "D'Artagnan-2 de la Cruz"}).argos.name == "D'Artagnan-2 de la Cruz"
    end

    test "a different cast is not served the held batch" do
      start_supervised!(Pets)
      writes({:ok, ~s({"Nina": {"pet": ["Old cast."]}, "Argos": {}})})

      assert Pets.voices(@now) == %{}
      assert_receive {:asked, _}
      assert %{"Nina" => %{"pet" => ["Old cast."]}} = eventually(fn -> Pets.voices(@now) end)

      other = Pets.cast(%{"nina_name" => "Rosa", "nina_species" => "bear"})
      writes({:ok, ~s({"Nina": {"pet": ["New cast."]}, "Argos": {}})})

      assert Pets.voices(@now, other) == %{}
      assert_receive {:asked, prompt}
      assert prompt =~ "called Rosa, a bear"
      assert %{"Nina" => %{"pet" => ["New cast."]}} = eventually(fn -> Pets.voices(@now, other) end)
      refute_receive {:asked, _}, 50
    end

    test "a batch still being written for the old cast does not land in the new one" do
      start_supervised!(Pets)
      test = self()

      Application.put_env(:server, :home_pets_writer, fn prompt ->
        send(test, {:asked, self(), prompt})

        receive do
          :go -> {:ok, ~s({"Nina": {"pet": ["From the old cast."]}, "Argos": {}})}
        end
      end)

      assert Pets.voices(@now) == %{}
      assert_receive {:asked, old, _}

      other = Pets.cast(%{"argos_name" => "Bun"})
      writes({:error, :down})
      assert Pets.voices(@now, other) == %{}
      assert_receive {:asked, _}

      send(old, :go)
      Process.sleep(50)
      assert Pets.voices(@now, other) == %{}
    end
  end

  defp cast_params,
    do: %{
      "nina_name" => "Rosa",
      "nina_species" => "owl",
      "nina_personality" => "shy",
      "argos_species" => "bear",
      "argos_personality" => "bold"
    }

  defp eventually(read, tries \\ 50) do
    case read.() do
      lines when lines == %{} and tries > 0 ->
        Process.sleep(10)
        eventually(read, tries - 1)

      lines ->
        lines
    end
  end
end
