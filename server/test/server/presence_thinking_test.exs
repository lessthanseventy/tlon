defmodule Server.Presence.ThinkingTest do
  # The explicit half of presence: a harness declares thinking at turn start and idle at
  # turn end. In-memory store + sweep + Bus liveness, and the session row's durable mark.
  use ExUnit.Case, async: false

  alias Server.Bus
  alias Server.Presence.Thinking

  defp start_store(opts) do
    name = :"thinking_#{System.unique_integer([:positive])}"
    start_supervised!({Thinking, Keyword.put(opts, :name, name)})
    name
  end

  test "thinking marks the agent's live session mid-turn; idle (or the sweep) clears it" do
    Server.TestDB.clean!()
    store = start_store(max_seconds: 0)
    {:ok, t} = Server.Channel.open_thread(%{title: "marked"})
    {:ok, a} = Server.Staff.register_agent(%{name: "hronir", mandate: "m", engine: "pi"})
    {:ok, s} = Server.Staff.start_session(%{agent_id: a.id, thread_id: t.id})
    mark = fn -> Server.Repo.get!(Server.Session, s.id).thinking_since end

    Thinking.thinking(store, t.id, "hronir")
    assert %DateTime{} = mark.()
    Thinking.idle(store, t.id, "hronir")
    assert mark.() == nil

    Thinking.thinking(store, t.id, "hronir")
    Thinking.sweep(store)
    assert mark.() == nil
  end

  test "thinking registers an entry readable per-thread and across all threads" do
    store = start_store([])

    Thinking.thinking(store, 7, "hronir")
    Thinking.thinking(store, 9, "tertius")

    assert [%{agent: "hronir", started_at: %DateTime{}}] = Thinking.thinking_for(store, 7)
    assert %{7 => [%{agent: "hronir"}], 9 => [%{agent: "tertius"}]} = Thinking.thinking_all(store)
  end

  test "idle clears the entry; a thread with nobody thinking reads empty" do
    store = start_store([])

    Thinking.thinking(store, 7, "hronir")
    Thinking.idle(store, 7, "hronir")

    assert Thinking.thinking_for(store, 7) == []
    assert Thinking.thinking_all(store) == %{}
  end

  test "idle for an agent that never declared thinking is a harmless no-op" do
    store = start_store([])

    assert :ok = Thinking.idle(store, 7, "hronir")
    assert Thinking.thinking_for(store, 7) == []
  end

  test "two agents thinking on one thread both read back" do
    store = start_store([])

    Thinking.thinking(store, 7, "hronir")
    Thinking.thinking(store, 7, "tertius")

    assert ["hronir", "tertius"] =
             store |> Thinking.thinking_for(7) |> Enum.map(& &1.agent) |> Enum.sort()
  end

  test "thinking and idle broadcast on funes:presence and the thread topic" do
    store = start_store([])
    Bus.subscribe_presence()
    Bus.subscribe_thread(7)

    Thinking.thinking(store, 7, "hronir")

    assert_received {:presence_thinking, %{thread_id: 7, agent: "hronir", started_at: %DateTime{}}}
    assert_received {:presence_thinking, %{thread_id: 7, agent: "hronir"}}

    Thinking.idle(store, 7, "hronir")

    assert_received {:presence_idle, %{thread_id: 7, agent: "hronir"}}
    assert_received {:presence_idle, %{thread_id: 7, agent: "hronir"}}
  end

  test "the sweep clears entries older than the max and announces them idle" do
    store = start_store(max_seconds: 0)
    Bus.subscribe_presence()

    Thinking.thinking(store, 7, "hronir")
    assert_received {:presence_thinking, _}

    Thinking.sweep(store)

    assert Thinking.thinking_for(store, 7) == []
    assert_received {:presence_idle, %{thread_id: 7, agent: "hronir"}}
  end

  test "the sweep keeps entries younger than the max" do
    store = start_store(max_seconds: 3600)

    Thinking.thinking(store, 7, "hronir")
    Thinking.sweep(store)

    assert [%{agent: "hronir"}] = Thinking.thinking_for(store, 7)
  end
end
