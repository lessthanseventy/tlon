defmodule Server.Jobs.Alarm do
  @moduledoc """
  A job about no thread that is discarded or cancelled tells the operator: one line on the standing
  machine thread, delivered at birth (an alarm is for the operator, not a wake for the lead) and
  skipped while it is already the thread's latest message, so a job failing every minute is one
  line, not a flood. Rides Oban's `[:oban, :job, :exception]` and `[:oban, :job, :stop]` telemetry;
  a job about a thread is `Server.Jobs.Outcome`'s.
  """

  import Ecto.Query

  alias Server.Bus
  alias Server.Channel
  alias Server.Jobs.Outcome
  alias Server.Message
  alias Server.Repo
  alias Server.Thread

  @handler "tlon-job-alarm"

  def attach,
    do: :telemetry.attach_many(@handler, [[:oban, :job, :exception], [:oban, :job, :stop]], &__MODULE__.handle/4, nil)

  @doc false
  def handle(_event, _measurements, %{state: :discard, worker: worker} = meta, _config),
    do: unbound(meta, "⚠ job #{worker} discarded: #{Outcome.reason(meta)}")

  def handle(_event, _measurements, %{state: :cancelled, worker: worker} = meta, _config),
    do: unbound(meta, "⚠ job #{worker} cancelled: #{Outcome.reason(meta)}")

  def handle(_event, _measurements, _meta, _config), do: :ok

  defp unbound(%{job: %Oban.Job{args: args}}, body) do
    case Outcome.thread(args) do
      :unbound -> post(body)
      {:thread, _} -> :ok
    end
  end

  defp unbound(_meta, body), do: post(body)

  @doc "One line on the standing thread."
  @spec post(String.t()) :: :ok
  def post(body), do: post(nil, body)

  @doc """
  One line on thread `thread_id` as `tlon`, delivered at birth; nil, or a thread gone, goes to the
  standing thread. Skipped while the same line is already the thread's latest message.
  """
  @spec post(integer() | nil, String.t()) :: :ok
  def post(thread_id, body) do
    with %Thread{id: tid} <- target(thread_id),
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

  defp target(nil), do: Channel.machine_thread()
  defp target(thread_id), do: Channel.thread(thread_id) || Channel.machine_thread()

  defp repeat?(tid, body) do
    case Repo.one(from m in Message, where: m.thread_id == ^tid, order_by: [desc: m.id], limit: 1) do
      %Message{author: "tlon", body: ^body} -> true
      _ -> false
    end
  end
end
