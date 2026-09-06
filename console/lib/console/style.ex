defmodule Console.Style do
  @moduledoc """
  The one palette. Panels render in **semantic styles** (`:header`, `:warm`, `:selected`, …),
  never raw hex — so the whole cockpit reads as one surface and a re-theme is one edit here,
  not a hunt through every panel (design §3: panels are thin; presentation is centralized).

  Colors are 24-bit RGB for termbox2's `TB_OUTPUT_TRUECOLOR` (see `Mix.Tasks.Console.Run`);
  `@bg` is `0x000000`, which truecolor maps to the terminal's own background. The values
  themselves are `Console.Palette` — generated, shared with every other surface on the box.
  """

  # Every hue comes from Console.Palette (generated from modules/desktop/theme/palette.nix —
  # the one palette the whole machine shares, plan doc §5b). The rule, same as the shell's:
  # body text AMBER on black; green is the LIVE highlight; pink flags agents/the operator;
  # cyan is keys/labels/code; lilac is secondary text; the active thing is inverse video
  # (amber field, near-black ink). Green used to be the body here — that was the drift.
  alias Console.Palette, as: P

  @bg P.bg()
  @amber P.amber()
  @green P.green()
  @cyan P.cyan()
  @pink P.pink()
  @lilac P.lilac()
  @red P.red()
  @dim P.dim()
  @sep P.sep()
  @sel P.sel()

  # Chip fields carry dark text, so their background must be BRIGHT to pop — body amber is a
  # burnt mid-tone that leaves black text muddy next to the green chip; the chip amber lifts
  # the field to ~the green's luminance (black-on-it 14.3:1 vs 11.5) while staying gold.
  @chip P.chip()

  # Chip TEXT ink. Must NOT be 0x000000: under TB_OUTPUT_TRUECOLOR color 0 is termbox's "default"
  # sentinel — fine as a background (→ terminal bg), but as a FOREGROUND it falls through to the
  # terminal's default fg (light), so `{@bg, chip}` rendered as white-on-chip, not the intended
  # black. A non-zero near-black keeps the dark text the bright fields were tuned for.
  @ink P.ink()

  @colors %{
    normal: {@amber, @bg},
    header: {@cyan, @bg},
    label: {@cyan, @bg},
    accent: {@pink, @bg},
    # The operator's voice in chat — pink, its OWN key (not :accent) so re-theming the operator
    # doesn't entangle with the cursor/thinking chrome.
    operator: {@pink, @bg},
    warm: {@amber, @bg},
    dim: {@dim, @bg},
    meta: {@lilac, @bg},
    separator: {@sep, @bg},
    selected: {P.cream(), @sel},
    selected_accent: {P.white(), @sel},
    # Status-line chips: inverse-video tabs, dark text on a bright field.
    tab: {P.white(), @sel},
    stat: {@ink, @chip},
    stat_live: {@ink, @green},
    # LOCK's chip — total keyboard passthrough deserves the loudest, most alarming color on hand.
    stat_warn: {@ink, @red},
    # A commit diff in MAIN (Commits pane detail): additions green, deletions red, hunk headers
    # cyan. File/meta lines borrow :label and :dim from above.
    diff_add: {@green, @bg},
    diff_del: {@red, @bg},
    diff_hunk: {@cyan, @bg},
    # Semantic event styles (the server activity feed + footer pulse): a fact banked or a check
    # passing reads live-green, a failure red, a posted message cyan; work landed and an
    # issue/question raised both read body amber — icon carries the done/warn distinction.
    event_ok: {@green, @bg},
    event_bad: {@red, @bg},
    event_msg: {@cyan, @bg},
    event_done: {@amber, @bg},
    event_warn: {@amber, @bg},
    # Slice D visual system — STATUS colors (the signal tier: card gutters + status dots).
    st_working: {P.green(), @bg},
    st_blocked: {P.red(), @bg},
    st_await: {P.pink(), @bg},
    st_open: {P.amber(), @bg},
    st_done: {P.moss(), @bg},
    st_idle: {P.dim(), @bg},
    # IDENTITY colors (the splash tier: same entity → same hue). Per coworker archetype, reused as
    # the workspace-hue cycle. surveyor cyan, builder green, reviewer amber, planner pink,
    # assistant violet.
    arch_surveyor: {P.cyan(), @bg},
    arch_builder: {P.green(), @bg},
    arch_reviewer: {P.amber(), @bg},
    arch_planner: {P.pink(), @bg},
    arch_assistant: {P.violet(), @bg},
    # Markdown rendering in the chat (Console.Markdown) — no bold attr in this palette, so
    # emphasis maps to COLOUR: **bold** white, `code`/fences cyan, # headings the chip amber,
    # *italic* lilac, rules the structure orange.
    md_bold: {P.white(), @bg},
    md_italic: {@lilac, @bg},
    md_code: {@cyan, @bg},
    md_head: {@chip, @bg},
    md_rule: {@sep, @bg}
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
