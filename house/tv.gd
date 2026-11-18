extends RefCounted

const INK := Color("2a2530")
const FORMAT := "{{playerName}}\t{{status}}\t{{artist}}\t{{title}}"

var state := ""
var player := ""
var caption := ""
var forced := false
var last_raw := ""

var _thread: Thread
var _mutex := Mutex.new()
var _raw := ""
var _fresh := false


func force(status: String, text: String) -> void:
	forced = true
	state = status
	caption = text
	player = "demo"


func poll() -> void:
	if forced:
		return
	if _thread != null:
		if _thread.is_alive():
			return
		_thread.wait_to_finish()
	_thread = Thread.new()
	_thread.start(_run)


func _run() -> void:
	var out: Array = []
	var code := OS.execute("playerctl", ["-a", "metadata", "--format", FORMAT], out, false)
	_mutex.lock()
	_raw = str(out[0]) if code == 0 and not out.is_empty() else ""
	_fresh = true
	_mutex.unlock()


func collect() -> void:
	_mutex.lock()
	var fresh := _fresh
	var raw := _raw
	_fresh = false
	_mutex.unlock()
	if fresh:
		last_raw = raw
		_parse(raw)


func _parse(raw: String) -> void:
	var playing := []
	var paused := []
	for line in raw.split("\n", false):
		var parts := line.split("\t")
		if parts.size() < 4:
			continue
		match parts[1]:
			"Playing":
				playing.append(parts)
			"Paused":
				paused.append(parts)
	var pick: Array = []
	state = ""
	if not playing.is_empty():
		pick = playing[0]
		state = "playing"
	elif not paused.is_empty():
		pick = paused[0]
		state = "paused"
	if pick.is_empty():
		player = ""
		caption = ""
		return
	player = pick[0]
	var artist: String = pick[2].strip_edges()
	var title: String = pick[3].strip_edges()
	caption = (
		(artist + " - " + title)
		if artist != "" and title != ""
		else (title if title != "" else artist)
	)
	if caption == "":
		caption = player


func toggle() -> void:
	if state == "":
		return
	state = "paused" if state == "playing" else "playing"
	if not forced and player != "":
		OS.create_process("playerctl", ["-p", player, "play-pause"])


func exit() -> void:
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null


static func sub(
	q: PackedVector2Array, u0: float, v0: float, u1: float, v1: float
) -> PackedVector2Array:
	return PackedVector2Array(
		[
			q[0] + (q[1] - q[0]) * u0 + (q[3] - q[0]) * v0,
			q[0] + (q[1] - q[0]) * u1 + (q[3] - q[0]) * v0,
			q[0] + (q[1] - q[0]) * u1 + (q[3] - q[0]) * v1,
			q[0] + (q[1] - q[0]) * u0 + (q[3] - q[0]) * v1,
		]
	)


func screen(c: CanvasItem, q: PackedVector2Array, t: float) -> void:
	if state == "":
		return
	if state == "paused":
		c.draw_colored_polygon(q, Color("141826"))
		c.draw_colored_polygon(sub(q, 0.38, 0.3, 0.46, 0.7), Color("6c7490"))
		c.draw_colored_polygon(sub(q, 0.54, 0.3, 0.62, 0.7), Color("6c7490"))
		return
	for i in 8:
		var hue := fmod(0.62 + 0.14 * i / 8.0 + t * 0.03, 1.0)
		c.draw_colored_polygon(
			sub(q, 0, i / 8.0, 1, (i + 1) / 8.0),
			Color.from_hsv(hue, 0.55, 0.3 + 0.35 * (1.0 - i / 8.0))
		)
	for i in 7:
		var h := 0.15 + 0.6 * absf(sin(t * 2.6 + i * 1.9))
		var u0 := 0.09 + i * 0.125
		c.draw_colored_polygon(
			sub(q, u0, 0.94 - h, u0 + 0.085, 0.94),
			Color.from_hsv(fmod(0.08 + i * 0.13 + t * 0.1, 1.0), 0.5, 1.0)
		)
	var sx := fmod(t * 0.45, 1.5) - 0.25
	c.draw_colored_polygon(sub(q, sx, 0, sx + 0.12, 1), Color(1, 1, 1, 0.12))


static func note(c: CanvasItem, at: Vector2, k: int, col: Color) -> void:
	var r := 1.5 * k
	c.draw_circle(at, r, col)
	c.draw_line(at + Vector2(r * 0.9, 0), at + Vector2(r * 0.9, -4.5 * k), col, maxf(1.0, 0.6 * k))
	c.draw_line(
		at + Vector2(r * 0.9, -4.5 * k), at + Vector2(r * 2.4, -3.2 * k), col, maxf(1.0, 0.8 * k)
	)


func over(c: CanvasItem, q: PackedVector2Array, k: int, t: float, bounds: Rect2) -> void:
	if state == "":
		return
	var top := (q[0] + q[1]) / 2.0
	if state == "playing":
		for i in 3:
			var ph := fmod(t * 0.45 + i * 0.33, 1.0)
			var at := (
				top + Vector2(-6 * k + i * 6 * k + sin(t * 2.0 + i) * 2 * k, -3 * k - ph * 20 * k)
			)
			note(c, at, k, Color.from_hsv(fmod(i * 0.3 + t * 0.05, 1.0), 0.45, 1.0, 1.0 - ph))
	var font := ThemeDB.fallback_font
	var fs := 13
	var text := caption
	var width := 190.0
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width:
		var pad := text + "   "
		var off := int(t * 4.0) % pad.length()
		var wrapped := pad.substr(off) + pad + pad
		var n := 0
		while (
			n < wrapped.length()
			and (
				font.get_string_size(wrapped.substr(0, n), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				< width
			)
		):
			n += 1
		text = wrapped.substr(0, n)
	var w := minf(width, font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	var plate := Rect2(Vector2(top.x - w / 2.0 - 18, top.y - 30 - k * 4), Vector2(w + 30, 22))
	plate.position.x = clampf(
		plate.position.x, bounds.position.x + 4, bounds.end.x - plate.size.x - 4
	)
	plate.position.y = maxf(plate.position.y, bounds.position.y + 42)
	var dim := state == "paused"
	c.draw_rect(Rect2(plate.position + Vector2(2, 3), plate.size), Color(0, 0, 0, 0.25))
	c.draw_rect(plate, INK)
	c.draw_rect(plate.grow(-2), Color("3a3446") if dim else Color("231f2b"))
	if dim:
		c.draw_rect(Rect2(plate.position + Vector2(8, 6), Vector2(3, 10)), Color("a89fb0"))
		c.draw_rect(Rect2(plate.position + Vector2(13, 6), Vector2(3, 10)), Color("a89fb0"))
	else:
		note(c, plate.position + Vector2(11, 15), 2, Color("e8b86d"))
	c.draw_string(
		font,
		plate.position + Vector2(24, 15),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		fs,
		Color("a89fb0") if dim else Color("f1e9dc")
	)
