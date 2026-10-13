defmodule Server.Usage do
  @moduledoc """
  The Claude plan's limits, the office's meter: the five-hour and weekly windows as the last session
  on the plan saw them (the mod's `session.measure` hook posts them, `POST /api/usage/claude`, when a
  window moves a whole point). Each window is `%{percent, resets_at}`; `at` is when the newest report
  came, so a surface can say how old the reading is. In memory, like presence: a restart starts with
  no reading (`claude/0` is nil) until the next turn on the plan reports.
  """
  use Agent

  @windows %{"five_hour" => :five_hour, "seven_day" => :seven_day}

  def start_link(_opts), do: Agent.start_link(fn -> nil end, name: __MODULE__)

  @doc "The newest reading, `%{five_hour?, seven_day?, at}`, or nil when none has come."
  def claude, do: Agent.get(__MODULE__, & &1)

  @doc """
  Take a report: `%{"five_hour" => %{"percent" => n, "resets_at" => iso | nil}, "seven_day" => …}`,
  either window alone. A window the report leaves out keeps its last figure. `:ok`, or
  `{:error, why}` for anything else, which changes nothing.
  """
  def report(%{} = body) do
    windows = for {k, v} <- body, Map.has_key?(@windows, k), into: %{}, do: {@windows[k], window(v)}

    cond do
      windows == %{} ->
        {:error, "expected five_hour and/or seven_day"}

      Enum.any?(windows, fn {_, w} -> w == :error end) ->
        {:error, "a window is %{percent: number, resets_at: iso8601 | null}"}

      true ->
        Agent.update(__MODULE__, &Map.merge(&1 || %{}, Map.put(windows, :at, DateTime.utc_now())))
    end
  end

  @doc false
  def clear, do: Agent.update(__MODULE__, fn _ -> nil end)

  defp window(%{"percent" => p} = w) when is_number(p) do
    case w["resets_at"] do
      r when is_binary(r) or is_nil(r) -> %{percent: p, resets_at: r}
      _ -> :error
    end
  end

  defp window(_), do: :error
end
