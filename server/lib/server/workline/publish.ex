defmodule Server.Workline.Publish do
  @moduledoc """
  An approved workline's branch is rebased onto origin's main and gated (`Server.Workline.Merge`);
  this carries it to GitHub, whose main takes only PRs — the only way a landing reaches main, which
  this machine's checkout then follows: push `work/<slug>`, open a PR, and ask GitHub to rebase-merge
  it once its checks pass (`gh pr merge --auto`; with auto-merge off on the repo the PR stays open,
  its link on the thread). A repo with no `origin` is `:none` — nothing to publish to.
  """

  @doc "Publish `work/<slug>` from `repo`. `{:ok, pr_url}` | `:none` | `{:error, why}`."
  def publish(repo, slug, title, run \\ &System.cmd/3) do
    branch = "work/#{slug}"
    opts = [cd: repo, stderr_to_stdout: true]

    with {_, 0} <- run.("git", ["-C", repo, "remote", "get-url", "origin"], opts),
         {:push, {_, 0}} <- {:push, run.("git", ["-C", repo, "push", "--force-with-lease", "origin", branch], opts)},
         {:pr, {out, 0}} <-
           {:pr,
            run.(
              "gh",
              ["pr", "create", "--head", branch, "--base", "main", "--title", title, "--body", body(slug)],
              opts
            )} do
      url = out |> String.split("\n", trim: true) |> List.last() |> String.trim()
      _ = run.("gh", ["pr", "merge", url, "--rebase", "--auto", "--delete-branch"], opts)
      {:ok, url}
    else
      {:push, {out, _}} -> {:error, "push of #{branch} refused: #{String.slice(out, 0, 200)}"}
      {:pr, {out, _}} -> {:error, "PR for #{branch} not opened: #{String.slice(out, 0, 200)}"}
      {_out, _code} -> :none
    end
  end

  @doc """
  Keep its landings mergeable: GitHub's main must be up to date before a PR merges, so a landing
  published just before another merge sits `BEHIND` with auto-merge on and never lands. Each such
  PR on a `work/*` branch — the server's own, never a human's — is rebased onto main by GitHub
  (`gh pr update-branch --rebase`), which re-runs its checks and lets auto-merge go. Returns the
  PR numbers it refreshed; a repo `gh` can't read is `[]`.
  """
  def refresh_behind(repo, run \\ &System.cmd/3) do
    opts = [cd: repo, stderr_to_stdout: true]
    fields = "number,headRefName,mergeStateStatus,autoMergeRequest"

    with {out, 0} <- run.("gh", ["pr", "list", "--state", "open", "--json", fields], opts),
         {:ok, prs} when is_list(prs) <- Jason.decode(out) do
      for %{"number" => n, "headRefName" => "work/" <> _, "mergeStateStatus" => "BEHIND", "autoMergeRequest" => %{}} <-
            prs,
          match?({_, 0}, run.("gh", ["pr", "update-branch", to_string(n), "--rebase"], opts)),
          do: n
    else
      _ -> []
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
      case git.(["merge-base", "--is-ancestor", "HEAD", "origin/main"]) do
        {_, 0} ->
          case git.(["merge", "--ff-only", "-q", "origin/main"]) do
            {_, 0} -> :forwarded
            {out, _} -> {:error, String.slice(out, 0, 200)}
          end

        _ ->
          {ahead, _} = git.(["rev-list", "--count", "origin/main..HEAD"])

          {:diverged,
           ahead
           |> String.trim()
           |> Integer.parse()
           |> then(fn
             {n, _} -> n
             _ -> 0
           end)}
      end
    else
      {out, code} when is_binary(out) and code != 0 -> {:error, String.slice(out, 0, 200)}
      _ -> :skipped
    end
  end

  defp body(slug), do: "Workline `#{slug}`, approved at its review gate. Spec, plan and review are in `work/#{slug}/`."
end
