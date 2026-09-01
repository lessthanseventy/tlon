defmodule Console.GraphicsKittyTest do
  # kitty?/0 reads the OS env, so this runs sync + saves/restores the vars it touches.
  use ExUnit.Case, async: false

  alias Console.Graphics

  @vars ~w(TERM TERM_PROGRAM KITTY_WINDOW_ID GHOSTTY_RESOURCES_DIR)

  setup do
    saved = Map.new(@vars, &{&1, System.get_env(&1)})
    Enum.each(@vars, &System.delete_env/1)

    on_exit(fn ->
      Enum.each(saved, fn
        {k, nil} -> System.delete_env(k)
        {k, v} -> System.put_env(k, v)
      end)
    end)

    :ok
  end

  test "kitty and ghostty are both detected as graphics-capable" do
    System.put_env("TERM", "xterm-256color")
    refute Graphics.kitty?()

    System.put_env("KITTY_WINDOW_ID", "1")
    assert Graphics.kitty?()
    System.delete_env("KITTY_WINDOW_ID")

    # ghostty: reports xterm-ghostty / TERM_PROGRAM=ghostty / GHOSTTY_* but no kitty markers.
    System.put_env("TERM", "xterm-ghostty")
    assert Graphics.kitty?()

    System.put_env("TERM", "xterm-256color")
    System.put_env("TERM_PROGRAM", "ghostty")
    assert Graphics.kitty?()

    System.delete_env("TERM_PROGRAM")
    System.put_env("GHOSTTY_RESOURCES_DIR", "/usr/share/ghostty")
    assert Graphics.kitty?()
  end
end
