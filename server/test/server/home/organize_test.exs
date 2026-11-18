defmodule Server.Home.OrganizeTest do
  use ExUnit.Case, async: false

  alias Server.Alerts
  alias Server.Home
  alias Server.Home.Clock
  alias Server.Home.Inbox
  alias Server.Home.Organize
  alias Server.Jot
  alias Server.Repo

  setup do
    Server.TestDB.clean!()
    reads(fn _body, _context -> :error end)
    helps(fn prompt -> flunk("the model was asked: #{prompt}") end)

    on_exit(fn ->
      Application.delete_env(:server, :home_reader)
      Application.delete_env(:server, :home_helper)
    end)

    me = self()

    %{
      say: fn chat, text, opts ->
        send(me, {:said, chat, text})
        if opts != [], do: send(me, {:with, opts})
        :ok
      end
    }
  end

  defp reads(reader), do: Application.put_env(:server, :home_reader, reader)
  defp helps(helper), do: Application.put_env(:server, :home_helper, helper)

  defp friday, do: Clock.utc(~N[2026-11-20 17:35:00])

  defp set(jot, changes), do: Jot |> Repo.get!(jot.id) |> Ecto.Changeset.change(changes) |> Repo.update!()
  defp fresh(jot), do: Repo.get!(Jot, jot.id)

  defp todo(id, text, attrs \\ []) do
    {:ok, jot} = Jot.take("telegram", id, text)
    jot |> Jot.file(%{kind: "todo", text: text, due_at: nil}) |> set(attrs)
  end

  defp project_reading(steps),
    do:
      {:ok,
       %{kind: "project", text: "plan mom's birthday", due_at: nil, every: nil, ids: [], amends: false, steps: steps}}

  defp hear(say, id, text) do
    Inbox.hear([%{id: id, chat: "42", text: text}], "telegram", "42", say)
  end

  defp press(data, ref \\ 90), do: %{id: 20, chat: "42", text: nil, tap: data, tap_id: "q", ref: ref}

  defp tapped(say, data), do: Inbox.hear([press(data)], "telegram", "42", say)

  describe "projects" do
    test "an outcome is filed as a project with its first step open and the rest planned", %{say: say} do
      reads(fn "plan mom's birthday", _context -> project_reading(["book a table", "ask dad", "order a cake"]) end)

      hear(say, 1, "plan mom's birthday")

      assert_received {:said, "42",
                       "project: plan mom's birthday\nfirst step: book a table\nthen: ask dad, order a cake"}

      assert [%{id: id, plan: ["ask dad", "order a cake"], kind: "project"}] = Jot.projects("telegram")
      assert [%{text: "book a table", project_id: ^id, kind: "todo"}] = Jot.steps(id)

      status = Home.status(DateTime.utc_now())
      assert [%{id: ^id, text: "plan mom's birthday", next: %{text: "book a table"}, done: 0}] = status.projects
      assert [%{text: "book a table", project: %{id: ^id, text: "plan mom's birthday"}}] = status.open
    end

    test "a step done proposes the next planned one with no model call, one at a time, then the model's", %{say: say} do
      reads(fn _body, _context -> project_reading(["book a table", "ask dad", "order a cake"]) end)
      hear(say, 1, "plan mom's birthday")
      assert_received {:said, "42", "project:" <> _}
      [%{id: pid}] = Jot.projects("telegram")
      [first] = Jot.steps(pid)

      tapped(say, "done:#{first.id}")

      assert_received {:said, "42", "done: book a table\n\nNext for plan mom's birthday: ask dad?"}
      assert_received {:with, replace: 90, choices: [[{"Add it", add}, {"Project's finished", finish}]]}
      assert add == "a:#{pid}:add" and finish == "a:#{pid}:finish"
      assert Jot.steps(pid) == []

      tapped(say, add)
      assert_received {:said, "42", "added: ask dad"}
      [second] = Jot.steps(pid)
      assert second.text == "ask dad"

      tapped(say, "done:#{second.id}")
      assert_received {:said, "42", "done: ask dad\n\nNext for plan mom's birthday: order a cake?"}
      tapped(say, add)
      [third] = Jot.steps(pid)

      me = self()

      helps(fn prompt ->
        send(me, {:helped, prompt})
        {:ok, "- Pick up the cake\n"}
      end)

      tapped(say, "done:#{third.id}")

      assert_received {:helped, prompt}
      assert prompt =~ "PROJECT: plan mom's birthday"
      assert prompt =~ "- book a table\n- ask dad\n- order a cake"
      assert_received {:said, "42", "done: order a cake\n\nNext for plan mom's birthday: Pick up the cake?"}

      tapped(say, finish)

      assert_received {:said, "42", "done: plan mom's birthday. That's the project finished."}
      assert %{projects: [], open: [], done_week: 4} = Home.status(DateTime.utc_now())
      assert Home.asked() == []
    end

    test "with no next step to propose, the question is asked bare and a typed reply is the step", %{say: say} do
      reads(fn _body, _context -> project_reading(["call the florist"]) end)
      hear(say, 1, "plan mom's birthday")
      [%{id: pid}] = Jot.projects("telegram")
      [step] = Jot.steps(pid)
      helps(fn _prompt -> {:error, :down} end)

      ExUnit.CaptureLog.capture_log(fn -> tapped(say, "done:#{step.id}") end)

      assert_received {:said, "42", "project:" <> _}
      assert_received {:said, "42", "done: call the florist\n\nWhat's the next step for plan mom's birthday?"}
      assert_received {:with, replace: 90, choices: [[{"Project's finished", _}]]}

      reads(fn "ask dad about venues", %{projects: [%Jot{id: ^pid, ask: "next"}]} ->
        {:ok, %{kind: "todo", text: "ask dad about venues", due_at: nil, project: pid}}
      end)

      hear(say, 2, "ask dad about venues")

      assert_received {:said, "42", "next step of plan mom's birthday: ask dad about venues"}
      assert [%{text: "ask dad about venues", project_id: ^pid}] = Jot.steps(pid)
      assert Home.asked() == []
    end

    test "a to-do naming a project that is not waiting on a step is a to-do of its own", %{say: say} do
      reads(fn _body, _context -> project_reading(["call"]) end)
      hear(say, 1, "plan mom's birthday")
      [%{id: pid}] = Jot.projects("telegram")

      reads(fn _body, _context -> {:ok, %{kind: "todo", text: "buy milk", due_at: nil, project: pid}} end)
      hear(say, 2, "buy milk")

      assert_received {:said, "42", "to do: buy milk"}
      assert [%{text: "call"}] = Jot.steps(pid)
    end

    test "the daily list names a step under its project", %{say: say} do
      reads(fn _body, _context -> project_reading(["call"]) end)
      hear(say, 1, "plan mom's birthday")
      todo(2, "buy milk")

      assert {"Still open:\n• plan mom's birthday: call\n• buy milk", _} = Inbox.digest("telegram", DateTime.utc_now())
      assert %{body: "Still open: plan mom's birthday: call · buy milk"} = listing()
    end

    test "a step done from the desktop proposes the next one there", %{say: say} do
      reads(fn _body, _context -> project_reading(["call", "write"]) end)
      hear(say, 1, "plan mom's birthday")
      [%{id: pid}] = Jot.projects("telegram")
      [step] = Jot.steps(pid)

      assert {:ok, _} = Home.done(step.id, DateTime.utc_now())

      assert [%{id: ^pid, text: "Next for plan mom's birthday: write?", choices: [{"Add it", "add"}, _], typed: "step"}] =
               Home.asked()

      assert {:ok, "added: write"} = Home.answer(pid, "add", nil, DateTime.utc_now())
      assert :error = Home.answer(pid, "add", nil, DateTime.utc_now())
      [step] = Jot.steps(pid)

      helps(fn _prompt -> {:ok, "DONE"} end)
      Home.done(step.id, DateTime.utc_now())

      assert [%{text: "What's the next step for plan mom's birthday?"}] = Home.asked()
      assert :error = Home.answer(pid, "step", "  ", DateTime.utc_now())
      assert {:ok, "added: send it"} = Home.answer(pid, "step", " send it ", DateTime.utc_now())
    end

    test "a project reading files a project, and a message that cannot be read is still kept", %{say: say} do
      reads(fn _body, _context -> {:ok, %{kind: "project", text: "x", due_at: nil, steps: ["a"]}} end)
      hear(say, 1, "x")
      assert_received {:said, "42", "project: x\nfirst step: a"}

      reads(fn _body, _context -> :error end)
      hear(say, 2, "something")
      assert_received {:said, "42", "got it"}
      assert [%{kind: nil}, %{kind: "project"}, %{kind: "todo"}] = Jot.recent("telegram", 10)
    end
  end

  defp listing do
    Home.listing(Clock.utc(NaiveDateTime.new!(Date.utc_today(), ~T[17:35:00])))
  end

  describe "vague things" do
    test "what the reader assumed and the one question it has are said, and the reply to it amends the jot", %{say: say} do
      reads(fn "dentist next week", _context ->
        {:ok,
         %{
           kind: "reminder",
           text: "call the dentist",
           due_at: ~U[2026-11-27 09:00:00Z],
           assumed: "it's Dr Lee",
           ask: "Which day?"
         }}
      end)

      hear(say, 1, "dentist next week")

      assert_received {:said, "42", text}
      assert text =~ "I'll remind you"
      assert text =~ "\nI took it that it's Dr Lee.\nWhich day?"
      assert [%{kind: "reminder", text: "call the dentist"}] = Jot.recent("telegram", 10)

      reads(fn "tuesday", %{previous: %Jot{external_id: 1}} ->
        {:ok, %{kind: "reminder", text: "call the dentist", due_at: ~U[2026-11-24 09:00:00Z], amends: true}}
      end)

      hear(say, 2, "tuesday")

      assert_received {:said, "42", "changed: I'll remind you " <> _}
      assert [%{kind: "amend"}, %{kind: "reminder", due_at: ~U[2026-11-24 09:00:00Z]}] = Jot.recent("telegram", 10)
    end

    test "the reader is shown the open projects and what is put off", %{say: say} do
      reads(fn _body, _context -> project_reading(["call"]) end)
      hear(say, 1, "plan mom's birthday")
      later = todo(2, "paint the fence", someday_at: friday())
      me = self()

      reads(fn _body, context ->
        send(me, {:context, context})
        :error
      end)

      hear(say, 3, "hello")

      assert_received {:context, %{projects: [%Jot{text: "plan mom's birthday"}], someday: [%Jot{id: id}]}}
      assert id == later.id
    end
  end

  describe "someday" do
    test "put off things are out of the open list and the daily list, listed when asked, and any mention revives one",
         %{
           say: say
         } do
      fence = todo(1, "paint the fence")
      todo(2, "buy milk")
      Jot.someday(fence, friday())

      assert {"Still open:\n• buy milk", _} = Inbox.digest("telegram", DateTime.utc_now())
      assert %{open: [%{text: "buy milk"}]} = Home.status(DateTime.utc_now())

      reads(fn "what's on someday", _context -> {:ok, %{kind: "someday", text: "", due_at: nil, ids: []}} end)
      hear(say, 3, "what's on someday")
      assert_received {:said, "42", "On someday:\n• paint the fence"}

      reads(fn "do the fence tomorrow", %{someday: [%Jot{id: id}]} ->
        {:ok, %{kind: "todo", text: "paint the fence", due_at: nil, revive: [id]}}
      end)

      hear(say, 4, "do the fence tomorrow")

      assert_received {:said, "42", "to do: paint the fence\nback on the list: paint the fence"}
      assert Jot.somedays("telegram") == []
      assert [_, _, _] = Jot.opens("telegram")
    end

    test "nothing on someday is said so", %{say: say} do
      reads(fn _body, _context -> {:ok, %{kind: "someday", text: "", due_at: nil, ids: []}} end)
      hear(say, 1, "someday?")
      assert_received {:said, "42", "Nothing on someday."}
    end
  end

  describe "the weekly review" do
    defp stale(id, text, days), do: todo(id, text, touched_at: DateTime.add(friday(), -days, :day))

    defp review(say, reviewed \\ ~D[2026-11-13]),
      do: Organize.weekly("telegram", "42", say, friday(), "fri", "17:30", reviewed)

    test "up to five open things untouched for 14 days are offered, oldest touch first, each with Keep, Later and Drop",
         %{say: say} do
      for n <- 1..7, do: stale(n, "old #{n}", 14 + n)
      stale(8, "fresh", 13)
      todo(9, "brand new")

      assert review(say) == ~D[2026-11-20]

      for n <- 7..3//-1 do
        said = "Still want this? old #{n}"
        assert_received {:said, "42", ^said}
      end

      refute_received {:said, _, "Still want this? old 2"}
      refute_received {:said, _, "Still want this? fresh"}
      assert_received {:with, choices: [[{"Keep", "a:" <> _}, {"Later", _}, {"Drop", _}]]}
      assert length(Enum.filter(Jot.asked("telegram"), &(&1.ask == "review"))) == 5

      assert review(say, ~D[2026-11-20]) == ~D[2026-11-20]
      refute_received {:said, _, _}
    end

    test "Keep resets its staleness, Later puts it on someday, Drop closes it and is not counted as done", %{say: say} do
      keep = stale(1, "keep me", 15)
      later = stale(2, "later me", 16)
      drop = stale(3, "drop me", 17)
      review(say)

      tapped(say, "a:#{keep.id}:keep")
      assert_received {:said, "42", "kept: keep me"}
      assert DateTime.diff(DateTime.utc_now(), Jot.touched(fresh(keep))) < 5
      assert fresh(keep).ask == nil

      tapped(say, "a:#{later.id}:later")
      assert_received {:said, "42", "moved to someday: later me"}
      assert [%{text: "later me"}] = Jot.somedays("telegram")

      tapped(say, "a:#{drop.id}:drop")
      assert_received {:said, "42", "dropped: drop me"}
      assert %DateTime{} = fresh(drop).dropped_at

      assert [%{text: "keep me"}] = Jot.opens("telegram")
      assert %{done_week: 0} = Home.status(DateTime.utc_now())

      tapped(say, "a:#{drop.id}:drop")
      assert_received {:said, "42", "That one is already answered."}
    end

    test "anything untouched for 28 days is moved to someday by itself, said in one line", %{say: say} do
      stale(1, "ancient", 28)
      stale(2, "also ancient", 40)
      stale(3, "old", 15)

      review(say)

      assert_received {:said, "42", "moved to someday: ancient, also ancient"}
      assert Enum.map(Jot.somedays("telegram"), & &1.text) == ["ancient", "also ancient"]
      assert_received {:said, "42", "Still want this? old"}
      refute_received {:said, _, _}
    end

    test "a step that drifts away leaves its project asking for the next one", %{say: say} do
      reads(fn _body, _context -> project_reading(["call"]) end)
      hear(say, 1, "plan mom's birthday")
      assert_received {:said, "42", "project:" <> _}
      [%{id: pid}] = Jot.projects("telegram")
      [step] = Jot.steps(pid)
      set(step, touched_at: DateTime.add(friday(), -30, :day))
      helps(fn _prompt -> {:ok, "Call the venue"} end)

      review(say)

      assert_received {:said, "42", "moved to someday: call"}
      assert_received {:said, "42", "Next for plan mom's birthday: Call the venue?"}
    end

    test "it runs once on its weekday after its time, never on another day, and not on the day the inbox starts late",
         %{say: say} do
      stale(1, "old", 15)
      at = fn date, time -> Clock.utc(NaiveDateTime.new!(date, time)) end
      week = fn now, on, reviewed -> Organize.weekly("telegram", "42", say, now, on, "17:30", reviewed) end

      assert week.(at.(~D[2026-11-20], ~T[17:29:00]), "fri", ~D[2026-11-13]) == ~D[2026-11-13]
      assert week.(at.(~D[2026-11-21], ~T[17:35:00]), "fri", ~D[2026-11-13]) == ~D[2026-11-13]
      assert week.(at.(~D[2026-11-20], ~T[17:35:00]), "", ~D[2026-11-13]) == ~D[2026-11-13]
      refute_received {:said, _, _}

      assert week.(at.(~D[2026-11-20], ~T[17:35:00]), "fri", :boot) == ~D[2026-11-20]
      assert week.(at.(~D[2026-11-20], ~T[17:20:00]), "fri", :boot) == ~D[2026-11-19]
      refute_received {:said, _, _}

      assert week.(at.(~D[2026-11-20], ~T[17:35:00]), "fri", ~D[2026-11-13]) == ~D[2026-11-20]
      assert_received {:said, "42", "Still want this? old"}
    end

    test "with no messenger the questions are put all the same, and the desktop raises them" do
      stale(1, "old", 15)
      assert Organize.weekly("telegram", "", nil, friday(), "fri", "17:30", ~D[2026-11-13]) == ~D[2026-11-20]
      refute_received {:said, _, _}

      assert [%{text: "Still want this? old", choices: [{"Keep", "keep"}, {"Later", "later"}, {"Drop", "drop"}]}] =
               Home.asked()

      assert {:ok, "kept: old"} = Home.answer(hd(Home.asked()).id, "keep", nil, DateTime.utc_now())
      assert Home.asked() == []
    end
  end

  describe "waiting on" do
    defp waiting(say, due) do
      reads(fn "waiting on Sam for the photos", _context ->
        {:ok, %{kind: "waiting", text: "the photos", due_at: nil, who: "Sam"}}
      end)

      hear(say, 1, "waiting on Sam for the photos")
      assert_received {:said, "42", "waiting on Sam for the photos. I'll ask in 3 days."}
      [jot] = Jot.waiting("telegram")
      set(jot, due_at: DateTime.truncate(due, :second))
    end

    test "it is filed, three days out, and shows under waiting and not under open", %{say: say} do
      before = DateTime.utc_now()
      waiting(say, before)
      [jot] = Jot.waiting("telegram")
      assert jot.waiting_on == "Sam"

      assert %{
               open: [],
               waiting: [%{id: id, text: "the photos", who: "Sam", since: %DateTime{}, due_at: %DateTime{}}]
             } = Home.status(DateTime.utc_now())

      assert id == jot.id
    end

    test "the filing sets its three days from now", %{say: say} do
      waiting(say, DateTime.utc_now())
      reads(fn _body, _context -> {:ok, %{kind: "waiting", text: "x", due_at: nil, who: "Al"}} end)
      hear(say, 2, "waiting on Al for x")
      [_, al] = Jot.waiting("telegram")
      assert_in_delta DateTime.diff(al.due_at, DateTime.utc_now()), 3 * 86_400, 5
    end

    test "after three days it is asked about, once, in waking hours, with Got it, Chased and Tomorrow", %{say: say} do
      due = Clock.utc(~N[2026-11-23 09:00:00])
      waiting(say, due)
      [jot] = Jot.waiting("telegram")

      Organize.waiting("telegram", "42", say, DateTime.add(due, -60))
      refute_received {:said, _, _}

      Organize.waiting("telegram", "42", say, Clock.utc(~N[2026-11-23 07:00:00]))
      refute_received {:said, _, _}

      now = Clock.utc(~N[2026-11-23 09:30:00])
      Organize.waiting("telegram", "42", say, now)

      assert_received {:said, "42", "Still waiting on Sam for the photos?"}
      assert_received {:with, choices: [[{"Got it", got}, {"Chased", chased}, {"Tomorrow", tomorrow}]]}
      assert {got, chased, tomorrow} == {"a:#{jot.id}:got", "a:#{jot.id}:chased", "a:#{jot.id}:tomorrow"}

      Organize.waiting("telegram", "42", say, DateTime.add(now, 3600))
      refute_received {:said, _, _}

      tapped(say, chased)
      assert_received {:said, "42", "I'll ask again in 3 days."}
      assert %{ask: nil, due_at: again} = fresh(jot)
      assert DateTime.diff(again, DateTime.utc_now(), :day) in 2..3

      set(jot, due_at: now)
      Organize.waiting("telegram", "42", say, DateTime.add(now, 60))
      assert_received {:said, "42", "Still waiting on Sam for the photos?"}

      tapped(say, tomorrow)
      assert_received {:said, "42", "I'll ask again tomorrow."}
      assert %{ask: nil, done_at: nil} = fresh(jot)

      set(jot, due_at: now)
      Organize.waiting("telegram", "42", say, DateTime.add(now, 120))
      tapped(say, got)

      assert_received {:said, "42", "got it: the photos from Sam"}
      assert Jot.waiting("telegram") == []
      assert %{done_week: 1} = Home.status(DateTime.utc_now())
    end

    test "it waits for the morning when it falls due at night", %{say: say} do
      waiting(say, Clock.utc(~N[2026-11-23 22:30:00]))

      Organize.waiting("telegram", "42", say, Clock.utc(~N[2026-11-23 23:00:00]))
      refute_received {:said, _, _}

      Organize.waiting("telegram", "42", say, Clock.utc(~N[2026-11-24 08:00:00]))
      assert_received {:said, "42", "Still waiting on Sam for the photos?"}
    end
  end

  describe "shrinking a to-do that has sat" do
    defp sat_todo, do: todo(1, "do the taxes", received_at: DateTime.add(friday(), -8, :day))

    defp daily(say, now \\ friday(), listed \\ ~D[2026-11-19]),
      do: Inbox.daily("telegram", "42", say, now, "17:30", listed)

    test "it is offered with the daily list, once, and Add that turns it into a project with that start", %{say: say} do
      taxes = sat_todo()
      me = self()

      helps(fn prompt ->
        send(me, {:helped, prompt})
        {:ok, "\"Find last year's return\""}
      end)

      assert daily(say) == ~D[2026-11-20]

      assert_received {:helped, prompt}
      assert prompt =~ "TO DO: do the taxes"

      assert_received {:said, "42", text}

      assert text ==
               "Before you clock out:\n\nStill open:\n• do the taxes\n\n'do the taxes' has sat a week. A two-minute start: Find last year's return?"

      assert_received {:with, choices: [[{"✓ do the taxes", _}], [{"Add that", add}, {"No thanks", _}]]}
      assert add == "a:#{taxes.id}:add"

      daily(say, DateTime.add(friday(), 1, :day), ~D[2026-11-20])
      assert_received {:said, "42", "Before you clock out:\n\nStill open:\n• do the taxes"}
      refute_received {:helped, _}

      tapped(say, add)

      assert_received {:said, "42", "do the taxes is a project now. First step: Find last year's return"}
      assert [%{id: id, kind: "project", text: "do the taxes"}] = Jot.projects("telegram")
      assert [%{text: "Find last year's return", mins: 2, project_id: ^id}] = Jot.steps(id)
    end

    test "No thanks leaves it a to-do, never offered again", %{say: say} do
      taxes = sat_todo()
      helps(fn _prompt -> {:ok, "Find the return"} end)
      daily(say)
      assert_received {:said, "42", "Before you clock out:" <> _}

      tapped(say, "a:#{taxes.id}:no")

      assert_received {:said, "42", "ok, leaving it."}
      assert %{kind: "todo", ask: nil, shrunk_at: %DateTime{}} = fresh(taxes)
      helps(fn prompt -> flunk("asked again: #{prompt}") end)
      daily(say, DateTime.add(friday(), 1, :day), ~D[2026-11-20])
    end

    test "a to-do that has sat less than a week, a project's step and a model with no start get no offer", %{say: say} do
      todo(11, "new", received_at: DateTime.add(friday(), -6, :day))
      todo(12, "stepped", received_at: DateTime.add(friday(), -9, :day), project_id: 99)
      daily(say)
      assert_received {:said, "42", "Before you clock out:\n\nStill open:\n• new\n• stepped"}

      sat_todo()
      helps(fn _prompt -> {:ok, "DONE"} end)
      daily(say, DateTime.add(friday(), 1, :day), ~D[2026-11-20])
      assert_received {:said, "42", text}
      refute text =~ "two-minute"
      assert Jot.asked("telegram") == []
    end

    test "with no messenger the offer is put all the same, for the desktop" do
      sat_todo()
      helps(fn _prompt -> {:ok, "Find the return"} end)

      assert Inbox.daily("telegram", "", nil, friday(), "17:30", ~D[2026-11-19]) == ~D[2026-11-20]

      refute_received {:said, _, _}

      assert [%{text: "'do the taxes' has sat a week. A two-minute start: Find the return?", choices: [add, _]}] =
               Home.asked()

      assert add == {"Add that", "add"}
    end
  end

  describe "what now" do
    test "one open thing is answered with Done, Something else and Not today, and each does its part", %{say: say} do
      taxes = todo(1, "do the taxes", mins: 60)
      reply = todo(2, "reply to Sam", mins: 2)

      reads(fn "I have ten minutes", _context ->
        {:ok, %{kind: "now", text: "", due_at: nil, ids: [], amends: false, minutes: 10}}
      end)

      hear(say, 3, "I have ten minutes")

      assert_received {:said, "42", "reply to Sam — fits 10 minutes"}

      assert_received {:with, choices: [[{"Done", done}, {"Something else", other}, {"Not today", nottoday}]]}

      assert {done, other, nottoday} ==
               {"done:#{reply.id}", "n:10:#{reply.id}", "a:#{reply.id}:nottoday"}

      tapped(say, other)
      assert_received {:said, "42", "do the taxes — longer than 10 minutes, but it is what is open"}
      assert_received {:with, replace: 90, choices: [[_, {"Something else", other_again}, _]]}
      assert other_again == "n:10:#{taxes.id}-#{reply.id}"

      tapped(say, other_again)
      assert_received {:said, "42", "Nothing open right now." <> _}

      tapped(say, nottoday)
      assert_received {:said, "42", "not today: reply to Sam. It'll wait until tomorrow."}
      assert %{pick: %{id: id}} = Home.now([], nil, DateTime.utc_now())
      assert id == taxes.id
      assert %{pick: %{id: ^id}} = Home.now([reply.id], nil, DateTime.utc_now())
      assert %{pick: nil} = Home.now([id], nil, DateTime.utc_now())

      tapped(say, done)
      assert_received {:said, "42", "done: reply to Sam"}
    end

    test "asked with nothing open, it says so kindly", %{say: say} do
      reads(fn _body, _context -> {:ok, %{kind: "now", text: "", due_at: nil, ids: [], amends: false}} end)
      hear(say, 1, "what now")
      assert_received {:said, "42", "Nothing open right now. That's a good place to be."}
      assert [%{kind: "talk"}] = Jot.recent("telegram", 10)
    end

    test "Not today hides a thing until tomorrow, not after", %{say: say} do
      jot = todo(1, "do the taxes")
      tapped(say, "a:#{jot.id}:nottoday")
      assert_received {:said, "42", "not today:" <> _}
      %{hidden_until: until} = fresh(jot)
      assert DateTime.diff(until, DateTime.utc_now()) in 1..86_400

      assert :error = Organize.answer("telegram", jot.id + 1, "nottoday", nil, DateTime.utc_now())
    end
  end

  describe "the desktop" do
    test "every question is a sticky alert whose buttons are calls on the answer route" do
      todo(1, "do the taxes", received_at: DateTime.add(friday(), -8, :day))
      stale(2, "old", 15)
      {:ok, wait} = Jot.take("telegram", 3, "x")
      Jot.file(wait, %{kind: "waiting", text: "the photos", due_at: Clock.utc(~N[2026-11-20 08:00:00]), who: "Sam"})
      helps(fn _prompt -> {:ok, "Find the return"} end)
      Organize.waiting("telegram", "", nil, friday())
      Organize.weekly("telegram", "", nil, friday(), "fri", "17:30", ~D[2026-11-13])
      Inbox.daily("telegram", "", nil, friday(), "17:30", ~D[2026-11-19])

      {:ok, project} = Jot.take("telegram", 4, "plan")
      project = Jot.file(project, %{kind: "project", text: "plan mom's birthday", due_at: nil, steps: ["a", "b"]})
      project |> Jot.plan(["b"]) |> Jot.ask("next", "b", friday())

      alerts = Alerts.build([], [], friday(), asked: Home.asked())

      assert [%{kind: "home_ask", level: "sticky"} | _] = alerts
      assert length(alerts) == 4

      by_title = Map.new(alerts, &{&1.title, &1})

      assert %{actions: [keep, later, drop], key: "ask:" <> _} = by_title["Still want this? old"]
      assert keep.label == "Keep" and later.body == %{choice: "later"} and drop.method == "POST"
      assert keep.path =~ ~r{^/api/home/\d+/answer$}

      assert %{actions: [got, chased, tomorrow]} = by_title["Still waiting on Sam for the photos?"]
      assert {got.body, chased.body, tomorrow.body} == {%{choice: "got"}, %{choice: "chased"}, %{choice: "tomorrow"}}

      assert %{actions: [add, _no]} = by_title["'do the taxes' has sat a week. A two-minute start: Find the return?"]
      assert add.label == "Add that"

      assert %{actions: [add_it, finish, typed]} = by_title["Next for plan mom's birthday: b?"]
      assert add_it.path == "/api/home/#{project.id}/answer" and add_it.body == %{choice: "add"}
      assert finish.label == "Project's finished"

      assert typed == %{
               label: "Something else…",
               method: "POST",
               path: add_it.path,
               body: %{choice: "step"},
               input: "text"
             }
    end

    test "an answered question stops being raised, and a new ask of the same thing is a new alert" do
      jot = stale(1, "old", 15)
      Organize.weekly("telegram", "", nil, friday(), "fri", "17:30", ~D[2026-11-13])
      [%{key: first}] = Alerts.build([], [], friday(), asked: Home.asked())

      Home.answer(jot.id, "keep", nil, friday())
      assert Alerts.build([], [], friday(), asked: Home.asked()) == []

      set(jot, touched_at: DateTime.add(friday(), -15, :day))
      Organize.weekly("telegram", "", nil, DateTime.add(friday(), 7, :day), "fri", "17:30", ~D[2026-11-20])
      assert [%{key: second}] = Alerts.build([], [], friday(), asked: Home.asked())
      assert second != first
    end
  end
end
