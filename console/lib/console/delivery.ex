defmodule Console.Delivery do
  @moduledoc """
  How a Bus event reaches a coworker or the operator: @-mention wake-ups injected as turns into
  the right tmux window (`delivery_target/3` is the routing decision), the leaf-finished nudge to
  the surveyor, a closed leaf's window teardown, and desktop notifications (OSC 777). All
  best-effort edges — a missing window is a skip, never a crash.
  """

  alias Console.Profiles
  alias Console.Reads
  alias Console.Safe
  alias Console.Space
  alias Console.Staffing
  alias Console.Tmux

  # Operator-relevant Bus events become native desktop notifications via an OSC 777 escape —
  # ghostty (Linux and macOS) raises it as a real notification, and only when unfocused (the
  # terminal owns focus policy). Best-effort: a host that ignores OSC 777 ignores the bytes.
  def desktop_notify(tag, row) do
    with {title, body} <- Console.Notify.for_event(tag, row) do
      _ = File.write("/dev/tty", Console.Notify.osc(title, body))
    end

    :ok
  end

  # A machine LEAF closing nudges the tertius center to refresh the rollup — the "a leaf
  # finished" synthesis trigger. The root closing is not a leaf finish. Best-effort; tertius not up
  # (or not yet captured) = no-op. (record_done-without-close is a future trigger — its Bus event is
  # thread-scoped, so it doesn't reach the cockpit globally the way :thread_closed does.)
  def nudge_tertius_on_finish(:thread_closed, %{scope: "machine", id: id}, %{standing_thread_id: root} = state)
      when is_integer(root) and is_integer(id) and id != root do
    workspace_id = Space.active_workspace_id(state)

    case tlon_window_index(workspace_id, lead_window_name(workspace_id)) do
      nil ->
        :ok

      index ->
        inject_turn(
          workspace_id,
          index,
          "[tlon] leaf ##{id} finished — run machine_overview and refresh the root rollup."
        )
    end
  end

  def nudge_tertius_on_finish(_tag, _row, _state), do: :ok

  # A closed leaf's window is torn down (the driver contract's `teardown`, Slice F): the seat
  # frees instead of idling forever — the warm-pool groundwork. Safe against the standing center:
  # `leaf_tab` only matches `@funes_thread`-tagged / legacy `t<id>` windows, never the lead's own
  # window. Can't respawn-loop: the spawn candidates (`Server.staffed_machine_threads`) are OPEN
  # threads only. Best-effort — a vanished window is already what we wanted.
  def teardown_closed_leaf(:thread_closed, %{scope: "machine", id: id}, state) when is_integer(id) do
    workspace_id = Space.active_workspace_id(state)

    case Tmux.leaf_tab(Tmux.list_windows(workspace_id), id) do
      %{index: index} -> Tmux.kill_window(workspace_id, index)
      _ -> :ok
    end

    :ok
  end

  def teardown_closed_leaf(_tag, _row, _state), do: :ok

  @doc """
  @-mention delivery: a posted message naming a coworker (`@tertius-machine`) is injected as a turn
  into that coworker's tmux window, so a cold pane gets woken instead of silently accumulating an
  unread thread. Pure routing lives in `Console.Mention`; this is the edge — best-effort tmux
  send-keys, never a crash on a missing window.
  """
  def mention_notify(row, state) do
    lead = thread_lead(row)
    workspace_id = Space.active_workspace_id(state)

    case delivery_target(row, state, lead) do
      :skip ->
        :ok

      {:route, staffed} ->
        for {window, text} <-
              Console.Mention.route(row, [lead: lead, staffed_window: staffed], Space.roster(workspace_id)),
            index = tlon_window_index(workspace_id, window),
            not is_nil(index) do
          inject_turn(workspace_id, index, text)
        end

        :ok
    end
  end

  @doc """
  THE routing decision: which window a posted message wakes, and whether to wake at all. Every
  staffed machine thread has its OWN leaf window, so:

    * the standing coworker's thread → route globally (`staffed_window: nil`); its lead already
      runs in the center window.
    * a worker-led staffed thread that's live AND past its opening turn → route onto its leaf, so
      replies reach the session working THAT thread — not the standing coworker (otherwise both
      would answer the same post).
    * a worker-led staffed thread mid-spawn / pre-opening → `:skip`: the spawn pass owns the
      opening turn (two-phase, race-safe); waking here would double it.
    * no staffed lead, or a meta/unknown lead (no leaf window for it) → route globally.
  """
  @spec delivery_target(map(), map(), String.t() | nil) :: :skip | {:route, String.t() | nil}
  def delivery_target(%{thread_id: tid}, state, lead) when is_integer(tid) do
    workspace_id = Space.active_workspace_id(state)
    standing = state.standing_thread_id || Reads.machine_thread_id(workspace_id)

    cond do
      tid == standing -> {:route, nil}
      is_nil(lead) or not Staffing.leaf_staffed?(lead, workspace_id) -> {:route, nil}
      window = staffed_leaf_window(tid, Tmux.list_windows(workspace_id), state.opening_injected) -> {:route, window}
      true -> :skip
    end
  end

  def delivery_target(_row, _state, _lead), do: {:route, nil}

  @doc """
  The live window NAME of a staffed thread's leaf session once its opening turn has been submitted
  — the `staffed_window` redirect `Console.Mention.route/3` rewrites the lead onto. Resolved via
  the `@funes_thread` routing map; the submitted check reads the window's own `@funes_opening` tag
  first, so a restarted cockpit (empty `opening_injected`) keeps delivering to already-running
  leaves instead of `:skip`ping them forever. nil while mid-spawn / pre-opening.
  """
  @spec staffed_leaf_window(integer(), [Tmux.tab()], MapSet.t()) :: String.t() | nil
  def staffed_leaf_window(tid, tabs, opening_injected) do
    case Tmux.leaf_tab(tabs, tid) do
      %{name: name} = tab ->
        if tab[:opening] == "done" or MapSet.member?(opening_injected, tid), do: name

      _ ->
        nil
    end
  end

  # The server handle of the coworker staffed on this message's thread (its lead), or nil.
  # Read in-process (console boots server); never crash the hub if the lookup fails.
  defp thread_lead(%{thread_id: tid}) when not is_nil(tid), do: Safe.value(fn -> Server.thread_lead(tid) end, nil)

  defp thread_lead(_), do: nil

  # The active roster's LEAD window name (the center's tab label) for `workspace_id`, or nil (no roster
  # / server down).
  defp lead_window_name(workspace_id) do
    case Space.fetch(workspace_id) do
      %Space{roster: [lead | _]} -> Profiles.roster_entry(lead).name
      _ -> nil
    end
  end

  # The tmux window index for a named coworker window in workspace `workspace_id`, from the live session
  # (nil if not up).
  defp tlon_window_index(workspace_id, name), do: Tmux.window_index(Tmux.list_windows(workspace_id), name)

  # Inject `text` as a submitted turn into window `index`: text, then Enter, in one go. Only safe for
  # a LONG-BOOTED window (the standing coworkers); a freshly-spawned harness needs the two-phase
  # form (`Tmux.send_text` now, `Tmux.submit` on a later render) or the Enter is swallowed.
  defp inject_turn(workspace_id, index, text) do
    Tmux.send_text(workspace_id, index, text)
    Tmux.submit(workspace_id, index)
  end
end
