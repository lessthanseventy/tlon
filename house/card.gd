extends RefCounted

# The card: one paper popup near a thing the person clicked. It is told what to show as blocks:
# {"t": "title"|"text"|"dim", "text"}, {"t": "gap"}, {"t": "month", "year", "month", "today",
# "marks": {day: true}}, {"t": "buttons", "items": [{"label", "act"}]}.
const Props := preload("res://props.gd")
const WIDTH := 330.0
const PAD := 16.0
const CELL := Vector2(40.0, 26.0)
const MONTHS := [
	"January",
	"February",
	"March",
	"April",
	"May",
	"June",
	"July",
	"August",
	"September",
	"October",
	"November",
	"December",
]
const WEEK := ["S", "M", "T", "W", "T", "F", "S"]

var kind := ""
var key := ""
var page := 0

var _box := Rect2()
var _buttons: Array = []
var _hover := -1


static func unix(year: int, month: int, day: int, hour: int = 0, minute: int = 0) -> float:
	return Time.get_unix_time_from_datetime_dict(
		{"year": year, "month": month, "day": day, "hour": hour, "minute": minute, "second": 0}
	)


static func days_in(year: int, month: int) -> int:
	var next := unix(year + month / 12, month % 12 + 1, 1)
	return int((next - unix(year, month, 1)) / 86400.0)


# {first: weekday of the 1st (0 = Sunday), days}
static func month_info(year: int, month: int) -> Dictionary:
	var wd: int = Time.get_datetime_dict_from_unix_time(int(unix(year, month, 1)))["weekday"]
	return {"first": wd, "days": days_in(year, month)}


# the times (unix, local) a reminder falls on in [from, to): its due time, and for a repeating one
# every day, week or month after it
static func occurrences(due: float, every: String, from: float, to: float) -> Array:
	var out: Array = []
	match every:
		"day", "week":
			var step := 86400.0 if every == "day" else 604800.0
			var at := due
			if at < from:
				at += ceilf((from - at) / step) * step
			while at < to:
				out.append(at)
				at += step
		"month":
			var d := Time.get_datetime_dict_from_unix_time(int(due))
			var y: int = d["year"]
			var m: int = d["month"]
			for _i in 1200:
				var at := unix(y, m, mini(int(d["day"]), days_in(y, m)), d["hour"], d["minute"])
				if at >= to:
					break
				if at >= due and at >= from:
					out.append(at)
				m += 1
				if m > 12:
					m = 1
					y += 1
		_:
			if due >= from and due < to:
				out.append(due)
	return out


# "in 2 h 10 min", "in 25 min", "in 1 day 3 h"
static func until_text(secs: float) -> String:
	var mins := roundi(secs / 60.0)
	if mins <= 0:
		return "now"
	if mins < 60:
		return "in %d min" % mins
	if mins < 1440:
		var h := mins / 60
		return "in %d h" % h if mins % 60 == 0 else "in %d h %d min" % [h, mins % 60]
	var days := mins / 1440
	var h := (mins % 1440) / 60
	var text := "in %d day%s" % [days, "" if days == 1 else "s"]
	return text if h == 0 else text + " %d h" % h


func is_open() -> bool:
	return kind != ""


func open(what: String, from: String) -> void:
	kind = what
	key = from
	page = 0
	_hover = -1
	_buttons = []


func close() -> void:
	kind = ""
	key = ""
	_box = Rect2()
	_buttons = []


func hover(pos: Vector2) -> bool:
	_hover = -1
	for i in _buttons.size():
		if (_buttons[i]["rect"] as Rect2).has_point(pos):
			_hover = i
	return is_open() and _box.has_point(pos)


# "outside" for a click off the card, "inside" for one that was kept (page buttons included), or
# the act of a button the owner handles
func click(pos: Vector2) -> String:
	if not _box.has_point(pos):
		return "outside"
	for b in _buttons:
		if (b["rect"] as Rect2).has_point(pos):
			match b["act"]:
				"prev":
					page = maxi(0, page - 1)
				"next":
					page += 1
				_:
					return b["act"]
	return "inside"


static func _text_size(font: Font, text: String, size: int, wrap: float) -> Vector2:
	return font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, wrap, size)


static func _height(font: Font, b: Dictionary, wrap: float) -> float:
	match b["t"]:
		"title":
			return font.get_height(20) + 8.0
		"text":
			return _text_size(font, b["text"], 16, wrap).y + 6.0
		"dim":
			return _text_size(font, b["text"], 13, wrap).y + 6.0
		"month":
			var info := month_info(b["year"], b["month"])
			var rows := ceili((info["first"] + info["days"]) / 7.0)
			return font.get_height(17) + 8.0 + CELL.y + rows * CELL.y + 6.0
		"buttons":
			return 38.0
	return 8.0


func draw(c: CanvasItem, bounds: Rect2, anchor: Vector2, blocks: Array) -> void:
	var font := ThemeDB.fallback_font
	var inner := WIDTH - 2.0 * PAD
	var h := 2.0 * PAD + 4.0
	for b in blocks:
		h += _height(font, b, inner)
	var pos := Vector2(anchor.x - WIDTH / 2.0, anchor.y + 12.0)
	pos.x = clampf(pos.x, bounds.position.x + 6, bounds.end.x - WIDTH - 6)
	if pos.y + h > bounds.end.y - 6:
		pos.y = anchor.y - h - 36.0
	pos.y = clampf(pos.y, bounds.position.y + 6, bounds.end.y - h - 6)
	_box = Rect2(pos.round(), Vector2(WIDTH, h))
	c.draw_rect(Rect2(_box.position + Vector2(3, 5), _box.size), Color(0, 0, 0, 0.3))
	c.draw_rect(_box, Props.INK)
	c.draw_rect(_box.grow(-2), Props.PAPER)
	c.draw_circle(_box.position + Vector2(WIDTH / 2.0, 7), 4, Props.PIN_COLORS[0])
	c.draw_circle(_box.position + Vector2(WIDTH / 2.0 - 1, 6), 1.5, Color(1, 1, 1, 0.7))
	_buttons = []
	var y := _box.position.y + PAD + 4.0
	var x := _box.position.x + PAD
	for b in blocks:
		match b["t"]:
			"title":
				c.draw_string(
					font,
					Vector2(x, y + font.get_ascent(20)),
					b["text"],
					HORIZONTAL_ALIGNMENT_LEFT,
					inner,
					20,
					Props.INK
				)
			"text", "dim":
				var fs := 16 if b["t"] == "text" else 13
				var col := Props.INK if b["t"] == "text" else Color(Props.INK, 0.6)
				c.draw_multiline_string(
					font,
					Vector2(x, y + font.get_ascent(fs)),
					b["text"],
					HORIZONTAL_ALIGNMENT_LEFT,
					inner,
					fs,
					-1,
					col
				)
			"month":
				_draw_month(c, font, Vector2(x, y), inner, b)
			"buttons":
				var bx := x
				for item in b["items"]:
					var w := (
						font.get_string_size(item["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
					)
					var r := Rect2(Vector2(bx, y + 2), Vector2(w + 24, 28))
					bx += r.size.x + 8.0
					_buttons.append({"rect": r, "act": item["act"]})
					c.draw_rect(r, Props.INK)
					var lit := _buttons.size() - 1 == _hover
					c.draw_rect(r.grow(-2), Color("f8efb8") if lit else Color("e4d8bd"))
					c.draw_string(
						font,
						r.position + Vector2(12, 19),
						item["label"],
						HORIZONTAL_ALIGNMENT_LEFT,
						-1,
						15,
						Props.INK
					)
		y += _height(font, b, inner)


func _draw_month(c: CanvasItem, font: Font, at: Vector2, inner: float, b: Dictionary) -> void:
	var title: String = "%s %d" % [MONTHS[int(b["month"]) - 1], int(b["year"])]
	c.draw_string(
		font,
		at + Vector2(0, font.get_ascent(17)),
		title,
		HORIZONTAL_ALIGNMENT_LEFT,
		inner,
		17,
		Props.INK
	)
	var top := at + Vector2((inner - 7.0 * CELL.x) / 2.0, font.get_height(17) + 8.0)
	for i in 7:
		var w := font.get_string_size(WEEK[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		c.draw_string(
			font,
			top + Vector2(i * CELL.x + (CELL.x - w) / 2.0, 16),
			WEEK[i],
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			12,
			Color(Props.INK, 0.55)
		)
	var info := month_info(b["year"], b["month"])
	var marks: Dictionary = b.get("marks", {})
	for d in range(1, int(info["days"]) + 1):
		var idx: int = int(info["first"]) + d - 1
		var cell := top + Vector2((idx % 7) * CELL.x, CELL.y + (idx / 7) * CELL.y)
		var mid := cell + CELL / 2.0
		if d == int(b.get("today", 0)):
			c.draw_circle(mid + Vector2(0, -1), 11.0, Color("e8b86d"))
		var label := str(d)
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		c.draw_string(
			font,
			cell + Vector2((CELL.x - w) / 2.0, 17),
			label,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			14,
			Props.INK
		)
		if marks.has(d):
			c.draw_circle(mid + Vector2(0, 11), 2.6, Color("c8483f"))
