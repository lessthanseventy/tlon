defmodule Console.Panel.Brief do
  @moduledoc """
  BRIEF — the focused thread's brief (design §8), a thin view over `Server.Board.brief/1`:
  GOAL, LEAD, TODOS (NEXT marked →), LEARNINGS, UNKNOWNS, BLOCKERS, CHECKS (✓/✗ measured), DONE
  (each capped + a `more` count), RECENT. DONE is the merged view — completed todos + `work_landed`. Re-renders
  on that thread's topic. Data is the `brief/1` map, or `nil` when nothing is focused.
  """
  @behaviour Console.Panel

  import Console.Panel, only: [line: 2, blank: 0]

  alias Server.Bus

  @impl Console.Panel
  def topics(%{focused_id: id}) when not is_nil(id), do: [Bus.thread_topic(id)]
  def topics(_assigns), do: []

  @impl Console.Panel
  def render(nil, rect) do
    Console.Panel.clip([line("select a thread ↑↓", :dim)], rect)
  end

  def render(scope, rect) do
    rows =
      section("GOAL", [scope.goal], rect.w) ++
        lead_section(scope.lead, rect.w) ++
        section("TODOS", capped_lines(scope.todos, &todo_line(&1, scope.next)), rect.w) ++
        section("LEARNINGS", capped_lines(scope.learnings, & &1.text), rect.w) ++
        section("UNKNOWNS", capped_lines(scope.unknowns, &question_line/1), rect.w) ++
        section("BLOCKERS", capped_lines(scope.blockers, & &1.summary), rect.w) ++
        section("CHECKS", capped_lines(scope.checks, &check_line/1), rect.w) ++
        section("DONE", capped_lines(scope.done, &done_line/1), rect.w) ++
        section("RECENT", Enum.map(scope.recent, &recent_line/1), rect.w)

    Console.Panel.clip(rows, rect)
  end

  defp lead_section(nil, w), do: section("LEAD", ["unassigned"], w)
  defp lead_section(name, w), do: section("LEAD", [name], w)

  # A capped section (%{shown, more}, server Board): the cut is always rendered
  # WITH its count — a cut without a count lies.
  defp capped_lines(%{shown: [], more: _}, _fmt), do: []

  defp capped_lines(%{shown: shown, more: more}, fmt) do
    Enum.map(shown, fmt) ++ if(more > 0, do: ["+#{more} more"], else: [])
  end

  # An open question — a known unknown, marked with a "?".
  defp question_line(%{text: text}), do: "? #{text}"

  # A measured check — passed (✓) or failed (✗ with its exit code), keyed on the number.
  defp check_line(%{kind: "check_passed", detail: d}), do: "✓ #{check_cmd(d)}"
  defp check_line(%{detail: d}), do: "✗ #{check_cmd(d)} (exit #{check_exit(d)})"

  defp check_cmd(d) when is_map(d), do: Map.get(d, "cmd") || "check"
  defp check_cmd(_), do: "check"
  defp check_exit(d) when is_map(d), do: Map.get(d, "exit")
  defp check_exit(_), do: "?"

  # NEXT — the first open todo — is marked with an arrow; the rest are plain steps.
  defp todo_line(%{id: id, text: text}, %{id: next_id}) when id == next_id, do: "→ #{text}"
  defp todo_line(%{text: text}, _next), do: "· #{text}"

  # DONE is the merged view: a completed todo (✓) or a work_landed event (its summary).
  defp done_line(%{source: :todo, row: %{text: text}}), do: "✓ #{text}"
  defp done_line(%{source: :event, row: event}), do: event_summary(event)

  defp event_summary(%{detail: detail}) when is_map(detail), do: Map.get(detail, "summary") || "work landed"
  defp event_summary(_event), do: "work landed"

  defp recent_line(%{author: author, body: body}), do: "#{author}: #{body}"

  # A labelled section: the label, its body word-wrapped and bulleted, then a blank spacer.
  # An empty body renders a dim "—" so the shape of the brief stays legible (and honest: the
  # section exists, it is just empty — never an invented value).
  defp section(label, [], w), do: section(label, ["—"], w)

  defp section(label, body, w) do
    body_rows =
      body
      |> Enum.flat_map(&Console.Text.wrap(&1, max(w - 2, 1)))
      |> Enum.map(fn text -> [{"  ", :dim}, {text, :normal}] end)

    [line(label, :label) | body_rows] ++ [blank()]
  end
end
