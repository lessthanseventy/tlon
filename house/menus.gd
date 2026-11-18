extends RefCounted

const Props := preload("res://props.gd")
const ROW := 26.0

var is_open := false
var id := 0
var anchor := Vector2.ZERO
var title := ""
var rows: Array = []

var _hover := -1
var _rects: Array = []
var _box := Rect2()


func show_at(item_id: int, at: Vector2, heading: String, entries: Array) -> void:
	is_open = true
	id = item_id
	anchor = at
	title = heading
	rows = entries
	_hover = -1


func close() -> void:
	is_open = false
	rows = []
	_rects = []


func _layout(bounds: Rect2) -> void:
	var font := ThemeDB.fallback_font
	var w := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	for r in rows:
		w = maxf(w, font.get_string_size(r["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x)
	var box := Vector2(w + 40, 26 + rows.size() * ROW + 8)
	var pos := Vector2(anchor.x - box.x / 2.0, anchor.y + 14)
	pos.x = clampf(pos.x, bounds.position.x + 6, bounds.end.x - box.x - 6)
	if pos.y + box.y > bounds.end.y - 6:
		pos.y = anchor.y - box.y - 14
	pos.y = clampf(pos.y, bounds.position.y + 6, bounds.end.y - box.y - 6)
	_box = Rect2(pos.round(), box)
	_rects = []
	for i in rows.size():
		_rects.append(Rect2(_box.position + Vector2(8, 24 + i * ROW), Vector2(box.x - 16, ROW - 2)))


func draw(c: CanvasItem, bounds: Rect2) -> void:
	if not is_open:
		return
	_layout(bounds)
	var font := ThemeDB.fallback_font
	c.draw_rect(Rect2(_box.position + Vector2(3, 5), _box.size), Color(0, 0, 0, 0.3))
	c.draw_rect(_box, Props.INK)
	c.draw_rect(_box.grow(-2), Props.PAPER)
	c.draw_circle(_box.position + Vector2(_box.size.x / 2.0, 7), 4, Props.PIN_COLORS[0])
	c.draw_circle(_box.position + Vector2(_box.size.x / 2.0 - 1, 6), 1.5, Color(1, 1, 1, 0.7))
	c.draw_string(
		font,
		_box.position + Vector2(12, 21),
		title,
		HORIZONTAL_ALIGNMENT_LEFT,
		_box.size.x - 24,
		12,
		Color(Props.INK, 0.6)
	)
	for i in rows.size():
		var r: Rect2 = _rects[i]
		if i == _hover:
			c.draw_rect(r, Color("f8efb8"))
			c.draw_rect(r, Color(Props.INK, 0.5), false, 1.0)
		c.draw_string(
			font,
			r.position + Vector2(10, 18),
			rows[i]["label"],
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			16,
			Props.INK
		)


func hover(pos: Vector2) -> bool:
	_hover = -1
	for i in _rects.size():
		if (_rects[i] as Rect2).has_point(pos):
			_hover = i
	return is_open and (_box.has_point(pos))


func click(pos: Vector2) -> String:
	for i in _rects.size():
		if (_rects[i] as Rect2).has_point(pos):
			return str(rows[i]["act"])
	return "inside" if _box.has_point(pos) else "outside"
