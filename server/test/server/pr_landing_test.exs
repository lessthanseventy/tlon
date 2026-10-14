defmodule Server.PRLandingTest do
  # A reviewed PR lands through the same merge queue as worklines: queued only when its review on tlon
  # approves its head; landed by the job — re-checked, rebased onto origin's main and gated on a
  # private ref, pushed with lease, the review commented, tlon/check posted on the gated sha, merged at
  # exactly that head. Real git with a bare origin; the gate and gh stubbed, gh recording its calls.
  use ExUnit.Case, async: false
  use Oban.Testing, repo: Server.Repo

  import Ecto.Query

  alias Server.BranchReview
  alias Server.PRLanding

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp} do
    Server.TestDB.clean!()
    {:ok, thread} = Server.Channel.open_thread(%{title: "review feature"})
    repo = Path.join(tmp, "tlon")

    sh!(tmp, """
    git init -q --bare origin.git && git clone -q origin.git tlon && cd tlon &&
    git config user.email t@t && git config user.name t &&
    git commit -q --allow-empty -m one && git branch -M main && git push -q origin main &&
    git checkout -qb feature && echo f >f && git add f && git commit -qm 'feature: f' && git push -q origin feature &&
    git checkout -q main && echo m >m && git add m && git commit -qm two && git push -q origin main
    """)

    %{repo: repo, tmp: tmp, thread: thread}
  end

  defp sh!(cwd, cmd) do
    {out, 0} = System.cmd("sh", ["-c", cmd], cd: cwd, stderr_to_stdout: true)
    String.trim(out)
  end

  defp origin(ctx, ref), do: sh!(Path.join(ctx.tmp, "origin.git"), "git rev-parse #{ref}")

  defp approve(ctx, sha, verdict \\ "approve") do
    {:ok, _} =
      BranchReview.record(%{
        branch: "feature",
        sha: sha,
        verdict: verdict,
        by: "lonnrot",
        body: "#{verdict}: reads right\nno findings",
        thread_id: ctx.thread.id
      })
  end

  defp gh do
    test = self()

    fn cmd, args, _opts ->
      send(test, {:ran, [cmd | args]})
      {"", 0}
    end
  end

  defp land(ctx, opts \\ []) do
    PRLanding.land(
      %{"pr" => 7, "branch" => "feature", "on_thread" => ctx.thread.id},
      opts ++ [repo: ctx.repo, gate: fn _repo, _ref -> {:ok, :green} end, run: gh()]
    )
  end

  defp posts(ctx), do: ctx.thread |> Server.Channel.thread_messages() |> Enum.map_join("\n", & &1.body)

  defp jobs, do: Server.Repo.all(from j in Oban.Job, where: j.worker == "Server.Jobs.Land", select: j.args)

  describe "queue/3: into the merge queue only with an approval of its head" do
    test "no review: refused, nothing queued", ctx do
      assert {:error, why} = PRLanding.queue(ctx.repo, 7, "feature")
      assert why =~ "no review"
      assert jobs() == []
    end

    test "approved at its head: queued on the review's thread", ctx do
      start_supervised!({Oban, Application.fetch_env!(:server, Oban)})
      approve(ctx, origin(ctx, "feature"))
      assert {:ok, _} = PRLanding.queue(ctx.repo, 7, "feature")
      assert [%{"pr" => 7, "branch" => "feature", "on_thread" => id}] = jobs()
      assert id == ctx.thread.id
      assert posts(ctx) =~ "merge queue"
    end

    test "the PR's author approving it: refused", ctx do
      approve(ctx, origin(ctx, "feature"))
      assert {:error, why} = PRLanding.queue(ctx.repo, 7, "feature", "lonnrot")
      assert why =~ "opened the PR"
      assert jobs() == []
    end

    test "main is never queued", ctx do
      assert {:error, why} = PRLanding.queue(ctx.repo, 7, "main")
      assert why =~ "main"
    end
  end

  describe "land/2: the merge queue's turn" do
    test "approved at its head: rebased, gated, pushed, the review commented, tlon/check posted, merged at that head",
         ctx do
      approve(ctx, origin(ctx, "feature"))
      assert {:ok, to} = land(ctx)

      assert origin(ctx, "feature") == to
      assert origin(ctx, "feature~1") == origin(ctx, "main")
      assert_received {:ran, ["gh", "pr", "comment", "7", "--body", body]}
      assert body =~ "Reviewed on tlon by lonnrot" and body =~ "> approve: reads right"

      assert_received {:ran,
                       [
                         "gh",
                         "api",
                         "repos/{owner}/{repo}/statuses/" <> ^to,
                         "-f",
                         "state=success",
                         "-f",
                         "context=tlon/check" | _
                       ]}

      assert_received {:ran, ["gh", "pr", "merge", "7", "--rebase", "--match-head-commit", ^to, "--delete-branch"]}
      assert posts(ctx) =~ "merged"
      assert sh!(ctx.repo, "git branch --list 'land/*'") == ""
    end

    test "approved, then only rebased onto main: the same patches, it lands", ctx do
      approve(ctx, origin(ctx, "feature"))

      sh!(
        ctx.repo,
        "git checkout -q feature && git rebase -q main && git push -q -f origin feature && git checkout -q main"
      )

      assert {:ok, _} = land(ctx)
      assert_received {:ran, ["gh", "pr", "merge" | _]}
    end

    test "new commits since the approval: nothing pushed or merged, and it says so", ctx do
      approve(ctx, origin(ctx, "feature"))

      sh!(
        ctx.repo,
        "git checkout -q feature && echo g >g && git add g && git commit -qm more && git push -q origin feature && git checkout -q main"
      )

      before = origin(ctx, "feature")

      assert {:error, why} = land(ctx)
      assert why =~ "review it again"
      assert origin(ctx, "feature") == before
      refute_received {:ran, ["gh" | _]}
      assert posts(ctx) =~ "review it again"
    end

    test "a red gate: nothing pushed or merged, the finding posted", ctx do
      approve(ctx, origin(ctx, "feature"))
      before = origin(ctx, "feature")

      assert {:error, _} = land(ctx, gate: fn _, _ -> {:error, "the full check is red: 1 failure"} end)
      assert origin(ctx, "feature") == before
      refute_received {:ran, ["gh", "pr", "merge" | _]}
      assert posts(ctx) =~ "1 failure"
    end

    test "a gate cut off is interrupted, for the queue to try again; said only on the last attempt", ctx do
      approve(ctx, origin(ctx, "feature"))
      cut = fn _, _ -> {:error, {:interrupted, "killed, exit 143"}} end

      assert {:error, {:interrupted, _}} = land(ctx, gate: cut)
      refute posts(ctx) =~ "143"
      assert {:error, {:interrupted, _}} = land(ctx, gate: cut, last: true)
      assert posts(ctx) =~ "143"
    end

    test "GitHub refusing the merge is said", ctx do
      approve(ctx, origin(ctx, "feature"))
      test = self()

      refusing = fn
        "gh", ["pr", "merge" | _], _ ->
          {"Required status check \"tlon/check\" is expected", 1}

        cmd, args, _ ->
          send(test, {:ran, [cmd | args]})
          {"", 0}
      end

      assert {:error, why} = land(ctx, run: refusing)
      assert why =~ "tlon/check"
      assert posts(ctx) =~ "tlon/check"
    end
  end
end
