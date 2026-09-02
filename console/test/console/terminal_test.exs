defmodule Console.TerminalTest do
  @moduledoc """
  The embedded terminal (design §4) — a real PTY through Ghostty's VT engine, not a capture. These
  drive a live child and read its screen back, so they exercise the actual native loop.
  """
  use ExUnit.Case, async: true

  alias Console.Cockpit
  alias Console.Terminal

  test "runs a command in a real PTY, pings on output, reads the screen back with color" do
    {:ok, t} =
      Terminal.start_link(
        cmd: "/bin/bash",
        args: ["-c", "printf 'hi \\033[31mred\\033[0m done\\r\\n'; sleep 0.2"],
        cols: 40,
        rows: 4,
        notify: self()
      )

    # the cockpit repaints on this ping, not on a timer
    assert_receive {Terminal, ^t, :updated}, 2000
    # let the rest of the line land
    Process.sleep(120)

    rows = Terminal.cells(t)
    # reconstruct row 0's visible text from the cell grid (the render path reads cells, not snapshot)
    text =
      (Enum.at(rows, 0) || [])
      |> Enum.map_join(fn {g, _fg, _bg, _flags} -> if g == "", do: " ", else: g end)
      |> String.trim_trailing()

    assert text =~ "hi red done"

    # the ANSI red survives as a real RGB fg on the cells (a capture-pane view lost color)
    reds = rows |> List.flatten() |> Enum.filter(fn {g, fg, _bg, _flags} -> g == "r" and fg != nil end)
    assert reds != [], "expected the red run to carry an RGB foreground"
  end

  test "resize/3 does not crash the session (emulator + PTY both resized)" do
    {:ok, t} = Terminal.start_link(cmd: "/bin/cat", cols: 40, rows: 4, notify: self())
    assert :ok = Terminal.resize(t, 80, 24)
    # still answering after the resize
    assert is_list(Terminal.cells(t))
  end

  test "render_state/1 gives the renderer everything at once: cells + a real cursor" do
    {:ok, t} = Terminal.start_link(cmd: "/bin/cat", cols: 40, rows: 4, notify: self())
    state = Terminal.render_state(t)
    assert is_list(state.cells)
    # a cursor with a position + visibility so the embedded terminal shows where you type
    assert %{x: _, y: _, visible: _} = state.cursor
  end

  test "a {:pty_write, _} query response from the emulator is written back to the PTY, never dropped" do
    # cat echoes stdin, so if the query response reaches the PTY it comes back as screen output.
    {:ok, t} = Terminal.start_link(cmd: "/bin/cat", cols: 40, rows: 4, notify: self())
    send(t, {:pty_write, "echoed\r\n"})
    assert_receive {Terminal, ^t, :updated}, 2000
    Process.sleep(80)

    text = t |> Terminal.cells() |> List.flatten() |> Enum.map_join(fn {g, _, _, _} -> g end)
    assert text =~ "echoed"
  end

  describe "wheel/5 — the pure routing seams" do
    test "wheel_button maps up→:four (xterm button 4), down→:five (button 5)" do
      assert Terminal.wheel_button(:up) == :four
      assert Terminal.wheel_button(:down) == :five
    end

    test "scroll_delta: up is negative (into scrollback history), down is positive (newer)" do
      assert Terminal.scroll_delta(:up, 3) == -3
      assert Terminal.scroll_delta(:down, 3) == 3
    end

    test "sgr_mouse_bytes encodes wheel/click at the CORRECT cell, not the NIF's pixel-divided cell" do
      # The bug: the ghostty NIF treats x,y as PIXELS and divides by a hardcoded 10x20 cell grid,
      # so a wheel at cell (40,12) encoded as (5,1) and tmux scrolled the wrong pane. SGR is
      # encoded in cell space here, so (40,12) -> 1-indexed (41,13). Cb 64 = wheel-up, 65 = down.
      assert Terminal.sgr_mouse_bytes(:press, :four, [], 40, 12) == "\e[<64;41;13M"
      assert Terminal.sgr_mouse_bytes(:press, :five, [], 40, 12) == "\e[<65;41;13M"

      # A left click is a press (capital M) + release (lowercase m) pair at the same cell.
      assert Terminal.sgr_mouse_bytes(:press, :left, [], 0, 0) == "\e[<0;1;1M"
      assert Terminal.sgr_mouse_bytes(:release, :left, [], 0, 0) == "\e[<0;1;1m"

      # A drag is a motion (Cb + the +32 motion bit) — tmux extends the selection instead of
      # starting a new one. Left (0) + motion (32) = 32. `:move` is the atom raxol's InputParser
      # actually emits for a button-motion report; `:motion` is accepted for rename-tolerance.
      assert Terminal.sgr_mouse_bytes(:move, :left, [], 5, 2) == "\e[<32;6;3M"
      assert Terminal.sgr_mouse_bytes(:motion, :left, [], 5, 2) == "\e[<32;6;3M"

      # Modifier bits: shift +4, alt +8, ctrl +16 (ctrl+click at cell 7,3 -> Cb 16).
      assert Terminal.sgr_mouse_bytes(:press, :left, [:ctrl], 7, 3) == "\e[<16;8;4M"
    end
  end

  describe "wheel/5 — the live branch" do
    test "scrolls the VT scrollback when the program hasn't enabled mouse tracking" do
      # 30 lines into a 4-row terminal ⇒ scrollback. The child stays alive long enough to scroll.
      {:ok, t} =
        Terminal.start_link(
          cmd: "/bin/bash",
          args: ["-c", "for i in $(seq 1 30); do printf 'line %d\n' $i; done; sleep 1"],
          cols: 40,
          rows: 4,
          notify: self()
        )

      assert_receive {Terminal, ^t, :updated}, 2000
      Process.sleep(250)

      base = Terminal.render_state(t).scrollbar.offset
      assert :scrolled = Terminal.wheel(t, :up, 3, 0, 0)
      up = Terminal.render_state(t).scrollbar.offset
      assert up != base
      # wheel back down by the same amount restores the viewport
      assert :scrolled = Terminal.wheel(t, :down, 3, 0, 0)
      assert Terminal.render_state(t).scrollbar.offset == base
    end

    test "forwards a mouse event to the PTY when the program enabled mouse tracking" do
      # A mouse-aware TUI enables tracking by writing \e[?1000h to its stdout; the PTY delivers that
      # to the emulator as :data. Send it directly (the realistic path) and assert the branch taken.
      {:ok, t} = Terminal.start_link(cmd: "/bin/cat", cols: 40, rows: 4, notify: self())
      send(t, {:data, "\e[?1000h"})
      assert_receive {Terminal, ^t, :updated}, 1000

      assert Terminal.mouse_modes(t).tracking
      assert :forwarded = Terminal.wheel(t, :up, 3, 5, 5)
    end
  end

  describe "Kitty keyboard protocol — the embedded terminal speaks pi's input dialect" do
    # pi's TUI decodes Kitty sequences: shift+enter (\e[13;2u) is tui.input.newLine, ctrl+v
    # (\e[118;5u) is app.clipboard.pasteImage. init enables Kitty (\e[>1u) on the emulator so
    # input_key emits them; without Kitty it emits modifyOtherKeys (\e[27;2;13~) which pi drops.
    test "shift+enter encodes to \e[13;2u — the newline binding pi expects" do
      {:ok, t} = Terminal.start_link(cmd: "/bin/cat", cols: 40, rows: 4, notify: self())
      ev = Cockpit.ghostty_key(%{key: :enter, shift: true})
      assert {:ok, "\e[13;2u"} = Terminal.encode_key(t, ev)
    end

    test "ctrl+v encodes to \e[118;5u — the paste-image binding pi expects" do
      {:ok, t} = Terminal.start_link(cmd: "/bin/cat", cols: 40, rows: 4, notify: self())
      ev = Cockpit.ghostty_key(%{key: :char, char: "v", ctrl: true})
      assert {:ok, "\e[118;5u"} = Terminal.encode_key(t, ev)
    end

    test "ctrl+shift+c encodes to \e[99;6u — copy, not collapsed to ^C (0x03)" do
      {:ok, t} = Terminal.start_link(cmd: "/bin/cat", cols: 40, rows: 4, notify: self())
      ev = Cockpit.ghostty_key(%{key: :char, char: "c", ctrl: true, shift: true})
      assert {:ok, "\e[99;6u"} = Terminal.encode_key(t, ev)
    end

    test "a plain unmodified key still encodes as its bare char (Kitty doesn't disturb typing)" do
      {:ok, t} = Terminal.start_link(cmd: "/bin/cat", cols: 40, rows: 4, notify: self())
      ev = Cockpit.ghostty_key(%{key: :char, char: "a"})
      assert {:ok, "a"} = Terminal.encode_key(t, ev)
    end
  end
end
