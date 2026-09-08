defmodule Console.Panel.TopBar do
  @moduledoc """
  The frame's top line (UX slice 1): **where am I, what am I on, who is on it, is the server up**.

  One row, justified: the workspace, then the focused thread and its stage on the left; the
  thread's lead with a warmth dot on the right, preceded by an alarm chip when the link to the
  always-up server is down. Data is `%{workspace, thread, stage, lead, warm?, link}` — every key
  optional but `link`, so a half-assembled frame renders rather than crashing.
  """
  @behaviour Console.Panel

  alias Console.Panel
  alias Server.Bus

  @impl Panel
  def topics(_assigns), do: [Bus.threads_topic(), Bus.sessions_topic()]

  @impl Panel
  def render(data, rect) do
    Panel.clip([Panel.justify(left(data), right(data), rect.w)], rect)
  end

  defp left(data) do
    [{" ", :normal}, {data[:workspace] || "—", :tab}] ++ thread_seg(data[:thread]) ++ stage_seg(data[:stage])
  end

  defp thread_seg(thread) when is_binary(thread) and thread != "", do: [{" · ", :dim}, {thread, :normal}]
  defp thread_seg(_thread), do: []

  defp stage_seg(stage) when is_binary(stage) and stage != "", do: [{"  [", :dim}, {stage, :accent}, {"]", :dim}]
  defp stage_seg(_stage), do: []

  defp right(data), do: link_seg(data[:link]) ++ lead_seg(data[:lead], data[:warm?] == true)

  # ● warm / ○ cold — the same pair Panel.Roster uses for a session's warmth.
  defp lead_seg(lead, warm?) when is_binary(lead) and lead != "" do
    dot = if warm?, do: {"●", :warm}, else: {"○", :dim}
    [dot, {" ", :normal}, {lead, :accent}, {" ", :normal}]
  end

  defp lead_seg(_lead, _warm?), do: []

  defp link_seg(:down), do: [{" server down ", :stat_warn}, {" ", :normal}]
  defp link_seg(_link), do: []
end
