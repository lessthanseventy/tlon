defmodule Server.Schedules do
  @moduledoc """
  The operator's calendar: things to run on a cron or once at a time (`Server.Schedule`), and each
  firing (`Server.ScheduleRun`, the automation board). OSS Oban has no dynamic cron, so a
  per-minute job (`Server.Jobs.Dispatch`) asks `dispatch/1` what is due; each due schedule is
  claimed — its `last_run_at` moved, guarded so two dispatchers can't both fire it — a run row
  written, and `Server.Jobs.RunSchedule` does the work (`perform/1`): an agent run is a prompt
  posted to a thread (fresh, or the schedule's standing one) staffed with the named coworker; a
  workline opens; a script runs in a shell and its exit and output land on the run (and in the
  standing thread, when it has one). A firing missed while the service was down fires once on
  its return, not once per missed slot.

  A cron reads the server's local wall clock: an expression is matched against local time and
  turned back to UTC through the OS's timezone rules for that very instant (no tz database here),
  so a 9:00 cron fires at 9:00 on either side of a DST change.
  """

  import Ecto.Query

  alias Oban.Cron.Expression
  alias Server.Channel
  alias Server.Message
  alias Server.Repo
  alias Server.Schedule
  alias Server.ScheduleRun

  @script_timeout_ms 30 * 60 * 1000
  @output_cap 4000

  @doc "A new schedule. `{:ok, schedule}` or `{:error, changeset}`."
  def create(attrs), do: attrs |> Schedule.create_changeset() |> Repo.insert()

  @doc "Change one. `{:ok, schedule}` or `{:error, changeset}`."
  def update(%Schedule{} = s, attrs), do: s |> Schedule.update_changeset(attrs) |> Repo.update()

  @doc "Remove one, and its runs."
  def remove(%Schedule{} = s), do: Repo.delete(s)

  @doc "A schedule by id, or nil."
  def get(id), do: Repo.get(Schedule, id)

  @doc "A workspace's schedules, oldest first."
  def in_workspace(workspace_id),
    do: Repo.all(from s in Schedule, where: s.workspace_id == ^workspace_id, order_by: [asc: s.id])

  @doc "A schedule's last `limit` runs, newest first."
  def runs(schedule_id, limit \\ 20),
    do: Repo.all(from r in ScheduleRun, where: r.schedule_id == ^schedule_id, order_by: [desc: r.id], limit: ^limit)

  @doc """
  When it next fires, from `now`: a one-off's time until it has run (then nil); a cron's next slot
  after its last firing — `now` when that slot has already passed and is waiting on the dispatcher.
  nil while disabled.
  """
  @spec next_at(Schedule.t(), DateTime.t()) :: DateTime.t() | nil
  def next_at(s, now \\ DateTime.utc_now())
  def next_at(%Schedule{enabled: false}, _now), do: nil

  def next_at(%Schedule{} = s, now) do
    case slot(s) do
      nil -> nil
      t -> if DateTime.compare(t, now) == :lt, do: DateTime.truncate(now, :second), else: t
    end
  end

  @doc "The next local occurrence of `cron` (or `@daily`/`@weekly`/…) strictly after `after_at`."
  @spec next_occurrence(String.t(), DateTime.t()) :: DateTime.t()
  def next_occurrence(cron, after_at), do: cron |> Expression.parse!() |> after_local(after_at)

  # the slot it is owed: a one-off's time (until it ran), or the cron's next after its last firing
  defp slot(%Schedule{cron: nil, at: at, last_run_at: nil}), do: at
  defp slot(%Schedule{cron: nil}), do: nil
  defp slot(%Schedule{cron: cron} = s), do: after_local(Expression.parse!(cron), s.last_run_at || s.created_at)

  @doc "Whether it is owed a firing at `now`."
  def due?(%Schedule{enabled: true} = s, now) do
    case slot(s) do
      nil -> false
      t -> DateTime.compare(t, now) != :gt
    end
  end

  def due?(_s, _now), do: false

  @doc "The days of `month` (1..12) of `year`, in local time, on which it fires."
  @spec days(Schedule.t(), integer(), integer()) :: [integer()]
  def days(%Schedule{cron: nil, at: at}, year, month) do
    local = to_local(at)
    if {local.year, local.month} == {year, month}, do: [local.day], else: []
  end

  def days(%Schedule{cron: cron}, year, month) do
    expr = Expression.parse!(cron)
    start = year |> Date.new!(month, 1) |> DateTime.new!(~T[00:00:00]) |> DateTime.add(-60)
    start |> Stream.unfold(&day_after(expr, &1, month)) |> Enum.to_list()
  end

  # the next day it fires after `cursor` (local, as a UTC-labelled datetime), and the end of that day
  defp day_after(expr, cursor, month) do
    case Expression.next_at(expr, cursor) do
      %DateTime{month: ^month} = t -> {t.day, DateTime.new!(DateTime.to_date(t), ~T[23:59:00])}
      _ -> nil
    end
  end

  @doc """
  Fire everything due at `now`: claim it (its `last_run_at` moves to `now`, only if no one else
  moved it first), write its run, and queue the work where Oban runs. The runs it started.
  """
  @spec dispatch(DateTime.t()) :: [ScheduleRun.t()]
  def dispatch(now \\ DateTime.utc_now()) do
    now = DateTime.truncate(now, :second)

    for s <- Repo.all(from s in Schedule, where: s.enabled), due?(s, now), {:ok, run} <- [claim(s, now)] do
      _ = Server.Jobs.enqueue(Server.Jobs.RunSchedule.new(%{run_id: run.id}))
      run
    end
  end

  defp claim(s, now) do
    Repo.transaction(fn ->
      {n, _} =
        Repo.update_all(
          from(x in Schedule,
            where: x.id == ^s.id and fragment("? IS NOT DISTINCT FROM ?", x.last_run_at, ^s.last_run_at)
          ),
          set: [last_run_at: now]
        )

      if n == 1, do: start_run(s, now), else: Repo.rollback(:taken)
    end)
  end

  @doc """
  Fire it now, whatever its calendar says; its calendar is left as it was. Queued where Oban
  runs; on a node without it, done in a task of its own, so the run never sits at `running`.
  `{:ok, run}`.
  """
  def run_now(%Schedule{} = s) do
    run = start_run(s, DateTime.truncate(DateTime.utc_now(), :second))

    with {:error, :no_oban} <- Server.Jobs.enqueue(Server.Jobs.RunSchedule.new(%{run_id: run.id})),
         do: Task.start(fn -> perform(run.id) end)

    {:ok, run}
  end

  defp start_run(s, now), do: Repo.insert!(%ScheduleRun{schedule_id: s.id, status: "running", started_at: now})

  @doc """
  Do a run's work and close it: `ok` or `failed`, the thread it landed in, a script's exit and
  output. A schedule removed since it fired fails its run, saying so.
  """
  @spec perform(integer()) :: ScheduleRun.t()
  def perform(run_id) do
    run = Repo.get!(ScheduleRun, run_id)

    result =
      case get(run.schedule_id) do
        nil -> %{status: "failed", output: "the schedule is gone"}
        s -> work(s)
      end

    run
    |> Ecto.Changeset.change(Map.put(result, :finished_at, DateTime.truncate(DateTime.utc_now(), :second)))
    |> Repo.update!()
  end

  defp work(%Schedule{kind: "agent"} = s) do
    with {:ok, t} <- thread_for(s),
         :ok <- staff(t, s.agent),
         {:ok, _} <- Channel.post(%{thread_id: t.id, author: operator(), body: s.body}) do
      %{status: "ok", thread_id: t.id}
    else
      {:error, why} -> %{status: "failed", output: inspect(why)}
    end
  end

  defp work(%Schedule{kind: "workline"} = s) do
    attrs = %{title: dated(s), stage: "intent", workspace_id: s.workspace_id}

    with {:ok, t} <- Server.open_workline(attrs),
         {:ok, _} <- Channel.post(%{thread_id: t.id, author: operator(), body: s.body}) do
      %{status: "ok", thread_id: t.id}
    else
      {:error, why} -> %{status: "failed", output: inspect(why)}
    end
  end

  defp work(%Schedule{kind: "script"} = s) do
    {code, out} = shell(s.body, dir_for(s))
    tail = String.slice(out, -@output_cap, @output_cap)
    result = Map.merge(%{status: if(code == 0, do: "ok", else: "failed"), exit: code, output: tail}, ran_on(out))

    result =
      if s.standing do
        {:ok, t} = thread_for(s)
        note(t.id, "⏰ #{s.title} — exit #{code}\n```\n#{String.slice(tail, -1500, 1500)}\n```")
        Map.put(result, :thread_id, t.id)
      else
        result
      end

    # the note above wakes no one, by design; a red run is the sheriff's to triage
    if code != 0 do
      source = %{id: result[:thread_id], title: s.title, workspace_id: s.workspace_id}

      Server.Sheriff.report(
        source,
        "the scheduled run failed (exit #{code}): #{String.slice(String.trim(tail), -300, 300)}"
      )
    end

    result
  end

  # a standing schedule's one thread (opened by its first firing, reopened if since closed), else
  # a fresh thread for this firing
  defp thread_for(%Schedule{standing: true, thread_id: tid} = s) when is_integer(tid) do
    case Channel.reopen_if_closed(tid) do
      :no_thread -> open_thread(s)
      _ -> {:ok, Channel.thread(tid)}
    end
  end

  defp thread_for(s), do: open_thread(s)

  defp open_thread(s) do
    title = if s.standing, do: s.title, else: dated(s)

    with {:ok, t} <- Channel.open_thread(%{title: title, workspace_id: s.workspace_id, scope: "machine"}) do
      if s.standing, do: {:ok, _} = update_thread(s, t.id)
      {:ok, t}
    end
  end

  defp update_thread(s, tid), do: s |> Ecto.Changeset.change(thread_id: tid) |> Repo.update()

  defp staff(_t, nil), do: :ok

  # the lead it runs with: the staffing pass spawns them onto it, and the prompt is their wake
  defp staff(t, agent) do
    case Channel.assign_lead(t.id, agent) do
      {:ok, _} -> :ok
      {:error, why} -> {:error, {:assign_lead, agent, why}}
    end
  end

  # a script's output for the record: on the thread, but delivered at birth — it is for the
  # operator to read, not a wake for the thread's lead
  defp note(tid, body) do
    %{thread_id: tid, author: "tlon", body: body}
    |> Message.post_changeset()
    |> Ecto.Changeset.put_change(:delivered_at, DateTime.truncate(DateTime.utc_now(), :second))
    |> Repo.insert!()
    |> tap(&Server.Bus.broadcast({:message_posted, &1}))
  end

  defp dir_for(%Schedule{dir: dir}) when is_binary(dir) and dir != "", do: Path.expand(dir)

  defp dir_for(s) do
    case Server.Workspaces.repos(s.workspace_id) do
      [r | _] -> Path.expand(r.path)
      [] -> System.user_home!()
    end
  end

  # the command in `sh -c`, output merged, nothing on its stdin (a command that reads it ends
  # rather than waits); one that outlives the timeout is killed with every process it started
  # (its tree, read off `pgrep -P`) and reported as exit 124
  defp shell(cmd, dir) do
    args = ["-c", "exec </dev/null\n" <> cmd]
    port = Port.open({:spawn_executable, "/bin/sh"}, [:binary, :exit_status, :stderr_to_stdout, args: args, cd: dir])
    timeout = Application.get_env(:server, :schedule_script_timeout_ms, @script_timeout_ms)
    collect(port, "", System.monotonic_time(:millisecond) + timeout, fn -> kill(port) end, timeout)
  rescue
    e -> {127, Exception.message(e)}
  end

  defp collect(port, out, deadline, kill, timeout) do
    wait = max(0, deadline - System.monotonic_time(:millisecond))

    receive do
      {^port, {:data, d}} ->
        collect(port, String.slice(out <> d, -(4 * @output_cap), 4 * @output_cap), deadline, kill, timeout)

      {^port, {:exit_status, code}} ->
        {code, out}
    after
      wait ->
        kill.()
        close(port)
        {124, out <> "\n… timed out after #{div(timeout, 1000)} s"}
    end
  end

  # the script's pid, asked only now: a fast one may be long gone, and its port with it
  defp kill(port) do
    case Port.info(port, :os_pid) do
      {:os_pid, pid} -> kill_tree(pid)
      nil -> :ok
    end
  end

  # the kill may have closed the port already, and closing a closed port raises
  defp close(port) do
    Port.close(port)
  rescue
    ArgumentError -> :ok
  end

  # every descendant is found before any is killed — a killed parent's children are re-parented away
  defp kill_tree(pid) do
    pids = Enum.map([pid | descendants(pid)], &Integer.to_string/1)
    System.cmd("kill", ["-KILL" | pids], stderr_to_stdout: true)
  end

  defp descendants(pid) do
    {out, _} = System.cmd("pgrep", ["-P", Integer.to_string(pid)], stderr_to_stdout: true)
    kids = for l <- String.split(out, "\n", trim: true), {n, ""} <- [Integer.parse(l)], do: n
    kids ++ Enum.flat_map(kids, &descendants/1)
  end

  defp dated(s), do: "#{s.title} · #{Calendar.strftime(to_local(DateTime.utc_now()), "%b %-d %H:%M")}"

  @doc "The server's local wall-clock time now, as a UTC-labelled datetime — whose year and month a calendar shows."
  def local_now, do: to_local(DateTime.utc_now())

  # local wall-clock time, carried as a UTC-labelled datetime (what Expression matches against),
  # through the OS's own timezone rules for that instant — so a date across a DST change converts
  # with the offset in force then, not now
  defp to_local(%DateTime{} = utc) do
    utc |> DateTime.to_naive() |> NaiveDateTime.to_erl() |> :calendar.universal_time_to_local_time() |> naive_utc()
  end

  defp after_local(expr, utc), do: expr |> Expression.next_at(to_local(utc)) |> from_local(expr)

  # a local slot back to UTC: an hour that happens twice (clocks back) is its first; one that never
  # happens (clocks forward) is the next slot after it
  defp from_local(local, expr) do
    local
    |> DateTime.to_naive()
    |> NaiveDateTime.to_erl()
    |> :calendar.local_time_to_universal_time_dst()
    |> case do
      [utc | _] -> naive_utc(utc)
      [] -> from_local(Expression.next_at(expr, local), expr)
    end
  end

  defp naive_utc(erl), do: erl |> NaiveDateTime.from_erl!() |> DateTime.from_naive!("Etc/UTC")

  defp operator, do: Application.get_env(:server, :operator, "andrew")

  # the last `ran-on: <check> <sha>` line a script printed: the commit it checked
  defp ran_on(out) do
    case Regex.scan(~r/^ran-on: (\S+) ([0-9a-f]{40})$/m, out) do
      [] -> %{}
      found -> with [_, check, sha] <- List.last(found), do: %{check_name: check, sha: sha}
    end
  end
end
