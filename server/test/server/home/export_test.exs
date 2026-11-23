defmodule Server.Home.ExportTest do
  use ExUnit.Case, async: false

  alias Server.Agenda
  alias Server.Home.Clock
  alias Server.Home.Export
  alias Server.Jot
  alias Server.Repo

  setup do
    Server.TestDB.clean!()
    :ok
  end

  defp jot(id, kind, text, changes \\ []) do
    {:ok, jot} = Jot.take("telegram", id, text)

    jot
    |> Jot.file(%{kind: kind, text: text, due_at: nil})
    |> Ecto.Changeset.change(changes)
    |> Repo.update!()
  end

  test "every jot of the home, in every state, and every pile, in the list's shape" do
    now = Clock.utc(~N[2026-11-20 17:35:00])
    jot(1, "todo", "open one")
    jot(2, "todo", "finished", done_at: now)
    jot(3, "note", "gone", dropped_at: now)
    jot(4, "todo", "later", someday_at: now)
    jot(5, "reminder", "water", due_at: now, every: "week", every_day: 20)
    {:ok, _} = Jot.take("telegram", 6, "just chat")
    {:ok, sam} = Agenda.create("telegram", "Sam", %{kind: "person", birthday: "03-15"}, now)
    {:ok, _retro} = Agenda.create("telegram", "retro", %{}, now)
    Agenda.ensure_door("telegram", now)

    export = Export.build("telegram")

    assert Enum.map(export.things, &{&1.text, &1.state}) ==
             [{"open one", "open"}, {"finished", "done"}, {"gone", "dropped"}, {"later", "someday"}, {"water", "open"}]

    water = List.last(export.things)
    assert %{kind: "reminder", every: "week", every_day: 20, due_at: due} = water
    assert due == DateTime.to_iso8601(now)

    assert export.agendas |> Enum.find(&(&1.id == sam.id)) |> Map.take([:kind, :name, :birthday]) ==
             %{kind: "person", name: "Sam", birthday: "03-15"}

    assert export.counts == %{
             "todo" => 3,
             "note" => 1,
             "reminder" => 1,
             "person" => 1,
             "agenda" => 1,
             "door" => 1,
             "proposals" => 0
           }

    assert export.settings == %{telegram_list_at: "17:30", telegram_morning_at: "08:30", telegram_chat: ""}
  end
end
