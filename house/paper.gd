extends RefCounted

# The paper look the settings and the chat are built from.
const Fonts := preload("res://fonts.gd")
const INK := Color("2a2530")
const PAPER := Color("f3ead6")
const QUIET := Color(0.165, 0.145, 0.188, 0.6)
const WARM := Color("a8453c")
const GOLD := Color("e8c77a")


static func panel(margin: int = 14) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PAPER
	style.set_border_width_all(3)
	style.border_color = INK
	style.shadow_color = Color(0, 0, 0, 0.3)
	style.shadow_size = 4
	style.shadow_offset = Vector2(3, 5)
	style.set_content_margin_all(margin)
	return style


static func flat() -> StyleBoxFlat:
	var flat := StyleBoxFlat.new()
	flat.bg_color = Color(1, 1, 1, 0.35)
	flat.set_content_margin_all(5)
	return flat


static func label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func heading(text: String, size: int, color: Color) -> Label:
	var l := label(text, size, color)
	l.theme_type_variation = Fonts.HEADING
	return l


# a section's label: small, dim, with room above it; `indent` lines it up with a row's text
static func section(text: String, indent: int = 0) -> Label:
	var l := label(text, Fonts.LABEL, QUIET)
	var gap := StyleBoxEmpty.new()
	gap.content_margin_top = 6
	gap.content_margin_left = indent
	l.add_theme_stylebox_override("normal", gap)
	return l


static func row(parent: Control) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 6)
	parent.add_child(r)
	return r


static func edit(placeholder: String, parent: Control) -> LineEdit:
	var e := LineEdit.new()
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.placeholder_text = placeholder
	e.add_theme_color_override("font_color", INK)
	e.add_theme_color_override("font_placeholder_color", Color(INK, 0.4))
	e.add_theme_color_override("caret_color", INK)
	e.add_theme_font_size_override("font_size", Fonts.BODY)
	for s in ["normal", "focus", "read_only"]:
		e.add_theme_stylebox_override(s, flat())
	parent.add_child(e)
	return e


# The three button styles of the sidebar, in one place. `primary`: filled, one per group at most.
# `secondary`: a light outline. `quiet`: text only, an underline on hover. A toggle (a chip) is
# the secondary look unselected and a tinted fill selected.
static func chip(
	text: String, parent: Control, cb: Callable, toggle: bool = false, kind: String = "secondary"
) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = toggle
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	skin(b, kind)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


static func _box(fill: Color, edge: Color, under: bool = false) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = edge
	if under:
		s.border_width_bottom = 1
	else:
		s.set_border_width_all(1)
	s.set_corner_radius_all(2)
	s.content_margin_left = 9
	s.content_margin_right = 9
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	return s


static func skin(b: Button, kind: String = "secondary") -> void:
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", Fonts.SMALL)
	var none := Color(0, 0, 0, 0)
	var line := Color(INK, 0.3)
	var ink := INK
	var disabled := QUIET
	var look := {}
	match kind:
		"primary":
			ink = PAPER
			disabled = Color(PAPER, 0.7)
			look = {
				"normal": _box(INK, INK),
				"hover": _box(Color(INK, 0.82), INK),
				"pressed": _box(Color(INK, 0.7), INK),
				"hover_pressed": _box(Color(INK, 0.7), INK),
				"disabled": _box(Color(INK, 0.45), none),
			}
		"quiet":
			ink = Color(INK, 0.7)
			look = {
				"normal": _box(none, none),
				"hover": _box(none, INK, true),
				"pressed": _box(none, INK, true),
				"hover_pressed": _box(none, INK, true),
				"disabled": _box(none, none),
			}
		_:
			look = {
				"normal": _box(none, line),
				"hover": _box(Color(INK, 0.07), Color(INK, 0.5)),
				"pressed": _box(Color(GOLD, 0.85), Color(INK, 0.6)),
				"hover_pressed": _box(Color(GOLD, 0.85), Color(INK, 0.6)),
				"disabled": _box(none, Color(INK, 0.15)),
			}
	for c in ["font_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(c, ink)
	b.add_theme_color_override("font_hover_color", INK if kind != "primary" else PAPER)
	b.add_theme_color_override("font_disabled_color", disabled)
	for state in look:
		b.add_theme_stylebox_override(state, look[state])
