defmodule Server.Librarian do
  @moduledoc """
  The steward of the office's memory. A workspace's librarian (bench archetype `librarian`) curates
  its facts: it decides the correction judge's proposals (`supersede_proposed` events), retires a
  fact a newer one restates (`supersede/4`) or tombstones junk (`forget/3`) — each with its reason
  on the record as a `superseded`/`forgotten` event — and posts a weekly count of what the office
  knows in the lobby (`report/3`). It never demotes a `stated` fact: the operator's words change
  only when he says so.

  The judge is its own module (`Server.Recall.Supersede`, read from `:supersede_judge` so a test can
  stand one in): `apply_proposal(event_id)` and `reject_proposal(event_id, reason)`. A server
  without them answers `{:error, :judge_not_installed}` and changes nothing.

  Its two standing duties are schedules (`ensure_schedules/2`): a daily sweep and a weekly report.
  """
  import Ecto.Query

  alias Server.Dossier
  alias Server.Event
  alias Server.Fact
  alias Server.Repo
  alias Server.Schedules

  # Events on a fact that are not a decision about it: use, checks, and the proposal itself.
  @not_decisions ~w(cited check_passed check_failed supersede_proposed)

  @schedules [
    %{
      title: "librarian's sweep",
      cron: "0 7 * * *",
      body: """
      The daily sweep of the office's memory. 1) review_proposals: read both facts of each, then \
      decide_proposal apply or reject, with the reason. 2) search_facts for duplicates, stale or \
      wrong facts, and placeholder junk ("...", empty restatements): supersede_fact or forget_fact \
      each, with the reason. A stated fact is not yours to change: ask_operator instead. 3) A fact \
      about code with no check: name the command that would re-check it in your summary. Post one \
      summary on this thread: what you changed and what waits on the operator.\
      """
    },
    %{
      title: "state of the office's knowledge",
      cron: "30 7 * * 1",
      body: """
      The weekly state of the office's knowledge: knowledge_report, with notes of three lines at \
      most — what changed this week and what is shaky. It posts in the lobby with the counts; no \
      @mention of the operator.\
      """
    }
  ]

  @doc "The workspace's librarian on its bench, or nil."
  def of(workspace_id) when is_integer(workspace_id),
    do: workspace_id |> Server.Workspaces.bench() |> Enum.find(&(&1.archetype == "librarian"))

  def of(_workspace_id), do: nil

  @doc """
  Retire `old_id` behind `new_id` (the newer fact's `supersedes`), recording a `superseded` event
  with `reason`. Options: `by` (who), `thread_id` (where the event lands), `workspace_id` (both
  facts must be in it). `{:ok, new_fact}` or `{:error, :no_reason | :same_fact | :not_found |
  :stated | :forgotten | {:already_supersedes, id}}`.
  """
  def supersede(old_id, new_id, reason, opts \\ []) do
    with :ok <- reason(reason),
         :ok <- if(old_id == new_id, do: {:error, :same_fact}, else: :ok),
         {:ok, old} <- fetch(old_id, opts[:workspace_id]),
         {:ok, new} <- fetch(new_id, opts[:workspace_id]),
         :ok <- unstated(old),
         :ok <- if(old.forgotten_at || new.forgotten_at, do: {:error, :forgotten}, else: :ok),
         :ok <- if(new.supersedes in [nil, old.id], do: :ok, else: {:error, {:already_supersedes, new.supersedes}}) do
      Repo.transaction(fn ->
        new = new |> Ecto.Changeset.change(supersedes: old.id) |> Repo.update!()
        record!("superseded", new.id, %{"old" => old.id, "reason" => reason}, opts)
        new
      end)
    end
  end

  @doc """
  Tombstone a fact (`Server.Dossier.forget_fact/1`), recording a `forgotten` event with `reason`.
  Options as `supersede/4`. `{:ok, fact}` or `{:error, :no_reason | :not_found | :stated}`.
  """
  def forget(fact_id, reason, opts \\ []) do
    with :ok <- reason(reason),
         {:ok, fact} <- fetch(fact_id, opts[:workspace_id]),
         :ok <- unstated(fact),
         {:ok, fact} <- Dossier.forget_fact(fact) do
      record!("forgotten", fact.id, %{"reason" => reason}, opts)
      {:ok, fact}
    end
  end

  @doc """
  The judge's open proposals in a workspace, oldest first: both facts still live, the new one not
  yet superseding the old, and no decision recorded on the new fact since (any later event on it
  but a citation or a check). Each is `%{event_id, verdict, reason, how, new, old}`, the facts as
  `%{id, text, provenance}`.
  """
  def proposals(workspace_id) do
    events = Repo.all(from e in Event, where: e.kind == "supersede_proposed", order_by: [asc: e.id])
    pairs = for e <- events, {:ok, new_id} <- [fact_id(e.correlation)], do: {e, new_id, int(e.detail["old"])}

    facts =
      from(f in Fact, where: f.id in ^Enum.flat_map(pairs, fn {_e, n, o} -> [n, o] end) and is_nil(f.forgotten_at))
      |> Fact.in_workspace(workspace_id)
      |> Repo.all()
      |> Map.new(&{&1.id, &1})

    later = decisions(Enum.map(pairs, fn {e, _n, _o} -> e.correlation end))

    for {e, new_id, old_id} <- pairs,
        %Fact{} = new <- [facts[new_id]],
        %Fact{} = old <- [facts[old_id]],
        new.supersedes != old.id,
        not Enum.any?(later[e.correlation] || [], &(&1 > e.id)) do
      %{
        event_id: e.id,
        verdict: e.detail["verdict"],
        reason: e.detail["reason"],
        how: e.detail["how"],
        new: brief(new),
        old: brief(old)
      }
    end
  end

  @doc """
  Decide a proposal: `"apply"` (through the judge's `apply_proposal/1`; refused over a stated fact)
  or `"reject"` (its `reject_proposal/2`, a reason required). Option `workspace_id`: the proposal's
  new fact must be in it. The judge's own answer, or `{:error, :not_a_proposal | :bad_decision |
  :no_reason | :stated | :judge_not_installed}`.
  """
  def decide(event_id, decision, reason, opts \\ []) do
    with {:ok, event, new_id} <- proposal(event_id),
         {:ok, _new} <- new_id |> fetch(opts[:workspace_id]) |> or_error(:not_a_proposal),
         :ok <- if(decision in ~w(apply reject), do: :ok, else: {:error, :bad_decision}) do
      decided(decision, event, reason)
    end
  end

  defp decided("apply", event, _reason) do
    with {:ok, old} <- fetch(int(event.detail["old"]), nil),
         :ok <- unstated(old),
         do: judge(:apply_proposal, [event.id])
  end

  defp decided("reject", event, reason) do
    with :ok <- reason(reason), do: judge(:reject_proposal, [event.id, reason])
  end

  @doc """
  What the office knows in a workspace, counted in the query: live facts by provenance, how many
  are superseded, this week's banked and forgotten, the shaky (derived with no check, a failed
  recheck this week), and the proposals waiting.
  """
  def stats(workspace_id) do
    week = DateTime.add(DateTime.utc_now(), -7, :day)
    scoped = Fact.in_workspace(Fact, workspace_id)
    superseded = from f in scoped, where: not is_nil(f.supersedes), select: f.supersedes
    live = from f in scoped, where: is_nil(f.forgotten_at) and f.id not in subquery(superseded)
    by = from(f in live, group_by: f.provenance, select: {f.provenance, count()}) |> Repo.all() |> Map.new()
    live_ids = Repo.all(from f in live, select: f.id)

    %{
      stated: by["stated"] || 0,
      derived: by["derived"] || 0,
      superseded: Repo.one(from f in scoped, where: not is_nil(f.supersedes), select: count(f.supersedes, :distinct)),
      banked: Repo.aggregate(from(f in scoped, where: f.created_at >= ^week), :count),
      forgotten: Repo.aggregate(from(f in scoped, where: f.forgotten_at >= ^week), :count),
      unchecked: Repo.aggregate(from(f in live, where: f.provenance == "derived" and is_nil(f.check_cmd)), :count),
      failed_recheck:
        Repo.one(
          from e in Event,
            where:
              e.kind == "check_failed" and e.created_at >= ^week and
                e.correlation in ^Enum.map(live_ids, &"fact:#{&1}"),
            select: count(e.correlation, :distinct)
        ),
      proposals: length(proposals(workspace_id))
    }
  end

  @doc """
  Post the weekly state of the office's knowledge in the workspace's lobby: `stats/1` as one line,
  then the librarian's `notes`. A record, delivered at birth, so it wakes no one. Option `by` is the
  author. `{:ok, message}` or `{:error, :mentions_operator | :no_lobby}`.
  """
  def report(workspace_id, notes, opts \\ []) do
    notes = String.trim(notes || "")
    lobby = Server.Channel.machine_thread(workspace_id)

    cond do
      ~r/@([\w.-]+)/ |> Regex.scan(notes) |> Enum.any?(fn [_, who] -> Server.Channel.operator?(who) end) ->
        {:error, :mentions_operator}

      is_nil(lobby) ->
        {:error, :no_lobby}

      true ->
        s = stats(workspace_id)

        counts =
          "📚 the office's knowledge: #{s.stated + s.derived} live facts (#{s.stated} stated, #{s.derived} derived), " <>
            "#{s.superseded} superseded in all. This week: +#{s.banked} banked, #{s.forgotten} forgotten. " <>
            "Shaky: #{s.unchecked} derived with no check, #{s.failed_recheck} failed a recheck. " <>
            "#{s.proposals} proposals waiting."

        {:ok, Schedules.note(lobby.id, String.trim("#{counts}\n\n#{notes}"), opts[:by] || "librarian")}
    end
  end

  @doc """
  The librarian's standing schedules in a workspace for the coworker `agent`: the daily sweep
  (07:00) and the weekly report (Mondays 07:30), each a standing agent run. Creates whichever is
  missing by title; returns both.
  """
  def ensure_schedules(workspace_id, agent) do
    existing = Map.new(Schedules.in_workspace(workspace_id), &{&1.title, &1})

    for s <- @schedules do
      case existing[s.title] do
        nil ->
          {:ok, created} =
            Schedules.create(Map.merge(s, %{workspace_id: workspace_id, kind: "agent", agent: agent, standing: true}))

          created

        found ->
          found
      end
    end
  end

  defp judge(fun, args) do
    mod = Application.get_env(:server, :supersede_judge, Server.Recall.Supersede)

    if Code.ensure_loaded?(mod) and function_exported?(mod, fun, length(args)),
      do: apply(mod, fun, args),
      else: {:error, :judge_not_installed}
  end

  defp proposal(event_id) do
    with %Event{kind: "supersede_proposed"} = e <- Repo.get(Event, event_id),
         {:ok, new_id} <- fact_id(e.correlation) do
      {:ok, e, new_id}
    else
      _ -> {:error, :not_a_proposal}
    end
  end

  # correlation => [event ids] of the decisions recorded on those facts
  defp decisions(correlations) do
    from(e in Event,
      where: e.correlation in ^correlations and e.kind not in @not_decisions,
      select: {e.correlation, e.id}
    )
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  defp fetch(id, workspace_id) when is_integer(id) do
    from(f in Fact, where: f.id == ^id)
    |> Fact.in_workspace(workspace_id)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      fact -> {:ok, fact}
    end
  end

  defp fetch(_id, _workspace_id), do: {:error, :not_found}

  defp or_error({:ok, _} = ok, _reason), do: ok
  defp or_error(_, reason), do: {:error, reason}

  defp unstated(%Fact{provenance: "stated"}), do: {:error, :stated}
  defp unstated(_fact), do: :ok

  defp reason(r) when is_binary(r), do: if(String.trim(r) == "", do: {:error, :no_reason}, else: :ok)
  defp reason(_), do: {:error, :no_reason}

  defp record!(kind, fact_id, detail, opts) do
    {:ok, _} =
      Dossier.record_event(%{
        thread_id: opts[:thread_id],
        kind: kind,
        correlation: "fact:#{fact_id}",
        detail: Map.put(detail, "by", opts[:by])
      })
  end

  defp fact_id("fact:" <> id),
    do:
      (case Integer.parse(id) do
         {n, ""} -> {:ok, n}
         _ -> :error
       end)

  defp fact_id(_), do: :error

  defp int(n) when is_integer(n), do: n

  defp int(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp int(_), do: nil

  defp brief(%Fact{} = f), do: %{id: f.id, text: f.text, provenance: f.provenance}
end
