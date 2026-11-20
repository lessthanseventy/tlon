extends VBoxContainer

# The add view: one free-text line the house's reader takes as it is; Enter sends it, and
# while it is read a pencil scribbles. main.gd sends it and says how it went; the view then shows what
# the house made of it.
signal submitted(text: String)
signal details_wanted
signal accepted
signal change_wanted

const Paper := preload("res://paper.gd")
const Fonts := preload("res://fonts.gd")
const EXAMPLE := "Like: remind me to call Sam on Friday at 3pm"

var _ask: VBoxContainer
var _kept: VBoxContainer
var _summary: Label
var _said: Label
var _change: Button
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
	add_theme_constant_override("separation", 6)
	_ask = VBoxContainer.new()
	_ask.add_theme_constant_override("separation", 6)
	add_child(_ask)
	var row := Paper.row(_ask)
	_edit = Paper.edit("Jot it down", row)
	_edit.text_submitted.connect(_on_submit)
	_scribble = Scribble.new()
	row.add_child(_scribble)
	_hint = Paper.label("", Fonts.SMALL, Paper.QUIET)
	_ask.add_child(_hint)
	_hint.text = EXAMPLE
	var more := Paper.chip("Fill in the details instead", _ask, func() -> void: details_wanted.emit(), false, "quiet")
	more.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var box: StyleBoxFlat = more.get_theme_stylebox(state).duplicate()
		box.content_margin_left = 0
		more.add_theme_stylebox_override(state, box)
	_kept = VBoxContainer.new()
	_kept.add_theme_constant_override("separation", 6)
	_kept.visible = false
	add_child(_kept)
	_summary = Paper.label("", Fonts.SMALL, Paper.QUIET)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_kept.add_child(_summary)
	_said = Paper.label("", Fonts.BODY, Paper.INK)
	_said.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_kept.add_child(_said)
	var buttons := Paper.row(_kept)
	Paper.chip("OK", buttons, func() -> void: accepted.emit(), false, "primary")
	_change = Paper.chip("Change", buttons, func() -> void: change_wanted.emit(), false)


# shown with the cursor in it
func open(prefill: String = "") -> void:
	show_quiet()
	_edit.text = prefill
	_edit.grab_focus()
	_edit.caret_column = prefill.length()


# shown, the cursor elsewhere
func show_quiet() -> void:
	visible = true
	_ask.visible = true
	_kept.visible = false
	_edit.text = ""
	sending(false)
	_hint.text = EXAMPLE
	_hint.add_theme_color_override("font_color", Paper.QUIET)


# what the house made of the line: `summary` ("Reminder · Sat 10:00 · every week", empty when it made
# nothing) over `said`; "Change" only when there is a thing to change
func read_back(summary: String, said: String, can_change: bool) -> void:
	sending(false)
	_edit.release_focus()
	_ask.visible = false
	_kept.visible = true
	_summary.text = summary
	_summary.visible = summary != ""
	_said.text = said
	_change.visible = can_change


func sending(on: bool) -> void:
	_busy = on
	_edit.editable = not on
	_scribble.visible = on
	if on:
		_hint.text = "reading it..."
		_hint.add_theme_color_override("font_color", Paper.QUIET)


func fail(message: String) -> void:
	sending(false)
	_hint.text = message
	_hint.add_theme_color_override("font_color", Paper.WARM)
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
