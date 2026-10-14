defmodule Server.Alerts do
  @moduledoc """
  What the desktop should raise, and how loudly — the needs queue (`Server.Office.Needs`) and the
  calendar's meetings (`Server.Calendar`) as one list, served at `GET /api/alerts`:

    * **alarm** — a meeting from `alarm_minutes` (settings file, default 5) before it starts until
      ten minutes in: full screen, with Join;
    * **decision** — work has stopped on a choice (a gate, a dialog, a question, a coworker's
      ask): a banner with its answers;
    * **sticky** — wants the operator, nothing waits on it (a red verify, stuck work): stays until
      dismissed or resolved. A rollout note raises nothing here: the office's inbox has it;
    * **info** — something the operator set going took effect where they can't see it: a toast
      that goes by on its own, no actions. One per happening, keyed by it, and listed for ten
      minutes after. Kinds: `seated`, a thread parked on the leaf cap got its coworker
      (`Server.Staffing.note_seated/2`); `landed`, GitHub merged a workline's PR
      (`Server.Workline.landed_since/1`); `fixing`, an issue a ticket
      took, saying who has it (`Server.Dossier.own_issue/3`); `live`, the service booted
      on a new release (`Server.Release.PM.note_live/1`). A `mention` of the operator is info too: a
      coworker's report goes by, and the office's inbox keeps it; what they must decide is an ask.

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
      fixing: Server.Dossier.fixing_since(since),
      live: Server.Release.PM.live_since(since)
    )
  end

  @doc """
  The alerts for these needs and meetings at `now` — `list/0` without the reads. Raised as info:
  `seated:` the seating notices, `landed:` the landings, `fixing:` the issues a ticket took,
  `live:` the live-release notices.
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
      Enum.filter(from_needs, &(&1.level == "info")) ++
      Enum.map(Keyword.get(opts, :seated, []), &info("seated", &1, &1.body)) ++
      Enum.map(Keyword.get(opts, :landed, []), &info("landed", &1, "##{&1.thread_id} landed — #{&1.title}")) ++
      Enum.map(Keyword.get(opts, :fixing, []), &info("fixing", &1, &1.body)) ++
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
    level =
      cond do
        n.kind in ~w(gate dialog question ask pr_blocked) -> "decision"
        n.kind == "mention" -> "info"
        true -> "sticky"
      end

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
  defp put_away(%{kind: kind, level: level, key: key}) when level == "decide" or kind in ~w(ask stalled quota),
    do: [%{label: put_away_label(kind), method: "POST", path: "/api/office/needs/dismiss", body: %{key: key}}]

  defp put_away(_need), do: []

  # a quota put away stays away until the reset clears it
  defp put_away_label("quota"), do: "Wait for the reset"
  defp put_away_label(_kind), do: "Put away"

  # a review gate has a build behind it, so it can also go back: to build for the code, to plan for its shape
  defp actions(%{kind: "gate", thread_id: t, stage: "review"}),
    do: [read_doc(t), call("Approve", "/approve", t), send_back("build", t), send_back("plan", t), other(t)]

  defp actions(%{kind: "gate", thread_id: t}), do: [read_doc(t), call("Approve", "/approve", t), other(t)]

  # by the prompt's own id, so a key meant for one prompt on a thread never lands in another
  defp actions(%{kind: "dialog", thread_id: t, ref: id, options: options}),
    do: answers("/api/office/prompts/#{id}", options) ++ [other(t)]

  defp actions(%{kind: "ask", ref: id, options: options}),
    do:
      answers("/api/office/asks/#{id}", options) ++
        [%{label: "Hand it to Uqbar", method: "POST", path: "/api/office/prompts/#{id}/uqbar", body: %{}}]

  defp actions(%{kind: k, thread_id: t}) when k in ~w(question mention stalled),
    do: ["Reply…" |> call("/messages", t) |> Map.put(:input, "body")]

  defp actions(%{kind: "verify_failed", thread_id: t}), do: [call("Run verify again", "/verify", t)]

  defp actions(%{kind: "pr_blocked", thread_id: t, url: url}),
    do: [call("Rebase", "/rebase", t), call("Close and reland", "/reland", t), %{label: "Show me", open: url}]

  defp actions(%{kind: "rollout", ref: id}),
    do: [%{label: "Done", method: "DELETE", path: "/api/office/rollout/#{id}", body: nil}]

  # asks why: a resolution naming a PR banks a beat incident's postmortem (`Server.Sheriff.postmortem/1`)
  defp actions(%{kind: "issue", ref: id}),
    do: [
      %{label: "Get it fixed", method: "POST", path: "/api/issues/#{id}/fix", body: %{}},
      %{label: "Resolve…", method: "POST", path: "/api/issues/#{id}/resolve", body: %{}, input: "resolution"}
    ]

  # opened by hand instead (the command is in its body), its PR's url is what GitHub is polled for
  defp actions(%{kind: "publish_failed", thread_id: t}),
    do: [call("Republish", "/republish", t), "Opened by hand…" |> call("/published", t) |> Map.put(:input, "url")]

  defp actions(%{kind: "release_failed", ref: id}),
    do: [%{label: "Retry the cut", method: "POST", path: "/api/release/retry/#{id}", body: %{}}]

  defp actions(%{kind: "no_seat", thread_id: t, workspace_id: ws, archetype: kind}),
    do: [
      %{
        label: "Hire a #{kind}…",
        method: "POST",
        path: "/api/workspaces/#{ws}/coworkers",
        body: %{archetype: kind},
        input: "name"
      },
      "Hand it to…" |> call("/hand-off", t, %{}) |> Map.put(:input, "agent")
    ]

  # pencils down stops the turns that would hit the limit; a crew put on takes the work
  defp actions(%{kind: "quota", workspace_id: ws, options: options}),
    do:
      for(
        o <- options || [],
        do: %{label: o["label"], method: "POST", path: "/api/office/shift", body: %{workspace_id: ws, shift: o["key"]}}
      ) ++ [%{label: "Pencils down", method: "POST", path: "/api/office/pause", body: %{mode: "pencils_down"}}]

  defp actions(%{kind: "stranded", key: key}),
    do: [%{label: "Take the checkout down", method: "POST", path: "/api/office/needs/retire", body: %{key: key}}]

  defp actions(_need), do: []

  defp answers(path, options),
    do: for(o <- options || [], do: %{label: o["label"], method: "POST", path: path, body: %{key: o["key"]}})

  defp call(label, sub, t, body \\ nil),
    do: %{label: label, method: "POST", path: "/api/threads/#{t}#{sub}", body: body}

  # the doc the gate is about, to read before approving it
  defp read_doc(t), do: %{label: "Read it", read: "/api/threads/#{t}/docs/current"}

  defp other(t), do: "Other…" |> call("/messages", t) |> Map.put(:input, "body")

  defp send_back(stage, t), do: "Back to #{stage}…" |> call("/send_back", t, %{stage: stage}) |> Map.put(:input, "why")
end
