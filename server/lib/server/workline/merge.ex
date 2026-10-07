defmodule Server.Workline.Merge do
  @moduledoc """
  The approved workline's last act: land its branch `work/<slug>` on `main` (first brought up to date
  with its remote), linearly — the branch
  is rebased onto main (in its worktree, where it is checked out), then main fast-forwards to it, as
  the remote takes no merge commits. It runs in the checkout people work in, so it is careful: only
  onto `main`, only with nothing uncommitted, and a conflict is aborted — main and the branch left
  as they were. `{:ok, %{from, to}}` (the main commits before and after), or `{:error, why}` in
  words the operator can act on.
  """

  @doc "Land `work/<slug>` on `main` in `repo`: rebase it onto main, fast-forward main."
  @spec merge(String.t(), String.t()) :: {:ok, %{from: String.t(), to: String.t()}} | {:error, String.t()}
  def merge(repo, slug) do
    branch = "work/#{slug}"

    with {:ok, _} <- run(repo, ["rev-parse", "--verify", "--quiet", branch], "there is no branch #{branch}"),
         {:ok, "main"} <- current(repo),
         {:ok, _} <-
           run(
             repo,
             ["diff", "--quiet"],
             "#{repo} has uncommitted changes — commit or set them aside, then approve again"
           ),
         {:ok, _} <-
           run(
             repo,
             ["diff", "--cached", "--quiet"],
             "#{repo} has staged, uncommitted changes — commit them, then approve again"
           ),
         {:ok, _} <- sync(repo),
         {:ok, from} <- run(repo, ["rev-parse", "HEAD"], "no HEAD"),
         {:ok, _} <- rebase(repo, branch),
         {:ok, _} <- run(repo, ["merge", "--ff-only", "--quiet", branch], "main could not fast-forward to #{branch}"),
         {:ok, to} <- run(repo, ["rev-parse", "HEAD"], "no HEAD") do
      {:ok, %{from: from, to: to}}
    else
      {:ok, other} -> {:error, "#{repo} is on #{other}, not main — the merge goes onto main"}
      {:error, _} = e -> e
    end
  end

  # main up to date with its remote first: what GitHub merged (as new commits, by rebase) is pulled
  # in and this machine's copies of it drop out, so the landing builds on what GitHub has
  defp sync(repo) do
    case git(repo, ["remote", "get-url", "origin"]) do
      {_, 0} ->
        run(
          repo,
          ["pull", "--rebase", "--quiet", "origin", "main"],
          "main could not be brought up to date with origin — sort it out, then approve again"
        )

      _ ->
        {:ok, :no_remote}
    end
  end

  defp current(repo), do: run(repo, ["symbolic-ref", "--short", "HEAD"], "#{repo} is not on a branch")

  # where the branch is checked out it can only be rebased there; elsewhere, in a throwaway worktree
  defp rebase(repo, branch) do
    case checked_out(repo, branch) do
      nil ->
        tmp = Path.join(System.tmp_dir!(), "tlon-land-#{System.unique_integer([:positive])}")

        with {:ok, _} <- run(repo, ["worktree", "add", "--quiet", tmp, branch], "could not check out #{branch}") do
          try do
            rebase_in(tmp, branch)
          after
            git(repo, ["worktree", "remove", "--force", tmp])
          end
        end

      tree ->
        rebase_in(tree, branch)
    end
  end

  defp rebase_in(tree, branch) do
    case git(tree, ["rebase", "--quiet", "main"]) do
      {_, 0} ->
        {:ok, :rebased}

      {out, _} ->
        _ = git(tree, ["rebase", "--abort"])

        {:error,
         "rebasing #{branch} onto main hit a conflict, aborted — main and the branch are as they were: #{String.slice(out, 0, 300)}"}
    end
  end

  defp checked_out(repo, branch) do
    {out, 0} = git(repo, ["worktree", "list", "--porcelain"])

    out
    |> String.split("\n\n", trim: true)
    |> Enum.find_value(fn entry ->
      lines = String.split(entry, "\n")
      if "branch refs/heads/#{branch}" in lines, do: lines |> hd() |> String.replace_prefix("worktree ", "")
    end)
  end

  defp run(repo, args, why) do
    case git(repo, args) do
      {out, 0} -> {:ok, String.trim(out)}
      {out, _} -> {:error, said(why, out)}
    end
  end

  # what git said, so the operator can act on the failure, not just learn which step it was
  defp said(why, out) do
    out
    |> String.trim()
    |> String.slice(-300, 300)
    |> case do
      "" -> why
      git -> "#{why} (git: #{git})"
    end
  end

  defp git(repo, args), do: System.cmd("git", ["-C", repo | args], stderr_to_stdout: true)
end
