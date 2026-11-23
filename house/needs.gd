extends Control

# The header's count of what waits on the person: a drawn triangle and the number, a click opens
# Your move. Gone at zero.
signal pressed

const Fonts := preload("res://fonts.gd")
const GAP := 4.0
const SIDE := 28.0

var ink := Color("e8b86d")
var count := 0:
	set(v):
		if v == count:
			return
		count = v
		visible = v > 0
		tooltip_text = "Your move: %d waiting on you" % v
		custom_minimum_size = Vector2(SIDE * 0.5 + GAP + _width(), SIDE)
		queue_redraw()
var _hover := false


func _init() -> void:
	visible = false
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(func() -> void: _lit(true))
	mouse_exited.connect(func() -> void: _lit(false))


func _width() -> float:
	return ThemeDB.fallback_font.get_string_size(str(count), 0, -1, Fonts.SMALL).x


func _lit(on: bool) -> void:
	_hover = on
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		pressed.emit()


func _draw() -> void:
	var color := Color(ink, 1.0 if _hover else 0.85)
	var mid := Vector2(SIDE * 0.25, size.y / 2.0).round()
	draw_colored_polygon(
		PackedVector2Array([mid + Vector2(0, -5), mid + Vector2(5, 4), mid + Vector2(-5, 4)]), color
	)
	var at := Vector2(SIDE * 0.5 + GAP, size.y / 2.0 + Fonts.SMALL * 0.35).round()
	draw_string(
		ThemeDB.fallback_font, at, str(count), HORIZONTAL_ALIGNMENT_LEFT, -1, Fonts.SMALL, color
	)
