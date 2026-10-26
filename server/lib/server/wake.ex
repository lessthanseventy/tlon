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

  @doc "Let go of every wake waiting on `thread_id`: a closed thread has no pane to take them."
  def clear(thread_id), do: Repo.delete_all(from(w in __MODULE__, where: w.thread_id == ^thread_id))

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
  fault to fix, never a pane to type into. A wake whose coworker is mid-turn on its thread (a live
  session's `thinking_since` within the stale-turn clock, `Server.Presence.Thinking`) waits: a pane
  in a long tool call drains only once the call returns. The message it was for is still a row, and
  `Server.Switchboard.redeliver_unheard/1` offers it again. A wake on a closed thread, or whose seat
  posted anywhere since it was queued, is let go unreported; so is one to a seat with no live session
  or no window on the thread, or that no longer holds the thread's stage (nothing to drain it); a seat already paged and silent since is
  paged once per stall. Returns how many were reported.
  """
  def report_overdue(now \\ DateTime.utc_now()) do
    cutoff = DateTime.add(now, -@overdue_s)
    live = DateTime.add(now, -Server.Presence.Thinking.stale_turn_seconds())

    busy =
      from s in Server.Session,
        join: a in Server.Agent,
        on: a.id == s.agent_id,
        where:
          s.thread_id == parent_as(:wake).thread_id and a.name == parent_as(:wake).agent and is_nil(s.ended_at) and
            s.thinking_since > ^live,
        select: 1

    {_, wakes} =
      Repo.delete_all(from(w in __MODULE__, as: :wake, where: w.inserted_at < ^cutoff and not exists(busy), select: w))

    reported =
      wakes
      |> Enum.uniq_by(&{&1.thread_id, &1.agent})
      |> Enum.filter(fn w ->
        with %Server.Thread{state: "open"} = thread <- Repo.get(Server.Thread, w.thread_id),
             true <- seated?(thread, w.agent),
             false <- took_it?(w),
             false <- paged_and_silent?(thread, w.agent) do
          Server.Sheriff.report(
            thread,
            "#{w.agent}'s pane has not taken its wake in #{div(@overdue_s, 60)} minutes — its session " <>
              "is not draining wakes (is the tlon-citizen mod loaded?)"
          )

          true
        else
          _ -> false
        end
      end)

    length(reported)
  end

  # A wake is for a pane to drain: the seat holds the workline's current stage and its LIVE session
  # is the one in the thread's window (its `pane_ref` is a pane of that window — a windowless live
  # row beside a windowed dead one is no seat). Without one the wake is let go unpaged
  # (`Server.Switchboard.redeliver_unheard/1` and staffing answer a lead that moved on). A tmux that
  # can't be asked is no proof of a missing window.
  defp seated?(thread, agent) do
    holds_stage?(thread, agent) and
      case live_pane_ref(thread, agent) do
        nil -> false
        pane_ref -> windowed?(thread, agent, pane_ref)
      end
  end

  defp holds_stage?(%{stage: nil}, _agent), do: true
  defp holds_stage?(thread, agent), do: Server.Channel.thread_lead(thread.id) == agent

  defp live_pane_ref(thread, agent) do
    Repo.one(
      from s in Server.Session,
        join: a in Server.Agent,
        on: a.id == s.agent_id,
        where: s.thread_id == ^thread.id and a.name == ^agent and is_nil(s.ended_at),
        select: s.pane_ref
    )
  end

  defp windowed?(thread, agent, pane_ref) do
    case Server.Tmux.list_windows(thread.workspace_id) do
      {:error, :not_up} -> false
      {:error, _} -> true
      tabs -> tabs |> Enum.filter(&(&1.pane_id == pane_ref)) |> Server.Office.windowed?(thread.id, agent)
    end
  end

  # A seat that posted anywhere since its wake was queued is alive and heard it, whichever pane
  # it answered from.
  defp took_it?(w) do
    Repo.exists?(from m in Server.Message, where: m.author == ^w.agent and m.created_at >= ^w.inserted_at)
  end

  # One page per stall: the seat's last page on this thread stands until it posts again.
  defp paged_and_silent?(%{workspace_id: nil}, _agent), do: false

  defp paged_and_silent?(thread, agent) do
    like = "🚨 ##{thread.id} %: #{agent}'s pane has not taken its wake%"

    page_at =
      Repo.one(
        from m in Server.Message,
          join: t in Server.Thread,
          on: t.id == m.thread_id,
          where:
            t.workspace_id == ^thread.workspace_id and t.title == ^Server.Sheriff.beat_title() and
              like(m.body, ^like),
          select: max(m.created_at)
      )

    page_at != nil and
      not Repo.exists?(from m in Server.Message, where: m.author == ^agent and m.created_at >= ^page_at)
  end

  defp now, do: DateTime.truncate(DateTime.utc_now(), :second)
end
