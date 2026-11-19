defmodule Server.Home.MorningTest do
  use ExUnit.Case, async: false

  alias Server.Agenda
  alias Server.Home
  alias Server.Home.Clock
  alias Server.Home.Day
  alias Server.Home.Inbox
  alias Server.Home.Morning
  alias Server.Jot
  alias Server.Proposal

  setup do
    Server.TestDB.clean!()

    me = self()

    %{
      say: fn chat, text, opts ->
        send(me, {:said, chat, text, opts})
        :ok
      end
    }
  end

  defp at(date, time), do: Clock.utc(NaiveDateTime.new!(date, time))
  defp friday(time), do: at(~D[2026-11-20], time)

  defp reminder(text, due) do
    {:ok, jot} = Jot.take("telegram", System.unique_integer([:positive]), text)
    Jot.file(jot, %{kind: "reminder", text: text, due_at: due}, due)
  end

  defp propose(n, attrs \\ %{}) do
    Proposal.offer(
      "telegram",
      "test",
      [Map.merge(%{key: "k#{n}", text: "thing #{n}", why: "from #{n}", kind: "todo"}, attrs)],
      friday(~T[06:00:00]),
      []
    )
  end

  test "there is nothing to say, so nothing is said" do
    assert Morning.compose("telegram", friday(~T[08:35:00])) == nil
    assert Morning.plain("telegram", friday(~T[08:35:00]), friday(~T[08:30:00])) == nil
  end

  defp meeting(title, date, from, to, opts \\ []) do
    Map.merge(
      %{title: title, start: at(date, from), stop: at(date, to), cancelled: false, busy: :busy, all_day: false},
      Map.new(opts)
    )
  end

  test "it holds the meetings, what to start with, the agendas due today and what is proposed" do
    now = friday(~T[08:35:00])
    friday = ~D[2026-11-20]

    meetings =
      Day.build(
        [
          meeting("Standup", friday, ~T[09:30:00], ~T[10:00:00]),
          meeting("1:1 with Sam", friday, ~T[13:00:00], ~T[13:30:00], busy: :tentative),
          meeting("Offsite", friday, ~T[00:00:00], ~T[00:00:00],
            all_day: true,
            start: ~U[2026-11-20 00:00:00Z],
            stop: ~U[2026-11-21 00:00:00Z]
          ),
          meeting("Tomorrow's", ~D[2026-11-21], ~T[09:00:00], ~T[10:00:00])
        ],
        now
      )

    reminder("call the dentist", friday(~T[08:05:00]))
    {:ok, retro} = Agenda.create("telegram", "retro", %{next_at: friday(~T[14:00:00])}, friday(~T[06:00:00]))

    {:ok, other} =
      Agenda.create("telegram", "weekly", %{next_at: at(~D[2026-11-23], ~T[10:00:00])}, friday(~T[06:00:00]))

    for {agenda, text} <- [{retro, "flaky gate"}, {retro, "deploy"}, {other, "later"}] do
      {:ok, jot} = Jot.take("telegram", System.unique_integer([:positive]), text)
      Agenda.note(agenda, jot, text, friday(~T[06:00:00]))
    end

    propose(1)
    propose(2)

    assert {text, []} = Morning.compose("telegram", now, meetings)

    assert text ==
             """
             Good morning.

             Today:
             • all day Offsite
             • 09:30 Standup
             • 13:00 1:1 with Sam (tentative)

             Start with: call the dentist — due 30 minutes ago

             Due today:
             • retro at 14:00: 2 things\
             """

    assert {plain, []} = Morning.plain("telegram", now, friday(~T[08:30:00]), meetings)
    assert plain == text <> "\n\nProposed (2):\n1. thing 1 (from 1)\n2. thing 2 (from 2)"
  end

  test "the chat's morning message has no buttons and the proposals follow as a message of their own", %{say: say} do
    reminder("call the dentist", friday(~T[08:05:00]))
    propose(1)
    propose(2)

    assert Inbox.morning("telegram", "42", say, friday(~T[08:35:00]), "08:30", ~D[2026-11-19]) == ~D[2026-11-20]
    assert_received {:said, "42", "Good morning.\n\nStart with: call the dentist — due 30 minutes ago", []}
    assert_received {:said, "42", "Proposed (2):\n1. thing 1 (from 1)\n2. thing 2 (from 2)", opts}
    assert [[{"Add 1", "p:" <> _}, {"No 1", _}], [{"Add 2", _}, {"No 2", _}]] = opts[:choices]
    refute_received {:said, _, _, _}
  end

  test "with only proposals the chat gets just the proposals message, five shown and the rest counted", %{say: say} do
    for n <- 1..7, do: propose(n)
    assert Morning.compose("telegram", friday(~T[08:35:00])) == nil
    Inbox.morning("telegram", "42", say, friday(~T[08:35:00]), "08:30", ~D[2026-11-19])
    assert_received {:said, "42", "Proposed (7):\n1. thing 1" <> _ = text, opts}
    assert text =~ "5. thing 5 (from 5)\nand 2 more"
    assert length(opts[:choices]) == 5
    refute_received {:said, _, _, _}
  end

  test "with no proposals there is no second message", %{say: say} do
    reminder("call the dentist", friday(~T[08:05:00]))
    Inbox.morning("telegram", "42", say, friday(~T[08:35:00]), "08:30", ~D[2026-11-19])
    assert_received {:said, "42", "Good morning." <> _, []}
    refute_received {:said, _, _, _}
  end

  test "a tap on Add replaces the proposals message only; the last No leaves a closing line with no buttons", %{
    say: say
  } do
    propose(1)
    propose(2)
    Inbox.morning("telegram", "42", say, friday(~T[08:35:00]), "08:30", ~D[2026-11-19])
    assert_received {:said, "42", "Proposed (2):" <> _, opts}
    [[{_, add}, {_, no}] | _] = opts[:choices]

    Inbox.hear([%{id: 1, chat: "42", tap: add, ref: 77, text: nil}], "telegram", "42", say)
    assert_received {:said, "42", "added: thing 1\n\nProposed (1):\n1. thing 2 (from 2)", reply}
    assert reply[:replace] == 77
    assert [[{"Add 1", _}, {"No 1", no2}]] = reply[:choices]
    refute no == no2

    Inbox.hear([%{id: 2, chat: "42", tap: no2, ref: 77, text: nil}], "telegram", "42", say)
    assert_received {:said, "42", "left out: thing 2", [replace: 77]}
  end

  test "a tick on a daily list that had Settled lines keeps them, and adds no proposals", %{say: say} do
    {:ok, jot} = Jot.take("telegram", 1, "milk")
    Jot.file(jot, %{kind: "todo", text: "milk", due_at: nil}, friday(~T[06:00:00]))
    {:ok, other} = Jot.take("telegram", 2, "bread")
    Jot.file(other, %{kind: "todo", text: "bread", due_at: nil}, friday(~T[06:00:00]))
    propose(1)
    settle()

    Inbox.daily("telegram", "42", say, friday(~T[17:35:00]), "17:30", ~D[2026-11-19])

    assert_received {:said, "42", "Before you clock out:\n\nStill open:\n• milk\n• bread\n\nSettled:\n• Reviewed: PR 1",
                     opts}

    assert [[{"✓ milk", tick}], [{"✓ bread", _}]] = opts[:choices]
    assert_received {:said, "42", "Proposed (1):" <> _, _}

    Inbox.hear([%{id: 3, chat: "42", tap: tick, ref: 9, text: nil}], "telegram", "42", say)
    assert_received {:said, "42", "Still open:\n• bread\n\nSettled:\n• Reviewed: PR 1", reply}
    assert reply[:replace] == 9
    assert [[{"✓ bread", _}]] = reply[:choices]

    Inbox.hear([%{id: 4, chat: "42", tap: tick, ref: 9, text: nil}], "telegram", "42", say)
    assert_received {:said, "42", "Still open:\n• bread\n\nSettled:\n• Reviewed: PR 1", _}
  end

  describe "said once a day at home_morning_at" do
    test "the first start counts the newest slot as said; the next day's is said once, when awake", %{say: say} do
      propose(1)
      saturday = ~D[2026-11-21]
      last = Inbox.morning("telegram", "42", say, at(saturday, ~T[08:40:00]), "08:30", :boot)
      assert last == saturday
      refute_received {:said, _, _, _}

      sunday = ~D[2026-11-22]
      assert Inbox.morning("telegram", "42", say, at(sunday, ~T[08:20:00]), "08:30", last) == last
      refute_received {:said, _, _, _}

      assert Inbox.morning("telegram", "42", say, at(sunday, ~T[08:31:00]), "08:30", last) == sunday
      assert_received {:said, "42", "Proposed (1):" <> _, [choices: [_]]}

      assert Inbox.morning("telegram", "42", say, at(sunday, ~T[09:00:00]), "08:30", sunday) == sunday
      refute_received {:said, _, _, _}
    end

    test "one set for the small hours waits for waking, and \"\" is never", %{say: say} do
      propose(1)
      last = ~D[2026-11-21]
      assert Inbox.morning("telegram", "42", say, at(~D[2026-11-22], ~T[03:05:00]), "03:00", last) == last
      refute_received {:said, _, _, _}

      assert Inbox.morning("telegram", "42", say, at(~D[2026-11-22], ~T[08:00:00]), "03:00", last) == ~D[2026-11-22]
      assert_received {:said, "42", "Proposed (1):" <> _, _}

      assert Inbox.morning("telegram", "42", say, at(~D[2026-11-23], ~T[09:00:00]), "", last) == last
      refute_received {:said, _, _, _}
    end

    test "with nothing to say the slot passes without a word, and with no chat it passes silently", %{say: say} do
      last = ~D[2026-11-21]
      assert Inbox.morning("telegram", "42", say, at(~D[2026-11-22], ~T[09:00:00]), "08:30", last) == ~D[2026-11-22]
      propose(1)

      assert Inbox.morning("telegram", "", nil, at(~D[2026-11-23], ~T[09:00:00]), "08:30", ~D[2026-11-22]) ==
               ~D[2026-11-23]

      refute_received {:said, _, _, _}
    end

    test "a settled waiting-on is said in it once", %{say: say} do
      Proposal.offer(
        "telegram",
        "test",
        [%{key: "w", text: "Waiting on review: PR 1", kind: "waiting", done_text: "Reviewed: PR 1"}],
        friday(~T[06:00:00]),
        ["waiting"]
      )

      Proposal.resolve("test", ["w"], friday(~T[07:00:00]))
      Inbox.morning("telegram", "42", say, friday(~T[08:35:00]), "08:30", ~D[2026-11-19])
      assert_received {:said, "42", "Good morning.\n\nSettled:\n• Reviewed: PR 1", _}
      assert Proposal.settled() == []
    end
  end

  test "the desktop is raised it for ten minutes after its time, as plain text" do
    propose(1)
    assert %{id: "morning:2026-11-20", body: "Good morning." <> _} = Home.morning(friday(~T[08:35:00]))
    assert Home.morning(friday(~T[08:29:00])) == nil
    assert Home.morning(friday(~T[08:41:00])) == nil
  end

  test "the desktop reading its alert marks nothing: the chat's morning still carries the settled line", %{say: say} do
    settle()
    assert %{body: body} = Home.morning(friday(~T[08:32:00]))
    assert body =~ "Settled:\n• Reviewed: PR 1"
    assert [%{resolved_said_at: nil}] = Proposal.settled()

    Inbox.morning("telegram", "42", say, friday(~T[08:33:00]), "08:30", ~D[2026-11-19])
    assert_received {:said, "42", "Good morning.\n\nSettled:\n• Reviewed: PR 1", _}
    assert %{body: ^body} = Home.morning(friday(~T[08:38:00]))
    assert Home.morning(friday(~T[08:45:00])) == nil
  end

  test "the chat's morning said first: the desktop still reads the line while its alert is up, and no longer", %{
    say: say
  } do
    settle()
    Inbox.morning("telegram", "42", say, friday(~T[08:30:30]), "08:30", ~D[2026-11-19])
    assert_received {:said, "42", "Good morning.\n\nSettled:" <> _, _}

    assert %{body: "Good morning.\n\nSettled:\n• Reviewed: PR 1"} = Home.morning(friday(~T[08:32:00]))
    assert Home.morning(friday(~T[08:45:00])) == nil
  end

  test "with no chat, the tick records the settled line at the slot: the desktop shows it for its window, once" do
    settle()
    assert Inbox.morning("telegram", "", nil, friday(~T[08:30:30]), "08:30", ~D[2026-11-19]) == ~D[2026-11-20]
    assert [] = Proposal.settled()

    assert %{body: body} = Home.morning(friday(~T[08:32:00]))
    assert body =~ "Settled:\n• Reviewed: PR 1"
    assert %{body: ^body} = Home.morning(friday(~T[08:38:00]))
    assert Home.morning(friday(~T[08:45:00])) == nil

    next = DateTime.add(friday(~T[08:32:00]), 86_400)
    assert Home.morning(next) == nil

    assert Inbox.morning("telegram", "", nil, DateTime.add(friday(~T[08:30:30]), 86_400), "08:30", ~D[2026-11-20]) ==
             ~D[2026-11-21]

    assert Home.morning(next) == nil
  end

  test "the daily list is the same: a desktop read marks nothing, and with no chat the tick records it" do
    settle()
    assert %{body: "Settled:\n• Reviewed: PR 1"} = Home.listing(friday(~T[17:35:00]))
    assert [%{resolved_said_at: nil}] = Proposal.settled()

    assert Inbox.daily("telegram", "", nil, friday(~T[17:30:30]), "17:30", ~D[2026-11-19]) == ~D[2026-11-20]
    assert [] = Proposal.settled()
    assert %{body: "Settled:" <> _} = Home.listing(friday(~T[17:38:00]))
    assert Home.listing(friday(~T[17:45:00])) == nil
  end

  defp settle do
    Proposal.offer(
      "telegram",
      "test",
      [%{key: "w", text: "Waiting on review: PR 1", kind: "waiting", done_text: "Reviewed: PR 1"}],
      friday(~T[06:00:00]),
      ["waiting"]
    )

    Proposal.resolve("test", ["w"], friday(~T[07:00:00]))
  end

  test "the daily list holds the proposals, and what a source settled, once", %{say: say} do
    {:ok, jot} = Jot.take("telegram", 1, "milk")
    Jot.file(jot, %{kind: "todo", text: "milk", due_at: nil}, friday(~T[06:00:00]))
    propose(1)

    Proposal.offer(
      "telegram",
      "test",
      [%{key: "w", text: "Waiting on review: PR 1", kind: "waiting", done_text: "Reviewed: PR 1"}],
      friday(~T[06:00:00]),
      ["waiting"]
    )

    Proposal.resolve("test", ["w"], friday(~T[07:00:00]))
    Inbox.daily("telegram", "42", say, friday(~T[17:35:00]), "17:30", ~D[2026-11-19])

    assert_received {:said, "42", text, opts}

    assert text == "Before you clock out:\n\nStill open:\n• milk\n\nSettled:\n• Reviewed: PR 1"
    assert [[{"✓ milk", _}]] = opts[:choices]
    assert_received {:said, "42", "Proposed (1):\n1. thing 1 (from 1)", [choices: [[{"Add 1", _}, {"No 1", _}]]]}

    Inbox.daily("telegram", "42", say, friday(~T[17:36:00]), "17:30", ~D[2026-11-19])
    assert_received {:said, "42", text, _}
    refute text =~ "Settled"
  end
end
