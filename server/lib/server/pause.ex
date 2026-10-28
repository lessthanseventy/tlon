defmodule Server.Pause do
  @moduledoc """
  The office's stop controls. Pencils down asks it to stop: intake routes nothing and no workline
  is nudged to continue (`Server.Intake`, `Server.Workline.Continuation`), and every coworker on a
  live thread hears, as a `notice` that wakes nobody, to finish its turn, commit and stop. While
  paused only the operator's own posts wake anyone (`Server.Switchboard.deliver/1`): every other
  wake — a stage brief, a sheriff's report, a coworker's post — is held undelivered and the drain after
  back to work delivers it; and nothing is staffed (`at_work/0`, asked by `Server.Tickets.start_thread/2`
  and `staff_child`). Lights
  out is pencils down plus the verify and landing queues paused (`Server.Rollout.pause_gates/1`)
  and an Escape into every coworker pane; nothing is killed and every branch stays where it is.
  Back to work undoes either, and wakes every thread this pause stopped that is still open: a chat
  from tlon @mentioning its lead as it is now, so the switchboard wakes it, or spawns its pane.

  The state is the operator's settings file's `"pause"` key (`Server.OperatorConfig`), not a
  workspace's: both levers it pulls, intake and the queues, are the whole office's. A restart keeps
  it, and the boot starts the queues paused under lights out (`OperatorConfig.boot_oban/2`).

  One thread can be paused on its own (`pause_thread/1`, the mark `thread.paused_at`; it stays
  `"open"` to every query): its lead hears the same finish-this-turn notice, only the operator's
  posts wake it, it owes no continuation, stalled Need or wake alert, and staffing a child of it is
  refused. The office's pause leaves it alone both ways: pencils down tells it nothing again and back
  to work does not resume it. `resume_thread/1` clears the mark, drains what was held and wakes the
  lead.
  """
  import Ecto.Query

  alias Server.Channel
  alias Server.OperatorConfig
  alias Server.Tmux

  @told "✎ pencils down — finish this turn"

  # differs from @told so stopped_threads/0 never counts a thread pause as the office's
  @thread_told "✎ paused — finish this turn"

  @resumed "▶ back to work:"

  @doc "`:working`, `:pencils_down` or `:lights_out`."
  def state do
    case OperatorConfig.read()["pause"] do
      "pencils_down" -> :pencils_down
      "lights_out" -> :lights_out
      _ -> :working
    end
  end

  @doc "`:ok` at work; paused, `{:error, line}` — the line a door that would start work says instead."
  def at_work do
    case state() do
      :working -> :ok
      :pencils_down -> {:error, "the office is paused (pencils down): back to work first"}
      :lights_out -> {:error, "the office is paused (lights out): back to work first"}
    end
  end

  @doc "Ask the office to stop. `{:ok, :pencils_down}`; already there, nothing is said again."
  def pencils_down, do: go(:pencils_down)

  @doc "Stop the office: pencils down, the verify and landing queues paused, every coworker pane interrupted. `{:ok, :lights_out}`."
  def lights_out, do: go(:lights_out)

  @doc "Undo pencils down or lights out. `{:ok, :working}`."
  def back_to_work, do: go(:working)

  @doc """
  A plan meter reading (`%{five_hour?: w, seven_day?: w}`, `w = %{percent, resets_at}`): at the
  `auto_pause_at` knob, pencils down and the reason on the lobby. Only from :working; a window that
  already paused the office (its `resets_at`, kept per window in the settings file) never pauses it
  again, so the operator's back_to_work sticks. Always `:ok`.
  """
  def auto(windows) do
    limit = OperatorConfig.setting("auto_pause_at")
    latched = latched()

    with :working <- state(),
         {name, %{percent: p, resets_at: r}} <-
           Enum.find(windows, fn {name, w} ->
             w.percent >= limit and Map.get(latched, to_string(name), :none) != w.resets_at
           end) do
      :ok = OperatorConfig.put("auto_paused_for", Map.put(latched, to_string(name), r))
      {:ok, _} = pencils_down()
      auto_say(name, p, r)
    end

    :ok
  end

  # One slot per window, so one window firing never forgets the other's override.
  defp latched do
    case OperatorConfig.read()["auto_paused_for"] do
      %{} = m -> m
      _ -> %{}
    end
  end

  defp auto_say(name, percent, resets_at) do
    label = if name == :five_hour, do: "5h", else: "weekly"

    reset =
      with r when is_binary(r) <- resets_at,
           {:ok, at, _} <- DateTime.from_iso8601(r),
           do: ", resets #{Calendar.strftime(at, "%H:%M")} UTC",
           else: (_ -> "")

    body = "#{label} at #{round(percent)}%#{reset} — pencils down, back to work when you say"

    with %Server.Thread{id: id} <- Channel.machine_thread(),
         do: _ = Channel.post(%{thread_id: id, author: "tlon", body: body, kind: "notice"})
  end

  @doc "Whether this one thread is paused, by the operator or by its lead's hold."
  def thread_paused?(thread_id),
    do: Server.Repo.exists?(from t in Server.Thread, where: t.id == ^thread_id and not is_nil(t.paused_at))

  @doc "Every thread paused on its own, as a set: one query for a list of candidates."
  def paused_thread_ids do
    from(t in Server.Thread, where: not is_nil(t.paused_at), select: t.id) |> Server.Repo.all() |> MapSet.new()
  end

  @doc """
  Pause one thread: its lead is told to finish the turn, and nothing but the operator's posts wakes
  it until `resume_thread/1`. `{:ok, thread}`; already paused, nothing is said again.
  `{:error, :not_found | :not_open}`. A lead's hold (`Server.MCP.Tool.HoldThread`) passes its `why`,
  which the notice carries: the mark is cleared only by `resume_thread/1`, never by a turn ending.
  """
  def pause_thread(thread_id, why \\ nil) do
    with {:ok, %Server.Thread{paused_at: nil} = thread} <- open_thread(thread_id) do
      now = DateTime.truncate(DateTime.utc_now(), :second)
      {:ok, thread} = thread |> Ecto.Changeset.change(paused_at: now) |> Server.Repo.update()
      tell(thread_id, @thread_told, why)
      {:ok, thread}
    end
  end

  @doc """
  Undo `pause_thread/1`: clear the mark, wake the lead, deliver what was held. `{:ok, thread}`; not
  paused, nothing is said. The mark goes first, or the wake itself is held.
  """
  def resume_thread(thread_id) do
    with {:ok, %Server.Thread{paused_at: %DateTime{}} = thread} <- open_thread(thread_id) do
      {:ok, thread} = thread |> Ecto.Changeset.change(paused_at: nil) |> Server.Repo.update()
      wake(thread_id)
      Server.Switchboard.drain()
      {:ok, thread}
    end
  end

  defp open_thread(thread_id) do
    case Server.Repo.get(Server.Thread, thread_id) do
      nil -> {:error, :not_found}
      %Server.Thread{state: "open"} = thread -> {:ok, thread}
      _ -> {:error, :not_open}
    end
  end

  defp go(want) do
    from = state()

    if from != want do
      :ok = OperatorConfig.put("pause", if(want != :working, do: Atom.to_string(want)))
      if from == :working, do: tell_live_threads()
      if want == :working, do: wake_stopped_threads()
      if want == :lights_out, do: lights_off()
      if from == :lights_out, do: Server.Rollout.pause_gates(:resume_queue)
      lobby(want)
    end

    {:ok, want}
  end

  defp tell_live_threads, do: for(tid <- live_threads(), do: tell(tid, @told))

  defp tell(tid, head, why \\ nil) do
    held = if why, do: " (held: #{why})", else: ""

    body =
      head <>
        ", commit what you have, and stop; don't start anything new." <>
        held <> " You'll hear when it's back to work."

    _ = Channel.post(%{thread_id: tid, author: "tlon", body: body, kind: "notice"})
  end

  # Runs before the lobby's back-to-work notice, which is this pause's lower bound next time.
  defp wake_stopped_threads, do: for(tid <- stopped_threads(), do: wake(tid))

  defp wake(tid) do
    with lead when lead != nil <- Channel.thread_lead(tid) do
      body = "@#{lead} ▶ back to work — pick up where you stopped, from the brief."
      _ = Channel.post(%{thread_id: tid, author: "tlon", body: body})
    end
  end

  defp stopped_threads do
    since =
      Server.Repo.one(
        from m in Server.Message,
          where: m.author == "tlon" and m.kind == "notice" and like(m.body, ^"#{@resumed}%"),
          select: max(m.id)
      ) || 0

    Server.Repo.all(
      from m in Server.Message,
        join: t in Server.Thread,
        on: t.id == m.thread_id,
        where:
          m.id > ^since and m.author == "tlon" and m.kind == "notice" and like(m.body, ^"#{@told}%") and
            t.state == "open" and is_nil(t.paused_at),
        distinct: true,
        select: t.id
    )
  end

  defp live_threads do
    Server.Repo.all(
      from t in Server.Thread,
        join: s in Server.Session,
        on: s.thread_id == t.id and is_nil(s.ended_at),
        where: t.state == "open" and is_nil(t.paused_at),
        distinct: true,
        select: t.id
    )
  end

  defp lights_off do
    Server.Rollout.pause_gates(:pause_queue)

    for %{id: ws} <- Server.Workspaces.all(),
        tabs = Tmux.list_windows(ws),
        is_list(tabs),
        %{agent: agent, index: window} <- tabs,
        agent != nil,
        do: Tmux.interrupt(ws, window)
  end

  defp lobby(state) do
    body =
      case state do
        :pencils_down ->
          "✎ pencils down: nothing new is picked up, and every coworker is asked to stop after its turn."

        :lights_out ->
          "◼ lights out: nothing new is picked up, verify and landing are paused, and every pane was interrupted."

        :working ->
          @resumed <> " intake, nudges, verify and landing are on again."
      end

    with %Server.Thread{id: id} <- Channel.machine_thread(),
         do: _ = Channel.post(%{thread_id: id, author: "tlon", body: body, kind: "notice"})
  end
end
