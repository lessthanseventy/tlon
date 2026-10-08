defmodule Server.Rollout do
  @moduledoc """
  What a merge into tlon means for what is running: tlon works on itself, so the code it changes is
  often the code it runs. After a workline merges (`after_merge/1`), the changed paths say which
  parts moved (`parts/1`):

    * the server — restarted once nobody is mid-turn (a coworker's turn is never cut), as a
      transient systemd unit, so the restart outlives the service it stops; outside systemd the
      thread is told the command to run;
    * the office TUI — nothing here: the snapshot carries the office's revision (`revs/0`) and a
      TUI started on an older one offers a reload;
    * the room kit (`office/kit`, `office/rooms`) — the desktop shell bundles it, and that is the
      machine's to pin: a note for the operator (`pending/0`), since tlon never reaches into the
      machine's config.

  The thread gets one line saying what was rolled out.
  """
  use GenServer

  import Ecto.Query

  require Logger

  @quiet_poll_ms 10_000
  @quiet_tries 60

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

  @doc "Roll out a merge: `%{repo, from, to, thread_id}`, `from`..`to` the main commits it moved."
  def after_merge(%{repo: repo, from: from, to: to, thread_id: tid}) do
    {out, 0} = System.cmd("git", ["-C", repo, "diff", "--name-only", from, to])
    parts = out |> String.split("\n", trim: true) |> parts()
    own? = Path.expand(repo) == Path.expand(Server.Profiles.tlon_root())

    lines =
      if(own? and :server in parts, do: [restart_server(repo, tid)], else: []) ++
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

  @doc "Notes waiting on the operator — what a rollout could not do itself. `[%{id, text, at}]`."
  def pending, do: if(GenServer.whereis(__MODULE__), do: GenServer.call(__MODULE__, :pending), else: [])

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
  executing (their gate scripts die with the server). `[]` is the change window open.
  """
  def busy do
    turns = for {tid, _} <- Server.Presence.Thinking.thinking_all(), do: "a coworker is mid-turn on ##{tid}"

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

  defp restart_server(repo, tid) do
    if System.get_env("INVOCATION_ID") && System.find_executable("systemd-run") do
      Task.Supervisor.start_child(Server.TaskSupervisor, fn -> restart_when_quiet(repo, tid, @quiet_tries) end)
      "the server restarts once nobody is mid-turn"
    else
      "the server needs a restart: mise run server:restart"
    end
  end

  # Wait for a moment no coworker is mid-turn (or give up waiting and say so), then hand the
  # rebuild-and-restart to a transient unit: the service stops under it and must not take it down.
  defp restart_when_quiet(repo, tid, 0) do
    Server.Channel.post(%{
      thread_id: tid,
      author: "tlon",
      body:
        "⟳ the server restart is still waiting — someone has been mid-turn for ten minutes; run mise run server:restart when it suits"
    })

    run_restart(repo)
  end

  defp restart_when_quiet(repo, tid, tries) do
    if quiet?() do
      run_restart(repo)
    else
      Process.sleep(@quiet_poll_ms)
      restart_when_quiet(repo, tid, tries - 1)
    end
  end

  defp run_restart(repo) do
    env = for var <- ["PATH", "HOME", "XDG_RUNTIME_DIR"], v = System.get_env(var), do: ["-E", "#{var}=#{v}"]

    args =
      [
        "--user",
        "--collect",
        "--quiet",
        "--unit",
        "tlon-redeploy-#{System.os_time(:second)}",
        "-p",
        "WorkingDirectory=#{repo}"
      ] ++
        List.flatten(env) ++ ["mise", "run", "server:restart"]

    {out, code} = System.cmd("systemd-run", args, stderr_to_stdout: true)
    if code != 0, do: Logger.warning("rollout: the server restart could not be started: #{String.slice(out, 0, 300)}")
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
end
