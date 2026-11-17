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

  @doc "A UTC instant as the helper says it: `Fri 20 Nov 09:00`, local."
  @spec say(DateTime.t()) :: String.t()
  def say(%DateTime{} = utc), do: Calendar.strftime(local(utc), "%a %-d %b %H:%M")
end
