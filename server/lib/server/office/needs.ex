defmodule Server.Office.Needs do
  @moduledoc """
  Everything waiting on the operator, as ONE list — derived from the state that already says so,
  never a second record that could drift from it. Each item is
  `%{key, kind, level, thread_id, workspace_id, title, text, at, options}`:

    * **blocking** — work has stopped until the operator acts:
      `gate` (a workline at its gate: approve), `question` (a coworker asked: reply), `dialog` (a pane
      sits on a prompt, or the PM's release gate waits: pick an option), `ask` (one decision a
      coworker filed with its answers, `Server.Attention.ask/4`: one item per ask, `ref` its id,
      answered by key), `verify_failed` (a workline whose last gate run was red —
      only where the workspace has no sheriff, who owns red there: `Server.Sheriff`);
    * **decide** — wants the operator, nothing waits on it: `mention` (an @operator on an open thread
      with no reply from them since, from the last 12 hours: one older than that is history, still on
      its thread), `rollout` (what a
      merge could not roll out itself), `stranded` (a worktree no thread is working in that holds
      work: merge it or delete it — `Server.Maintain.Strays`; a workline that landed within the hour
      is its PR waiting on GitHub's checks, and one in the merge queue is landing — neither is stranded),
      `seats` (threads parked on the leaf cap, per workspace: `ref` the bigger cap it offers),
      `job_failed` (a background job discarded in the last day: retry or dismiss, `ref` the job),
      `issue` (a blocker raised on an open thread and not resolved: resolve it, `ref` the issue).

  Blocking first, then to decide; oldest first within each. An item leaves the list when the thing
  behind it is resolved — approved, answered, filed — or when the operator puts it away (`dismiss/1`):
  never because it was looked at.

  Only what someone actually asked for, or the machine actually needs, is here: the corkboard's
  suggestions are banter written in a coworker's voice, not their request, so they stay in its
  suggestion box (`Server.Office.Corkboard.suggestions/1`) and never reach this list.
  """
  import Ecto.Query

  alias Server.Event
  alias Server.Message
  alias Server.Repo
  alias Server.Thread

  @mention_hours 12
  @landing_grace_s 3600

  @doc "Every item waiting on the operator, across the workspaces."
  def list do
    items = all()
    away = Map.new(Repo.all(from d in "need_dismissal", select: {d.key, type(d.at, :utc_datetime)}))
    prune(away, items)
    Enum.reject(items, &put_away?(&1, away[&1.key]))
  end

  @doc """
  The operator puts an item away without acting on it (the inbox's `d`): it leaves the list until
  something newer arrives under its key, a later mention on that thread say. An ask is withdrawn and
  its asker told; a failed job and a rollout note are dismissed as their kinds are. A gate, a dialog,
  a question or a red verify is never put away — work waits on it: approve, answer or fix it. `:ok`,
  `{:error, :blocking}`, or `{:error, :not_found}` for a key the list does not hold.
  """
  def dismiss(key) do
    case Enum.find(all(), &(&1.key == key)) do
      nil ->
        {:error, :not_found}

      %{kind: "ask", ref: id} ->
        withdraw_ask(id)
        remember(key)

      %{level: "blocking"} ->
        {:error, :blocking}

      %{kind: "job_failed", ref: id} ->
        dismiss_job(id)

      %{kind: "rollout", ref: id} ->
        Server.Rollout.dismiss(id)

      _ ->
        remember(key)
    end
  end

  @doc """
  The stranded checkout behind `key` taken down (`Server.Worktree.retire/2`): its branch stays. Only
  one the list still shows as stranded — `{:error, :not_stranded}` otherwise. `:ok` or `{:error, why}`.
  """
  def retire_stranded(key) do
    case Enum.find(stranded(), &(&1.key == key)) do
      nil ->
        {:error, :not_stranded}

      %{repo: repo, name: name} ->
        case Server.Worktree.retire(repo, name) do
          {:removed, _} -> :ok
          :none -> :ok
          {:kept, why} -> {:error, why}
        end
    end
  end

  # a pane on a prompt is a dialog; else an `awaiting` is a gate (workline at its gate) or a question
  defp waits(open, prompts) do
    for t <- open, item = wait(t, prompts[t.id]), item, do: item
  end

  defp wait(t, %{} = prompt),
    do: item("dialog", "blocking", t, prompt.summary, prompt_at(prompt.id), %{options: prompt.options})

  defp wait(%Thread{awaiting: nil}, nil), do: nil

  defp wait(%Thread{stage: stage} = t, nil) when not is_nil(stage) do
    if Server.Workline.at_gate?(t),
      do: item("gate", "blocking", t, gate_text(t, stage), t.created_at, %{stage: stage}),
      else: question(t)
  end

  defp wait(t, nil), do: question(t)

  # what to decide the gate on; git trouble only costs the detail
  defp gate_text(t, stage) do
    Server.Workline.gate_summary(t)
  rescue
    _ -> "#{t.slug} waits at #{stage} for your approval"
  end

  # the question is the newest message from someone other than the operator
  defp question(t) do
    operator = Application.get_env(:server, :operator, "andrew")

    m =
      Repo.one(
        from m in Message,
          where: m.thread_id == ^t.id and m.author != ^operator,
          order_by: [desc: m.id],
          limit: 1
      )

    item("question", "blocking", t, (m && m.body) || "waits on you", (m && m.created_at) || t.created_at)
  end

  defp prompt_at(id), do: Repo.one(from m in Message, where: m.id == ^id, select: m.created_at)

  # each ask is its own decision: answered by its id, so two on one thread never cross
  defp asks(open) do
    by_id = Map.new(open, &{&1.id, &1})

    for m <- Server.Attention.open_asks(), t = by_id[m.thread_id] do
      item("ask", "blocking", t, "#{m.payload["ask"]}: #{m.payload["summary"]}", m.created_at, %{
        key: "ask:#{m.id}",
        options: m.payload["options"],
        ref: m.id
      })
    end
  end

  # threads parked on the leaf cap: the cause of empty desks, with the bigger cap as its answer
  defp seats(open) do
    knob = Enum.find(Server.OperatorConfig.knobs(), &(&1.key == "max_leaves"))
    cap = knob.value
    target = min(cap + 2, knob.max)

    for {ws, threads} <-
          open |> Enum.filter(&(&1.agent_id && Server.Staffing.parked_note?(&1.id))) |> Enum.group_by(& &1.workspace_id),
        cap < target do
      %{
        key: "seats:#{ws}",
        kind: "seats",
        level: "decide",
        thread_id: nil,
        workspace_id: ws,
        title: "work waits for a seat",
        text:
          "#{length(threads)} threads wait for a seat (the leaf cap is #{cap}): " <>
            Enum.map_join(threads, ", ", &"##{&1.id} #{&1.title}"),
        at: threads |> Enum.map(& &1.created_at) |> Enum.min(DateTime),
        options: [%{"key" => "1", "label" => "raise the cap to #{target}"}],
        ref: target
      }
    end
  end

  @doc "Background jobs discarded in the last day that nobody has dismissed (`dismiss_job/1`)."
  def failed_jobs_query do
    day = DateTime.add(DateTime.utc_now(), -86_400)

    from j in Oban.Job,
      where:
        j.state in ["discarded", "retryable"] and j.attempted_at > ^day and
          fragment("NOT coalesce((? ->> 'dismissed')::boolean, false)", j.meta)
  end

  defp failed_jobs do
    for j <- Repo.all(failed_jobs_query()) do
      %{
        key: "job:#{j.id}",
        kind: "job_failed",
        level: "decide",
        thread_id: nil,
        workspace_id: nil,
        title: "#{j.worker} failed",
        text: last_error(j.errors),
        at: j.attempted_at,
        options: nil,
        ref: j.id
      }
    end
  end

  defp last_error([_ | _] = errors), do: errors |> List.last() |> Map.get("error", "no error recorded")
  defp last_error(_), do: "no error recorded"

  @doc "The operator has seen a failed job: it leaves the list and the rack's count. `:ok`."
  def dismiss_job(id) do
    {_, _} =
      Repo.update_all(
        from(j in Oban.Job,
          where: j.id == ^id,
          update: [set: [meta: fragment("coalesce(?, '{}'::jsonb) || '{\"dismissed\": true}'::jsonb", j.meta)]]
        ),
        []
      )

    :ok
  end

  @doc "Run a failed job again. `:ok`."
  def retry_job(id), do: Oban.retry_job(id)

  # a workline sitting at verify whose newest verify run was red — where no sheriff owns red
  defp red_verifies(open) do
    for %Thread{stage: "verify", slug: slug} = t <- open,
        Server.Sheriff.of(t.workspace_id) == nil,
        %{kind: "check_failed"} = e <- [last_verify(slug)],
        do:
          item(
            "verify_failed",
            "blocking",
            t,
            "verify is red: #{e.detail["cmd"]} (exit #{e.detail["exit"]})",
            e.created_at
          )
  end

  defp last_verify(slug) do
    Repo.one(
      from e in Event,
        where: e.correlation == ^"workline:#{slug}:verify" and e.kind in ["check_passed", "check_failed"],
        order_by: [desc: e.id],
        limit: 1
    )
  end

  # an @operator nobody has answered: the newest such message per open thread, with no operator
  # message after it
  defp mentions(open, operator) do
    since = DateTime.add(DateTime.utc_now(), -@mention_hours * 3600, :second)
    ids = Enum.map(open, & &1.id)
    by_id = Map.new(open, &{&1.id, &1})
    like = "%@#{operator}%"

    from(m in Message,
      where:
        m.thread_id in ^ids and m.kind != "suggestion" and m.author != ^operator and ilike(m.body, ^like) and
          m.created_at > ^since,
      order_by: [desc: m.id]
    )
    |> Repo.all()
    |> Enum.uniq_by(& &1.thread_id)
    # a thread already waiting on the operator is on the list as its question, not twice
    |> Enum.reject(&(by_id[&1.thread_id].awaiting != nil or settled?(&1, operator)))
    |> Enum.map(&item("mention", "decide", by_id[&1.thread_id], "#{&1.author}: #{&1.body}", &1.created_at))
  end

  # a reply settles a mention; so does the workline moving on — it asked about a stage now done
  defp settled?(m, operator) do
    Repo.exists?(from r in Message, where: r.thread_id == ^m.thread_id and r.author == ^operator and r.id > ^m.id) or
      Repo.exists?(
        from e in Event,
          where: e.thread_id == ^m.thread_id and e.kind == "stage_advanced" and e.created_at >= ^m.created_at
      )
  end

  defp rollout do
    for n <- Server.Rollout.pending() do
      %{
        key: "rollout:#{n.id}",
        kind: "rollout",
        level: "decide",
        thread_id: nil,
        workspace_id: nil,
        title: "rollout",
        text: n.text,
        at: DateTime.from_unix!(n.at),
        options: nil,
        ref: n.id
      }
    end
  end

  defp stranded do
    for %{repo: repo, name: name, thread: t} <- Server.Maintain.Strays.worktrees(),
        not just_landed?(t),
        !(t && landing?(t)),
        why = Server.Worktree.holds(repo, name) do
      %{
        key: "stranded:#{repo}:#{name}",
        repo: repo,
        name: name,
        kind: "stranded",
        level: "decide",
        thread_id: t && t.id,
        workspace_id: t && t.workspace_id,
        title: "stranded work in #{name}",
        text: "#{Path.join([repo, ".worktrees", name])}: #{why}",
        at: (t && t.created_at) || DateTime.utc_now(),
        options: nil,
        ref: nil
      }
    end
  end

  # a landing's PR waits on GitHub's checks before it merges; until then its commits are on no main,
  # and that is the merge going as it should, not work left behind
  defp just_landed?(%Thread{stage: "merged", id: id}) do
    since = DateTime.add(DateTime.utc_now(), -@landing_grace_s, :second)

    Repo.exists?(
      from e in Server.Event,
        where:
          e.thread_id == ^id and e.kind == "stage_advanced" and
            fragment("(?::jsonb ->> 'to') = 'merged'", e.detail) and e.created_at > ^since
    )
  end

  defp just_landed?(_), do: false

  @doc "Whether a landing of `thread` is queued or running in the merge queue (`Server.Jobs.Land`)."
  def landing?(%Thread{id: id}) do
    Repo.exists?(
      from j in Oban.Job,
        where:
          j.worker == "Server.Jobs.Land" and j.state in ["available", "scheduled", "executing", "retryable"] and
            fragment("(? ->> 'thread_id')::int = ?", j.args, ^id)
    )
  end

  defp item(kind, level, %Thread{} = t, text, at, extra \\ %{}) do
    Map.merge(
      %{
        key: "#{kind}:#{t.id}",
        kind: kind,
        level: level,
        thread_id: t.id,
        workspace_id: t.workspace_id,
        title: t.title,
        text: text,
        at: at,
        options: nil,
        ref: nil
      },
      extra
    )
  end

  # put away stays away until something newer comes under the key; a stranded checkout or a seats
  # count has no "newer", so it stays away until it is gone (and its put-away with it, `prune/2`)
  defp put_away?(_item, nil), do: false
  defp put_away?(%{kind: kind}, _at) when kind in ~w(stranded seats), do: true
  defp put_away?(item, at), do: DateTime.compare(item.at, at) != :gt

  defp remember(key) do
    now = DateTime.truncate(DateTime.utc_now(), :second)
    Repo.insert_all("need_dismissal", [%{key: key, at: now}], on_conflict: {:replace, [:at]}, conflict_target: :key)
    :ok
  end

  defp withdraw_ask(id) do
    with %Message{kind: "prompt", resolved_at: nil} = ask <- Repo.get(Message, id) do
      operator = Application.get_env(:server, :operator, "andrew")
      Server.Attention.resolve(ask, "dismissed by #{operator}")

      Server.Channel.post(%{
        thread_id: ask.thread_id,
        author: "tlon",
        reply_to: ask.id,
        body:
          "@#{ask.payload["ask"]} #{operator} put your ask away without answering it: go on with your best judgement, or ask again if it still matters"
      })
    end
  end

  # an open blocker on an open thread
  defp issues(open) do
    by_id = Map.new(open, &{&1.id, &1})

    for i <- Repo.all(from i in Server.Issue, where: i.state == "open" and not is_nil(i.thread_id)),
        t = by_id[i.thread_id] do
      item("issue", "decide", t, "#{i.found_by || "someone"}: #{i.summary}", i.created_at, %{
        key: "issue:#{i.id}",
        ref: i.id
      })
    end
  end

  # everything, put away or not
  defp all do
    operator = Application.get_env(:server, :operator, "andrew")
    open = Repo.all(from t in Thread, where: t.state == "open")
    prompts = Server.Attention.open_prompts_by_thread()

    blocking = waits(open, prompts) ++ asks(open) ++ red_verifies(open)
    decide = mentions(open, operator) ++ rollout() ++ stranded() ++ seats(open) ++ failed_jobs() ++ issues(open)
    Enum.sort_by(blocking, & &1.at, DateTime) ++ Enum.sort_by(decide, & &1.at, DateTime)
  end

  # a put-away whose item is gone has nothing left to hide: a later item under the same key is new
  defp prune(away, items) do
    keys = MapSet.new(items, & &1.key)
    gone = for {key, _} <- away, not MapSet.member?(keys, key), do: key
    if gone != [], do: Repo.delete_all(from d in "need_dismissal", where: d.key in ^gone)
  end
end
