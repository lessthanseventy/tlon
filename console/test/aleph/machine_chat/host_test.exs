defmodule Console.MachineChat.HostTest do
  @moduledoc """
  The machine-chat interaction state (the Slack reshape): id-keyed selection that survives rail
  reorders, unread accounting, the composer draft, and the reply/new intent.
  """
  use ExUnit.Case, async: true

  alias Console.MachineChat.Host

  defp block(id, title, n_messages, state \\ "open") do
    %{
      thread: %{id: id, title: title, state: state},
      messages: List.duplicate(%{author: "pi", body: "m", created_at: nil}, n_messages)
    }
  end

  describe "merge/3 — selection is an ID, not an index" do
    test "first poll lands on the root thread when present, else the newest" do
      blocks = [block(3, "newest", 1), block(1, "root", 1)]
      assert Host.merge(Host.new(), blocks, 1).selected_id == 1
      assert Host.merge(Host.new(), blocks, nil).selected_id == 3
    end

    test "a reorder can't move the open conversation" do
      state = Host.merge(Host.new(), [block(1, "a", 1), block(2, "b", 1)], nil)
      assert state.selected_id == 1

      # b gains activity and jumps to the head — the selection stays on a.
      state = Host.merge(state, [block(2, "b", 5), block(1, "a", 1)], nil)
      assert state.selected_id == 1
    end

    test "a vanished selection falls back to root, else newest" do
      state = %{Host.merge(Host.new(), [block(9, "gone", 1)], nil) | selected_id: 9}
      assert Host.merge(state, [block(4, "new", 1), block(1, "root", 1)], 1).selected_id == 1
    end
  end

  describe "ordered/2 + select/3 — rail order with the root pinned first" do
    test "root pins to the head; others keep poll (activity) order" do
      blocks = [block(3, "c", 1), block(1, "root", 1), block(2, "b", 1)]
      assert Enum.map(Host.ordered(blocks, 1), & &1.thread.id) == [1, 3, 2]
      assert Enum.map(Host.ordered(blocks, nil), & &1.thread.id) == [3, 1, 2]
    end

    test "select moves within the ordered rail and clamps at the ends" do
      state = Host.merge(Host.new(), [block(3, "c", 1), block(1, "root", 1), block(2, "b", 1)], 1)
      assert state.selected_id == 1

      state = Host.select(state, 1, 1)
      assert state.selected_id == 3

      state = state |> Host.select(1, 1) |> Host.select(1, 1) |> Host.select(1, 1)
      assert state.selected_id == 2

      assert Host.select(state, -3, 1).selected_id == 1
    end
  end

  describe "unread/2" do
    test "the open thread reads 0; others count messages past the seen mark" do
      state = Host.merge(Host.new(), [block(1, "open", 2), block(2, "other", 3)], nil)
      [open, other] = state.blocks

      assert Host.unread(state, open) == 0
      assert Host.unread(state, other) == 3

      # Visiting the other thread clears it; new messages afterwards count again.
      state = Host.select(state, 1, nil)
      assert state.selected_id == 2
      state = Host.merge(state, [block(1, "open", 2), block(2, "other", 5)], nil)
      [_open, other] = state.blocks
      assert Host.unread(state, other) == 0

      state = Host.select(state, -1, nil)
      state = Host.merge(state, [block(1, "open", 2), block(2, "other", 7)], nil)
      [_open, other] = state.blocks
      assert Host.unread(state, other) == 2
    end
  end

  describe "composer + intent" do
    test "typing/backspace/clear build the draft; Esc cancels intent but NEVER the draft" do
      state =
        Host.new()
        |> Host.handle_key({:putc, "h"})
        |> Host.handle_key({:putc, "i"})

      assert state.input == "hi"
      assert Host.handle_key(state, :backspace).input == "h"

      state = Host.handle_key(state, :new_task)
      assert state.intent == :new

      state = Host.handle_key(state, :cancel)
      assert state.intent == :reply
      assert state.input == "hi"

      assert Host.handle_key(state, :clear).input == ""
    end

    test "after_submit clears the draft and drops back to reply" do
      state = Host.new() |> Host.handle_key({:putc, "x"}) |> Host.handle_key(:new_task) |> Host.after_submit()
      assert state.input == ""
      assert state.intent == :reply
    end
  end
end
