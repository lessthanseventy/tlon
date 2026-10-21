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
  `opts[:branch]` names another local branch to land in its place (a PR's, `Server.PRLanding`).
  `opts[:gate]`, a `fn repo, branch -> {:ok, _} | {:error, why} end`, runs on the rebased branch —
  red, the branch keeps its rebase. `opts[:rehash]`, a `fn tree -> {:ok, _} | {:error, why} end`,
  rewrites the golden frames in the rebased checkout (default: `bun test/golden.ts` in its office).
  """
  @spec merge(String.t(), String.t() | nil, keyword()) ::
          {:ok, %{from: String.t(), to: String.t()}} | {:error, String.t()}
  def merge(repo, slug, opts \\ []) do
    branch = Keyword.get(opts, :branch, "work/#{slug}")
    gate = Keyword.get(opts, :gate, fn _repo, _branch -> {:ok, :no_gate} end)
    rehash = Keyword.get(opts, :rehash, &bun_rehash/1)

    with {:ok, _} <- run(repo, ["rev-parse", "--verify", "--quiet", branch], "there is no branch #{branch}"),
         {:ok, _} <- run(repo, ["remote", "get-url", "origin"], "#{repo} has no origin to land on"),
         {:ok, _} <- run(repo, ["fetch", "--quiet", "origin", "main"], "could not fetch origin"),
         {:ok, from} <- run(repo, ["rev-parse", "origin/main"], "origin has no main"),
         {:ok, _} <- rebase(repo, branch, rehash, "origin/main"),
         {:ok, _} <- gate.(repo, branch),
         {:ok, to} <- run(repo, ["rev-parse", branch], "no #{branch}") do
      {:ok, %{from: from, to: to}}
    end
  end

  @doc """
  Ready a merge train in `repo`: each `work/<slug>` of `slugs`, in order, rebased onto the one before
  it (the first onto a freshly fetched `origin/main`), then the last, which holds them all, gated once.
  `{:ok, %{from, cars: [%{slug, to, tree}]}}`, each car's tip and the tree the train put there, so a car
  re-landed later onto a main that holds the cars before it is known to be the train's by its tree;
  `{:error, {slug, why}}` for a conflict, `{:error, {:gate, why}}` for a red gate. `opts` as `merge/3`.
  """
  def stack(repo, slugs, opts \\ []) do
    gate = Keyword.get(opts, :gate, fn _repo, _branch -> {:ok, :no_gate} end)
    rehash = Keyword.get(opts, :rehash, &bun_rehash/1)

    with {:ok, _} <- run(repo, ["fetch", "--quiet", "origin", "main"], "could not fetch origin"),
         {:ok, from} <- run(repo, ["rev-parse", "origin/main"], "origin has no main"),
         {:ok, cars} <- stack_cars(repo, slugs, rehash),
         {:gate, {:ok, _}} <- {:gate, gate.(repo, "work/#{List.last(slugs)}")} do
      {:ok, %{from: from, cars: cars}}
    else
      {:gate, {:error, why}} -> {:error, {:gate, why}}
      {:error, _} = error -> error
    end
  end

  @doc "The tree `ref` points at in `repo`, or nil."
  def tree(repo, ref) do
    case git(repo, ["rev-parse", ref <> "^{tree}"]) do
      {out, 0} -> String.trim(out)
      _ -> nil
    end
  end

  defp stack_cars(repo, slugs, rehash) do
    slugs
    |> Enum.reduce_while({[], "origin/main"}, fn slug, {cars, onto} ->
      branch = "work/#{slug}"

      with {:ok, _} <- run(repo, ["rev-parse", "--verify", "--quiet", branch], "there is no branch #{branch}"),
           {:ok, _} <- rebase(repo, branch, rehash, onto),
           {:ok, to} <- run(repo, ["rev-parse", branch], "no #{branch}") do
        {:cont, {cars ++ [%{slug: slug, to: to, tree: tree(repo, branch)}], branch}}
      else
        {:error, why} -> {:halt, {:error, {slug, why}}}
      end
    end)
    |> case do
      {cars, _} when is_list(cars) -> {:ok, cars}
      error -> error
    end
  end

  # where the branch is checked out it can only be rebased there; elsewhere, in a throwaway worktree
  defp rebase(repo, branch, rehash, onto) do
    case checked_out(repo, branch) do
      nil ->
        tmp = Path.join(System.tmp_dir!(), "tlon-land-#{System.unique_integer([:positive])}")

        with {:ok, _} <- run(repo, ["worktree", "add", "--quiet", tmp, branch], "could not check out #{branch}") do
          try do
            rebase_in(tmp, branch, rehash, onto)
          after
            git(repo, ["worktree", "remove", "--force", tmp])
          end
        end

      tree ->
        rebase_in(tree, branch, rehash, onto)
    end
  end

  # rebase drops the commits whose patch origin already has: this machine's copies of what GitHub
  # merged under new ids
  defp rebase_in(tree, branch, rehash, onto) do
    # ExUnit's tmp_dir leaves ignored files here; git refuses to replay a commit that once tracked
    # one of them over its ignored copy
    _ = git(tree, ["clean", "-fdxq", "--", "server/tmp"])

    case past_golden(tree, git(tree, ["rebase", "--quiet", onto])) do
      {:ok, _} ->
        rehash_golden(tree, rehash)

      {:conflict, out} ->
        _ = git(tree, ["rebase", "--abort"])

        {:error,
         "rebasing #{branch} onto #{onto} hit a conflict, aborted — the branch is as it was: #{out |> without_hints() |> String.slice(0, 300)}"}
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
