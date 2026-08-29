defmodule Console.Panel.Conversation do
  @moduledoc """
  CHAT — the slack-style conversation on a thread (the coordination spine, funes `Channel`).
  This is not a tmux session: agents and the human posting to a thread *is* the chat, already
  durable in funes. Serves double duty — the compact left "CHATTER" box and the full-screen
  chat view (Tab) — the only difference is the rect it's handed. Re-renders on the thread topic.

  Data is `%{title: String.t() | nil, messages: [%Server.Message{}]}`, optionally with
  `thinking`/`working` (the focused thread's presence) rendered as a trailing indicator —
  thinking counts as working, so the explicit declare (accent) outranks the tmux-activity
  inference (dim). `thinking` is `[{agent, elapsed_s}]` — `⋯ <agent> is thinking… (3m12s)` —
  so a long single turn visibly counts up instead of sitting on a static word that reads as
  frozen (funes thread #3); `working` stays a bare name list (no start timestamp to show).

  A message carrying `attachment: %{w, h}` renders `Console.Graphics.placeholder/2` after its
  body (design 2026-08-23 §Images) — the seam's proof, not a feature. Server doesn't emit
  attachments yet; real thumbnails (`images/2` on this panel + the funes write-path) land with
  the coming Spaces work.
  """
  @behaviour Console.Panel

  import Console.Panel, only: [line: 2, blank: 0]

  alias Server.Bus

  @impl Console.Panel
  def topics(%{focused_id: id}) when not is_nil(id), do: [Bus.thread_topic(id)]
  def topics(_assigns), do: []

  @impl Console.Panel
  def render(%{messages: messages} = data, rect) do
    header = [line(head_label(data[:title]), :header), blank()]

    body =
      case messages do
        [] ->
          [line("no messages yet", :dim)]

        ms ->
          ms
          |> Enum.map(&message_rows(&1, rect.w))
          |> Enum.reject(&(&1 == []))
          |> Enum.intersperse([blank()])
          |> Enum.concat()
      end

    Console.Panel.clip(header ++ body ++ presence_rows(data), rect)
  end

  defp presence_rows(data) do
    rows =
      Enum.map(data[:thinking] || [], &thinking_row/1) ++
        Enum.map(data[:working] || [], &line("⋯ #{&1} is working…", :dim))

    case rows do
      [] -> []
      rows -> [blank() | rows]
    end
  end

  # `elapsed_s` (now - the declare's started_at) is the trust signal (funes thread #3): a
  # coworker stuck on "thinking" through a long single turn must visibly count up, not sit on
  # a static word that reads as frozen.
  defp thinking_row({agent, elapsed_s}),
    do: line("⋯ #{agent} is thinking… (#{Console.Text.duration(elapsed_s)})", :accent)

  defp head_label(nil), do: "CHAT"
  defp head_label(title), do: "CHAT · #{title}"

  # "author: body", paragraph-aware wrap with a hanging indent so the author stays legible;
  # blank lines in the body render as paragraph breaks instead of collapsing. The operator's
  # messages render whole in :operator pink; agents keep amber author / green body.
  defp message_rows(%{author: author, body: body} = msg, w) do
    prefix = "#{author}: "
    body_style = if Server.Channel.operator?(author), do: :operator, else: :normal

    rows =
      case Console.Text.wrap_paragraphs(prefix <> body, max(w, 1)) do
        [] -> []
        [first | rest] -> [author_run(first, author, body_style) | Enum.map(rest, &continuation(&1, body_style))]
      end

    rows ++ attachment_row(Map.get(msg, :attachment))
  end

  defp attachment_row(%{w: w, h: h}), do: [Console.Graphics.placeholder(w, h)]
  defp attachment_row(_attachment), do: []

  defp continuation("", _style), do: blank()
  defp continuation(text, style), do: line("  " <> text, style)

  # Colour the author name on the first wrapped line; the rest of that line is body text.
  defp author_run(first_line, author, body_style) do
    author_style = if body_style == :operator, do: :operator, else: :label

    case String.split(first_line, ": ", parts: 2) do
      [^author, tail] -> [{author, author_style}, {": ", :dim}, {tail, body_style}]
      _ -> [{first_line, body_style}]
    end
  end
end
