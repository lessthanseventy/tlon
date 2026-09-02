defmodule Console.Presence do
  @moduledoc """
  Liveness/typing signals for the chat surfaces (general console + cockpit), derived purely from a tmux window
  snapshot — `[%{name, thread_id, activity}]` where `activity` is the window's
  `\#{window_activity}` unix timestamp (last content change). A harness that is thinking/typing
  repaints its pane, so recent activity is the "coworker is working…" indicator; a live-but-quiet
  window is a warm seat; no window is a cold one. Pure (now is an argument) so it tests headless.
  """

  # Content changed within this window = "working" (the typing indicator). Wide enough to ride
  # out paint gaps between tool calls, tight enough that an idle TUI goes quiet fast.
  @working_s 10

  @type window :: %{name: String.t(), thread_id: integer() | nil, activity: integer() | nil}
  @type status :: :working | :live | :none

  @doc "The leaf status for a thread: its tagged (or legacy `t<id>`) window, judged by activity."
  @spec thread_status([window()], integer(), integer()) :: status()
  def thread_status(windows, thread_id, now_s) do
    windows
    |> Enum.find(&(&1.thread_id == thread_id or &1.name == "t#{thread_id}"))
    |> status(now_s)
  end

  @doc "A standing coworker's status by its window name (roster window = the coworker's name)."
  @spec coworker_status([window()], String.t(), integer()) :: status()
  def coworker_status(windows, name, now_s) do
    windows |> Enum.find(&(&1.name == name)) |> status(now_s)
  end

  @doc """
  Where a coworker is working right now: the busiest of its standing window and any leaf it
  leads — `{status, thread_id | nil}` (nil = the standing window). `led` is the thread ids this
  coworker leads.
  """
  @spec coworker_seat([window()], String.t(), [integer()], integer()) :: {status(), integer() | nil}
  def coworker_seat(windows, name, led, now_s) do
    seats =
      [{coworker_status(windows, name, now_s), nil}] ++
        Enum.map(led, fn tid -> {thread_status(windows, tid, now_s), tid} end)

    Enum.max_by(seats, fn {status, _tid} -> rank(status) end)
  end

  defp status(nil, _now_s), do: :none
  defp status(%{activity: activity}, now_s) when is_integer(activity) and now_s - activity <= @working_s, do: :working
  defp status(%{}, _now_s), do: :live

  defp rank(:working), do: 2
  defp rank(:live), do: 1
  defp rank(:none), do: 0

  @doc """
  A thinking declaration's `started_at` as UNIX SECONDS — the one seam where server time
  (idiomatic DateTimes, on the Bus event and in `thinking_all/0`) becomes cockpit time
  (the integers `Crew.seat`/`presence_read` subtract). The live 2026-08-28 crash was this
  conversion missing: `now_s - ~U[...]` is an ArithmeticError, and every fixture had been
  fabricating integers, so no test could see it.
  """
  @spec started_s(DateTime.t() | integer()) :: integer()
  def started_s(%DateTime{} = at), do: DateTime.to_unix(at)
  def started_s(seconds) when is_integer(seconds), do: seconds
end
