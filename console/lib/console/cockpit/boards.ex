defmodule Console.Cockpit.Boards do
  @moduledoc """
  The Tickets and Notes boards: the rows each one shows, and the Tickets kanban's own verbs (cursor,
  advance, promote-to-thread). Both are DRAWER panes since UX slice 1 (`Console.Cockpit.Drawer`) —
  this module is what they read and what their verbs do, not where they sit. Reads/writes go through
  `Server.Tickets` / `Server.Notes`, degraded by `Console.Safe`.
  """

  alias Console.Panel
  alias Console.Reads
  alias Console.Safe
  alias Console.Server.Channel
  alias Console.Server.Tickets
  alias Console.Space
  alias Console.Staffing

  @doc "A board pane's data: the workspace's tickets under the kanban cursor, or its notes."
  @spec board_data(:tickets | :notes, map()) :: map()
  def board_data(:tickets, state) do
    id = board_workspace_id(state)

    # ONE query for the whole board (Tickets.blocked_in_workspace/1), not one per card — a card
    # asks "am I blocked?" every frame, and per-card queries are how a board gets slow.
    blocked = Safe.value(fn -> id && Tickets.blocked_in_workspace(id) end, nil) || MapSet.new()
    tickets = Safe.value(fn -> id && id |> Tickets.in_workspace() |> Enum.map(&ticket_row(&1, blocked)) end, nil) || []

    %{tickets: tickets, cursor: state[:board_cursor] || {0, 0}}
  end

  def board_data(:notes, state) do
    id = board_workspace_id(state)
    %{notes: Safe.value(fn -> id && Console.Server.Notes.for_scope("workspace", id) end, nil) || []}
  end

  @ticket_statuses ~w(backlog todo doing done)

  @doc "Move the kanban cursor one step (the drawer's `H`/`L`/`j`/`k` on the TICKETS pane)."
  @spec move_cursor(map(), String.t()) :: map()
  def move_cursor(state, dir), do: %{state | board_cursor: move_grid(state.board_cursor, dir, ticket_columns(state))}

  @doc "Advance the selected ticket one column (`p`), flashing the new status."
  @spec advance_selected_ticket(map()) :: map()
  def advance_selected_ticket(state) do
    case selected_ticket(state, ticket_columns(state)) do
      %{status: status} = ticket ->
        next = next_status(status)
        _ = Safe.value(fn -> Tickets.update(ticket, %{status: next}) end, nil)
        %{state | flash: "ticket ##{ticket.id} → #{next}"}

      _ ->
        %{state | flash: "no ticket selected"}
    end
  end

  # The active workspace's tickets grouped into kanban columns (structs — the render maps to rows off
  # the same in_workspace order, so the cursor indexes the same grid).
  @doc false
  def ticket_columns(state) do
    id = board_workspace_id(state)
    tickets = Safe.value(fn -> id && Tickets.in_workspace(id) end, nil) || []
    Panel.TicketBoard.by_column(tickets)
  end

  defp selected_ticket(%{board_cursor: {col, row}}, cols), do: cols |> Enum.at(col, []) |> Enum.at(row)

  @doc "Move the kanban cursor by a vim key over `cols` (lists per column), clamped to the grid."
  def move_grid({col, row}, "h", cols), do: clamp_grid(max(col - 1, 0), row, cols)
  def move_grid({col, row}, "l", cols), do: clamp_grid(min(col + 1, length(cols) - 1), row, cols)
  def move_grid({col, row}, "j", cols), do: clamp_grid(col, row + 1, cols)
  def move_grid({col, row}, "k", cols), do: clamp_grid(col, max(row - 1, 0), cols)

  def clamp_grid(col, row, cols) do
    len = length(Enum.at(cols, col, []))
    {col, row |> max(0) |> min(max(len - 1, 0))}
  end

  @doc "The kanban's `p`: one column to the right, pinned at done; an unknown status stays put."
  def next_status(status) do
    case Enum.find_index(@ticket_statuses, &(&1 == status)) do
      nil -> status
      i -> Enum.at(@ticket_statuses, min(i + 1, length(@ticket_statuses) - 1))
    end
  end

  @doc "Promote the selected ticket to a thread (`Enter`), staffing it like any new thread."
  @spec promote_selected_ticket(map()) :: map()
  def promote_selected_ticket(state) do
    case selected_ticket(state, ticket_columns(state)) do
      %{id: id, title: title} = ticket ->
        with {:ok, thread} <-
               Channel.open_thread(%{title: title, workspace_id: Space.active_workspace_id(state), scope: "machine"}),
             {:ok, _} <- Safe.value(fn -> Tickets.promote(ticket, thread.id) end, nil) do
          _ = Staffing.spawn_onto(thread.id, Reads.center_dims(state))
          # The promoted thread is the point — close the drawer so it's on screen.
          %{Console.Cockpit.Drawer.close(state) | focused_id: thread.id, flash: "promoted ticket ##{id} → thread"}
        else
          _ -> %{state | flash: "couldn't promote the ticket"}
        end

      _ ->
        %{state | flash: "no ticket selected"}
    end
  end

  defp ticket_row(t, blocked) do
    %{
      id: t.id,
      title: t.title,
      status: t.status,
      priority: t.priority,
      assignee: t.assignee,
      blocked?: MapSet.member?(blocked, t.id)
    }
  end

  # The workspace whose tickets/notes the board shows: the active one (a stale key falls back to
  # the first workspace via active_workspace_id/1).
  defp board_workspace_id(state), do: Space.active_workspace_id(state)

  @doc """
  Move the selected ticket up or down within its column (`J`/`K`), persisting the board order.
  A card at the end of its column simply stays there — the flash says so rather than nothing
  happening for no visible reason.
  """
  @spec reorder_selected_ticket(map(), :up | :down) :: map()
  def reorder_selected_ticket(state, direction) do
    case selected_ticket(state, ticket_columns(state)) do
      %{id: id} = ticket ->
        _ = Safe.value(fn -> Tickets.reorder(ticket, direction) end, nil)
        %{state | flash: "ticket ##{id} moved #{direction}", board_cursor: follow(state.board_cursor, direction)}

      _ ->
        %{state | flash: "no ticket selected"}
    end
  end

  @doc """
  Open the "blocked by…" menu over the selected card (`b`). The menu is placed at the board rather
  than at a click, so it appears where the eye already is.
  """
  @spec open_blocker_menu(map()) :: map()
  def open_blocker_menu(state) do
    id = board_workspace_id(state)

    case selected_ticket(state, ticket_columns(state)) do
      %{} = ticket ->
        others = Safe.value(fn -> id && Tickets.in_workspace(id) end, nil) || []
        blocking = Safe.value(fn -> Tickets.blockers(ticket.id) end, nil) || []
        menu = Console.Cockpit.Author.blocker_menu(ticket, others, blocking, div(state.w, 3), div(state.h, 4))
        %{state | menu: menu}

      _ ->
        %{state | flash: "no ticket selected"}
    end
  end

  # The cursor follows the card it just moved, clamped — otherwise a reorder leaves the highlight
  # on whatever swapped INTO the old row, and a second press moves the wrong ticket.
  defp follow({col, row}, :up), do: {col, max(row - 1, 0)}
  defp follow({col, row}, :down), do: {col, row + 1}
end
