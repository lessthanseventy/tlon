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
    test "a reply needs someone else's note to answer; a tease, someone to tease" do
      alone = %{crew: [hd(@crew)], tickets: []}
      kinds = for i <- 0..99, do: elem(Corkboard.pick(alone, [], hd(@crew), i / 100), 0)
      refute :reply in kinds
      refute :tease in kinds

      board = [%{id: 1, author: "hronir", kind: "joke", body: "a joke", re: nil}]
      yu = Enum.at(@crew, 1)
      picks = for i <- 0..99, do: Corkboard.pick(%{crew: @crew, tickets: []}, board, yu, i / 100)
      assert Enum.all?([:reply, :tease], &(&1 in Enum.map(picks, fn p -> elem(p, 0) end)))
    end

    test "the banter never writes a bug report: no suggestion is drawn, and the voice forbids claims about the work" do
      board = [%{id: 1, author: "hronir", kind: "joke", body: "a joke", re: nil}]

      kinds =
        for i <- 0..99, do: elem(Corkboard.pick(%{crew: @crew, tickets: []}, board, Enum.at(@crew, 1), i / 100), 0)

      refute :suggestion in kinds
      assert Corkboard.voice() =~ "never a ticket or thread number"
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

  test "a side project is due once a day, only for a seat that has the section" do
    now = ~U[2026-10-14 10:00:00Z]
    assert Corkboard.side_due?(%{section: "The Earth", last: nil}, now)
    assert Corkboard.side_due?(%{section: "The Earth", last: ~U[2026-10-13 09:00:00Z]}, now)
    refute Corkboard.side_due?(%{section: "The Earth", last: ~U[2026-10-14 01:00:00Z]}, now)
    refute Corkboard.side_due?(%{section: "", last: nil}, now)
  end

  test "a seat's side-project counter lives on the standing thread and survives a restart" do
    Server.TestDB.clean!()
    {:ok, ws} = Server.Workspaces.register(%{name: "Sided"})
    {:ok, _} = Server.Channel.open_thread(%{title: "standing", scope: "machine", workspace_id: ws.id})
    start_supervised!(Corkboard)

    assert Corkboard.side_state(ws.id, "daneri") == %{n: 0, last: nil}
    assert {:ok, _} = Corkboard.post_side_project(ws.id, "daneri", "stanza one", 1)
    assert {:ok, newer} = Corkboard.post_side_project(ws.id, "daneri", "stanza two", 2)
    assert {:ok, _} = Corkboard.post_side_project(ws.id, "yu", "elsewhere", 1)

    expect = %{n: 2, last: newer.created_at}
    assert Corkboard.side_state(ws.id, "daneri") == expect

    stop_supervised!(Corkboard)
    start_supervised!(Corkboard)
    assert Corkboard.side_state(ws.id, "daneri") == expect
    assert %Server.Message{kind: "side project", delivered_at: %DateTime{}} = Server.Repo.get(Server.Message, newer.id)
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
      dir = Path.join(System.tmp_dir!(), "cork-#{System.pid()}-#{System.unique_integer([:positive])}")
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
      assert kind in ~w(encourage joke comment) and is_integer(at)
    end
  end

  test "a coworker's suggestion goes in the box on the standing thread, apart from the chatter, survives a restart, and leaves when dropped" do
    Server.TestDB.clean!()
    {:ok, ws} = Server.Workspaces.register(%{name: "Boxed"})
    {:ok, root} = Server.Channel.open_thread(%{title: "standing", scope: "machine", workspace_id: ws.id})
    {:ok, work} = Server.Channel.open_thread(%{title: "work", workspace_id: ws.id})
    start_supervised!(Corkboard)

    assert {:ok, _} = Corkboard.suggest(ws.id, "ashe", "log first-failure times", work.id)
    assert {:error, _} = Corkboard.suggest(ws.id, "ashe", "  ", work.id)
    GenServer.cast(Corkboard, {:pinned, ws.id, %{author: "yu", kind: "joke", body: "a joke", re: nil}})
    refute Enum.any?(:sys.get_state(Corkboard)[ws.id].notes, &(&1.kind == "suggestion"))

    stop_supervised!(Corkboard)
    start_supervised!(Corkboard)

    assert [%{id: id, author: "ashe", kind: "suggestion", body: note, re: nil, at: at}] = Corkboard.suggestions(ws.id)
    assert note == "log first-failure times (seen on ##{work.id})"
    assert is_integer(at)

    assert %Server.Message{thread_id: thread_id, kind: "suggestion", delivered_at: %DateTime{}, body: body} =
             Server.Repo.get(Server.Message, id)

    assert thread_id == root.id and body =~ "suggestion from ashe, while on ##{work.id}"

    assert :ok = Corkboard.drop(ws.id, id)
    assert Corkboard.suggestions(ws.id) == []
    assert %Server.Message{resolved_at: %DateTime{}} = Server.Repo.get(Server.Message, id)
  end
end
