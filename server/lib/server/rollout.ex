defmodule Server.Rollout do
  @moduledoc """
  What a merge into tlon means for what is running: tlon works on itself, so the code it changes is
  often the code it runs. After a workline merges (`after_merge/1`), the changed paths say which
  parts moved (`parts/1`):

    * the server — nothing runs it yet: the service runs the release pointer (`scripts/release.sh`),
      so a merge waits for the next `release:cut`, and the thread says so;
    * the office TUI — nothing here: the snapshot carries the office's revision (`revs/0`) and a
      TUI started on an older one offers a reload;
    * the room kit (`office/kit`, `office/rooms`) — the desktop shell bundles it, and that is the
      machine's to pin: a note for the operator (`pending/0`), since tlon never reaches into the
      machine's config.

  The thread gets one line saying what was rolled out.

  Notes live in this process's state, so a restart drops them and the next check refiles them. That
  is fine for a note a check keeps true: `note/2` is keyed, so refiling after a restart makes one
  note, not a pile, and `clear/1` removes it when the check passes again.
  """
  use GenServer

  import Ecto.Query

  require Logger

  @quiet_poll_ms 10_000
  @waiter :tlon_restart_waiter

  def start_link(_), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  @doc "Which parts of tlon a set of changed paths touches."
  @spec parts([String.t()]) :: MapSet.t(:server | :office_tui | :office_room | :adapters)
  def parts(paths) do
    paths
    |> MapSet.new(fn
      "server/" <> _ -> :server
      "office/tui/" <> _ -> :office_tui
      "office/kit/" <> _ -> :office_room
      "office/rooms/" <> _ -> :office_room
      "adapters/" <> _ -> :adapters
      _ -> nil
    end)
    |> MapSet.delete(nil)
  end

  @doc """
  Roll out a merge: `%{repo, from, to, thread_id}`, `from`..`to` the main commits it moved. A range
  git can't diff is said on the thread, never raised: the landing still publishes after it.
  """
  def after_merge(%{repo: repo, from: from, to: to, thread_id: tid} = merge) do
    case System.cmd("git", ["-C", repo, "diff", "--name-only", from, to], stderr_to_stdout: true) do
      {out, 0} ->
        roll_out(merge, out |> String.split("\n", trim: true) |> parts())

      {_, code} ->
        {:ok, _} =
          Server.Channel.post(%{
            thread_id: tid,
            author: "tlon",
            body: "⟳ rollout unknown: git diff #{from}..#{to} exited #{code} in #{repo}, so what changed is unread"
          })

        :ok
    end
  end

  @doc "Notes waiting on the operator — what a rollout could not do itself. `[%{id, text, at}]`."
  def pending, do: if(GenServer.whereis(__MODULE__), do: GenServer.call(__MODULE__, :pending), else: [])

  @doc "File note `text` under `key`: a note already filed under it has its text replaced in place."
  def note(key, text), do: GenServer.cast(__MODULE__, {:note, key, text})

  @doc "Drop the note filed under `key`, if any."
  def clear(key), do: GenServer.cast(__MODULE__, {:clear, key})

  @doc "Done with note `id` (the operator did it, or doesn't need to)."
  def dismiss(id), do: if(GenServer.whereis(__MODULE__), do: GenServer.call(__MODULE__, {:dismiss, id}), else: :ok)

  @doc "The revisions surfaces compare against their own: `%{office: <tree sha of office/ on main>}`."
  def revs do
    case :persistent_term.get({__MODULE__, :revs}, nil) do
      {at, revs} when at > 0 -> if System.monotonic_time(:second) - at < 10, do: revs, else: fresh_revs()
      _ -> fresh_revs()
    end
  end

  defp fresh_revs do
    revs =
      case System.cmd("git", ["-C", Server.Profiles.tlon_root(), "rev-parse", "HEAD:office"], stderr_to_stdout: true) do
        {sha, 0} -> %{office: String.trim(sha)}
        _ -> %{office: nil}
      end

    :persistent_term.put({__MODULE__, :revs}, {System.monotonic_time(:second), revs})
    revs
  rescue
    _ -> %{office: nil}
  end

  @doc """
  What a restart would cut off right now, one line each: a coworker mid-turn, a verify or a landing
  executing (their gate scripts die with the server). `[]` is the change window open. `thinking`
  is who is mid-turn, by thread (the live tracker's unless given).
  """
  def busy(thinking \\ Server.Presence.Thinking.thinking_all()) do
    turns = for {tid, _} <- thinking, do: "a coworker is mid-turn on ##{tid}"

    jobs =
      for {queue, args} <-
            Server.Repo.all(
              from j in Oban.Job,
                where: j.queue in ["verify", "landing"] and j.state == "executing",
                select: {j.queue, j.args}
            ),
          do: "the #{if queue == "verify", do: "verify", else: "landing"} of ##{args["thread_id"]} is running"

    turns ++ jobs
  end

  @doc "Whether a restart cuts nothing off now (`busy/0` is empty)."
  def quiet?, do: busy() == []

  @doc """
  Restart the server — the office's button and a merge's rollout alike. Quiet (or `force: true`):
  now, `:ok` or `{:error, why}`. Busy: one restart is scheduled for the first quiet moment — it
  waits as long as it takes, never forcing — and `{:scheduled, lines}` says what it waits on; a
  second ask while one is scheduled joins it. `why:` is what the workers' notice says; `run:`,
  `busy:` and `poll_ms:` stand in for the restart, `busy/0` and the poll in a test (the app env's
  `:restart_run` for `run:` where a caller can't pass it, e.g. through the API).
  """
  def restart(opts \\ []) do
    why = Keyword.get(opts, :why, "the operator asked")
    busy = Keyword.get(opts, :busy, &busy/0)

    case Keyword.get_lazy(opts, :run, fn -> Application.get_env(:server, :restart_run) || systemd_restart(why) end) do
      nil -> {:error, "not under systemd: run mise run server:restart"}
      run -> restart(run, busy, Keyword.get(opts, :force, false), Keyword.get(opts, :poll_ms, @quiet_poll_ms))
    end
  end

  defp restart(run, _busy, true, _poll_ms), do: run.(true)

  defp restart(run, busy, false, poll_ms) do
    if busy.() == [], do: run.(false), else: schedule(run, busy, poll_ms)
  end

  @doc "Whether a restart is scheduled for the first quiet moment."
  def restart_pending?, do: Process.whereis(@waiter) != nil

  @doc "Drop a scheduled restart. `:ok` whether or not one was."
  def cancel_restart do
    with pid when is_pid(pid) <- Process.whereis(@waiter) do
      # unregistered first, so restart_pending?/0 is false once this returns, not once the kill lands
      try do
        Process.unregister(@waiter)
      rescue
        ArgumentError -> :ok
      end

      Process.exit(pid, :kill)
      pause_gates(:resume_queue)
    end

    :ok
  end

  @doc """
  Tell every open thread with a live session that the server is restarting (`why` says who asked),
  as a `notice`: it wakes nobody, so announcing a restart never makes anyone busy. `:ok`.
  `scripts/server-restart.sh` calls it (`tlon-cli announce-restart`), the one door every restart takes.
  """
  def announce_restart(why) do
    threads =
      Server.Repo.all(
        from t in Server.Thread,
          join: s in Server.Session,
          on: s.thread_id == t.id and is_nil(s.ended_at),
          where: t.state == "open",
          distinct: true,
          select: t.id
      )

    body =
      "⟳ the server is restarting (#{why}). A tool call in the next minute may fail: retry it, and don't read it as the server being down."

    for tid <- threads,
        do: _ = Server.Channel.post(%{thread_id: tid, author: "tlon", body: body, kind: "notice"})

    :ok
  end

  defp run_restart(repo, why, extra) do
    env =
      Enum.map(
        [
          {"TLON_RESTART_WHY", why}
          | for(var <- ["PATH", "HOME", "XDG_RUNTIME_DIR"], v = System.get_env(var), do: {var, v})
        ],
        fn {var, v} -> ["-E", "#{var}=#{v}"] end
      )

    args =
      [
        "--user",
        "--collect",
        "--quiet",
        "--slice=tlon.slice",
        "--unit",
        "tlon-redeploy-#{System.os_time(:second)}",
        "-p",
        "WorkingDirectory=#{repo}"
      ] ++
        List.flatten(env) ++ ["mise", "run", "server:restart"] ++ extra

    case System.cmd("systemd-run", args, stderr_to_stdout: true) do
      {_, 0} ->
        :ok

      {out, _} ->
        Logger.warning("rollout: the server restart could not be started: #{String.slice(out, 0, 300)}")
        {:error, "the restart could not be started: #{String.slice(out, 0, 200)}"}
    end
  end

  defp note_desktop(short) do
    GenServer.cast(
      __MODULE__,
      {:note, "the desktop shell runs an older office: pin tlon (#{short}) in the machine config and switch"}
    )

    "the desktop shell needs a pin (in your needs list)"
  end

  @impl true
  def init(_), do: {:ok, %{notes: [], next: 1}}

  @impl true
  def handle_call(:pending, _from, state), do: {:reply, Enum.reverse(state.notes), state}

  def handle_call({:dismiss, id}, _from, state),
    do: {:reply, :ok, %{state | notes: Enum.reject(state.notes, &(&1.id == id))}}

  @impl true
  def handle_cast({:note, text}, state) do
    note = %{id: state.next, text: text, at: System.system_time(:second)}
    {:noreply, %{state | notes: [note | state.notes], next: state.next + 1}}
  end

  def handle_cast({:note, key, text}, state) do
    case Enum.find(state.notes, &(&1[:key] == key)) do
      nil ->
        note = %{id: state.next, key: key, text: text, at: System.system_time(:second)}
        {:noreply, %{state | notes: [note | state.notes], next: state.next + 1}}

      %{id: id} ->
        {:noreply, %{state | notes: Enum.map(state.notes, &if(&1.id == id, do: %{&1 | text: text}, else: &1))}}
    end
  end

  def handle_cast({:clear, key}, state), do: {:noreply, %{state | notes: Enum.reject(state.notes, &(&1[:key] == key))}}

  defp schedule(run, busy, poll_ms) do
    if !restart_pending?() do
      # registered by the caller before it waits, so restart_pending?/0 is true once this returns;
      # a schedule that lost the race to another drops its own waiter
      {:ok, pid} =
        Task.Supervisor.start_child(Server.TaskSupervisor, fn ->
          receive do: (:go -> wait_then(run, busy, poll_ms))
        end)

      try do
        Process.register(pid, @waiter)
        pause_gates(:pause_queue)
        send(pid, :go)
      rescue
        ArgumentError -> Process.exit(pid, :kill)
      end
    end

    {:scheduled, busy.()}
  end

  defp wait_then(run, busy, poll_ms) do
    if busy.() == [] do
      run.(false)
    else
      Process.sleep(poll_ms)
      wait_then(run, busy, poll_ms)
    end
  end

  # the rebuild-and-restart goes to a transient unit: the service stops under it and must not take it down
  defp systemd_restart(why) do
    if System.get_env("INVOCATION_ID") && System.find_executable("systemd-run"),
      do: &run_restart(Server.Profiles.tlon_root(), why, force_args(&1))
  end

  defp force_args(true), do: ["--", "--force"]
  defp force_args(false), do: []

  # no new verify or landing starts while a restart waits for the ones running to finish; a boot
  # starts its queues unpaused. Best-effort: a node without those queues running (a test) is a no-op.
  defp pause_gates(verb) do
    for q <- [:verify, :landing], do: apply(Oban, verb, [[queue: q]])
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end

  defp roll_out(%{repo: repo, to: to, thread_id: tid}, parts) do
    own? = Path.expand(repo) == Path.expand(Server.Profiles.tlon_root())

    lines =
      if(own? and :server in parts, do: ["the server ships with the next release:cut"], else: []) ++
        if(own? and MapSet.intersection(parts, MapSet.new([:office_tui, :office_room])) != MapSet.new(),
          do: ["office TUIs offer a reload"],
          else: []
        ) ++
        if(own? and :office_room in parts, do: [note_desktop(String.slice(to, 0, 7))], else: [])

    if lines != [],
      do:
        {:ok, _} =
          Server.Channel.post(%{thread_id: tid, author: "tlon", body: "⟳ rolled out: " <> Enum.join(lines, " · ")})

    :ok
  end
end
