defmodule Server.Wake do
  @moduledoc """
  A wake waiting for its coworker: the prompt the switchboard would hand a pane, queued for the
  coworker's own session to take (the tlon-citizen mod drains it and submits it as a turn) instead
  of typed into the pane. Keyed by the pane's thread and the coworker's name, not a session, so a
  pane that died and was respawned takes what its predecessor never did. Taking a wake is not
  activity: `take/2` is read through an identity that leaves warmth alone, so only the turn a wake
  starts counts as its coworker having heard it.
  """
  use Ecto.Schema

  import Ecto.Query

  alias Server.Repo

  @overdue_s 300

  schema "wake" do
    field :agent, :string
    field :prompt, :string
    field :inserted_at, :utc_datetime
    belongs_to :thread, Server.Thread
  end

  @doc "Queue `prompt` for `agent`'s pane on `thread_id`. `{:ok, wake}`."
  def queue(thread_id, agent, prompt) do
    Repo.insert(%__MODULE__{thread_id: thread_id, agent: agent, prompt: prompt, inserted_at: now()})
  end

  @doc "Every wake waiting for `agent` on `thread_id`, oldest first, taken: gone once returned."
  def take(thread_id, agent) do
    {_, wakes} =
      Repo.delete_all(from(w in __MODULE__, where: w.thread_id == ^thread_id and w.agent == ^agent, select: w))

    wakes |> Enum.sort_by(&{&1.inserted_at, &1.id}) |> Enum.map(& &1.prompt)
  end

  @doc """
  Queue `prompts` again for `agent` on `thread_id`: wakes it took but could not submit, put back
  in order so the next take hands them over again. `{:ok, count}`.
  """
  def put_back(thread_id, agent, prompts) do
    at = now()
    rows = Enum.map(prompts, &%{thread_id: thread_id, agent: agent, prompt: &1, inserted_at: at})
    {n, _} = Repo.insert_all(__MODULE__, rows)
    {:ok, n}
  end

  @doc """
  Report each wake left untaken past `@overdue_s` to its workspace's sheriff, and let it go: its
  pane's session is not draining (no tlon-citizen mod, a session that never registered), which is a
  fault to fix, never a pane to type into. The message it was for is still a row, and
  `Server.Switchboard.redeliver_unheard/1` offers it again. Returns how many were reported.
  """
  def report_overdue(now \\ DateTime.utc_now()) do
    cutoff = DateTime.add(now, -@overdue_s)

    {n, wakes} =
      Repo.delete_all(from(w in __MODULE__, where: w.inserted_at < ^cutoff, select: w))

    wakes
    |> Enum.uniq_by(&{&1.thread_id, &1.agent})
    |> Enum.each(fn w ->
      with %Server.Thread{} = thread <- Repo.get(Server.Thread, w.thread_id) do
        Server.Sheriff.report(
          thread,
          "#{w.agent}'s pane has not taken its wake in #{div(@overdue_s, 60)} minutes — its session " <>
            "is not draining wakes (is the tlon-citizen mod loaded?)"
        )
      end
    end)

    n
  end

  defp now, do: DateTime.truncate(DateTime.utc_now(), :second)
end
