defmodule Console.Panel.Stack do
  @moduledoc """
  STACK — the machine's own changelog for the Tlön space: the current branch with tracking
  status, working-tree summary, recent `ficciones` commits (newest first), and the files that
  have been moving lately. Health (services, system metrics, tools) lives in the HEALTH panel
  next door.

  Data is `%{branch, dirty, ahead, behind, status_summary, commits: [%{hash, subject, relative,
  date, author, agent?}], files: [path]}`. Three labeled sections (BRANCH, COMMITS, FILES),
  each separated by a `Panel.rule/1` divider so the eye has somewhere to land in a panel this
  dense — bare blank-line spacing reads as one long undifferentiated column.

  Each commit prints on two rows — the full subject first, then `hash  author  relative (date)`
  indented below — so the subject (what changed) reads first and the attribution is secondary,
  glanceable context rather than the lead. `author` is padded to a fixed column so the relative
  time lines up down the list instead of ragging on name length. `author` is the
  `Co-Authored-By` model when the commit has one (pink, `agent? == true`) rather than the
  human's git identity every dogfood commit is pushed under — a plain human commit (no trailer)
  shows the git author instead, in label amber.
  """
  @behaviour Console.Panel

  import Console.Panel, only: [line: 2, rule: 1]

  # Author column width: enough for "Claude Opus 4.8" (a full model name) without ragging the
  # relative-time column too far right on a narrow panel.
  @author_col 16

  @impl Console.Panel
  def topics(_assigns), do: []

  @impl Console.Panel
  def render(
        %{branch: branch, dirty: dirty, ahead: ahead, behind: behind, status_summary: summary, commits: commits} = data,
        rect
      ) do
    divider = [rule(rect.w)]

    branch_section =
      [line("BRANCH", :label), branch_row(branch, dirty, ahead, behind)] ++ status_rows(summary)

    selected = Map.get(data, :selected)

    commits_section =
      [line("COMMITS", :label)] ++
        case commits do
          [] -> [line("  no git history", :dim)]
          cs -> cs |> Enum.with_index() |> Enum.flat_map(fn {c, i} -> commit_row(c, i == selected) end)
        end

    files_section =
      case Map.get(data, :files, []) do
        [] -> []
        files -> divider ++ [line("FILES", :label)] ++ Enum.map(files, &file_row/1)
      end

    rows = branch_section ++ divider ++ commits_section ++ files_section

    Console.Panel.clip(rows, rect)
  end

  defp status_rows(nil), do: []
  defp status_rows(s) when s.staged == 0 and s.unstaged == 0 and s.untracked == 0, do: []
  defp status_rows(s), do: [status_row(s)]

  defp branch_row(nil, _dirty, _ahead, _behind), do: [{"  no branch", :dim}]

  defp branch_row(branch, dirty, ahead, behind) do
    tracking = tracking_suffix(ahead, behind)
    dirty_mark = if dirty, do: [{" ✗", :label}], else: []
    [{"  ", :dim}, {branch, :label}] ++ tracking ++ dirty_mark
  end

  defp tracking_suffix(nil, nil), do: []

  defp tracking_suffix(ahead, behind) do
    parts =
      []
      |> then(fn ps -> if ahead && ahead > 0, do: [{" ↑", :warm}, {Integer.to_string(ahead), :normal} | ps], else: ps end)
      |> then(fn ps ->
        if behind && behind > 0, do: [{" ↓", :label}, {Integer.to_string(behind), :normal} | ps], else: ps
      end)

    if parts == [], do: [], else: [{" ", :dim} | parts]
  end

  defp status_row(summary) do
    parts =
      []
      |> then(fn ps -> if summary.staged > 0, do: [{"+" <> Integer.to_string(summary.staged), :warm} | ps], else: ps end)
      |> then(fn ps ->
        if summary.unstaged > 0, do: [{"~" <> Integer.to_string(summary.unstaged), :normal} | ps], else: ps
      end)
      |> then(fn ps ->
        if summary.untracked > 0, do: [{"?" <> Integer.to_string(summary.untracked), :dim} | ps], else: ps
      end)

    joined = Enum.intersperse(parts, {" ", :dim})
    [{"  ", :dim} | joined]
  end

  # The selected commit (j/k cursor) gets a ▸ gutter and the :selected wash on its subject, so the
  # eye lands on which Enter would open; unselected rows keep the two-space gutter.
  defp commit_row(
         %{hash: hash, subject: subject, relative: relative, date: date, author: author, agent?: agent?},
         selected?
       ) do
    author_style = if agent?, do: :accent, else: :label
    {gutter, subject_style} = if selected?, do: {"▸ ", :selected}, else: {"  ", :normal}

    meta = [
      {"  " <> hash <> "  ", :dim},
      {String.pad_trailing(author, @author_col), author_style},
      {relative, :dim},
      {" (" <> date <> ")", :dim}
    ]

    [[{gutter <> subject, subject_style}], meta]
  end

  defp file_row(path), do: [{"  ", :dim}, {path, :normal}]

  @impl Console.Panel
  def hints(_data), do: [{"j/k", "commits"}, {"⏎", "lazygit"}, {"y", "sha"}]

  @doc "The semantic yank for the cursor row: the full sha."
  def yank(%{commits: commits}, cursor) do
    case Enum.at(commits, cursor) do
      %{hash: hash} -> {"sha #{hash}", hash}
      _ -> nil
    end
  end

  def yank(_data, _cursor), do: nil
end
