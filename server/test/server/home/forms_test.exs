defmodule Server.Home.FormsTest do
  use ExUnit.Case, async: false

  alias Server.Home
  alias Server.Home.Clock
  alias Server.Home.Inbox
  alias Server.Jot
  alias Server.Repo

  setup do
    Server.TestDB.clean!()
    me = self()

    %{
      say: fn chat, text, opts ->
        send(me, {:said, chat, text})
        if opts != [], do: send(me, {:with, opts})
        :ok
      end
    }
  end

  defp now, do: Clock.utc(~N[2026-11-20 12:00:00])
  defp fresh(id), do: Repo.get!(Jot, id)
  defp set(jot, changes), do: jot |> Ecto.Changeset.change(changes) |> Repo.update!()

  defp add(params), do: Home.add(Map.new(params, fn {k, v} -> {to_string(k), v} end), now())
  defp edit(id, params), do: Home.edit(id, Map.new(params, fn {k, v} -> {to_string(k), v} end), now())

  defp project(steps \\ ["call", "write"]) do
    {:ok, row} = add(kind: "project", text: "plan mom's birthday", steps: steps)
    row
  end

  describe "add" do
    test "a to-do, a note and a waiting-on are filed as they are given, with no reader" do
      assert {:ok, %{kind: "todo", text: "buy milk", due_at: nil, every: nil, project: nil, told_at: nil}} =
               add(kind: "todo", text: " buy milk ")

      assert {:ok, %{kind: "note", text: "wifi is on the fridge"}} = add(kind: "note", text: "wifi is on the fridge")

      assert {:ok, %{kind: "waiting", text: "the photos", who: "Sam", due_at: due}} =
               add(kind: "waiting", text: "the photos", who: "Sam")

      assert due == DateTime.add(now(), 3 * 86_400)

      assert %{open: [%{text: "buy milk"}], notes: ["wifi is on the fridge"], waiting: [%{who: "Sam"}]} =
               Home.status(now())
    end

    test "a reminder's time is exactly the one given: local without a zone, the instant with one" do
      assert {:ok, %{kind: "reminder", due_at: local}} = add(kind: "reminder", text: "call", at: "2026-11-21T09:00")
      assert local == Clock.utc(~N[2026-11-21 09:00:00])

      assert {:ok, %{due_at: ~U[2026-11-21 09:00:00Z]}} = add(kind: "reminder", text: "z", at: "2026-11-21T09:00:00Z")

      assert {:ok, %{due_at: ~U[2026-11-21 07:00:00Z]}} =
               add(kind: "reminder", text: "o", at: "2026-11-21T09:00:00+02:00")
    end

    test "a reminder can repeat every N days, weeks or months" do
      assert {:ok, %{every: "6 week", due_at: due}} =
               add(kind: "reminder", text: "haircut", at: "2026-11-21T09:00:00Z", every: "6 week")

      assert due == ~U[2026-11-21 09:00:00Z]
      assert {:ok, %{every: "week"}} = add(kind: "reminder", text: "bins", at: "2026-11-21T09:00:00Z", every: "1 week")
    end

    test "a bad body is a one-line reason" do
      assert {:error, "kind is todo, reminder, note, waiting or project"} = add(kind: "idea", text: "x")
      assert {:error, "text is required"} = add(kind: "todo", text: "  ")
      assert {:error, "a reminder needs at"} = add(kind: "reminder", text: "x")

      assert {:error, "at is ISO 8601: 2026-11-21T09:00 (local) or with a zone" <> _} =
               add(kind: "reminder", text: "x", at: "friday")

      assert {:error, "at is for a reminder"} = add(kind: "todo", text: "x", at: "2026-11-21T09:00")

      assert {:error, "every is day, week or month, or a number then one of them: 6 week"} =
               add(kind: "reminder", text: "x", at: "2026-11-21T09:00", every: "fortnight")

      assert {:error, "every is for a reminder"} = add(kind: "todo", text: "x", every: "week")
      assert {:error, "who is required for a waiting-on"} = add(kind: "waiting", text: "x")
      assert {:error, "steps is a list of texts, at least one"} = add(kind: "project", text: "x", steps: [])
      assert {:error, "project is for a to-do"} = add(kind: "note", text: "x", project: 1)
    end

    test "a project is filed with its first step open and the rest planned" do
      assert %{kind: "project", plan: ["write"], steps_done: [], next: %{text: "call"}} = project()
    end

    test "a to-do for a project is its step when it has none, else it joins the plan" do
      %{id: pid} = project(["call"])
      assert :not_found = add(kind: "todo", text: "x", project: 9999)

      assert {:ok, %{kind: "project", id: ^pid, plan: ["book the florist"]}} =
               add(kind: "todo", text: "book the florist", project: pid)

      assert [%{text: "call"}] = Jot.steps(pid)
      Enum.each(Jot.steps(pid), &Jot.done(&1, now()))
      Jot.ask(Jot.project("telegram", pid), "next", nil, now())

      assert {:ok, %{text: "order the cake", project: %{id: ^pid}}} =
               add(kind: "todo", text: "order the cake", project: pid)

      assert [%{text: "order the cake"}] = Jot.steps(pid)
      assert Jot.asked("telegram") == []

      assert {:ok, %{kind: "project", id: ^pid, plan: ["book the florist", "later one"]}} =
               add(kind: "todo", text: "later one", project: pid)

      assert [%{text: "order the cake"}] = Jot.steps(pid)
    end

    test "a reminder due in under a minute, or past by a few seconds, is told at the next tick", %{say: say} do
      add(kind: "reminder", text: "soon", at: DateTime.to_iso8601(DateTime.add(now(), 20)))
      add(kind: "reminder", text: "just now", at: DateTime.to_iso8601(DateTime.add(now(), -5)))

      Inbox.nudge("telegram", "42", say, DateTime.add(now(), 30))

      assert_received {:said, "42", "reminder: just now"}
      assert_received {:said, "42", "reminder: soon"}
    end
  end

  describe "edit" do
    test "a reminder moves to the exact time given, is a touch and is told afresh" do
      {:ok, %{id: id}} = add(kind: "reminder", text: "call", at: "2026-11-21T09:00:00Z")
      set(fresh(id), nudges: 3, nudged_at: now(), touched_at: DateTime.add(now(), -30, :day))

      assert {:ok, %{text: "call Sam", due_at: ~U[2026-11-22 10:30:00Z]}} =
               edit(id, text: "call Sam", at: "2026-11-22T10:30:00Z")

      assert %{nudges: 0, nudged_at: nil, touched_at: touched} = fresh(id)
      assert touched == now()
    end

    test "every is set, changed or stopped with null" do
      {:ok, %{id: id}} = add(kind: "reminder", text: "bins", at: "2026-11-21T09:00:00Z", every: "week")

      assert {:ok, %{every: "2 week"}} = edit(id, every: "2 week")
      assert {:ok, %{every: nil, due_at: ~U[2026-11-21 09:00:00Z]}} = edit(id, every: nil)
      assert %{every: nil} = fresh(id)
      assert {:error, "every is day, week or month, or a number then one of them: 6 week"} = edit(id, every: "often")
    end

    test "a reminder with no time cannot be made to repeat without one" do
      {:ok, %{id: id}} = add(kind: "todo", text: "odd")
      set(fresh(id), kind: "reminder")

      assert {:error, "a reminder needs at"} = edit(id, every: "week")
      assert {:ok, %{text: "odder"}} = edit(id, text: "odder")

      assert {:ok, %{every: "week", due_at: ~U[2026-11-21 09:00:00Z]}} =
               edit(id, every: "week", at: "2026-11-21T09:00:00Z")
    end

    test "a to-do becomes a reminder with a time, and a reminder a to-do without one" do
      {:ok, %{id: id}} = add(kind: "todo", text: "taxes")
      assert {:error, "a to-do has no time: send kind reminder with at"} = edit(id, at: "2026-11-21T09:00:00Z")
      assert {:error, "a reminder needs at"} = edit(id, kind: "reminder")

      assert {:ok, %{kind: "reminder", due_at: ~U[2026-11-21 09:00:00Z]}} =
               edit(id, kind: "reminder", at: "2026-11-21T09:00:00Z")

      assert {:error, "a to-do has no time and no repeat"} = edit(id, kind: "todo", at: "2026-11-22T09:00:00Z")
      assert {:ok, %{kind: "todo", due_at: nil, every: nil}} = edit(id, kind: "todo")
      assert {:error, "kind is only todo or reminder"} = edit(id, kind: "note")
    end

    test "a question that no longer applies is cleared, and a project keeps the one it asks" do
      {:ok, %{id: id}} = add(kind: "todo", text: "old")
      Jot.ask(fresh(id), "review", nil, now())

      assert {:ok, %{text: "newer"}} = edit(id, text: "newer")
      assert %{ask: nil} = fresh(id)

      %{id: pid} = project(["call"])
      Jot.ask(Jot.project("telegram", pid), "next", "x", now())
      assert {:ok, %{text: "party"}} = edit(pid, text: "party")
      assert %{ask: "next"} = fresh(pid)
    end

    test "a note, a waiting-on and a project take a new text; anything else is refused" do
      {:ok, %{id: note}} = add(kind: "note", text: "wifi")
      assert {:ok, %{text: "wifi: fridge"}} = edit(note, text: "wifi: fridge")
      assert {:error, "at is for a reminder"} = edit(note, at: "2026-11-21T09:00:00Z")
      assert {:error, "text is required"} = edit(note, text: " ")
      assert :not_found = edit(9999, text: "x")

      {:ok, %{id: milk}} = add(kind: "todo", text: "milk")
      Jot.done(fresh(milk), now())
      assert :not_found = edit(milk, text: "x")
    end
  end

  describe "projects for a card" do
    test "a project row carries what is planned and what is done, and the plan is replaced" do
      %{id: pid} = project(["call", "write", "book"])
      [step] = Jot.steps(pid)
      Jot.done(step, now())

      assert %{projects: [%{plan: ["write", "book"], steps_done: ["call"], kind: "project"}]} = Home.status(now())
      assert {:ok, %{plan: ["book", "send", "write"]}} = Home.plan(pid, ["book", " send ", "write"], now())
      assert %{plan: ["book", "send", "write"]} = fresh(pid)
      assert {:ok, %{plan: []}} = Home.plan(pid, [], now())
      assert {:error, "plan is a list of texts"} = Home.plan(pid, "x", now())
      assert {:error, "plan is a list of texts"} = Home.plan(pid, [1], now())
      assert :not_found = Home.plan(9999, ["x"], now())
    end

    test "open, coming and waiting rows carry what a form needs, and someday rows can be revived" do
      {:ok, %{id: wait}} = add(kind: "waiting", text: "the photos", who: "Sam")
      {:ok, %{id: soon}} = add(kind: "reminder", text: "bins", at: "2026-11-27T09:00:00Z", every: "2 week")

      assert %{
               waiting: [
                 %{
                   id: ^wait,
                   kind: "waiting",
                   text: "the photos",
                   due_at: _,
                   every: nil,
                   since: _,
                   told_at: nil,
                   project: nil
                 }
               ],
               coming: [%{id: ^soon, kind: "reminder", every: "2 week", since: _, told_at: nil, project: nil}]
             } = Home.status(now())

      Jot.someday(fresh(soon), now())

      assert %{someday: [%{id: ^soon, text: "bins", kind: "reminder", every: "2 week"}], coming: []} =
               Home.status(now())

      assert {:ok, %{id: ^soon, due_at: ~U[2026-11-27 09:00:00Z]}} = Home.revive(soon, now())
      assert %{someday: [], coming: [%{id: ^soon}]} = Home.status(now())
      assert :not_found = Home.revive(soon, now())
    end
  end
end
