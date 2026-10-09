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
      with no reply from them since), `suggestion` (the corkboard's suggestion box), `rollout` (what a
      merge could not roll out itself), `stranded` (a worktree no thread is working in that holds
      work: merge it or delete it — `Server.Maintain.Strays`; a workline that landed within the hour
      is its PR waiting on GitHub's checks, and one in the merge queue is landing — neither is stranded),
      `seats` (threads parked on the leaf cap, per workspace: `ref` the bigger cap it offers),
      `job_failed` (a background job discarded in the last day: retry or dismiss, `ref` the job).

  Blocking first, then to decide; oldest first within each. An item leaves the list when the thing
  behind it is resolved — approved, answered, filed — not when it is looked at.
  """
  import Ecto.Query

  alias Server.Event
  alias Server.Message
  alias Server.Repo
  alias Server.Thread

  @mention_days 7
  @landing_grace_s 3600

  @doc "Every item waiting on the operator, across the workspaces."
  def list do
    operator = Application.get_env(:server, :operator, "andrew")
    open = Repo.all(from t in Thread, where: t.state == "open")
    prompts = Server.Attention.open_prompts_by_thread()

    blocking = waits(open, prompts) ++ asks(open) ++ red_verifies(open)
    decide = mentions(open, operator) ++ suggestions(open) ++ rollout() ++ stranded() ++ seats(open) ++ failed_jobs()

    Enum.sort_by(blocking, & &1.at, DateTime) ++ Enum.sort_by(decide, & &1.at, DateTime)
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
      do: item("gate", "blocking", t, gate_text(t, stage), t.created_at),
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
    since = DateTime.add(DateTime.utc_now(), -@mention_days * 86_400, :second)
    ids = Enum.map(open, & &1.id)
    by_id = Map.new(open, &{&1.id, &1})
    like = "%@#{operator}%"

    from(m in Message,
      where: m.thread_id in ^ids and m.author != ^operator and ilike(m.body, ^like) and m.created_at > ^since,
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

  defp suggestions(open) do
    workspaces = open |> Enum.map(& &1.workspace_id) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    for ws <- workspaces, s <- Server.Office.Corkboard.suggestions(ws) do
      %{
        key: "suggestion:#{ws}:#{s.id}",
        kind: "suggestion",
        level: "decide",
        thread_id: nil,
        workspace_id: ws,
        title: "suggestion from #{s.author}",
        text: s.body,
        at: DateTime.from_unix!(s.at),
        options: nil,
        ref: s.id
      }
    end
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
end
