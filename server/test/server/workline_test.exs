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

  test "any-stage entry: open at a later stage (Slice 4D) sets the start, doesn't gate or backfill" do
    at_build = open!(%{slug: "any-build", stage: "build"})
    assert at_build.stage == "build"
    assert at_build.born == "operator"
    # Operator-initiated later-stage entry parks on nothing — the human chose the entry point.
    assert at_build.awaiting == nil

    at_review = open!(%{slug: "any-review", stage: "review"})
    assert at_review.stage == "review"
  end

  test "any-stage entry opens with the brief for THAT stage, not the intent brief" do
    at_build = open!(%{slug: "brief-build", stage: "build"})
    bodies = Server.Message |> Repo.all() |> Enum.filter(&(&1.thread_id == at_build.id)) |> Enum.map(& &1.body)
    # The build brief owes "commits on branch work/<slug>" — intent's brief never says "branch".
    assert Enum.any?(bodies, &(&1 =~ "branch work/brief-build"))
  end

  test "any-stage entry refuses the terminal stage and any non-stage" do
    assert {:error, {:invalid_stage, "merged"}} = Workline.open(%{title: "t", slug: "no-merged", stage: "merged"})
    assert {:error, {:invalid_stage, "garbage"}} = Workline.open(%{title: "t", slug: "no-garbage", stage: "garbage"})
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

  test "a stuck hold off a gate yields once the artifact is there: advance flips and clears it" do
    {:ok, stuck} =
      %{stage: "verify"} |> open!() |> Thread.workline_stage_changeset(%{awaiting: "andrew"}) |> Repo.update()

    assert {:ok, advanced} = Workline.advance(stuck, artifacts: AllPresent)
    assert advanced.stage == "review"
    assert advanced.awaiting == nil
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
        repos: [],
        roster: [%{"archetype" => "reviewer", "name" => "menard"}]
      })

    # seating the bench already registered `menard` — the agent is the bench (UX slice 5)
    assert Server.Staff.agent_by_name("menard")

    thread = open!(%{slug: "restaffed", workspace_id: workspace.id})
    {:ok, thread} = Workline.advance(thread, artifacts: AllPresent)
    {:awaiting, thread} = Workline.advance(thread, artifacts: AllPresent)
    {:ok, thread} = Workline.approve(thread, artifacts: AllPresent)
    {:ok, thread} = Workline.advance(thread, artifacts: AllPresent)
    {:ok, thread} = Workline.advance(thread, artifacts: AllPresent)
    {:ok, at_review} = Workline.advance(thread, artifacts: AllPresent)

    assert at_review.stage == "review"
    assert Channel.thread_lead(thread.id) == "menard"
  end

  defmodule Merges do
    @moduledoc false
    def merge(repo, slug, opts \\ []) do
      gate = Keyword.get(opts, :gate, fn _, _ -> {:ok, :no_gate} end)

      cond do
        slug == "conflicted" -> {:error, "merging hit a conflict"}
        match?({:error, _}, gate.(repo, "work/#{slug}")) -> gate.(repo, "work/#{slug}")
        true -> {:ok, %{from: "a", to: "b"}}
      end
    end
  end

  test "approving the review gate merges the branch, then the workline is merged and its thread closed" do
    thread = open!(%{slug: "landing", stage: "review"})
    {:awaiting, parked} = Workline.advance(thread, artifacts: AllPresent)
    assert {:ok, merged} = Workline.approve(parked, artifacts: AllPresent, merge: Merges)
    assert merged.stage == "merged"
    assert %Server.Thread{state: "closed"} = Server.Repo.get(Server.Thread, thread.id)
  end

  describe "the merge queue" do
    use Oban.Testing, repo: Server.Repo

    test "approving the review gate queues the landing: no longer waiting on the operator, not yet merged" do
      start_supervised!({Oban, Application.fetch_env!(:server, Oban)})
      thread = open!(%{slug: "queued", stage: "review"})
      {:awaiting, parked} = Workline.advance(thread, artifacts: AllPresent)

      assert {:ok, queued} = Workline.approve(parked, artifacts: AllPresent, land: :queue)
      assert %Server.Thread{stage: "review", awaiting: nil, state: "open"} = queued
      assert_enqueued(worker: Server.Jobs.Land, args: %{thread_id: thread.id})
      assert Enum.any?(Channel.thread_messages(queued), &(&1.body =~ "merge queue"))
    end

    test "its turn, green on main: merged, closed" do
      thread = open!(%{slug: "lands", stage: "review"})
      {:awaiting, parked} = Workline.advance(thread, artifacts: AllPresent)
      {:ok, queued} = parked |> Server.Thread.workline_stage_changeset(%{awaiting: nil}) |> Repo.update()

      assert {:ok, %{stage: "merged"}} =
               Workline.land_queued(queued, merge: Merges, gate: fn _, _ -> {:ok, :green} end)

      assert %Server.Thread{state: "closed"} = Repo.get(Server.Thread, thread.id)
    end

    test "its turn, red on main or a conflict: back to build, the builder told why — never parked on the operator" do
      for {slug, gate, why} <- [
            {"conflicted", fn _, _ -> {:ok, :green} end, "merging hit a conflict"},
            {"red-on-main", fn _, _ -> {:error, "the gate on main is red"} end, "the gate on main is red"}
          ] do
        thread = open!(%{slug: slug, stage: "review"})
        {:awaiting, parked} = Workline.advance(thread, artifacts: AllPresent)
        {:ok, queued} = parked |> Server.Thread.workline_stage_changeset(%{awaiting: nil}) |> Repo.update()

        assert {:error, {:bounced, ^why}} = Workline.land_queued(queued, merge: Merges, gate: gate)
        assert %Server.Thread{stage: "build", awaiting: nil, state: "open"} = Repo.get(Server.Thread, thread.id)
        assert Enum.any?(Channel.thread_messages(queued), &(&1.body =~ "back to build" and &1.body =~ why))
      end
    end

    test "advance_stage at verify with no fresh evidence asks the server to verify — the lead's only way to" do
      start_supervised!({Oban, Application.fetch_env!(:server, Oban)})
      {:ok, t} = Workline.open(%{title: "v", slug: "asks-verify", stage: "verify"})

      assert {:error, {:artifact_missing, why}} = Workline.advance(t, artifacts: NonePresent, reverify: true)
      assert why =~ "verify is queued"
      assert_enqueued(worker: Server.Jobs.Verify, args: %{thread_id: t.id, slug: "asks-verify"})
    end

    test "a thread no longer queued (re-parked, closed, moved on) is left alone" do
      thread = open!(%{slug: "not-queued", stage: "review"})
      {:awaiting, parked} = Workline.advance(thread, artifacts: AllPresent)
      assert {:ok, %{stage: "review", awaiting: "andrew"}} = Workline.land_queued(parked, merge: Merges)
    end
  end

  test "a merge that can't land keeps the gate parked, and says why on the thread" do
    thread = open!(%{slug: "conflicted", stage: "review"})
    {:awaiting, parked} = Workline.advance(thread, artifacts: AllPresent)
    assert {:error, {:merge, "merging hit a conflict"}} = Workline.approve(parked, artifacts: AllPresent, merge: Merges)

    assert %Server.Thread{stage: "review", awaiting: "andrew", state: "open"} =
             Server.Repo.get(Server.Thread, thread.id)

    assert Enum.any?(Channel.thread_messages(parked), &(&1.body =~ "couldn't merge"))
  end

  test "a stage that changes its lead closes the old lead's window, so the new lead can be spawned on it" do
    {:ok, workspace} =
      Server.Workspaces.register(%{
        name: "HandedWorkspace",
        type: "code",
        scope: "machine",
        repos: [],
        roster: [%{"archetype" => "reviewer", "name" => "lonnrot"}]
      })

    thread = open!(%{slug: "handed", workspace_id: workspace.id, stage: "verify"})
    pid = self()

    Application.put_env(:server, :tmux_cmd, fn "tmux", args, _opts ->
      send(pid, {:tmux, args})
      if "list-windows" in args, do: {"3\tt#{thread.id}\t#{thread.id}\t\t42\tdaneri\t1\n", 0}, else: {"", 0}
    end)

    on_exit(fn -> Application.delete_env(:server, :tmux_cmd) end)

    {:ok, at_review} = Workline.advance(thread, artifacts: AllPresent)
    assert Channel.thread_lead(at_review.id) == "lonnrot"
    assert_received {:tmux, ["-L", _, "kill-window", "-t", target]}
    assert target =~ ":3"
  end

  test "each stage is staffed by its kind: spec and plan the planner, build and verify the builder, review the reviewer" do
    {:ok, workspace} =
      Server.Workspaces.register(%{
        name: "StagedWorkspace",
        type: "code",
        scope: "machine",
        repos: [],
        roster: [
          %{"archetype" => "planner", "name" => "yu"},
          %{"archetype" => "builder", "name" => "daneri"},
          %{"archetype" => "reviewer", "name" => "lonnrot"}
        ]
      })

    thread = open!(%{slug: "staged", workspace_id: workspace.id})
    {:ok, at_spec} = Workline.advance(thread, artifacts: AllPresent)
    assert at_spec.stage == "spec" and Channel.thread_lead(thread.id) == "yu"

    {:awaiting, thread} = Workline.advance(at_spec, artifacts: AllPresent)
    {:ok, at_plan} = Workline.approve(thread, artifacts: AllPresent)
    assert at_plan.stage == "plan" and Channel.thread_lead(thread.id) == "yu"

    {:ok, at_build} = Workline.advance(at_plan, artifacts: AllPresent)
    assert at_build.stage == "build" and Channel.thread_lead(thread.id) == "daneri"

    {:ok, at_verify} = Workline.advance(at_build, artifacts: AllPresent)
    assert at_verify.stage == "verify" and Channel.thread_lead(thread.id) == "daneri"

    {:ok, at_review} = Workline.advance(at_verify, artifacts: AllPresent)
    assert at_review.stage == "review" and Channel.thread_lead(thread.id) == "lonnrot"
  end

  test "opening a workline staffs its first stage: intent the bench's lead, spec the planner" do
    {:ok, workspace} =
      Server.Workspaces.register(%{
        name: "OpenedWorkspace",
        type: "code",
        scope: "machine",
        repos: [],
        roster: [%{"archetype" => "planner", "name" => "yu"}, %{"archetype" => "builder", "name" => "tertius"}]
      })

    at_intent = open!(%{slug: "opened-intent", workspace_id: workspace.id})
    assert Channel.thread_lead(at_intent.id) == "tertius"

    at_spec = open!(%{slug: "opened-spec", stage: "spec", workspace_id: workspace.id})
    assert Channel.thread_lead(at_spec.id) == "yu"
  end

  describe "one coworker, one workline" do
    defp bench_ws(name, roster),
      do: Server.Workspaces.register(%{name: name, type: "code", scope: "machine", repos: [], roster: roster})

    test "a coworker leading one workline is not handed another: a free one of the kind is" do
      {:ok, ws} =
        bench_ws("TwoPlanners", [
          %{"archetype" => "planner", "name" => "yu"},
          %{"archetype" => "planner", "name" => "averroes"}
        ])

      a = open!(%{slug: "first", stage: "spec", workspace_id: ws.id})
      b = open!(%{slug: "second", stage: "spec", workspace_id: ws.id})
      assert Channel.thread_lead(a.id) == "yu"
      assert Channel.thread_lead(b.id) == "averroes"
    end

    test "every one of the kind busy, another is hired onto the bench and leads it" do
      {:ok, ws} = bench_ws("OnePlanner", [%{"archetype" => "planner", "name" => "yu"}])
      yu = Enum.find(Server.Workspaces.bench(ws.id), &(&1.name == "yu"))
      glm = %{"provider" => "ollama-cloud", "model" => "glm-5.2", "thinking" => "medium"}
      {:ok, _} = Server.Workspaces.set_policy(ws.id, yu.agent_id, %{model: glm})
      _a = open!(%{slug: "busy-one", stage: "spec", workspace_id: ws.id})
      b = open!(%{slug: "busy-two", stage: "spec", workspace_id: ws.id})

      hired = Channel.thread_lead(b.id)
      refute hired in [nil, "yu"]
      seat = Enum.find(Server.Workspaces.bench(ws.id), &(&1.name == hired and &1.archetype == "planner"))
      assert seat
      # the hire runs on its peers' model
      assert Server.Workspaces.policy(ws.id, seat.agent_id).model == glm
    end

    test "a coworker whose other workline only waits on the operator is free to lead this one" do
      {:ok, ws} = bench_ws("WaitingPlanner", [%{"archetype" => "planner", "name" => "yu"}])
      a = open!(%{slug: "waits", stage: "spec", workspace_id: ws.id})
      {:ok, _} = a |> Ecto.Changeset.change(awaiting: "andrew") |> Server.Repo.update()
      b = open!(%{slug: "meanwhile", stage: "spec", workspace_id: ws.id})
      assert Channel.thread_lead(b.id) == "yu"
    end

    test "a manager's pick stands when it fits: of the stage's kind and free" do
      {:ok, ws} =
        bench_ws("PickFits", [
          %{"archetype" => "planner", "name" => "yu"},
          %{"archetype" => "planner", "name" => "averroes"}
        ])

      w = open!(%{slug: "picked", stage: "spec", workspace_id: ws.id})
      assert {:ok, "averroes", :as_asked} = Workline.lead_for(w, "averroes")
    end

    test "a manager's pick that is busy, or the wrong kind, gives way to the rule's — and says why" do
      {:ok, ws} =
        bench_ws("PickGivesWay", [
          %{"archetype" => "planner", "name" => "yu"},
          %{"archetype" => "builder", "name" => "hronir"}
        ])

      _busy = open!(%{slug: "yu-busy", stage: "spec", workspace_id: ws.id})
      w = open!(%{slug: "second-spec", stage: "spec", workspace_id: ws.id})
      staffed = Channel.thread_lead(w.id)

      assert {:ok, ^staffed, {:instead, why}} = Workline.lead_for(w, "yu")
      assert why =~ "yu" and why =~ "another workline"
      assert {:ok, ^staffed, {:instead, why}} = Workline.lead_for(w, "hronir")
      assert why =~ "planner"
    end

    test "a lead already of the stage's kind keeps the workline, busy elsewhere or not" do
      {:ok, ws} = bench_ws("Continuity", [%{"archetype" => "planner", "name" => "yu"}])
      a = open!(%{slug: "keeps", stage: "spec", workspace_id: ws.id})
      {:awaiting, a} = Workline.advance(a, artifacts: AllPresent)
      {:ok, at_plan} = Workline.approve(a, artifacts: AllPresent)
      assert at_plan.stage == "plan" and Channel.thread_lead(a.id) == "yu"
    end
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

  test "an approval already landing is not run twice: a second one meanwhile is refused" do
    thread = open!(%{born: "machine", slug: "approving-twice"})
    {:awaiting, parked} = Workline.advance(thread, artifacts: AllPresent)
    me = self()

    holder =
      spawn(fn ->
        Workline.landing(parked.id, fn ->
          send(me, :holding)
          receive do: (:release -> :ok)
        end)
      end)

    assert_receive :holding
    assert {:error, :approving} = Workline.approve(parked, artifacts: AllPresent)
    send(holder, :release)
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

    test "promotion renames the thread's t<id> worktree to the slug's, branch included" do
      %{repo: repo, ws: ws, project: p} = Server.TestRepoDir.with_project()
      {:ok, plain} = Channel.open_thread(%{title: "Rename Me", workspace_id: ws.id, project_id: p.id})
      {:ok, old} = Server.worktree_for_thread(plain)
      assert old == Server.Worktree.path(repo, "t#{plain.id}")

      assert {:ok, tracked} = Workline.promote(plain)
      assert tracked.slug == "rename-me"
      refute File.exists?(old)
      assert File.exists?(Path.join(Server.Worktree.path(repo, "rename-me"), ".git"))
      {out, 0} = System.cmd("git", ["-C", repo, "branch", "--list", "work/rename-me"])
      assert String.trim(out) != ""
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
