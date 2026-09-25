defmodule Console.Panel.TopBar do
  @moduledoc """
  The frame's top line: **where am I, and what needs me**.

  Left, the workspace as `‹ name ›` — a `!` after it when another workspace has a thread waiting on
  you — then its projects as tabs, the open one inverse, each carrying the loudest badge among its
  threads (`!` waiting, `…` working, `•` unread). Right, the open thread's worktree and its lead
  with a warmth dot, preceded by a `server down` alarm that outranks everything on a narrow frame.
  The open thread's title is the conversation's own header, not repeated here.

  Data is `%{workspace, workspace_id, elsewhere?, projects: [%{id, name, badge}], open_project, cwd, lead,
  warm?, link}` — every key optional but `link`. `hit/2` answers what a click at a column means,
  off the same segments `render/2` draws, so the two cannot disagree.
  """
  @behaviour Console.Panel

  alias Console.Panel
  alias Server.Bus

  @impl Panel
  def topics(_assigns), do: [Bus.threads_topic(), Bus.sessions_topic(), Bus.workspaces_topic()]

  @impl Panel
  def render(data, rect) do
    Panel.clip([row(data, rect.w)], rect)
  end

  @doc """
  What a click at column `x` means: `{:workspace_step, :prev | :next}` on an arrow, `:workspace`
  on the name (its right-click menu), `{:project, id}` on a tab, else nil.
  """
  @spec hit(map(), non_neg_integer(), pos_integer()) ::
          {:workspace_step, :prev | :next} | :workspace | {:project, integer()} | nil
  def hit(data, x, w) do
    data
    |> segments(w)
    |> Enum.reduce_while(0, fn {runs, target}, from ->
      to = from + Panel.row_width(runs)
      if x < to, do: {:halt, {:hit, target}}, else: {:cont, to}
    end)
    |> case do
      {:hit, target} -> target
      _ -> nil
    end
  end

  # The alarm outranks the tabs: when both sides won't fit, drop the right, reserve the alarm's
  # width and clip the left into the remainder — "server down" must not be what a narrow frame loses.
  defp row(data, w) do
    left = data |> segments(w) |> Enum.flat_map(&elem(&1, 0))
    alarm = link_seg(data[:link])
    right = cwd_seg(data[:cwd]) ++ lead_seg(data[:lead], data[:warm?] == true)

    cond do
      w - Panel.row_width(left) - Panel.row_width(alarm) - Panel.row_width(right) >= 1 ->
        Panel.justify(left, alarm ++ right, w)

      alarm == [] ->
        left

      true ->
        Panel.justify(clip_row(left, w - Panel.row_width(alarm) - 1), alarm, w)
    end
  end

  # Every project as a tab while they fit beside the alarm; else the open one and a count of the rest,
  # so a narrow frame can never clip away which project is open.
  defp segments(data, w) do
    projects = data[:projects] || []
    open = data[:open_project]
    full = workspace_segs(data) ++ tab_segs(projects, open)
    budget = w - Panel.row_width(link_seg(data[:link])) - 1

    if Panel.row_width(Enum.flat_map(full, &elem(&1, 0))) <= budget or length(projects) < 2 do
      full
    else
      shown = Enum.filter(projects, &(&1.id == open))
      workspace_segs(data) ++ tab_segs(shown, open) ++ [{[{"  +#{length(projects) - length(shown)}", :dim}], nil}]
    end
  end

  defp workspace_segs(data) do
    elsewhere = if data[:elsewhere?] == true, do: [{[{"!", :st_await}], nil}], else: []

    [
      {[{" ‹ ", :tab}], {:workspace_step, :prev}},
      {[{data[:workspace] || "—", :tab}], :workspace},
      {[{" › ", :tab}], {:workspace_step, :next}}
    ] ++ elsewhere
  end

  defp tab_segs([], _open), do: []

  defp tab_segs(projects, open),
    do: [{[{" ", :normal}], nil} | Enum.flat_map(projects, &[{[{" ", :normal}], nil}, tab(&1, &1.id == open)])]

  defp tab(%{id: id, name: name} = project, open?) do
    style = if open?, do: :selected, else: :normal
    {[{" #{name}", style}] ++ badge(project[:badge], open?) ++ [{" ", style}], {:project, id}}
  end

  defp badge(nil, _open?), do: []
  defp badge({glyph, style}, open?), do: [{" " <> glyph, if(open?, do: :selected_accent, else: style)}]

  defp clip_row(row, w) when w > 0, do: hd(Panel.clip([row], %{x: 0, y: 0, w: w, h: 1}))
  defp clip_row(_row, _w), do: []

  # The open thread's worktree, its last two segments (`.worktrees/<name>`) — enough to know which
  # tree the coworker is in, short enough for one row.
  defp cwd_seg(cwd) when is_binary(cwd) and cwd != "" do
    short = cwd |> Path.split() |> Enum.take(-2) |> Path.join()
    [{short, :dim}, {"  ", :normal}]
  end

  defp cwd_seg(_cwd), do: []

  defp lead_seg(lead, warm?) when is_binary(lead) and lead != "" do
    [Panel.warmth_dot(warm?), {" ", :normal}, {lead, :accent}, {" ", :normal}]
  end

  defp lead_seg(_lead, _warm?), do: []

  defp link_seg(:down), do: [{" server down ", :stat_warn}, {" ", :normal}]
  defp link_seg(_link), do: []
end
