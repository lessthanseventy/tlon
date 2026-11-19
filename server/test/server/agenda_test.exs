defmodule Server.AgendaTest do
  use ExUnit.Case, async: false

  alias Server.Agenda
  alias Server.Home
  alias Server.Home.Clock
  alias Server.Jot

  setup do
    Server.TestDB.clean!()
    :ok
  end

  defp now, do: Clock.utc(~N[2026-11-19 12:00:00])
  defp thursday, do: Clock.utc(~N[2026-11-19 14:00:00])
  defp via, do: Application.get_env(:server, :home_messenger, Server.Home.Telegram).name()

  defp agenda(name, rhythm \\ %{}) do
    {:ok, agenda} = Agenda.create(via(), name, rhythm, now())
    agenda
  end

  defp pile(agenda, texts) do
    for text <- texts do
      {:ok, jot} = Jot.take(via(), -System.unique_integer([:positive]), text)
      Agenda.note(agenda, jot, text, now())
    end
  end

  test "names are found in any case and kept unique" do
    retro = agenda("retro")
    assert %Agenda{id: id} = Agenda.named(via(), "Retro")
    assert id == retro.id
    assert {:error, "there is already an agenda called RETRO"} = Agenda.create(via(), "RETRO", %{}, now())
    assert {:error, _} = Agenda.edit(agenda("weekly"), %{name: "retro"}, now())
  end

  test "a pile's notes are in no plain list and not in what was done" do
    retro = agenda("retro")
    [_, _] = pile(retro, ["deploy took three tries", "flaky gate"])

    via()
    |> Jot.take(1, "wifi")
    |> then(fn {:ok, jot} -> Jot.file(jot, %{kind: "note", text: "wifi", due_at: nil}, now()) end)

    assert ["wifi"] = Jot.notes(via(), 20)
    assert 2 = Agenda.clear(retro, now())
    assert %{done: [], done_week: 0, notes: ["wifi"], agendas: [%{name: "retro", notes: []}]} = Home.status(now())
  end

  test "clearing keeps the notes, done, and the agenda stands empty" do
    retro = agenda("retro")
    pile(retro, ["a", "b"])
    assert Agenda.clear(retro, now()) == 2
    assert Jot.agenda_notes(retro.id) == []
    assert ["a", "b"] = Enum.map(Jot.agenda_archived(retro.id), & &1.text)
    pile(retro, ["c"])
    assert ["c"] = Enum.map(Jot.agenda_notes(retro.id), & &1.text)
    assert ["a", "b"] = Enum.map(Jot.agenda_archived(retro.id), & &1.text)
  end

  test "a rhythm in the past starts from its next time; a month keeps its day" do
    retro = agenda("retro", %{every: "2 week", next_at: Clock.utc(~N[2026-11-05 14:00:00])})
    assert retro.next_at == Clock.utc(~N[2026-11-19 14:00:00])

    monthly = agenda("monthly", %{every: "month", next_at: Clock.utc(~N[2026-01-31 10:00:00])})
    assert monthly.every_day == 31
    assert monthly.next_at == Clock.utc(~N[2026-11-30 10:00:00])
  end

  test "an agenda is due once, in the lead before its time, and moves on an hour after it" do
    retro = agenda("retro", %{every: "2 week", next_at: thursday()})
    assert Agenda.due(via(), DateTime.add(thursday(), -16, :minute)) == []
    assert [%{id: id}] = Agenda.due(via(), DateTime.add(thursday(), -15, :minute))
    assert id == retro.id

    told = Agenda.told(retro, DateTime.add(thursday(), -14, :minute))
    assert Agenda.due(via(), DateTime.add(thursday(), -10, :minute)) == []
    assert [_] = Agenda.told_since(via(), DateTime.add(thursday(), -1, :hour))
    assert told.told_for == thursday()

    Agenda.advance(via(), DateTime.add(thursday(), 30, :minute))
    assert Agenda.get(via(), retro.id).next_at == thursday()
    Agenda.advance(via(), DateTime.add(thursday(), 61, :minute))
    next = Agenda.get(via(), retro.id).next_at
    assert next == Clock.utc(~N[2026-12-03 14:00:00])
    assert [] = Agenda.due(via(), DateTime.add(thursday(), 90, :minute))
    assert [_] = Agenda.due(via(), DateTime.add(next, -10, :minute))
  end

  test "an agenda with no rhythm is never due and a one-off time is told then forgotten" do
    agenda("offsite")
    once = agenda("one-off", %{next_at: thursday()})
    assert [%{id: id}] = Agenda.due(via(), DateTime.add(thursday(), -5, :minute))
    assert id == once.id
    Agenda.advance(via(), DateTime.add(thursday(), 2, :hour))
    assert %{next_at: nil} = Agenda.get(via(), once.id)
  end

  test "the words" do
    retro = agenda("retro", %{every: "2 week", next_at: thursday()})
    notes = pile(retro, ["deploy took three tries", "flaky gate"])
    assert Agenda.say_told(retro, notes) == "Retro in 15 — 2 things: deploy took three tries; flaky gate"
    assert Agenda.say_pile(retro, 2) == "On the retro pile (2)."
    assert Agenda.say_list(retro, notes) == "On the retro pile (2):\n• deploy took three tries\n• flaky gate"
    assert Agenda.say_list(retro, []) == "Nothing on the retro pile."
    assert Agenda.say_rhythm(retro) =~ "retro is every 2 weeks, next Thu 19 Nov 14:00."
    assert Agenda.say_rhythm(agenda("offsite")) == "offsite has no rhythm: bring it up when you want."
  end

  test "deleting an agenda deletes its pile" do
    retro = agenda("retro")
    [note] = pile(retro, ["a"])
    :ok = Agenda.delete(retro, now())
    assert Agenda.get(via(), retro.id) == nil
    assert %{dropped_at: %DateTime{}} = Jot.get(note.id)
  end
end
