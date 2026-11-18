extends RefCounted

# The office through the door: a coworker who leans in when something waits on the operator, and a
# paper plane for each landing. Both come from the polled `/api/office`.
const Props := preload("res://props.gd")
const DOORWAY := Vector2(0.5, 7.5)
const PLANE_FROM := Vector3(0.5, 7.4, 26.0)
const PLANE_TO := Vector3(4.95, 0.95, 17.2)
const FLIGHT := 1.7
const PLANE_STAYS := 300.0
const CAPTION_MAX := 46

var want := {}
var shown := {}
var lean := 0.0
var plane := {}
var seen: Dictionary = {}
var primed := false
var t := 0.0


static func _cap(text: String, n: int) -> String:
	return text if text.length() <= n else text.substr(0, n - 1) + "..."


static func visitor(d: Dictionary) -> Dictionary:
	if d.get("pause") != null:
		return {}
	var asks := {}
	var order: Array = []
	for th in d.get("threads", []):
		if th.get("prompt") != null:
			asks[th["id"]] = "asks: " + str(th["prompt"].get("summary", ""))
		elif th.get("awaiting") != null:
			asks[th["id"]] = str(th.get("title", "waiting on you"))
		else:
			continue
		order.append(th)
	var bench: Array = d.get("bench", [])
	for r in d.get("roster", []):
		if r.get("status") == "waiting":
			var text: String = asks.get(r.get("thread_id"), str(r.get("title", "waiting on you")))
			return {
				"name": str(r["agent"]),
				"text": _cap(text, CAPTION_MAX),
				"skin": _skin(bench, str(r["agent"]))
			}
	if not order.is_empty():
		var th: Dictionary = order[0]
		var lead := str(th.get("lead", "")) if th.get("lead") != null else ""
		return {
			"name": lead if lead != "" else "someone",
			"text": _cap(str(asks[th["id"]]), CAPTION_MAX),
			"skin": _skin(bench, lead)
		}
	if int(d.get("awaiting", 0)) > 0:
		return {"name": "someone", "text": "something waits on you", "skin": 0}
	return {}


static func _skin(bench: Array, name: String) -> int:
	for i in bench.size():
		if str(bench[i].get("name", "")) == name:
			return i
	return 0


static func fresh_landings(landings: Array, seen_refs: Dictionary) -> Array:
	var out: Array = []
	for l in landings:
		var ref := str(l.get("ref", ""))
		if ref != "" and not seen_refs.has(ref):
			out.append(l)
	return out


func update_office(d: Dictionary) -> void:
	want = visitor(d)
	var landings: Array = d.get("landings", []) if d.get("landings") is Array else []
	var fresh := fresh_landings(landings, seen)
	for l in landings:
		seen[str(l.get("ref", ""))] = true
	if primed and not fresh.is_empty():
		fly(str(fresh[0].get("subject", "landed")))
	primed = true


func fly(title: String) -> void:
	plane = {"t": 0.0, "title": title}


func show_visitor(who: String, text: String) -> void:
	want = {"name": who, "text": text, "skin": 0}
	shown = want
	lean = 1.0


func dismiss_plane() -> void:
	plane = {}


func ajar() -> bool:
	return lean > 0.05 or (not plane.is_empty() and plane["t"] < FLIGHT + 0.3)


func present() -> bool:
	return lean > 0.9 and not shown.is_empty()


func process(dt: float) -> void:
	t += dt
	if not want.is_empty():
		shown = want
		lean = minf(1.0, lean + dt * 1.6)
	else:
		lean = maxf(0.0, lean - dt * 1.6)
		if lean <= 0.0:
			shown = {}
	if not plane.is_empty():
		plane["t"] += dt
		if plane["t"] > FLIGHT + PLANE_STAYS:
			plane = {}


func plane_landed() -> bool:
	return not plane.is_empty() and plane["t"] >= FLIGHT


func draw_visitor(
	c: CanvasItem, room: Control, o: Vector2, k: int, bounds: Rect2
) -> PackedVector2Array:
	if lean <= 0.01 or shown.is_empty():
		return PackedVector2Array()
	var e := lean * lean * (3.0 - 2.0 * lean)
	var cell := lerpf(0.05, 0.95, e)
	var feet := Props.floor_pt(o, k, cell, DOORWAY.y) + Vector2(0, 0)
	var skin: int = int(shown["skin"]) % room.SKINS.size()
	var name: String = room.SKINS[skin]
	var sheet: Texture2D = room._load_texture(
		room._person_dir() + "Sheets/%dx/%s/%s_idle.png" % [k, name, name]
	)
	c.draw_set_transform(feet, 0.1 * (1.0 - e * 0.4), Vector2.ONE)
	if sheet == null:
		c.draw_circle(Vector2(0, -26 * k), 8 * k, Color("e0b07a", e))
		c.draw_rect(
			Rect2(Vector2(-6 * k, -24 * k), Vector2(12 * k, 24 * k)),
			Color(room.SKIN_FALLBACK[skin], e)
		)
	else:
		var cellpx := 64 * k
		var frame: int = int(t * room.FRAME_FPS) % room.FRAMES
		c.draw_texture_rect_region(
			sheet,
			Rect2(Vector2(-32, -46) * k, Vector2(cellpx, cellpx)),
			Rect2(frame * cellpx, 7 * cellpx, cellpx, cellpx),
			Color(1, 1, 1, e)
		)
	var hand := Vector2(-12 + 3.0 * sin(t * 11.0), -39 + 2.0 * cos(t * 11.0)) * k
	c.draw_line(
		Vector2(-6, -27) * k, hand, Color(room.SKIN_FALLBACK[skin].lightened(0.2), e), 2.2 * k
	)
	c.draw_circle(hand, 1.8 * k, Color("e0b07a", e))
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if e > 0.8:
		var m := feet + Vector2(12, -48) * k
		c.draw_circle(m, 10, Props.INK)
		c.draw_circle(m, 8, Color("e8b86d"))
		c.draw_string(
			ThemeDB.fallback_font,
			m + Vector2(-2.5, 6),
			"!",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			15,
			Props.INK
		)
		Props.bubble(
			c,
			feet + Vector2(78, -50 * k),
			"%s: %s" % [shown["name"], shown["text"]],
			bounds,
			1.0,
			13
		)
	return PackedVector2Array(
		[
			feet + Vector2(-14, -48) * k,
			feet + Vector2(14, -48) * k,
			feet + Vector2(14, 2) * k,
			feet + Vector2(-14, 2) * k
		]
	)


func draw_plane(c: CanvasItem, o: Vector2, k: int, bounds: Rect2) -> PackedVector2Array:
	if plane.is_empty():
		return PackedVector2Array()
	var a := Props.floor_pt(o, k, PLANE_FROM.x, PLANE_FROM.y, PLANE_FROM.z)
	var b := Props.floor_pt(o, k, PLANE_TO.x, PLANE_TO.y, PLANE_TO.z)
	var u := minf(plane["t"] / FLIGHT, 1.0)
	var at := a.lerp(b, u) + Vector2(0, -34.0 * k * sin(PI * u) * (1.0 - u * 0.4))
	var ahead := (
		a.lerp(b, minf(u + 0.04, 1.0)) + Vector2(0, -34.0 * k * sin(PI * minf(u + 0.04, 1.0)))
	)
	var ang := (ahead - at).angle() if u < 1.0 else -0.45
	_paper_plane(c, at, ang, k, u >= 1.0)
	if u < 1.0:
		return PackedVector2Array()
	var lines := _wrap(str(plane["title"]), 28)
	var tag_at := b + Vector2(0, 8 * k)
	Props.tag(c, tag_at, lines, bounds)
	return PackedVector2Array(
		[
			b + Vector2(-9, -8) * k,
			b + Vector2(9, -8) * k,
			b + Vector2(9, 4) * k,
			b + Vector2(-9, 4) * k
		]
	)


static func _wrap(text: String, width: int) -> Array:
	var lines: Array = []
	var line := ""
	for word in text.split(" "):
		if line != "" and line.length() + word.length() + 1 > width:
			lines.append(line)
			line = word
		else:
			line = word if line == "" else line + " " + word
		if lines.size() == 2:
			break
	if lines.size() < 3 and line != "":
		lines.append(line)
	if lines.size() > 2:
		lines = lines.slice(0, 2)
		lines[1] = _cap(str(lines[1]), width - 1)
	return lines


func _paper_plane(c: CanvasItem, at: Vector2, ang: float, k: int, flat: bool) -> void:
	var s := 1.3 * k
	var pts := PackedVector2Array(
		[Vector2(9, 0) * s, Vector2(-7, -5) * s, Vector2(-4, 0) * s, Vector2(-7, 5) * s]
	)
	c.draw_set_transform(at, ang, Vector2(1.0, 0.7 if flat else 1.0))
	c.draw_colored_polygon(Props.shifted(pts, Vector2(1, 2) * s), Color(0, 0, 0, 0.22))
	c.draw_colored_polygon(pts, Props.PAPER)
	c.draw_colored_polygon(PackedVector2Array([pts[0], pts[1], pts[2]]), Color("ffffff"))
	c.draw_colored_polygon(PackedVector2Array([pts[0], pts[2], pts[3]]), Props.PAPER_SHADE)
	c.draw_polyline(
		PackedVector2Array([pts[1], pts[0], pts[3], pts[2], pts[1]]), Color(Props.INK, 0.6), 1.0
	)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
