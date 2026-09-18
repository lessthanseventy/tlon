defmodule Server.MCP.Brief do
  @moduledoc """
  JSON-safe renderings of the reads the channel serves — one renderer per row
  type, shared by the `get_brief`/`get_facts` tools AND the resources: one
  source, two protocol doors. Every fact carries its read-time `certainty`
  (§4a: the certainty axis is a QUERY over provenance × check_cmd — `stated` >
  `checked` > `opinion`), so a brief can never launder an unchecked hunch into
  received truth (pi doc §2b). Caps keep their counts — a cut without a count
  lies.
  """

  alias Server.Event
  alias Server.Fact
  alias Server.Habit
  alias Server.Issue
  alias Server.Message
  alias Server.Note
  alias Server.Question
  alias Server.Ticket
  alias Server.Todo
  alias Server.Workspace

  @doc "A Board.brief/1 map, rendered."
  def scope(scope) do
    %{
      "thread_id" => scope.thread.id,
      "goal" => scope.goal,
      "todos" => capped(scope.todos, &todo/1),
      "next" => next(scope.next),
      "lead" => scope.lead,
      "done" => capped(scope.done, &done_entry/1),
      "learnings" => capped(scope.learnings, &fact/1),
      "unknowns" => capped(scope.unknowns, &question/1),
      "blockers" => capped(scope.blockers, &issue/1),
      "checks" => capped(scope.checks, &check/1),
      "commits" => capped(scope.commits, &commit/1),
      "workline" => workline(scope.workline),
      "cited" => Enum.map(scope.cited, &cited/1),
      "recent" => Enum.map(scope.recent, &message/1)
    }
  end

  @doc "A %{shown, more} cap, rendered with its count intact."
  def capped(%{shown: shown, more: more}, render) do
    %{"shown" => Enum.map(shown, render), "more" => more}
  end

  @doc "A commit the thread made — `Server.Commits` row; the sha is cut to 12 like the artifact checker's."
  def commit(%{sha: sha, subject: subject, author: author, at: at}) do
    %{"sha" => String.slice(sha, 0, 12), "subject" => subject, "author" => author, "at" => at}
  end

  @doc "The workline gate as the brief carries it — nil for a plain thread."
  def workline(nil), do: nil

  def workline(%{stage: stage, awaiting: awaiting, artifact_ok: ok, why: why}) do
    %{"stage" => stage, "awaiting" => awaiting, "artifact_ok" => ok, "why" => why}
  end

  @doc "A thread another message cited with `#N`, resolved."
  def cited(%{id: id, title: title, stage: stage, lead: lead}) do
    %{"id" => id, "title" => title, "stage" => stage, "lead" => lead}
  end

  @doc "A playbook — name, summary, steps, success, where it came from."
  def playbook(%Server.Playbook{} = p) do
    %{
      "name" => p.name,
      "summary" => p.summary,
      "steps" => p.steps,
      "success" => p.success,
      "author" => p.author,
      "source_thread_id" => p.source_thread_id
    }
  end

  @doc "A fact with its read-time certainty rank."
  def fact(%Fact{} = f) do
    %{
      "id" => f.id,
      "kind" => f.kind,
      "text" => f.text,
      "provenance" => f.provenance,
      "check_cmd" => f.check_cmd,
      "certainty" => certainty(f),
      "at" => at(f.created_at)
    }
  end

  @doc """
  The §4 total order, computed at read time and named in words: `stated` (the
  operator's own quoted words), `checked` (derived, carrying the command that
  re-runs it), `opinion` (derived and unverifiable — rank it last, re-verify
  before building on it).
  """
  def certainty(%Fact{provenance: "stated"}), do: "stated"
  def certainty(%Fact{check_cmd: nil}), do: "opinion"
  def certainty(%Fact{}), do: "checked"

  @doc "An event; `summary`/`evidence` surface from its human-readable detail."
  def event(%Event{} = e) do
    detail = e.detail || %{}

    %{
      "id" => e.id,
      "kind" => e.kind,
      "summary" => detail["summary"],
      "evidence" => detail["evidence"],
      "at" => at(e.created_at)
    }
  end

  @doc "A todo — a plan step. `done_at` present only when done (it opens NULL)."
  def todo(%Todo{} = t) do
    %{
      "id" => t.id,
      "text" => t.text,
      "done_at" => at(t.done_at),
      "at" => at(t.created_at)
    }
  end

  @doc "NEXT — the first open todo, or nil (derived, never stored)."
  def next(nil), do: nil
  def next(%Todo{} = t), do: todo(t)

  @doc """
  One entry of the merged DONE view, tagged by `source`: a completed `todo` or a
  `work_landed` event, each at its own timestamp — the merge, never a copy.
  """
  def done_entry(%{source: :todo, at: done_at, row: %Todo{} = t}) do
    %{"source" => "todo", "id" => t.id, "text" => t.text, "at" => at(done_at)}
  end

  def done_entry(%{source: :event, row: %Event{} = e}) do
    e |> event() |> Map.put("source", "event")
  end

  @doc "A question — an UNKNOWN. `resolution` is the answer once resolved (nil while open)."
  def question(%Question{} = q) do
    %{
      "id" => q.id,
      "text" => q.text,
      "state" => q.state,
      "resolution" => q.resolution,
      "at" => at(q.created_at)
    }
  end

  @doc "An issue — the stack's tracker (pi doc §4b)."
  def issue(%Issue{} = i) do
    %{
      "id" => i.id,
      "summary" => i.summary,
      "evidence" => i.evidence,
      "found_by" => i.found_by,
      "state" => i.state,
      "at" => at(i.created_at)
    }
  end

  @doc "A measured check — a `check_passed`/`check_failed` event, keyed on the real exit code."
  def check(%Event{kind: kind, created_at: created_at, detail: detail}) do
    d = detail || %{}

    %{
      "passed" => kind == "check_passed",
      "cmd" => d["cmd"],
      "exit" => d["exit"],
      "tail" => d["tail"],
      "at" => at(created_at)
    }
  end

  @doc "A message on the thread. A consult ASK (consult_id set, not a mirror) is flagged so a
  consumer can render it as a request for an answer, not ambient chatter."
  def message(%Message{} = m) do
    %{
      "id" => m.id,
      "author" => m.author,
      "body" => m.body,
      "reply_to" => m.reply_to,
      "at" => at(m.created_at),
      "consult" => m.consult_id != nil and m.mirrored == false
    }
  end

  @doc """
  A HABIT — how the agent should work with the operator. `state` distinguishes an approved,
  always-loaded preference from one still `pending` review; a cut without a count lies, and a
  pending habit is not an approved one.
  """
  def habit(%Habit{} = h) do
    %{
      "id" => h.id,
      "text" => h.text,
      "rationale" => h.rationale,
      "state" => h.state,
      "at" => at(h.created_at)
    }
  end

  @doc "A ticket row, rendered — the container tools' reply shape."
  def ticket(%Ticket{} = t) do
    %{
      "id" => t.id,
      "title" => t.title,
      "status" => t.status,
      "priority" => t.priority,
      "labels" => t.labels,
      "assignee" => t.assignee,
      # UX slice 4: a ticket ties to MANY threads, so the single promoted_thread_id is gone. The
      # promoted one is named on its own because it is the tie a caller usually means.
      "promoted_thread_id" => promoted_thread_id(t.id),
      "thread_ids" => Enum.map(Server.Tickets.threads_of(t.id), &elem(&1, 1)),
      "blocked_by" => Server.Tickets.blockers(t.id)
    }
  end

  @doc "A note row, rendered."
  def note(%Note{} = n),
    do: %{"id" => n.id, "scope" => n.scope, "scope_id" => n.scope_id, "body" => n.body, "author" => n.author}

  @doc """
  A WORKSPACE — a composition console reads to drive its picker/survey/spawn. Machine-global
  (no thread scope). `repos` is the git-tracked scope as ROWS (UX slice 5: a `path` plus the
  `remote` and `default_branch` a bare glob had nowhere to record); `roster`/`knobs` still
  round-trip as the JSON their columns hold.
  """
  def workspace(%Workspace{} = w) do
    %{
      "id" => w.id,
      "name" => w.name,
      "type" => w.type,
      "scope" => w.scope,
      "repos" => Enum.map(Server.Workspaces.repos(w.id), &workspace_repo/1),
      "roster" => w.id |> Server.Workspaces.bench() |> Enum.map(&Server.Coworker.to_wire/1),
      "knobs" => w.knobs,
      "at" => at(w.created_at)
    }
  end

  defp workspace_repo(%Server.WorkspaceRepo{} = r),
    do: %{"path" => r.path, "remote" => r.remote, "default_branch" => r.default_branch}

  defp at(nil), do: nil
  defp at(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  defp promoted_thread_id(ticket_id) do
    case Enum.find(Server.Tickets.threads_of(ticket_id), &(elem(&1, 0) == "promoted")) do
      {_kind, thread_id} -> thread_id
      nil -> nil
    end
  end
end
