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
