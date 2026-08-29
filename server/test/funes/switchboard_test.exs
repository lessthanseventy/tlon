defmodule Server.SwitchboardTest do
  # The switchboard's liveness layer (§10, §5b.2, aleph §6), addressed-delivery
  # model (aleph §2): a message wakes who it is addressed to — the thread's LEAD for
  # a plain post, an @mentioned coworker, or the author of a replied-to message —
  # never the whole room. The DB stays the truth (delivered_at is durable).
  use ExUnit.Case, async: false

  alias Server.Channel
  alias Server.Message
  alias Server.Presence.Engine.Manual
  alias Server.Repo
  alias Server.Staff
  alias Server.Switchboard
  alias Server.Switchboard.Runner

  setup do
    Application.put_env(:server, :arbiter, Server.Arbiter.Test)
    Application.put_env(:server, :test_pid, self())

    on_exit(fn ->
      Application.delete_env(:server, :arbiter)
      Application.delete_env(:server, :test_pid)
    end)

    Server.TestDB.clean!()
    :ok
  end

  # Sandra is the thread's lead (orchestrator); Robert is a coworker on it. Both live.
  defp staffed_thread do
    {:ok, thread} = Channel.open_thread(%{title: "review PR 329"})

    {:ok, sandra} =
      Staff.register_agent(%{name: "Sandra", mandate: "orchestrator", engine: "deep"})

    {:ok, robert} = Staff.register_agent(%{name: "Robert", mandate: "reviewer", engine: "fresh"})
    {:ok, _} = Staff.assign(thread, sandra)

    {:ok, ss} =
      Staff.start_session(%{agent_id: sandra.id, thread_id: thread.id, pane_ref: "wSandra"})

    {:ok, rs} =
      Staff.start_session(%{agent_id: robert.id, thread_id: thread.id, pane_ref: "wRobert"})

    %{thread: thread, sandra: sandra, robert: robert, sandra_session: ss, robert_session: rs}
  end

  defp set_last_active(session, seconds_ago) do
    at = DateTime.utc_now() |> DateTime.shift(second: -seconds_ago) |> DateTime.truncate(:second)
    {:ok, updated} = session |> Ecto.Changeset.change(last_active_at: at) |> Repo.update()
    updated
  end

  describe "addressed delivery — who a message wakes (aleph §2)" do
    test "a plain top-level post wakes ONLY the lead, not the rest of the room" do
      %{thread: thread} = staffed_thread()

      {:ok, m} =
        Channel.post(%{thread_id: thread.id, author: "stakeholder", body: "how's it going?"})

      Switchboard.deliver(m)

      assert_received {:woke, "wSandra", _}
      refute_received {:woke, "wRobert", _}
    end

    test "the lead's own top-level post wakes no agent — it is a report up to the human" do
      %{thread: thread} = staffed_thread()
      {:ok, m} = Channel.post(%{thread_id: thread.id, author: "Sandra", body: "shipped the fix"})
      Switchboard.deliver(m)

      refute_received {:woke, _, _}
    end

    test "an @mention wakes that coworker, not the lead" do
      %{thread: thread} = staffed_thread()

      {:ok, m} =
        Channel.post(%{
          thread_id: thread.id,
          author: "stakeholder",
          body: "@Robert can you check CI?"
        })

      Switchboard.deliver(m)

      assert_received {:woke, "wRobert", _}
      refute_received {:woke, "wSandra", _}
    end

    test "a reply wakes the author of the message it answers" do
      %{thread: thread} = staffed_thread()
      {:ok, parent} = Channel.post(%{thread_id: thread.id, author: "Robert", body: "CI is red"})
      flush()

      {:ok, reply} =
        Channel.post(%{
          thread_id: thread.id,
          author: "stakeholder",
          body: "thanks — fix it?",
          reply_to: parent.id
        })

      Switchboard.deliver(reply)

      assert_received {:woke, "wRobert", _}
      refute_received {:woke, "wSandra", _}
    end

    test "a wrong-case @mention still reaches the coworker, not the lead" do
      %{thread: thread} = staffed_thread()

      {:ok, m} =
        Channel.post(%{thread_id: thread.id, author: "stakeholder", body: "hey @robert ping"})

      Switchboard.deliver(m)

      assert_received {:woke, "wRobert", _}
      refute_received {:woke, "wSandra", _}
    end

    test "a reply to a mis-cased author still reaches them (case-insensitive seam)" do
      # Robert posts under a lowercase handle; a reply must still wake agent "Robert",
      # not silently drop because author matching was case-sensitive.
      %{thread: thread} = staffed_thread()
      {:ok, parent} = Channel.post(%{thread_id: thread.id, author: "robert", body: "CI is red"})
      flush()

      {:ok, reply} =
        Channel.post(%{
          thread_id: thread.id,
          author: "stakeholder",
          body: "on it",
          reply_to: parent.id
        })

      Switchboard.deliver(reply)
      assert_received {:woke, "wRobert", _}
    end

    test "an @handle that names no agent falls back to the lead (never suppresses it)" do
      %{thread: thread} = staffed_thread()

      {:ok, m} =
        Channel.post(%{thread_id: thread.id, author: "stakeholder", body: "@nobody are we good?"})

      Switchboard.deliver(m)

      assert_received {:woke, "wSandra", _}
      refute_received {:woke, "wRobert", _}
    end

    test "an ended session is not woken — @mention a coworker who clocked out" do
      %{thread: thread} = staffed_thread()
      robert_session = Staff.session_for_thread(thread)
      assert robert_session.pane_ref == "wRobert"
      {:ok, _} = Staff.end_session(robert_session)

      {:ok, m} =
        Channel.post(%{thread_id: thread.id, author: "stakeholder", body: "@Robert you there?"})

      Switchboard.deliver(m)

      refute_received {:woke, "wRobert", _}
    end
  end

  describe "warmth-gating the wake (§3b)" do
    test "a session gone COLD is not woken — a poke would pay full re-ingestion" do
      %{thread: thread, sandra_session: ss} = staffed_thread()
      # Sandra's context went cold: last active two hours ago, past the ~1h window.
      set_last_active(ss, 7200)

      {:ok, m} = Channel.post(%{thread_id: thread.id, author: "stakeholder", body: "you there?"})
      Switchboard.deliver(m)

      refute_received {:woke, "wSandra", _}
      # Nothing was woken, so it is not a delivery — it stays pending.
      assert Repo.get!(Message, m.id).delivered_at == nil
    end

    test "a still-warm session is woken and its warmth is bumped forward" do
      %{thread: thread, sandra_session: ss} = staffed_thread()
      warm = set_last_active(ss, 1800).last_active_at

      {:ok, m} = Channel.post(%{thread_id: thread.id, author: "stakeholder", body: "hi"})
      Switchboard.deliver(m)

      assert_received {:woke, "wSandra", _}
      bumped = Repo.get!(Server.Session, ss.id).last_active_at
      assert DateTime.after?(bumped, warm)
    end

    test "draining an OLD backlog message never cools a warmer author (forward-only)" do
      %{thread: thread, sandra_session: ss} = staffed_thread()
      # Sandra is warm now, but authored a note whose timestamp is two hours old.
      {:ok, m} = Channel.post(%{thread_id: thread.id, author: "Sandra", body: "old note"})
      old = DateTime.utc_now() |> DateTime.shift(hour: -2) |> DateTime.truncate(:second)
      {:ok, _} = m |> Ecto.Changeset.change(created_at: old) |> Repo.update()

      warm_before = Repo.get!(Server.Session, ss.id).last_active_at
      flush()

      Switchboard.drain()

      # touch_author is forward-only: the stale message must not drag Sandra's warmth
      # back two hours and strand her as "cold."
      assert Repo.get!(Server.Session, ss.id).last_active_at == warm_before
    end

    test "a proactive post keeps its author warm even though no one is woken" do
      # The lead posts a report (top-level, author = the lead): nobody is woken, but
      # authoring is a turn, so the lead's own session stays warm.
      %{thread: thread, sandra_session: ss} = staffed_thread()
      warm = set_last_active(ss, 1800).last_active_at

      {:ok, m} = Channel.post(%{thread_id: thread.id, author: "Sandra", body: "shipped it"})
      Switchboard.deliver(m)

      refute_received {:woke, _, _}
      bumped = Repo.get!(Server.Session, ss.id).last_active_at
      assert DateTime.after?(bumped, warm)
    end
  end

  describe "engine-credit presence — the other half of clocked-out (§3b)" do
    setup do
      # A pluggable engine-presence backend (§8: vendor lives in the backend, never the
      # design). The Test impl reads a set of clocked-out engine handles from app env.
      Application.put_env(:server, :engine_presence, Manual)

      on_exit(fn ->
        Application.delete_env(:server, :engine_presence)
        Application.delete_env(:server, :clocked_out_engines)
      end)

      :ok
    end

    test "a WARM session whose engine is clocked out is not woken — the scarce-bucket guard" do
      %{thread: thread, sandra_session: ss} = staffed_thread()
      # Sandra is freshly warm, but her engine ("deep") is out of credits / past its
      # rate-limit window — poking it would burn the wrong bucket for a full re-ingestion.
      set_last_active(ss, 60)
      Application.put_env(:server, :clocked_out_engines, ["deep"])

      {:ok, m} = Channel.post(%{thread_id: thread.id, author: "stakeholder", body: "you there?"})
      Switchboard.deliver(m)

      refute_received {:woke, "wSandra", _}
      # No live+available recipient, so it is not a delivery — it stays pending for drain.
      assert Repo.get!(Message, m.id).delivered_at == nil
    end

    test "a coworker on an AVAILABLE engine is still woken while another's engine is clocked out" do
      %{thread: thread, robert_session: rs} = staffed_thread()
      set_last_active(rs, 60)
      # "deep" is Sandra's engine; Robert's is "fresh" and available.
      Application.put_env(:server, :clocked_out_engines, ["deep"])

      {:ok, m} = Channel.post(%{thread_id: thread.id, author: "stakeholder", body: "@Robert ping"})
      Switchboard.deliver(m)

      assert_received {:woke, "wRobert", _}
    end

    test "absent config, every engine is available — the default degrades honestly" do
      %{thread: thread, sandra_session: ss} = staffed_thread()
      set_last_active(ss, 60)
      # No :clocked_out_engines set → Test impl treats none as clocked out.

      {:ok, m} = Channel.post(%{thread_id: thread.id, author: "stakeholder", body: "hi"})
      Switchboard.deliver(m)

      assert_received {:woke, "wSandra", _}
    end
  end

  describe "delivered ≠ a file (§5b.3)" do
    test "marks delivered once the addressee was woken" do
      %{thread: thread} = staffed_thread()
      {:ok, m} = Channel.post(%{thread_id: thread.id, author: "stakeholder", body: "hi"})
      assert m.delivered_at == nil

      Switchboard.deliver(m)
      assert %DateTime{} = Repo.get!(Message, m.id).delivered_at
    end

    test "a message no live addressee can receive stays undelivered (the spawned session delivers it)" do
      # A thread with a lead assigned but whose session hasn't started: nobody live to
      # WAKE, so the post is pending — but the autonomous spawn (§4c.3) opens a pane, and
      # the message is delivered once that session registers and drains, not by this call.
      {:ok, thread} = Channel.open_thread(%{title: "unattended"})
      {:ok, sandra} = Staff.register_agent(%{name: "Sandra", mandate: "lead", engine: "deep"})
      {:ok, _} = Staff.assign(thread, sandra)

      {:ok, m} = Channel.post(%{thread_id: thread.id, author: "stakeholder", body: "anyone?"})
      Switchboard.deliver(m)

      refute_received {:woke, _, _}
      assert Repo.get!(Message, m.id).delivered_at == nil
    end
  end

  describe "autonomous cold-thread spawn — the lead is absent (§4c.3)" do
    # The switchboard's own answer to a thread whose lead isn't running: spawn a fresh pane
    # (the mechanism the `s` verb also uses), so a message to an unattended thread wakes
    # someone instead of waiting for the human. Gated hard: never a clocked-out engine, never
    # a double-spawn over a live session.
    test "a message to a thread whose LEAD has no live session spawns a fresh pane for it" do
      {:ok, thread} = Channel.open_thread(%{title: "cold thread"})
      {:ok, carl} = Staff.register_agent(%{name: "Carl", mandate: "review", engine: "fresh"})
      {:ok, _} = Staff.assign(thread, carl)
      # No session was ever started — the thread is staffed but not running.

      {:ok, m} = Channel.post(%{thread_id: thread.id, author: "stakeholder", body: "please review"})
      assert {:pending, _} = Switchboard.deliver(m)

      # the arbiter was asked to open a pane carrying Carl's identity on this thread
      assert_received {:spawned, exports}
      assert exports =~ ~s(TLON_AUTHOR="Carl")
      assert exports =~ ~s(TLON_THREAD="#{thread.id}")
    end

    test "a clocked-out lead is NOT spawned — a fresh session it can't run is worse than waiting" do
      Application.put_env(:server, :engine_presence, Manual)
      on_exit(fn -> Application.delete_env(:server, :engine_presence) end)

      {:ok, thread} = Channel.open_thread(%{title: "cold thread"})
      {:ok, carl} = Staff.register_agent(%{name: "Carl", mandate: "review", engine: "claude"})
      {:ok, _} = Staff.assign(thread, carl)
      Application.put_env(:server, :clocked_out_engines, ["claude"])
      on_exit(fn -> Application.delete_env(:server, :clocked_out_engines) end)

      {:ok, m} = Channel.post(%{thread_id: thread.id, author: "stakeholder", body: "review?"})
      Switchboard.deliver(m)

      refute_received {:spawned, _}
    end

    test "a lead with a live (even cold) session is not auto-spawned — no zombie double-spawn" do
      {:ok, thread} = Channel.open_thread(%{title: "cold but attended"})
      {:ok, carl} = Staff.register_agent(%{name: "Carl", mandate: "review", engine: "fresh"})
      {:ok, _} = Staff.assign(thread, carl)
      {:ok, sess} = Staff.start_session(%{agent_id: carl.id, thread_id: thread.id, pane_ref: "wCarl"})
      set_last_active(sess, 7200)

      {:ok, m} = Channel.post(%{thread_id: thread.id, author: "stakeholder", body: "hi"})
      Switchboard.deliver(m)

      # cold → not poked, and a live session already exists → not re-spawned.
      refute_received {:woke, _, _}
      refute_received {:spawned, _}
    end

    test "an @mention of an absent coworker does not spawn the LEAD (only the addressed lead spawns)" do
      {:ok, thread} = Channel.open_thread(%{title: "t"})
      {:ok, carl} = Staff.register_agent(%{name: "Carl", mandate: "lead", engine: "fresh"})
      {:ok, _} = Staff.assign(thread, carl)
      {:ok, ss} = Staff.start_session(%{agent_id: carl.id, thread_id: thread.id, pane_ref: "wCarl"})
      set_last_active(ss, 60)
      {:ok, _dana} = Staff.register_agent(%{name: "Dana", mandate: "review", engine: "fresh"})

      # @Dana (absent coworker) is addressed, not the lead — the lead must not be spawned.
      {:ok, m} = Channel.post(%{thread_id: thread.id, author: "stakeholder", body: "@Dana take a look"})
      Switchboard.deliver(m)

      refute_received {:spawned, _}
    end
  end

  describe "drain/0 — durability + coalescing (§10)" do
    test "delivers a backlog posted while nothing was listening" do
      %{thread: thread} = staffed_thread()
      {:ok, m1} = Channel.post(%{thread_id: thread.id, author: "stakeholder", body: "one"})
      {:ok, m2} = Channel.post(%{thread_id: thread.id, author: "stakeholder", body: "two"})
      flush()

      Switchboard.drain()

      assert %DateTime{} = Repo.get!(Message, m1.id).delivered_at
      assert %DateTime{} = Repo.get!(Message, m2.id).delivered_at
    end

    test "coalesces a backlog into ONE wake per pane — the burst guard" do
      %{thread: thread} = staffed_thread()

      for body <- ["one", "two", "three"] do
        {:ok, _} = Channel.post(%{thread_id: thread.id, author: "stakeholder", body: body})
      end

      flush()
      Switchboard.drain()

      # Three top-level posts all address the lead — Sandra is woken exactly once.
      assert_received {:woke, "wSandra", _}
      refute_received {:woke, "wSandra", _}
    end
  end

  describe "Runner — the reactive live path over PubSub" do
    test "a posted message wakes its addressee without anyone calling deliver" do
      %{thread: thread} = staffed_thread()
      start_supervised!(Runner)

      {:ok, _} = Channel.post(%{thread_id: thread.id, author: "stakeholder", body: "live!"})

      assert_receive {:woke, "wSandra", _}, 1000
    end

    test "on start it drains a backlog posted while it was down (§10 durability)" do
      %{thread: thread} = staffed_thread()

      {:ok, m} =
        Channel.post(%{thread_id: thread.id, author: "stakeholder", body: "left for you"})

      flush()
      assert Repo.get!(Message, m.id).delivered_at == nil

      start_supervised!(Runner)
      assert_receive {:woke, "wSandra", _}, 1000
      assert %DateTime{} = Repo.get!(Message, m.id).delivered_at
    end
  end

  defp flush do
    receive do
      _ -> flush()
    after
      0 -> :ok
    end
  end
end
