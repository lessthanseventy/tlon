defmodule Server.Office.Room do
  @moduledoc """
  The reads behind the office's things you open: the in-tray (`activity/1`, what just happened in
  a workspace), the beacon (`triage/1`, what is stuck), the server rack (`health/0`), memory
  (`memory/1`, pinned facts and habits to review), the ticket board (`tickets/1`, every column), a
  workspace's settings (`workspace/1`), the wall calendar (`schedules/2`, `calendar/1`, `runs/1`),
  and the history the finder searches (`history/0`). Plain maps, JSON-ready, served under
  `GET /api/office/*` (`Server.MCP.OperatorAPI`).
  """

  import Ecto.Query

  alias Server.Channel
  alias Server.Dossier
  alias Server.Event
  alias Server.Fact
  alias Server.Intake
  alias Server.Issue
  alias Server.Message
  alias Server.Question
  alias Server.Repo
  alias Server.Schedules
  alias Server.Thread
  alias Server.Ticket
  alias Server.Tickets

  @cap 5

  @doc """
  What just happened in a workspace, newest first: messages posted, facts banked, events recorded,
  issues and questions raised. Each `%{kind, at, thread_id, who, text}`; `limit` rows at most.
  """
  @spec activity(integer(), pos_integer()) :: [map()]
  def activity(workspace_id, limit \\ 50) do
    ids = from(t in Thread, where: t.workspace_id == ^workspace_id, select: t.id)
    in_ws = &from(r in &1, where: r.thread_id in subquery(ids), order_by: [desc: r.id], limit: ^limit)

    messages =
      for m <- Repo.all(in_ws.(Message)),
          do: row("message", m.created_at, m.thread_id, m.author, m.body)

    facts =
      for f <- Repo.all(from(f in in_ws.(Fact), where: is_nil(f.forgotten_at))),
          do: row("fact", f.created_at, f.thread_id, nil, f.text)

    events =
      for e <- Repo.all(in_ws.(Event)),
          do: row(e.kind, e.created_at, e.thread_id, nil, event_text(e))

    issues = for i <- Repo.all(in_ws.(Issue)), do: row("issue", i.created_at, i.thread_id, i.found_by, i.summary)

    questions =
      for q <- Repo.all(in_ws.(Question)), do: row("question", q.created_at, q.thread_id, nil, q.text)

    (messages ++ facts ++ events ++ issues ++ questions)
    |> Enum.sort_by(& &1.at, {:desc, DateTime})
    |> Enum.take(limit)
  end

  defp row(kind, at, tid, who, text),
    do: %{kind: kind, at: at, thread_id: tid, who: who, text: String.slice(text || "", 0, 300)}

  defp event_text(%Event{detail: %{"cmd" => cmd}}), do: cmd
  defp event_text(%Event{detail: %{"summary" => s}}), do: s
  defp event_text(%Event{correlation: c}), do: c

  @doc """
  What is stuck in a workspace's open threads: open issues (blockers), failed checks (a command
  whose newest check failed), and threads nobody leads. Each section `%{shown, more}`, #{@cap} shown;
  `count` is everything, the beacon's reason to flash.
  """
  @spec triage(integer()) :: map()
  def triage(workspace_id) do
    open = from(t in Thread, where: t.workspace_id == ^workspace_id and t.state == "open")

    blockers =
      Repo.all(
        from i in Issue,
          join: t in subquery(open),
          on: t.id == i.thread_id,
          where: i.state == "open",
          order_by: [desc: i.id],
          select: %{thread_id: t.id, title: t.title, text: i.summary}
      )

    checks =
      Repo.all(
        from e in Event,
          join: t in subquery(open),
          on: t.id == e.thread_id,
          where: e.kind in ["check_passed", "check_failed"],
          order_by: [desc: e.id],
          select: %{thread_id: t.id, title: t.title, kind: e.kind, detail: e.detail}
      )

    failed =
      checks
      |> Enum.uniq_by(&{&1.thread_id, cmd(&1.detail)})
      |> Enum.filter(&(&1.kind == "check_failed"))
      # a stage's owed doc not there yet is work in progress, not something stuck
      |> Enum.reject(&String.starts_with?(cmd(&1.detail), "workline artifact"))
      |> Enum.map(&%{thread_id: &1.thread_id, title: &1.title, text: cmd(&1.detail)})

    unled =
      Repo.all(
        from t in subquery(open),
          where: is_nil(t.agent_id),
          order_by: [desc: t.id],
          select: %{thread_id: t.id, title: t.title, text: "nobody leads it"}
      )

    %{
      blockers: cap(blockers),
      failed_checks: cap(failed),
      unled: cap(unled),
      count: length(blockers) + length(failed) + length(unled)
    }
  end

  defp cmd(%{"cmd" => c}) when is_binary(c), do: c
  defp cmd(_), do: "check"

  defp cap(list), do: %{shown: Enum.take(list, @cap), more: max(length(list) - @cap, 0)}

  @doc """
  The service and its box: the release, how long it has been up, the database, the job queue
  (failures in the last day), whether tmux is there, and the box's disk, memory and load where the
  OS says (`nil` where it doesn't). `state` is `"ok"`, or `"warn"` with `problems` naming why.
  """
  @spec health() :: map()
  def health do
    db = match?({:ok, _}, Repo.query("SELECT 1"))
    failed_jobs = if db, do: Repo.aggregate(Server.Office.Needs.failed_jobs_query(), :count)

    h = %{
      version: to_string(Application.spec(:server, :vsn)),
      up_s: :wall_clock |> :erlang.statistics() |> elem(0) |> div(1000),
      db: db,
      jobs: Application.get_env(:server, :start_oban, false),
      failed_jobs: failed_jobs || 0,
      tmux: System.find_executable("tmux") != nil,
      disk_pct: disk_pct(),
      mem_pct: mem_pct(),
      load: load(),
      checks: checks(),
      merge_queue: if(db, do: merge_queue(), else: [])
    }

    problems = problems(h)
    Map.merge(h, %{state: if(problems == [], do: "ok", else: "warn"), problems: problems})
  end

  @doc """
  The machine's checks queue (`scripts/checks-queue.sh`): the full check running now, as it said
  when it took the lock, and the ones waiting their turn, each `"<command> (pid N) in <dir> since
  HH:MM:SS"`. A waiter whose process is gone is not counted. `%{running: line | nil, waiting: [line]}`.
  """
  def checks(dir \\ System.get_env("XDG_RUNTIME_DIR") || "/tmp") do
    running =
      case File.read(Path.join(dir, "tlon-checks.holder")) do
        {:ok, line} -> if String.trim(line) != "", do: String.trim(line)
        _ -> nil
      end

    waiting =
      for name <- ls(Path.join(dir, "tlon-checks.wait")),
          File.exists?("/proc/#{name}"),
          {:ok, line} <- [File.read(Path.join([dir, "tlon-checks.wait", name]))],
          do: String.trim(line)

    %{running: running, waiting: waiting}
  end

  @doc """
  The merge queue: worklines approved and landing, one at a time (`Server.Jobs.Land`) — the one
  being gated now first, then the queued in order. `[%{thread_id, title, state}]`, `state`
  `"landing"` or `"queued"`.
  """
  def merge_queue do
    from(j in Oban.Job,
      join: t in Server.Thread,
      on: t.id == type(fragment("(?->>'thread_id')", j.args), :integer),
      where: j.worker == "Server.Jobs.Land" and j.state in ["executing", "available", "scheduled", "retryable"],
      order_by: [desc: fragment("? = 'executing'", j.state), asc: j.id],
      select: %{thread_id: t.id, title: t.title, state: j.state}
    )
    |> Repo.all()
    |> Enum.map(&%{&1 | state: if(&1.state == "executing", do: "landing", else: "queued")})
  end

  defp problems(h) do
    [
      {!h.db, "the database does not answer"},
      {h.failed_jobs > 0, "#{h.failed_jobs} job(s) failed today"},
      {!h.tmux, "no tmux: coworkers can't run"},
      {(h.disk_pct || 0) >= 90, "disk #{h.disk_pct}% full"},
      {(h.mem_pct || 0) >= 90, "memory #{h.mem_pct}% used"}
    ]
    |> Enum.filter(&elem(&1, 0))
    |> Enum.map(&elem(&1, 1))
  end

  defp disk_pct do
    case System.cmd("df", ["-P", System.user_home!()], stderr_to_stdout: true) do
      {out, 0} ->
        out |> String.split("\n", trim: true) |> List.last() |> String.split() |> Enum.at(4, "") |> pct()

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  defp pct(s) do
    case Integer.parse(s) do
      {n, "%"} -> n
      _ -> nil
    end
  end

  defp mem_pct do
    with {:ok, raw} <- File.read("/proc/meminfo"),
         %{"MemTotal" => total, "MemAvailable" => avail} <- meminfo(raw),
         true <- total > 0 do
      round((total - avail) * 100 / total)
    else
      _ -> nil
    end
  end

  defp meminfo(raw) do
    for l <- String.split(raw, "\n"), [k, v] <- [String.split(l, ":", parts: 2)], into: %{} do
      {k, v |> String.trim() |> Integer.parse() |> then(&if(&1 == :error, do: 0, else: elem(&1, 0)))}
    end
  end

  defp load do
    case File.read("/proc/loadavg") do
      {:ok, raw} -> raw |> String.split() |> hd() |> Float.parse() |> elem(0)
      _ -> nil
    end
  end

  @doc """
  A workspace's memory, for the operator to tend: the pinned facts every session loads (with their
  ids, to forget one), the habits coworkers proposed awaiting review, and the recall coverage.
  """
  @spec memory(integer()) :: map()
  def memory(workspace_id) do
    %{
      pinned: for(f <- Dossier.always_loaded_constraints(workspace_id), do: %{id: f.id, text: f.text}),
      habits:
        for(
          h <- Dossier.pending_habits(workspace_id),
          do: %{id: h.id, text: h.text, rationale: h.rationale, by: h.proposed_by}
        ),
      coverage: Server.Recall.coverage(workspace_id)
    }
  end

  @doc """
  A workspace's whole ticket board, every status, in board order (`sort` high first), each with the
  ids of the unfinished tickets blocking it.
  """
  @spec tickets(integer()) :: [map()]
  def tickets(workspace_id) do
    for t <- Tickets.in_workspace(workspace_id) do
      %{
        id: t.id,
        title: t.title,
        body: t.body,
        status: t.status,
        priority: t.priority,
        project_id: t.project_id,
        blocked_by: Tickets.blockers(t.id)
      }
    end
  end

  @doc """
  A workspace's backlog grouped by epic: `%{epics: [row], loose: [ticket]}`. Each epic row carries `done`/`total` over its
  children, its own `priority`, `status` (derived), its `children` (each with `epic_id` and the `effective_priority` —
  the higher of its own and its epic's) and `next`: `%{id, title}` of its lowest-`sort` child that is `backlog`,
  unblocked and not held (what intake would start), or nil. Epics sort most urgent first, then board order.
  Tickets with no epic are `loose`. Flat reads stay in `tickets/1`.
  """
  @spec board(integer()) :: %{epics: [map()], loose: [map()]}
  def board(workspace_id) do
    all = Tickets.in_workspace(workspace_id)
    blocked = Tickets.blocked_in_workspace(workspace_id)
    by_id = Map.new(all, &{&1.id, &1})

    parent_of =
      from(l in Server.TicketLink,
        join: e in Ticket,
        on: e.id == l.from_id,
        where: l.kind == "parent" and e.workspace_id == ^workspace_id,
        select: {l.to_id, l.from_id}
      )
      |> Repo.all()
      |> Map.new()

    {epics, tickets} = Enum.split_with(all, &(&1.kind == "epic"))
    {kids, loose} = Enum.split_with(tickets, &Map.has_key?(parent_of, &1.id))
    kids_of = Enum.group_by(kids, &parent_of[&1.id])

    rows =
      for e <- epics do
        children = Map.get(kids_of, e.id, [])

        free =
          Enum.filter(
            children,
            &(&1.status == "backlog" and not MapSet.member?(blocked, &1.id) and not Intake.held?(&1))
          )

        next = Enum.min_by(free, &{&1.sort || 0, &1.id}, fn -> nil end)

        %{
          id: e.id,
          title: e.title,
          body: e.body,
          status: e.status,
          priority: e.priority,
          labels: e.labels,
          done: Enum.count(children, &(&1.status == "done")),
          total: length(children),
          next: next && %{id: next.id, title: next.title},
          children: Enum.map(children, &board_ticket(&1, by_id[parent_of[&1.id]], blocked))
        }
      end

    %{
      epics: Enum.sort_by(rows, &Ticket.urgency(&1.priority)),
      loose: Enum.map(loose, &board_ticket(&1, nil, blocked))
    }
  end

  defp board_ticket(t, epic, blocked) do
    %{
      id: t.id,
      title: t.title,
      status: t.status,
      priority: t.priority,
      effective_priority: Enum.min_by([t.priority | List.wrap(epic && epic.priority)], &Ticket.urgency/1),
      epic_id: epic && epic.id,
      blocked: MapSet.member?(blocked, t.id),
      held: Intake.held?(t)
    }
  end

  @doc "A workspace's settings, for its config card: type, scope, icon, and its repos in order. nil for none."
  @spec workspace(integer()) :: map() | nil
  def workspace(workspace_id) do
    with %{} = w <- Server.Workspaces.get(workspace_id) do
      %{
        id: w.id,
        name: w.name,
        type: w.type,
        scope: w.scope,
        icon: (w.knobs || %{})["icon"],
        repos: for(r <- Server.Workspaces.repos(w.id), do: %{id: r.id, path: r.path, remote: r.remote})
      }
    end
  end

  @doc """
  A workspace's schedules for the wall calendar's card: what each runs and when — `next_at`, the
  days of `{year, month}` (default: this local month) it fires on — and how its last run went.
  """
  @spec schedules(integer(), {integer(), integer()} | nil) :: [map()]
  def schedules(workspace_id, month \\ nil) do
    {y, m} = month || this_month()
    list = Schedules.in_workspace(workspace_id)
    last = last_runs(Enum.map(list, & &1.id))

    for s <- list do
      s
      |> Map.take([:id, :kind, :title, :body, :cron, :at, :agent, :standing, :thread_id, :dir, :enabled])
      |> Map.merge(%{next_at: Schedules.next_at(s), days: Schedules.days(s, y, m), last: last[s.id]})
    end
  end

  @doc "The days of this local month on which each workspace has something scheduled, by workspace id."
  @spec calendar([integer()]) :: %{integer() => [integer()]}
  def calendar(ws_ids) do
    {y, m} = this_month()
    on = Repo.all(from s in Server.Schedule, where: s.workspace_id in ^ws_ids and s.enabled)
    by_ws = Enum.group_by(on, & &1.workspace_id)

    Map.new(ws_ids, fn ws ->
      {ws, by_ws |> Map.get(ws, []) |> Enum.flat_map(&Schedules.days(&1, y, m)) |> Enum.uniq() |> Enum.sort()}
    end)
  end

  @doc "A schedule's recent runs, newest first: the automation board."
  @spec runs(integer()) :: [map()]
  def runs(schedule_id),
    do:
      for(
        r <- Schedules.runs(schedule_id),
        do: Map.take(r, [:id, :status, :exit, :output, :thread_id, :started_at, :finished_at])
      )

  defp this_month do
    t = Schedules.local_now()
    {t.year, t.month}
  end

  defp last_runs(ids) do
    from(r in Server.ScheduleRun,
      where: r.schedule_id in ^ids,
      distinct: r.schedule_id,
      order_by: [asc: r.schedule_id, desc: r.id]
    )
    |> Repo.all()
    |> Map.new(&{&1.schedule_id, %{status: &1.status, exit: &1.exit, at: &1.started_at, thread_id: &1.thread_id}})
  end

  @doc "Every closed thread, any workspace, newest first — what the finder searches beside the open ones."
  @spec history() :: [map()]
  def history, do: Enum.map(Channel.closed_threads(), &Map.take(&1, [:id, :title, :workspace_id, :at]))

  defp ls(dir) do
    case File.ls(dir) do
      {:ok, names} -> Enum.sort(names)
      _ -> []
    end
  end
end
