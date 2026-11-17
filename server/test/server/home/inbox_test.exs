defmodule Server.Home.InboxTest do
  use ExUnit.Case, async: false

  alias Server.Home.Inbox
  alias Server.Jot

  setup do
    Server.TestDB.clean!()
    reads(fn _body, _previous -> :error end)
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
    reads(fn "call the dentist friday", nil -> dentist(friday(), false) end)

    Inbox.hear([%{id: 7, chat: "42", text: "call the dentist friday"}], "telegram", "42", say)

    assert [%{body: "call the dentist friday", kind: "reminder", text: "call the dentist", due_at: due}] =
             Jot.recent("telegram", 10)

    assert due == friday()
    assert_received {:said, "42", "I'll remind you " <> _}
  end

  test "a message that corrects the jot before it changes that jot's reading", %{say: say} do
    reads(fn _body, nil -> dentist(friday(), false) end)
    Inbox.hear([%{id: 7, chat: "42", text: "call the dentist friday"}], "telegram", "42", say)
    saturday = DateTime.add(friday(), 86_400)
    reads(fn "no, saturday", %Jot{external_id: 7} -> dentist(saturday, true) end)

    Inbox.hear([%{id: 8, chat: "42", text: "no, saturday"}], "telegram", "42", say)

    assert [%{kind: "amend", body: "no, saturday"}, %{kind: "reminder", due_at: ^saturday}] = Jot.recent("telegram", 10)
    assert_received {:said, "42", "changed: I'll remind you " <> _}
  end

  defp reminded(say) do
    reads(fn _body, nil -> dentist(friday(), false) end)
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
    assert_received {:with, choices: [{"Done", done}, {"In an hour", _}, {"Tomorrow", _}]}
    assert done == "done:#{jot.id}"
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
