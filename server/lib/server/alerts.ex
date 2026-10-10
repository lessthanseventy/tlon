defmodule Server.Alerts do
  @moduledoc """
  What the desktop should raise, and how loudly — the needs queue (`Server.Office.Needs`) and the
  calendar's meetings (`Server.Calendar`) as one list, served at `GET /api/alerts`:

    * **alarm** — a meeting from `alarm_minutes` (settings file, default 5) before it starts until
      ten minutes in: full screen, with Join;
    * **decision** — work has stopped on a choice (a gate, a dialog, a question, a coworker's
      ask): a banner with its answers;
    * **sticky** — wants the operator, nothing waits on it (a red verify, a mention): stays until
      dismissed or resolved. A rollout note raises nothing here: the office's inbox has it;
    * **info** — something the operator set going took effect where they can't see it: a toast
      that goes by on its own, no actions. One per happening, keyed by it, and listed for ten
      minutes after. Kinds: `seated`, a thread parked on the leaf cap got its coworker
      (`Server.Staffing.note_seated/2`); `landed`, a workline reached `merged`
      (`Server.Workline.landed_since/1`, its `stage_advanced` event); `live`, the service booted
      on a new release (`Server.Release.PM.note_live/1`).

  Each alert is `%{key, level, kind, title, body, at, thread_id, link, actions}`; an action is a
  call on the operator API (`method`, `path`, `body`, and `input` naming the body field a typed
  answer fills) or a link to `open`, so a surface acts on any alert the same way. Alarms first,
  then decisions, then sticky, then info; snoozing and dismissing are the surface's.
  """

  @alarm_minutes 5
  # a rollout's housekeeping: the inbox has it, the desktop doesn't
  @inbox_only ~w(rollout)
  @alarm_after_s 600
  @info_s 600

  @doc "Every alert now."
  def list do
    now = DateTime.utc_now()
    minutes = Server.OperatorConfig.setting("alarm_minutes")
    window = {DateTime.add(now, -@alarm_after_s), DateTime.add(now, minutes * 60)}
    since = DateTime.add(now, -@info_s)

    build(Server.Office.Needs.list(), Server.Calendar.upcoming(window), now,
      alarm_minutes: minutes,
      seated: Server.Staffing.seated_since(since),
      landed: Server.Workline.landed_since(since),
      live: Server.Release.PM.live_since(since)
    )
  end

  @doc """
  The alerts for these needs and meetings at `now` — `list/0` without the reads. Raised as info:
  `seated:` the seating notices, `landed:` the landings, `live:` the live-release notices.
  """
  def build(needs, meetings, now, opts \\ []) do
    lead = Keyword.get(opts, :alarm_minutes, @alarm_minutes) * 60

    alarms =
      for m <- meetings,
          DateTime.diff(m.start, now) <= lead,
          DateTime.diff(now, m.start) <= @alarm_after_s,
          do: alarm(m)

    from_needs = needs |> Enum.reject(&(&1.kind in @inbox_only)) |> Enum.map(&from_need/1)

    Enum.sort_by(alarms, & &1.at, DateTime) ++
      Enum.filter(from_needs, &(&1.level == "decision")) ++
      Enum.filter(from_needs, &(&1.level == "sticky")) ++
      Enum.map(Keyword.get(opts, :seated, []), &info("seated", &1, &1.body)) ++
      Enum.map(Keyword.get(opts, :landed, []), &info("landed", &1, "##{&1.thread_id} landed — #{&1.title}")) ++
      Enum.map(Keyword.get(opts, :live, []), &info("live", &1, &1.body))
  end

  defp info(kind, m, title) do
    %{
      key: "#{kind}:#{m.id}",
      level: "info",
      kind: kind,
      title: title,
      body: nil,
      at: m.created_at,
      thread_id: m.thread_id,
      link: nil,
      actions: []
    }
  end

  defp alarm(m) do
    %{
      key: "meeting:#{m.uid}:#{DateTime.to_iso8601(m.start)}",
      level: "alarm",
      kind: "meeting",
      title: m.title,
      body: m[:calendar],
      at: m.start,
      thread_id: nil,
      link: m.link,
      actions: if(m.link, do: [%{label: "Join", open: m.link}], else: [])
    }
  end

  defp from_need(n) do
    level = if n.kind in ~w(gate dialog question ask), do: "decision", else: "sticky"

    %{
      key: n.key,
      level: level,
      kind: n.kind,
      title: n.title,
      body: n.text,
      at: n.at,
      thread_id: n.thread_id,
      link: nil,
      actions: actions(n) ++ put_away(n)
    }
  end

  # what nothing waits on can be put away on the server (`Office.Needs.dismiss/1`), so it leaves the
  # office's inbox too, not only this surface
  defp put_away(%{kind: kind, level: level, key: key}) when level == "decide" or kind == "ask",
    do: [%{label: "Put away", method: "POST", path: "/api/office/needs/dismiss", body: %{key: key}}]

  defp put_away(_need), do: []

  # a review gate has a build behind it, so it can also go back: to build for the code, to plan for its shape
  defp actions(%{kind: "gate", thread_id: t, stage: "review"}),
    do: [read_doc(t), call("Approve", "/approve", t), send_back("build", t), send_back("plan", t), other(t)]

  defp actions(%{kind: "gate", thread_id: t}), do: [read_doc(t), call("Approve", "/approve", t), other(t)]

  defp actions(%{kind: "dialog", thread_id: t, options: options}),
    do: Enum.map(options || [], &call(&1["label"], "/messages", t, %{body: &1["key"]})) ++ [other(t)]

  # by the ask's own id, so two asks on one thread never cross
  defp actions(%{kind: "ask", ref: id, options: options}),
    do:
      for(
        o <- options || [],
        do: %{label: o["label"], method: "POST", path: "/api/office/asks/#{id}", body: %{key: o["key"]}}
      )

  defp actions(%{kind: k, thread_id: t}) when k in ~w(question mention),
    do: ["Reply…" |> call("/messages", t) |> Map.put(:input, "body")]

  defp actions(%{kind: "verify_failed", thread_id: t}), do: [call("Run verify again", "/verify", t)]

  defp actions(%{kind: "rollout", ref: id}),
    do: [%{label: "Done", method: "DELETE", path: "/api/office/rollout/#{id}", body: nil}]

  defp actions(%{kind: "issue", ref: id}),
    do: [%{label: "Resolve", method: "POST", path: "/api/issues/#{id}/resolve", body: %{}}]

  defp actions(%{kind: "stranded", key: key}),
    do: [%{label: "Take the checkout down", method: "POST", path: "/api/office/needs/retire", body: %{key: key}}]

  defp actions(_need), do: []

  defp call(label, sub, t, body \\ nil),
    do: %{label: label, method: "POST", path: "/api/threads/#{t}#{sub}", body: body}

  # the doc the gate is about, to read before approving it
  defp read_doc(t), do: %{label: "Read it", read: "/api/threads/#{t}/docs/current"}

  defp other(t), do: "Other…" |> call("/messages", t) |> Map.put(:input, "body")

  defp send_back(stage, t), do: "Back to #{stage}…" |> call("/send_back", t, %{stage: stage}) |> Map.put(:input, "why")
end
