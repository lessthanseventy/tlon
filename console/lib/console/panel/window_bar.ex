defmodule Console.Panel.WindowBar do
  @moduledoc """
  The top band framing the Tlön center: console's own window strip — tmux's status bar is off, so
  this is the only window chrome — moved OUT of the terminal into a standalone bordered panel (the
  terminal renders edge-to-edge now). Left: each tmux window as a tab, a presence dot for its live
  agent, the active window highlighted. Right: the Claude-engine clock state + the focused thread.

  Data is `%{tabs: [%{name, active?, index, agent, warm?}], engine: :on | :off, thread: id | nil}`
  — tabs pre-joined to roster presence by `Console.View.data_for/2` (window → agent handle via
  `Console.Mention.coworkers/0`, warmth via `Server.Staff.roster/0`), so this panel stays a pure
  render with no server reads of its own.
  """
  @behaviour Console.Panel

  import Console.Panel, only: [row_width: 1]

  @impl Console.Panel
  def topics(_assigns), do: []

  @impl Console.Panel
  def render(%{tabs: tabs, engine: engine, thread: thread}, rect) do
    left = Enum.map(tabs, &tab_run/1)
    right = engine_run(engine) ++ [{"  ", :normal}, {"##{thread || "—"}", :dim}]

    Console.Panel.clip([justify(left, right, rect.w)], rect)
  end

  defp tab_run(t), do: {tab_label(t), if(t[:active?], do: :selected, else: :dim)}

  defp tab_label(t), do: " #{presence(t)} #{tab_name(t)} "

  defp presence(%{warm?: true}), do: "●"
  defp presence(_t), do: "○"

  defp tab_name(%{agent: agent, name: name}) when is_binary(agent), do: "#{name}·#{agent}"
  defp tab_name(%{name: name}), do: name

  defp engine_run(:on), do: [{"⚡ claude", :header}]
  defp engine_run(_off), do: [{"⚡ claude", :dim}]

  @doc """
  Hit-test the window strip a click landed on: the tab whose ` name ` segment contains column `x`
  (0-based within the panel), or nil past the last tab. Shares `tab_label/1` with `render/2` so the
  clickable regions can't drift from what's drawn — mirrors the terminal's old `tab_at_x/2`, moved
  here with the strip itself.
  """
  @spec tab_at_x([map()], non_neg_integer()) :: map() | nil
  def tab_at_x(tabs, x) do
    tabs
    |> Enum.reduce_while(0, fn t, start ->
      next = start + String.length(tab_label(t))
      if x >= start and x < next, do: {:halt, t}, else: {:cont, next}
    end)
    |> case do
      %{} = tab -> tab
      _ -> nil
    end
  end

  # Left-align the tabs, right-align engine+thread, fill the middle to exactly `w`. Too narrow for
  # both: keep the tabs (clip/2 trims them) — window switching matters more than the readout.
  defp justify(left, right, w) do
    gap = w - row_width(left) - row_width(right)
    if gap >= 1, do: left ++ [{String.duplicate(" ", gap), :normal}] ++ right, else: left
  end
end
