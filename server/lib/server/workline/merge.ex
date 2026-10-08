defmodule Server.Workline.Merge do
  @moduledoc """
  The approved workline's landing, readied for GitHub: `work/<slug>` is rebased onto origin's main
  (freshly fetched; in its worktree where it is checked out, else a throwaway one) and gated there.
  `Server.Workline.Publish` then pushes it and GitHub rebase-merges it. Local `main` is never
  touched — GitHub's merge gives the commits new ids, so a local fast-forward would hold copies that
  differ from origin's; the checkout's main only ever follows origin. A conflict is aborted, the
  branch left as it was — except one only on the office's golden frames (`office/test/golden.json`),
  which takes origin's side; a branch that touched `office/` has its frames re-hashed and committed
  after the rebase, before the gate. `{:ok, %{from, to}}` (origin's main, and the rebased branch tip), or
  `{:error, why}` in words the operator can act on.
  """

  @golden "office/test/golden.json"

  @doc """
  Ready `work/<slug>` in `repo` to land: fetch origin, rebase the branch onto `origin/main`, gate it.
  `opts[:gate]`, a `fn repo, branch -> {:ok, _} | {:error, why} end`, runs on the rebased branch —
  red, the branch keeps its rebase. `opts[:rehash]`, a `fn tree -> {:ok, _} | {:error, why} end`,
  rewrites the golden frames in the rebased checkout (default: `bun test/golden.ts` in its office).
  """
  @spec merge(String.t(), String.t(), keyword()) :: {:ok, %{from: String.t(), to: String.t()}} | {:error, String.t()}
  def merge(repo, slug, opts \\ []) do
    branch = "work/#{slug}"
    gate = Keyword.get(opts, :gate, fn _repo, _branch -> {:ok, :no_gate} end)
    rehash = Keyword.get(opts, :rehash, &bun_rehash/1)

    with {:ok, _} <- run(repo, ["rev-parse", "--verify", "--quiet", branch], "there is no branch #{branch}"),
         {:ok, _} <- run(repo, ["remote", "get-url", "origin"], "#{repo} has no origin to land on"),
         {:ok, _} <- run(repo, ["fetch", "--quiet", "origin", "main"], "could not fetch origin"),
         {:ok, from} <- run(repo, ["rev-parse", "origin/main"], "origin has no main"),
         {:ok, _} <- rebase(repo, branch, rehash),
         {:ok, _} <- gate.(repo, branch),
         {:ok, to} <- run(repo, ["rev-parse", branch], "no #{branch}") do
      {:ok, %{from: from, to: to}}
    end
  end

  # where the branch is checked out it can only be rebased there; elsewhere, in a throwaway worktree
  defp rebase(repo, branch, rehash) do
    case checked_out(repo, branch) do
      nil ->
        tmp = Path.join(System.tmp_dir!(), "tlon-land-#{System.unique_integer([:positive])}")

        with {:ok, _} <- run(repo, ["worktree", "add", "--quiet", tmp, branch], "could not check out #{branch}") do
          try do
            rebase_in(tmp, branch, rehash)
          after
            git(repo, ["worktree", "remove", "--force", tmp])
          end
        end

      tree ->
        rebase_in(tree, branch, rehash)
    end
  end

  # rebase drops the commits whose patch origin already has: this machine's copies of what GitHub
  # merged under new ids
  defp rebase_in(tree, branch, rehash) do
    case past_golden(tree, git(tree, ["rebase", "--quiet", "origin/main"])) do
      {:ok, _} ->
        rehash_golden(tree, rehash)

      {:conflict, out} ->
        _ = git(tree, ["rebase", "--abort"])

        {:error,
         "rebasing #{branch} onto origin/main hit a conflict, aborted — the branch is as it was: #{out |> without_hints() |> String.slice(0, 300)}"}
    end
  end

  # every branch that moves the room re-hashes golden.json, so two of them always conflict there;
  # origin's side is taken and the frames re-hashed once the rebase is done
  defp past_golden(_tree, {_, 0}), do: {:ok, :rebased}

  defp past_golden(tree, {out, _}) do
    case git(tree, ["diff", "--name-only", "--diff-filter=U"]) do
      {@golden <> "\n", 0} ->
        _ = git(tree, ["checkout", "--ours", "--", @golden])
        _ = git(tree, ["add", "--", @golden])
        # a commit that only re-hashed is empty once origin's side is taken
        step = if match?({_, 0}, git(tree, ["diff", "--cached", "--quiet"])), do: "--skip", else: "--continue"
        past_golden(tree, git(tree, ["rebase", step], [{"GIT_EDITOR", "true"}]))

      _ ->
        {:conflict, out}
    end
  end

  defp rehash_golden(tree, rehash) do
    {touched, 0} = git(tree, ["diff", "--name-only", "origin/main", "HEAD", "--", "office/"])

    if touched == "" or not File.exists?(Path.join(tree, @golden)) do
      {:ok, :rebased}
    else
      with {:ok, _} <- rehash.(tree), do: commit_golden(tree)
    end
  end

  defp commit_golden(tree) do
    case git(tree, ["status", "--porcelain", "--", @golden]) do
      {"", 0} ->
        {:ok, :rebased}

      _ ->
        run(
          tree,
          ["commit", "--quiet", "-m", "office: re-hash the golden frames on landing", "--", @golden],
          "could not commit the re-hashed golden frames"
        )
    end
  end

  defp bun_rehash(tree) do
    case System.find_executable("bun") do
      nil ->
        {:error, "re-hashing the golden frames needs bun, which is not on the PATH"}

      bun ->
        case System.cmd(bun, ["test/golden.ts"], cd: Path.join(tree, "office"), stderr_to_stdout: true) do
          {_, 0} -> {:ok, :rehashed}
          {out, _} -> {:error, "re-hashing the golden frames failed: #{String.slice(out, -300, 300)}"}
        end
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

  defp git(repo, args, env \\ []), do: System.cmd("git", ["-C", repo | args], stderr_to_stdout: true, env: env)
end
