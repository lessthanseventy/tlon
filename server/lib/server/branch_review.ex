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
  `{:ok, event}` | `{:error, why}` (main, a short sha, an unknown verdict).
  """
  def record(%{branch: branch, sha: sha, verdict: verdict, by: by, body: body} = attrs) do
    cond do
      not is_binary(branch) or not Regex.match?(~r{\A[A-Za-z0-9][A-Za-z0-9._/-]*\z}, branch) ->
        {:error, "#{inspect(branch)} is not a branch name"}

      branch == "main" ->
        {:error, "main is never reviewed as a branch — review the branch that lands on it"}

      not is_binary(sha) or not Regex.match?(~r/\A[0-9a-f]{40}\z/, sha) ->
        {:error, "the sha must be the full 40-hex commit you read (git rev-parse HEAD), not #{inspect(sha)}"}

      verdict not in @verdicts ->
        {:error, "verdict must be approve or request_changes, not #{inspect(verdict)}"}

      true ->
        Server.Dossier.record_event(%{
          thread_id: attrs[:thread_id],
          kind: if(verdict == "approve", do: "check_passed", else: "check_failed"),
          correlation: correlation(branch),
          detail: %{"sha" => sha, "verdict" => verdict, "by" => by, "body" => body}
        })
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
  is that commit rebased onto main and nothing else); else `{:error, why}`.
  """
  def approves(repo, branch, head, base \\ "origin/main") do
    case latest(branch) do
      nil ->
        {:error, "#{branch} has no review on tlon — a reviewer records one with review_branch"}

      %{verdict: "approve", sha: ^head} = review ->
        {:ok, review}

      %{verdict: "approve", sha: sha, by: by} = review ->
        if rebased?(repo, base, sha, head),
          do: {:ok, review},
          else:
            {:error,
             "#{by} approved #{short(sha)}, but #{branch} is at #{short(head)} with changes since — review it again"}

      %{sha: sha, by: by} ->
        {:error, "#{by}'s review of #{short(sha)} requests changes"}
    end
  end

  defp rebased?(repo, base, approved, head) do
    match?({_, 0}, System.cmd("git", ["-C", repo, "cat-file", "-e", "#{approved}^{commit}"], stderr_to_stdout: true)) and
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
end
