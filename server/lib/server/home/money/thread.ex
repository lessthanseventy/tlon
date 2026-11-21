defmodule Server.Home.Money.Thread do
  @moduledoc """
  The short conversation of a money chat thread, kept in `Server.Home.Keep` as JSON under
  `home_money:<thread>`: the last #{10} turns, each `%{"q", "plan", "reply", "at"}` (`at` in Unix
  seconds), none older than two hours.
  """

  alias Server.Home.Keep

  @turns 10
  @ttl 7_200
  @id ~r/\A[A-Za-z0-9_-]{1,40}\z/

  @type turn :: %{String.t() => term()}

  @doc "`id` when it is a usable thread id, else a new one."
  @spec id(term()) :: String.t()
  def id(id) when is_binary(id) do
    if Regex.match?(@id, id), do: id, else: fresh()
  end

  def id(_other), do: fresh()

  defp fresh, do: 6 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

  @doc "The turns kept for `thread` that are not older than two hours at `now`, oldest first."
  @spec load(String.t(), DateTime.t()) :: [turn()]
  def load(thread, now) do
    with body when is_binary(body) <- Keep.get(key(thread)),
         {:ok, turns} when is_list(turns) <- JSON.decode(body) do
      Enum.filter(turns, &fresh?(&1, now))
    else
      _ -> []
    end
  end

  @doc "Keep `turn` (stamped with `now`) after the turns already there, the newest #{10}."
  @spec push(String.t(), %{q: String.t(), plan: term(), reply: String.t()}, DateTime.t()) :: :ok
  def push(thread, %{q: q, plan: plan, reply: reply}, now) do
    turn = %{"q" => q, "plan" => plan, "reply" => reply, "at" => DateTime.to_unix(now)}
    turns = Enum.take(load(thread, now) ++ [turn], -@turns)
    Keep.put(key(thread), JSON.encode!(turns))
  end

  defp key(thread), do: "home_money:" <> thread

  defp fresh?(%{"at" => at}, now) when is_integer(at), do: DateTime.to_unix(now) - at <= @ttl
  defp fresh?(_other, _now), do: false
end
