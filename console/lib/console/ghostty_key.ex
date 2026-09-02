defmodule Console.GhosttyKey do
  @moduledoc """
  The translation a forwarded key crosses to reach an embedded terminal: a raxol key event
  (`%{key: :char, char: "v", ctrl: true}`) → a `Ghostty.KeyEvent` the emulator encodes to PTY
  bytes. A wrong mapping is a key that misfires; a missing one is a key that vanishes.
  """

  alias Ghostty.KeyEvent

  @doc "A console key event as a `Ghostty.KeyEvent`, or nil for a key with no mapping (dropped, never misdelivered)."
  @spec from_event(map()) :: KeyEvent.t() | nil
  def from_event(%{key: :char, char: c} = ev),
    do: %KeyEvent{key: char_key(c), utf8: c, mods: mods(ev), unshifted_codepoint: unshifted_codepoint(c)}

  def from_event(%{key: :up} = ev), do: %KeyEvent{key: :arrow_up, mods: mods(ev)}
  def from_event(%{key: :down} = ev), do: %KeyEvent{key: :arrow_down, mods: mods(ev)}
  def from_event(%{key: :left} = ev), do: %KeyEvent{key: :arrow_left, mods: mods(ev)}
  def from_event(%{key: :right} = ev), do: %KeyEvent{key: :arrow_right, mods: mods(ev)}

  def from_event(%{key: k} = ev)
      when k in [:enter, :tab, :backspace, :delete, :escape, :space, :home, :end, :page_up, :page_down],
      do: %KeyEvent{key: k, mods: mods(ev)}

  def from_event(_key), do: nil

  # a-z (and A-Z → the lowercase key + a shift mod via utf8), 0-9 → :digit_N; anything else is
  # carried by utf8 alone under :unidentified.
  # to_atom, NOT to_existing_atom: the char set is bounded (a-z, A-Z, 0-9 → 36 known atoms), so there's
  # no atom-table-exhaustion risk — and to_existing_atom CRASHES the cockpit on any letter whose atom
  # wasn't already interned (e.g. pressing "o" when :o exists nowhere as a literal). The from_event
  # unit tests masked this: their :x/:c/:v literals intern exactly those atoms at compile time.
  defp char_key(<<cp>>) when cp in ?a..?z, do: String.to_atom(<<cp>>)
  defp char_key(<<cp>>) when cp in ?A..?Z, do: String.to_atom(<<cp + 32>>)
  defp char_key(<<cp>>) when cp in ?0..?9, do: String.to_atom("digit_#{<<cp>>}")
  defp char_key(_c), do: :unidentified

  # The Kitty encoder needs the unshifted codepoint to build \e[<cp>;<mods>u for a modified
  # printable (ctrl+v → \e[118;5u); without it modifiers are dropped (ctrl+v → "v"). Letters use
  # their lowercase codepoint. KNOWN LIMIT: a shifted symbol (shift+2 → "@") can't be recovered
  # here (the host keyboard layout is gone by this layer) — no current binding hits that path.
  defp unshifted_codepoint(c) do
    c |> String.downcase() |> String.to_charlist() |> List.first() || 0
  end

  defp mods(ev) do
    [{:ctrl, ev[:ctrl]}, {:alt, ev[:alt]}, {:shift, ev[:shift]}]
    |> Enum.filter(fn {_mod, on?} -> on? end)
    |> Enum.map(fn {mod, _} -> mod end)
  end
end
