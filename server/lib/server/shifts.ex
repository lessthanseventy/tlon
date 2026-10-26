defmodule Server.Shifts do
  @moduledoc """
  Crews on one bench, as many as the operator names — an account, a provider, a time of day. A
  seat is on one crew, or on every one (`all`, every seat until it is put on one, so a workspace
  with no crews works as it always has). A crew exists while a seat is on it. The workspace has one
  crew on at a time, and `Server.Workspaces.bench/1` is that crew plus the `all` seats, so
  staffing, intake and every restaff pick only from it. A switch restaffs each open workline led
  by someone going off, the workline's own way (`Server.Workline.restaff_now/1`); a plain thread
  waits for its lead's crew.

  Nothing switches crews by itself: a switch is the operator's, by hand or by answering an offer.
  Claude's usage limit on a pane offers the other crews in the lobby; taking one schedules the
  offer to come back at the reset (`Server.Jobs.ShiftBack`). With no other crew, the limit is a
  `quota` item on the operator's list (`out_of_quota/1`, `Server.Office.Needs`) until the reset.
  """
  import Ecto.Query

  alias Server.Channel
  alias Server.Repo
  alias Server.Thread
  alias Server.Workspace
  alias Server.WorkspaceAgent
  alias Server.Workspaces

  require Logger

  @crew ~r/^[a-z0-9][a-z0-9_-]{0,31}$/

  # Claude Code's own usage-limit line, anchored to how it prints it, so a pane that only talks
  # about limits never reads as out of quota
  @quota_out ~r/^\s*(⎿\s*)?(Claude usage limit reached|(5-hour|weekly|session) limit reached\b|You've hit your (usage )?limit\b)/miu

  @doc "The crew on in the workspace."
  def current(workspace_id), do: Repo.one(from w in Workspace, where: w.id == ^workspace_id, select: w.shift) || "day"

  @doc "The workspace's crews, by name: every crew a seat is on (`all` is no crew of its own)."
  def crews(workspace_id),
    do:
      workspace_id
      |> Workspaces.bench_all()
      |> Enum.map(& &1.crew)
      |> Enum.reject(&(&1 == "all"))
      |> Enum.uniq()
      |> Enum.sort()

  @doc "Whether `name` can name a crew: lowercase letters, digits, `-` and `_`, 32 at most."
  def crew_name?(name), do: is_binary(name) and Regex.match?(@crew, name)

  @doc """
  Put crew `to` on. Each open workline led by someone going off is restaffed from the crew coming
  on (`restaffed`); a plain thread they lead waits for them (`waiting`). An open offer to switch is
  withdrawn, and a pending reminder cancelled: the operator has chosen. Switching to the crew
  already on changes nothing. `{:ok, %{restaffed, waiting}}` | `{:error, :unknown_shift | :not_found}`.
  """
  def switch(workspace_id, to) do
    cond do
      is_nil(Repo.get(Workspace, workspace_id)) -> {:error, :not_found}
      current(workspace_id) == to -> {:ok, %{restaffed: [], waiting: []}}
      to not in crews(workspace_id) -> {:error, :unknown_shift}
      true -> switch_to(workspace_id, to)
    end
  end

  @doc """
  An offer taken (`Server.Attention`, an answer naming crew `crew`): that crew goes on, and an offer
  made for a limit (`"back"`, the crew it took off) schedules the offer to come back at the reset.
  `:ok` | `switch/2`'s error (the crew has lost its last seat since the offer, say).
  """
  def take(%{"workspace" => workspace_id} = offer, crew) do
    with {:ok, _} <- switch(workspace_id, crew) do
      if offer["back"], do: remind(workspace_id, offer)
      :ok
    end
  end

  @doc """
  The crew a seat hired now joins: the shift on, once the workspace has crews; with none set, both,
  so a bench with no shifts stays without them.
  """
  def hire_crew(workspace_id) do
    if Enum.any?(Workspaces.bench_all(workspace_id), &(&1.crew != "all")), do: current(workspace_id), else: "all"
  end

  @doc "Whether a pane's text shows Claude Code's usage limit reached."
  def out_of_quota?(text) when is_binary(text), do: Regex.match?(@quota_out, text)

  @doc """
  Coworker `agent`'s pane text, read by the attention sweep: on a Claude Code pane, Claude's usage
  limit reached, with another crew to put on, offers the lobby each other crew — it switches
  nothing; with none, it is remembered for the operator's list (`out_of_quota/1`). A limit line acts once: it stays on screen until the pane scrolls, so each pane's line
  (`pane`, the tab's thread and window) is remembered by fingerprint, in the workspace across
  restarts, until that pane no longer shows one; a new line's offer replaces an open one. A window
  with no coworker tagged on it is never read. `{:offered, crews}` | `:ok`.
  """
  def quota_check(workspace_id, agent, pane, text) do
    if Server.Presence.provider_of(agent, workspace_id) == "anthropic" do
      key = "#{agent}/#{pane}"

      case limit_line(text) do
        nil -> forget(workspace_id, key)
        {line, after_line} -> on_limit(workspace_id, key, line, after_line)
      end
    else
      :ok
    end
  end

  @doc "Put a seat on crew `crew` (any crew name, a new one too) or `all`. `{:ok, seat}` | `{:error, changeset | :not_found}`."
  def assign(seat_id, crew) do
    with %WorkspaceAgent{} = seat <- Repo.get(WorkspaceAgent, seat_id) || {:error, :not_found},
         {:ok, seat} <- seat |> WorkspaceAgent.edit_changeset(%{crew: crew}) |> Repo.update() do
      announce(seat.workspace_id)
      {:ok, seat}
    end
  end

  defp switch_to(workspace_id, to) do
    {1, _} = Repo.update_all(from(w in Workspace, where: w.id == ^workspace_id), set: [shift: to])
    announce(workspace_id)
    withdraw_offers(workspace_id, "withdrawn: the #{to} crew is on")
    cancel_reminders(workspace_id)

    going = workspace_id |> Workspaces.bench_all() |> Enum.filter(&(&1.crew not in ["all", to]))
    {:ok, workspace_id |> led_by(going) |> Enum.reduce(%{restaffed: [], waiting: []}, &change_over(&1, &2, to))}
  end

  defp announce(workspace_id), do: Server.Bus.broadcast({:workspace_edited, Repo.get!(Workspace, workspace_id)})

  defp led_by(_workspace_id, []), do: []

  defp led_by(workspace_id, going) do
    ids = Enum.map(going, & &1.agent_id)

    Repo.all(
      from t in Thread,
        where: t.workspace_id == ^workspace_id and t.state == "open" and t.agent_id in ^ids,
        order_by: t.id
    )
  end

  # restaffed only when the lead actually changed: with nobody of the kind on shift, restaff says so
  # itself and the workline waits
  defp change_over(%Thread{stage: stage} = thread, acc, to) when stage not in [nil, "landed"] do
    before = Channel.thread_lead(thread.id)
    {:ok, _} = Server.Workline.restaff_now(thread)

    if Channel.thread_lead(thread.id) == before do
      %{acc | waiting: acc.waiting ++ [thread.id]}
    else
      note(thread, "⇄ the #{to} crew is on: it picks this workline up at #{stage}.")
      %{acc | restaffed: acc.restaffed ++ [thread.id]}
    end
  end

  defp change_over(thread, acc, to) do
    note(thread, "⇄ the #{to} crew is on: this waits for its lead's crew.")
    %{acc | waiting: acc.waiting ++ [thread.id]}
  end

  defp note(thread, body), do: {:ok, _} = Channel.post(%{thread_id: thread.id, author: "tlon", body: body})

  # the limit line and the line after it (Claude Code may put the reset time there)
  defp limit_line(text) do
    lines = String.split(text, "\n")

    with i when is_integer(i) <- Enum.find_index(lines, &Regex.match?(@quota_out, &1)),
         do: {Enum.at(lines, i), Enum.at(lines, i + 1) || ""}
  end

  defp forget(workspace_id, agent) do
    for knob <- ["limits_seen", "quota_out"],
        seen = seen(workspace_id, knob),
        Map.has_key?(seen, agent),
        do: put_seen(workspace_id, Map.delete(seen, agent), knob)

    :ok
  end

  # remembered once acted on (offered, or nothing to offer): an offer that raises is retried
  defp on_limit(workspace_id, key, line, after_line) do
    mark = fingerprint(line)

    if seen(workspace_id)[key] == mark do
      :ok
    else
      on = current(workspace_id)
      others = workspace_id |> crews() |> List.delete(on)
      text = line <> "\n" <> after_line

      result =
        if others == [], do: note_quota(workspace_id, key, on, text), else: offer(workspace_id, on, others, text)

      remember(workspace_id, key, mark)
      result
    end
  end

  @doc """
  The panes whose Claude usage limit no other crew could take, per workspace, with the reset still
  ahead: `[%{workspace_id, crew, reset, until, at}]` (`reset` the local label, `until` and `at` UTC).
  A pane that no longer shows its limit, or is gone, has left it.
  """
  def out_of_quota(now \\ DateTime.utc_now()) do
    for %Workspace{id: ws, knobs: %{"quota_out" => out}} <- Repo.all(Workspace),
        {_pane, %{"until" => until, "at" => at} = q} <- out,
        {:ok, until, _} = DateTime.from_iso8601(until),
        DateTime.after?(until, now) do
      {:ok, at, _} = DateTime.from_iso8601(at)
      %{workspace_id: ws, crew: q["crew"], reset: q["reset"], until: until, at: at}
    end
  end

  defp offer(workspace_id, on, others, text) do
    {local, how} = reset_at(text, NaiveDateTime.from_erl!(:calendar.local_time()))
    label = Calendar.strftime(local, "%a %-I:%M%P") <> if(how == :estimated, do: ", estimated", else: "")
    withdraw_offers(workspace_id, "withdrawn: a newer limit's offer replaces it")

    with %Thread{id: lobby} <- Channel.machine_thread(workspace_id) do
      {:ok, _} =
        Server.Attention.ask(
          lobby,
          "tlon",
          "Claude's usage limit is reached on the #{on} crew (it resets #{label}). Put another crew on?",
          Enum.map(others, &"#{&1} crew on") ++ ["stay on #{on}"],
          nil,
          %{
            "switch" => %{
              "workspace" => workspace_id,
              "crews" => others,
              "back" => on,
              "reset" => label,
              "estimated" => how == :estimated,
              "at" => DateTime.to_iso8601(to_utc(local))
            }
          }
        )
    end

    {:offered, others}
  end

  defp remind(workspace_id, %{"back" => back, "reset" => label, "at" => at} = offer) do
    {:ok, at, _} = DateTime.from_iso8601(at)
    args = %{workspace_id: workspace_id, back: back, reset: label, estimated: offer["estimated"] == true}

    case Server.Jobs.enqueue(Server.Jobs.ShiftBack.new(args, scheduled_at: at)) do
      {:ok, _} ->
        :ok

      {:error, _} ->
        with %Thread{id: lobby} <- Channel.machine_thread(workspace_id),
             do:
               note(
                 %Thread{id: lobby},
                 "Claude resets #{label}; the reminder to put the #{back} crew back couldn't be scheduled."
               )
    end
  end

  @doc """
  The reset Claude's limit line names, as the next local moment it falls on after `now` (a naive
  local time), and whether the line said so (`:exact`: `5pm`, `9:30am`, `Mon 9:00 AM`) or it is a
  guess (`:estimated`: a bare weekday is the start of that day; nothing at all, five hours on, the
  session window). The server's clock is the local one: right while Claude runs on this box.
  """
  def reset_at(text, now) do
    timed = ~r/resets?\s+(?:at\s+)?(?:(mon|tue|wed|thu|fri|sat|sun)\w*\s+)?(\d{1,2})(?::(\d{2}))?\s*([ap])\.?m/i

    case {Regex.run(timed, text), Regex.run(~r/resets?\s+(?:on\s+)?(mon|tue|wed|thu|fri|sat|sun)\w*/i, text)} do
      {[_, day, h, m, ap | _], _} ->
        {next_at(now, day, String.to_integer(h), if(m == "", do: 0, else: String.to_integer(m)), ap), :exact}

      {nil, [_, day]} ->
        {next_at(now, day, 12, 0, "a"), :estimated}

      _ ->
        {NaiveDateTime.add(now, 5 * 3600), :estimated}
    end
  end

  @doc """
  The reset has come (`Server.Jobs.ShiftBack`): with another crew on than `back`, the one the limit
  took off, the lobby is offered `back` again. Already back, or `back` no crew any more: nothing. `:ok`.
  """
  def offer_back(workspace_id, back, reset, estimated \\ false) do
    on = current(workspace_id)

    with true <- on != back and back in crews(workspace_id),
         %Thread{id: lobby} <- Channel.machine_thread(workspace_id) do
      {:ok, _} =
        Server.Attention.ask(
          lobby,
          "tlon",
          "Claude's limit #{if estimated, do: "should have reset", else: "has reset"} (#{reset}). Put the #{back} crew back on?",
          ["#{back} crew on", "stay on #{on}"],
          nil,
          %{"switch" => %{"workspace" => workspace_id, "crews" => [back]}}
        )
    end

    :ok
  end

  @doc """
  Forget the limit memory of every pane not in `panes` (`\"agent/thread/window\"`): they are gone. An
  empty read (tmux failing to list) is not an empty office, so it forgets nothing.
  """
  def prune(_workspace_id, %MapSet{map: map}) when map_size(map) == 0, do: :ok

  def prune(workspace_id, panes) do
    for knob <- ["limits_seen", "quota_out"] do
      seen = seen(workspace_id, knob)
      kept = Map.filter(seen, fn {key, _} -> MapSet.member?(panes, key) end)
      if map_size(kept) != map_size(seen), do: put_seen(workspace_id, kept, knob)
    end

    :ok
  end

  # the line's fingerprint, not its text: knobs reach every coworker's brief, and pane text is untrusted
  defp fingerprint(line), do: :sha256 |> :crypto.hash(line) |> Base.encode16(case: :lower) |> binary_part(0, 16)

  defp withdraw_offers(workspace_id, why) do
    for ask <- Server.Attention.open_asks(),
        ask.payload["switch"]["workspace"] == workspace_id,
        do: Server.Attention.resolve(ask, why)
  end

  defp next_at(now, day, h, m, ap) do
    hour = rem(h, 12) + if(String.downcase(ap) == "p", do: 12, else: 0)
    at = %{now | hour: hour, minute: m, second: 0, microsecond: {0, 0}}
    wanted = if day != "", do: Enum.find_index(~w(mon tue wed thu fri sat sun), &(&1 == String.downcase(day))) + 1

    0..7
    |> Enum.find(fn d ->
      t = NaiveDateTime.add(at, d * 86_400)
      NaiveDateTime.after?(t, now) and (is_nil(wanted) or Date.day_of_week(t) == wanted)
    end)
    |> then(&NaiveDateTime.add(at, &1 * 86_400))
  end

  # a local time as UTC; one that a spring-forward skips doesn't exist, so an hour on
  defp to_utc(local) do
    local
    |> NaiveDateTime.to_erl()
    |> :calendar.local_time_to_universal_time_dst()
    |> case do
      [] -> to_utc(NaiveDateTime.add(local, 3600))
      times -> times |> List.last() |> NaiveDateTime.from_erl!() |> DateTime.from_naive!("Etc/UTC")
    end
  end

  # a reminder still queued from an earlier limit belongs to a choice the operator has since made
  defp cancel_reminders(workspace_id) do
    Oban.cancel_all_jobs(
      from j in Oban.Job,
        where:
          j.worker == "Server.Jobs.ShiftBack" and j.state in ["scheduled", "available"] and
            fragment("(? ->> 'workspace_id')::int = ?", j.args, ^workspace_id)
    )
  rescue
    # a failed cancel must not break the limit switch, but it leaves a stale reminder behind
    e ->
      Logger.warning("shift reminder cancel failed for workspace #{workspace_id}: #{Exception.message(e)}")
      :ok
  end

  # each Claude pane's limit line already acted on (by fingerprint), in the workspace's knobs so a
  # restart keeps it: the same line still on that pane is the old limit; the pane without one forgets it
  defp seen(workspace_id, knob \\ "limits_seen"), do: (Repo.get!(Workspace, workspace_id).knobs || %{})[knob] || %{}

  defp remember(workspace_id, agent, value, knob \\ "limits_seen"),
    do: put_seen(workspace_id, Map.put(seen(workspace_id, knob), agent, value), knob)

  defp put_seen(workspace_id, seen, knob) do
    workspace = Repo.get!(Workspace, workspace_id)
    {:ok, _} = Workspaces.edit(workspace, %{knobs: Map.put(workspace.knobs || %{}, knob, seen)})
    :ok
  end

  # no other crew to offer: the operator's list carries it (`out_of_quota/1`) until the reset
  defp note_quota(workspace_id, key, on, text) do
    {label, at} = reset_label(text)
    now = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

    remember(
      workspace_id,
      key,
      %{"crew" => on, "reset" => label, "until" => DateTime.to_iso8601(at), "at" => now},
      "quota_out"
    )
  end

  # the reset as a local label and the UTC moment
  defp reset_label(text) do
    {local, how} = reset_at(text, NaiveDateTime.from_erl!(:calendar.local_time()))
    {Calendar.strftime(local, "%a %-I:%M%P") <> if(how == :estimated, do: ", estimated", else: ""), to_utc(local)}
  end
end
