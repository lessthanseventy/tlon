defmodule Server.Home do
  @moduledoc """
  The home, as a surface other than the chat reads it: what the operator's jots have left open, what
  is coming, and the newest notes. The jots are the home messenger's (`:home_messenger`).
  """

  alias Server.Jot

  @doc """
  The home at `now`: `open` the to-dos and the reminders whose time has passed, `coming` the
  reminders to come, soonest first, `notes` the newest twenty, and `done_week` how many things were
  done in the last seven days. A row's `since` is when it was said, its `told_at` when the operator
  was last told a reminder that is due (nil before that).
  """
  @spec status(DateTime.t()) :: %{open: [map()], coming: [map()], notes: [String.t()], done_week: non_neg_integer()}
  def status(now) do
    {coming, open} = board(via(), now)

    %{
      open: Enum.map(open, &row/1),
      coming: Enum.map(coming, &row/1),
      notes: Jot.notes(via(), 20),
      done_week: Jot.done_since(via(), DateTime.add(now, -7, :day))
    }
  end

  @doc """
  Take what the operator typed somewhere other than the chat, at `now`, as a text in the chat is
  taken: kept, read, and answered. The answer, as the chat would say it.
  """
  @spec say(String.t(), DateTime.t()) :: String.t()
  def say(text, now) do
    {reply, _opts} =
      Server.Home.Inbox.keep(
        via(),
        -System.unique_integer([:positive, :monotonic]) - System.os_time(:second),
        text,
        now
      )

    reply
  end

  @doc ~s|Put the open thing `id` off `until` (`"hour"`, `"tomorrow"`) from `now`: `{:ok, jot}`, `:error` when it is none or is done.|
  @spec later(integer(), String.t(), DateTime.t()) :: {:ok, Jot.t()} | :error
  def later(id, until, now) when until in ["hour", "tomorrow"] do
    case Jot.open(via(), id) do
      nil -> :error
      jot -> {:ok, Server.Home.Inbox.later(jot, until, now)}
    end
  end

  def later(_id, _until, _now), do: :error

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

  defp row(jot) do
    %{
      id: jot.id,
      kind: jot.kind,
      text: jot.text,
      due_at: jot.due_at,
      every: jot.every,
      since: jot.received_at,
      told_at: jot.nudged_at
    }
  end
end
