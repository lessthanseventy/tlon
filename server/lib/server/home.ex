defmodule Server.Home do
  @moduledoc """
  The home, as a surface other than the chat reads it: what the operator's jots have left open, what
  is coming, and the newest notes. The jots are the home messenger's (`:home_messenger`).
  """

  alias Server.Jot

  @doc """
  The home at `now`: `open` the to-dos and the reminders whose time has passed, `coming` the
  reminders to come, soonest first, and `notes` the newest twenty.
  """
  @spec status(DateTime.t()) :: %{open: [map()], coming: [map()], notes: [String.t()]}
  def status(now) do
    {coming, open} = board(via(), now)
    %{open: Enum.map(open, &row/1), coming: Enum.map(coming, &row/1), notes: Jot.notes(via(), 20)}
  end

  @doc "What is open from `via` at `now`, as `{coming, open}`: the reminders to come, and everything else still open."
  @spec board(String.t(), DateTime.t()) :: {[Jot.t()], [Jot.t()]}
  def board(via, now),
    do: via |> Jot.opens() |> Enum.split_with(&(&1.kind == "reminder" and DateTime.after?(&1.due_at, now)))

  @doc "Mark the open thing `id` done at `now`: `{:ok, jot}`, `:error` when it is none or is done."
  @spec done(integer(), DateTime.t()) :: {:ok, Jot.t()} | :error
  def done(id, now) do
    case Jot.open(via(), id) do
      nil -> :error
      jot -> {:ok, Jot.done(jot, now)}
    end
  end

  defp via, do: Application.get_env(:server, :home_messenger, Server.Home.Telegram).name()

  defp row(jot), do: %{id: jot.id, kind: jot.kind, text: jot.text, due_at: jot.due_at, every: jot.every}
end
