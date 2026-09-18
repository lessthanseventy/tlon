defmodule Server.MemoryTurnPassTest do
  # Worklines slice 5: the post-response memory pass — event-shaped (presence_idle), off the
  # latency path, replacing turn-count nudges. A cheap extractor turns a completed turn's
  # messages into 0..3 banked facts; guards keep it from firing on every idle. One-brain E/2:
  # the pass is a job — `schedule/1` enqueues it (unique per thread), `run/2` performs it, and
  # where it stopped is a column on the thread.
  use ExUnit.Case, async: false
  use Oban.Testing, repo: Server.Repo

  alias Server.Channel
  alias Server.Fact
  alias Server.Jobs
  alias Server.Memory.Extractor
  alias Server.Memory.TurnPass
  alias Server.Repo
  alias Server.Thread

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

  test "a pass after enough new messages banks the extractor's facts and stamps the thread" do
    thread = thread_with_messages(3)

    assert :ok = TurnPass.run(thread.id, extractor: StubExtractor, min_messages: 3)

    assert [fact] = Repo.all(Fact)
    assert fact.text == "reuse the composer wrap"
    assert fact.provenance == "derived"
    assert fact.thread_id == thread.id
    assert Repo.get!(Thread, thread.id).memory_pass_last_id == Repo.aggregate(Server.Message, :max, :id)
  end

  test "too few new messages → no extraction" do
    thread = thread_with_messages(1)

    assert :ok = TurnPass.run(thread.id, extractor: StubExtractor, min_messages: 3)

    assert Repo.all(Fact) == []
  end

  test "already-extracted messages don't re-extract on the next pass" do
    thread = thread_with_messages(3)

    :ok = TurnPass.run(thread.id, extractor: StubExtractor, min_messages: 3)
    :ok = TurnPass.run(thread.id, extractor: StubExtractor, min_messages: 3)

    assert length(Repo.all(Fact)) == 1
  end

  test "machine-authored process text (briefs, nags) neither counts nor extracts" do
    {:ok, thread} = Channel.open_thread(%{title: "briefs only"})

    for n <- 1..3 do
      {:ok, _} = Channel.post(%{thread_id: thread.id, author: "tlon", body: "▶ STAGE #{n} — workline x"})
    end

    :ok = TurnPass.run(thread.id, extractor: StubExtractor, min_messages: 3)

    assert Repo.all(Fact) == []
  end

  test "an empty extraction is a quiet no-op" do
    thread = thread_with_messages(3)

    :ok = TurnPass.run(thread.id, extractor: EmptyExtractor, min_messages: 1)

    assert Repo.all(Fact) == []
  end

  test "an unknown thread is a no-op" do
    assert :ok = TurnPass.run(0, extractor: StubExtractor, min_messages: 1)
  end

  describe "schedule/1" do
    setup do
      previous = Application.get_env(:server, :memory_pass)
      on_exit(fn -> Application.put_env(:server, :memory_pass, previous) end)
      :ok
    end

    test "with the pass off, nothing is queued" do
      Application.put_env(:server, :memory_pass, false)
      assert {:error, :memory_pass_off} = TurnPass.schedule(7)
    end

    test "with the pass on but no Oban on this node, an honest error — never an exit" do
      Application.put_env(:server, :memory_pass, true)
      assert {:error, :no_oban} = TurnPass.schedule(7)
    end

    test "with Oban up, one job per thread per interval — a burst of idles is one pass" do
      Application.put_env(:server, :memory_pass, true)
      start_supervised!({Oban, Application.fetch_env!(:server, Oban)})
      thread = thread_with_messages(3)

      assert {:ok, %Oban.Job{conflict?: false}} = TurnPass.schedule(thread.id)
      assert {:ok, %Oban.Job{conflict?: true}} = TurnPass.schedule(thread.id)
      assert_enqueued(worker: Jobs.TurnPass, args: %{thread_id: thread.id})
      assert [_one] = all_enqueued(worker: Jobs.TurnPass)
    end
  end
end
