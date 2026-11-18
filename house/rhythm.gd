extends RefCounted

# The day's two beats, each once a day: he comes home at the server's daily-list time and a slip of
# what is still open unrolls; in the morning he stretches and a slip shows what is coming today.
const Props := preload("res://props.gd")
const STORE := "user://house_rhythm.json"
const HOME_WINDOW := 3.0
const MORNING_FROM := 5.5
const MORNING_LATE := 8.0
const MORNING_UNTIL := 12.0
const SLIP_SECONDS := 14.0
const UNROLL := 0.55
const ROW := 24.0
const SHOWN := 6

var list_at := 17.5
var persist := true
var days := {"home": "", "morning": ""}
var first_hour := -1.0
var kind := ""
var title := ""
var rows: Array = []
var more := 0
var left := 0.0
var age := 0.0

var _rects: Array = []
var _box := Rect2()
var _hover := false
var _mouse := Vector2(-1, -1)


static func parse_time(text: String) -> float:
	var parts := text.strip_edges().split(":")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return -1.0
	return float(int(parts[0])) + float(int(parts[1])) / 60.0


static func home_due(hour: float, at: float, done_day: String, today: String) -> bool:
	return at >= 0.0 and done_day != today and hour >= at and hour < minf(at + HOME_WINDOW, 23.0)


static func morning_due(hour: float, first: float, done_day: String, today: String) -> bool:
	if done_day == today or hour >= MORNING_UNTIL or hour < MORNING_FROM:
		return false
	return first >= MORNING_FROM or hour >= MORNING_LATE


func load_days() -> void:
	if not persist or not FileAccess.file_exists(STORE):
		return
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(STORE))
	if d is Dictionary:
		for k in days:
			days[k] = str(d.get(k, ""))


func _save() -> void:
	if not persist:
		return
	var f := FileAccess.open(STORE, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(days))


func due(hour: float, today: String) -> String:
	if first_hour < 0.0:
		first_hour = hour
	if morning_due(hour, first_hour, days["morning"], today):
		days["morning"] = today
		_save()
		return "morning"
	if home_due(hour, list_at, days["home"], today):
		days["home"] = today
		_save()
		return "home"
	return ""


func show_slip(which: String, heading: String, items: Array, extra: int = 0) -> void:
	kind = which
	title = heading
	rows = items.slice(0, SHOWN)
	more = extra + maxi(0, items.size() - SHOWN)
	left = SLIP_SECONDS
	age = 0.0


func dismiss() -> void:
	if kind != "":
		left = minf(left, UNROLL)


func active() -> bool:
	return kind != ""


func process(dt: float) -> void:
	if kind == "":
		return
	age += dt
	if not _hover:
		left -= dt
	if left <= 0.0:
		kind = ""
		rows = []
		_rects = []


func draw(c: CanvasItem, bounds: Rect2) -> void:
	if kind == "":
		return
	var font := ThemeDB.fallback_font
	var w := 250.0
	for r in rows:
		w = maxf(w, font.get_string_size(str(r["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 52)
	var full := (
		36.0 + rows.size() * ROW + (20.0 if more > 0 else 0.0) + (22.0 if rows.is_empty() else 0.0)
	)
	var grow := minf(minf(age, left) / UNROLL, 1.0)
	var h := maxf(14.0, full * grow * grow * (3.0 - 2.0 * grow))
	var pos := Vector2((bounds.size.x - w) / 2.0, 56.0)
	_box = Rect2(pos.round(), Vector2(w, h))
	c.draw_rect(Rect2(_box.position + Vector2(3, 5), _box.size), Color(0, 0, 0, 0.3))
	c.draw_rect(_box, Props.INK)
	c.draw_rect(_box.grow(-2), Props.PAPER)
	c.draw_rect(Rect2(_box.position + Vector2(-5, -6), Vector2(w + 10, 10)), Props.PAPER_SHADE)
	c.draw_rect(Rect2(_box.position + Vector2(-5, -6), Vector2(w + 10, 10)), Props.INK, false, 2.0)
	_rects = []
	if h < full * 0.5:
		return
	c.draw_string(
		font,
		_box.position + Vector2(14, 28),
		title,
		HORIZONTAL_ALIGNMENT_LEFT,
		w - 28,
		14,
		Color(Props.INK, 0.6)
	)
	for i in rows.size():
		var r := Rect2(_box.position + Vector2(8, 36 + i * ROW), Vector2(w - 16, ROW - 2))
		_rects.append(r)
		if int(rows[i].get("id", -1)) >= 0 and r.has_point(_mouse):
			c.draw_rect(r, Color("f8efb8"))
		c.draw_circle(
			r.position + Vector2(12, ROW / 2.0 - 1),
			4,
			Color(rows[i].get("color", Props.PIN_COLORS[2]))
		)
		c.draw_string(
			font,
			r.position + Vector2(26, 17),
			str(rows[i]["label"]),
			HORIZONTAL_ALIGNMENT_LEFT,
			w - 44,
			15,
			Props.INK
		)
	if rows.is_empty():
		c.draw_string(
			font,
			_box.position + Vector2(14, 56),
			"Nothing waiting.",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			15,
			Props.INK
		)
	if more > 0:
		c.draw_string(
			font,
			_box.position + Vector2(14, full - 8),
			"and %d more" % more,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			13,
			Color(Props.INK, 0.6)
		)




func hover(pos: Vector2) -> bool:
	_mouse = pos
	_hover = kind != "" and _box.has_point(pos)
	return _hover


func click(pos: Vector2) -> Dictionary:
	if kind == "" or not _box.has_point(pos):
		return {}
	for i in _rects.size():
		if (_rects[i] as Rect2).has_point(pos) and int(rows[i].get("id", -1)) >= 0:
			return {"id": int(rows[i]["id"])}
	dismiss()
	return {"body": true}
