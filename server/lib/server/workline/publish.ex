defmodule Server.Workline.Publish do
  @moduledoc """
  An approved workline's branch is rebased onto origin's main and gated (`Server.Workline.Merge`);
  this carries it to GitHub, whose main takes only PRs — the only way a landing reaches main, which
  this machine's checkout then follows: push `work/<slug>`, open a PR, post `tlon/check` (main's
  required check, the local gate's commit status) on the sha the landing's gate passed on, and merge
  it at once at exactly that head (`gh pr merge --rebase --match-head-commit`). A publish no gate
  passed (a republish) posts nothing and arms auto-merge instead, which waits for a `tlon/check` on its
  head. A repo with no `origin` is `:none` — nothing to publish to.
  """

  @doc """
  Publish `work/<slug>` from `repo`. `landing[:gated]`, the sha the landing's gate passed on, is posted
  as the commit status `tlon/check` = success and the PR merged at once at that head; with none, no
  status is posted (it vouches only for a commit it gated) and auto-merge is armed. `{:ok, pr_url}` |
  `{:auto_refused, pr_url, why}` (the PR is open but GitHub refused to merge it, or to arm auto-merge)
  | `:none` | `{:error, why}`.
  """
  def publish(repo, slug, title, run \\ &System.cmd/3, landing \\ []) do
    branch = "work/#{slug}"
    opts = [cd: repo, stderr_to_stdout: true]

    with {_, 0} <- run.("git", ["-C", repo, "remote", "get-url", "origin"], opts),
         {:push, {_, 0}} <- {:push, run.("git", ["-C", repo, "push", "--force-with-lease", "origin", branch], opts)},
         {:pr, {out, 0}} <-
           {:pr,
            run.(
              "gh",
              ["pr", "create", "--head", branch, "--base", "main", "--title", title, "--body", body(repo, slug, run)],
              opts
            )} do
      url = out |> String.split("\n", trim: true) |> List.last() |> String.trim()

      merged =
        case landing[:gated] do
          nil ->
            arm_auto(url, opts, run)

          sha ->
            post_check(repo, sha, run)
            merge_at(repo, url, sha, branch, run)
        end

      case merged do
        {:error, why} -> {:auto_refused, url, why}
        _ -> {:ok, url}
      end
    else
      {:push, {out, _}} -> {:error, "push of #{branch} refused: #{String.slice(out, 0, 200)}"}
      {:pr, {out, _}} -> {:error, "PR for #{branch} not opened: #{String.slice(out, 0, 200)}"}
      {_out, _code} -> :none
    end
  end

  @doc """
  Merge PR `pr` (number or url) of `repo` at exactly `sha`, the head its landing gated
  (`--match-head-commit`). Merged, the remote `branch` is deleted, best-effort: a failure is logged,
  never a failed landing; no local branch is touched (gh's `--delete-branch` would delete the local
  one too, which a worktree may hold, and fail after GitHub merged). GitHub not having evaluated the
  fresh `tlon/check` yet arms auto-merge at that head instead. `:merged` | `:auto` | `{:error, why}`.
  """
  def merge_at(repo, pr, sha, branch, run \\ &System.cmd/3) do
    opts = [cd: repo, stderr_to_stdout: true]

    case run.("gh", ["pr", "merge", to_string(pr), "--rebase", "--match-head-commit", sha], opts) do
      {_, 0} ->
        delete_remote_head(repo, branch, run)
        :merged

      {out, _} ->
        if out =~ ~r/Required status check "tlon\/check" is expected/,
          do: arm_auto(to_string(pr), opts, run, ["--match-head-commit", sha]),
          else: {:error, out |> String.trim() |> String.slice(0, 300)}
    end
  end

  @doc """
  PR `url` as GitHub has it now: `{:ok, %{"state" => "OPEN" | "MERGED" | "CLOSED", "mergeStateStatus",
  "statusCheckRollup", "headRefOid"}}`, or `{:error, why}` when gh can't be read.
  """
  def view(repo, url, run \\ &System.cmd/3) do
    case run.("gh", ["pr", "view", url, "--json", "state,mergeStateStatus,statusCheckRollup,headRefOid"],
           cd: repo,
           stderr_to_stdout: true
         ) do
      {out, 0} ->
        case Jason.decode(out) do
          {:ok, %{} = pr} -> {:ok, pr}
          _ -> {:error, "gh pr view: not a JSON object: #{String.slice(out, 0, 200)}"}
        end

      {out, code} ->
        {:error, "gh pr view exited #{code}: #{String.slice(String.trim(out), 0, 200)}"}
    end
  end

  # the repo's open PRs as `gh` lists them: `{:ok, prs}`, or `{:error, why}` when gh can't be read
  defp open_prs(repo, fields, run) do
    case run.("gh", ["pr", "list", "--state", "open", "--json", fields], cd: repo, stderr_to_stdout: true) do
      {out, 0} ->
        case Jason.decode(out) do
          {:ok, prs} when is_list(prs) -> {:ok, prs}
          _ -> {:error, "gh pr list: not a JSON list: #{String.slice(out, 0, 200)}"}
        end

      {out, code} ->
        {:error, "gh pr list exited #{code}: #{String.slice(String.trim(out), 0, 200)}"}
    end
  end

  @doc """
  Fetch `branch`'s head on origin into its tracking ref, so a `push_branch/3` after it leases
  against what GitHub holds now — a head GitHub moved itself (an update-branch) is not a push the
  lease should refuse. `:ok` | `{:error, why}`.
  """
  def fetch_branch(repo, branch, run \\ &System.cmd/3) do
    refspec = "+refs/heads/#{branch}:refs/remotes/origin/#{branch}"

    case run.("git", ["-C", repo, "fetch", "origin", refspec], cd: repo, stderr_to_stdout: true) do
      {_, 0} -> :ok
      {out, _} -> {:error, "fetch of #{branch} refused: #{String.slice(String.trim(out), 0, 300)}"}
    end
  end

  @doc """
  Push one thread's branch to origin, force-with-lease — the only way a coworker's branch reaches
  GitHub (`push_branch`; the pre-push hook refuses a coworker pane's own pushes). Only a
  `work/<slug>` branch: never main, never anything else. `:ok` | `{:error, why}`.
  """
  def push_branch(repo, branch, run \\ &System.cmd/3) do
    if Regex.match?(~r{\Awork/[a-z0-9][a-z0-9-]*\z}, branch) do
      case run.("git", ["-C", repo, "push", "--force-with-lease", "origin", branch], cd: repo, stderr_to_stdout: true) do
        {_, 0} -> :ok
        {out, _} -> {:error, "push of #{branch} refused: #{String.slice(String.trim(out), 0, 300)}"}
      end
    else
      {:error, "#{branch} is not a thread's work/<slug> branch — only those are pushed"}
    end
  end

  @doc """
  Its landings GitHub can never merge: main moved under one after it landed and they now conflict
  (`DIRTY`), which no `update-branch` fixes. Each open PR on a `work/*` branch so marked, as
  `%{number, slug}`; a repo `gh` can't read is `{:error, why}`, never `[]`.
  """
  def conflicting(repo, run \\ &System.cmd/3) do
    with {:ok, prs} <- open_prs(repo, "number,headRefName,mergeStateStatus", run) do
      for %{"number" => n, "headRefName" => "work/" <> slug, "mergeStateStatus" => "DIRTY"} <- prs,
          do: %{number: n, slug: slug}
    end
  end

  @doc """
  Its landings whose checks went red: auto-merge waits on green, so such a PR stays open for good
  (`BEHIND`/`DIRTY` it is not). Each open PR on a `work/*` branch with a failed check, as
  `%{number, slug}`; one still pending is not failing. A repo `gh` can't read is `{:error, why}`, never `[]`.
  """
  def failing(repo, run \\ &System.cmd/3) do
    with {:ok, prs} <- open_prs(repo, "number,headRefName,statusCheckRollup", run) do
      for %{"number" => n, "headRefName" => "work/" <> slug} = pr <- prs,
          Enum.any?(pr["statusCheckRollup"] || [], &red?/1),
          do: %{number: n, slug: slug}
    end
  end

  @doc "Whether any of a PR's checks (`statusCheckRollup`, as `view/3` reads it) is still running."
  def checks_running?(pr), do: Enum.any?(pr["statusCheckRollup"] || [], &running?/1)

  defp running?(%{"status" => s}) when is_binary(s), do: s != "COMPLETED"
  defp running?(%{"state" => s}), do: s in ["PENDING", "EXPECTED"]
  defp running?(_), do: false

  # a CheckRun carries `conclusion`, a commit status `state`
  defp red?(%{"conclusion" => c}) when c in ["FAILURE", "TIMED_OUT", "STARTUP_FAILURE"], do: true
  defp red?(%{"state" => s}) when s in ["FAILURE", "ERROR"], do: true
  defp red?(_), do: false

  @doc "Close PR `number`, saying why; its branch stays for the next landing to push and open anew."
  def close(repo, number, why, run \\ &System.cmd/3) do
    case run.("gh", ["pr", "close", to_string(number), "--comment", why], cd: repo, stderr_to_stdout: true) do
      {_, 0} -> :ok
      {out, _} -> {:error, String.slice(out, 0, 200)}
    end
  end

  @doc """
  Keep `repo`'s main checkout a mirror of origin/main: on `main`, fetch and fast-forward to it.
  Never a merge or a rewrite — local main with commits of its own is `{:diverged, ahead}` for the
  operator to sort out; a checkout on another branch is `:skipped`. `:forwarded` (or already level),
  or `{:error, why}` when git refuses.
  """
  def follow_main(repo, run \\ &System.cmd/3) do
    git = fn args -> run.("git", ["-C", repo | args], stderr_to_stdout: true) end

    with {"main\n", 0} <- git.(["symbolic-ref", "--short", "HEAD"]),
         {_, 0} <- git.(["fetch", "-q", "origin", "main"]) do
      if match?({_, 0}, git.(["merge-base", "--is-ancestor", "HEAD", "origin/main"])),
        do: forward(git),
        else: diverged(git)
    else
      {out, code} when is_binary(out) and code != 0 -> {:error, String.slice(out, 0, 200)}
      _ -> :skipped
    end
  end

  defp forward(git) do
    case git.(["merge", "--ff-only", "-q", "origin/main"]) do
      {_, 0} -> :forwarded
      {out, _} -> {:error, String.slice(out, 0, 200)}
    end
  end

  defp diverged(git) do
    {ahead, _} = git.(["rev-list", "--count", "origin/main..HEAD"])

    case Integer.parse(String.trim(ahead)) do
      {n, _} -> {:diverged, n}
      :error -> {:diverged, 0}
    end
  end

  # The PR is where a reader lands from `git log` or GitHub: the builder's own account (pr.md, or
  # the plan's, spec's or intent's title when it wrote none), then what the server can state as fact
  # from the branch.
  defp body(repo, slug, run) do
    branch = "work/#{slug}"

    git = fn args ->
      case run.("git", ["-C", repo | args], stderr_to_stdout: true) do
        {out, 0} -> String.trim(out)
        _ -> ""
      end
    end

    show = fn name -> git.(["show", "#{branch}:work/#{slug}/#{name}"]) end
    summary = with "" <- show.("pr.md"), do: Enum.find_value(~w(plan.md spec.md intent.md), "", &heading(show.(&1)))

    [
      summary,
      section("Commits", git.(["log", "--reverse", "--format=- %s", "origin/main..#{branch}"])),
      section("Size", git.(["diff", "--shortstat", "origin/main...#{branch}", "--", ".", ":!work/"])),
      # every published branch was approved, and reviewers word it every which way: the line saying so
      section("Review", first_line(show.("review.md"), &(&1 =~ ~r/\bapprove/i))),
      "Workline `#{slug}`, approved at its review gate. Spec, plan and review are in `work/#{slug}/`."
    ]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  defp section(_name, ""), do: ""
  defp section(name, text), do: "**#{name}**\n#{text}"

  defp heading(text) do
    case first_line(text, & &1) do
      "" -> nil
      line -> line
    end
  end

  defp first_line(text, pick) do
    text
    |> String.split("\n")
    |> Enum.map(&(&1 |> String.trim_leading("#") |> String.trim()))
    |> Enum.find("", &(&1 != "" and pick.(&1)))
  end

  @doc """
  Post the commit status `tlon/check` = success on `sha` in `repo`'s GitHub repo: the required check
  on main, posted only for a commit a landing's gate passed on. A status gh can't post leaves the PR
  waiting on its check. gh's `{out, exit}`.
  """
  def post_check(repo, sha, run \\ &System.cmd/3) do
    run.(
      "gh",
      [
        "api",
        "repos/{owner}/{repo}/statuses/#{sha}",
        "-f",
        "state=success",
        "-f",
        "context=tlon/check",
        "-f",
        "description=the landing's gate (mise run check)"
      ],
      cd: repo,
      stderr_to_stdout: true
    )
  end

  defp delete_remote_head(repo, branch, run) do
    case run.("gh", ["api", "-X", "DELETE", "repos/{owner}/{repo}/git/refs/heads/#{branch}"],
           cd: repo,
           stderr_to_stdout: true
         ) do
      {_, 0} ->
        :ok

      {out, _} ->
        require Logger

        Logger.warning("merged, but the remote #{branch} wasn't deleted: #{String.slice(String.trim(out), 0, 200)}")
    end
  end

  # auto-merge: GitHub merges once its required check is green on the head
  defp arm_auto(pr, opts, run, how \\ ["--delete-branch"]) do
    case run.("gh", ["pr", "merge", pr, "--rebase", "--auto" | how], opts) do
      {_, 0} -> :auto
      {out, _} -> {:error, out |> String.trim() |> String.slice(0, 300)}
    end
  end
end
