# generated from modules/desktop/theme/palette.nix — edit THAT, never this file
defmodule Console.Palette do
  @moduledoc """
  The machine palette for the cockpit, as 24-bit integers. `Console.Style` maps semantic
  styles onto these; nothing else in the cockpit names a colour.

  Two vocabularies, and the rule is: use a ROLE. Roles say what a thing MEANS, so two
  surfaces that mean the same thing cannot drift apart. The hue names (`amber`, `chip`)
  are deliberately absent — they were the same colour as each other for a while and
  nothing could tell us, so a stale name is a compile error now.

  The exception is the `cat_*` tier: hues used because they are DISTINGUISHABLE from one
  another (a diff's add/delete, an archetype's splash), where the point is that they
  differ, not that they mean anything.
  """

  # roles: what a surface asks for
  def accent_field, do: 0x33C7FF
  def alarm, do: 0xFF6969
  def alarm_field, do: 0xFF6969
  def assistant, do: 0xB98AFF
  def assistant_voice, do: 0xFFB000
  def attention, do: 0xF06CB4
  def attention_dim, do: 0x9C4A76
  def attention_field, do: 0xF06CB4
  def body, do: 0xFFB000
  def border_active, do: 0xFFB000
  def border_active2, do: 0xFF6E06
  def border_inactive, do: 0x7A5500
  def border_inactive2, do: 0x9E3B00
  def card, do: 0x0E0E0E
  def cursor_field, do: 0xFFB000
  def done, do: 0x62A562
  def edge, do: 0x2A2A2A
  def field_ink, do: 0x0A0A0A
  def ground, do: 0x000000
  def hover_ground, do: 0x100C00
  def inactive, do: 0xB8994C
  def input_ground, do: 0x141414
  def key, do: 0x33C7FF
  def live, do: 0x33FF00
  def live_field, do: 0x33FF00
  def max_contrast, do: 0xFFFFFF
  def menu_ground, do: 0x332800
  def meta, do: 0xB4A5D6
  def panel, do: 0x0D0D0D
  def pressed_ground, do: 0x1A1200
  def prose, do: 0xC7C7C7
  def raised, do: 0x1A1A1A
  def sel_field, do: 0xC7B6E8
  def sel_ink, do: 0x1A0A2E
  def sel_soft, do: 0x2E0057
  def structure, do: 0xB5651D
  def user_voice, do: 0x33FF00
  def visited, do: 0xCC8D00
  def warn, do: 0xFF6E06
  def warn_field, do: 0xFF6E06

  # the status tier (card gutters, status dots)
  def st_await, do: 0xF06CB4
  def st_blocked, do: 0xFF6969
  def st_done, do: 0x62A562
  def st_idle, do: 0xB8994C
  def st_open, do: 0xFFB000
  def st_working, do: 0x33FF00

  # the identity tier (one hue per coworker archetype)
  def arch_assistant, do: 0xB98AFF
  def arch_builder, do: 0x33FF00
  def arch_planner, do: 0xF06CB4
  def arch_reviewer, do: 0xFFB000
  def arch_surveyor, do: 0x33C7FF

  # the categorical tier: hues as categories, not as meanings
  def cat_amber, do: 0xFFB000
  def cat_cyan, do: 0x33C7FF
  def cat_green, do: 0x33FF00
  def cat_lilac, do: 0xB4A5D6
  def cat_pink, do: 0xF06CB4
  def cat_red, do: 0xFF6969
  def cat_violet, do: 0xB98AFF
end
