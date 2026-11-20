extends VBoxContainer

# The free-text jot in the add view: one line the house's reader takes as it is; Enter sends it, and
# while it is read a pencil scribbles. main.gd sends it and says how it went.
signal submitted(text: String)

const Paper := preload("res://paper.gd")
const Fonts := preload("res://fonts.gd")

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
	add_theme_constant_override("separation", 4)
	add_child(Paper.section("Jot it"))
	var row := Paper.row(self)
	_edit = Paper.edit("remind me to..., buy..., a note..., or ask", row)
	_edit.text_submitted.connect(_on_submit)
	_scribble = Scribble.new()
	row.add_child(_scribble)
	_hint = Paper.label("", Fonts.SMALL, Paper.QUIET)
	add_child(_hint)
	_hint.text = "Enter keeps it"


# shown with the cursor in it
func open(prefill: String = "") -> void:
	show_quiet()
	_edit.text = prefill
	_edit.grab_focus()
	_edit.caret_column = prefill.length()


# shown, the cursor elsewhere
func show_quiet() -> void:
	visible = true
	_edit.text = ""
	sending(false)
	_hint.text = "Enter keeps it"
	_hint.add_theme_color_override("font_color", Paper.QUIET)


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
