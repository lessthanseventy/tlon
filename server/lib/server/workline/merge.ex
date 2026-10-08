defmodule Server.Workline.Merge do
  @moduledoc """
  The approved workline's landing, readied for GitHub: `work/<slug>` is rebased onto origin's main
  (freshly fetched; in its worktree where it is checked out, else a throwaway one) and gated there.
  `Server.Workline.Publish` then pushes it and GitHub rebase-merges it. Local `main` is never
  touched — GitHub's merge gives the commits new ids, so a local fast-forward would hold copies that
  differ from origin's; the checkout's main only ever follows origin. A conflict is aborted, the
  branch left as it was. `{:ok, %{from, to}}` (origin's main, and the rebased branch tip), or
  `{:error, why}` in words the operator can act on.
  """

  @doc """
  Ready `work/<slug>` in `repo` to land: fetch origin, rebase the branch onto `origin/main`, gate it.
  `opts[:gate]`, a `fn repo, branch -> {:ok, _} | {:error, why} end`, runs on the rebased branch —
  red, the branch keeps its rebase.
  """
  @spec merge(String.t(), String.t(), keyword()) :: {:ok, %{from: String.t(), to: String.t()}} | {:error, String.t()}
  def merge(repo, slug, opts \\ []) do
    branch = "work/#{slug}"
    gate = Keyword.get(opts, :gate, fn _repo, _branch -> {:ok, :no_gate} end)

    with {:ok, _} <- run(repo, ["rev-parse", "--verify", "--quiet", branch], "there is no branch #{branch}"),
         {:ok, _} <- run(repo, ["remote", "get-url", "origin"], "#{repo} has no origin to land on"),
         {:ok, _} <- run(repo, ["fetch", "--quiet", "origin", "main"], "could not fetch origin"),
         {:ok, from} <- run(repo, ["rev-parse", "origin/main"], "origin has no main"),
         {:ok, _} <- rebase(repo, branch),
         {:ok, _} <- gate.(repo, branch),
         {:ok, to} <- run(repo, ["rev-parse", branch], "no #{branch}") do
      {:ok, %{from: from, to: to}}
    end
  end

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

  # rebase drops the commits whose patch origin already has: this machine's copies of what GitHub
  # merged under new ids
  defp rebase_in(tree, branch) do
    case git(tree, ["rebase", "--quiet", "origin/main"]) do
      {_, 0} ->
        {:ok, :rebased}

      {out, _} ->
        _ = git(tree, ["rebase", "--abort"])

        {:error,
         "rebasing #{branch} onto origin/main hit a conflict, aborted — the branch is as it was: #{out |> without_hints() |> String.slice(0, 300)}"}
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
    |> without_hints()
    |> String.slice(-300, 300)
    |> case do
      "" -> why
      git -> "#{why} (git: #{git})"
    end
  end

  # git's advice lines say how to drive git by hand, not what went wrong
  defp without_hints(out),
    do: out |> String.split("\n") |> Enum.reject(&String.starts_with?(&1, "hint:")) |> Enum.join("\n") |> String.trim()

  defp git(repo, args), do: System.cmd("git", ["-C", repo | args], stderr_to_stdout: true)
end
