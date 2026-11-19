defmodule Server.Home.AgendasTest do
  use ExUnit.Case, async: false

  alias Server.Agenda
  alias Server.Home.Clock
  alias Server.Home.Inbox
  alias Server.Jot

  setup do
    Server.TestDB.clean!()
    on_exit(fn -> Application.delete_env(:server, :home_reader) end)
    me = self()

    %{
      say: fn chat, text, _opts ->
        send(me, {:said, chat, text})
        :ok
      end
    }
  end

  defp thursday, do: Clock.utc(~N[2026-11-19 14:00:00])

  # the reader, stubbed: a message and what it is read as, and the agendas it was shown
  defp say_it(text, reading, say, id) do
    me = self()

    Application.put_env(:server, :home_reader, fn ^text, context ->
      send(me, {:shown, context[:agendas]})
      {:ok, Map.merge(%{text: "", due_at: nil, every: nil, ids: [], amends: false}, reading)}
    end)

    Inbox.hear([%{id: id, chat: "42", text: text}], "telegram", "42", say)
  end

  defp replied do
    assert_receive {:said, "42", reply}
    reply
  end

  test ~s("for retro: the deploy took three tries" starts the agenda retro, and "retro - flaky gate again" files on it),
       %{
         say: say
       } do
    say_it(
      "for retro: the deploy took three tries",
      %{kind: "agenda", agenda: "retro", text: "the deploy took three tries"},
      say,
      1
    )

    assert_received {:shown, []}
    assert replied() == "Started a new agenda, retro. On the retro pile (1)."

    say_it("retro - flaky gate again", %{kind: "agenda", agenda: "Retro", text: "flaky gate again"}, say, 2)
    assert_received {:shown, ["retro"]}
    assert replied() == "On the retro pile (2)."

    assert [%{name: "retro", id: id}] = Agenda.all("telegram")
    assert ["the deploy took three tries", "flaky gate again"] = Enum.map(Jot.agenda_notes(id), & &1.text)
    assert Jot.notes("telegram", 20) == []
  end

  test ~s("tell Sam about the conference budget in our 1:1" and "add to weekly: …" file on their agendas), %{say: say} do
    say_it(
      "tell Sam about the conference budget in our 1:1",
      %{kind: "agenda", agenda: "1:1 with Sam", text: "conference budget"},
      say,
      1
    )

    assert replied() =~ "Started a new agenda, 1:1 with Sam."

    say_it("my 1:1: the offsite", %{kind: "agenda", agenda: "1:1 with Sam", text: "the offsite"}, say, 2)
    assert_received {:shown, ["1:1 with Sam"]}
    assert replied() == "On the 1:1 with Sam pile (2)."

    say_it("add to weekly: rotate the on-call", %{kind: "agenda", agenda: "weekly", text: "rotate the on-call"}, say, 3)
    assert replied() == "Started a new agenda, weekly. On the weekly pile (1)."
  end

  test "\"retro is every other Thursday at 2\" creates the agenda with its rhythm, and sets it on an existing one", %{
    say: say
  } do
    {:ok, jot} = Jot.take("telegram", 1, "retro is every other Thursday at 2")
    reading = %{kind: "agenda_set", agenda: "retro", due_at: thursday(), every: "2 week", text: ""}

    assert Server.Home.Agendas.ask(jot, reading, DateTime.add(thursday(), -1, :day)) ==
             "Started a new agenda, retro. retro is every 2 weeks, next Thu 19 Nov 14:00."

    assert %{every: "2 week", next_at: at} = Agenda.named("telegram", "retro")
    assert at == thursday()

    say_it(
      "my 1:1 with Sam is weekly on Mondays at 10",
      %{kind: "agenda_set", agenda: "1:1 with Sam", due_at: Clock.utc(~N[2026-11-23 10:00:00]), every: "week"},
      say,
      2
    )

    assert replied() =~ "1:1 with Sam is every week"

    say_it("retro is weekly", %{kind: "agenda_set", agenda: "retro", every: "week"}, say, 3)
    assert replied() =~ "retro is every week, next"
    assert %{every: "week"} = Agenda.named("telegram", "retro")
  end

  test "\"what's on retro?\" answers with the pile", %{say: say} do
    say_it("for retro: a", %{kind: "agenda", agenda: "retro", text: "a"}, say, 1)
    replied()
    say_it("what's on retro?", %{kind: "agenda_show", agenda: "retro"}, say, 2)
    assert replied() == "On the retro pile (1):\n• a"
    say_it("what do I have for Sam?", %{kind: "agenda_show", agenda: "1:1 with Sam"}, say, 3)
    assert replied() == "I don't have an agenda called 1:1 with Sam."
    assert [%{kind: "talk"}, %{kind: "talk"}, %{kind: "note"}] = Jot.recent("telegram", 3)
  end

  test ~s("retro's done" archives the pile, and "what did we cover last retro?" answers from it), %{say: say} do
    say_it("for retro: a", %{kind: "agenda", agenda: "retro", text: "a"}, say, 1)
    say_it("for retro: b", %{kind: "agenda", agenda: "retro", text: "b"}, say, 2)
    replied()
    replied()

    say_it("retro's done", %{kind: "agenda_clear", agenda: "retro"}, say, 3)
    assert replied() == "Cleared the retro pile (2 kept, done)."
    say_it("clear retro", %{kind: "agenda_clear", agenda: "retro"}, say, 4)
    assert replied() == "The retro pile was already empty."
    say_it("what's on retro?", %{kind: "agenda_show", agenda: "retro"}, say, 5)
    assert replied() == "Nothing on the retro pile."

    say_it("what did we cover last retro?", %{kind: "agenda_past", agenda: "retro"}, say, 6)
    assert replied() =~ ~r/^On the retro pile when it was cleared, \w+ \d+ \w+:\n• a\n• b$/
  end

  test "a correction of the note just said edits it in place, and it stays on its pile", %{say: say} do
    say_it("for retro: flaky gate", %{kind: "agenda", agenda: "retro", text: "flaky gate"}, say, 1)
    replied()
    say_it("no, flaky gate again", %{kind: "note", text: "flaky gate again", amends: true}, say, 2)
    assert replied() == "changed: noted: flaky gate again"
    assert %{id: id} = Agenda.named("telegram", "retro")
    assert ["flaky gate again"] = Enum.map(Jot.agenda_notes(id), & &1.text)
    assert Jot.notes("telegram", 20) == []
  end

  test "a correction that puts a plain note on a pile moves that note: one note, not two", %{say: say} do
    say_it("flaky gate again", %{kind: "note", text: "flaky gate again"}, say, 1)
    replied()
    say_it("no, that's for retro", %{kind: "agenda", agenda: "retro", text: "flaky gate again", amends: true}, say, 2)
    assert replied() == "changed: Started a new agenda, retro. On the retro pile (1)."

    assert %{id: id} = Agenda.named("telegram", "retro")
    assert [%{text: "flaky gate again"}] = Jot.agenda_notes(id)
    assert Jot.notes("telegram", 20) == []
    assert [%{kind: "amend"}, %{kind: "note", agenda_id: ^id}] = Jot.recent("telegram", 2)
  end

  test "a pile note re-filed as a to-do leaves the pile, and stays off it when corrected back to a note", %{say: say} do
    say_it("for retro: call the vendor", %{kind: "agenda", agenda: "retro", text: "call the vendor"}, say, 1)
    replied()
    say_it("no, I'll just do it", %{kind: "todo", text: "call the vendor", amends: true}, say, 2)
    replied()

    assert %{id: id} = Agenda.named("telegram", "retro")
    assert Jot.agenda_notes(id) == []
    assert [%{text: "call the vendor", kind: "todo", agenda_id: nil}] = Jot.opens("telegram")

    say_it("no, just a note", %{kind: "note", text: "call the vendor", amends: true}, say, 3)
    replied()
    assert Jot.agenda_notes(id) == []
    assert [%{text: "call the vendor"}] = "telegram" |> Jot.notes(20) |> Enum.map(&%{text: &1})
  end

  test "a correction onto a pile leaves a project as it is and files a new note", %{say: say} do
    reading = %{kind: "project", text: "plan the trip", steps: ["book the flights"]}
    say_it("plan the trip", reading, say, 1)
    replied()
    assert [%{id: project_id}] = Jot.projects("telegram")

    say_it("no, that's for retro", %{kind: "agenda", agenda: "retro", text: "plan the trip", amends: true}, say, 2)
    assert replied() == "Started a new agenda, retro. On the retro pile (1)."

    assert [%{id: ^project_id, kind: "project"}] = Jot.projects("telegram")
    assert [%{agenda_id: nil, project_id: ^project_id}] = Jot.steps(project_id)
    assert %{id: id} = Agenda.named("telegram", "retro")
    assert [%{id: note_id, text: "plan the trip"}] = Jot.agenda_notes(id)
    assert note_id != project_id
  end

  test "a correction onto a pile leaves a project's step as it is and files a new note", %{say: say} do
    say_it("plan the trip", %{kind: "project", text: "plan the trip", steps: ["book the flights"]}, say, 1)
    replied()
    assert [%{id: project_id}] = Jot.projects("telegram")
    {:ok, step} = Jot.take("telegram", 2, "pack bags")
    Jot.file(step, %{kind: "todo", text: "pack bags", due_at: nil, project: project_id})
    step_id = step.id

    say_it("no, that's for retro", %{kind: "agenda", agenda: "retro", text: "pack bags", amends: true}, say, 3)
    assert replied() == "Started a new agenda, retro. On the retro pile (1)."

    assert %{kind: "todo", agenda_id: nil, project_id: ^project_id} = Jot.get(step_id)
    assert %{id: id} = Agenda.named("telegram", "retro")
    assert [%{id: note_id, text: "pack bags", project_id: nil}] = Jot.agenda_notes(id)
    assert note_id != step_id
  end

  describe "telling the pile" do
    setup %{say: say} do
      say_it("for retro: a", %{kind: "agenda", agenda: "retro", text: "deploy took three tries"}, say, 1)
      say_it("for retro: b", %{kind: "agenda", agenda: "retro", text: "flaky gate"}, say, 2)
      replied()
      replied()

      {:ok, agenda} =
        Agenda.edit(
          Agenda.named("telegram", "retro"),
          %{every: "2 week", next_at: thursday()},
          DateTime.add(thursday(), -1, :day)
        )

      %{agenda: agenda}
    end

    test "is said once, fifteen minutes before, in the chat; then the time moves on by the rhythm", %{say: say} do
      Server.Home.Agendas.tell("telegram", "42", say, DateTime.add(thursday(), -20, :minute))
      refute_received {:said, _, _}

      Server.Home.Agendas.tell("telegram", "42", say, DateTime.add(thursday(), -14, :minute))
      assert replied() == "Retro in 15 — 2 things: deploy took three tries; flaky gate"

      Server.Home.Agendas.tell("telegram", "42", say, DateTime.add(thursday(), -5, :minute))
      Server.Home.Agendas.tell("telegram", "42", say, DateTime.add(thursday(), 10, :minute))
      refute_received {:said, _, _}

      Server.Home.Agendas.tell("telegram", "42", say, DateTime.add(thursday(), 2, :hour))
      assert %{next_at: next} = Agenda.named("telegram", "retro")
      assert next == Clock.utc(~N[2026-12-03 14:00:00])
    end

    test "a message that did not go out is said at the next poll", %{agenda: agenda} do
      Server.Home.Agendas.tell("telegram", "42", fn _, _, _ -> :error end, DateTime.add(thursday(), -10, :minute))
      assert Agenda.get("telegram", agenda.id).told_at == nil
    end

    test "with no chat it is recorded as told, for the desktop", %{agenda: agenda} do
      Server.Home.Agendas.tell("telegram", "", nil, DateTime.add(thursday(), -10, :minute))
      assert %{told_for: told_for} = Agenda.get("telegram", agenda.id)
      assert told_for == thursday()
    end

    test "the desktop raises what was told, while it has notes", %{agenda: agenda} do
      Server.Home.Agendas.tell("telegram", "", nil, DateTime.add(thursday(), -10, :minute))
      since = DateTime.add(thursday(), -20, :minute)

      assert [%{id: id, body: "Retro in 15 — 2 things: deploy took three tries; flaky gate"}] =
               Server.Home.told_agendas(since)

      assert id == "#{agenda.id}:#{DateTime.to_unix(thursday())}"
      Agenda.clear(agenda, thursday())
      assert Server.Home.told_agendas(since) == []
    end

    test "a note added after a poll found the pile empty is told by the next poll, once", %{say: say} do
      retro = Agenda.named("telegram", "retro")
      Agenda.clear(retro, thursday())

      Server.Home.Agendas.tell("telegram", "42", say, DateTime.add(thursday(), -14, :minute))
      refute_received {:said, _, _}

      say_it("for retro: late one", %{kind: "agenda", agenda: "retro", text: "late one"}, say, 3)
      replied()

      Server.Home.Agendas.tell("telegram", "42", say, DateTime.add(thursday(), -5, :minute))
      assert replied() == "Retro in 15 — 1 thing: late one"
      Server.Home.Agendas.tell("telegram", "42", say, DateTime.add(thursday(), -2, :minute))
      refute_received {:said, _, _}
    end

    test "an empty pile is passed without a word, and an agenda with no rhythm is never told", %{say: say} do
      Agenda.clear(Agenda.named("telegram", "retro"), thursday())
      Server.Home.Agendas.tell("telegram", "42", say, DateTime.add(thursday(), -10, :minute))
      {:ok, _} = Agenda.create("telegram", "offsite", %{}, thursday())
      Server.Home.Agendas.tell("telegram", "42", say, DateTime.add(thursday(), 5, :day))
      refute_received {:said, _, _}
    end
  end
end
