defmodule Server.Workline.Grade do
  @moduledoc """
  The risk grade a reviewed workline carries to its merge gate: how much is at stake if the review
  that approved it was wrong — the question a standing approval (`auto_land_risk` in the settings
  file) is decided on, and the line the operator's approval card shows.

  Two halves. **Limits** are script, read off the change itself, and no grade argues past them: a
  migration, a dependency, the gate or CI, the law (`AGENTS.md`, the spec), a deleted test, or a
  change too big to grade in one read always waits for the operator. **Scores** are the grader's: a
  model that neither wrote nor reviewed the change (`:grader_cmd`/`:grader_model`; vendor is
  configuration) scores five axes 1 (low) to 5 (high), each with its evidence, and lists the
  decisions the change makes that the operator would want to make. A grader that can't answer
  records that it couldn't, and the workline waits for the operator.

  Recorded as an event correlated `workline:<slug>:grade` — `check_passed` with the grade in its
  detail, `check_failed` when the grader could not grade — and judged against the policy at read
  time, so a changed threshold applies to grades already on record.
  """

  alias Server.Thread
  alias Server.Workline.Artifacts.Git

  @axes ~w(scope reversibility blast detectability proof)
  @max_lines 400

  @doc "The axes a grade scores, in the order the card shows them."
  def axes, do: @axes

  @doc """
  The limits `change` (`%{paths, deleted, lines}`) hits, each a short reason — `[]` when none.
  """
  def limits(%{paths: paths, deleted: deleted, lines: lines}) do
    Enum.filter(
      [
        Enum.any?(paths, &(&1 =~ ~r{(^|/)priv/repo/migrations/})) && "a database migration",
        Enum.any?(
          paths,
          &(Path.basename(&1) in ~w(mix.exs mix.lock package.json bun.lock bun.lockb flake.nix flake.lock))
        ) && "a dependency change",
        Enum.any?(paths, &(&1 =~ ~r{^(\.github/|tasks/|mise\.toml$|scripts/workline-verify\.sh$)})) &&
          "the gate or CI itself",
        Enum.any?(paths, &(Path.basename(&1) in ~w(AGENTS.md CLAUDE.md) or String.ends_with?(&1, "docs/spec.md"))) &&
          "the law (AGENTS.md or the spec)",
        Enum.any?(deleted, &(&1 =~ ~r{(^|/)test/|_test\.exs$|\.test\.ts$})) && "a deleted test",
        lines > @max_lines && "#{lines} changed lines — over #{@max_lines}, too big to grade in one read"
      ],
      & &1
    )
  end

  @doc "The grader's prompt: the ticket, the plan and the diff, and what to score."
  def prompt(spec, plan, diff) do
    """
    You are grading the risk of merging a change WITHOUT a human looking at it. A reviewer has
    already approved it. Do not review it again: say how much is at stake if that review was wrong.
    You are the last check before it lands unattended, so be a skeptic, and score from the diff, not
    from what the ticket or the plan promise.

    Score each axis 1 (low risk) to 5 (high risk), each with one sentence of evidence from the diff:

    - scope: does the diff do what the ticket asks and nothing else? 1 = exactly the ticket;
      5 = it changes behaviour the ticket never mentions.
    - reversibility: would a plain `git revert` fully undo it? 1 = yes, code only; 5 = it writes,
      migrates or deletes stored data, publishes outside the repo, or changes what a revert can't reach.
    - blast: if it is wrong, what breaks? 1 = one cosmetic or isolated corner; 5 = a path everything
      depends on (state transitions, landing or merging, message delivery, auth, the database).
    - detectability: if it is wrong, how soon would anyone notice? 1 = loudly and at once (a crash,
      a red test, visibly wrong on screen); 5 = silently (wrong but plausible data, a check that
      quietly passes, a message that never arrives).
    - proof: do the tests in the diff pin the changed behaviour — would they fail without it?
      1 = yes, directly; 5 = behaviour changes and no test would notice.

    Then list `decisions`: choices the change makes that its owner would want to be asked about —
    product or UX behaviour, policy, what people will see — where the ticket left it open and a
    reasonable owner might well choose differently. Not implementation details a competent engineer
    settles without asking (limits, formats, internal names): those belong in the scores, if anywhere.
    Most changes leave none; an empty list then.

    Answer with ONLY this JSON object, nothing before or after it:
    {"scores": {"scope": 1, "reversibility": 1, "blast": 1, "detectability": 1, "proof": 1},
     "reasons": {"scope": "…", "reversibility": "…", "blast": "…", "detectability": "…", "proof": "…"},
     "decisions": []}

    TICKET (spec.md):
    #{spec || "(none committed)"}

    PLAN (plan.md):
    #{plan || "(none committed)"}

    DIFF:
    #{diff}
    """
  end

  @doc """
  The grader's answer → `{:ok, %{"scores", "reasons", "decisions"}}`, or `{:error, why}` unless
  every axis is scored 1–5. The object is taken from the first `{` to the last `}`, since a CLI
  may wrap it in prose or a fence.
  """
  def parse(text) do
    with [json] <- Regex.run(~r/\{.*\}/s, text),
         {:ok, %{"scores" => scores} = g} when is_map(scores) <- Jason.decode(json),
         true <- Enum.all?(@axes, &(scores[&1] in 1..5)) do
      {:ok,
       %{
         "scores" => Map.take(scores, @axes),
         "reasons" => if(is_map(g["reasons"]), do: Map.take(g["reasons"], @axes), else: %{}),
         "decisions" => Enum.filter(List.wrap(g["decisions"]), &(is_binary(&1) and &1 != ""))
       }}
    else
      _ -> {:error, "the grader's answer is not a grade: #{String.slice(String.trim(text), 0, 200)}"}
    end
  end

  @doc """
  Whether `grade` lets a workline land without the operator at `max` (every axis at or under it):
  no limit hit, no decision left to them, every axis scored and none over.
  """
  def allows?(%{"limits" => [], "decisions" => [], "scores" => scores}, max) when is_integer(max),
    do: Enum.all?(@axes, &(is_integer(scores[&1]) and scores[&1] <= max))

  def allows?(_grade, _max), do: false

  @doc "The grade in one line for the approval card."
  def line(%{"limits" => [_ | _] = limits}), do: "risk: yours to judge — #{Enum.join(limits, ", ")}"

  def line(%{"scores" => scores} = grade) do
    worst = Enum.max_by(@axes, &scores[&1])
    axes = Enum.map_join(@axes, " · ", &"#{&1} #{scores[&1]}")
    why = if scores[worst] > 1 and grade["reasons"][worst], do: " (#{worst}: #{grade["reasons"][worst]})", else: ""
    decides = if grade["decisions"] == [], do: "", else: " · leaves you: #{Enum.join(grade["decisions"], "; ")}"
    "risk #{axes}#{why}#{decides}"
  end

  @doc """
  Grade `thread`'s change and record it. The limits first, read off the change: one hit and the
  grader isn't asked. `opts[:change]`/`opts[:docs]` swap what git would read (tests).
  `{:ok, grade}` | `{:error, why}` — both recorded.
  """
  def grade(%Thread{} = thread, opts \\ []) do
    change = Keyword.get_lazy(opts, :change, fn -> Git.change(thread) end)

    result =
      case limits(change) do
        [] -> ask(change, Keyword.get_lazy(opts, :docs, fn -> docs(thread) end))
        limits -> {:ok, %{"limits" => limits}}
      end

    record(thread, result)
    result
  end

  defp docs(thread), do: %{spec: Git.doc(thread, "spec.md"), plan: Git.doc(thread, "plan.md")}

  defp ask(change, docs) do
    with {:ok, out} <-
           Server.ModelCli.prompt(
             prompt(docs.spec, docs.plan, change.diff),
             :grader_cmd,
             :grader_model,
             {"claude", "opus"}
           ),
         {:ok, grade} <- parse(out) do
      {:ok, Map.put(grade, "limits", [])}
    else
      {:error, why} when is_binary(why) -> {:error, why}
      {:error, why} -> {:error, "the grader could not run: #{inspect(why)}"}
    end
  end

  defp record(thread, result) do
    {kind, detail} =
      case result do
        {:ok, grade} -> {"check_passed", Map.merge(grade, %{"cmd" => "risk grade", "exit" => 0})}
        {:error, why} -> {"check_failed", %{"cmd" => "risk grade", "exit" => 1, "tail" => why}}
      end

    {:ok, _} =
      Server.Dossier.record_event(%{
        thread_id: thread.id,
        kind: kind,
        correlation: "workline:#{thread.slug}:grade",
        detail: detail
      })
  end
end
