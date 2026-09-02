defmodule Server.Dossier do
  @moduledoc """
  The dossier (console §9.4, spec §4/§5): `fact`, `event`, `issue`, `todo`, `question` and
  `habit` scoped to a thread — the thread's accumulated state, and the source of the brief's
  LEARNINGS, DONE, BLOCKERS, TODOS/NEXT, UNKNOWNS and CHECKS (`Server.Board.brief/1`). These
  are the judgement and the record a system cannot re-derive from a transcript; the channel
  (`Server.Channel`) and the staff (`Server.Staff`) own the rest of the spine.

  The open/recent reads are ranked and cut (§5/§6): `%{shown, more}`, at most five rows and
  the count of what was set aside, so a cut never reads as "this is everything". The raw
  per-thread reads (`facts_for_thread`, `shipped_for_thread`, `done_todos_for_thread`) return
  every row for the surfaces that rank them themselves.
  """
  import Ecto.Query

  alias Server.Bus
  alias Server.Channel
  alias Server.Event
  alias Server.Fact
  alias Server.Habit
  alias Server.Issue
  alias Server.Message
  alias Server.Question
  alias Server.Repo
  alias Server.Thread
  alias Server.Todo

  # Every capped read shows at most five rows; the rest is a number, never a
  # complete-and-useless list (§5 rank-and-cut, §1).
  @cap 5

  # A measured check outcome is one of these event kinds, keyed on the real exit code.
  @check_kinds ["check_passed", "check_failed"]

  @doc "Bank a durable fact. `{:ok, fact}` or `{:error, changeset}`."
  def bank_fact(attrs) do
    attrs |> Fact.bank_changeset() |> Repo.insert() |> Bus.announce(:fact_banked)
  end

  @doc """
  Manually forget a fact — the operator's tombstone, distinct from the recall engine's
  budget-driven forgetting. The row and its provenance stay; every recall surface
  (dossier, pinned, search) drops it. `{:ok, fact}` or `{:error, changeset}`.
  """
  def forget_fact(%Fact{} = fact) do
    fact |> Fact.forget_changeset() |> Repo.update() |> Bus.announce(:fact_forgotten)
  end

  @doc """
  Bank a STATED fact from the operator's own message — §4's capture path made
  mechanical (pi doc §2a). `stated` outranks everything by construction, so it is
  reachable only THROUGH a message row: the fact quotes the message body VERBATIM
  and is scoped to the message's thread. The message must be authored by the
  operator (`Channel.operator?/1`) — an agent's paraphrase, or an agent quoted by
  another agent, laundered into the owner's instruction is the one abuse the
  provenance ordering makes possible, refused here rather than by rule.
  `attrs` carries the judgement half (`kind`, optionally `check_cmd`/`incident`).
  Returns `{:ok, fact}`, `{:error, :not_the_operator}`, or `{:error, changeset}`.
  """
  def bank_stated_fact(%Message{} = message, attrs) do
    if Channel.operator?(message.author) do
      attrs
      |> Map.merge(%{
        text: message.body,
        provenance: "stated",
        thread_id: message.thread_id
      })
      |> bank_fact()
    else
      {:error, :not_the_operator}
    end
  end

  @doc """
  The always-loaded constraint set (§4): `provenance='stated' AND kind='constraint'`,
  the ~32 rows every session reads at start. A superseded constraint is excluded —
  superseding is explicit (a later fact's `supersedes` points at it), never inferred
  from recency. Newest first.

  Only a PEER retires a peer: the superseding fact must itself be a stated
  constraint. His constraints outrank our conclusions by construction (§4), so a
  `derived` fact — a paraphrase of his instruction — must never silently retire one.
  """
  def always_loaded_constraints(workspace_id \\ nil) do
    superseded =
      from f in Fact,
        where: not is_nil(f.supersedes) and f.provenance == "stated" and f.kind == "constraint",
        select: f.supersedes

    from(f in Fact,
      where:
        f.provenance == "stated" and f.kind == "constraint" and f.id not in subquery(superseded) and
          is_nil(f.forgotten_at),
      order_by: [desc: f.id]
    )
    |> Fact.in_workspace(workspace_id)
    |> Repo.all()
  end

  @doc "A thread's facts, scoped to it, newest first — the raw material for LEARNINGS."
  def facts_for_thread(%Thread{} = thread) do
    Repo.all(from f in Fact, where: f.thread_id == ^thread.id and is_nil(f.forgotten_at), order_by: [desc: f.id])
  end

  @doc "A fact by id, or nil — the load path for `recheck_fact`, scope-checked by its tool."
  def fact(id), do: Repo.get(Fact, id)

  @doc "Record an append-only event. `{:ok, event}` or `{:error, changeset}`."
  def record_event(attrs) do
    attrs |> Event.record_changeset() |> Repo.insert() |> Bus.announce(:event_recorded)
  end

  @doc """
  A thread's SHIPPED (§9.4): only `work_landed` events — the outcome kind, not the
  mechanism kinds around it. Newest first.
  """
  def shipped_for_thread(%Thread{} = thread) do
    Repo.all(
      from e in Event,
        where: e.thread_id == ^thread.id and e.kind == "work_landed",
        order_by: [desc: e.id]
    )
  end

  @doc "Raise a durable issue. `{:ok, issue}` or `{:error, changeset}`."
  def raise_issue(attrs) do
    attrs |> Issue.raise_changeset() |> Repo.insert() |> Bus.announce(:issue_raised)
  end

  @doc """
  Close an issue — a finding that has been settled — recording `resolution` when given. The
  operator's path is `tlon-cli.sh resolve-issue`; there is deliberately no MCP tool.
  """
  def resolve_issue(%Issue{} = issue, resolution \\ nil) do
    issue |> Issue.resolve_changeset(resolution) |> Repo.update() |> Bus.announce(:issue_resolved)
  end

  @doc """
  A thread's open issues, ranked and cut (§5): `%{shown: [issue], more: n}` where
  `shown` is at most five (newest first) and `more` counts the open issues beyond
  them. This is the BLOCKERS read `orient` calls at session start — the acceptance
  test §5 makes load-bearing: an issue table that no session reads must not exist.
  Closed issues and other threads' issues are excluded.
  """
  def open_issues_for_thread(%Thread{} = thread) do
    cut(from(i in Issue, where: i.thread_id == ^thread.id and i.state == "open"), desc: :id)
  end

  # Rank and cut (§5): the first `@cap` rows of `queryable` in `order`, and the count of the rest.
  defp cut(queryable, order) do
    shown = Repo.all(from q in queryable, order_by: ^order, limit: @cap)
    total = Repo.aggregate(queryable, :count, :id)
    %{shown: shown, more: total - length(shown)}
  end

  @doc "Add a plan step (todo) to a thread. `{:ok, todo}` or `{:error, changeset}`."
  def add_todo(attrs) do
    attrs |> Todo.add_changeset() |> Repo.insert() |> Bus.announce(:todo_added)
  end

  @doc """
  Mark a todo done — stamps `done_at`. Emits NO event: DONE is a merged view (todos by
  their `done_at`, plus `work_landed`), never a copy. `record_done` is the evidence-
  bearing verb for judgement-worthy outcomes.
  """
  def complete_todo(%Todo{} = todo) do
    todo |> Todo.done_changeset() |> Repo.update() |> Bus.announce(:todo_completed)
  end

  @doc "A todo by id, or nil — the load path for `complete_todo`, scope-checked by its tool."
  def todo(id), do: Repo.get(Todo, id)

  @doc """
  A thread's OPEN todos, ranked and cut (§5): `%{shown, more}`, `shown` at most five in
  INSERTION order (`id` asc) — so the head is NEXT, the derived first-open-todo. Completed
  todos and other threads' todos are excluded.
  """
  def open_todos_for_thread(%Thread{} = thread) do
    cut(from(t in Todo, where: t.thread_id == ^thread.id and is_nil(t.done_at)), asc: :id)
  end

  @doc """
  A thread's COMPLETED todos, most-recently-done first — the todo half of the DONE merged
  view. Ordered by `done_at` (then `id` for same-second ties), never copied into an event.
  """
  def done_todos_for_thread(%Thread{} = thread) do
    Repo.all(
      from t in Todo,
        where: t.thread_id == ^thread.id and not is_nil(t.done_at),
        order_by: [desc: t.done_at, desc: t.id]
    )
  end

  @doc "Raise a task question — a knowledge gap. `{:ok, question}` or `{:error, changeset}`."
  def raise_question(attrs) do
    attrs |> Question.raise_changeset() |> Repo.insert() |> Bus.announce(:question_raised)
  end

  @doc """
  Resolve a question — state resolved, `resolved_at` stamped, the optional `resolution`
  (the answer) recorded. A durable answer is banked as a `fact` separately; this only
  closes the gap. `{:ok, question}` or `{:error, changeset}`.
  """
  def resolve_question(%Question{} = question, resolution \\ nil) do
    question |> Question.resolve_changeset(resolution) |> Repo.update() |> Bus.announce(:question_resolved)
  end

  @doc "A question by id, or nil — the load path for `resolve_question`, scope-checked by its tool."
  def question(id), do: Repo.get(Question, id)

  @doc """
  A thread's OPEN questions, ranked and cut (§5): `%{shown, more}`, `shown` at most five
  (newest first) — the UNKNOWNS the brief surfaces beside FACTS. Resolved and other
  threads' questions are excluded.
  """
  def open_questions_for_thread(%Thread{} = thread) do
    cut(from(q in Question, where: q.thread_id == ^thread.id and q.state == "open"), desc: :id)
  end

  @doc """
  Record a MEASURED check: the command run, its real `exit` code, and a
  `tail` of output. exit 0 lands a `check_passed` event, anything else a `check_failed` —
  the outcome is keyed on the number, never on a self-report. `{:ok, event}` or
  `{:error, changeset}`. The agent runs the command (via `cap`); server only records.
  """
  def record_check(%{exit: exit} = attrs) do
    kind = if exit == 0, do: "check_passed", else: "check_failed"

    record_event(%{
      thread_id: attrs[:thread_id],
      kind: kind,
      correlation: attrs[:correlation],
      detail: %{"cmd" => attrs[:cmd], "exit" => exit, "tail" => attrs[:tail]}
    })
  end

  @doc """
  Re-verify a fact by re-running its OWN `check_cmd` (fact re-verification): the check
  is keyed on the real exit code and CORRELATED to the fact (`correlation: "fact:<id>"`),
  so a reader can tell "checked once, long ago" from "still passes" — and a `check_failed`
  is the drift signal that a claim `certainty` still calls `checked` has gone stale. The
  recorded `cmd` is PINNED to the fact's `check_cmd`; the agent re-runs it (via `cap`) and
  reports `exit`/`tail`, but cannot substitute a different command for the claim it proves.

  A fact with no `check_cmd` is unverifiable by construction (§4: `derived` WITHOUT a check
  ranks lowest) — there is nothing to re-run, so it is refused rather than faked.
  `{:ok, event}`, `{:error, :no_check_cmd}`, or `{:error, changeset}`.
  """
  def recheck_fact(%Fact{check_cmd: nil}, _attrs), do: {:error, :no_check_cmd}

  def recheck_fact(%Fact{check_cmd: cmd} = fact, %{exit: exit} = attrs) do
    record_check(%{
      thread_id: fact.thread_id,
      cmd: cmd,
      exit: exit,
      tail: attrs[:tail],
      correlation: "fact:#{fact.id}"
    })
  end

  @doc """
  A thread's recent checks (CHECKS), ranked and cut (§5): `%{shown, more}`, at most five
  `check_passed`/`check_failed` events, newest first — so the brief shows the current
  verification state (last check red or green), not a self-reported one.
  """
  def recent_checks_for_thread(%Thread{} = thread) do
    cut(from(e in Event, where: e.thread_id == ^thread.id and e.kind in ^@check_kinds), desc: :id)
  end

  @doc """
  Propose a HABIT — the agent's suggestion for how to work
  with the operator, distinct from a `stated` constraint (his verbatim words). It lands
  `pending`; the operator promotes it via `approve_habit/1`. `{:ok, habit}` or `{:error, cs}`.
  """
  def propose_habit(attrs) do
    attrs |> Habit.propose_changeset() |> Repo.insert() |> Bus.announce(:habit_proposed)
  end

  @doc """
  Approve a pending habit — state approved, `approved_at` stamped, and it joins the always-
  loaded set (`approved_habits/0`). This is the OPERATOR's act: it is deliberately NOT an
  agent-facing MCP tool (only `propose_habit` is), so an agent cannot approve its own
  proposal — the gate is architectural, not a runtime author check. Called from console /
  iex. `{:ok, habit}` or `{:error, changeset}`.
  """
  def approve_habit(%Habit{} = habit) do
    habit |> Habit.approve_changeset() |> Repo.update() |> Bus.announce(:habit_approved)
  end

  @doc "Reject a pending habit — the operator declines it; it never joins the always-loaded set."
  def reject_habit(%Habit{} = habit) do
    habit |> Habit.reject_changeset() |> Repo.update() |> Bus.announce(:habit_rejected)
  end

  @doc """
  The always-loaded approved habits — machine-wide, newest first. Mirrors
  `always_loaded_constraints/0`: the operator-approved "how to work" preferences every
  session reads at start, served over the channel by `Resource.Habits`.
  """
  def approved_habits do
    Repo.all(from h in Habit, where: h.state == "approved", order_by: [desc: h.id])
  end

  @doc "Habits awaiting review — the operator's queue, newest first (the console/iex review read)."
  def pending_habits(workspace_id \\ nil) do
    from(h in Habit, where: h.state == "pending", order_by: [desc: h.id])
    |> scope_habits_by_workspace(workspace_id)
    |> Repo.all()
  end

  defp scope_habits_by_workspace(query, nil), do: query

  defp scope_habits_by_workspace(query, workspace_id) do
    ids = from(t in Thread, where: t.workspace_id == ^workspace_id, select: t.id)
    from h in query, where: is_nil(h.source_thread_id) or h.source_thread_id in subquery(ids)
  end

  @doc "A habit by id, or nil — the load path for `approve_habit`/`reject_habit`."
  def habit(id), do: Repo.get(Habit, id)
end
