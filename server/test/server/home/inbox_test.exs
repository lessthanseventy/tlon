defmodule Server.Home.InboxTest do
  use ExUnit.Case, async: false

  alias Server.Home.Inbox
  alias Server.Jot

  setup do
    Server.TestDB.clean!()
    reads(fn _body, _context -> :error end)
    on_exit(fn -> Application.delete_env(:server, :home_reader) end)
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

  defp friday, do: ~U[2026-11-20 16:00:00Z]

  defp dentist(due, amends), do: {:ok, %{kind: "reminder", text: "call the dentist", due_at: due, amends: amends}}

  test "a jot is read, and the reading is kept beside it and said back", %{say: say} do
    reads(fn "call the dentist friday", %{previous: nil, open: [], notes: []} -> dentist(friday(), false) end)

    Inbox.hear([%{id: 7, chat: "42", text: "call the dentist friday"}], "telegram", "42", say)

    assert [%{body: "call the dentist friday", kind: "reminder", text: "call the dentist", due_at: due}] =
             Jot.recent("telegram", 10)

    assert due == friday()
    assert_received {:said, "42", "I'll remind you " <> _}
  end

  test "a message that corrects the jot before it changes that jot's reading", %{say: say} do
    reads(fn _body, _context -> dentist(friday(), false) end)
    Inbox.hear([%{id: 7, chat: "42", text: "call the dentist friday"}], "telegram", "42", say)
    saturday = DateTime.add(friday(), 86_400)
    reads(fn "no, saturday", %{previous: %Jot{external_id: 7}} -> dentist(saturday, true) end)

    Inbox.hear([%{id: 8, chat: "42", text: "no, saturday"}], "telegram", "42", say)

    assert [%{kind: "amend", body: "no, saturday"}, %{kind: "reminder", due_at: ^saturday}] = Jot.recent("telegram", 10)
    assert_received {:said, "42", "changed: I'll remind you " <> _}
  end

  defp keep(id, text, reading, say) do
    reads(fn _body, _context -> {:ok, Map.merge(%{due_at: nil, every: nil, ids: [], amends: false}, reading)} end)
    Inbox.hear([%{id: id, chat: "42", text: text}], "telegram", "42", say)
    assert_received {:said, "42", _}
    [jot] = Jot.recent("telegram", 1)
    jot
  end

  test "a to-do and an overdue reminder are still open, a later one is coming up, each open one with its tick", %{
    say: say
  } do
    milk = keep(1, "buy milk", %{kind: "todo", text: "buy milk"}, say)
    keep(2, "wifi is on the fridge", %{kind: "note", text: "wifi is on the fridge"}, say)
    dentist = keep(3, "dentist", %{kind: "reminder", text: "call the dentist", due_at: ~U[2026-11-01 16:00:00Z]}, say)
    keep(4, "bins", %{kind: "reminder", text: "bins", due_at: DateTime.add(friday(), 2, :day)}, say)

    assert {text, choices: [[{"✓ buy milk", tick}], [{"✓ call the dentist", _}]]} =
             Inbox.digest("telegram", DateTime.add(friday(), 1, :hour))

    assert tick == "tick:#{milk.id}"
    assert text =~ "Still open:\n• buy milk\n• call the dentist\n\nComing up:\n• "
    assert text =~ ": bins"
    refute text =~ "wifi"

    Inbox.hear([press("tick", milk)], "telegram", "42", say)
    assert_received {:said, "42", "Still open:\n• call the dentist" <> _}
    assert_received {:with, replace: 90, choices: [[{"✓ call the dentist", _}]]}

    Inbox.hear([press("tick", dentist)], "telegram", "42", say)
    assert_received {:said, "42", "Coming up:" <> _}
    assert Inbox.digest("telegram", DateTime.add(friday(), 3, :day)) != nil
  end

  test "asked what is open, the helper lists it, and the question is kept as nothing", %{say: say} do
    keep(1, "buy milk", %{kind: "todo", text: "buy milk"}, say)

    reads(fn "what's on my list?", %{open: [%Jot{text: "buy milk"}]} ->
      {:ok, %{kind: "list", text: "", ids: [], amends: false}}
    end)

    Inbox.hear([%{id: 2, chat: "42", text: "what's on my list?"}], "telegram", "42", say)

    assert_received {:said, "42", "Still open:\n• buy milk"}
    assert [%{kind: "talk"}, %{kind: "todo"}] = Jot.recent("telegram", 10)
  end

  test "told in words that things are done, the helper closes them", %{say: say} do
    milk = keep(1, "buy milk", %{kind: "todo", text: "buy milk"}, say)
    reads(fn _body, _context -> {:ok, %{kind: "done", text: "", ids: [milk.id, 999], amends: false}} end)

    Inbox.hear([%{id: 2, chat: "42", text: "got the milk"}], "telegram", "42", say)

    assert_received {:said, "42", "done: buy milk"}
    assert Inbox.digest("telegram", friday()) == nil

    Inbox.hear([%{id: 3, chat: "42", text: "got the milk again"}], "telegram", "42", say)
    assert_received {:said, "42", "I couldn't tell which one you meant.\n\nNothing open."}
  end

  test "a question is answered from the notes it is shown, and kept as nothing", %{say: say} do
    keep(1, "wifi at mom's is on the fridge", %{kind: "note", text: "wifi at mom's is on the fridge"}, say)

    reads(fn "where's mom's wifi?", %{notes: ["wifi at mom's is on the fridge"]} ->
      {:ok, %{kind: "answer", text: "On the fridge.", ids: [], amends: false}}
    end)

    Inbox.hear([%{id: 2, chat: "42", text: "where's mom's wifi?"}], "telegram", "42", say)

    assert_received {:said, "42", "On the fridge."}
    assert Jot.notes("telegram", 10) == ["wifi at mom's is on the fridge"]
  end

  test "a reminder that repeats is put off to its next time when done", %{say: say} do
    jot = keep(1, "bins every week", %{kind: "reminder", text: "bins", due_at: friday(), every: "week"}, say)
    Inbox.nudge("telegram", "42", say, friday())
    assert_received {:said, "42", "reminder: bins"}

    Inbox.hear([press("done", jot)], "telegram", "42", say)

    assert_received {:said, "42", "done: bins. Next: " <> _}
    assert [%{done_at: nil, due_at: due, nudges: 0}] = Jot.recent("telegram", 1)
    assert DateTime.diff(due, friday(), :day) == 7
  end

  test "a reminder that repeats and was never answered moves on to its newest time", %{say: say} do
    keep(1, "bins every day", %{kind: "reminder", text: "bins", due_at: friday(), every: "day"}, say)
    Inbox.nudge("telegram", "42", say, friday())
    assert_received {:said, "42", "reminder: bins"}

    Inbox.nudge("telegram", "42", say, DateTime.add(friday(), 49, :hour))

    assert_received {:said, "42", "reminder: bins"}
    assert [%{due_at: due, nudges: 1}] = Jot.recent("telegram", 1)
    assert DateTime.diff(due, friday(), :hour) == 48
  end

  test "the daily list is said once a day, after its time, and not on the day the inbox starts late", %{say: say} do
    keep(1, "buy milk", %{kind: "todo", text: "buy milk"}, say)
    before = Server.Home.Clock.utc(~N[2026-11-20 17:00:00])
    past = Server.Home.Clock.utc(~N[2026-11-20 17:31:00])

    assert Inbox.daily("telegram", "42", say, past, "17:30", :boot) == ~D[2026-11-20]
    assert Inbox.daily("telegram", "42", say, before, "17:30", :boot) == ~D[2026-11-19]
    assert Inbox.daily("telegram", "42", say, before, "17:30", ~D[2026-11-19]) == ~D[2026-11-19]
    refute_received {:said, _, _}

    assert Inbox.daily("telegram", "42", say, past, "17:30", ~D[2026-11-19]) == ~D[2026-11-20]
    assert_received {:said, "42", "Before you clock out:\n\nStill open:\n• buy milk"}

    assert Inbox.daily("telegram", "42", say, past, "17:30", ~D[2026-11-20]) == ~D[2026-11-20]
    assert Inbox.daily("telegram", "42", say, past, "", ~D[2026-11-19]) == ~D[2026-11-19]
    refute_received {:said, _, _}
  end

  defp reminded(say) do
    reads(fn _body, _context -> dentist(friday(), false) end)
    Inbox.hear([%{id: 7, chat: "42", text: "call the dentist friday"}], "telegram", "42", say)
    assert_received {:said, "42", "I'll remind you " <> _}
    [jot] = Jot.recent("telegram", 1)
    jot
  end

  defp press(what, jot), do: %{id: 20, chat: "42", text: nil, tap: "#{what}:#{jot.id}", tap_id: "q", ref: 90}

  test "a reminder is said when it is due, with its choices under it", %{say: say} do
    jot = reminded(say)

    Inbox.nudge("telegram", "42", say, DateTime.add(friday(), -60))
    refute_received {:said, _, _}

    Inbox.nudge("telegram", "42", say, friday())
    assert_received {:said, "42", "reminder: call the dentist"}
    assert_received {:with, choices: [[{"Done", done}, {"In an hour", _}, {"Tomorrow", _}], [{"Delete", "drop:" <> _}]]}
    assert done == "done:#{jot.id}"
  end

  test "with no chat, a due reminder is told all the same, and is what the desktop keeps up", %{say: say} do
    jot = reminded(say)
    assert Server.Home.told() == []

    Inbox.nudge("telegram", "", nil, friday())

    assert [%{id: id, nudges: 1}] = Server.Home.told()
    assert id == jot.id

    assert [%{key: key, kind: "reminder", title: "call the dentist"}] =
             Enum.filter(Server.Alerts.list(), &(&1.kind == "reminder"))

    assert key == "reminder:#{jot.id}:1"
  end

  test "the daily list is a desktop's for ten minutes after its time, when something is open", %{say: say} do
    at = fn time -> Server.Home.Clock.utc(NaiveDateTime.new!(~D[2026-11-21], time)) end
    assert Server.Home.listing(at.(~T[17:35:00])) == nil

    reminded(say)

    assert %{id: "2026-11-21", body: "Still open: call the dentist"} = Server.Home.listing(at.(~T[17:35:00]))
    assert Server.Home.listing(at.(~T[17:29:00])) == nil
    assert Server.Home.listing(at.(~T[17:41:00])) == nil
  end

  test "a reminder left unanswered is said again after half an hour, then an hour after that", %{say: say} do
    reminded(say)
    Inbox.nudge("telegram", "42", say, friday())
    assert_received {:said, "42", "reminder: " <> _}

    Inbox.nudge("telegram", "42", say, DateTime.add(friday(), 29, :minute))
    refute_received {:said, _, _}

    Inbox.nudge("telegram", "42", say, DateTime.add(friday(), 30, :minute))
    assert_received {:said, "42", "reminder: " <> _}

    Inbox.nudge("telegram", "42", say, DateTime.add(friday(), 89, :minute))
    refute_received {:said, _, _}

    Inbox.nudge("telegram", "42", say, DateTime.add(friday(), 90, :minute))
    assert_received {:said, "42", "reminder: " <> _}
  end

  test "an unanswered reminder waits out the night", %{say: say} do
    reminded(say)
    night = Server.Home.Clock.utc(~N[2026-11-20 23:00:00])
    Inbox.nudge("telegram", "42", say, DateTime.add(night, -3600))
    assert_received {:said, "42", "reminder: " <> _}

    Inbox.nudge("telegram", "42", say, night)
    refute_received {:said, _, _}

    Inbox.nudge("telegram", "42", say, Server.Home.Clock.utc(~N[2026-11-21 08:00:00]))
    assert_received {:said, "42", "reminder: " <> _}
  end

  test "a tap on done closes the reminder, in place of the message it was under", %{say: say} do
    jot = reminded(say)
    Inbox.nudge("telegram", "42", say, friday())
    assert_received {:said, "42", "reminder: " <> _}
    assert_received {:with, choices: _}

    assert Inbox.hear([press("done", jot)], "telegram", "42", say) == 21

    assert_received {:said, "42", "done: call the dentist"}
    assert_received {:with, replace: 90}
    Inbox.nudge("telegram", "42", say, DateTime.add(friday(), 30, :minute))
    refute_received {:said, _, _}

    Inbox.hear([press("done", jot)], "telegram", "42", say)
    assert_received {:said, "42", "That one is already done."}
  end

  test "a tap on in an hour or tomorrow puts the reminder off, to be said afresh then", %{say: say} do
    jot = reminded(say)
    Inbox.nudge("telegram", "42", say, friday())

    Inbox.hear([press("tomorrow", jot)], "telegram", "42", say)

    [%{due_at: due, nudges: 0, nudged_at: nil}] = Jot.recent("telegram", 1)
    local = Server.Home.Clock.local(due)
    assert NaiveDateTime.to_time(local) == ~T[09:00:00]

    assert Date.diff(NaiveDateTime.to_date(local), NaiveDateTime.to_date(Server.Home.Clock.local(DateTime.utc_now()))) ==
             1

    Inbox.hear([press("hour", jot)], "telegram", "42", say)
    [%{due_at: due}] = Jot.recent("telegram", 1)
    assert_in_delta DateTime.diff(due, DateTime.utc_now()), 3600, 5
  end

  test "done typed in the chat is the reminder said last, and is kept as no jot", %{say: say} do
    reminded(say)
    Inbox.nudge("telegram", "42", say, friday())
    assert_received {:said, "42", "reminder: " <> _}

    Inbox.hear([%{id: 9, chat: "42", text: " Done "}], "telegram", "42", say)

    assert_received {:said, "42", "done: call the dentist"}
    assert [%{done_at: %DateTime{}}] = Jot.recent("telegram", 10)
  end

  test "a reminder whose message did not go out is said at the next poll", %{say: say} do
    reminded(say)

    Inbox.nudge("telegram", "42", fn _chat, _text, _opts -> {:error, :timeout} end, friday())

    assert [%{nudged_at: nil, nudges: 0}] = Jot.due("telegram", friday())
  end

  defp bodies, do: Enum.map(Jot.recent("telegram", 10), & &1.body)

  test "a text from the paired chat is kept as it came and answered", %{say: say} do
    assert Inbox.hear([%{id: 7, chat: "42", text: "dentist, call before friday"}], "telegram", "42", say) == 8

    assert bodies() == ["dentist, call before friday"]
    assert_received {:said, "42", "got it"}
  end

  test "an update heard twice is one jot and one answer", %{say: say} do
    update = %{id: 7, chat: "42", text: "milk"}
    Inbox.hear([update], "telegram", "42", say)
    assert_received {:said, "42", "got it"}

    assert Inbox.hear([update], "telegram", "42", say) == 8
    assert bodies() == ["milk"]
    refute_received {:said, _, _}
  end

  test "a voice note's words are the jot, said back as heard", %{say: say} do
    Application.put_env(:server, :home_ear, fn "f1" -> {:ok, "call the dentist friday"} end)
    on_exit(fn -> Application.delete_env(:server, :home_ear) end)
    reads(fn "call the dentist friday", _context -> dentist(friday(), false) end)

    assert Inbox.hear([%{id: 7, chat: "42", text: nil, voice: "f1"}], "telegram", "42", say) == 8

    assert [%{body: "call the dentist friday", kind: "reminder"}] = Jot.recent("telegram", 10)
    assert_received {:said, "42", "heard: “call the dentist friday”\nI'll remind you " <> _}
  end

  test "a voice note that cannot be heard is kept nowhere, and said so", %{say: say} do
    Application.put_env(:server, :home_ear, fn _file -> {:error, :silence} end)
    on_exit(fn -> Application.delete_env(:server, :home_ear) end)

    ExUnit.CaptureLog.capture_log(fn ->
      Inbox.hear([%{id: 7, chat: "42", text: nil, voice: "f1"}], "telegram", "42", say)
    end)

    assert bodies() == []
    assert_received {:said, "42", "I couldn't make that one out" <> _}
  end

  test "what is not text is kept nowhere, and said so", %{say: say} do
    assert Inbox.hear([%{id: 3, chat: "42", text: nil}], "telegram", "42", say) == 4

    assert bodies() == []
    assert_received {:said, "42", "I can only keep text so far" <> _}
  end

  test "the messenger's own command is greeted and never kept", %{say: say} do
    assert Inbox.hear([%{id: 2, chat: "42", text: "/start"}], "telegram", "42", say) == 3

    assert bodies() == []
    assert_received {:said, "42", "Text me anything" <> _}
  end

  test "with no chat paired, a chat is told its id and nothing is kept", %{say: say} do
    Inbox.hear([%{id: 1, chat: "99", text: "hello"}], "telegram", "", say)

    assert bodies() == []
    assert_received {:said, "99", text}
    assert text =~ "99"
    assert text =~ "home_chat"
  end

  test "once a chat is paired, another chat is ignored", %{say: say} do
    assert Inbox.hear([%{id: 1, chat: "99", text: "let me in"}], "telegram", "42", say) == 2

    assert bodies() == []
    refute_received {:said, _, _}
  end

  test "no updates leave the offset where it was", %{say: say} do
    assert Inbox.hear([], "telegram", "42", say) == nil
  end

  test "the next poll starts after the last jot kept", %{say: say} do
    assert Jot.cursor("telegram") == nil
    Inbox.hear([%{id: 11, chat: "42", text: "a"}, %{id: 12, chat: "42", text: "b"}], "telegram", "42", say)
    assert Jot.cursor("telegram") == 12
    assert bodies() == ["b", "a"]
  end
end
