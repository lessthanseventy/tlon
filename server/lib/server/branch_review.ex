defmodule Server.BranchReview do
  @moduledoc """
  A review on tlon of a branch that is not a workline (a PR's branch): `approve` or `request_changes`
  of `branch` at `sha`, by a reviewer. Recorded as a check event (`check_passed` for approve),
  correlation `branch:<name>:review`, detail `{sha, verdict, by, body}`; the newest one is the branch's
  verdict, and `approves/4` says whether it lets a given head land. A workline's review is
  `Server.Workline.review_verdict/4`, not this.
  """

  import Ecto.Query

  @verdicts ~w(approve request_changes)

  @doc """
  Record a verdict: `%{branch, sha, verdict, by, body, thread_id}`, `sha` the full 40-hex commit read.
  With `repo:`, the commit must be in it and `by` must not have built it (`builders/3`: no review of
  your own work). `{:ok, event}` | `{:error, why}` (main, a short sha, an unknown verdict, a commit not
  in the repo, a builder reviewing).
  """
  def record(%{branch: branch, sha: sha, verdict: verdict, by: by, body: body} = attrs) do
    with nil <- malformed(branch, sha, verdict),
         nil <- if(attrs[:repo], do: not_reviewable(attrs.repo, branch, sha, by)) do
      Server.Dossier.record_event(%{
        thread_id: attrs[:thread_id],
        kind: if(verdict == "approve", do: "check_passed", else: "check_failed"),
        correlation: correlation(branch),
        detail: %{"sha" => sha, "verdict" => verdict, "by" => by, "body" => body}
      })
    else
      why -> {:error, why}
    end
  end

  @doc "The newest verdict on `branch`: `%{verdict, sha, by, body, at, thread_id}`, or nil when it has none."
  def latest(branch) do
    from(e in Server.Event,
      where: e.correlation == ^correlation(branch) and e.kind in ["check_passed", "check_failed"],
      order_by: [desc: e.id],
      limit: 1
    )
    |> Server.Repo.one()
    |> case do
      nil ->
        nil

      %{detail: d, created_at: at, thread_id: thread_id} ->
        %{verdict: d["verdict"], sha: d["sha"], by: d["by"], body: d["body"], at: at, thread_id: thread_id}
    end
  end

  @doc """
  Whether `branch`'s newest verdict lets `head` land: `{:ok, review}` when it approves `head` itself,
  or a commit whose patches are `head`'s, in order, by `git patch-id --stable` over `base..` (the head
  is that commit rebased onto main and nothing else), and its reviewer neither opened the PR
  (`opts[:pr_author]`) nor authored a commit on it; else `{:error, why}`. `opts[:base]` defaults to
  origin/main.
  """
  def approves(repo, branch, head, opts \\ []) do
    base = Keyword.get(opts, :base, "origin/main")

    case latest(branch) do
      nil ->
        {:error, "#{branch} has no review on tlon — a reviewer records one with review_branch"}

      %{verdict: "approve", by: by} = review when is_binary(by) ->
        cond do
          String.downcase(by) == String.downcase(opts[:pr_author] || "") ->
            {:error, "#{by} opened the PR and approved it: a review is someone else's"}

          built?(by, builders(repo, "#{base}..#{head}")) ->
            {:error, "#{by} authored a commit on #{branch} and approved it: a review is someone else's"}

          true ->
            approved_head(repo, branch, head, base, review)
        end

      %{sha: sha, by: by} ->
        {:error, "#{by}'s review of #{short(sha)} requests changes"}
    end
  end

  @doc """
  Who built the commits in `range` of `repo`: each one's git author and `Tlon-Author:` trailer,
  downcased, leaving out commits that touch only `exclude` paths (a workline's own review.md). A range
  git can't read is no one.
  """
  def builders(repo, range, exclude \\ []) do
    args =
      ["-C", repo, "log", "--format=%an%x00%(trailers:key=Tlon-Author,valueonly,separator=%x00)%x00", range, "--", "."] ++
        Enum.map(exclude, &":!#{&1}")

    case System.cmd("git", args, stderr_to_stdout: true) do
      {out, 0} ->
        out
        |> String.split(["\0", "\n"])
        |> MapSet.new(&(&1 |> String.trim() |> String.downcase()))
        |> MapSet.delete("")

      _ ->
        MapSet.new()
    end
  end

  @doc "Whether reviewer `by` is among `builders` (as `builders/3` names them)."
  def built?(by, builders), do: is_binary(by) and MapSet.member?(builders, String.downcase(by))

  defp approved_head(repo, branch, head, base, review) do
    case review do
      %{sha: ^head} ->
        {:ok, review}

      %{sha: sha, by: by} ->
        if rebased?(repo, base, sha, head),
          do: {:ok, review},
          else:
            {:error,
             "#{by} approved #{short(sha)}, but #{branch} is at #{short(head)} with changes since — review it again"}
    end
  end

  defp commit?(repo, sha),
    do: match?({_, 0}, System.cmd("git", ["-C", repo, "cat-file", "-e", "#{sha}^{commit}"], stderr_to_stdout: true))

  defp base(repo) do
    if match?(
         {_, 0},
         System.cmd("git", ["-C", repo, "rev-parse", "-q", "--verify", "origin/main"], stderr_to_stdout: true)
       ),
       do: "origin/main",
       else: "main"
  end

  defp rebased?(repo, base, approved, head) do
    commit?(repo, approved) and
      patches(repo, base, head) not in [nil, ""] and patches(repo, base, approved) == patches(repo, base, head)
  end

  defp patches(repo, base, sha) do
    script =
      ~S(git -C "$1" log --reverse -p --format="commit %H" "$2..$3" | git -C "$1" patch-id --stable | cut -d" " -f1)

    case System.cmd("sh", ["-c", script, "patches", repo, base, sha], stderr_to_stdout: true) do
      {out, 0} -> out
      _ -> nil
    end
  end

  defp short(sha), do: String.slice(sha || "", 0, 12)

  defp correlation(branch), do: "branch:#{branch}:review"

  defp malformed(branch, sha, verdict) do
    cond do
      not is_binary(branch) or not Regex.match?(~r{\A[A-Za-z0-9][A-Za-z0-9._/-]*\z}, branch) ->
        "#{inspect(branch)} is not a branch name"

      branch == "main" ->
        "main is never reviewed as a branch — review the branch that lands on it"

      not is_binary(sha) or not Regex.match?(~r/\A[0-9a-f]{40}\z/, sha) ->
        "the sha must be the full 40-hex commit you read (git rev-parse HEAD), not #{inspect(sha)}"

      verdict not in @verdicts ->
        "verdict must be approve or request_changes, not #{inspect(verdict)}"

      true ->
        nil
    end
  end

  defp not_reviewable(repo, branch, sha, by) do
    cond do
      not commit?(repo, sha) ->
        "#{short(sha)} is not in #{repo} — push #{branch} first, then review it"

      built?(by, builders(repo, "#{base(repo)}..#{sha}")) ->
        "#{by} authored a commit on #{branch}: a review is someone else's, never the builder's"

      true ->
        nil
    end
  end
end
