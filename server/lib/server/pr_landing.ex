defmodule Server.PRLanding do
  @moduledoc """
  A reviewed PR lands through the same merge queue as worklines (`Server.Jobs.Land`, one at a time).
  `queue/3` takes it only when the branch's review on tlon approves its head
  (`Server.BranchReview.approves/4`); `request/3` is the door by PR number (`mise run land`, `land_pr`),
  `request_branch/3` the one an approving `review_branch` takes by itself, the branch's open PR onto
  main found by gh. Its turn (`land/2`) checks that again against the branch as it
  is then, rebases it onto origin's main on a private ref `land/<branch>` and gates it there
  (`Server.Workline.Merge`, the gate `Server.Jobs.Land.gate_pr/4`), pushes it with lease, comments the
  review on the PR (the PR is the record), posts `tlon/check` on the gated sha
  (`Server.Workline.Publish.post_check/3`) and merges at exactly that head
  (`gh pr merge --rebase --match-head-commit`). Each step's outcome is posted on the thread the review
  was recorded on.
  """

  alias Server.BranchReview
  alias Server.GitFetch
  alias Server.Workline.Publish

  @doc """
  Queue PR `pr` on `branch` of `repo` for landing, `pr_author` its GitHub author (who may not be its
  reviewer): `{:ok, job}`, or `{:error, why}` when it is main or its review doesn't approve its head
  on origin.
  """
  def queue(repo, pr, branch, pr_author \\ nil, opts \\ []) do
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
        "⧗ PR ##{pr} (#{branch}, approved by #{review.by}#{queued_by(opts[:by])}) is in the merge queue: it lands once rebased onto main and green there, one landing at a time"
      )

      {:ok, job}
    end
  end

  @doc """
  `scripts/land.sh`'s preflight, run here so a sandboxed seat reaches the queue over MCP (`land_pr`)
  rather than epmd: GitHub says what PR `pr` is, and one closed, not onto main, from a fork, from main
  or a protected branch is refused; else `queue/5` by its branch. `opts`: `:run` (gh; default the
  `:gh_cmd` app env, else `System.cmd/3`), `:by` (who queued it, named in the thread's post). gh's stderr
  is left out of stdout: a warning on exit 0 would not parse.
  """
  def request(repo, pr, opts \\ []) do
    run = Keyword.get(opts, :run, gh())

    with {:ok, info} <- view(repo, pr, run),
         :ok <- landable(info),
         :ok <- unprotected(repo, info["headRefName"], run) do
      queue(repo, pr, info["headRefName"], get_in(info, ["author", "login"]), by: opts[:by])
    end
  end

  @doc """
  `request/3` for a branch rather than a PR number, the step an approving `review_branch` takes: gh
  lists `branch`'s open PRs onto main (`--head`), and exactly one goes to `request/3` with the same
  `opts`; none, several, or gh failing is `{:error, why}`, nothing queued.
  """
  def request_branch(repo, branch, opts \\ []) do
    run = Keyword.get(opts, :run, gh())

    with {:ok, pr} <- open_pr(repo, branch, run) do
      request(repo, pr, Keyword.put(opts, :run, run))
    end
  end

  defp view(repo, pr, run) do
    fields = "headRefName,baseRefName,state,isCrossRepository,author"

    with {out, 0} <- run.("gh", ["pr", "view", to_string(pr), "--json", fields], cd: repo),
         {:ok, %{"headRefName" => _} = info} <- Jason.decode(out) do
      {:ok, info}
    else
      _ -> {:error, "gh could not read the PR"}
    end
  end

  defp landable(%{"state" => state}) when state != "OPEN", do: {:error, "it is #{state}, not open"}
  defp landable(%{"baseRefName" => base}) when base != "main", do: {:error, "it targets #{base}, not main"}
  defp landable(%{"isCrossRepository" => true}), do: {:error, "its branch is on a fork — the merge queue can't push it"}
  defp landable(%{"headRefName" => "main"}), do: {:error, "its branch is main — refused"}
  defp landable(_), do: :ok

  defp unprotected(repo, branch, run) do
    args = ["api", "repos/{owner}/{repo}/branches/#{branch}", "--jq", ".protected"]
    {out, code} = run.("gh", args, cd: repo)

    case {code, String.trim(out)} do
      {0, "false"} -> :ok
      {0, "true"} -> {:error, "its branch #{branch} is protected — refused"}
      {_, said} -> {:error, "can't tell whether its branch #{branch} is protected (gh said: #{said}) — refused"}
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
    run = Keyword.get(opts, :run, gh())
    gate = Keyword.get_lazy(opts, :gate, fn -> &Server.Jobs.Land.gate_pr(pr, branch, &1, &2) end)
    ref = "land/#{branch}"
    say = &post(args["on_thread"], "PR ##{pr} (#{branch}): #{&1}")

    try do
      with :ok <- not_main(branch),
           {:ok, head} <- interruptible(fetch(repo, branch)),
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
          if opts[:last], do: say.("⚠ the merge queue's turn was cut off on its last try (#{why}) — nothing merged")
          cut

        {:error, why} = error ->
          say.("✗ not landed: #{why}")
          error
      end
    after
      git(repo, ["branch", "-D", ref])
    end
  end

  defp queued_by(nil), do: ""
  defp queued_by(by), do: ", queued by #{by}"

  defp not_main("main"), do: {:error, "main is never landed — land the branch that goes onto it"}
  defp not_main(_branch), do: :ok

  # A fetch still failing after the retries is infra, not the branch's fault: the queue tries the turn again.
  defp interruptible({:error, why}), do: {:error, {:interrupted, "could not fetch origin: " <> why}}
  defp interruptible(ok), do: ok

  defp fetch(repo, branch) do
    with {:ok, _} <- git(repo, ["fetch", "-q", "origin", "main", branch], retry: true) do
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

  defp git(repo, args, opts \\ []) do
    run = fn -> Server.Git.cmd(repo, args) end

    case if(opts[:retry], do: GitFetch.retry(run), else: run.()) do
      {out, 0} -> {:ok, String.trim(out)}
      {out, _} -> {:error, "git #{hd(args)} failed: #{out |> String.trim() |> String.slice(-300, 300)}"}
    end
  end

  # a landing recorded with no thread still has an operator: its line goes to the standing thread
  defp post(nil, body), do: Server.Jobs.Alarm.post(body)

  defp post(thread_id, body) do
    Server.Channel.post(%{thread_id: thread_id, author: "tlon", body: body})
    :ok
  rescue
    _ -> :ok
  end

  defp open_pr(repo, branch, run) do
    args = ["pr", "list", "--head", branch, "--base", "main", "--state", "open", "--json", "number"]

    with {out, 0} <- run.("gh", args, cd: repo),
         {:ok, prs} when is_list(prs) <- Jason.decode(out) do
      case prs do
        [%{"number" => pr}] -> {:ok, pr}
        [] -> {:error, "#{branch} has no open PR onto main"}
        many -> {:error, "#{branch} has #{length(many)} open PRs onto main — land one by number"}
      end
    else
      _ -> {:error, "gh could not list #{branch}'s open PRs"}
    end
  end

  defp gh, do: Application.get_env(:server, :gh_cmd, &Server.Cmd.run/3)
end
