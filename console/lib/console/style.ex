defmodule Console.Style do
  @moduledoc """
  The one palette. Panels render in **semantic styles** (`:header`, `:warm`, `:selected`, …),
  never raw hex — so the whole cockpit reads as one surface and a re-theme is one edit here,
  not a hunt through every panel (design §3: panels are thin; presentation is centralized).

  Colors are 24-bit RGB for termbox2's `TB_OUTPUT_TRUECOLOR` (see `Mix.Tasks.Console.Run`);
  the ground is `0x000000`, which truecolor maps to the terminal's own background. The values
  are `Console.Palette` — generated, shared with every other surface on the box, and named by
  ROLE: what a style MEANS, never a colour.
  """

  alias Console.Palette, as: P

  @colors %{
    normal: {P.body(), P.ground()},
    header: {P.key(), P.ground()},
    label: {P.key(), P.ground()},
    accent: {P.attention(), P.ground()},
    # The operator's voice in chat — its OWN key (not :accent) so re-theming the operator
    # doesn't entangle with the cursor/thinking chrome.
    operator: {P.attention(), P.ground()},
    warm: {P.body(), P.ground()},
    dim: {P.inactive(), P.ground()},
    meta: {P.meta(), P.ground()},
    separator: {P.structure(), P.ground()},
    # `:selected` is the row CURSOR — one per list, gone when you look away — so it is the cursor
    # field, like every other "where I am" on the machine. The violet selection field is for a
    # SELECTION you pick and leave behind; a TUI list has no such state, so it does not appear here.
    selected: {P.field_ink(), P.cursor_field()},
    # A cursor row that is also attention: the same inverse video, in the operator's colour.
    selected_accent: {P.field_ink(), P.attention_field()},
    # Status-line chips: inverse-video tabs, dark text on a bright field.
    tab: {P.field_ink(), P.cursor_field()},
    stat: {P.field_ink(), P.cursor_field()},
    stat_live: {P.field_ink(), P.live_field()},
    # LOCK's chip — total keyboard passthrough deserves the loudest colour on hand.
    stat_warn: {P.field_ink(), P.alarm_field()},
    # A commit diff in MAIN (Commits pane detail). These are the CATEGORICAL tier: add/delete/hunk
    # are a diff convention, not machine state — an addition is not "running".
    diff_add: {P.cat_green(), P.ground()},
    diff_del: {P.cat_red(), P.ground()},
    diff_hunk: {P.cat_cyan(), P.ground()},
    # Semantic event styles (the server activity feed + footer pulse): a fact banked or a check
    # passing reads live, a failure alarm, a posted message reads as a key; work landed and an
    # issue/question raised both read body — icon carries the done/warn distinction.
    event_ok: {P.live(), P.ground()},
    event_bad: {P.alarm(), P.ground()},
    event_msg: {P.key(), P.ground()},
    event_done: {P.body(), P.ground()},
    event_warn: {P.body(), P.ground()},
    # STATUS tier (the signal tier: card gutters + status dots).
    st_working: {P.st_working(), P.ground()},
    st_blocked: {P.st_blocked(), P.ground()},
    st_await: {P.st_await(), P.ground()},
    st_open: {P.st_open(), P.ground()},
    st_done: {P.st_done(), P.ground()},
    st_idle: {P.st_idle(), P.ground()},
    # IDENTITY tier (the splash tier: same entity → same hue), per coworker archetype, reused as
    # the workspace-hue cycle.
    arch_surveyor: {P.arch_surveyor(), P.ground()},
    arch_builder: {P.arch_builder(), P.ground()},
    arch_reviewer: {P.arch_reviewer(), P.ground()},
    arch_planner: {P.arch_planner(), P.ground()},
    arch_assistant: {P.arch_assistant(), P.ground()},
    # Markdown in the chat (Console.Markdown) — no bold attr in this palette, so emphasis maps to
    # COLOUR: **bold** max-contrast, `code`/fences the key colour, # headings the cursor field,
    # *italic* secondary, rules the structure.
    md_bold: {P.max_contrast(), P.ground()},
    md_italic: {P.meta(), P.ground()},
    md_code: {P.key(), P.ground()},
    md_head: {P.cursor_field(), P.ground()},
    md_rule: {P.structure(), P.ground()}
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
  def bg, do: P.ground()
end
