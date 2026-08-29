defmodule Server.WorklineTest do
  # Worklines slice 1: the stage state machine. intent → spec → plan → build → verify →
  # review → merged, advancing only past a committed owed artifact (checker is a behaviour —
  # stubs here, git in the default impl), gating on spec→plan, review→merged, and
  # machine-born intents. The DB is the bus: every assertion reads back through SQLite.
  use ExUnit.Case, async: false

  alias Server.Channel
  alias Server.Event
  alias Server.Repo
  alias Server.Thread
  alias Server.Workline
  alias Server.Workline.Artifacts

  defmodule AllPresent do
    @moduledoc false
    @behaviour Artifacts

    @impl true
    def check(_thread, {:file, name}), do: {:ok, "committed #{name}"}
    def check(_thread, :branch), do: {:ok, "work/x @ abc123"}
    def check(_thread, :checks), do: {:ok, "1 verify check_passed"}
  end

  defmodule NonePresent do
    @moduledoc false
    @behaviour Artifacts

    @impl true
    def check(_thread, requirement), do: {:error, "missing #{inspect(requirement)}"}
  end

  setup do
    Server.TestDB.clean!()
    :ok
  end

  defp open!(attrs \\ %{}) do
    {:ok, thread} = Workline.open(Map.merge(%{title: "fix the composer", slug: "composer-wrap"}, attrs))
    thread
  end

  test "open starts a workline at intent, operator-born, machine-scoped" do
    thread = open!()
    assert thread.stage == "intent"
    assert thread.slug == "composer-wrap"
    assert thread.born == "operator"
    assert thread.state == "open"
    assert thread.scope == "machine"
  end

  test "advance refuses without the owed artifact — the invariant advance_stage carries" do
    thread = open!()
    assert {:error, {:artifact_missing, reason}} = Workline.advance(thread, artifacts: NonePresent)
    assert reason =~ "intent.md"
    assert Repo.get!(Thread, thread.id).stage == "intent"
  end

  test "operator-born intent auto-advances to spec once intent.md is committed" do
    assert {:ok, advanced} = Workline.advance(open!(), artifacts: AllPresent)
    assert advanced.stage == "spec"
    assert advanced.awaiting == nil
  end

  test "machine-born intent parks awaiting the operator; approve completes the transition" do
    thread = open!(%{born: "machine", slug: "machine-born"})

    assert {:awaiting, parked} = Workline.advance(thread, artifacts: AllPresent)
    assert parked.awaiting == "andrew"
    assert parked.stage == "intent"
    assert {:error, :awaiting_operator} = Workline.advance(parked, artifacts: AllPresent)

    assert {:ok, approved} = Workline.approve(parked, artifacts: AllPresent)
    assert approved.stage == "spec"
    assert approved.awaiting == nil
  end

  test "the full pipeline: gates at spec→plan and review→merged, terminal at merged" do
    thread = open!(%{slug: "full-run"})

    {:ok, thread} = Workline.advance(thread, artifacts: AllPresent)
    {:awaiting, thread} = Workline.advance(thread, artifacts: AllPresent)
    {:ok, thread} = Workline.approve(thread, artifacts: AllPresent)
    assert thread.stage == "plan"
    {:ok, thread} = Workline.advance(thread, artifacts: AllPresent)
    {:ok, thread} = Workline.advance(thread, artifacts: AllPresent)
    {:ok, thread} = Workline.advance(thread, artifacts: AllPresent)
    assert thread.stage == "review"
    {:awaiting, thread} = Workline.advance(thread, artifacts: AllPresent)
    {:ok, thread} = Workline.approve(thread, artifacts: AllPresent)

    assert thread.stage == "merged"
    assert {:error, :terminal} = Workline.advance(thread, artifacts: AllPresent)
  end

  test "every completed flip records a stage_advanced event — the ledger for free" do
    thread = open!(%{slug: "ledger"})
    {:ok, _} = Workline.advance(thread, artifacts: AllPresent)

    assert [event] = Event |> Repo.all() |> Enum.filter(&(&1.thread_id == thread.id and &1.kind == "stage_advanced"))
    assert event.detail["from"] == "intent"
    assert event.detail["to"] == "spec"
  end

  test "artifact verification lands in CHECKS, stage-correlated, pass and fail" do
    {:ok, _} = Workline.advance(open!(%{slug: "checked"}), artifacts: AllPresent)
    {:error, _} = Workline.advance(open!(%{slug: "reject"}), artifacts: NonePresent)

    by_corr = fn corr -> Event |> Repo.all() |> Enum.filter(&(&1.correlation == corr)) |> Enum.map(& &1.kind) end
    assert "check_passed" in by_corr.("workline:checked:artifact:intent")
    assert by_corr.("workline:reject:artifact:intent") == ["check_failed"]
  end

  test "a taken slug is a changeset refusal, not a raise" do
    _first = open!(%{slug: "taken"})
    assert {:error, changeset} = Workline.open(%{title: "again", slug: "taken"})
    refute changeset.valid?
  end

  test "a workline never masquerades as the machine ROOT, but IS in the open leaf set (slice C)" do
    {:ok, root} = Channel.open_thread(%{title: "Tlön", scope: "machine"})
    workline = open!(%{slug: "not-the-root"})

    assert Channel.machine_thread().id == root.id
    # Unified (reshape slice C): tracked threads stay visible to the meta overview — the old
    # exclusion made exactly the leaves doing real work vanish from the surveyor's eye.
    assert workline.id in Enum.map(Channel.open_machine_threads(), & &1.id)

    {:ok, _} = Channel.close_thread(root)
    assert Channel.machine_thread() == nil
  end

  test "stage flips and gates announce on the Bus" do
    Server.Bus.subscribe_threads()

    {:ok, advanced} = Workline.advance(open!(%{slug: "loud"}), artifacts: AllPresent)
    assert_receive {:workline_advanced, %Thread{id: id}}
    assert id == advanced.id

    {:awaiting, parked} = Workline.advance(advanced, artifacts: AllPresent)
    assert_receive {:workline_gated, %Thread{id: gated_id}}
    assert gated_id == parked.id
  end

  test "a stage outside the ring is refused by the DATABASE itself (§4 closed set)" do
    thread = open!(%{slug: "drifted"})

    assert_raise Ecto.ConstraintError, fn ->
      thread |> Thread.workline_stage_changeset(%{stage: "deploy"}) |> Repo.update()
    end

    # The Elixir-side typed refusal stays as insurance for raw-SQL edits the CHECK can't see
    # (a detached struct) — advance never crashes on a value outside the ring.
    assert {:error, {:invalid_stage, "deploy"}} = Workline.advance(%{thread | stage: "deploy"}, artifacts: AllPresent)
  end

  test "entering review restaffs the workspace's reviewer as lead — never the builder reviews" do
    {:ok, workspace} =
      Server.Workspaces.register(%{
        name: "ReviewWorkspace",
        type: "code",
        scope: "machine",
        paths: [],
        roster: [%{"archetype" => "reviewer", "name" => "menard"}]
      })

    {:ok, _} =
      Server.Staff.register_agent(%{name: "menard-machine", mandate: "review", engine: "sonnet"})

    thread = open!(%{slug: "restaffed", workspace_id: workspace.id})
    {:ok, thread} = Workline.advance(thread, artifacts: AllPresent)
    {:awaiting, thread} = Workline.advance(thread, artifacts: AllPresent)
    {:ok, thread} = Workline.approve(thread, artifacts: AllPresent)
    {:ok, thread} = Workline.advance(thread, artifacts: AllPresent)
    {:ok, thread} = Workline.advance(thread, artifacts: AllPresent)
    {:ok, at_review} = Workline.advance(thread, artifacts: AllPresent)

    assert at_review.stage == "review"
    assert Channel.thread_lead(thread.id) == "menard-machine"
  end

  test "entering review with no reviewer in the roster leaves the lead alone" do
    thread = open!(%{slug: "no-reviewer"})
    {:ok, thread} = Workline.advance(thread, artifacts: AllPresent)
    {:awaiting, thread} = Workline.advance(thread, artifacts: AllPresent)
    {:ok, thread} = Workline.approve(thread, artifacts: AllPresent)
    {:ok, thread} = Workline.advance(thread, artifacts: AllPresent)
    {:ok, thread} = Workline.advance(thread, artifacts: AllPresent)
    {:ok, at_review} = Workline.advance(thread, artifacts: AllPresent)

    assert at_review.stage == "review"
    assert Channel.thread_lead(thread.id) == nil
  end

  test "approve with nothing parked is refused; a plain thread is not a workline" do
    assert {:error, :nothing_awaiting} = Workline.approve(open!())

    {:ok, plain} = Channel.open_thread(%{title: "not a workline"})
    assert {:error, :not_a_workline} = Workline.advance(plain, artifacts: AllPresent)
  end

  describe "promote/1 — tracking is the lazy path (reshape slice B)" do
    import Ecto.Query

    test "a plain chat thread promotes to build: derived slug, ledger event, build brief" do
      {:ok, plain} = Channel.open_thread(%{title: "Fix the CHAT feed!"})

      assert {:ok, tracked} = Workline.promote(plain)
      assert tracked.stage == "build"
      assert tracked.slug == "fix-the-chat-feed"

      assert [event] =
               Repo.all(from e in Event, where: e.thread_id == ^plain.id and e.kind == "stage_advanced")

      assert event.detail == %{"from" => nil, "to" => "build", "promoted" => true}
      assert event.correlation == "workline:fix-the-chat-feed"

      # The build brief lands on the thread — the worker learns the machinery it's now inside.
      bodies = Repo.all(from m in Server.Message, where: m.thread_id == ^plain.id, select: m.body)
      assert Enum.any?(bodies, &(&1 =~ "BUILD"))
    end

    test "an already-tracked thread is a no-op — no second event" do
      thread = open!(%{slug: "already-tracked"})
      assert {:ok, same} = Workline.promote(thread)
      assert same.stage == "intent"
      assert same.slug == "already-tracked"

      events =
        Repo.all(from e in Event, where: e.thread_id == ^thread.id and e.kind == "stage_advanced")

      assert events == []
    end

    test "the ROOT machine thread is refused — the standing home is not a work item" do
      {:ok, root} = Channel.open_thread(%{title: "Tlön", scope: "machine"})
      assert root.id == Channel.machine_thread().id

      assert {:error, :root_machine_thread} = Workline.promote(root)
    end

    test "a slug collision falls back to slug-<thread id>" do
      open!(%{slug: "fix-the-chat-feed"})
      {:ok, plain} = Channel.open_thread(%{title: "Fix the CHAT feed!"})

      assert {:ok, tracked} = Workline.promote(plain)
      assert tracked.slug == "fix-the-chat-feed-#{plain.id}"
    end

    test "an unslugifiable title falls back to thread-<id>" do
      {:ok, plain} = Channel.open_thread(%{title: "🎉🎉"})

      assert {:ok, tracked} = Workline.promote(plain)
      assert tracked.slug == "thread-#{plain.id}"
    end
  end
end
