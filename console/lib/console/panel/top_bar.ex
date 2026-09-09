defmodule Console.Panel.TopBar do
  @moduledoc """
  The frame's top line (UX slice 1): **where am I, what am I on, who is on it, is the server up**.

  One row, justified: the workspace, then the focused thread and its stage on the left; the
  thread's lead with a warmth dot on the right, preceded by an alarm chip when the link to the
  always-up server is down. Data is `%{workspace, thread, stage, cwd, lead, warm?, link}` — every key
  optional but `link`, so a half-assembled frame renders rather than crashing.
  """
  @behaviour Console.Panel

  alias Console.Panel
  alias Server.Bus

  @impl Panel
  def topics(_assigns), do: [Bus.threads_topic(), Bus.sessions_topic()]

  @impl Panel
  def render(data, rect) do
    Panel.clip([row(data, rect.w)], rect)
  end

  # The alarm outranks the thread title (design 2026-09-08 §2): when both sides won't fit, drop the
  # lead, reserve the alarm's width and clip the left into the remainder — "server down" must not be
  # the thing a narrow frame loses. Link up, nothing outranks the left, so the left simply survives.
  defp row(data, w) do
    left = left(data)
    alarm = link_seg(data[:link])
    lead = lead_seg(data[:lead], data[:warm?] == true)

    cond do
      w - Panel.row_width(left) - Panel.row_width(alarm) - Panel.row_width(lead) >= 1 ->
        Panel.justify(left, alarm ++ lead, w)

      alarm == [] ->
        left

      true ->
        Panel.justify(clip_row(left, w - Panel.row_width(alarm) - 1), alarm, w)
    end
  end

  defp clip_row(row, w) when w > 0, do: hd(Panel.clip([row], %{x: 0, y: 0, w: w, h: 1}))
  defp clip_row(_row, _w), do: []

  defp left(data) do
    [{" #{data[:workspace] || "—"} ", :tab}] ++
      thread_seg(data[:thread]) ++ stage_seg(data[:stage]) ++ cwd_seg(data[:cwd])
  end

  # The open thread's worktree, its last two segments (`.worktrees/<name>`) — enough to know which
  # tree the coworker is in, short enough for one row.
  defp cwd_seg(cwd) when is_binary(cwd) and cwd != "" do
    short = cwd |> Path.split() |> Enum.take(-2) |> Path.join()
    [{"  ", :normal}, {short, :dim}]
  end

  defp cwd_seg(_cwd), do: []

  defp thread_seg(thread) when is_binary(thread) and thread != "", do: [{" · ", :dim}, {thread, :normal}]
  defp thread_seg(_thread), do: []

  defp stage_seg(stage) when is_binary(stage) and stage != "", do: [{"  [", :dim}, {stage, :accent}, {"]", :dim}]
  defp stage_seg(_stage), do: []

  defp lead_seg(lead, warm?) when is_binary(lead) and lead != "" do
    dot = Panel.warmth_dot(warm?)
    [dot, {" ", :normal}, {lead, :accent}, {" ", :normal}]
  end

  defp lead_seg(_lead, _warm?), do: []

  defp link_seg(:down), do: [{" server down ", :stat_warn}, {" ", :normal}]
  defp link_seg(_link), do: []
end
