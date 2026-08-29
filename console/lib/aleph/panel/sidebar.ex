defmodule Console.Panel.Sidebar do
  @moduledoc """
  The Slack-shaped left sidebar (reshape slice D) — replaces the SPACES picker. **Home** (the
  Orbis god-view, the collapsed state) leads; then one group per workspace: its header (the
  space nav — `Enter`/click switches, exactly what SPACES rows did), its unified thread list
  (`⋯` working, stage chip, `⏸` awaiting; the root thread renders as the workspace's `#`
  channel), and its crew with presence (`●` working / `○` idle).

  Pure over `Server.Board.sidebar/0`'s read: data is `%{groups, active_key}`, plus `selected`
  (the nav cursor over the PICKABLE rows — Home then each workspace header, the same order
  `key_at/2` resolves) injected only while this pane holds the focus, and `:scroll` via the View.
  """
  @behaviour Console.Panel

  import Console.Panel, only: [line: 2, blank: 0, pad: 3]

  alias Server.Bus

  @impl Console.Panel
  def topics(_assigns), do: [Bus.threads_topic(), Bus.sessions_topic()]

  @impl Console.Panel
  def render(%{groups: groups, active_key: active_key} = data, rect) do
    cursor = data[:selected]

    body =
      data
      |> rows_of()
      |> Enum.map(&row(&1, active_key, cursor, rect.w))

    note = if groups == [], do: [line("no workspaces — is funes up?", :dim)], else: []

    Console.Panel.clip(body ++ note, rect)
  end

  def render(_data, rect), do: Console.Panel.clip([line("no workspaces — is funes up?", :dim)], rect)

  # Click → the row under local_y, same list render walked. Workspace headers (and Home) switch
  # the space; a thread row focuses its thread; crew rows and spacers are inert.
  @impl Console.Panel
  def pick(%{groups: _} = data, _rect, local_y) do
    case data |> rows_of() |> Enum.at(local_y) do
      {:home, _i} -> {:switch_space, :orbis}
      {:workspace, %{id: id}, _i} -> {:switch_space, id}
      {:thread, %{id: id}} -> {:focus_thread, id}
      _ -> nil
    end
  end

  def pick(_data, _rect, _local_y), do: nil

  @doc """
  The space key under nav-cursor `index` — pickables in render order: 0 = Home (`:orbis`),
  then each workspace's id. The cockpit's Enter-to-switch resolves through this, so the
  cursor can never switch to a different space than the row the paint marked.
  """
  def key_at(_data, 0), do: :orbis

  def key_at(%{groups: groups}, index) when is_integer(index) and index > 0,
    do: with(%{workspace: %{id: id}} <- Enum.at(groups, index - 1), do: id)

  def key_at(_data, _index), do: nil

  @doc "How many pickable rows (Home + workspace headers) — what j/k clamps against."
  def pickable_count(%{groups: groups}), do: 1 + length(groups)
  def pickable_count(_data), do: 1

  # The one row list render/pick share: Home, then per group a header, its threads, its crew,
  # and a spacer. Pickables carry their cursor index (Home 0, workspace i).
  defp rows_of(%{groups: groups}) do
    [{:home, 0}] ++
      (groups
       |> Enum.with_index(1)
       |> Enum.flat_map(fn {group, i} ->
         [{:workspace, group.workspace, i}] ++
           Enum.map(group.threads, &{:thread, &1}) ++
           Enum.map(group.crew, &{:crew, &1}) ++
           [{:spacer}]
       end))
  end

  defp row({:home, i}, active_key, cursor, w), do: pickable_row("Home", active_key == :orbis, cursor == i, w)

  defp row({:workspace, %{id: id, name: name}, i}, active_key, cursor, w),
    do: pickable_row(name, active_key == id, cursor == i, w)

  defp row({:thread, thread}, _active_key, _cursor, _w) do
    {glyph, style} = thread_glyph(thread)
    [{"  ", :dim}, {glyph, style}, {thread.title || "untitled", :normal}] ++ thread_chips(thread)
  end

  defp row({:crew, member}, _active_key, _cursor, _w) do
    if member.working,
      do: [{"  ● ", :accent}, {member.name, :normal}],
      else: [{"  ○ ", :dim}, {member.name, :dim}]
  end

  defp row({:spacer}, _active_key, _cursor, _w), do: blank()

  # The active space: the solid ▸ highlight (SPACES' idiom). The nav cursor: an accent →
  # marking where Enter would switch. Both can hold at once (cursor parked on the active row).
  defp pickable_row(label, true = _active?, _cursor?, w),
    do: pad([{"▸ ", :selected_accent}, {label, :selected_accent}], w, :selected)

  defp pickable_row(label, false, true = _cursor?, _w), do: [{"→ ", :accent}, {label, :accent}]
  defp pickable_row(label, false, false, _w), do: [{"  ", :dim}, {label, :normal}]

  # The root thread is the workspace's channel (`#`); a working thread ticks `⋯`; the rest sit
  # behind a quiet `·`.
  defp thread_glyph(%{root: true}), do: {"# ", :accent}
  defp thread_glyph(%{working: true}), do: {"⋯ ", :warm}
  defp thread_glyph(_thread), do: {"· ", :dim}

  defp thread_chips(thread) do
    chip = if stage = thread[:stage], do: [{" ▸ #{stage}", :accent}], else: []
    gate = if thread[:awaiting], do: [{" ⏸", :label}], else: []
    chip ++ gate
  end

  @impl Console.Panel
  def hints(_data), do: [{"j/k", "workspaces"}, {"⏎", "switch"}]
end
