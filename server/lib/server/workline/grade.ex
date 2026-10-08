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
  decisions the change makes that the operator would want to make, and the fixes that would bring
  its high axes down. The whole grade is posted on the thread (`report/1`), so whoever picks the
  work up next starts from it. A grader that can't answer says so, and the workline waits for the
  operator.

  Recorded as an event correlated `workline:<slug>:grade` — `check_passed` with the grade in its
  detail, `check_failed` when the grader could not grade — and judged against the policy at read
  time, so a changed threshold applies to grades already on record.
  """

  alias Server.Thread
  alias Server.Workline.Artifacts.Git

  @axes ~w(scope reversibility blast detectability proof)
  @max_lines 400
  @file_budget 200_000

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

  @doc """
  The grader's prompt: the ticket, the plan, the diff, and every changed file in full as the branch
  has it — so a claim about the code around a hunk is read, not guessed. Files are added while they
  fit `@file_budget` characters; one that doesn't is named as left out.
  """
  def prompt(spec, plan, change) do
    {files, _left} =
      Enum.reduce(change.files, {[], @file_budget}, fn {path, text}, {acc, left} ->
        if String.length(text) <= left,
          do: {["=== #{path} ===\n#{text}" | acc], left - String.length(text)},
          else: {["=== #{path} — not included (over the grader's file budget) ===" | acc], left}
      end)

    """
    You are grading the risk of merging a change WITHOUT a human looking at it. A reviewer has
    already approved it. Do not review it again: say how much is at stake if that review was wrong.
    You are the last check before it lands unattended, so be a skeptic, and score from the code, not
    from what the ticket or the plan promise. You have the diff AND the full text of every changed
    file after the change: read the files before claiming anything about code outside a hunk.

    Score each axis 1 (low risk) to 5 (high risk):

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

    EVIDENCE. Every reason and every fix has a `kind` and a `quote`:
    - "fact": a claim about what this code does or doesn't do. Its `quote` is one line copied
      exactly, character for character, from the diff or the files below, that shows it. Quotes are
      checked against the change by a script; a fact whose quote is not there is shown as
      unverified. If you cannot point at a line, you have not verified it: say so rather than guess.
    - "opinion": a judgment no line can prove — style, idiom, standard practice, a better design.
      Its `quote` is the line it is about, if there is one. It is shown as your opinion, which is
      what it is; do not dress one up as a fact.
    A low score is a claim of safety: give it a fact, or it cannot let the change land unattended.

    Then list `decisions`: choices the change makes that its owner would want to be asked about —
    product or UX behaviour, policy, what people will see — where the ticket left it open and a
    reasonable owner might well choose differently. Not implementation details a competent engineer
    settles without asking (limits, formats, internal names): those belong in the scores, if anywhere.
    Most changes leave none; an empty list then.

    Last, `fixes`: for every axis you scored 3 or more, the concrete step that would bring it down —
    which file, which test to add, what to change, quoting the line it starts from. Whoever picks
    this up next starts from your list instead of re-reading the diff, so name the place, not the
    principle. An empty list if every axis is under 3.

    Answer with ONLY this JSON object, nothing before or after it:
    {"scores": {"scope": 1, "reversibility": 1, "blast": 1, "detectability": 1, "proof": 1},
     "reasons": {"scope": {"why": "…", "kind": "fact", "quote": "…"},
                 "reversibility": {"why": "…", "kind": "fact", "quote": "…"},
                 "blast": {"why": "…", "kind": "fact", "quote": "…"},
                 "detectability": {"why": "…", "kind": "fact", "quote": "…"},
                 "proof": {"why": "…", "kind": "fact", "quote": "…"}},
     "decisions": [],
     "fixes": [{"fix": "…", "kind": "fact", "quote": "…"}]}

    TICKET (spec.md):
    #{spec || "(none committed)"}

    PLAN (plan.md):
    #{plan || "(none committed)"}

    DIFF:
    #{change.diff}

    FILES AFTER THE CHANGE:
    #{files |> Enum.reverse() |> Enum.join("\n\n")}
    """
  end

  @doc """
  The grader's answer → `{:ok, %{"scores", "reasons", "decisions", "fixes"}}`, or `{:error, why}`
  unless every axis is scored 1–5. Each reason (`%{"why", "kind", "quote"}`) and fix (`%{"fix",
  "kind", "quote"}`) keeps its `kind` — `"opinion"` as the grader said, anything else a `"fact"` —
  and gains `"grounded"`: whether its quote is really in `material` (the diff and the files),
  whitespace aside. The object is taken from the first `{` to the last `}`, since a CLI may wrap
  it in prose or a fence.
  """
  def parse(text, material) do
    with [json] <- Regex.run(~r/\{.*\}/s, text),
         {:ok, %{"scores" => scores} = g} when is_map(scores) <- Jason.decode(json),
         true <- Enum.all?(@axes, &(scores[&1] in 1..5)) do
      haystack = squash(material)
      reasons = if is_map(g["reasons"]), do: g["reasons"], else: %{}

      {:ok,
       %{
         "scores" => Map.take(scores, @axes),
         "reasons" => Map.new(@axes, &{&1, claim(reasons[&1], "why", haystack)}),
         "decisions" => Enum.filter(List.wrap(g["decisions"]), &(is_binary(&1) and &1 != "")),
         "fixes" => for(f <- List.wrap(g["fixes"]), is_map(f), is_binary(f["fix"]), do: claim(f, "fix", haystack))
       }}
    else
      _ -> {:error, "the grader's answer is not a grade: #{String.slice(String.trim(text), 0, 200)}"}
    end
  end

  defp claim(%{} = c, key, haystack) do
    quote = if is_binary(c["quote"]), do: c["quote"], else: ""
    needle = squash(quote)

    %{
      key => to_string(c[key]),
      "kind" => if(c["kind"] == "opinion", do: "opinion", else: "fact"),
      "quote" => quote,
      "grounded" => needle != "" and String.contains?(haystack, needle)
    }
  end

  defp claim(_, key, _haystack), do: %{key => "(no reason given)", "kind" => "fact", "quote" => "", "grounded" => false}

  defp squash(text), do: text |> String.replace(~r/\s+/u, " ") |> String.trim()

  @doc """
  Whether `grade` lets a workline land without the operator at `max` (every axis at or under it):
  no limit hit, no decision left to them, every axis scored and none over — and each axis's reason
  a fact, grounded, since a low score is a claim of safety and must show where it looked.
  """
  def allows?(%{"limits" => [], "decisions" => [], "scores" => scores, "reasons" => reasons}, max)
      when is_integer(max) do
    Enum.all?(@axes, &(is_integer(scores[&1]) and scores[&1] <= max and grounded?(reasons[&1])))
  end

  def allows?(_grade, _max), do: false

  defp grounded?(%{"kind" => "fact", "grounded" => true}), do: true
  defp grounded?(_), do: false

  @doc "The grade in one line for the approval card."
  def line(%{"limits" => [_ | _] = limits}), do: "risk: yours to judge — #{Enum.join(limits, ", ")}"

  def line(%{"scores" => scores} = grade) do
    worst = Enum.max_by(@axes, &scores[&1])
    axes = Enum.map_join(@axes, " · ", &"#{&1} #{scores[&1]}")
    why = if scores[worst] > 1, do: " (#{worst}: #{said(grade["reasons"][worst], "why")})", else: ""
    decides = if grade["decisions"] == [], do: "", else: " · leaves you: #{Enum.join(grade["decisions"], "; ")}"
    "risk #{axes}#{why}#{decides}"
  end

  defp said(%{"kind" => "opinion"} = c, key), do: "#{c[key]} (opinion)"
  defp said(%{"grounded" => true} = c, key), do: c[key]
  defp said(%{} = c, key), do: "#{c[key]} ⚠ unverified"
  defp said(_, _key), do: "no reason given"

  @doc """
  The whole grade for the thread, where its next pair of hands reads it: each axis with its
  evidence, what is left for the operator to decide, and the grader's fixes — a fact whose quote
  isn't in the change marked unverified, an opinion labelled one, so nobody acts on either as read.
  """
  def report(%{"limits" => [_ | _] = limits}),
    do: "⚖ risk grade: not graded — #{Enum.join(limits, ", ")}. Changes like this wait for the operator."

  def report(%{"scores" => scores} = grade) do
    axes = Enum.map(@axes, &"- #{&1} #{scores[&1]} — #{evidence(grade["reasons"][&1], "why")}")
    decisions = Enum.map(grade["decisions"], &"- #{&1}")
    fixes = Enum.map(grade["fixes"], &"- #{evidence(&1, "fix")}")

    Enum.join(
      ["⚖ risk grade (1 low – 5 high; ↳ the line each claim rests on)" | axes] ++
        if(decisions == [], do: [], else: ["", "left for the operator to decide:" | decisions]) ++
        if(fixes == [], do: [], else: ["", "fixes that would lower it:" | fixes]),
      "\n"
    )
  end

  defp evidence(%{"kind" => "opinion", "grounded" => true} = c, key), do: "#{c[key]}\n    (opinion) ↳ `#{c["quote"]}`"
  defp evidence(%{"kind" => "opinion"} = c, key), do: "#{c[key]}\n    (opinion)"
  defp evidence(%{"grounded" => true} = c, key), do: "#{c[key]}\n    ↳ `#{c["quote"]}`"
  defp evidence(%{} = c, key), do: "#{c[key]}\n    ⚠ unverified: its quote is not in the change"
  defp evidence(_, _key), do: "(no reason given)"

  @doc """
  Grade `thread`'s change, record it, and post the report on the thread. The limits first, read off
  the change: one hit and the grader isn't asked. `opts[:change]`/`opts[:docs]` swap what git
  would read (tests). `{:ok, grade}` | `{:error, why}` — both recorded.
  """
  def grade(%Thread{} = thread, opts \\ []) do
    change = Keyword.get_lazy(opts, :change, fn -> Git.change(thread) end)
    result = assess(change, fn -> Keyword.get_lazy(opts, :docs, fn -> docs(thread) end) end)
    record(thread, result)

    body =
      case result do
        {:ok, grade} -> report(grade)
        {:error, why} -> "⚖ risk grade: the grader could not grade this (#{why}). It waits for the operator."
      end

    Server.Channel.post(%{thread_id: thread.id, author: "grader", body: body})
    result
  end

  @doc """
  Grade `change` (`%{paths, deleted, lines, diff, files}`) against `docs` (`%{spec, plan}`, or a
  function giving them, read only when the grader is asked): the limits first, then the grader.
  Records and posts nothing — `grade/2` does that for a workline; a release grades its commits here.
  """
  def assess(change, docs) do
    case limits(change) do
      [] -> ask(change, if(is_function(docs, 0), do: docs.(), else: docs))
      limits -> {:ok, %{"limits" => limits}}
    end
  end

  defp docs(thread), do: %{spec: Git.doc(thread, "spec.md"), plan: Git.doc(thread, "plan.md")}

  defp ask(change, docs) do
    material = Enum.join([change.diff | Enum.map(change.files, &elem(&1, 1))], "\n")

    with {:ok, out} <-
           Server.ModelCli.prompt(prompt(docs.spec, docs.plan, change), :grader_cmd, :grader_model, {"claude", "opus"}),
         {:ok, grade} <- parse(out, material) do
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
