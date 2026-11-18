extends RefCounted

# The window's weather from the weather pack: its rain, snow and fog loops, and in a storm now and
# then a lightning bolt, all clipped to the glass (the quad of the pane) and nowhere else. A loop
# is a 128x128 tile whose frames sit in a grid; the pane is smaller than a tile, so one fixed
# window into each frame is shown and no tiling is needed. Frames step at most ten times a second.
const Props := preload("res://props.gd")
const Looks := preload("res://looks.gd")
const DIR := "weather-effects/Gridwright Weather FX/"
const TILE := 128
const MAX_FPS := 10.0
const OVERLAYS := DIR + "Overlays/Sheets/1x/"
# `stack` windows into the same tile, so a pane the size of a fraction of a tile is still dense
const LAYERS := {
	"rain": {"file": OVERLAYS + "rain_medium.png", "frames": 16, "fps": 15.0, "alpha": 0.85, "stack": 4},
	"storm": {"file": OVERLAYS + "rain_heavy.png", "frames": 16, "fps": 15.0, "alpha": 0.9, "stack": 6},
	"snow": {"file": OVERLAYS + "snow_medium.png", "frames": 32, "fps": 10.0, "alpha": 1.0, "stack": 8},
	"fog": {"file": OVERLAYS + "fog_thick.png", "frames": 32, "fps": 8.0, "alpha": 0.55, "stack": 1},
}
# a bolt is a row of 8 frames of 64x192 whose ground point is (32, 186); one every third flash
const BOLTS := ["lightning_bolt_a", "lightning_bolt_b", "lightning_bolt_c"]
const BOLT_SHEET := DIR + "Sprites/Sheets/1x/%s.png"
const BOLT_CELL := Vector2(64, 192)
const BOLT_GROUND := Vector2(32, 186)
const BOLT_FRAMES := 8
const FLASH_EVERY := 5.5
const FLASH_SPREAD := 3


static func files() -> Array:
	var out: Array = []
	for l in LAYERS.values():
		out.append(l["file"])
	for b in BOLTS:
		out.append(BOLT_SHEET % b)
	return out


# true when the pack draws this weather in the window (so the code-drawn drops and flakes stay out)
static func shown(weather: String) -> bool:
	return (
		Looks.on("weather_art")
		and LAYERS.has(weather)
		and Looks.tex(LAYERS[weather]["file"]) != null
	)


# what to draw in the pane `q`: [{poly, uvs, tex, color}], every polygon inside the pane's quad
static func plan(q: PackedVector2Array, k: int, weather: String, t: float, day: float) -> Array:
	var out: Array = []
	if not shown(weather):
		return out
	var box := Rect2(q[0], Vector2.ZERO)
	for p in q:
		box = box.expand(p)
	var src := box.size / k
	if src.x > TILE or src.y > TILE:
		return out
	var l: Dictionary = LAYERS[weather]
	var tex: Texture2D = Looks.tex(l["file"])
	var cols := int(tex.get_width() / TILE)
	var frame := int(t * minf(float(l["fps"]), MAX_FPS)) % int(l["frames"])
	var cell := Vector2((frame % cols) * TILE, (frame / cols) * TILE)
	var shade := lerpf(0.75, 1.0, day)
	var color := Color(shade, shade, shade, l["alpha"])
	for i in int(l["stack"]):
		var from: Vector2 = cell + ((Vector2(TILE, TILE) - src) * _spot(i)).floor()
		var uvs := PackedVector2Array()
		for p in q:
			uvs.append((from + (p - box.position) / k) / tex.get_size())
		out.append({"poly": q, "uvs": uvs, "tex": tex, "color": color})
	if weather == "storm":
		_bolt(out, q, k, t)
	return out


static func _bolt(out: Array, q: PackedVector2Array, k: int, t: float) -> void:
	var flash := int((t + 4.2) / FLASH_EVERY)
	if flash % FLASH_SPREAD != 0:
		return
	var frame := int(fmod(t + 4.2, FLASH_EVERY) * MAX_FPS)
	if frame >= BOLT_FRAMES:
		return
	var tex: Texture2D = Looks.tex(BOLT_SHEET % BOLTS[(flash / FLASH_SPREAD) % BOLTS.size()])
	if tex == null:
		return
	var u: float = [0.3, 0.55, 0.75][(flash / FLASH_SPREAD) % 3]
	var origin := Props.qlerp(q, u, 0.12) - BOLT_GROUND * k
	var cell := PackedVector2Array(
		[
			origin,
			origin + Vector2(BOLT_CELL.x * k, 0),
			origin + BOLT_CELL * k,
			origin + Vector2(0, BOLT_CELL.y * k)
		]
	)
	for poly in Geometry2D.intersect_polygons(q, cell):
		var uvs := PackedVector2Array()
		for p in poly:
			uvs.append((Vector2(frame * BOLT_CELL.x, 0) + (p - origin) / k) / tex.get_size())
		out.append({"poly": poly, "uvs": uvs, "tex": tex, "color": Color.WHITE})
	if frame <= 2:
		out.append(
			{"poly": q, "uvs": PackedVector2Array(), "tex": null, "color": Color(1, 1, 0.92, 0.22)}
		)



static func draw(
	c: CanvasItem, q: PackedVector2Array, k: int, weather: String, t: float, day: float
) -> bool:
	var layers := plan(q, k, weather, t, day)
	for g in layers:
		if g["tex"] == null:
			c.draw_colored_polygon(g["poly"], g["color"])
			continue
		var colors := PackedColorArray()
		colors.resize(g["poly"].size())
		colors.fill(g["color"])
		c.draw_polygon(g["poly"], colors, g["uvs"], g["tex"])
	return not layers.is_empty()


# where the i-th stacked window sits in the tile, as a fraction of the room left over
static func _spot(i: int) -> Vector2:
	return Vector2(fposmod(i * 0.618, 1.0), fposmod(i * 0.382 + 0.3, 1.0))
