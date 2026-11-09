defmodule Server.Office.NeedsDirty do
  @moduledoc """
  Whether the needs have possibly changed since the last page pass, so `Server.Jobs.Drain` derives
  them (`Server.Office.NeedsPage`) when something moved, not every minute. Any write on the bus's
  activity, thread or session topics marks it dirty; `take/1` answers true once per mark, and also
  once at boot and when `@ceiling_s` has passed since the last true. The ceiling is for the needs no
  bus event announces: a clock (a quiet workline), a failed job, the box's health, a stranded
  checkout. Marks that arrive while a pass runs survive it: `take/1` clears before the pass.
  """
  use GenServer

  @ceiling_s 300

  def start_link(_), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc "True when the needs should be derived now; clears the mark. True too when the server is not up."
  @spec take(DateTime.t()) :: boolean()
  def take(now \\ DateTime.utc_now()) do
    if Process.whereis(__MODULE__), do: GenServer.call(__MODULE__, {:take, now}), else: true
  end

  @doc "Mark the needs possibly changed."
  @spec mark() :: :ok
  def mark, do: GenServer.cast(__MODULE__, :mark)

  @impl GenServer
  def init(:ok) do
    Server.Bus.subscribe_activity()
    Server.Bus.subscribe_threads()
    Server.Bus.subscribe_sessions()
    {:ok, %{dirty: true, last: nil}}
  end

  @impl GenServer
  def handle_call({:take, now}, _from, %{dirty: dirty, last: last} = state) do
    run? = dirty or is_nil(last) or DateTime.diff(now, last) >= @ceiling_s
    {:reply, run?, if(run?, do: %{state | dirty: false, last: now}, else: state)}
  end

  @impl GenServer
  def handle_cast(:mark, state), do: {:noreply, %{state | dirty: true}}

  @impl GenServer
  def handle_info(_event, state), do: {:noreply, %{state | dirty: true}}
end
