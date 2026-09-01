defmodule Console.Panel.Activity do
  @moduledoc """
  The machine-wide server activity feed (Tlön right sidebar): every durable write — a fact
  banked, a check passed/failed, work landed, a message posted, an issue/question raised —
  as one colored, newest-first stream (design: replace the opaque "server · calling server (2
  tools)" with real visibility). Fed by `Server.Bus`'s global `activity` topic (cross-thread,
  unlike `Overview`'s per-thread blocks); the Cockpit keeps the bounded buffer, this panel is a
  pure render over it.

  Data is `%{events: [{tag, row}, ...]}`, newest-first (the Cockpit's buffer order).
  `summarize/1` — the `{tag, row} -> {icon, style, text}` mapping — is exported so the footer
  pulse (status bar) reuses it verbatim rather than re-deriving it (no panel/footer drift).
  """
  @behaviour Console.Panel

  import Console.Panel, only: [line: 2]

  # The cockpit subscribes to the activity topic once (Bus.subscribe_activity), globally — no
  # per-assigns topic needed here (mirrors Overview, which does the same for messages).
  @impl Console.Panel
  def topics(_assigns), do: []

  @impl Console.Panel
  def render(data, rect) do
    # Gates lead — the parked worklines awaiting the operator (Slice 4D ATTENTION), a standing list
    # above the ambient feed. `gates` is optional so the plain `%{events: …}` shape still renders.
    Console.Panel.clip(gate_section(data[:gates] || []) ++ event_body(data[:events] || []), rect)
  end

  defp event_body([]), do: [line("no activity yet", :dim)]
  defp event_body(evs), do: Enum.map(evs, &event_row/1)

  defp gate_section([]), do: []

  defp gate_section(gates) do
    [line("⏸ AWAITING YOU", :event_warn)] ++ Enum.map(gates, &gate_row/1) ++ [line("", :dim)]
  end

  defp gate_row(%{id: id, title: title, stage: stage}) do
    [{"  ⏸ ", :event_warn}, {"##{id} #{title} — #{stage} · approve #{id}", :event_warn}]
  end

  defp event_row(event) do
    {icon, style, text} = summarize(event)
    [{icon, style}, {text, style}]
  end

  @doc """
  Map one buffered `{tag, row}` Bus event to `{icon, style, summary text}` — the single source
  both this panel and the footer pulse render from. The summary is flattened to a single line
  (agent-authored text can carry a literal newline that would render as a raw control byte).
  """
  @spec summarize({atom(), map()}) :: {String.t(), atom(), String.t()}
  def summarize(event) do
    {icon, style, text} = classify(event)
    {icon, style, flatten(text)}
  end

  defp classify({:fact_banked, fact}), do: {"● ", :event_ok, "fact ##{fact.id} #{fact.kind} — #{fact.text}"}

  defp classify({:event_recorded, %{kind: "check_passed"} = ev}), do: {"✓ ", :event_ok, check_text(ev)}
  defp classify({:event_recorded, %{kind: "check_failed"} = ev}), do: {"✗ ", :event_bad, check_text(ev)}
  defp classify({:event_recorded, %{kind: "work_landed"} = ev}), do: {"⚑ ", :event_done, work_text(ev)}
  defp classify({:event_recorded, ev}), do: {"· ", :event_msg, ev.kind}

  defp classify({:message_posted, m}), do: {"▸ ", :event_msg, "#{m.author}: #{m.body}"}

  defp classify({:issue_raised, row}), do: {"◆ ", :event_warn, "issue: #{row.summary}"}
  defp classify({:question_raised, row}), do: {"◆ ", :event_warn, "question: #{row.text}"}

  # Anything else that rides the activity topic (issue_resolved, question_resolved, todo_*…) —
  # a plain row rather than a silent drop, so the feed never hides a real write.
  defp classify({tag, _row}), do: {"· ", :event_msg, to_string(tag)}

  # Collapse any run of whitespace (incl. embedded newlines) to a single space, so the summary
  # stays one clean line — the panel keeps one row per event and the footer stays compact.
  defp flatten(text), do: text |> to_string() |> String.replace(~r/\s+/, " ") |> String.trim()

  defp check_text(%{detail: detail}) do
    d = detail || %{}
    cmd = d["cmd"] || "check"
    if d["exit"], do: "#{cmd} — exit #{d["exit"]}", else: cmd
  end

  defp work_text(%{detail: detail}) do
    d = detail || %{}
    d["summary"] || "work landed"
  end
end
