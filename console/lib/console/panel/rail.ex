defmodule Console.Panel.Rail do
  @moduledoc """
  The always-on left rail (UX slice 1, design 2026-09-08 §2): **workspaces as a short list, and
  under the active one its threads** — Slack's sidebar with warmth. It replaces both the icon spine
  and the funes rail; the situational panes it displaced live in the drawer.

  A thread row is `warmth dot · title · at most ONE badge`, the badge by priority
  **waiting on you (`!`) > unread (`•`) > working (`…`)** — a row never carries two claims on your
  attention. The ACTIVE workspace and the OPEN thread render inverse (the palette's "this is the
  live one"); the nav cursor is an accent title, so "where I am" and "where the cursor is" never
  collide.

  Data is `%{groups, active_key, opened}` — `groups` is `Server.Board.sidebar/0`'s read
  (`%{workspace: %{id, name}, threads: [%{id, title, awaiting, working, …}]}`) enriched per thread
  by `Console.Reads` with `warm?`, plus `selected` (the nav cursor) injected by the View. `unread?`
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
    case data |> entries() |> Enum.at(Panel.scroll_offset(data) + local_y) do
      {:thread, %{id: id}} -> {:open_thread_view, id}
      {:workspace, %{id: id}} -> {:switch_space, id}
      _ -> nil
    end
  end

  def pick(_data, _rect, _local_y), do: nil

  @impl Panel
  def hints(_data), do: [{"j/k", "row"}, {"⏎", "open"}, {"[ ]", "space"}]

  @doc "The workspace under `local_y` (the right-click context menu's target), or nil."
  @spec workspace_at(map(), Panel.rect(), non_neg_integer()) :: map() | nil
  def workspace_at(%{groups: _} = data, _rect, local_y) do
    case data |> entries() |> Enum.at(Panel.scroll_offset(data) + local_y) do
      {:workspace, workspace} -> workspace
      _ -> nil
    end
  end

  def workspace_at(_data, _rect, _local_y), do: nil

  @doc "The rail's rows as data: every workspace, and the ACTIVE workspace's threads under it."
  @spec entries(map()) :: [{:workspace, map()} | {:thread, map()}]
  def entries(%{groups: groups} = data) do
    Enum.flat_map(groups, fn group ->
      workspace = group.workspace
      threads = if workspace.id == data[:active_key], do: group[:threads] || [], else: []

      [{:workspace, workspace} | Enum.map(threads, &{:thread, &1})]
    end)
  end

  def entries(_data), do: []

  # :active = the workspace you're in / the thread that's open (inverse video); :cursor = where j/k
  # sits; :idle = everything else.
  defp face({:workspace, %{id: id}}, data, i), do: face(id == data[:active_key], i == data[:selected])
  defp face({:thread, %{id: id}}, data, i), do: face(id == data[:opened], i == data[:selected])

  defp face(true = _active?, _cursor?), do: :active
  defp face(false, true = _cursor?), do: :cursor
  defp face(false, false), do: :idle

  defp row({:workspace, workspace}, face, w) do
    name = clip(workspace[:name] || "?", max(w - 1, 1))

    pad([{" ", fill(face)}, {name, workspace_style(face)}], w, fill(face))
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
      is_binary(thread[:awaiting]) and thread[:awaiting] != "" -> [{"!", badge_style(face, :st_await)}]
      thread[:unread?] == true -> [{"•", badge_style(face, :accent)}]
      thread[:working] == true -> [{"…", badge_style(face, :st_working)}]
      true -> []
    end
  end

  # ● warm / ○ cold — the pair Panel.Roster and the top bar use. The face only STYLES the dot;
  # the glyph follows warmth alone, so an open-but-cold thread can never read warm here while
  # the top bar reads it cold.
  defp dot(%{warm?: true}, face), do: {"●", dot_style(face, :warm)}
  defp dot(_thread, face), do: {"○", dot_style(face, :dim)}

  defp dot_style(:active, _style), do: :selected
  defp dot_style(_face, style), do: style

  # An inverse row is inverse all the way across, so its runs take the selection's own styles.
  defp badge_style(:active, _style), do: :selected_accent
  defp badge_style(_face, style), do: style

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
