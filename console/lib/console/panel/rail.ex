defmodule Console.Panel.Rail do
  @moduledoc """
  The always-on left rail (UX slice 1, design 2026-09-08 §2; channels slice 1b): **workspaces as
  a short list, under the active one its channels, and under the OPEN channel its threads** (grouped
  under a heading per project once they span more than one) —
  Slack's sidebar with warmth. It replaces both the icon spine
  and the funes rail; the situational panes it displaced live in the drawer.

  A thread row is `warmth dot · title · at most ONE badge`, the badge by priority
  **waiting on you (`!`) > unread (`•`) > working (`…`)** — a row never carries two claims on your
  attention. The ACTIVE workspace and the OPEN thread render inverse (the palette's "this is the
  live one"); the nav cursor is an accent title, so "where I am" and "where the cursor is" never
  collide.

  Data is `%{groups, active_key, open_channel, opened}` — `groups` is `Server.Board.sidebar/0`'s
  read (`%{workspace: %{id, name}, channels: [%{id, name, kind, threads: [%{id, title, awaiting,
  working, …}]}]}`) enriched per thread by `Console.Reads` with `warm?`, plus `selected` (the nav
  cursor) injected by the View. `open_channel` nil means the workspace's #general. A closed
  channel's row carries its threads' one badge, so attention never hides behind a fold. `unread?`
  is honoured here and set once messages carry read state (design §4 lists it as a schema gap).
  """
  @behaviour Console.Panel

  import Console.Panel, only: [line: 2, pad: 3]

  alias Console.Panel
  alias Server.Bus

  @impl Panel
  def topics(_assigns), do: [Bus.threads_topic(), Bus.sessions_topic(), Bus.workspaces_topic()]

  @impl Panel
  def render(%{groups: [_ | _]} = data, rect) do
    rows =
      data
      |> entries()
      |> Enum.with_index()
      |> Enum.map(fn {entry, i} -> row(entry, face(entry, data, i), rect.w) end)

    Panel.clip(rows, rect)
  end

  def render(_data, rect), do: Panel.clip([line("no workspaces — is server up?", :dim)], rect)

  # Click → the entry under `local_y`, off the same list render walks. A thread opens its
  # conversation, a workspace switches to it — the verbs the Cockpit already dispatches.
  @impl Panel
  def pick(%{groups: _} = data, _rect, local_y) do
    data
    |> entries()
    |> Enum.at(Panel.scroll_offset(data) + local_y)
    |> case do
      {:thread, %{id: id}} -> {:open_thread_view, id}
      {:channel, %{id: id}} -> {:open_channel, id}
      {:workspace, %{id: id}} -> {:switch_space, id}
      _ -> nil
    end
  end

  def pick(_data, _rect, _local_y), do: nil

  @impl Panel
  def hints(_data), do: [{"j/k", "row"}, {"⏎", "open"}, {"m", "move"}, {"#", "channel"}, {"d", "delete"}]

  @doc "The entry under `local_y` (the right-click context menu's target), or nil."
  @spec entry_at(map(), Panel.rect(), non_neg_integer()) :: {:workspace | :channel | :project | :thread, map()} | nil
  def entry_at(%{groups: _} = data, _rect, local_y),
    do: data |> entries() |> Enum.at(Panel.scroll_offset(data) + local_y)

  def entry_at(_data, _rect, _local_y), do: nil

  @doc "The rail's rows as data: every workspace; the ACTIVE one's channels; the OPEN channel's threads, under a heading per project once they span more than one."
  @spec entries(map()) :: [{:workspace, map()} | {:channel, map()} | {:project, map()} | {:thread, map()}]
  def entries(%{groups: groups} = data) do
    Enum.flat_map(groups, fn group ->
      workspace = group.workspace
      channels = if workspace.id == data[:active_key], do: group[:channels] || [], else: []
      open = open_channel_id(channels, data[:open_channel])

      [
        {:workspace, workspace}
        | Enum.flat_map(channels, fn channel ->
            threads = if channel.id == open, do: channel[:threads] || [], else: []
            [{:channel, channel} | by_project(threads, group[:projects] || [])]
          end)
      ]
    end)
  end

  def entries(_data), do: []

  # Threads under a heading per project, in the workspace's project order, once more than one
  # project has threads here. Newest-first order holds within a project; a project with no thread
  # in the channel gets no heading. Threads on a project the read doesn't know trail at the end.
  defp by_project(threads, projects) do
    groups = Enum.group_by(threads, & &1[:project_id])

    if map_size(groups) < 2 do
      Enum.map(threads, &{:thread, &1})
    else
      known = for p <- projects, rows = groups[p.id], rows != nil, do: [{:project, p} | Enum.map(rows, &{:thread, &1})]
      ids = MapSet.new(projects, & &1.id)
      stray = for t <- threads, not MapSet.member?(ids, t[:project_id]), do: {:thread, t}
      List.flatten(known) ++ stray
    end
  end

  @doc "The id of the open channel among `channels`: the chosen one if it is still there, else #general."
  @spec open_channel_id([map()], integer() | nil) :: integer() | nil
  def open_channel_id(channels, chosen) do
    cond do
      Enum.any?(channels, &(&1.id == chosen)) -> chosen
      general = Enum.find(channels, &(&1[:kind] == "general")) -> general.id
      true -> nil
    end
  end

  # :active = the workspace you're in / the thread that's open (inverse video); :cursor = where j/k
  # sits; :idle = everything else.
  defp face({:workspace, %{id: id}}, data, i), do: face(id == data[:active_key], i == data[:selected])
  defp face({:channel, %{id: id}}, data, i), do: face(id == open_id(data), i == data[:selected])
  defp face({:thread, %{id: id}}, data, i), do: face(id == data[:opened], i == data[:selected])
  defp face({:project, _project}, data, i), do: face(false, i == data[:selected])

  defp open_id(data) do
    case Enum.find(data.groups, &(&1.workspace.id == data[:active_key])) do
      %{channels: channels} -> open_channel_id(channels, data[:open_channel])
      _ -> nil
    end
  end

  defp face(true = _active?, _cursor?), do: :active
  defp face(false, true = _cursor?), do: :cursor
  defp face(false, false), do: :idle

  defp row({:workspace, workspace}, face, w) do
    name = clip(workspace[:name] || "?", max(w - 1, 1))

    pad([{" ", fill(face)}, {name, workspace_style(face)}], w, fill(face))
  end

  # `#name`, and — folded — the strongest badge among its threads (the same priority as a thread's).
  defp row({:channel, channel}, face, w) do
    badge = channel[:threads] |> List.wrap() |> Enum.map(&badge(&1, face)) |> Enum.min_by(&badge_rank/1, fn -> [] end)
    lead = [{" ", fill(face)}, {"#", channel_style(face)}]
    name = clip(channel[:name] || "?", max(w - Panel.row_width(lead) - width(badge), 1))
    runs = lead ++ [{name, channel_style(face)}]
    gap = max(w - Panel.row_width(runs) - width(badge), 0)

    runs ++ [{String.duplicate(" ", gap), fill(face)}] ++ badge
  end

  # a heading, not a destination: the project's name under the channel, above its threads
  defp row({:project, project}, face, w) do
    name = clip(project[:name] || "?", max(w - 2, 1))
    pad([{"  ", fill(face)}, {name, project_style(face)}], w, fill(face))
  end

  defp row({:thread, thread}, face, w) do
    badge = badge(thread, face)
    # The badge is the row's point — reserve its width and clip the TITLE, never the badge.
    lead = [{"  ", fill(face)}, dot(thread, face), {" ", fill(face)}]
    title = clip(thread[:title] || "", max(w - Panel.row_width(lead) - width(badge), 1))
    runs = lead ++ [{title, title_style(face)}]
    gap = max(w - Panel.row_width(runs) - width(badge), 0)

    runs ++ [{String.duplicate(" ", gap), fill(face)}] ++ badge
  end

  # One badge, by priority: waiting on you, then unread, then working.
  defp badge(thread, face) do
    cond do
      # a coworker waiting on a dialog (Server.Attention) is "awaiting you" exactly like a parked gate
      is_map(thread[:prompt]) -> [{"!", badge_style(face, :st_await)}]
      is_binary(thread[:awaiting]) and thread[:awaiting] != "" -> [{"!", badge_style(face, :st_await)}]
      thread[:unread?] == true -> [{"•", badge_style(face, :accent)}]
      thread[:working] == true -> [{"…", badge_style(face, :st_working)}]
      true -> []
    end
  end

  # a channel folds to its threads' strongest badge — lower is louder
  defp badge_rank([{"!", _}]), do: 0
  defp badge_rank([{"•", _}]), do: 1
  defp badge_rank([{"…", _}]), do: 2
  defp badge_rank([]), do: 3

  # The face only STYLES the dot; the glyph follows warmth alone (Panel.warmth_dot/1), so an
  # open-but-cold thread can never read warm here while the top bar reads it cold.
  defp dot(thread, face) do
    {glyph, style} = Panel.warmth_dot(thread[:warm?] == true)
    {glyph, dot_style(face, style)}
  end

  defp dot_style(:active, _style), do: :selected
  defp dot_style(_face, style), do: style

  # An inverse row is inverse all the way across, so its runs take the selection's own styles.
  defp badge_style(:active, _style), do: :selected_accent
  defp badge_style(_face, style), do: style

  defp channel_style(:active), do: :selected
  defp channel_style(:cursor), do: :accent
  defp channel_style(:idle), do: :header

  defp project_style(:cursor), do: :accent
  defp project_style(_face), do: :dim

  defp workspace_style(:active), do: :selected
  defp workspace_style(:cursor), do: :accent
  defp workspace_style(:idle), do: :header

  defp title_style(:active), do: :selected
  defp title_style(:cursor), do: :accent
  defp title_style(:idle), do: :normal

  defp fill(:active), do: :selected
  defp fill(_face), do: :normal

  defp width(runs), do: Panel.row_width(runs)

  defp clip(text, w), do: String.slice(text, 0, w)
end
