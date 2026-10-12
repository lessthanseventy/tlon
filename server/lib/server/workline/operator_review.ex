defmodule Server.Workline.OperatorReview do
  @moduledoc """
  The operator's review of a workline's branch, from the office: `diff/1` reads what the branch
  changes (`Server.Workline.Artifacts.Git.change/1`, its own `work/<slug>/` docs left out) as files,
  hunks and numbered lines; `submit/6` takes the operator's notes on lines or files and a verdict.

  The notes reach the lead as one post in revdiff's shape, which a model reads without a schema:
  `## path:line (+) note` on an added line, `(-)` on a removed one, nothing on context, and
  `## path note` on a whole file. A verdict is a verb the workline already has: `comment` only
  posts; `changes` is `Workline.send_back/4` to build with the notes as its why (on a workline
  already at build, there is nowhere back to: a comment); `approve` posts any notes, then
  `Workline.approve/2`.
  """

  alias Server.Channel
  alias Server.Workline
  alias Server.Workline.Artifacts.Git

  @verdicts ~w(comment changes approve)

  @doc """
  The branch's change: `%{head, files}`, `head` the branch's commit (nil without a branch), each
  file `%{path, status, added, deleted, binary, hunks}` (`status` added | deleted | renamed |
  modified), each hunk `%{header, lines}`, each line `%{kind, old, new, text}` (`kind` `+`, `-` or
  `" "`; `old`/`new` its line numbers on either side, nil on the side it isn't on). Path order.
  """
  def diff(thread) do
    files = thread |> Git.change() |> Map.fetch!(:diff) |> parse() |> Enum.sort_by(& &1.path)
    %{head: Workline.branch_head(thread), files: files}
  end

  @doc """
  Submit the operator's review: `verdict` comment | changes | approve, a `summary` and `notes`
  (`%{"path", "line"?, "side"? ("+" | "-" | " "), "text"}`; no line is a note on the file). `opts`
  go to `Workline.approve/2`. `{:ok, thread}` | `{:error, :unknown_verdict | :nothing_to_say}` |
  the verb's own error.
  """
  def submit(thread, author, verdict, summary, notes, opts \\ [])

  def submit(_thread, _author, verdict, _summary, _notes, _opts) when verdict not in @verdicts,
    do: {:error, :unknown_verdict}

  def submit(thread, author, verdict, summary, notes, opts) do
    said = said(summary, notes)

    cond do
      said == "" and verdict != "approve" -> {:error, :nothing_to_say}
      verdict == "approve" -> with :ok <- post(thread, author, said, "approved"), do: Workline.approve(thread, opts)
      verdict == "changes" and thread.stage not in [nil, "build"] -> Workline.send_back(thread, "build", said, author)
      true -> with :ok <- post(thread, author, said, "comments"), do: {:ok, thread}
    end
  end

  defp said(summary, notes) do
    [String.trim(summary || "") | Enum.map(notes, &note/1)] |> Enum.reject(&(&1 == "")) |> Enum.join("\n\n")
  end

  defp note(%{"path" => path, "line" => line, "text" => text} = n) when is_integer(line),
    do: "## #{path}:#{line}#{side(n["side"])} #{String.trim(text)}"

  defp note(%{"path" => path, "text" => text}), do: "## #{path} #{String.trim(text)}"

  defp side("+"), do: " (+)"
  defp side("-"), do: " (-)"
  defp side(_), do: ""

  defp post(_thread, _author, "", _how), do: :ok

  defp post(thread, author, said, how) do
    to = Channel.thread_lead(thread.id)
    head = Workline.branch_head(thread)
    at = if head, do: " at #{String.slice(head, 0, 7)}", else: ""

    with {:ok, _} <-
           Channel.post(%{
             thread_id: thread.id,
             author: author,
             body: "#{if to, do: "@#{to} "}review#{at} — #{how}\n\n#{said}"
           }),
         do: :ok
  end

  # `git diff`'s unified output, file by file
  defp parse(text) do
    text
    |> String.split(~r/^diff --git /m, trim: true)
    |> Enum.flat_map(fn chunk -> chunk |> String.split("\n") |> file() end)
  end

  defp file([header | lines]) do
    {meta, body} = Enum.split_while(lines, &(not String.starts_with?(&1, "@@")))
    path = path(header, meta)

    status =
      cond do
        Enum.any?(meta, &String.starts_with?(&1, "new file")) -> "added"
        Enum.any?(meta, &String.starts_with?(&1, "deleted file")) -> "deleted"
        Enum.any?(meta, &String.starts_with?(&1, "rename from")) -> "renamed"
        true -> "modified"
      end

    hunks = hunks(body)
    counted = Enum.flat_map(hunks, & &1.lines)

    [
      %{
        path: path,
        status: status,
        binary: Enum.any?(meta, &String.starts_with?(&1, "Binary files")),
        added: Enum.count(counted, &(&1.kind == "+")),
        deleted: Enum.count(counted, &(&1.kind == "-")),
        hunks: hunks
      }
    ]
  end

  defp file(_), do: []

  # the new side's path (`+++ b/…`), else the old one's for a deletion, else the header's
  defp path(header, meta) do
    Enum.find_value(meta, fn
      "+++ b/" <> p -> p
      _ -> nil
    end) ||
      Enum.find_value(meta, fn
        "--- a/" <> p -> p
        _ -> nil
      end) ||
      header |> String.split(" b/", parts: 2) |> List.last() |> String.trim()
  end

  defp hunks(lines) do
    lines
    |> Enum.chunk_while(
      nil,
      fn
        "@@" <> _ = line, nil -> {:cont, start(line)}
        "@@" <> _ = line, hunk -> {:cont, finish(hunk), start(line)}
        _line, nil -> {:cont, nil}
        line, hunk -> {:cont, add(hunk, line)}
      end,
      fn
        nil -> {:cont, nil}
        hunk -> {:cont, finish(hunk), nil}
      end
    )
    |> Enum.reject(&is_nil/1)
  end

  defp start(line) do
    [_, old, new] = Regex.run(~r/^@@ -(\d+)(?:,\d+)? \+(\d+)/, line)
    %{header: line, lines: [], old: String.to_integer(old), new: String.to_integer(new)}
  end

  defp add(hunk, "+" <> text),
    do: %{hunk | lines: [%{kind: "+", old: nil, new: hunk.new, text: text} | hunk.lines], new: hunk.new + 1}

  defp add(hunk, "-" <> text),
    do: %{hunk | lines: [%{kind: "-", old: hunk.old, new: nil, text: text} | hunk.lines], old: hunk.old + 1}

  defp add(hunk, " " <> text),
    do: %{
      hunk
      | lines: [%{kind: " ", old: hunk.old, new: hunk.new, text: text} | hunk.lines],
        old: hunk.old + 1,
        new: hunk.new + 1
    }

  # `\ No newline at end of file`, and the empty string a trailing newline leaves
  defp add(hunk, _), do: hunk

  defp finish(hunk), do: %{header: hunk.header, lines: Enum.reverse(hunk.lines)}
end
