defmodule Server.Workline.Publish do
  @moduledoc """
  An approved workline lands on this machine's main first (`Server.Workline.Merge`); this carries it
  to GitHub, whose main takes only PRs: push `work/<slug>`, open a PR, and ask GitHub to rebase-merge
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

  defp body(slug), do: "Workline `#{slug}`, approved at its review gate. Spec, plan and review are in `work/#{slug}/`."
end
