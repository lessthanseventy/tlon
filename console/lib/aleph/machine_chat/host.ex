defmodule Console.MachineChat.Host do
  @moduledoc """
  The machine-chat interaction state and its pure reducers — the brain the `aleph.machine_chat`
  termbox loop wraps. Kept free of IO so it's headlessly testable (aleph's law: unit-test the
  pure seams, never the TTY loop).

  Slack-shaped (the 2026-08 reshape): the surface is a THREADS rail + ONE open conversation, so
  the state's core is `selected_id` — a thread **id**, not a list index, so a poll that reorders
  the rail (activity resorts it) can never silently move you to a different conversation.

  State:
    - `blocks`      — the `Server.Channel.machine_threads/1` read model (most-recent-activity first).
    - `selected_id` — the OPEN thread's id (the center conversation + the composer's reply target).
    - `seen`        — thread_id => message count seen; unread badge = messages beyond it.
    - `input`       — the composer draft (owned here so Esc/mode churn can never eat it).
    - `intent`      — `:reply` (into the open thread) or `:new` (Ctrl+N — the next Enter opens a
      fresh task thread).
    - `quit`        — set by `:quit`; the loop tears down on it.
  """

  @type state :: %{
          blocks: [map()],
          selected_id: term() | nil,
          seen: %{optional(term()) => non_neg_integer()},
          input: String.t(),
          intent: :reply | :new,
          quit: boolean()
        }

  @doc "A fresh interaction state before the first poll."
  @spec new() :: state()
  def new, do: %{blocks: [], selected_id: nil, seen: %{}, input: "", intent: :reply, quit: false}

  @doc """
  Fold a fresh poll into the state. The selection sticks to its thread ID across reorders; a
  vanished (or never-set) selection falls to `root_id` — the rollup home, the primary surface —
  else the most recent thread. The open thread is always marked seen (you're looking at it).
  """
  @spec merge(state(), [map()], term() | nil) :: state()
  def merge(state, blocks, root_id \\ nil) do
    selected =
      cond do
        present?(blocks, state.selected_id) -> state.selected_id
        present?(blocks, root_id) -> root_id
        true -> blocks |> List.first() |> thread_id()
      end

    mark_seen(%{state | blocks: blocks, selected_id: selected})
  end

  @doc "The rail order: the root thread pinned first, then the rest as polled (activity, newest first)."
  @spec ordered([map()], term() | nil) :: [map()]
  def ordered(blocks, root_id) do
    case Enum.split_with(blocks, &(thread_id(&1) == root_id)) do
      {[root], rest} -> [root | rest]
      {_none, rest} -> rest
    end
  end

  @doc "Move the rail selection by `delta` within `ordered/2`'s order, clamped; marks the target seen."
  @spec select(state(), integer(), term() | nil) :: state()
  def select(state, delta, root_id) do
    rows = ordered(state.blocks, root_id)
    count = length(rows)

    if count == 0 do
      state
    else
      i = Enum.find_index(rows, &(thread_id(&1) == state.selected_id)) || 0
      target = rows |> Enum.at(clamp(i + delta, count)) |> thread_id()
      mark_seen(%{state | selected_id: target})
    end
  end

  @doc "The open (selected) thread's block, or nil."
  @spec selected_block(state()) :: map() | nil
  def selected_block(state), do: Enum.find(state.blocks, &(thread_id(&1) == state.selected_id))

  @doc "Unread count for a block: messages beyond the seen mark (the open thread always reads 0)."
  @spec unread(state(), map()) :: non_neg_integer()
  def unread(state, block) do
    id = thread_id(block)

    if id == state.selected_id,
      do: 0,
      else: max(length(block.messages) - Map.get(state.seen, id, 0), 0)
  end

  @doc "Advance the interaction state for one key intent. Unknown intents pass through unchanged."
  @spec handle_key(state(), atom()) :: state()
  def handle_key(state, {:putc, c}), do: %{state | input: state.input <> c}

  def handle_key(state, :backspace),
    do: %{state | input: String.slice(state.input, 0, max(String.length(state.input) - 1, 0))}

  def handle_key(state, :clear), do: %{state | input: ""}
  def handle_key(state, :new_task), do: %{state | intent: :new}
  # Esc cancels the new-task intent; it NEVER clears the draft (Ctrl+U is the deliberate clear).
  def handle_key(state, :cancel), do: %{state | intent: :reply}
  def handle_key(state, :quit), do: %{state | quit: true}
  def handle_key(state, _other), do: state

  @doc "Clear the composer and drop back to reply intent — the post-submit reset."
  @spec after_submit(state()) :: state()
  def after_submit(state), do: %{state | input: "", intent: :reply}

  defp mark_seen(%{selected_id: nil} = state), do: state

  defp mark_seen(state) do
    case selected_block(state) do
      nil -> state
      block -> %{state | seen: Map.put(state.seen, state.selected_id, length(block.messages))}
    end
  end

  defp present?(_blocks, nil), do: false
  defp present?(blocks, id), do: Enum.any?(blocks, &(thread_id(&1) == id))

  defp thread_id(nil), do: nil
  defp thread_id(%{thread: %{id: id}}), do: id

  defp clamp(_index, 0), do: 0
  defp clamp(index, count), do: index |> min(count - 1) |> max(0)
end
