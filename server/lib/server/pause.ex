defmodule Server.Pause do
  @moduledoc """
  The office's stop controls. Pencils down asks it to stop: intake routes nothing and no workline
  is nudged to continue (`Server.Intake`, `Server.Workline.Continuation`), and every coworker on a
  live thread hears, as a `notice` that wakes nobody, to finish its turn, commit and stop. Lights
  out is pencils down plus the verify and landing queues paused (`Server.Rollout.pause_gates/1`)
  and an Escape into every coworker pane; nothing is killed and every branch stays where it is.
  Back to work undoes either, and wakes every thread this pause stopped that is still open: a chat
  from tlon @mentioning its lead as it is now, so the switchboard wakes it, or spawns its pane.

  The state is the operator's settings file's `"pause"` key (`Server.OperatorConfig`), not a
  workspace's: both levers it pulls, intake and the queues, are the whole office's. A restart keeps
  it, and the boot starts the queues paused under lights out (`OperatorConfig.boot_oban/2`).
  """
  import Ecto.Query

  alias Server.Channel
  alias Server.OperatorConfig
  alias Server.Tmux

  @told "✎ pencils down — finish this turn"

  @resumed "▶ back to work:"

  @doc "`:working`, `:pencils_down` or `:lights_out`."
  def state do
    case OperatorConfig.read()["pause"] do
      "pencils_down" -> :pencils_down
      "lights_out" -> :lights_out
      _ -> :working
    end
  end

  @doc "Ask the office to stop. `{:ok, :pencils_down}`; already there, nothing is said again."
  def pencils_down, do: go(:pencils_down)

  @doc "Stop the office: pencils down, the verify and landing queues paused, every coworker pane interrupted. `{:ok, :lights_out}`."
  def lights_out, do: go(:lights_out)

  @doc "Undo pencils down or lights out. `{:ok, :working}`."
  def back_to_work, do: go(:working)

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

  defp tell_live_threads do
    body =
      @told <>
        ", commit what you have, and stop; don't start anything new. You'll hear when it's back to work."

    for tid <- live_threads(), do: _ = Channel.post(%{thread_id: tid, author: "tlon", body: body, kind: "notice"})
  end

  # Runs before the lobby's back-to-work notice, which is this pause's lower bound next time.
  defp wake_stopped_threads do
    for tid <- stopped_threads(), lead = Channel.thread_lead(tid), lead != nil do
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
            t.state == "open",
        distinct: true,
        select: t.id
    )
  end

  defp live_threads do
    Server.Repo.all(
      from t in Server.Thread,
        join: s in Server.Session,
        on: s.thread_id == t.id and is_nil(s.ended_at),
        where: t.state == "open",
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
