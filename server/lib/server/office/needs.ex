defmodule Server.Office.Needs do
  @moduledoc """
  Everything waiting on the operator, as ONE list — derived from the state that already says so,
  never a second record that could drift from it. Each item is
  `%{key, kind, level, thread_id, workspace_id, title, text, at, options}`:

    * **blocking** — work has stopped until the operator acts:
      `gate` (a workline at its gate: approve), `question` (a coworker asked: reply), `dialog` (a pane
      sits on a prompt, or the PM's release gate waits: pick an option, answered by `ref`, the prompt's id), `ask` (one decision a
      coworker filed with its answers, `Server.Attention.ask/4`: one item per ask, `ref` its id,
      answered by key), `verify_failed` (a workline whose last gate run was red — the sheriff, where
      there is one, gets a copy: `Server.Sheriff`), `stalled` (a workline nothing has moved for past
      the quiet window (the operator's `quiet_workline_minutes` knob, the one Maintain nudges at) — no
      stage advance, check, commit or operator answer — and nobody on duty for it (a mid-turn mark
      counts until `Server.Presence.Thinking.stale_turn_seconds/0`): whatever stopped it has no kind of its own yet; its text carries the thread's last word.
      Put away, it stays away until the workline moves; under pencils down or lights out nothing
      stalls, the operator stopped it), `publish_failed` (a workline merged here whose newest publish
      to GitHub — recorded under `Server.Workline.publish_correlation/1` — failed: republish it, or open its PR by
      hand with the command its text names and give its url (`Server.Workline.published_by_hand/2`); `ref`
      the thread), `pr_blocked` (a landed workline whose PR GitHub isn't merging:
      its merge refused, closed unmerged, `BLOCKED` with no check running, or no merge an hour after it
      was published or rebased — `Server.Workline.waiting_on_github/0`; `url` the PR; answered by
      rebase, close and reland, or a look at the PR), `no_seat` (an open
      workline at a stage whose kind — `Server.Workline.staff_kind/1` — the bench lacks, and nobody
      on the bench leads it: hire one, or hand it to someone; `archetype` the kind), `quota` (per
      workspace: Claude's usage limit with no other crew to put on, until its reset —
      `Server.Shifts.out_of_quota/1` — or a provider's plan spent with a seat on it —
      `Server.Presence.Engine.spent/0`: `options` the other crews to put on; put away, it waits for
      the reset);
    * **decide** — wants the operator, nothing waits on it: `mention` (an @operator on an open thread
      with no reply from them since, from the last 12 hours: one older than that is history, still on
      its thread), `rollout` (what a
      merge could not roll out itself), `stranded` (a worktree no thread is working in that holds
      work: merge it or delete it — `Server.Maintain.Strays`; a landed workline's thread stays open
      while its PR waits on GitHub's checks, and one in the merge queue is landing — neither is stranded),
      `seats` (threads parked on the leaf cap, per workspace: `ref` the bigger cap it offers),
      `job_failed` (a background job discarded in the last day, its runs failing the same way one
      item: retry or dismiss, `ref` the newest run),
      `issue` (a blocker raised on an open thread and not resolved: resolve it, `ref` the issue),
      `release_failed` (a workspace's newest release cut failed and live is not at its commit:
      retry it, `ref` its `check_failed` event — `Server.Release.PM.retry/1` — or put it away and
      stay on what runs; a failed cut never moves the pointer, so there is nothing to roll back).

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

      %{kind: kind} when kind in ~w(stalled quota) ->
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
    do: item("dialog", "blocking", t, prompt.summary, prompt_at(prompt.id), %{options: prompt.options, ref: prompt.id})

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

  # a cron job failing the same way every run (KeepUp every 5 minutes) is one item, its newest run
  defp failed_jobs do
    for {_, runs} <- Enum.group_by(Repo.all(failed_jobs_query()), &failure/1) do
      j = Enum.max_by(runs, & &1.attempted_at, DateTime)
      times = if length(runs) > 1, do: " #{length(runs)} times", else: ""

      %{
        key: "job:#{j.id}",
        kind: "job_failed",
        level: "decide",
        thread_id: nil,
        workspace_id: nil,
        title: "#{j.worker} failed#{times}",
        text: last_error(j.errors),
        at: j.attempted_at,
        options: nil,
        ref: j.id
      }
    end
  end

  defp last_error([_ | _] = errors), do: errors |> List.last() |> Map.get("error", "no error recorded")
  defp last_error(_), do: "no error recorded"

  @doc """
  The operator has seen a failed job, and every run that failed the same way (one item): they
  leave the list and the rack's count. `:ok`.
  """
  def dismiss_job(id) do
    same =
      case Repo.get(Oban.Job, id) do
        nil -> [id]
        job -> for j <- Repo.all(failed_jobs_query()), failure(j) == failure(job), do: j.id
      end

    {_, _} =
      Repo.update_all(
        from(j in Oban.Job,
          where: j.id == ^id or j.id in ^same,
          update: [set: [meta: fragment("coalesce(?, '{}'::jsonb) || '{\"dismissed\": true}'::jsonb", j.meta)]]
        ),
        []
      )

    :ok
  end

  @doc "Run a failed job again. `:ok`."
  def retry_job(id), do: Oban.retry_job(id)

  # a workline sitting at verify whose newest verify run was red, and no re-run queued or running
  defp red_verifies(open) do
    for %Thread{stage: "verify", slug: slug} = t <- open,
        %{kind: "check_failed"} = e <- [last_verify(slug)],
        not verifying?(t),
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

  # a landing GitHub isn't merging: told so, or an hour gone without a merge; one back in the merge
  # queue waits on that, not on the operator
  defp pr_blocked do
    cutoff = DateTime.add(DateTime.utc_now(), -@landing_grace_s, :second)

    for %{thread: t, url: url, event: e} <- Server.Workline.waiting_on_github(),
        e.kind == "check_failed" or DateTime.before?(e.created_at, cutoff),
        not landing?(t) do
      text =
        if e.kind == "check_failed",
          do: "#{e.detail["tail"]} — #{url}",
          else: "GitHub hasn't merged #{url} in over an hour: its checks still pending, or nothing will merge it"

      item("pr_blocked", "blocking", t, text, e.created_at, %{url: url})
    end
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
        m.thread_id in ^ids and m.kind not in ["suggestion", "margin"] and m.author != ^operator and
          ilike(m.body, ^like) and
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
  defp put_away?(%{kind: kind}, _at) when kind in ~w(stranded seats quota), do: true
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

  # an open blocker on an open thread that no ticket is fixing: unowned, or owned by a ticket that
  # ended without landing (`Server.Dossier.resolve_fixed/2` closes the ones that land)
  defp issues(open) do
    by_id = Map.new(open, &{&1.id, &1})

    for i <-
          Repo.all(
            from i in Server.Issue,
              left_join: t in Server.Ticket,
              on: t.id == i.ticket_id,
              where: i.state == "open" and not is_nil(i.thread_id) and (is_nil(i.ticket_id) or t.status == "done")
          ),
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

    blocking = waits(open, prompts) ++ asks(open) ++ red_verifies(open) ++ unpublished() ++ pr_blocked()
    blocking = blocking ++ no_seat(open, MapSet.new(blocking, & &1.thread_id)) ++ quota()
    blocking = blocking ++ stalled(open, MapSet.new(blocking, & &1.thread_id))

    decide =
      mentions(open, operator) ++
        rollout() ++ stranded() ++ seats(open) ++ failed_jobs() ++ issues(open) ++ failed_cuts()

    Enum.sort_by(blocking, & &1.at, DateTime) ++ Enum.sort_by(decide, & &1.at, DateTime)
  end

  # an open workline at a stage whose kind the bench lacks, and nobody on the bench leads it:
  # staffing keeps the lead it has, and with none (or one off the bench) nothing moves it
  defp no_seat(open, listed) do
    for %Thread{stage: stage, workspace_id: ws} = t <- open,
        kind = Server.Workline.staff_kind(stage),
        kind && ws && is_nil(t.awaiting) && not MapSet.member?(listed, t.id),
        bench = Server.Workspaces.bench(ws),
        not Enum.any?(bench, &(&1.archetype == kind)),
        lead <- [Server.Channel.thread_lead(t.id)],
        is_nil(lead) or not Enum.any?(bench, &(&1.name == lead)) do
      who = if lead, do: "#{lead}, its lead, is off the bench", else: "nobody leads it"
      text = "#{t.slug} at #{stage} needs a #{kind} and the bench has none — #{who}"
      item("no_seat", "blocking", t, text, t.created_at, %{archetype: kind})
    end
  end

  # a workspace whose engine can't take a turn: Claude's limit with no other crew to put on
  # (`Server.Shifts.out_of_quota/1`), or a provider's plan spent (`Server.Presence.Engine.spent/0`,
  # every wake to its seats held); each offers the other crews, if any
  defp quota do
    claude =
      for {ws, [q | _]} <- Enum.group_by(Server.Shifts.out_of_quota(), & &1.workspace_id) do
        text =
          "Claude's usage limit is reached on the #{q.crew} crew and no other crew can take over: " <>
            "it resets #{q.reset}, and every wake to it waits until then"

        quota_item(ws, "anthropic", "Claude's usage limit", text, q.at)
      end

    spent =
      for %{provider: provider, until: until} <- Server.Presence.Engine.spent(),
          %Server.Workspace{id: ws} <- Repo.all(Server.Workspace),
          names =
            for(s <- Server.Workspaces.bench_all(ws), Server.Presence.provider_of(s.name, ws) == provider, do: s.name),
          names != [] do
        reset = if until, do: " until " <> local(until), else: ""
        text = "the #{provider} plan is spent#{reset}: every wake to #{Enum.join(names, ", ")} is held"

        quota_item(ws, provider, "#{provider} is spent", text, DateTime.truncate(DateTime.utc_now(), :second))
      end

    claude ++ spent
  end

  defp quota_item(ws, provider, title, text, at) do
    on = Server.Shifts.current(ws)

    %{
      key: "quota:#{ws}:#{provider}",
      kind: "quota",
      level: "blocking",
      thread_id: nil,
      workspace_id: ws,
      title: title,
      text: text,
      at: at,
      options: for(c <- List.delete(Server.Shifts.crews(ws), on), do: %{"key" => c, "label" => "#{c} crew on"}),
      ref: nil
    }
  end

  # the server's clock is the local one (`Server.Shifts.reset_at/2`)
  defp local(%DateTime{} = utc) do
    utc
    |> DateTime.to_naive()
    |> NaiveDateTime.to_erl()
    |> :calendar.universal_time_to_local_time()
    |> NaiveDateTime.from_erl!()
    |> Calendar.strftime("%a %-I:%M%P")
  end

  # each thread's newest check under `correlation` (a LIKE pattern), when it is the failed one
  defp newest_failed(pattern) do
    from(e in Event,
      where: like(e.correlation, ^pattern) and e.kind in ["check_passed", "check_failed"],
      distinct: e.thread_id,
      order_by: [desc: e.id]
    )
    |> Repo.all()
    |> Enum.filter(&(&1.kind == "check_failed"))
  end

  # merged here and never reached GitHub: with no PR, nothing polls its landing or wakes for it
  defp unpublished do
    for e <- newest_failed("workline:%:publish"),
        %Thread{stage: "merged"} = t <- [Repo.get(Thread, e.thread_id)] do
      repo = Server.Workline.Artifacts.Git.root(t)
      branch = "work/#{t.slug}"

      item(
        "publish_failed",
        "blocking",
        t,
        "#{branch} merged here but never reached GitHub: #{e.detail["tail"]} — by hand: " <>
          "git -C #{repo} push origin #{branch} && gh pr create --head #{branch} --base main --fill",
        e.created_at,
        %{ref: t.id}
      )
    end
  end

  # a workspace's newest cut failed, and live is not at its commit by another way
  defp failed_cuts do
    live = Server.Release.PM.live_release()

    for %Event{correlation: "release:" <> sha} = e <- newest_failed("release:%"),
        live == nil or live.sha != sha,
        t = Repo.get(Thread, e.thread_id) do
      item(
        "release_failed",
        "decide",
        t,
        "release #{String.slice(sha, 0, 7)} not cut: #{e.detail["tail"]}",
        e.created_at,
        %{ref: e.id}
      )
    end
  end

  # nothing moved it past the quiet window and nobody is on it: the stop that has no kind of its own
  defp stalled(open, listed) do
    if Server.Pause.state() == :working do
      cutoff = DateTime.add(DateTime.utc_now(), -Server.OperatorConfig.setting("quiet_workline_minutes") * 60, :second)

      for %Thread{stage: stage} = t <- open,
          stage not in [nil, "merged"],
          is_nil(t.awaiting),
          not MapSet.member?(listed, t.id),
          moved = last_moved(t),
          DateTime.before?(moved, cutoff),
          not on_duty?(t) do
        item("stalled", "blocking", t, stalled_text(t, moved), moved)
      end
    else
      []
    end
  end

  # a coworker's chatter is not movement, nor a prompt the machine closed ("window closed"); an
  # operator's answer starts the clock again, so the lead gets the window to act on it
  defp last_moved(t) do
    operator = Application.get_env(:server, :operator, "andrew")

    event =
      Repo.one(
        from e in Event,
          where: e.thread_id == ^t.id and e.kind in ["stage_advanced", "check_passed", "check_failed", "work_landed"],
          select: max(e.created_at)
      )

    answer =
      Repo.one(
        from m in Message,
          where:
            m.thread_id == ^t.id and
              (m.author == ^operator or like(m.resolution, "answered%") or like(m.resolution, "dismissed by%")),
          select: max(fragment("greatest(?, ?)", m.created_at, m.resolved_at))
      )

    [t.created_at, event, answer && DateTime.from_naive!(answer, "Etc/UTC"), commit_at(t)]
    |> Enum.reject(&is_nil/1)
    |> Enum.max(DateTime)
  end

  defp commit_at(%Thread{slug: slug} = t) when is_binary(slug) do
    case System.cmd(
           "git",
           ["-C", Server.Workline.Artifacts.Git.root(t), "log", "-1", "--format=%cI", "work/#{slug}", "--"],
           stderr_to_stdout: true
         ) do
      {iso, 0} ->
        case DateTime.from_iso8601(String.trim(iso)) do
          {:ok, at, _} -> at
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp commit_at(_), do: nil

  # someone is on it: the merge queue, a verify run queued or running, a coworker mid-turn here (a
  # mark past the stale-turn clock is a turn nothing will end, not someone on it)
  defp on_duty?(t) do
    live = DateTime.add(DateTime.utc_now(), -Server.Presence.Thinking.stale_turn_seconds(), :second)

    landing?(t) or verifying?(t) or
      Repo.exists?(
        from s in Server.Session,
          where: s.thread_id == ^t.id and is_nil(s.ended_at) and s.thinking_since > ^live
      )
  end

  defp verifying?(t) do
    Repo.exists?(
      from j in Oban.Job,
        where:
          j.worker == "Server.Jobs.Verify" and j.state in ["available", "scheduled", "executing", "retryable"] and
            fragment("(? ->> 'thread_id')::int = ?", j.args, ^t.id)
    )
  end

  defp stalled_text(t, moved) do
    last =
      Repo.one(
        from m in Message,
          where: m.thread_id == ^t.id and m.kind not in ["notice", "suggestion", "margin"],
          order_by: [desc: m.id],
          limit: 1
      )

    hours = DateTime.utc_now() |> DateTime.diff(moved, :minute) |> div(60)
    head = "#{t.slug} at #{t.stage}: nothing has moved for #{if hours > 0, do: "#{hours}h", else: "an hour"}"
    if last, do: "#{head} — #{last.author}: #{String.slice(last.body, 0, 200)}", else: head
  end

  # a put-away whose item is gone has nothing left to hide: a later item under the same key is new
  defp prune(away, items) do
    keys = MapSet.new(items, & &1.key)
    gone = for {key, _} <- away, not MapSet.member?(keys, key), do: key
    if gone != [], do: Repo.delete_all(from d in "need_dismissal", where: d.key in ^gone)
  end

  defp failure(j), do: {j.worker, last_error(j.errors)}
end
