extends RefCounted

# After dark, a soft light texture of the light pack at each light of the room: warm for the
# lamp, the fire, candles and the pumpkin, cool for the TV and the moon. SOURCES is the one
# table: the texture, its colour, its width in room pixels (times the room's scale), its
# strength and how far above the source's point it sits. By day nothing is drawn.
const Props := preload("res://props.gd")
const View := preload("res://view.gd")
const Looks := preload("res://looks.gd")
const DIR := "light-textures/Gridwright 2D Lights & Glow/Textures/smooth/alpha/"
const RADIAL := DIR + "radial/radial_soft_256.png"
const POOL := DIR + "pools/pool_256x128.png"
const SOURCES := {
	"lamp_pool": {"file": POOL, "color": Color("ffb860"), "size": 100.0, "alpha": 0.4, "up": 0.0},
	"lamp": {"file": RADIAL, "color": Color("ffc070"), "size": 64.0, "alpha": 0.4, "up": 0.0},
	"fire": {"file": RADIAL, "color": Color("ff8a3a"), "size": 64.0, "alpha": 0.5, "up": 6.0},
	"tv": {"file": RADIAL, "color": Color("8cb4ff"), "size": 100.0, "alpha": 0.4, "up": 0.0},
	"moon": {"file": RADIAL, "color": Color("b4c4ff"), "size": 40.0, "alpha": 0.4, "up": 0.0},
	"candles": {"file": RADIAL, "color": Color("ffc470"), "size": 52.0, "alpha": 0.5, "up": 8.0},
	"pumpkin": {"file": RADIAL, "color": Color("ffa040"), "size": 40.0, "alpha": 0.55, "up": 0.0},
}
const FLICKS := 32

static var _flick := PackedFloat32Array()


static func files() -> Array:
	var out: Array = []
	for s in SOURCES.values():
		if s["file"] not in out:
			out.append(s["file"])
	return out


static func shown() -> bool:
	return Looks.on("glow") and Looks.tex(RADIAL) != null


# 0.85-1.0, a seeded table stepped ten times a second and smoothed between the steps
static func flicker(t: float) -> float:
	if _flick.is_empty():
		var r := RandomNumberGenerator.new()
		r.seed = 5
		for i in FLICKS:
			_flick.append(r.randf_range(0.85, 1.0))
	var f := t * 10.0
	var i := int(f)
	return lerpf(_flick[i % FLICKS], _flick[(i + 1) % FLICKS], f - i)


# what to draw: [{tex, rect, color, clip}], each light kept inside its `clip` polygon (the room's
# outline, or the window's glass for the moon) so none spills onto the desktop behind the room
static func plan(h) -> Array:
	var out: Array = []
	if not shown():
		return out
	var env: Dictionary = h._env
	var k: int = h._k
	var dark := clampf(1.0 - float(env["day"]) * 2.0, 0.0, 1.0)
	var room := Props.hex(h._o, k, h.COLS, h.ROWS, h.WALL_H)
	var lamp := float(env["lamp"])
	_add(out, "lamp_pool", Props.floor_pt(h._o, k, 1.5, 6.5), lamp, k, room)
	_add(out, "lamp", Props.floor_pt(h._o, k, 0.5, 6.5, 30), lamp, k, room)
	if dark <= 0.0:
		return out
	if h.fire_on():
		_add(out, "fire", h.hearth.mouth(), dark * flicker(h._t), k, room)
	if h.tv.on:
		_add(out, "tv", Props.center(h._tv_quad()), dark, k, room)
	var q := View.quad(h._o, k)
	if str(env["weather"]) in ["clear", "partly"]:
		_add(out, "moon", Props.qlerp(q, 0.7, 0.72), dark, k, q)
	for p in h.layout.pieces + h.layout.guests:
		if str(p["p"]).contains("candle"):
			var r: Rect2i = h.layout.rect(p)
			var cx := r.position.x + r.size.x / 2.0
			var cy := r.position.y + r.size.y / 2.0
			var at: Vector2 = h._p(cx, cy, float(h.layout.height(p)))
			_add(out, "candles", at, dark * flicker(h._t + cx), k, room)
	if h._season() == "pumpkin" and h.window_frame.size() == 4:
		var at := Props.qlerp(h.window_frame, 0.82, 1.0) + Vector2(0, -3 * k)
		_add(out, "pumpkin", at, dark, k, room)
	return out


static func _add(
	out: Array, id: String, at: Vector2, strength: float, k: int, clip: PackedVector2Array
) -> void:
	var s: Dictionary = SOURCES[id]
	var tex := Looks.tex(s["file"])
	if tex == null or strength < 0.03:
		return
	var size := Vector2(s["size"], s["size"] * tex.get_height() / tex.get_width()) * k
	var c: Color = s["color"]
	var rect := Rect2(at - size / 2.0 - Vector2(0, float(s["up"]) * k), size)
	var color := Color(c, float(s["alpha"]) * clampf(strength, 0.0, 1.0))
	out.append({"tex": tex, "rect": rect, "color": color, "clip": clip})


static func draw(c: CanvasItem, h) -> void:
	for g in plan(h):
		var r: Rect2 = g["rect"]
		var box := PackedVector2Array(
			[
				r.position,
				r.position + Vector2(r.size.x, 0),
				r.end,
				r.position + Vector2(0, r.size.y)
			]
		)
		for poly in Geometry2D.intersect_polygons(g["clip"], box):
			var uvs := PackedVector2Array()
			var colors := PackedColorArray()
			for p in poly:
				uvs.append((p - r.position) / r.size)
				colors.append(g["color"])
			c.draw_polygon(poly, colors, uvs, g["tex"])
