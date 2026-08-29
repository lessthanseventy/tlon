defmodule Server.MemoryTurnPassTest do
  # Worklines slice 5: the post-response memory pass — event-shaped (presence_idle), off the
  # latency path, replacing turn-count nudges. A cheap extractor turns a completed turn's
  # messages into 0..3 banked facts; guards keep it from firing on every idle.
  use ExUnit.Case, async: false

  alias Server.Channel
  alias Server.Fact
  alias Server.Memory.Extractor
  alias Server.Memory.TurnPass
  alias Server.Repo

  defmodule StubExtractor do
    @moduledoc false
    @behaviour Extractor

    @impl true
    def extract(_messages, _existing_facts) do
      {:ok, [%{kind: "decision", text: "reuse the composer wrap", intent: "memory-pass"}]}
    end
  end

  defmodule EmptyExtractor do
    @moduledoc false
    @behaviour Extractor

    @impl true
    def extract(_messages, _existing), do: {:ok, []}
  end

  setup do
    Server.TestDB.clean!()
    :ok
  end

  defp thread_with_messages(count) do
    {:ok, thread} = Channel.open_thread(%{title: "turn pass"})

    for n <- 1..count do
      {:ok, _} = Channel.post(%{thread_id: thread.id, author: "hronir-machine", body: "message #{n}"})
    end

    thread
  end

  defp start_pass(opts) do
    start_supervised!({TurnPass, Keyword.merge([name: nil, subscribe: false, min_interval_ms: 0], opts)})
  end

  test "an idle after enough new messages banks the extractor's facts" do
    thread = thread_with_messages(3)
    pass = start_pass(extractor: StubExtractor, min_messages: 3)

    send(pass, {:presence_idle, %{thread_id: thread.id, agent: "hronir-machine"}})
    :ok = TurnPass.drain(pass)

    assert [fact] = Repo.all(Fact)
    assert fact.text == "reuse the composer wrap"
    assert fact.provenance == "derived"
    assert fact.thread_id == thread.id
  end

  test "too few new messages → no extraction" do
    thread = thread_with_messages(1)
    pass = start_pass(extractor: StubExtractor, min_messages: 3)

    send(pass, {:presence_idle, %{thread_id: thread.id, agent: "a"}})
    :ok = TurnPass.drain(pass)

    assert Repo.all(Fact) == []
  end

  test "the per-thread interval guard suppresses a rapid second pass" do
    thread = thread_with_messages(3)
    pass = start_pass(extractor: StubExtractor, min_messages: 1, min_interval_ms: 60_000)

    send(pass, {:presence_idle, %{thread_id: thread.id, agent: "a"}})
    :ok = TurnPass.drain(pass)
    {:ok, _} = Channel.post(%{thread_id: thread.id, author: "a", body: "more"})
    send(pass, {:presence_idle, %{thread_id: thread.id, agent: "a"}})
    :ok = TurnPass.drain(pass)

    assert length(Repo.all(Fact)) == 1
  end

  test "already-extracted messages don't re-extract on the next idle" do
    thread = thread_with_messages(3)
    pass = start_pass(extractor: StubExtractor, min_messages: 3)

    send(pass, {:presence_idle, %{thread_id: thread.id, agent: "a"}})
    :ok = TurnPass.drain(pass)
    send(pass, {:presence_idle, %{thread_id: thread.id, agent: "a"}})
    :ok = TurnPass.drain(pass)

    assert length(Repo.all(Fact)) == 1
  end

  test "machine-authored process text (briefs, nags) neither counts nor extracts" do
    {:ok, thread} = Channel.open_thread(%{title: "briefs only"})

    for n <- 1..3 do
      {:ok, _} = Channel.post(%{thread_id: thread.id, author: "funes", body: "▶ STAGE #{n} — workline x"})
    end

    pass = start_pass(extractor: StubExtractor, min_messages: 3)
    send(pass, {:presence_idle, %{thread_id: thread.id, agent: "a"}})
    :ok = TurnPass.drain(pass)

    assert Repo.all(Fact) == []
  end

  test "an empty extraction is a quiet no-op" do
    thread = thread_with_messages(3)
    pass = start_pass(extractor: EmptyExtractor, min_messages: 1)

    send(pass, {:presence_idle, %{thread_id: thread.id, agent: "a"}})
    :ok = TurnPass.drain(pass)

    assert Repo.all(Fact) == []
  end
end
