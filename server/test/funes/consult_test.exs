defmodule Server.ConsultTest do
  # The agent-to-agent consult (docs/plans/2026-08-17-agent-peer-consult-design.md):
  # a correlated ask/answer pair between two agents on different threads. The design
  # review pinned three invariants this suite proves: the caller never names a thread
  # (only a peer agent name), the target resolves agent-filtered with a defined tie-break,
  # and the mirror is a bidirectional bridge keyed on consult_id with an echo guard.
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Server.Channel
  alias Server.Consult
  alias Server.Consult.Mirror
  alias Server.Message
  alias Server.Repo
  alias Server.Staff

  setup do
    Server.TestDB.clean!()
    :ok
  end

  # A caller identity shaped like MCP.Identity.from_frame/1 returns.
  defp caller(thread, agent), do: %{thread_id: thread.id, agent_id: agent.id, agent: agent.name}

  describe "consult_peer/3 — the ask" do
    test "delivers the ask to the peer's live thread, authored by the caller, with the correlation" do
      {:ok, caller_thread} = Channel.open_thread(%{title: "caller's work"})
      {:ok, peer_thread} = Channel.open_thread(%{title: "peer's work"})
      {:ok, me} = Staff.register_agent(%{name: "pi", mandate: "ask", engine: "fresh"})
      {:ok, claude} = Staff.register_agent(%{name: "claude", mandate: "answer", engine: "fresh"})
      {:ok, _} = Staff.assign(peer_thread, claude)
      {:ok, _} = Staff.start_session(%{agent_id: claude.id, thread_id: peer_thread.id, pane_ref: "wClaude"})

      {:ok, %{consult_id: consult_id, peer_thread_id: peer_thread_id}} =
        Consult.consult_peer(caller(caller_thread, me), "claude", "is this design sound?")

      assert peer_thread_id == peer_thread.id

      # The ask is a message on the PEER's thread, authored by the CALLER, carrying the
      # correlation (consult_id + origin_thread_id = the caller's thread).
      [ask] = Channel.thread_messages(peer_thread)
      assert ask.author == "pi"
      assert ask.body == "is this design sound?"
      assert ask.consult_id == consult_id
      assert ask.origin_thread_id == caller_thread.id
      refute ask.mirrored
    end

    test "refuses an unknown peer — never guesses" do
      {:ok, caller_thread} = Channel.open_thread(%{title: "caller's work"})
      {:ok, me} = Staff.register_agent(%{name: "pi", mandate: "ask", engine: "fresh"})

      assert {:error, :unknown_peer} =
               Consult.consult_peer(caller(caller_thread, me), "nobody", "hello?")
    end

    test "0 live sessions degrades durably to the peer's most recent thread" do
      {:ok, caller_thread} = Channel.open_thread(%{title: "caller's work"})
      {:ok, old_thread} = Channel.open_thread(%{title: "old"})
      {:ok, new_thread} = Channel.open_thread(%{title: "new"})
      {:ok, me} = Staff.register_agent(%{name: "pi", mandate: "ask", engine: "fresh"})
      {:ok, claude} = Staff.register_agent(%{name: "claude", mandate: "answer", engine: "fresh"})

      # claude is staffed on both threads but has NO live session anywhere.
      {:ok, _} = Staff.assign(old_thread, claude)
      {:ok, _} = Staff.assign(new_thread, claude)

      {:ok, %{peer_thread_id: peer_thread_id}} =
        Consult.consult_peer(caller(caller_thread, me), "claude", "ping")

      # No liveness invented: the ask lands on the most recent thread, durably.
      assert peer_thread_id == new_thread.id
      assert [%Message{body: "ping"}] = Channel.thread_messages(new_thread)
    end

    test ">1 live session picks the most-recently-active by last_active_at, not thread id" do
      {:ok, caller_thread} = Channel.open_thread(%{title: "caller's work"})
      {:ok, machine} = Channel.open_thread(%{title: "machine"})
      {:ok, tlön} = Channel.open_thread(%{title: "tlön"})
      {:ok, me} = Staff.register_agent(%{name: "pi", mandate: "ask", engine: "fresh"})
      {:ok, claude} = Staff.register_agent(%{name: "claude", mandate: "answer", engine: "fresh"})

      # claude is live on BOTH threads — the normal coworker-on-several case.
      {:ok, _} = Staff.assign(machine, claude)
      {:ok, _} = Staff.assign(tlön, claude)
      {:ok, machine_sess} = Staff.start_session(%{agent_id: claude.id, thread_id: machine.id, pane_ref: "wM"})
      {:ok, _} = Staff.start_session(%{agent_id: claude.id, thread_id: tlön.id, pane_ref: "wT"})

      # machine is the OLDER thread (lower id) but the MORE recently active session, so
      # thread-id order would pick tlön while warmth must pick machine.
      assert machine.id < tlön.id

      Repo.update_all(from(s in Server.Session, where: s.id == ^machine_sess.id),
        set: [last_active_at: DateTime.utc_now() |> DateTime.shift(minute: 1) |> DateTime.truncate(:second)]
      )

      {:ok, %{peer_thread_id: peer_thread_id}} =
        Consult.consult_peer(caller(caller_thread, me), "claude", "which thread are you on?")

      # The tie-break is warmth (last_active_at), not thread-id order.
      assert peer_thread_id == machine.id
    end

    test "a stray cross-agent session on the peer's thread does not misroute the target" do
      {:ok, caller_thread} = Channel.open_thread(%{title: "caller's work"})
      {:ok, peer_thread} = Channel.open_thread(%{title: "peer's work"})
      {:ok, me} = Staff.register_agent(%{name: "pi", mandate: "ask", engine: "fresh"})
      {:ok, claude} = Staff.register_agent(%{name: "claude", mandate: "answer", engine: "fresh"})
      {:ok, other} = Staff.register_agent(%{name: "other", mandate: "stray", engine: "fresh"})

      # claude is staffed on peer_thread, but a DIFFERENT agent holds the live session there.
      {:ok, _} = Staff.assign(peer_thread, claude)
      {:ok, _} = Staff.start_session(%{agent_id: other.id, thread_id: peer_thread.id, pane_ref: "wOther"})

      # The target must filter by agent (live_session(thread.id, claude.id)), so claude has
      # NO live session → degrade durably to the most recent thread, not the stray's thread.
      {:ok, %{peer_thread_id: peer_thread_id}} =
        Consult.consult_peer(caller(caller_thread, me), "claude", "are you there?")

      assert peer_thread_id == peer_thread.id
      assert [%Message{body: "are you there?"}] = Channel.thread_messages(peer_thread)
    end
  end

  describe "maybe_mirror/1 — the bidirectional bridge" do
    setup do
      {:ok, caller_thread} = Channel.open_thread(%{title: "caller's work"})
      {:ok, peer_thread} = Channel.open_thread(%{title: "peer's work"})
      {:ok, me} = Staff.register_agent(%{name: "pi", mandate: "ask", engine: "fresh"})
      {:ok, claude} = Staff.register_agent(%{name: "claude", mandate: "answer", engine: "fresh"})
      {:ok, _} = Staff.assign(peer_thread, claude)
      {:ok, _} = Staff.start_session(%{agent_id: claude.id, thread_id: peer_thread.id, pane_ref: "wClaude"})

      {:ok, %{consult_id: consult_id}} =
        Consult.consult_peer(caller(caller_thread, me), "claude", "is this sound?")

      %{caller_thread: caller_thread, peer_thread: peer_thread, consult_id: consult_id}
    end

    test "the peer's reply mirrors back to the caller's thread, authored as the peer", ctx do
      [ask] = Channel.thread_messages(ctx.peer_thread)

      # The peer answers on its own thread, replying to the ask.
      {:ok, reply} =
        Channel.post(%{
          thread_id: ctx.peer_thread.id,
          author: "claude",
          body: "yes, sound",
          reply_to: ask.id
        })

      Consult.maybe_mirror(reply)

      # The answer lands on the CALLER's thread, authored as the peer, same consult_id.
      [mirrored] = Channel.thread_messages(ctx.caller_thread)
      assert mirrored.author == "claude"
      assert mirrored.body == "yes, sound"
      assert mirrored.consult_id == ctx.consult_id
      assert mirrored.mirrored
    end

    test "the caller's follow-up mirrors forward to the peer — the bridge runs both ways", ctx do
      [ask] = Channel.thread_messages(ctx.peer_thread)
      {:ok, reply} = Channel.post(%{thread_id: ctx.peer_thread.id, author: "claude", body: "yes", reply_to: ask.id})
      Consult.maybe_mirror(reply)
      [mirrored] = Channel.thread_messages(ctx.caller_thread)

      # The caller replies to the mirrored answer on its own thread.
      {:ok, followup} =
        Channel.post(%{
          thread_id: ctx.caller_thread.id,
          author: "pi",
          body: "and the tradeoff?",
          reply_to: mirrored.id
        })

      Consult.maybe_mirror(followup)

      # The follow-up is mirrored FORWARD to the peer's thread, authored as the caller.
      peer_msgs = Channel.thread_messages(ctx.peer_thread)
      assert Enum.any?(peer_msgs, &(&1.body == "and the tradeoff?" and &1.author == "pi" and &1.mirrored))
    end

    test "echo guard: a mirrored message is never re-mirrored (no infinite loop)", ctx do
      [ask] = Channel.thread_messages(ctx.peer_thread)
      {:ok, reply} = Channel.post(%{thread_id: ctx.peer_thread.id, author: "claude", body: "yes", reply_to: ask.id})
      Consult.maybe_mirror(reply)
      [mirrored] = Channel.thread_messages(ctx.caller_thread)

      # Feeding the mirrored message back to the mirror must be a no-op — the echo guard.
      assert Consult.maybe_mirror(mirrored) == :ok

      # And no second copy appeared on either side: the caller still has exactly the one
      # mirrored answer, and the peer still has exactly the ask + its reply.
      assert length(Channel.thread_messages(ctx.caller_thread)) == 1
      assert length(Channel.thread_messages(ctx.peer_thread)) == 2
    end

    test "a reply to a non-consult message is not mirrored", ctx do
      {:ok, unrelated} = Channel.post(%{thread_id: ctx.peer_thread.id, author: "claude", body: "unrelated"})

      {:ok, reply} =
        Channel.post(%{thread_id: ctx.peer_thread.id, author: "claude", body: "reply", reply_to: unrelated.id})

      assert Consult.maybe_mirror(reply) == :ok
      assert Channel.thread_messages(ctx.caller_thread) == []
    end
  end

  describe "the mirror server — bus wiring" do
    test "a posted consult reply is mirrored back through the server's handle_info", _ctx do
      {:ok, caller_thread} = Channel.open_thread(%{title: "caller's work"})
      {:ok, peer_thread} = Channel.open_thread(%{title: "peer's work"})
      {:ok, me} = Staff.register_agent(%{name: "pi", mandate: "ask", engine: "fresh"})
      {:ok, claude} = Staff.register_agent(%{name: "claude", mandate: "answer", engine: "fresh"})
      {:ok, _} = Staff.assign(peer_thread, claude)
      {:ok, _} = Staff.start_session(%{agent_id: claude.id, thread_id: peer_thread.id, pane_ref: "wClaude"})

      {:ok, %{consult_id: _}} = Consult.consult_peer(caller(caller_thread, me), "claude", "sound?")
      [ask] = Channel.thread_messages(peer_thread)

      # The peer answers. Start the mirror server AFTER the reply is posted, so the bus (no
      # subscriber yet) does not deliver it; then hand the message to the server's handle_info
      # directly. This proves the server wiring deterministically — no async PubSub timing.
      {:ok, reply} = Channel.post(%{thread_id: peer_thread.id, author: "claude", body: "yes", reply_to: ask.id})
      start_supervised!({Mirror, []})
      send(Mirror, {:message_posted, reply})

      # The server processes synchronously in handle_info; poll briefly for the mirrored copy.
      assert wait_for(fn -> length(Channel.thread_messages(caller_thread)) == 1 end)
      [mirrored] = Channel.thread_messages(caller_thread)
      assert mirrored.author == "claude"
      assert mirrored.body == "yes"
      assert mirrored.mirrored
    end
  end

  # Poll a predicate with a generous timeout — the only timing seam in the suite, and it is
  # bounded (a GenServer handle_info reacts in milliseconds, so 2s is far more than enough).
  defp wait_for(pred, attempts \\ 200) do
    cond do
      pred.() ->
        true

      attempts <= 0 ->
        false

      true ->
        Process.sleep(10)
        wait_for(pred, attempts - 1)
    end
  end
end
