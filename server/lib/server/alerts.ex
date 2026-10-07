defmodule Server.Alerts do
  @moduledoc """
  What the desktop should raise, and how loudly — the needs queue (`Server.Office.Needs`) and the
  calendar's meetings (`Server.Calendar`) as one list, served at `GET /api/alerts`:

    * **alarm** — a meeting from `alarm_minutes` (settings file, default 5) before it starts until
      ten minutes in: full screen, with Join;
    * **decision** — work has stopped on a choice (a gate, a dialog, a question): a banner with
      its answers;
    * **sticky** — wants the operator, nothing waits on it (a red verify, a mention, a
      suggestion, a rollout note): stays until dismissed or resolved.

  Each alert is `%{key, level, kind, title, body, at, thread_id, link, actions}`; an action is a
  call on the operator API (`method`, `path`, `body`, and `input` naming the body field a typed
  answer fills) or a link to `open`, so a surface acts on any alert the same way. Alarms first,
  then decisions, then sticky; snoozing and dismissing are the surface's.
  """

  @alarm_minutes 5
  @alarm_after_s 600

  @doc "Every alert now."
  def list do
    now = DateTime.utc_now()
    minutes = Server.OperatorConfig.read()["alarm_minutes"] || @alarm_minutes
    window = {DateTime.add(now, -@alarm_after_s), DateTime.add(now, minutes * 60)}
    build(Server.Office.Needs.list(), Server.Calendar.upcoming(window), now, alarm_minutes: minutes)
  end

  @doc "The alerts for these needs and meetings at `now` — `list/0` without the reads."
  def build(needs, meetings, now, opts \\ []) do
    lead = Keyword.get(opts, :alarm_minutes, @alarm_minutes) * 60

    alarms =
      for m <- meetings,
          DateTime.diff(m.start, now) <= lead,
          DateTime.diff(now, m.start) <= @alarm_after_s,
          do: alarm(m)

    from_needs = Enum.map(needs, &from_need/1)

    Enum.sort_by(alarms, & &1.at, DateTime) ++
      Enum.filter(from_needs, &(&1.level == "decision")) ++ Enum.filter(from_needs, &(&1.level == "sticky"))
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
    level = if n.kind in ~w(gate dialog question), do: "decision", else: "sticky"

    %{
      key: n.key,
      level: level,
      kind: n.kind,
      title: n.title,
      body: n.text,
      at: n.at,
      thread_id: n.thread_id,
      link: nil,
      actions: actions(n)
    }
  end

  defp actions(%{kind: "gate", thread_id: t}), do: [read_doc(t), call("Approve", "/approve", t), other(t)]

  defp actions(%{kind: "dialog", thread_id: t, options: options}),
    do: Enum.map(options || [], &call(&1["label"], "/messages", t, %{body: &1["key"]})) ++ [other(t)]

  defp actions(%{kind: k, thread_id: t}) when k in ~w(question mention),
    do: ["Reply…" |> call("/messages", t) |> Map.put(:input, "body")]

  defp actions(%{kind: "verify_failed", thread_id: t}), do: [call("Run verify again", "/verify", t)]

  defp actions(%{kind: "rollout", ref: id}),
    do: [%{label: "Done", method: "DELETE", path: "/api/office/rollout/#{id}", body: nil}]

  defp actions(_need), do: []

  defp call(label, sub, t, body \\ nil),
    do: %{label: label, method: "POST", path: "/api/threads/#{t}#{sub}", body: body}

  # the doc the gate is about, to read before approving it
  defp read_doc(t), do: %{label: "Read it", read: "/api/threads/#{t}/docs/current"}

  defp other(t), do: "Other…" |> call("/messages", t) |> Map.put(:input, "body")
end
