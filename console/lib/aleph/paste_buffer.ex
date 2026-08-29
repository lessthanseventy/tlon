defmodule Console.PasteBuffer do
  @moduledoc """
  The bracketed-paste buffer state machine (pure — the cockpit holds the buffer in its state, this
  module owns the transitions). aleph enables `\\e[?2004h` on the host tty, so ghostty wraps a paste
  in `\\e[200~…\\e[201~`; raxol's self-healed InputParser surfaces the markers as paste-start /
  paste-end events and the content between them as ordinary `:key` events. On paste-start the
  cockpit starts a buffer; while pasting, content keys accumulate here (a newline stays `\\n`, NOT
  `:enter`); on paste-end the whole buffer is forwarded to the center terminal wrapped back in the
  markers via `Console.Terminal.feed/2` — tmux passes bracketed paste through, and pi honors it as one
  multi-line paste instead of N submits.
  """

  # The bracketed-paste markers, re-emitted around the accumulated content when forwarding to the
  # center terminal. Byte-identical to the host-mode enable/disable in Console.Cockpit.
  @paste_enable "\e[200~"
  @paste_disable "\e[201~"

  @doc "Start collecting a paste: an empty buffer."
  @spec start() :: String.t()
  def start, do: ""

  @doc """
  Accumulate one decoded key event into the buffer. A printable char appends its text; a newline
  stays `\\n` (NOT `:enter`); a tab stays `\\t`. Anything else (arrows, modifiers, …) is skipped —
  paste content is raw bytes, so only the byte-carrying keys belong in the buffer, and a modified
  char (ctrl/alt/shift) is a real keypress, not paste content.
  """
  @spec accumulate(String.t(), map()) :: String.t()
  def accumulate(buffer, %{key: :char, char: c} = key)
      when is_binary(c) and not is_map_key(key, :ctrl) and not is_map_key(key, :alt) and not is_map_key(key, :shift),
      do: buffer <> c

  def accumulate(buffer, %{key: :enter}), do: buffer <> "\n"
  def accumulate(buffer, %{key: :tab}), do: buffer <> "\t"
  def accumulate(buffer, %{key: :space}), do: buffer <> " "
  def accumulate(buffer, _key), do: buffer

  @doc "Finish a paste: wrap the accumulated content in the bracketed-paste markers for forwarding."
  @spec finish(String.t()) :: String.t()
  def finish(buffer), do: @paste_enable <> buffer <> @paste_disable
end
