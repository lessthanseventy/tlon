defmodule Server.Jobs.Outcome do
  @moduledoc """
  A job about a thread ends with one line on that thread. A job is about a thread when its args
  carry `"thread_id"` or `"on_thread"`; a nil there falls back to the standing thread, never to
  nowhere. Its return value states the ending: `{:ok, line}` posts `✓ line`, a bare `:ok` posts
  `✓ <worker> done`, `{:ok, :quiet}` (nothing worth a line) and `{:ok, :posted}` (the callee posted
  its own outcome) post nothing; `{:error, _}`, `{:cancel, _}`, `{:discard, _}` and a raise post
  `✗ <worker>: why`, a retry saying so; a snooze is not an ending. Rides Oban's `:stop` and
  `:exception` telemetry beside `Server.Jobs.Alarm`, which keeps the jobs about no thread;
  `test/server/jobs/outcome_contract_test.exs` holds every worker to one of the two.
  """

  alias Server.Jobs.Alarm

  @handler "tlon-job-outcome"

  @doc "Attach to Oban's `:stop` and `:exception` events."
  @spec attach() :: :ok | {:error, :already_exists}
  def attach,
    do: :telemetry.attach_many(@handler, [[:oban, :job, :stop], [:oban, :job, :exception]], &__MODULE__.handle/4, nil)

  @doc "The thread a job's args are about: `{:thread, id | nil}`, or `:unbound` when they name none."
  @spec thread(map()) :: {:thread, integer() | nil} | :unbound
  def thread(%{"thread_id" => tid}), do: {:thread, tid}
  def thread(%{"on_thread" => tid}), do: {:thread, tid}
  def thread(_args), do: :unbound

  @doc false
  def handle(_event, _measurements, %{job: %Oban.Job{args: args}} = meta, _config) do
    with {:thread, tid} <- thread(args), line when is_binary(line) <- line(meta) do
      Alarm.post(tid, line)
    end

    :ok
  end

  def handle(_event, _measurements, _meta, _config), do: :ok

  @doc "The line a job's ending posts, `nil` for none."
  @spec line(map()) :: String.t() | nil
  def line(%{state: :success, result: {:ok, said}}) when said in [:quiet, :posted], do: nil
  def line(%{state: :success, result: {:ok, line}}) when is_binary(line), do: "✓ " <> line
  def line(%{state: :success, job: %Oban.Job{worker: worker}}), do: "✓ #{worker} done"
  def line(%{state: :snoozed}), do: nil

  def line(%{state: :failure, job: %Oban.Job{worker: worker, attempt: attempt, max_attempts: max}} = meta),
    do: "✗ #{worker}: #{reason(meta)} — retrying (#{attempt}/#{max})"

  def line(%{state: state, job: %Oban.Job{worker: worker}} = meta) when state in [:cancelled, :discard],
    do: "✗ #{worker}: #{reason(meta)}"

  @doc "Why a job ended badly, from its return value first, else the exception, in one short line."
  @spec reason(map()) :: String.t()
  def reason(%{result: {_, why}}) when is_binary(why), do: head(why)
  def reason(%{result: {_, why}}), do: why |> inspect() |> head()
  def reason(%{error: %{__exception__: true} = e}), do: e |> Exception.message() |> head()
  def reason(%{error: other}) when not is_nil(other), do: other |> inspect() |> head()
  def reason(_meta), do: "no error recorded"

  defp head(text), do: text |> String.split("\n", parts: 2) |> hd() |> String.slice(0, 160)
end
