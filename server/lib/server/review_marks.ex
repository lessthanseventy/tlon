defmodule Server.ReviewMarks do
  @moduledoc """
  A branch's review, shown where the operator watches their sessions. Each tmux pane whose directory
  is a checkout of this repo carries the pane option `@arena_review`, which arena draws on its rail:
  `queued` while the branch's landing waits or runs; `landed` once the commit its newest review
  (`Server.BranchReview`) is of is on origin's main; `reviewed` or `changes` when that review is of
  the commit checked out; unset otherwise, so a commit made after a review clears the mark. Kept by
  a sweep (`Server.Jobs.ReviewMarks`), not by the events, so a pane that changes branch is right at
  the next pass. With no tmux there is nothing to mark.
  """

  import Ecto.Query

  @option "@arena_review"
  @panes ~S(#{pane_id}	#{pane_current_path}	#{@arena_review})

  @doc """
  Bring every pane's mark to its branch's state. `opts[:tmux]` runs tmux (`args -> {out, code}`),
  `opts[:repo]` is the checkout whose panes are marked, `opts[:queued]` says whether a branch's
  landing is in the queue.
  """
  @spec sweep(keyword()) :: :ok
  def sweep(opts \\ []) do
    tmux = opts[:tmux] || (&tmux/1)
    queued = opts[:queued] || (&queued?/1)
    repo = common(opts[:repo] || Server.Profiles.tlon_root())

    for [pane, dir, had] <- panes(tmux), repo != nil, common(dir) == repo, want = state(dir, queued), want != had do
      set(tmux, pane, want)
    end

    :ok
  end

  defp panes(tmux) do
    case tmux.(["list-panes", "-a", "-F", @panes]) do
      {out, 0} -> for line <- String.split(out, "\n", trim: true), do: String.split(line, "\t")
      _down -> []
    end
  end

  defp state(dir, queued) do
    with {:ok, branch} when branch != "main" <- git(dir, ~w(symbolic-ref --short -q HEAD)),
         {:ok, head} <- git(dir, ~w(rev-parse HEAD)) do
      of(queued.(branch), Server.BranchReview.latest(branch), head, dir)
    else
      _ -> ""
    end
  end

  defp of(true, _review, _head, _dir), do: "queued"
  defp of(false, nil, _head, _dir), do: ""

  defp of(false, %{sha: sha, verdict: verdict}, head, dir) do
    cond do
      git(dir, ["merge-base", "--is-ancestor", sha, "origin/main"]) == {:ok, ""} -> "landed"
      sha != head -> ""
      verdict == "approve" -> "reviewed"
      true -> "changes"
    end
  end

  defp set(tmux, pane, ""), do: tmux.(["set-option", "-p", "-u", "-t", pane, @option])
  defp set(tmux, pane, state), do: tmux.(["set-option", "-p", "-t", pane, @option, state])

  defp queued?(branch) do
    Server.Repo.exists?(
      from(j in Oban.Job,
        where:
          j.worker == "Server.Jobs.Land" and j.state in ["available", "scheduled", "executing", "retryable"] and
            fragment("?->>'branch' = ?", j.args, ^branch)
      )
    )
  end

  defp common(dir) do
    case git(dir, ~w(rev-parse --path-format=absolute --git-common-dir)) do
      {:ok, path} -> path
      :error -> nil
    end
  end

  defp git(dir, args) do
    case System.cmd("git", ["-C", dir | args], stderr_to_stdout: true) do
      {out, 0} -> {:ok, String.trim(out)}
      _failed -> :error
    end
  end

  defp tmux(args) do
    System.cmd("tmux", args, stderr_to_stdout: true)
  rescue
    ErlangError -> {"", 127}
  end
end
