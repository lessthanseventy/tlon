defmodule Server.Home.NowTest do
  use ExUnit.Case, async: true

  alias Server.Home.Now
  alias Server.Jot

  @now ~U[2026-11-20 16:00:00Z]

  defp todo(id, days_old, attrs \\ []) do
    struct(
      %Jot{id: id, kind: "todo", text: "todo #{id}", received_at: DateTime.add(@now, -days_old, :day)},
      attrs
    )
  end

  defp reminder(id, due_ago_s, attrs \\ []) do
    struct(
      %Jot{id: id, kind: "reminder", text: "reminder #{id}", received_at: @now, due_at: DateTime.add(@now, -due_ago_s)},
      attrs
    )
  end

  defp picked(things, opts \\ []) do
    assert {:ok, jot, why} = Now.pick(things, @now, opts)
    {jot.id, why}
  end

  test "nothing open is none" do
    assert Now.pick([], @now) == :none
    assert Now.pick([reminder(1, -3600)], @now) == :none
  end

  test "an overdue reminder comes before any to-do, the most overdue first, and says how late" do
    assert picked([todo(1, 20), reminder(2, 3600), reminder(3, 7200 * 3)]) == {3, "due 6 hours ago"}
    assert picked([todo(1, 20), reminder(2, 3600)]) == {2, "due an hour ago"}
    assert picked([reminder(2, 30)]) == {2, "due just now"}
    assert picked([reminder(2, 86_400 * 3)]) == {2, "due 3 days ago"}
  end

  test "to-dos go by age, and the oldest says how long it sat" do
    assert picked([todo(1, 1), todo(2, 6), todo(3, 2)]) == {2, "sat 6 days"}
    assert picked([todo(1, 1)]) == {1, "next on the list"}
  end

  test "the age counts for no more than 30 days, and ties go to the older id" do
    assert picked([todo(5, 40), todo(4, 90)]) == {4, "sat 90 days"}
  end

  test "the next step of a project is weighed ahead of a to-do a few days younger" do
    things = [todo(1, 4), todo(2, 1, project_id: 9)]
    assert picked(things, projects: %{9 => "mom's birthday"}) == {2, "next step of mom's birthday"}
    assert picked(things) == {2, "next on the list"}
  end

  test "with minutes to spend, what fits is chosen, the biggest that does, and what does not is left" do
    things = [todo(1, 5, mins: 60), todo(2, 0, mins: 2), todo(3, 0, mins: 10), todo(4, 0)]

    assert picked(things, minutes: 10) == {3, "fits 10 minutes"}
    assert picked(things, minutes: 2) == {2, "fits 2 minutes"}
    assert {1, _} = picked(things)
  end

  test "when nothing fits, the pick says it is longer than the minutes there are" do
    assert picked([todo(1, 0, mins: 60)], minutes: 10) == {1, "longer than 10 minutes, but it is what is open"}
  end

  test "a reminder is picked whatever the minutes" do
    assert {1, _} = picked([reminder(1, 60), todo(2, 0, mins: 2)], minutes: 2)
  end

  test "never someday, dropped, done, hidden until later, skipped, or a reminder still to come" do
    things = [
      todo(1, 9, someday_at: @now),
      todo(2, 9, dropped_at: @now),
      todo(3, 9, done_at: @now),
      todo(4, 9, hidden_until: DateTime.add(@now, 3600)),
      todo(5, 9),
      reminder(6, -3600),
      todo(7, 1)
    ]

    assert picked(things) == {5, "sat 9 days"}
    assert picked(things, skip: [5]) == {7, "next on the list"}
    assert Now.pick(things, @now, skip: [5, 7]) == :none
    assert {4, _} = picked([todo(4, 9, hidden_until: @now)])
  end

  test "the same things at the same moment give the same pick" do
    things = for id <- 1..6, do: todo(id, rem(id, 3), mins: Enum.at([2, 10, 30], rem(id, 3)))
    assert picked(things, minutes: 30) == picked(Enum.reverse(things), minutes: 30)
  end
end
