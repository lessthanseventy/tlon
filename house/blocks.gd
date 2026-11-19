extends RefCounted

# Turns the blocks a thing's view is told to show into Controls on the paper sheet:
# {"t": "title"|"text"|"dim", "text"}, {"t": "gap"}, {"t": "month", "year", "month", "today",
# "marks": {day: true}, "pick": bool, "sel": day} (arrows and the name act "mprev" "mnext" "mtoday",
# a day "day:N"), {"t": "buttons", "items": [{"label", "act", "on", "s"}]}, {"t": "row", "text",
# "act", "dim", "marks": [{"label", "act"}]}, {"t": "foot", "text", "act"}, {"t": "day", "name",
# "kind", "temps", "wet"} (a forecast row with its icon). Every click calls `act.call(String)`.
const Paper := preload("res://paper.gd")
const Card := preload("res://card.gd")
const Forecast := preload("res://forecast.gd")
const CELL := Vector2(40.0, 26.0)
const HOVER := Color("f8efb8")


# a clickable row: text over an optional quiet line, an optional tick circle, small buttons at
# the end
class Row:
	extends PanelContainer
	signal pressed
	signal ticked
	var _lit := false

	# `line`: the quiet text sits at the right of the one line instead of under it
	func _init(
		text: String, sub: String = "", tick: bool = false, dim: bool = false, line: bool = false
	) -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_entered.connect(func() -> void: _set_lit(true))
		mouse_exited.connect(func() -> void: _set_lit(false))
		_set_lit(false)
		var h := HBoxContainer.new()
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_theme_constant_override("separation", 8)
		add_child(h)
		if tick:
			var t := Tick.new()
			t.pressed.connect(func() -> void: ticked.emit())
			h.add_child(t)
		var ink := Color(Paper.INK, 0.55) if dim else Paper.INK
		if line:
			var l := _text(text, 14, ink)
			l.autowrap_mode = TextServer.AUTOWRAP_OFF
			l.clip_text = true
			l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			h.add_child(l)
			if sub != "":
				var q := _text(sub, 12, Paper.QUIET)
				q.autowrap_mode = TextServer.AUTOWRAP_OFF
				q.size_flags_horizontal = Control.SIZE_SHRINK_END
				q.custom_minimum_size.x = 0
				q.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				h.add_child(q)
			return
		var col := VBoxContainer.new()
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 0)
		h.add_child(col)
		col.add_child(_text(text, 15, ink))
		if sub != "":
			col.add_child(_text(sub, 12, Paper.QUIET))

	static func _text(text: String, size: int, color: Color) -> Label:
		var l := Paper.label(text, size, color)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.custom_minimum_size.x = 40
		return l

	func marks(items: Array, act: Callable) -> void:
		var h: HBoxContainer = get_child(0)
		for m in items:
			var b := Paper.chip(str(m["label"]), h, func() -> void: act.call(str(m["act"])), false)
			b.add_theme_font_size_override("font_size", 12)
			b.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _set_lit(on: bool) -> void:
		_lit = on
		var s := StyleBoxFlat.new()
		s.bg_color = HOVER if on else Color(0, 0, 0, 0)
		s.set_content_margin_all(3)
		s.content_margin_left = 5
		add_theme_stylebox_override("panel", s)

	func _gui_input(event: InputEvent) -> void:
		if (
			event is InputEventMouseButton
			and event.pressed
			and event.button_index == MOUSE_BUTTON_LEFT
		):
			accept_event()
			pressed.emit()


class Tick:
	extends Control
	signal pressed
	var _lit := false

	func _init() -> void:
		custom_minimum_size = Vector2(22, 22)
		size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		tooltip_text = "done"
		mouse_entered.connect(func() -> void: _light(true))
		mouse_exited.connect(func() -> void: _light(false))

	func _light(on: bool) -> void:
		_lit = on
		queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if (
			event is InputEventMouseButton
			and event.pressed
			and event.button_index == MOUSE_BUTTON_LEFT
		):
			accept_event()
			pressed.emit()

	func _draw() -> void:
		var mid := size / 2.0
		if _lit:
			draw_circle(mid, 10.0, Paper.GOLD)
		draw_arc(mid, 10.0, 0.0, TAU, 24, Paper.INK, 2.0)


class MonthGrid:
	extends Control
	signal act(what: String)
	var b := {}

	func _init(block: Dictionary) -> void:
		b = block
		mouse_filter = Control.MOUSE_FILTER_STOP
		var info := Card.month_info(b["year"], b["month"])
		var rows := ceili((info["first"] + info["days"]) / 7.0)
		custom_minimum_size = Vector2(7.0 * CELL.x, 30.0 + CELL.y + rows * CELL.y)

	func _origin() -> Vector2:
		return Vector2((size.x - 7.0 * CELL.x) / 2.0, 30.0)

	func _arrows() -> Array:
		return [Rect2(size.x - 62, 0, 28, 24), Rect2(size.x - 32, 0, 28, 24)]

	func _gui_input(event: InputEvent) -> void:
		if not (
			event is InputEventMouseButton
			and event.pressed
			and event.button_index == MOUSE_BUTTON_LEFT
		):
			return
		accept_event()
		var pos: Vector2 = event.position
		if b.get("pick", false):
			var arrows := _arrows()
			if (arrows[0] as Rect2).has_point(pos):
				act.emit("mprev")
				return
			if (arrows[1] as Rect2).has_point(pos):
				act.emit("mnext")
				return
			if Rect2(0, 0, size.x - 66, 24).has_point(pos):
				act.emit("mtoday")
				return
		var info := Card.month_info(b["year"], b["month"])
		var at := pos - _origin() - Vector2(0, CELL.y)
		var col := int(floorf(at.x / CELL.x))
		var idx := int(floorf(at.y / CELL.y)) * 7 + col - int(info["first"])
		if at.y >= 0 and at.x >= 0 and col < 7 and idx >= 0 and idx < int(info["days"]):
			if b.get("pick", false):
				act.emit("day:%d" % (idx + 1))

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var title: String = "%s %d" % [Card.MONTHS[int(b["month"]) - 1], int(b["year"])]
		draw_string(
			font, Vector2(0, 18), title, HORIZONTAL_ALIGNMENT_LEFT, size.x - 66, 17, Paper.INK
		)
		if b.get("pick", false):
			var i := 0
			for r: Rect2 in _arrows():
				draw_rect(r, Paper.INK)
				draw_rect(r.grow(-2), Color("e4d8bd"))
				draw_string(font, r.position + Vector2(9, 18), "<>"[i], 0, -1, 16, Paper.INK)
				i += 1
		var top := _origin()
		for i in 7:
			var w := font.get_string_size(Card.WEEK[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			draw_string(
				font,
				top + Vector2(i * CELL.x + (CELL.x - w) / 2.0, 16),
				Card.WEEK[i],
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				12,
				Color(Paper.INK, 0.55)
			)
		var info := Card.month_info(b["year"], b["month"])
		var marks: Dictionary = b.get("marks", {})
		for d in range(1, int(info["days"]) + 1):
			var idx: int = int(info["first"]) + d - 1
			var cell := top + Vector2((idx % 7) * CELL.x, CELL.y + (idx / 7) * CELL.y)
			var mid := cell + CELL / 2.0
			if d == int(b.get("sel", 0)):
				draw_arc(mid + Vector2(0, -1), 12.0, 0.0, TAU, 24, Paper.INK, 2.0)
			if d == int(b.get("today", 0)):
				draw_circle(mid + Vector2(0, -1), 11.0, Color("e8b86d"))
			var label := str(d)
			var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
			draw_string(font, cell + Vector2((CELL.x - w) / 2.0, 17), label, 0, -1, 14, Paper.INK)
			if marks.has(d):
				draw_circle(mid + Vector2(0, 11), 2.6, Color("c8483f"))


class DayRow:
	extends Control
	var b := {}

	func _init(block: Dictionary) -> void:
		b = block
		custom_minimum_size = Vector2(0, 30)

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var base := 20.0
		draw_string(font, Vector2(0, base), b["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Paper.INK)
		Forecast.draw_icon(self, b["kind"], Vector2(96.0, 14.0), 26.0)
		draw_string(
			font, Vector2(122, base), b["temps"], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Paper.INK
		)
		var wet: String = b["wet"]
		if wet != "":
			var w := font.get_string_size(wet, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			draw_string(
				font,
				Vector2(size.x - w, base),
				wet,
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				13,
				Color(Paper.INK, 0.6)
			)


static func wrapped(text: String, size: int, color: Color) -> Label:
	var l := Paper.label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 40
	return l


static func build(parent: Control, blocks: Array, act: Callable) -> void:
	for b in blocks:
		match b["t"]:
			"title":
				var l := Paper.heading(str(b["text"]), 19, Paper.INK)
				l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				l.custom_minimum_size.x = 40
				parent.add_child(l)
			"text":
				parent.add_child(wrapped(str(b["text"]), 15, Paper.INK))
			"dim":
				parent.add_child(wrapped(str(b["text"]), 13, Paper.QUIET))
			"meet":
				var color := Color(Paper.INK, 0.55) if b.get("dim", false) else Paper.INK
				var m := wrapped(str(b["text"]), 14, color)
				parent.add_child(m)
			"gap":
				var g := Control.new()
				g.custom_minimum_size.y = 6
				parent.add_child(g)
			"month":
				var m := MonthGrid.new(b)
				m.act.connect(func(a: String) -> void: act.call(a))
				parent.add_child(m)
			"day":
				parent.add_child(DayRow.new(b))
			"buttons":
				var flow := HFlowContainer.new()
				flow.add_theme_constant_override("h_separation", 6)
				flow.add_theme_constant_override("v_separation", 6)
				parent.add_child(flow)
				for item in b["items"]:
					var chip := Paper.chip(
						str(item["label"]), flow, func() -> void: act.call(str(item["act"])), false
					)
					if item.get("on", false):
						chip.add_theme_stylebox_override(
							"normal", chip.get_theme_stylebox("pressed")
						)
					if int(item.get("s", 14)) < 14:
						chip.add_theme_font_size_override("font_size", int(item["s"]))
			"row":
				var r := Row.new(str(b["text"]), "", false, b.get("dim", false))
				r.pressed.connect(func() -> void: act.call(str(b["act"])))
				r.marks(b.get("marks", []), act)
				parent.add_child(r)
			"foot":
				var f := wrapped(str(b["text"]), 12, Paper.QUIET)
				if b.get("act", "") != "":
					f.mouse_filter = Control.MOUSE_FILTER_STOP
					f.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
					f.gui_input.connect(
						func(ev: InputEvent) -> void:
							if (
								ev is InputEventMouseButton
								and ev.pressed
								and ev.button_index == MOUSE_BUTTON_LEFT
							):
								act.call(str(b["act"]))
					)
				parent.add_child(f)
