defmodule Server.PRLanding do
  @moduledoc """
  A reviewed PR lands through the same merge queue as worklines (`Server.Jobs.Land`, one at a time).
  `queue/3` takes it only when the branch's review on tlon approves its head
  (`Server.BranchReview.approves/4`). Its turn (`land/2`) checks that again against the branch as it
  is then, rebases it onto origin's main on a private ref `land/<branch>` and gates it there
  (`Server.Workline.Merge`, the gate `Server.Jobs.Land.gate_pr/4`), pushes it with lease, comments the
  review on the PR (the PR is the record), posts `tlon/check` on the gated sha
  (`Server.Workline.Publish.post_check/3`) and merges at exactly that head
  (`gh pr merge --rebase --match-head-commit`). Each step's outcome is posted on the thread the review
  was recorded on.
  """

  alias Server.BranchReview
  alias Server.Workline.Publish

  @doc """
  Queue PR `pr` on `branch` of `repo` for landing, `pr_author` its GitHub author (who may not be its
  reviewer): `{:ok, job}`, or `{:error, why}` when it is main or its review doesn't approve its head
  on origin.
  """
  def queue(repo, pr, branch, pr_author \\ nil) do
    with :ok <- not_main(branch),
         {:ok, head} <- fetch(repo, branch),
         {:ok, review} <- BranchReview.approves(repo, branch, head, pr_author: pr_author),
         {:ok, job} <-
           Server.Jobs.enqueue(
             Server.Jobs.Land.new(%{
               "pr" => pr,
               "branch" => branch,
               "pr_author" => pr_author,
               "on_thread" => review.thread_id
             })
           ) do
      post(
        review.thread_id,
        "⧗ PR ##{pr} (#{branch}, approved by #{review.by}) is in the merge queue: it lands once rebased onto main and green there, one landing at a time"
      )

      {:ok, job}
    end
  end

  @doc """
  The merge queue's turn for a PR (`Server.Jobs.Land`'s args `%{"pr", "branch", "pr_author", "on_thread"}`).
  `opts`: `:repo` (default the tlon checkout), `:gate` (`fn repo, ref -> {:ok, _} | {:error, why} end`),
  `:run` (gh), `:last` (the queue's last attempt: a gate cut off is said then, else only retried).
  `{:ok, merged_sha}` | `{:error, why}` | `{:error, {:interrupted, why}}`.
  """
  def land(%{"pr" => pr, "branch" => branch} = args, opts \\ []) do
    repo = Keyword.get_lazy(opts, :repo, &Server.Profiles.tlon_root/0)
    run = Keyword.get(opts, :run, &System.cmd/3)
    gate = Keyword.get_lazy(opts, :gate, fn -> &Server.Jobs.Land.gate_pr(pr, branch, &1, &2) end)
    ref = "land/#{branch}"
    say = &post(args["on_thread"], "PR ##{pr} (#{branch}): #{&1}")

    try do
      with :ok <- not_main(branch),
           {:ok, head} <- fetch(repo, branch),
           {:ok, review} <- BranchReview.approves(repo, branch, head, pr_author: args["pr_author"]),
           {:ok, _} <- git(repo, ["branch", "-f", ref, head]),
           {:ok, %{to: to}} <- Server.Workline.Merge.merge(repo, nil, branch: ref, gate: gate),
           {:ok, _} <- push(repo, ref, branch, head),
           run.("gh", ["pr", "comment", to_string(pr), "--body", record(review)], cd: repo, stderr_to_stdout: true),
           Publish.post_check(repo, to, run),
           {:ok, how} <- merge(repo, pr, to, branch, run) do
        say.(
          if how == :auto,
            do:
              "⧗ gated green at #{String.slice(to, 0, 12)}; GitHub hadn't read its tlon/check yet, so auto-merge is armed at that head",
            else: "✓ merged at #{String.slice(to, 0, 12)}, gated on main"
        )

        {:ok, to}
      else
        {:error, {:interrupted, why}} = cut ->
          if opts[:last], do: say.("⚠ the merge queue's gate was cut off on its last try (#{why}) — nothing merged")
          cut

        {:error, why} = error ->
          say.("✗ not landed: #{why}")
          error
      end
    after
      git(repo, ["branch", "-D", ref])
    end
  end

  defp not_main("main"), do: {:error, "main is never landed — land the branch that goes onto it"}
  defp not_main(_branch), do: :ok

  defp fetch(repo, branch) do
    with {:ok, _} <- git(repo, ["fetch", "-q", "origin", "main", branch]) do
      git(repo, ["rev-parse", "--verify", "-q", "origin/#{branch}"])
    end
  end

  defp push(repo, ref, branch, head),
    do:
      git(repo, [
        "push",
        "-q",
        "--force-with-lease=refs/heads/#{branch}:#{head}",
        "origin",
        "#{ref}:refs/heads/#{branch}"
      ])

  defp merge(repo, pr, sha, branch, run) do
    case Publish.merge_at(repo, pr, sha, branch, run) do
      {:error, why} -> {:error, "GitHub refused the merge: #{why}"}
      how -> {:ok, how}
    end
  end

  defp record(review) do
    quoted = (review.body || "") |> String.split("\n") |> Enum.map_join("\n", &"> #{&1}")
    "Reviewed on tlon by #{review.by} — #{review.verdict} at `#{String.slice(review.sha, 0, 12)}`:\n\n#{quoted}"
  end

  defp git(repo, args) do
    case System.cmd("git", ["-C", repo | args], stderr_to_stdout: true) do
      {out, 0} -> {:ok, String.trim(out)}
      {out, _} -> {:error, "git #{hd(args)} failed: #{out |> String.trim() |> String.slice(-300, 300)}"}
    end
  end

  defp post(nil, _body), do: :ok

  defp post(thread_id, body) do
    Server.Channel.post(%{thread_id: thread_id, author: "tlon", body: body})
    :ok
  rescue
    _ -> :ok
  end
end
