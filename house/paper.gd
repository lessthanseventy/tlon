extends RefCounted

# The paper look the settings and the chat are built from.
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
	e.add_theme_font_size_override("font_size", 17)
	for s in ["normal", "focus", "read_only"]:
		e.add_theme_stylebox_override(s, flat())
	parent.add_child(e)
	return e


static func chip(text: String, parent: Control, cb: Callable, toggle: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = toggle
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	skin(b)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


static func skin(b: Button) -> void:
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 14)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(c, INK)
	b.add_theme_color_override("font_disabled_color", QUIET)
	for pair in [
		["normal", Color("e4d8bd")],
		["hover", Color("f8efb8")],
		["pressed", GOLD],
		["hover_pressed", GOLD],
		["disabled", Color("d8cfba")]
	]:
		var s := StyleBoxFlat.new()
		s.bg_color = pair[1]
		s.set_border_width_all(2)
		s.border_color = INK
		s.set_content_margin_all(4)
		s.content_margin_left = 9
		s.content_margin_right = 9
		b.add_theme_stylebox_override(pair[0], s)
