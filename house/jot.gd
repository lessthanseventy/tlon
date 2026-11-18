extends PanelContainer

signal submitted(text: String)
signal cancelled

const INK := Color("2a2530")
const PAPER := Color("f3ead6")
const QUIET := Color(0.165, 0.145, 0.188, 0.6)
const WARM := Color("a8453c")

var _edit: LineEdit
var _hint: Label
var _scribble: Scribble
var _busy := false


class Scribble:
	extends Control
	var t := 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(70, 26)
		visible = false

	func _process(dt: float) -> void:
		if visible:
			t += dt
			queue_redraw()

	func _draw() -> void:
		var pts := PackedVector2Array()
		var run := fmod(t * 1.6, 1.0)
		var n := 18
		for i in int(n * run) + 2:
			pts.append(
				Vector2(6 + i * 3.0, 14 + (7 if i % 2 else -7) * (0.4 + 0.6 * sin(t * 4.0 + i)))
			)
		if pts.size() > 1:
			draw_polyline(pts, Color("2a2530"), 2.0)
		var tip: Vector2 = pts[pts.size() - 1]
		draw_line(tip, tip + Vector2(10, -12), Color("e8b86d"), 4.0)
		draw_line(tip, tip + Vector2(2, -2.5), Color("2a2530"), 4.0)


func _ready() -> void:
	visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = PAPER
	style.set_border_width_all(3)
	style.border_color = INK
	style.shadow_color = Color(0, 0, 0, 0.3)
	style.shadow_size = 4
	style.shadow_offset = Vector2(3, 5)
	style.set_content_margin_all(12)
	add_theme_stylebox_override("panel", style)
	custom_minimum_size = Vector2(520, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	add_child(col)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	var tag := Label.new()
	tag.text = "jot:"
	tag.add_theme_color_override("font_color", QUIET)
	tag.add_theme_font_size_override("font_size", 16)
	row.add_child(tag)
	_edit = LineEdit.new()
	_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_edit.placeholder_text = "remind me to..., buy..., a note..., or ask something"
	_edit.add_theme_color_override("font_color", INK)
	_edit.add_theme_color_override("font_placeholder_color", Color(INK, 0.4))
	_edit.add_theme_color_override("caret_color", INK)
	_edit.add_theme_font_size_override("font_size", 18)
	var flat := StyleBoxFlat.new()
	flat.bg_color = Color(1, 1, 1, 0.35)
	flat.set_content_margin_all(5)
	for s in ["normal", "focus", "read_only"]:
		_edit.add_theme_stylebox_override(s, flat)
	_edit.text_submitted.connect(_on_submit)
	row.add_child(_edit)
	_scribble = Scribble.new()
	row.add_child(_scribble)
	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.add_theme_color_override("font_color", QUIET)
	col.add_child(_hint)


func open(prefill: String = "") -> void:
	visible = true
	_edit.text = prefill
	sending(false)
	_hint.text = "Enter keeps it  -  Esc puts it down"
	_hint.add_theme_color_override("font_color", QUIET)
	_edit.grab_focus()
	_edit.caret_column = prefill.length()


func sending(on: bool) -> void:
	_busy = on
	_edit.editable = not on
	_scribble.visible = on
	if on:
		_hint.text = "reading it..."
		_hint.add_theme_color_override("font_color", QUIET)


func fail(message: String) -> void:
	sending(false)
	_hint.text = message
	_hint.add_theme_color_override("font_color", WARM)
	_edit.grab_focus()
	_edit.caret_column = _edit.text.length()


func finish() -> void:
	visible = false
	_edit.release_focus()
	_busy = false
	_scribble.visible = false


func _on_submit(text: String) -> void:
	if _busy or text.strip_edges() == "":
		return
	submitted.emit(text.strip_edges())


func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		finish()
		cancelled.emit()
