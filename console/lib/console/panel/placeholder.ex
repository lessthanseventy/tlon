defmodule Console.Panel.Placeholder do
  @moduledoc """
  The right pane's stand-in (UX slice 1): a thread is OPEN but no coworker session is live, so the
  pane that would hold the terminal says so. The frame keeps its two panes either way — the
  conversation doesn't jump back to full width every time a session ends.

  `copy/0` is the ONE empty-state line: `Console.Panel.Terminal`'s own `:no_session` face renders
  through this module, so the two can't drift. It names no verb — nothing spawns a coworker on
  demand (`s` is `:section_next`, `Enter` opens a row), the frame attaches one when it is live.
  """
  @behaviour Console.Panel

  alias Console.Panel

  @copy "no terminal attached — the lead's session opens here"

  @doc "The empty state's one line — shared with `Console.Panel.Terminal`'s `:no_session` face."
  @spec copy() :: String.t()
  def copy, do: @copy

  @impl Panel
  def topics(_assigns), do: []

  @impl Panel
  def render(nil, rect), do: Panel.clip([], rect)

  def render(_data, rect) do
    line = @copy
    pad = String.duplicate(" ", max(div(rect.w - String.length(line), 2), 0))

    Panel.blank()
    |> List.duplicate(max(div(rect.h - 1, 2), 0))
    |> Kernel.++([[{pad <> line, :dim}]])
    |> Panel.clip(rect)
  end
end
