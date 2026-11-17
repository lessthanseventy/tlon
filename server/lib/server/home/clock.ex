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
  The occurrence of a time that repeats `every` (`"day"`, `"week"`, `"month"`) after `utc`, at the
  same wall-clock time.
  """
  @spec step(DateTime.t(), String.t()) :: DateTime.t()
  def step(%DateTime{} = utc, every) do
    local = local(utc)

    utc(
      case every do
        "day" -> NaiveDateTime.shift(local, day: 1)
        "week" -> NaiveDateTime.shift(local, week: 1)
        "month" -> NaiveDateTime.shift(local, month: 1)
      end
    )
  end

  @doc "The first occurrence of `utc` repeating `every` that is after `now`."
  @spec next(DateTime.t(), String.t(), DateTime.t()) :: DateTime.t()
  def next(%DateTime{} = utc, every, now) do
    stepped = step(utc, every)
    if DateTime.after?(stepped, now), do: stepped, else: next(stepped, every, now)
  end

  @doc "The last occurrence of `utc` repeating `every` that is not after `now`: `utc` itself when its next one is."
  @spec latest(DateTime.t(), String.t(), DateTime.t()) :: DateTime.t()
  def latest(%DateTime{} = utc, every, now) do
    stepped = step(utc, every)
    if DateTime.after?(stepped, now), do: utc, else: latest(stepped, every, now)
  end

  @doc "A UTC instant as the helper says it: `Fri 20 Nov 09:00`, local."
  @spec say(DateTime.t()) :: String.t()
  def say(%DateTime{} = utc), do: Calendar.strftime(local(utc), "%a %-d %b %H:%M")
end
