extends RefCounted

# The days ahead on the window's card: which of what the server or wttr.in gave are still to come,
# what to call each, and a small code-drawn icon for its kind.
const Props := preload("res://props.gd")
const DAYS := ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
const KINDS := ["clear", "partly", "cloudy", "fog", "rain", "snow", "storm"]
const SHOWN := 3
const WET_FROM := 20
const SUN := Color("e8a920")
const CLOUD := Color("8d97a5")
const DROP := Color("4a78b8")
const FLAKE := Color("7fa8c8")
const BOLT := Color("e8c030")
const BOLT_SHAPE := [
	Vector2(0.1, 0.0),
	Vector2(-0.12, 0.26),
	Vector2(-0.01, 0.26),
	Vector2(-0.1, 0.52),
	Vector2(0.16, 0.16),
	Vector2(0.04, 0.16),
]


# the days from `today` ("YYYY-MM-DD") on that read as a day, at most three: a stale forecast drops
# the days already gone
static func upcoming(days: Variant, today: String) -> Array:
	var out: Array = []
	if not days is Array:
		return out
	for d in days:
		if (
			d is Dictionary
			and d.get("date") is String
			and str(d["date"]) >= today
			and d.get("kind") in KINDS
			and (d.get("high_c") is int or d.get("high_c") is float)
			and (d.get("low_c") is int or d.get("low_c") is float)
		):
			out.append(d)
	return out.slice(0, SHOWN)


# Today, Tomorrow, then the weekday
static func name_of(date: String, today: String) -> String:
	if date == today:
		return "Today"
	var at := int(Time.get_unix_time_from_datetime_string(date + "T00:00:00"))
	var then := int(Time.get_unix_time_from_datetime_string(today + "T00:00:00"))
	if at == then + 86400:
		return "Tomorrow"
	return DAYS[Time.get_datetime_dict_from_unix_time(at)["weekday"]]


# the chance of rain or snow, when it is worth a word
static func wet_text(day: Dictionary) -> String:
	var wet := int(day.get("wet", 0))
	if wet < WET_FROM:
		return ""
	return "%d%% %s" % [wet, "snow" if day["kind"] == "snow" else "rain"]


static func draw_icon(c: CanvasItem, kind: String, at: Vector2, s: float) -> void:
	match kind:
		"clear":
			_sun(c, at, s * 0.3, s * 0.46)
		"partly":
			_sun(c, at + Vector2(-s * 0.16, -s * 0.16), s * 0.2, s * 0.32)
			_cloud(c, at + Vector2(s * 0.04, s * 0.1), s * 0.8)
		"cloudy":
			_cloud(c, at, s)
		"fog":
			for i in 3:
				var y := at.y - s * 0.28 + i * s * 0.28
				var half := s * (0.42 if i != 1 else 0.3)
				var x := at.x + (s * 0.1 if i == 1 else 0.0)
				c.draw_line(Vector2(x - half, y), Vector2(x + half, y), Props.INK, 2.0)
		"rain":
			_cloud(c, at + Vector2(0, -s * 0.14), s * 0.9)
			for i in 3:
				var x := at.x - s * 0.24 + i * s * 0.24
				var y := at.y + s * 0.26
				c.draw_line(Vector2(x, y), Vector2(x - s * 0.08, y + s * 0.2), DROP, 2.0)
		"snow":
			_cloud(c, at + Vector2(0, -s * 0.14), s * 0.9)
			for i in 3:
				var p := Vector2(at.x - s * 0.24 + i * s * 0.24, at.y + s * 0.34 - (i % 2) * 2.0)
				c.draw_circle(p, 2.2, FLAKE)
				c.draw_arc(p, 2.2, 0.0, TAU, 8, Props.INK, 1.0)
		"storm":
			_cloud(c, at + Vector2(0, -s * 0.14), s * 0.9)
			var bolt := PackedVector2Array()
			for p in BOLT_SHAPE:
				bolt.append(at + p * s)
			c.draw_colored_polygon(bolt, BOLT)


static func _sun(c: CanvasItem, at: Vector2, r: float, ray: float) -> void:
	for i in 8:
		var a := i * TAU / 8.0
		var dir := Vector2(cos(a), sin(a))
		c.draw_line(at + dir * (r + 2.0), at + dir * ray, SUN, 2.0)
	c.draw_circle(at, r, SUN)
	c.draw_arc(at, r, 0.0, TAU, 16, Props.INK, 1.0)


static func _cloud(c: CanvasItem, at: Vector2, s: float) -> void:
	var puffs := [
		[Vector2(-0.22, 0.06), 0.2],
		[Vector2(0.02, -0.08), 0.26],
		[Vector2(0.24, 0.06), 0.18],
	]
	var base := Rect2(at + Vector2(-0.36, 0.06) * s, Vector2(0.72, 0.2) * s)
	for pass_i in 2:
		var grow := 1.0 if pass_i == 0 else 0.0
		var col := Props.INK if pass_i == 0 else CLOUD
		for p in puffs:
			c.draw_circle(at + p[0] * s, p[1] * s + grow, col)
		c.draw_rect(base.grow(grow), col)
