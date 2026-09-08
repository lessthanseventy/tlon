defmodule Console.Panel.Placeholder do
  @moduledoc """
  The right pane's stand-in (UX slice 1): a thread is OPEN but no coworker session is live, so the
  pane that would hold the terminal says so and names the verb that starts one. The frame keeps its
  two panes either way — the conversation doesn't jump back to full width every time a session ends.

  Data is `%{verb: key}`; `Console.View.data_for/2` supplies the key, so the panel never has to know
  which chord spawns.
  """
  @behaviour Console.Panel

  alias Console.Panel

  @impl Panel
  def topics(_assigns), do: []

  @impl Panel
  def render(%{verb: verb}, rect) do
    line = "no live session — #{verb} spawns one"
    pad = String.duplicate(" ", max(div(rect.w - String.length(line), 2), 0))

    Panel.blank()
    |> List.duplicate(max(div(rect.h - 1, 2), 0))
    |> Kernel.++([[{pad <> line, :dim}]])
    |> Panel.clip(rect)
  end

  def render(_data, rect), do: Panel.clip([], rect)
end
