defmodule Server.BusTest do
  # The reactive substrate (aleph §5): typed events routed to focused topics so the
  # board can subscribe to one thread (IN SCOPE) or the roster (IN FLIGHT) rather
  # than filtering a firehose. Pure PubSub — no DB.
  use ExUnit.Case, async: false

  alias Server.Bus

  test "a posted message reaches both the firehose and its thread topic" do
    Bus.subscribe_messages()
    Bus.subscribe_thread(7)
    msg = %{id: 1, thread_id: 7}

    Bus.broadcast({:message_posted, msg})

    # Once from the firehose (the switchboard's stream), once from thread 7 (IN SCOPE).
    assert_received {:message_posted, ^msg}
    assert_received {:message_posted, ^msg}
    refute_received {:message_posted, _}
  end

  test "a thread-scoped dossier event reaches only its own thread topic" do
    Bus.subscribe_thread(7)
    Bus.subscribe_thread(8)
    fact = %{thread_id: 7}

    Bus.broadcast({:fact_banked, fact})

    assert_received {:fact_banked, ^fact}
    refute_received {:fact_banked, _}
  end

  test "an unscoped event (nil thread_id) broadcasts nowhere, without crashing" do
    Bus.subscribe_thread(7)
    Bus.subscribe_messages()

    assert Bus.broadcast({:fact_banked, %{thread_id: nil}}) == :ok

    refute_received {:fact_banked, _}
  end

  test "a thread lifecycle event reaches the threads topic and the thread topic" do
    Bus.subscribe_threads()
    Bus.subscribe_thread(7)
    thread = %{id: 7}

    Bus.broadcast({:thread_assigned, thread})

    assert_received {:thread_assigned, ^thread}
    assert_received {:thread_assigned, ^thread}
    refute_received {:thread_assigned, _}
  end

  test "a session lifecycle event reaches the sessions/roster topic and the thread topic" do
    Bus.subscribe_sessions()
    Bus.subscribe_thread(7)
    session = %{id: 1, thread_id: 7}

    Bus.broadcast({:session_started, session})

    assert_received {:session_started, ^session}
    assert_received {:session_started, ^session}
    refute_received {:session_started, _}
  end

  test "durable-write events also reach the global activity topic, regardless of thread" do
    Bus.subscribe_activity()
    fact = %{thread_id: 7}
    event = %{thread_id: 42}
    msg = %{id: 1, thread_id: 99}

    Bus.broadcast({:fact_banked, fact})
    Bus.broadcast({:event_recorded, event})
    Bus.broadcast({:message_posted, msg})

    assert_received {:fact_banked, ^fact}
    assert_received {:event_recorded, ^event}
    assert_received {:message_posted, ^msg}
  end
end
