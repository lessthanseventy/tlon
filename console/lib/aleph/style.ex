defmodule Console.Style do
  @moduledoc """
  The one palette. Panels render in **semantic styles** (`:header`, `:warm`, `:selected`, …),
  never raw hex — so the whole cockpit reads as one surface and a re-theme is one edit here,
  not a hunt through every panel (design §3: panels are thin; presentation is centralized).

  Colors are 24-bit RGB for termbox2's `TB_OUTPUT_TRUECOLOR` (see `Mix.Tasks.Console.Run`);
  `@bg` is `0x000000`, which truecolor maps to the terminal's own background.
  """

  @bg 0x000000

  # Green is the body (content/strings); amber is reserved for chrome (titles, labels, warm dots)
  # so it pops instead of tiring the eye everywhere. Pink flags agents, burnt orange marks
  # structure, violet marks selection.
  @sel 0x5B00AE

  # The two canonical phosphors: green #33FF00 (body) and amber #FFB000 (chrome).
  @green 0x33FF00
  @amber 0xFFB000

  # Chip fields carry dark text, so their background must be BRIGHT to pop — chrome amber (#FFB000)
  # is a burnt mid-tone that leaves black text looking muddy next to the green chip. #FFD000 lifts
  # the field to ~the green's luminance (black-on-it 14.3:1 vs 11.5) while staying gold, not lime.
  @amber_chip 0xFFD000

  # Chip TEXT ink. Must NOT be 0x000000: under TB_OUTPUT_TRUECOLOR color 0 is termbox's "default"
  # sentinel — fine as a background (→ terminal bg), but as a FOREGROUND it falls through to the
  # terminal's default fg (light), so `{@bg, chip}` rendered as white-on-chip, not the intended
  # black. A non-zero near-black keeps the dark text the bright fields were tuned for.
  @ink 0x0A0A0A

  @colors %{
    normal: {@green, @bg},
    header: {@amber, @bg},
    label: {@amber, @bg},
    accent: {0xE0218A, @bg},
    # The operator's voice in chat — pink, its OWN key (not :accent) so re-theming the operator
    # doesn't entangle with the cursor/thinking chrome.
    operator: {0xE0218A, @bg},
    warm: {@amber, @bg},
    dim: {0x9A803F, @bg},
    separator: {0xB5651D, @bg},
    selected: {0xFFF4C2, @sel},
    selected_accent: {0xFFFFFF, @sel},
    # Status-line chips: inverse-video tabs on the phosphors, dark text on a bright field.
    tab: {0xFFFFFF, @sel},
    stat: {@ink, @amber_chip},
    stat_live: {@ink, @green},
    # LOCK's chip — total keyboard passthrough deserves the loudest, most alarming color on hand.
    stat_warn: {@ink, 0xFF5555},
    # A commit diff in MAIN (Commits pane detail): additions green, deletions red, hunk headers
    # cyan. File/meta lines borrow chrome amber (:label) and :dim from above.
    diff_add: {@green, @bg},
    diff_del: {0xFF5555, @bg},
    diff_hunk: {0x33C7FF, @bg},
    # Semantic event styles (the funes activity feed + footer pulse): a fact banked or a check
    # passing reads body-green, a failure diff-red, a posted message diff-cyan; work landed and
    # an issue/question raised both read chrome amber — icon carries the done/warn distinction,
    # not color.
    event_ok: {@green, @bg},
    event_bad: {0xFF5555, @bg},
    event_msg: {0x33C7FF, @bg},
    event_done: {@amber, @bg},
    event_warn: {@amber, @bg}
  }

  @doc """
  The `{fg, bg}` truecolor pair for a run's style. A semantic atom resolves from the palette
  (unknown → `:normal`); an explicit `{:rgb, fg, bg}` passes its own 24-bit colours through — the
  path the embedded terminal uses, where each cell carries its own colour from the VT engine.
  """
  @spec fg_bg(atom() | {:rgb, non_neg_integer(), non_neg_integer()}) :: {non_neg_integer(), non_neg_integer()}
  def fg_bg({:rgb, fg, bg}), do: {fg, bg}
  def fg_bg(style), do: Map.get(@colors, style, @colors.normal)

  @doc "The default background (terminal-native black under truecolor)."
  def bg, do: @bg
end
