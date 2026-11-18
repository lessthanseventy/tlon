defmodule Server.Home.Clock do
  @moduledoc """
  The home's times are the operator's wall clock: read and said in the machine's own zone, kept in
  UTC. The zone is the OS's, with its rules for the instant asked about.
  """

  @doc "The local wall-clock time of the UTC instant `utc`."
  @spec local(DateTime.t()) :: NaiveDateTime.t()
  def local(%DateTime{} = utc) do
    utc
    |> DateTime.to_naive()
    |> NaiveDateTime.to_erl()
    |> :calendar.universal_time_to_local_time()
    |> NaiveDateTime.from_erl!()
  end

  @doc """
  The UTC instant of the local wall-clock time `local`: an hour that happens twice (clocks back) is
  its first, one that never happens (clocks forward) is the hour after.
  """
  @spec utc(NaiveDateTime.t()) :: DateTime.t()
  def utc(%NaiveDateTime{} = local) do
    case :calendar.local_time_to_universal_time_dst(NaiveDateTime.to_erl(local)) do
      [utc | _] -> utc |> NaiveDateTime.from_erl!() |> DateTime.from_naive!("Etc/UTC")
      [] -> utc(NaiveDateTime.add(local, 3600))
    end
  end

  @doc """
  A repeat as it is kept: `"day"`, `"week"` or `"month"` (every one), or a number then one of them
  (`"6 week"`, `"3 month"`; up to 99). Plurals and `"1 week"` are read; nil when it is none of those.
  """
  @spec every(term()) :: String.t() | nil
  def every(value) when is_binary(value) do
    with [_, n, unit] <- Regex.run(~r/^(?:(\d+)\s+)?(day|week|month)s?$/, String.trim(value)),
         n when n in 1..99 <- if(n == "", do: 1, else: String.to_integer(n)) do
      if n == 1, do: unit, else: "#{n} #{unit}"
    else
      _ -> nil
    end
  end

  def every(_value), do: nil

  @doc "A repeat as the helper says it: `week`, `6 weeks`."
  @spec say_every(String.t()) :: String.t()
  def say_every(every) do
    case String.split(every) do
      [_unit] -> every
      [_n, _unit] -> every <> "s"
    end
  end

  @doc """
  The occurrence of a time that repeats `every` (`every/1`) after `utc`, at the same wall-clock time.
  A month's `anchor` is the day of the month it started on, kept where the month has it and clamped
  where it does not (nil: the day `utc` is on), so Jan 31, Feb 28, Mar 31 does not drift.
  """
  @spec step(DateTime.t(), String.t(), pos_integer() | nil) :: DateTime.t()
  def step(%DateTime{} = utc, every, anchor \\ nil) do
    local = local(utc)

    utc(
      case parse(every) do
        {n, "day"} -> NaiveDateTime.shift(local, day: n)
        {n, "week"} -> NaiveDateTime.shift(local, week: n)
        {n, "month"} -> month(local, n, anchor)
      end
    )
  end

  @doc "The first occurrence of `utc` repeating `every` that is after `now`."
  @spec next(DateTime.t(), String.t(), DateTime.t(), pos_integer() | nil) :: DateTime.t()
  def next(%DateTime{} = utc, every, now, anchor \\ nil) do
    stepped = step(utc, every, anchor)
    if DateTime.after?(stepped, now), do: stepped, else: next(stepped, every, now, anchor)
  end

  @doc "The last occurrence of `utc` repeating `every` that is not after `now`: `utc` itself when its next one is."
  @spec latest(DateTime.t(), String.t(), DateTime.t(), pos_integer() | nil) :: DateTime.t()
  def latest(%DateTime{} = utc, every, now, anchor \\ nil) do
    stepped = step(utc, every, anchor)
    if DateTime.after?(stepped, now), do: utc, else: latest(stepped, every, now, anchor)
  end

  @doc "Whether the operator is up at `utc`: not between 22:00 and 08:00 local, when nothing unasked is said."
  @spec awake?(DateTime.t()) :: boolean()
  def awake?(%DateTime{} = utc), do: local(utc).hour in 8..21

  @doc """
  The date of the newest slot not after `now`: a slot is a day (or, with a weekday `on` as `"sun"`, that
  weekday) at `at` (`"17:30"`, local). nil when there is no such time (`at` or `on` is empty or not
  one).
  """
  @spec slot(DateTime.t(), String.t(), String.t() | nil) :: Date.t() | nil
  def slot(%DateTime{} = now, at, on \\ nil) do
    case Time.from_iso8601(at <> ":00") do
      {:ok, time} ->
        local = local(now)
        today = NaiveDateTime.to_date(local)
        newest = if Time.compare(NaiveDateTime.to_time(local), time) == :lt, do: Date.add(today, -1), else: today
        on_day(newest, on)

      _never ->
        nil
    end
  end

  @doc """
  What to do with a slot that comes round (the daily list, the weekly review): `{:say, slot}` when the
  newest slot (`slot/3`) is newer than `last`, the date of the last slot said, and the operator is up
  at `now`; the slot is then what is recorded. `:wait` otherwise, so a slot that went by asleep, or
  with the node down, is said at the first waking moment after it, once.
  """
  @spec due(Date.t(), DateTime.t(), String.t(), String.t() | nil) :: {:say, Date.t()} | :wait
  def due(%Date{} = last, %DateTime{} = now, at, on \\ nil) do
    case slot(now, at, on) do
      %Date{} = slot -> if Date.after?(slot, last) and awake?(now), do: {:say, slot}, else: :wait
      nil -> :wait
    end
  end

  @doc """
  The last slot said from what was kept (`{date, setting}`, `Server.Home.Slot`) when `setting` is
  what is set now; `:boot` (count the newest slot as said, say nothing) when nothing was kept or it
  was kept under another setting, so a change never fires a slot from before it.
  """
  @spec resume({Date.t() | :boot, String.t()} | nil, String.t()) :: Date.t() | :boot
  def resume({last, setting}, setting), do: last
  def resume(_kept, _setting), do: :boot

  @doc "A UTC instant as the helper says it: `Fri 20 Nov 09:00`, local."
  @spec say(DateTime.t()) :: String.t()
  def say(%DateTime{} = utc), do: Calendar.strftime(local(utc), "%a %-d %b %H:%M")

  defp on_day(date, nil), do: date

  defp on_day(date, on), do: Enum.find(for(back <- 0..6, do: Date.add(date, -back)), &(day_name(&1) == on))

  defp day_name(date), do: date |> Calendar.strftime("%a") |> String.downcase()

  defp parse(every) do
    case String.split(every) do
      [unit] -> {1, unit}
      [n, unit] -> {String.to_integer(n), unit}
    end
  end

  defp month(local, n, anchor) do
    date = local |> NaiveDateTime.to_date() |> Date.shift(month: n)
    day = min(anchor || local.day, Date.days_in_month(date))
    NaiveDateTime.new!(Date.new!(date.year, date.month, day), NaiveDateTime.to_time(local))
  end
end
