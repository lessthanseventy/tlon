defmodule Console.Panel.Rail do
  @moduledoc """
  The always-on left rail: the OPEN PROJECT's threads in the active workspace, as one flat list
  ranked by what needs you — waiting on you (`!`, a prompt or a parked gate), then working (`…`),
  then unread (`•`), then the rest newest first. The workspace's lobby is listed in every project.
  Workspace and project are chosen in the top bar, not here.

  Each thread is TWO rows: `▌! title`, then `○ lead · state` (the state is what it waits on, or
  that it is working, or how long ago it last moved). Only the OPEN thread renders inverse; the nav
  cursor is the `▌` gutter plus an accent title, so it stays visible on the open row too.

  Data is `%{groups, active_key, open_project, opened}` — `groups` is `Server.Board.sidebar/0`'s
  read (`%{workspace, projects: [%{id, name}], threads: [row]}`), each row enriched by
  `Console.Reads` with `warm?` — plus `selected` (the cursor, an entry index) and `scroll` (in
  rows) injected by the View, and `now` for the age (defaults to the clock).
  """
  @behaviour Console.Panel

  alias Console.Panel
  alias Server.Bus

  @rows_per_entry 2

  @impl Panel
  def topics(_assigns), do: [Bus.threads_topic(), Bus.sessions_topic(), Bus.workspaces_topic()]

  @impl Panel
  def render(%{groups: [_ | _]} = data, rect) do
    case entries(data) do
      [] ->
        Panel.clip([Panel.line(" no open threads here — n starts one", :dim)], rect)

      entries ->
        now = data[:now] || DateTime.utc_now()

        entries
        |> Enum.with_index()
        |> Enum.flat_map(fn {{:thread, thread}, i} -> rows(thread, face(thread, data, i), now, rect.w) end)
        |> Panel.clip(rect)
    end
  end

  def render(_data, rect), do: Panel.clip([Panel.line(" no workspaces — is server up?", :dim)], rect)

  @impl Panel
  def pick(data, rect, local_y) do
    case entry_at(data, rect, local_y) do
      {:thread, %{id: id}} -> {:open_thread_view, id}
      _ -> nil
    end
  end

  @impl Panel
  def hints(_data), do: [{"j/k", "thread"}, {"⏎", "open"}, {"[ ]", "project"}, {"m", "move"}, {"d", "delete"}]

  @doc "The entry under `local_y` (a click, the right-click menu's target), or nil."
  @spec entry_at(map(), Panel.rect(), non_neg_integer()) :: {:thread, map()} | nil
  def entry_at(%{groups: _} = data, _rect, local_y),
    do: data |> entries() |> Enum.at(div(Panel.scroll_offset(data) + local_y, @rows_per_entry))

  def entry_at(_data, _rect, _local_y), do: nil

  @doc "The screen row, from the rail's top, where entry `index` starts — how a cursor becomes rows."
  @spec row_of(non_neg_integer()) :: non_neg_integer()
  def row_of(index), do: index * @rows_per_entry

  @doc "The rail's entries: the active workspace's lobby and the open project's threads, most urgent first."
  @spec entries(map()) :: [{:thread, map()}]
  def entries(%{groups: groups} = data) do
    case Enum.find(groups, &(&1.workspace.id == data[:active_key])) do
      nil ->
        []

      group ->
        project = open_project_id(group[:projects] || [], data[:open_project])

        (group[:threads] || [])
        |> Enum.filter(&(&1[:root] == true or is_nil(project) or &1[:project_id] == project))
        |> Enum.sort_by(&{attention(&1), if(&1[:root] == true, do: 0, else: 1)})
        |> Enum.map(&{:thread, &1})
    end
  end

  def entries(_data), do: []

  @doc "The id of the open project among `projects`: the chosen one if it is still there, else the first."
  @spec open_project_id([map()], integer() | nil) :: integer() | nil
  def open_project_id(projects, chosen) do
    if Enum.any?(projects, &(&1.id == chosen)), do: chosen, else: projects |> List.first(%{}) |> Map.get(:id)
  end

  @doc "How loudly a thread claims the operator: 0 waiting on you, 1 working, 2 unread, 3 quiet."
  @spec attention(map()) :: 0..3
  def attention(thread) do
    cond do
      waiting?(thread) -> 0
      thread[:working] == true -> 1
      thread[:unread?] == true -> 2
      true -> 3
    end
  end

  @doc "The badge for an attention rank — `{glyph, style}`, nil for a quiet thread. The top bar's tabs use it too."
  @spec glyph(0..3) :: {String.t(), atom()} | nil
  def glyph(0), do: {"!", :st_await}
  def glyph(1), do: {"…", :st_working}
  def glyph(2), do: {"•", :accent}
  def glyph(3), do: nil

  defp waiting?(thread), do: is_map(thread[:prompt]) or (is_binary(thread[:awaiting]) and thread[:awaiting] != "")

  # :active = the open thread (inverse); :cursor = where j/k sits; :both = the cursor ON the open
  # thread (inverse, and the gutter still marks it); :idle = the rest.
  defp face(%{id: id}, data, i) do
    case {id == data[:opened], i == data[:selected]} do
      {true, true} -> :both
      {true, false} -> :active
      {false, true} -> :cursor
      {false, false} -> :idle
    end
  end

  defp rows(thread, face, now, w) do
    gutter = if face in [:cursor, :both], do: {"▌", gutter_style(face)}, else: {" ", fill(face)}
    badge = badge(thread, face)
    title = clip(thread[:title] || "", max(w - 3, 1))
    {dot, dot_style} = Panel.warmth_dot(thread[:warm?] == true)
    meta = clip("#{thread[:lead] || "no lead"} · #{state(thread, now)}", max(w - 5, 1))

    [
      Panel.pad([gutter, badge, {" ", fill(face)}, {title, title_style(face)}], w, fill(face)),
      Panel.pad(
        [gutter, {"  ", fill(face)}, {dot, meta_style(face, dot_style)}, {" " <> meta, meta_style(face, :dim)}],
        w,
        fill(face)
      )
    ]
  end

  defp badge(thread, face) do
    case glyph(attention(thread)) do
      nil -> {" ", fill(face)}
      {glyph, style} -> {glyph, badge_style(face, style)}
    end
  end

  defp state(%{prompt: %{summary: summary}}, _now) when is_binary(summary), do: "waiting: #{summary}"

  defp state(thread, now) do
    cond do
      waiting?(thread) -> "waiting on you"
      thread[:working] == true -> "working"
      true -> age(thread[:last_at], now)
    end
  end

  @doc false
  def age(%DateTime{} = at, %DateTime{} = now) do
    s = max(DateTime.diff(now, at), 0)

    cond do
      s < 60 -> "just now"
      s < 3600 -> "#{div(s, 60)}m"
      s < 86_400 -> "#{div(s, 3600)}h"
      s < 1_209_600 -> "#{div(s, 86_400)}d"
      true -> "#{div(s, 604_800)}w"
    end
  end

  def age(_at, _now), do: ""

  defp fill(face) when face in [:active, :both], do: :selected
  defp fill(_face), do: :normal

  defp gutter_style(:both), do: :selected_accent
  defp gutter_style(_face), do: :accent

  defp title_style(face) when face in [:active, :both], do: :selected
  defp title_style(:cursor), do: :accent
  defp title_style(:idle), do: :normal

  defp meta_style(face, _style) when face in [:active, :both], do: :selected
  defp meta_style(_face, style), do: style

  defp badge_style(face, _style) when face in [:active, :both], do: :selected_accent
  defp badge_style(_face, style), do: style

  defp clip(text, w), do: String.slice(text, 0, w)
end
