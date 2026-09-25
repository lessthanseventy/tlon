defmodule Console.GhosttyKeyTest do
  use ExUnit.Case, async: true

  alias Console.GhosttyKey
  alias Ghostty.KeyEvent

  test "a printable char carries its utf8 and its key atom" do
    ev = GhosttyKey.from_event(%{key: :char, char: "x"})
    assert %KeyEvent{key: :x, utf8: "x"} = ev
  end

  test "Ctrl+C maps to key :c with a ctrl mod — the emulator encodes it to ^C" do
    ev = GhosttyKey.from_event(%{key: :char, char: "c", ctrl: true})
    assert ev.key == :c
    assert :ctrl in ev.mods
  end

  test "Esc, Enter, Tab, Backspace map straight through" do
    assert %KeyEvent{key: :escape} = GhosttyKey.from_event(%{key: :escape})
    assert %KeyEvent{key: :enter} = GhosttyKey.from_event(%{key: :enter})
    assert %KeyEvent{key: :tab} = GhosttyKey.from_event(%{key: :tab})
    assert %KeyEvent{key: :backspace} = GhosttyKey.from_event(%{key: :backspace})
  end

  test "arrows map to the ghostty arrow_* keys" do
    assert %KeyEvent{key: :arrow_up} = GhosttyKey.from_event(%{key: :up})
    assert %KeyEvent{key: :arrow_down} = GhosttyKey.from_event(%{key: :down})
    assert %KeyEvent{key: :arrow_left} = GhosttyKey.from_event(%{key: :left})
    assert %KeyEvent{key: :arrow_right} = GhosttyKey.from_event(%{key: :right})
  end

  test "a digit maps to its :digit_N key" do
    assert %KeyEvent{key: :digit_7, utf8: "7"} = GhosttyKey.from_event(%{key: :char, char: "7"})
  end

  test "an unmappable key is nil — dropped, never misdelivered" do
    assert GhosttyKey.from_event(%{key: :f5}) == nil
  end

  test "EVERY letter and digit maps without crashing (atom-intern safety)" do
    # Iterate by codepoint so no literal key atom (`:o`, `:p`, …) is interned by this test — the trap
    # that let `to_existing_atom` crash the cockpit on a keypress whose atom existed nowhere. With
    # `to_atom` every printable maps; with `to_existing_atom` the first un-interned letter raises.
    for c <- Enum.map(?a..?z, &(<<>> / 1)) ++ Enum.map(?A..?Z, &(<<>> / 1)) ++ Enum.map(?0..?9, &(<<>> / 1)) do
      assert %KeyEvent{utf8: ^c} = GhosttyKey.from_event(%{key: :char, char: c})
    end
  end

  describe "Kitty keyboard encoding contract" do
    # pi's TUI decodes Kitty sequences (\e[13;2u for shift+enter, \e[118;5u for ctrl+v). The Kitty
    # encoder needs the key's UNSHIFTED codepoint to build \e[<cp>;<mods>u for a modified printable;
    # without it the modifier is dropped (ctrl+v → "v") and pi's binding misfires.
    test "a char key carries its unshifted codepoint so modifiers survive Kitty encoding" do
      ev = GhosttyKey.from_event(%{key: :char, char: "v", ctrl: true})
      assert %KeyEvent{key: :v, utf8: "v", mods: [:ctrl], unshifted_codepoint: ?v} = ev
    end

    test "an uppercase letter's unshifted codepoint is the lowercase codepoint (shift+v → ?v)" do
      ev = GhosttyKey.from_event(%{key: :char, char: "V", shift: true})
      assert %KeyEvent{key: :v, utf8: "V", mods: [:shift], unshifted_codepoint: ?v} = ev
    end

    test "a digit carries its own codepoint" do
      ev = GhosttyKey.from_event(%{key: :char, char: "5"})
      assert ev.unshifted_codepoint == ?5
    end
  end
end
