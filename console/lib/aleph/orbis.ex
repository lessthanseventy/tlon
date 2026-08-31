defmodule Console.Orbis do
  @moduledoc """
  ORBIS — the god-view survey DATA behind tertius, Orbis' **resident surveyor** (Orbis Tertius
  design, slice 2). tertius no longer sits as Tlön's center coworker in the operator's eye; its
  home view is this survey — the god-view over workspaces. Every machine thread (root + leaves) is
  reduced to lead + status + conflict count, plus the open/stalled/done tallies. The single source
  of the rollup's semantics, shared by BOTH surfaces — the Tlön sidebar panel (`Console.Panel.Orbis`,
  via `Console.Cockpit`) and the `chat` tab's header strip (`Console.MachineChat.Loop`) — so a status
  rule never drifts between them.

  Pure data, no styling: `rollup/0` returns `%{summary: %{open, stalled, done, conflicts},
  rows: [%{id, title, lead, status, conflicts, workspace_id, stage, awaiting, blocking}]
  (the last three nil on an untracked thread — chat and tracked are ONE list since slice C),
  workspaces: [%{id, name, summary, leaves}]}` (status
  `:open | :stalled | :done`), or `nil` when server is down / there are no machine threads. `summary`
  and `rows` are the per-thread lens the LEAVES sidebar + chat-tab strip read; `workspaces` is the
  survey's per-workspace rollup — grouped under the live server workspaces (`Console.Workspaces`, Slice 1), each
  row carrying its workspace `id` (D0.3) — the face Orbis' Overview renders as one row per workspace, and the
  survey's `Enter`/click resolve back to. Status derives from `Server.Board.brief/1` (the
  same per-thread brief Triage reads) so it reflects real blockers/failed checks, never a
  self-report. The gather is guarded: a server hiccup degrades to `nil`, never a crash.
  """

  alias Server.Channel

  @spec rollup() :: %{summary: map(), rows: [map()], workspaces: [map()]} | nil
  def rollup do
    # ONE list (reshape slice C): chat threads and tracked threads are the same kind of row —
    # a tracked one carries stage/awaiting/blocking and the panel chips it. The old reject
    # made worklines a parallel universe; that split is what let real work bypass the machine.
    blocking = blocking_by_thread()

    rows =
      Channel.machine_threads()
      |> without_root(root_thread_id())
      |> Enum.map(&row(&1.thread, blocking))
      |> Enum.sort_by(&status_rank(&1.status))

    if rows == [], do: nil, else: %{summary: summarize(rows), rows: rows, workspaces: workspaces(rows)}
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  @doc "Drop the root machine thread — the coworkers' permanent home, never a work item — from
  the survey `blocks` (`[%{thread: %{id}}]`). A nil `root_id` (funes down / no machine thread)
  keeps every block. Pure so both survey surfaces test it without a live channel."
  @spec without_root([%{thread: %{id: term()}}], term() | nil) :: [%{thread: %{id: term()}}]
  def without_root(blocks, nil), do: blocks
  def without_root(blocks, root_id), do: Enum.reject(blocks, &(&1.thread.id == root_id))

  # The root machine thread's id, or nil when funes is down / no machine thread yet — the same
  # guard shape as every server gather in this module.
  defp root_thread_id do
    case Channel.machine_thread() do
      %{id: id} -> id
      _ -> nil
    end
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  # Keyed by thread id; through the Server facade (the Ledger module is boundary-private).
  # Guarded like every server gather here.
  defp blocking_by_thread do
    Map.new(Server.workline_statuses(), &{&1.id, %{awaiting: &1.awaiting, blocking: &1.blocking}})
  rescue
    _ -> %{}
  catch
    :exit, _ -> %{}
  end

  @doc """
  Group the rollup rows under the live server workspaces (`Console.Workspaces.all/0`, Slice 1 Task B3). With
  the single seeded Tlön workspace this is one row — identical to Slice 0. Reads the cached workspace list;
  `workspaces/2` is the pure grouping over explicit `%{id, name}` refs (tested without the live cache).
  """
  @spec workspaces([map()]) :: [%{id: term(), name: String.t(), summary: map(), leaves: [map()]}]
  def workspaces(rows), do: workspaces(rows, workspace_refs())

  @doc """
  Group `rows` under explicit `%{id, name}` workspace refs — every row carries its server **id** (D0.3)
  and, since reshape slice C, its `workspace_id`: membership is REAL (slice A made `thread.workspace_id`
  enforced), so each workspace's survey row carries exactly its own threads. A row matching no ref
  lands in the first workspace — belt over the boot repair, never a dropped thread. No workspace refs
  (server genuinely down — the app self-seeds at boot) yields no rows; the survey renders empty
  rather than fabricating a workspace (reshape slice A).
  """
  @spec workspaces([map()], [%{id: term(), name: String.t()}]) :: [
          %{id: term(), name: String.t(), summary: map(), leaves: [map()]}
        ]
  def workspaces(_rows, []), do: []

  def workspaces(rows, refs) do
    known = MapSet.new(refs, & &1.id)
    # Orphans land in the OLDEST workspace (the seeded default) — the cache hands refs
    # newest-first, so the list head would be the wrong home the moment a second
    # workspace exists.
    default_id = Enum.min_by(refs, & &1.id).id

    by_workspace =
      Enum.group_by(rows, fn row ->
        workspace_id = Map.get(row, :workspace_id)
        if workspace_id in known, do: workspace_id, else: default_id
      end)

    Enum.map(refs, fn ref ->
      leaves = Map.get(by_workspace, ref.id, [])
      %{id: ref.id, name: ref.name, summary: summarize(leaves), leaves: leaves}
    end)
  end

  # The server workspace refs, guarded: a cache hiccup degrades to [] (→ empty survey).
  defp workspace_refs do
    Enum.map(Console.Workspaces.all(), &%{id: &1.id, name: &1.name})
  rescue
    _ -> []
  catch
    :exit, _ -> []
  end

  defp row(thread, blocking_by_thread) do
    scope = Server.Board.brief(thread)
    conflicts = length(scope.blockers.shown) + scope.blockers.more + failed_checks(scope)
    ledger = Map.get(blocking_by_thread, thread.id, %{})

    %{
      id: thread.id,
      title: thread.title,
      lead: scope.lead,
      status: status(thread.state, conflicts),
      conflicts: conflicts,
      workspace_id: thread.workspace_id,
      stage: thread.stage,
      awaiting: thread.awaiting,
      blocking: Map.get(ledger, :blocking)
    }
  end

  @doc """
  A thread's status from its state and conflict count: a CLOSED thread is `:done`; an open one with
  a blocker or failed check is `:stalled`; else it is `:open` (in flight).
  """
  @spec status(String.t(), non_neg_integer()) :: :open | :stalled | :done
  def status("closed", _conflicts), do: :done
  def status(_state, conflicts) when conflicts > 0, do: :stalled
  def status(_state, _conflicts), do: :open

  @doc "The open/stalled/done tallies + total conflicts across a list of rollup rows."
  @spec summarize([map()]) :: %{
          open: non_neg_integer(),
          stalled: non_neg_integer(),
          done: non_neg_integer(),
          conflicts: non_neg_integer()
        }
  def summarize(rows) do
    by = Enum.frequencies_by(rows, & &1.status)

    %{
      open: Map.get(by, :open, 0),
      stalled: Map.get(by, :stalled, 0),
      done: Map.get(by, :done, 0),
      conflicts: Enum.reduce(rows, 0, &(&1.conflicts + &2))
    }
  end

  defp failed_checks(scope), do: Enum.count(scope.checks.shown, &(&1.kind == "check_failed"))

  # Stalled sorts first so trouble rides the top of the lens; open before the settled done rows.
  defp status_rank(:stalled), do: 0
  defp status_rank(:open), do: 1
  defp status_rank(:done), do: 2
end
