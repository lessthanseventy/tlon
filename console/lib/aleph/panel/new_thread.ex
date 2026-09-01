defmodule Console.Panel.NewThread do
  @moduledoc """
  The persistent **new-thread** input — a band at the bottom of the chat window, above the tertius
  orchestrator line (2026-09-01, Andrew: "each thread gets a reply; the chat window gets one that
  starts a new thread; the orchestrator is at the very bottom" — three input tiers, no keybind).

  Always visible: an idle placeholder invites a title; click (or `n`) focuses it, and its live buffer
  renders with a caret while the `:new_thread` input is active. Enter creates the thread (keymap →
  `{:create_thread, …}`). Data is `%{input: input_map | nil}`. Pure render.
  """
  @behaviour Console.Panel

  @placeholder "‹＋ start a new thread… — click to type›"

  @impl Console.Panel
  def topics(_assigns), do: []

  @prefix "＋ new thread ▸ "
  # The prefix width in cells — the continuation lines indent to align under the caret.
  @indent String.duplicate(" ", String.length(@prefix))

  @impl Console.Panel
  def render(%{input: %{kind: :new_thread, buffer: buffer}}, rect) do
    lines = wrapped_lines(buffer, wrap_width(rect.w))
    last = length(lines) - 1

    lines
    |> Enum.with_index()
    |> Enum.map(fn {line, i} ->
      lead = if i == 0, do: {@prefix, :st_working}, else: {@indent, :normal}
      caret = if i == last, do: [{"▎", :accent}], else: []
      [lead, {line, :normal}] ++ caret
    end)
    |> Console.Panel.clip(rect)
  end

  def render(_data, rect),
    do: Console.Panel.clip([[{"＋ ", :st_working}, {@placeholder, :dim}]], rect)

  @doc "Wrap width for the buffer — the content width minus the prefix. Shared with the height calc."
  def wrap_width(content_w), do: max(content_w - String.length(@prefix), 8)

  @doc "The buffer as display lines: split on hard newlines FIRST, then width-wrap each. Shared so the
  height override and the render agree on the line count."
  def wrapped_lines(buffer, width) do
    (buffer || "")
    |> String.split("\n")
    |> Enum.flat_map(fn hard ->
      case Console.Text.wrap(hard, width) do
        [] -> [""]
        wrapped -> wrapped
      end
    end)
  end
end
