defmodule Server.Office.CorkboardTest do
  # The office corkboard: notes the coworkers pin for each other — encouragement, teasing, jokes,
  # comments, suggestions, replies — written by the cheap tier while an office watches, kept apart
  # from the real notes agents work from.
  use ExUnit.Case, async: false

  alias Server.Office.Corkboard

  @crew [
    %{
      name: "hronir",
      archetype: "builder",
      lead: true,
      thread: %{id: 1, title: "fix it", stage: "build", awaiting: nil}
    },
    %{name: "yu", archetype: "reviewer", lead: false, thread: nil}
  ]

  describe "pick/3" do
    test "a reply needs someone else's note to answer; a tease needs someone to tease" do
      alone = %{crew: [hd(@crew)], tickets: []}
      kinds = for i <- 0..99, do: elem(Corkboard.pick(alone, [], hd(@crew), i / 100), 0)
      refute :reply in kinds
      refute :tease in kinds

      board = [%{id: 1, author: "yu", kind: "joke", body: "a joke", re: nil}]
      kinds = for i <- 0..99, do: elem(Corkboard.pick(%{crew: @crew, tickets: []}, board, hd(@crew), i / 100), 0)
      assert :reply in kinds and :tease in kinds and :suggestion in kinds
    end

    test "a reply quotes the note it answers, and says who wrote it" do
      board = [%{id: 7, author: "yu", kind: "tease", body: "hronir's commits read like poems", re: nil}]

      {:reply, ask, re} =
        Enum.find_value(0..99, fn i ->
          r = Corkboard.pick(%{crew: @crew, tickets: []}, board, hd(@crew), i / 100)
          match?({:reply, _, _}, r) && r
        end)

      assert ask =~ "yu" and ask =~ "read like poems"
      assert re == 7
    end
  end

  test "a reply's note is kept trimmed and short; one with no note is dropped" do
    assert Corkboard.parse(~s(ok {"note": "  ship it  "})) == "ship it"
    assert Corkboard.parse(~s({"note": ""})) == nil
    assert Corkboard.parse("nope") == nil
  end

  describe "notes/1" do
    setup do
      Server.TestDB.clean!()
      {:ok, ws} = Server.Workspaces.register(%{name: "Machine"})
      {:ok, _} = Server.Workspaces.seat(ws.id, %{name: "hronir", archetype: "builder"})
      dir = Path.join(System.tmp_dir!(), "cork-#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      cli = Path.join(dir, "model")
      File.write!(cli, ~s(#!/bin/sh\necho '{"note": "Whoever keeps renaming things: I see you."}'\n))
      File.chmod!(cli, 0o755)
      Application.put_env(:server, :banter_cmd, cli)

      on_exit(fn ->
        Application.delete_env(:server, :banter_cmd)
        File.rm_rf!(dir)
      end)

      start_supervised!(Corkboard)
      %{ws: ws}
    end

    test "a poll asks for a note, and a later poll has it pinned", %{ws: ws} do
      assert Corkboard.notes(ws.id) == []

      notes =
        Enum.find_value(1..50, fn _ ->
          Process.sleep(50)
          n = Corkboard.notes(ws.id)
          match?([_], n) && n
        end)

      assert [%{id: 1, author: "hronir", body: "Whoever keeps renaming things: I see you.", kind: kind, at: at}] = notes
      assert kind in ~w(encourage joke comment suggestion) and is_integer(at)
    end
  end
end
