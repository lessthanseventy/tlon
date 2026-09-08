defmodule Console.Panel.Triage do
  @moduledoc """
  TRIAGE — the cross-thread view of what needs attention RIGHT NOW: open blockers across
  all threads, failed checks, and unassigned threads. A thin view over the server Board;
  re-renders on threads and sessions topics (any thread's state may have changed).

  Where DOSSIER shows one thread's brief in depth, TRIAGE shows ALL threads' trouble spots
  at a glance — the "what's on fire" summary the operator sees without focusing a thread.

  Data is `%{blockers, failed_checks, unassigned}` where blockers/failed_checks are
  `%{shown: [...], more: count}` (capped at 5 with a more count), and unassigned is a plain list.
  """
  @behaviour Console.Panel

  import Console.Panel, only: [line: 2]

  alias Server.Bus

  @impl Console.Panel
  def topics(_assigns), do: [Bus.threads_topic(), Bus.sessions_topic()]

  @impl Console.Panel
  def render(nil, rect) do
    Console.Panel.clip([line("triage has not been read yet", :dim)], rect)
  end

  @impl Console.Panel
  def render(data, rect), do: Console.Panel.clip(triage_rows(data, rect.w), rect)

  defp triage_rows(%{blockers: %{shown: []}, failed_checks: %{shown: []}, unassigned: []}, _w) do
    [line("all clear", :dim)]
  end

  defp triage_rows(data, w) do
    blockers_section(data.blockers, w) ++
      checks_section(data.failed_checks, w) ++
      unassigned_section(data.unassigned, w)
  end

  defp blockers_section(%{shown: []}, _w), do: []

  defp blockers_section(%{shown: items} = data, w) do
    rows = Enum.map(items, &blocker_row(&1, w))
    [line("BLOCKERS", :label) | rows] ++ more_line(data)
  end

  defp checks_section(%{shown: []}, _w), do: []

  defp checks_section(%{shown: items} = data, w) do
    rows = Enum.map(items, &check_row(&1, w))
    [line("FAILED CHECKS", :label) | rows] ++ more_line(data)
  end

  defp unassigned_section([], _w), do: []

  defp unassigned_section(threads, w) do
    items = Enum.map(threads, &unassigned_row(&1, w))
    [line("UNASSIGNED", :label) | items]
  end

  defp blocker_row(%{thread_title: title, summary: summary}, _w) do
    [{"✗ ", :label}, {title, :accent}, {": ", :dim}, {summary, :normal}]
  end

  defp check_row(%{thread_title: title, cmd: cmd}, _w) do
    [{"✗ ", :label}, {title, :accent}, {": ", :dim}, {cmd, :normal}]
  end

  defp unassigned_row(%{title: title}, _w) do
    [{"○ ", :dim}, {title, :normal}]
  end

  defp more_line(%{shown: _shown, more: more}) when more > 0, do: [line("+#{more} more", :dim)]
  defp more_line(_), do: []
end
