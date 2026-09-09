defmodule Console.Panel.Reply do
  @moduledoc """
  The persistent **per-thread reply** input — the band at the bottom of an OPENED conversation, in
  place of the new-thread band (2026-09-01, Andrew: tier-1 of the three input tiers, "each thread
  gets a reply"; opening a thread focuses this directly, no `c` verb).

  Unlike `Console.Panel.NewThread`, there's no idle face: the box is born focused with the open
  thread, so it always renders the live buffer + `▎` caret. Enter posts and keeps it focused (buffer
  cleared); Esc steps back to the thread list. Data is `%{input: %{kind: :reply, thread_id, buffer}}`.
  Pure render — the `Console.Text.wrap` height math is shared with `Console.View`'s band override.
  """
  @behaviour Console.Panel

  @impl Console.Panel
  def topics(_assigns), do: []

  @prefix_base "↳ reply to #"

  @impl Console.Panel
  def render(%{input: %{kind: :reply, thread_id: id, buffer: buffer}}, rect) do
    prefix = "#{@prefix_base}#{id} ▸ "
    indent = String.duplicate(" ", String.length(prefix))
    lines = wrapped_lines(buffer, wrap_width(rect.w, id))
    last = length(lines) - 1

    lines
    |> Enum.with_index()
    |> Enum.map(fn {line, i} ->
      lead = if i == 0, do: {prefix, :accent}, else: {indent, :normal}
      caret = if i == last, do: [{"▎", :accent}], else: []
      [lead, {line, :normal}] ++ caret
    end)
    |> Console.Panel.clip(rect)
  end

  # No live reply input (a stale nil between close and the next open) — render nothing, not a stray
  # placeholder; the band is only placed while a thread is open.
  def render(_data, rect), do: Console.Panel.clip([], rect)

  @doc "Wrap width for the buffer — content width minus the (id-dependent) prefix. Shared with the height calc."
  def wrap_width(content_w, id), do: max(content_w - String.length("#{@prefix_base}#{id} ▸ "), 8)

  @doc "The buffer as display lines: hard newlines first, then width-wrap each. Shared so the height
  override and the render agree on the line count."
  def wrapped_lines(buffer, width) do
    (buffer || "")
    |> String.split("\n")
    |> Enum.flat_map(fn hard ->
      Console.Text.wrap_exact(hard, width)
    end)
  end
end
