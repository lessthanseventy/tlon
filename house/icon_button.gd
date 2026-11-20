extends Control

# One of `Icons` as a button: a flat square, a tint under the pointer, a tooltip.
signal pressed

const Paper := preload("res://paper.gd")
const Icons := preload("res://icons.gd")

var kind: String
var ink: Color
var disabled := false:
	set(v):
		disabled = v
		mouse_default_cursor_shape = Control.CURSOR_ARROW if v else Control.CURSOR_POINTING_HAND
		queue_redraw()
var _hover := false


func _init(the_kind: String, tip: String, the_ink: Color = Paper.INK, side: int = 26) -> void:
	kind = the_kind
	ink = the_ink
	tooltip_text = tip
	custom_minimum_size = Vector2(side, side)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(func() -> void: _lit(true))
	mouse_exited.connect(func() -> void: _lit(false))


func _lit(on: bool) -> void:
	_hover = on
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if (
		event is InputEventMouseButton
		and event.pressed
		and event.button_index == MOUSE_BUTTON_LEFT
		and not disabled
	):
		accept_event()
		pressed.emit()


func _draw() -> void:
	if _hover and not disabled:
		draw_rect(Rect2(Vector2.ZERO, size), Color(ink, 0.12))
	Icons.draw(self, kind, size / 2.0, Color(ink, 0.25 if disabled else (1.0 if _hover else 0.7)))
