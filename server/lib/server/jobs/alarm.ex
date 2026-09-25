defmodule Server.Jobs.Alarm do
  @moduledoc """
  A discarded job tells the operator (master plan piece A): the staffing pass failed every
  minute for 31 hours on `tmux: enoent` (2026-09-23) and nothing said so. Rides Oban's
  `[:oban, :job, :exception]` telemetry; a discard posts `⚠ job … discarded` to the standing
  machine thread — delivered at birth (an alarm is for the operator, not a wake for the lead)
  and skipped while it is already the thread's latest message, so a job failing every minute
  is one line, not a flood.
  """

  import Ecto.Query

  alias Server.Bus
  alias Server.Channel
  alias Server.Message
  alias Server.Repo
  alias Server.Thread

  @handler "tlon-job-alarm"

  def attach, do: :telemetry.attach(@handler, [:oban, :job, :exception], &__MODULE__.handle/4, nil)

  @doc false
  def handle(_event, _measurements, %{state: :discarded, worker: worker} = meta, _config),
    do: post("⚠ job #{worker} discarded: #{reason(meta)}")

  def handle(_event, _measurements, _meta, _config), do: :ok

  defp reason(%{error: %{__exception__: true} = e}), do: e |> Exception.message() |> head()
  defp reason(%{error: other}), do: other |> inspect() |> head()
  defp reason(_meta), do: "no error recorded"

  defp head(text), do: text |> String.split("\n", parts: 2) |> hd() |> String.slice(0, 160)

  @doc false
  def post(body) do
    with %Thread{id: tid} <- Channel.machine_thread(),
         false <- repeat?(tid, body) do
      now = DateTime.truncate(DateTime.utc_now(), :second)

      %{thread_id: tid, author: "tlon", body: body}
      |> Message.post_changeset()
      |> Ecto.Changeset.put_change(:delivered_at, now)
      |> Repo.insert!()
      |> tap(&Bus.broadcast({:message_posted, &1}))
    end

    :ok
  end

  defp repeat?(tid, body) do
    case Repo.one(from m in Message, where: m.thread_id == ^tid, order_by: [desc: m.id], limit: 1) do
      %Message{author: "tlon", body: ^body} -> true
      _ -> false
    end
  end
end
