defmodule Server.Release.CandidateTest do
  # A candidate is releasable when the gate and the smoke each passed on exactly that commit and
  # nothing is mid-flight (pm-and-release design §4, checks 1, 2 and 4).
  use ExUnit.Case, async: false
  use Oban.Testing, repo: Server.Repo

  alias Server.Release.Candidate
  alias Server.Repo
  alias Server.ScheduleRun

  @a String.duplicate("a", 40)
  @b String.duplicate("b", 40)

  setup do
    Server.TestDB.clean!()
    start_supervised!({Oban, Application.fetch_env!(:server, Oban)})
    {:ok, ws} = Server.Workspaces.register(%{name: "Machine"})

    {:ok, s} =
      Server.Schedules.create(%{workspace_id: ws.id, kind: "script", title: "nightly", body: "true", cron: "@daily"})

    {:ok, s: s}
  end

  describe "a landing's gate is main's check when main's tip is the tree it gated (E2)" do
    # gh merges at the gated head; GitHub's rebase rewrites the commits, so main's tip is a new sha
    defp landing(trees) do
      fn
        "gh", ["pr", "merge" | _], _ -> {"", 0}
        "gh", _, _ -> {"", 0}
        "git", [_, _, "fetch" | _], _ -> {"", 0}
        "git", [_, _, "rev-parse", "origin/main"], _ -> {@b <> "\n", 0}
        "git", [_, _, "rev-parse", rev], _ -> {Map.fetch!(trees, rev) <> "\n", 0}
      end
    end

    test "the same tree: the gate is recorded on main's new tip, and the tip's smoke is queued" do
      run = landing(%{"#{@a}^{tree}" => "t1", "origin/main^{tree}" => "t1"})
      assert :merged = Server.Workline.Publish.merge_at(Server.Profiles.tlon_root(), 9, @a, "work/x", run)
      assert [%{check: :gate, ok: true} | _] = Candidate.check(@b, busy: fn -> [] end)
      assert %ScheduleRun{status: "ok"} = Candidate.passed("gate", @b)
      assert [%{args: %{"candidate" => true, "sha" => @b, "ref" => @b}}] = all_enqueued(worker: Server.Jobs.Smoke)
    end

    test "another tree (main moved past it), or another repo: nothing is recorded, no smoke queued" do
      run = landing(%{"#{@a}^{tree}" => "t1", "origin/main^{tree}" => "t2"})
      assert :merged = Server.Workline.Publish.merge_at(Server.Profiles.tlon_root(), 9, @a, "work/x", run)
      assert :merged = Server.Workline.Publish.merge_at("/elsewhere", 9, @a, "work/x", run)
      assert [%{check: :gate, ok: false} | _] = Candidate.check(@b, busy: fn -> [] end)
      assert Candidate.passed("gate", @b) == nil
      assert all_enqueued(worker: Server.Jobs.Smoke) == []
    end

    test "a newer tip's smoke replaces one still queued; a held QA smoke is not touched" do
      {:ok, held} = Oban.insert(Server.Jobs.Smoke.new(%{thread_id: 1, ref: "work/x", sha: @a}))
      {:ok, first} = Server.Smoke.queue_candidate(@a)
      {:ok, second} = Server.Smoke.queue_candidate(@b)

      assert Repo.reload!(first).state == "cancelled"
      assert Repo.reload!(second).state == "available"
      assert Repo.reload!(held).state == "available"
    end
  end

  defp ran!(s, check, sha, status) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    Repo.insert!(%ScheduleRun{
      schedule_id: s.id,
      status: status,
      check_name: check,
      sha: sha,
      started_at: now,
      finished_at: now
    })
  end

  defp quiet, do: [busy: fn -> [] end]
  defp by_check(results), do: Map.new(results, &{&1.check, &1})

  test "the gate and the smoke passed on exactly it, and nothing is mid-flight: releasable", %{s: s} do
    ran!(s, "gate", @a, "ok")
    ran!(s, "smoke", @a, "ok")

    assert %{gate: %{ok: true}, smoke: %{ok: true}, quiet: %{ok: true}} = by_check(Candidate.check(@a, quiet()))
    assert Candidate.releasable?(@a, quiet())
  end

  test "a candidate whose nightly ran on a different commit is not releasable", %{s: s} do
    ran!(s, "gate", @a, "ok")
    ran!(s, "smoke", @b, "ok")

    assert %{gate: %{ok: false, why: why}} = by_check(Candidate.check(@b, quiet()))
    assert why =~ "aaaaaaa"
    refute Candidate.releasable?(@b, quiet())
  end

  test "an interrupted run is no verdict: the sha reads as no gate yet, not red", %{s: s} do
    ran!(s, "gate", @a, "interrupted")
    ran!(s, "smoke", @a, "ok")

    assert %{gate: %{ok: false, why: why}} = by_check(Candidate.check(@a, quiet()))
    assert why =~ "no check:main on aaaaaaa"
    refute why =~ "interrupted"
  end

  test "an interrupted run does not unseat an earlier pass on the same commit", %{s: s} do
    ran!(s, "gate", @a, "ok")
    ran!(s, "gate", @a, "interrupted")

    assert %{gate: %{ok: true}} = by_check(Candidate.check(@a, quiet()))
  end

  test "the newest finished run on the commit decides", %{s: s} do
    ran!(s, "gate", @a, "ok")
    ran!(s, "gate", @a, "failed")
    ran!(s, "smoke", @a, "ok")

    assert %{gate: %{ok: false, why: why}} = by_check(Candidate.check(@a, quiet()))
    assert why =~ "failed"
  end

  test "with no smoke on it, or work mid-flight, it waits", %{s: s} do
    ran!(s, "gate", @a, "ok")

    results = by_check(Candidate.check(@a, busy: fn -> ["the verify of #7 is running"] end))
    assert %{smoke: %{ok: false}, quiet: %{ok: false, why: "the verify of #7 is running"}} = results
    refute Candidate.releasable?(@a, quiet())
  end

  test "its lines say each check and the verdict", %{s: s} do
    ran!(s, "gate", @a, "ok")

    lines = Candidate.lines(@a, quiet())
    assert Enum.any?(lines, &(&1 =~ ~r/^gate .*✓/))
    assert Enum.any?(lines, &(&1 =~ ~r/^smoke .*✗/))
    assert List.last(lines) == "releasable: no"
  end

  test "a hand run reported with no schedule counts as the gate and smoke on its commit" do
    assert {:ok, %{status: "ok"}} = Candidate.record("gate", @a, 0)
    assert {:ok, %{status: "ok"}} = Candidate.record("smoke", @a, 0)
    assert Candidate.releasable?(@a, quiet())
  end

  test "a hand run that exited non-zero is a failed run, and the newest decides" do
    {:ok, _} = Candidate.record("gate", @a, 0)
    assert {:ok, %{status: "failed", exit: 2}} = Candidate.record("gate", @a, 2)
    assert %{gate: %{ok: false, why: why}} = by_check(Candidate.check(@a, quiet()))
    assert why =~ "failed"
  end

  test "record refuses a check it doesn't know and a sha that is not a full commit id" do
    assert {:error, :bad_check} = Candidate.record("lint", @a, 0)
    assert {:error, :bad_sha} = Candidate.record("gate", "abc123", 0)
  end
end
