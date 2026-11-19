defmodule Server.ProposalTest do
  use ExUnit.Case, async: false

  alias Server.Home.Inbox
  alias Server.Home.Proposals
  alias Server.Jot
  alias Server.Proposal

  @now ~U[2026-11-19 12:00:00Z]

  setup do
    Server.TestDB.clean!()
    on_exit(fn -> Application.delete_env(:server, :home_reader) end)
    me = self()

    %{
      say: fn chat, text, opts ->
        send(me, {:said, chat, text, opts})
        :ok
      end
    }
  end

  defp sam, do: %{key: "sam-q4", text: "Send Sam the Q4 numbers by Friday", why: "Sam asked in #finance", kind: "todo"}

  defp pr(n),
    do: %{
      key: "https://github.com/o/r/pull/#{n}:waiting",
      text: "Waiting on review: PR #{n}",
      kind: "waiting",
      who: "a reviewer",
      done_text: "Reviewed: PR #{n}"
    }

  defp offer(attrs, auto \\ []), do: Proposal.offer("telegram", "test", attrs, @now, auto)

  test "offering the same key again never duplicates" do
    offer([sam()])
    offer([sam(), Map.put(sam(), :text, "changed")])
    assert [%{text: "Send Sam the Q4 numbers by Friday", state: :open}] = Proposal.open()
  end

  test "taking files a to-do linked back, and the key is never re-opened" do
    offer([sam()])
    [%{id: id}] = Proposal.open()

    assert {:ok, %{state: :taken, jot_id: jot_id}} = Proposal.take("telegram", id, @now)
    assert %{kind: "todo", text: "Send Sam the Q4 numbers by Friday"} = Jot.get(jot_id)
    assert :not_found = Proposal.take("telegram", id, @now)

    offer([sam()])
    assert Proposal.open() == []
    assert [%{id: ^jot_id}] = Jot.opens("telegram")
  end

  test "dismissing is final for that key" do
    offer([sam()])
    [%{id: id}] = Proposal.open()
    assert {:ok, %{state: :dismissed}} = Proposal.dismiss(id)
    offer([sam()])
    assert Proposal.open() == []
    assert :not_found = Proposal.dismiss(id)
  end

  test "a waiting proposal from a trusted source is taken at once; a to-do waits for a yes" do
    offer([sam(), pr(1)], ["waiting"])
    assert [%{key: "sam-q4"}] = Proposal.open()
    assert [%{text: "Waiting on review: PR 1", waiting_on: "a reviewer", due_at: nil}] = Jot.waiting("telegram")
  end

  test "a key that is gone withdraws an open proposal silently and leaves a taken to-do" do
    offer([sam(), Map.put(sam(), :key, "other")])
    [%{id: id} | _] = Proposal.open()
    {:ok, _} = Proposal.take("telegram", id, @now)

    Proposal.resolve("test", ["sam-q4", "other"], @now)
    assert Proposal.open() == []
    assert [%{text: "Send Sam the Q4 numbers by Friday"}] = Jot.opens("telegram")
    assert Proposal.settled() == []
  end

  test "a waiting-on taken from a proposal is done when its source resolves it, and said once as settled" do
    offer([pr(1), pr(2)], ["waiting"])

    assert ["https://github.com/o/r/pull/1:waiting", "https://github.com/o/r/pull/2:waiting"] =
             Proposal.live_keys("test")

    Proposal.resolve("test", ["https://github.com/o/r/pull/1:waiting"], @now)
    assert [%{text: "Waiting on review: PR 2"}] = Jot.waiting("telegram")
    assert ["https://github.com/o/r/pull/2:waiting"] = Proposal.live_keys("test")

    assert [row] = Proposal.settled()
    assert Proposals.settled([row]) == ["Reviewed: PR 1"]
    Proposal.settled_said([row], @now)
    assert Proposal.settled() == []
    assert [%{text: "Waiting on review: PR 1", done_at: %DateTime{}}] = Jot.done_since("telegram", @now)
  end

  test "nothing is said when a proposal arrives", %{say: say} do
    offer([sam(), pr(1)], ["waiting"])
    Server.Home.Agendas.tell("telegram", "42", say, @now)
    refute_received {:said, _, _, _}
  end

  describe "in the chat" do
    defp tell(text, reading, say, id) do
      Application.put_env(:server, :home_reader, fn ^text, context ->
        send(self(), {:shown, context.proposals})
        {:ok, Map.merge(%{text: "", due_at: nil, every: nil, ids: [], amends: false}, reading)}
      end)

      Inbox.hear([%{id: id, chat: "42", text: text}], "telegram", "42", say)
      assert_receive {:said, "42", reply, opts}
      {reply, opts}
    end

    setup do
      offer([sam(), Map.merge(sam(), %{key: "k2", text: "Review the deck"})])
      [first, second] = Proposal.open()
      %{first: first, second: second}
    end

    test "\"what's proposed?\" lists them with an Add and a No under each", %{say: say, first: a, second: b} do
      {reply, opts} = tell("what's proposed?", %{kind: "proposals"}, say, 1)
      assert_received {:shown, [_, _]}

      assert reply ==
               "Proposed (2):\n1. Send Sam the Q4 numbers by Friday (Sam asked in #finance)\n2. Review the deck (Sam asked in #finance)"

      assert opts[:choices] == [
               [{"Add 1", "p:#{a.id}:take"}, {"No 1", "p:#{a.id}:no"}],
               [{"Add 2", "p:#{b.id}:take"}, {"No 2", "p:#{b.id}:no"}]
             ]
    end

    test ~s("take the first" and "dismiss all" act on the ids the reader names), %{say: say, first: a, second: b} do
      {reply, _} = tell("take the first", %{kind: "take", ids: [a.id]}, say, 1)
      assert reply =~ "added: Send Sam the Q4 numbers by Friday\n\nProposed (1):\n1. Review the deck"
      assert [%{text: "Send Sam the Q4 numbers by Friday"}] = Jot.opens("telegram")

      {reply, opts} = tell("dismiss all", %{kind: "dismiss", ids: [a.id, b.id]}, say, 2)
      assert reply == "left out: Review the deck"
      assert opts == []
      assert Proposal.open() == []
    end

    test "an id that is not proposed is not guessed at", %{say: say} do
      {reply, _} = tell("yes to the Sam one", %{kind: "take", ids: [999_999]}, say, 1)
      assert reply =~ "I couldn't tell which one you meant.\n\nProposed (2):"
      assert Jot.opens("telegram") == []
    end

    test "a tap on Add files it and shows what is left, a tap on No leaves it out", %{say: say, first: a, second: b} do
      Inbox.hear([%{id: 1, chat: "42", tap: "p:#{a.id}:take", ref: 7, text: nil}], "telegram", "42", say)
      assert_receive {:said, "42", reply, opts}
      assert reply =~ "added: Send Sam the Q4 numbers by Friday\n\nProposed (1):"
      assert opts[:replace] == 7

      Inbox.hear([%{id: 2, chat: "42", tap: "p:#{b.id}:no", ref: 7, text: nil}], "telegram", "42", say)
      assert_receive {:said, "42", "left out: Review the deck", _}

      Inbox.hear([%{id: 3, chat: "42", tap: "p:#{b.id}:no", ref: 7, text: nil}], "telegram", "42", say)
      assert_receive {:said, "42", "That one is already answered.", _}
    end
  end

  describe "the list" do
    test "shows five and says how many more" do
      offer(for n <- 1..7, do: %{key: "k#{n}", text: "thing #{n}", kind: "todo"})
      {text, opts} = Proposals.say(Proposal.open())
      assert text =~ "Proposed (7):\n1. thing 1\n"
      assert text =~ "5. thing 5\nand 2 more"
      assert length(opts[:choices]) == 5
      assert Proposals.say([]) == nil
    end
  end
end
