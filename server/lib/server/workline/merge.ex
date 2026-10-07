defmodule Server.Workline.Merge do
  @moduledoc """
  The approved workline's last act: merge its branch `work/<slug>` into `main`. It runs in the
  checkout people work in, so it is careful: only onto `main`, only with nothing uncommitted, always
  a merge commit (`--no-ff`, so the work stays one reviewable unit), and a conflict is aborted —
  never a half-merged tree. `{:ok, %{from, to}}` (the main commits before and after), or
  `{:error, why}` in words the operator can act on.
  """

  @doc "Merge `work/<slug>` into `main` in `repo`, titled `title`."
  @spec merge(String.t(), String.t(), String.t()) :: {:ok, %{from: String.t(), to: String.t()}} | {:error, String.t()}
  def merge(repo, slug, title) do
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
         {:ok, from} <- run(repo, ["rev-parse", "HEAD"], "no HEAD"),
         {:ok, _} <- merge_commit(repo, branch, title),
         {:ok, to} <- run(repo, ["rev-parse", "HEAD"], "no HEAD") do
      {:ok, %{from: from, to: to}}
    else
      {:ok, other} -> {:error, "#{repo} is on #{other}, not main — the merge goes onto main"}
      {:error, _} = e -> e
    end
  end

  defp current(repo), do: run(repo, ["symbolic-ref", "--short", "HEAD"], "#{repo} is not on a branch")

  defp merge_commit(repo, branch, title) do
    case git(repo, ["merge", "--no-ff", "--no-edit", "-m", "Merge #{branch}: #{title}", branch]) do
      {_, 0} ->
        {:ok, :merged}

      {out, _} ->
        _ = git(repo, ["merge", "--abort"])
        {:error, "merging #{branch} hit a conflict, aborted — main is as it was: #{String.slice(out, 0, 300)}"}
    end
  end

  defp run(repo, args, why) do
    case git(repo, args) do
      {out, 0} -> {:ok, String.trim(out)}
      _ -> {:error, why}
    end
  end

  defp git(repo, args), do: System.cmd("git", ["-C", repo | args], stderr_to_stdout: true)
end
