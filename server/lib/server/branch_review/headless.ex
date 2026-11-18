defmodule Server.BranchReview.Headless do
  @moduledoc """
  A branch's review as one headless model run, for a branch no seat is on (any session's PR branch):
  the reviewer reads the diff in a throwaway checkout of the branch's head with read-only tools, its
  reply ends in a verdict line, and the verdict is recorded on that head as `Server.BranchReview`
  records any other; an approval then hands the branch's open PR to the merge queue
  (`Server.PRLanding.request_branch/3`). The reviewer is the first of `:branch_reviewers` that wrote
  none of the branch, by its commits' `Tlon-Model` and `Co-Authored-By` trailers: with none left the
  review is refused, never run on a builder's model. The rule is as good as the trailers: a commit
  that names no model counts as nobody's.
  """

  alias Server.BranchReview
  alias Server.Git

  @models ["anthropic/claude-sonnet-5-5", "anthropic/claude-opus-5-5"]
  @diff_budget 200_000
  @timeout_s 900

  @doc """
  Review `branch` of `repo` at its head (origin's, fetched, when the repo has an origin).
  `{:ok, %{verdict, sha, by, body, landing}}`, `by` the model that read it and `landing` what the
  merge queue said to an approval (nil for requested changes); `{:error, why}` with nothing recorded
  when the branch can't be read or changes nothing, every reviewer model built it, or the reply has
  no verdict line. `opts`: `:models` (default the `:branch_reviewers` app env), `:cmd` (the CLI;
  default `:reviewer_cmd`, else `claude`), `:land` (default `Server.PRLanding.request_branch/3`
  with no opts).
  """
  @spec review(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, String.t()}
  def review(repo, branch, opts \\ []) do
    with {:ok, %{verdict: verdict, sha: head, by: model, body: body}} <- opinion(repo, branch, opts),
         {:ok, _event} <-
           BranchReview.record(%{
             branch: branch,
             sha: head,
             verdict: verdict,
             by: model,
             body: body,
             repo: repo,
             thread_id: nil
           }) do
      {:ok, %{verdict: verdict, sha: head, by: model, body: body, landing: landing(verdict, repo, branch, opts)}}
    end
  end

  @doc """
  The review alone, recorded nowhere and queued nowhere: `{:ok, %{verdict, sha, by, body}}`, the
  errors and `opts` as `review/3`'s. For a branch of a repo whose reviews and landings are not this
  server's to keep.
  """
  @spec opinion(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, String.t()}
  def opinion(repo, branch, opts \\ []) do
    models = opts[:models] || Application.get_env(:server, :branch_reviewers, @models)

    with :ok <- named(branch),
         {:ok, base, head} <- refs(repo, branch),
         {:ok, model} <- reviewer(repo, "#{base}..#{head}", models),
         {:ok, diff} <- changes(repo, branch, "#{base}...#{head}"),
         {:ok, reply} <- read(repo, head, prompt(branch, head, diff), model, opts),
         {:ok, verdict, body} <- verdict(reply) do
      {:ok, %{verdict: verdict, sha: head, by: model, body: body}}
    end
  end

  defp named("main"), do: {:error, "main is never reviewed as a branch — review the branch that lands on it"}

  defp named(branch) do
    if Regex.match?(~r{\A[A-Za-z0-9][A-Za-z0-9._/-]*\z}, branch),
      do: :ok,
      else: {:error, "#{inspect(branch)} is not a branch name"}
  end

  defp refs(repo, branch) do
    {base, ref, fetched} =
      case Git.run(repo, ["remote", "get-url", "origin"]) do
        {:ok, _} -> {"origin/main", "origin/#{branch}", Git.run(repo, ["fetch", "-q", "origin", "main", branch])}
        {:error, _} -> {"main", branch, {:ok, ""}}
      end

    with {:ok, _} <- fetched,
         {:ok, head} <- Git.run(repo, ["rev-parse", "--verify", "-q", "#{ref}^{commit}"]) do
      {:ok, base, head}
    else
      {:error, why} -> {:error, "can't read #{branch}: #{why}"}
    end
  end

  defp changes(repo, branch, range) do
    case Git.run(repo, ["diff", range]) do
      {:ok, ""} -> {:error, "#{branch} changes nothing against main: there is nothing to review"}
      other -> other
    end
  end

  defp reviewer(repo, range, models) do
    format = "--format=%(trailers:key=Tlon-Model,valueonly)%n%(trailers:key=Co-Authored-By,valueonly)"

    with {:ok, trailers} <- Git.run(repo, ["log", format, range]) do
      built = slug(trailers)

      case Enum.find(models, &(not String.contains?(built, slug(name(&1))))) do
        nil ->
          {:error,
           "every reviewer model (#{Enum.join(models, ", ")}) wrote part of this branch: a review is another model's"}

        model ->
          {:ok, model}
      end
    end
  end

  # the family and version alone (`sonnet-5-5`), so a trailer that drops the vendor's prefix still matches
  defp name(model),
    do: model |> String.split("/") |> List.last() |> String.split(":") |> hd() |> String.replace_prefix("claude-", "")

  defp slug(text), do: text |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-")

  defp read(repo, head, prompt, model, opts) do
    dir = Path.join(System.tmp_dir!(), "tlon-review-#{System.unique_integer([:positive])}")
    cmd = opts[:cmd] || Application.get_env(:server, :reviewer_cmd, "claude")

    with {:ok, _} <- Git.run(repo, ["worktree", "add", "-q", "--detach", dir, head]) do
      try do
        # user settings only: the checkout's `.claude/settings.json` is the branch's, and its hooks
        # would run as the server
        run = [cd: dir, tools: "Read,Grep,Glob", settings: "user", timeout_s: @timeout_s]

        case Server.ModelCli.run(prompt, cmd, model, run) do
          {:ok, reply} -> {:ok, reply}
          {:error, why} -> {:error, "#{model} gave no review: #{inspect(why)}"}
        end
      after
        Git.cmd(repo, ["worktree", "remove", "--force", dir])
      end
    end
  end

  defp prompt(branch, head, diff) do
    """
    You are reviewing the branch `#{branch}` at commit #{head}, before it merges to main. Your working
    directory is a checkout of exactly that commit: read whatever the diff alone doesn't settle, and
    read the repo's AGENTS.md for its rules. You did not write this change.

    Look for what would hurt after the merge: wrong behaviour, an unhandled case the change makes
    reachable, a test that cannot fail, a doc or comment the change made untrue. Name each finding by
    file and line and say what input or state shows it. Leave style and taste alone. A finding you
    could not confirm by reading the code is a question, not a blocker; say which it is.

    Request changes only for something that must be fixed before the merge. End your reply with one
    line, exactly `VERDICT: approve` or `VERDICT: request_changes`, and nothing after it.

    The diff against main:

    #{cut(diff)}
    """
  end

  defp cut(diff) when byte_size(diff) > @diff_budget,
    do:
      String.slice(diff, 0, @diff_budget) <>
        "\n[the diff is cut here at #{@diff_budget} characters: read the rest in the checkout]"

  defp cut(diff), do: diff

  defp verdict(reply) do
    ~r/^VERDICT:[ \t]*(approve|request_changes)[ \t]*$/m
    |> Regex.scan(reply, return: :index)
    |> List.last()
    |> case do
      [{line, _}, {at, len}] ->
        {:ok, binary_part(reply, at, len), reply |> binary_part(0, line) |> String.trim()}

      nil ->
        {:error, "the reviewer's reply has no `VERDICT: approve` or `VERDICT: request_changes` line; nothing recorded"}
    end
  end

  defp landing("approve", repo, branch, opts) do
    land = opts[:land] || (&Server.PRLanding.request_branch/2)

    case land.(repo, branch) do
      {:ok, %{args: %{"pr" => pr}}} -> "queued PR ##{pr}"
      {:ok, _} -> "queued"
      {:error, why} when is_binary(why) -> "not queued: #{why}"
      {:error, why} -> "not queued: #{inspect(why)}"
    end
  end

  defp landing("request_changes", _repo, _branch, _opts), do: nil
end
