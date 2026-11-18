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

  describe "the day a monthly repeat keeps" do
    defp local(text), do: text |> NaiveDateTime.from_iso8601!() |> Clock.utc()

    test "only a monthly repeat has one, and it is the day of its current time when the repeat becomes monthly" do
      {:ok, %{id: id}} = add(kind: "reminder", text: "rent", at: "2026-11-03T09:00", every: "week")
      assert %{every_day: nil} = fresh(id)

      Jot.roll(fresh(id), local("2026-11-24 09:00:00"))
      assert {:ok, %{every: "month"}} = edit(id, every: "month")
      assert %{every_day: 24} = fresh(id)

      done = Jot.done(fresh(id), now())
      assert done.due_at == local("2026-12-24 09:00:00")

      assert {:ok, %{every: "2 week"}} = edit(id, every: "2 week")
      assert %{every_day: nil} = fresh(id)
    end

    test "moving a monthly reminder's time moves its day; the same time resent or a text edit does not" do
      {:ok, %{id: id}} = add(kind: "reminder", text: "rent", at: "2026-11-03T09:00", every: "month")
      assert %{every_day: 3} = fresh(id)

      assert {:ok, _} = edit(id, text: "rent!", every: "month")
      assert %{every_day: 3} = fresh(id)
      assert {:ok, _} = edit(id, at: "2026-11-30T09:00")
      assert %{every_day: 30} = fresh(id)
    end

    test "putting a monthly repeat off moves this time only: the next one is back on its day" do
      {:ok, %{id: id}} = add(kind: "reminder", text: "rent", at: "2026-11-03T09:00", every: "month")

      Inbox.later(fresh(id), "tomorrow", now())
      assert %{every_day: 3} = fresh(id)

      done = Jot.done(fresh(id), DateTime.add(now(), 86_400))
      assert done.due_at == local("2026-12-03 09:00:00")
    end
  end

  describe "what an edit does to a put-off thing" do
    test "one that sets a time or a repeat brings it back, one that only changes the text leaves it put off" do
      {:ok, %{id: id}} = add(kind: "reminder", text: "call", at: "2026-11-25T09:00:00Z")
      Jot.someday(fresh(id), now())

      assert {:ok, %{text: "call Sam"}} = edit(id, text: "call Sam")
      assert %{someday_at: %DateTime{}} = fresh(id)

      assert {:ok, %{due_at: ~U[2026-11-26 09:00:00Z]}} = edit(id, at: "2026-11-26T09:00:00Z")
      assert %{someday_at: nil} = fresh(id)
      assert %{coming: [%{id: ^id}], someday: []} = Home.status(now())

      Jot.someday(fresh(id), now())
      assert {:ok, %{every: "week"}} = edit(id, every: "week")
      assert %{someday_at: nil} = fresh(id)

      {:ok, %{id: todo}} = add(kind: "todo", text: "taxes")
      Jot.someday(fresh(todo), now())
      assert {:ok, %{kind: "reminder"}} = edit(todo, kind: "reminder", at: "2026-11-26T09:00:00Z")
      assert %{someday_at: nil} = fresh(todo)
    end
  end

  describe "at" do
    defp expected_at(%NaiveDateTime{} = local), do: Clock.utc(local)
    defp expected_at(%DateTime{} = utc), do: utc

    @accepted [
      {"2026-11-21T09:00", ~N[2026-11-21 09:00:00]},
      {"2026-11-21T09:00:30", ~N[2026-11-21 09:00:30]},
      {"2026-11-21T09:00Z", ~U[2026-11-21 09:00:00Z]},
      {"2026-11-21T09:00:00Z", ~U[2026-11-21 09:00:00Z]},
      {"2026-11-21T09:00+02:00", ~U[2026-11-21 07:00:00Z]},
      {"2026-11-21T09:00:00+02:00", ~U[2026-11-21 07:00:00Z]},
      {"2026-11-21T09:00:00.500Z", ~U[2026-11-21 09:00:00Z]}
    ]

    for {text, expected} <- @accepted do
      test "#{text} is accepted" do
        expected = expected_at(unquote(Macro.escape(expected)))

        assert {:ok, %{due_at: ^expected}} = add(kind: "reminder", text: "x", at: unquote(text))
      end
    end

    for text <- ["friday", "2026-11-21", "09:00", "2026-11-21T25:00", "2026-11-21T09:00:00+2", ""] do
      test "#{inspect(text)} is refused with the one reason" do
        assert {:error, "at is ISO 8601: " <> _} = add(kind: "reminder", text: "x", at: unquote(text))
      end
    end
  end

  describe "rows that are odd do not crash the routes" do
    test "reviving a reminder with no time, repeating or not, brings it back as a to-do" do
      for every <- ["week", nil] do
        {:ok, %{id: id}} = add(kind: "todo", text: "odd #{every}")
        set(fresh(id), kind: "reminder", every: every, due_at: nil)
        Jot.someday(fresh(id), now())

        assert {:ok, %{kind: "todo", due_at: nil, every: nil}} = Home.revive(id, now())
        assert %{someday_at: nil} = fresh(id)
      end
    end

    test "a repeating reminder with no time can be listed, edited and made monthly" do
      {:ok, %{id: id}} = add(kind: "todo", text: "odd")
      set(fresh(id), kind: "reminder", every: "week", due_at: nil)

      assert %{open: rows} = Home.status(now())
      assert Enum.any?(rows, &(&1.id == id))
      assert {:ok, %{text: "odd!"}} = edit(id, text: "odd!")
      assert {:error, "a reminder needs at"} = edit(id, every: "month")
      assert {:ok, %{every: "month"}} = edit(id, every: "month", at: "2026-11-25T09:00")
      assert %{every_day: 25} = fresh(id)
    end

    test "done on a repeating reminder with no time closes it, and a project with no steps can be planned and shown" do
      {:ok, %{id: id}} = add(kind: "todo", text: "odd")
      set(fresh(id), kind: "reminder", every: "week", due_at: nil)
      assert {:ok, %{text: "odd"}} = Home.done(id, now())
      assert %{done_at: %DateTime{}} = fresh(id)

      {:ok, plan} = Jot.take("telegram", 900, "p")
      project = Jot.file(plan, %{kind: "project", text: "bare", due_at: nil})
      assert {:ok, %{kind: "project", plan: ["x"], next: nil}} = Home.plan(project.id, ["x"], now())
      assert {:ok, %{text: "bare!"}} = edit(project.id, text: "bare!")
      assert {:ok, %{kind: "todo", project: %{id: pid}}} = add(kind: "todo", text: "first", project: project.id)
      assert pid == project.id
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
