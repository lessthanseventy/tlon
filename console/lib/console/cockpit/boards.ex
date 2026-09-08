defmodule Console.Cockpit.Boards do
  @moduledoc """
  The full-screen Tickets and Notes boards: what covers the frame while one is open, and the
  Tickets kanban's keys (cursor, advance, file, promote-to-thread). Reads/writes go through
  `Server.Tickets` / `Server.Notes`, degraded by `Console.Safe`; a handler answers the next
  cockpit state and the cockpit repaints it.
  """

  alias Console.Panel
  alias Console.Reads
  alias Console.Safe
  alias Console.Server.Channel
  alias Console.Server.Tickets
  alias Console.Space
  alias Console.Staffing

  @doc "The full-screen board's placements: a frame-covering border + the board panel (painted after the layout, before the menu)."
  def board_placements(%{board: nil}), do: []

  def board_placements(%{board: kind, w: w, h: h} = state) do
    rect = %{x: 0, y: 0, w: w, h: max(h - 1, 2)}
    inset = %{x: 2, y: 1, w: max(w - 4, 1), h: max(h - 3, 1)}
    {panel, data, title} = board_content(kind, state)

    [
      {Panel.Border, %{focused: true, digit: nil, title: "#{title}  ·  esc to close", tabs: nil, hint: nil}, rect},
      {panel, data, inset}
    ]
  end

  defp board_content(:tickets, state) do
    id = board_workspace_id(state)
    tickets = Safe.value(fn -> id && id |> Tickets.in_workspace() |> Enum.map(&ticket_row/1) end, nil) || []

    {Panel.TicketBoard, %{tickets: tickets, cursor: state.board_cursor},
     "TICKETS · h/l·j/k move · p advance · n new · ⏎ promote"}
  end

  defp board_content(:notes, state) do
    id = board_workspace_id(state)
    notes = Safe.value(fn -> id && Console.Server.Notes.for_scope("workspace", id) end, nil) || []
    {Panel.NoteBoard, %{notes: notes}, "NOTES"}
  end

  @ticket_statuses ~w(backlog todo doing done)

  @doc """
  The Tickets kanban keys: h/l/j/k move the `{col, row}` cursor, `p` advances the selected ticket's
  status, `n` files a new one (opens the `:new_ticket` input), Enter promotes it to a thread. The
  Notes board only knows `n`. Anything else is `:ignore`d (Esc is the cockpit's — it closes).
  """
  @spec handle_board_key(map(), map()) :: map() | :ignore
  def handle_board_key(%{key: :char, char: "n"}, %{board: :tickets} = state),
    do: %{state | input: %{kind: :new_ticket, buffer: "", cursor: 0}}

  def handle_board_key(%{key: :char, char: "n"}, %{board: :notes} = state),
    do: %{state | input: %{kind: :new_note, buffer: "", cursor: 0}}

  def handle_board_key(%{key: :char, char: c}, %{board: :tickets} = state) when c in ~w(h l j k),
    do: %{state | board_cursor: move_grid(state.board_cursor, c, ticket_columns(state))}

  def handle_board_key(%{key: :char, char: "p"}, %{board: :tickets} = state), do: advance_selected_ticket(state)

  def handle_board_key(%{key: :enter}, %{board: :tickets} = state), do: promote_selected_ticket(state)

  def handle_board_key(_key, _state), do: :ignore

  # The active workspace's tickets grouped into kanban columns (structs — the render maps to rows off
  # the same in_workspace order, so the cursor indexes the same grid).
  defp ticket_columns(state) do
    id = board_workspace_id(state)
    tickets = Safe.value(fn -> id && Tickets.in_workspace(id) end, nil) || []
    Console.Panel.TicketBoard.by_column(tickets)
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

  defp advance_selected_ticket(state) do
    case selected_ticket(state, ticket_columns(state)) do
      %{status: status} = ticket ->
        next = next_status(status)
        _ = Safe.value(fn -> Tickets.update(ticket, %{status: next}) end, nil)
        %{state | flash: "ticket ##{ticket.id} → #{next}"}

      _ ->
        state
    end
  end

  defp promote_selected_ticket(state) do
    case selected_ticket(state, ticket_columns(state)) do
      %{id: id, title: title} = ticket ->
        with {:ok, thread} <-
               Channel.open_thread(%{title: title, workspace_id: Space.active_workspace_id(state), scope: "machine"}),
             {:ok, _} <- Safe.value(fn -> Tickets.promote(ticket, thread.id) end, nil) do
          _ = Staffing.spawn_onto(thread.id, Reads.center_dims(state))
          %{state | board: nil, focused_id: thread.id, flash: "promoted ticket ##{id} → thread"}
        else
          _ -> %{state | flash: "couldn't promote the ticket"}
        end

      _ ->
        state
    end
  end

  defp ticket_row(t), do: %{id: t.id, title: t.title, status: t.status, priority: t.priority, assignee: t.assignee}

  # The workspace whose tickets/notes the board shows: the active one, or the default (Orbis falls
  # back to the first workspace via active_workspace_id/1).
  defp board_workspace_id(state), do: Space.active_workspace_id(state)
end
