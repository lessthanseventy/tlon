extends RefCounted

const INK := Color("2a2530")
const PAPER := Color("f3ead6")
const PAPER_SHADE := Color("d9cdb4")
const CORK := Color("b98a57")
const CORK_DARK := Color("98693d")
const FRAME := Color("6b4528")
const PIN_COLORS := [Color("d9534f"), Color("4f8fd9"), Color("e8b86d"), Color("5fb37a")]
const SLIP_COLORS := [Color("f3ead6"), Color("e4eef6"), Color("f8efb8"), Color("e5f0dc")]
const HEART := ["..XX.XX..", ".XXXXXXX.", ".XXXXXXX.", "..XXXXX..", "...XXX...", "....X...."]
const NIGHT_SKY := Color("0b1030")

# hour, room tint, lamp, sunlight, sky
const DAY := [
	[0.0, Color(0.05, 0.07, 0.30, 0.48), 1.0, 0.0, Color("0b1030")],
	[5.0, Color(0.05, 0.07, 0.30, 0.48), 1.0, 0.0, Color("0b1030")],
	[6.5, Color(1.0, 0.62, 0.45, 0.12), 0.5, 0.3, Color("e8a58c")],
	[8.0, Color(1.0, 0.95, 0.8, 0.0), 0.0, 1.0, Color("7fb8ec")],
	[16.0, Color(1.0, 0.95, 0.8, 0.0), 0.0, 1.0, Color("7fb8ec")],
	[18.0, Color(1.0, 0.55, 0.18, 0.16), 0.3, 0.7, Color("f0a35c")],
	[19.5, Color(0.7, 0.35, 0.35, 0.22), 0.8, 0.2, Color("5a3f7a")],
	[21.0, Color(0.05, 0.07, 0.30, 0.48), 1.0, 0.0, Color("0b1030")],
	[24.0, Color(0.05, 0.07, 0.30, 0.48), 1.0, 0.0, Color("0b1030")],
]
# weather kind: sky colour, how far the sky goes to it, sun let through, room tint added
const SKIES := {
	"clear": [Color("7fb8ec"), 0.0, 1.0, Color(0, 0, 0, 0)],
	"partly": [Color("a8c4de"), 0.25, 0.65, Color(0, 0, 0, 0.02)],
	"cloudy": [Color("98a2ae"), 0.7, 0.0, Color(0.3, 0.33, 0.4, 0.16)],
	"fog": [Color("c4c8cc"), 0.85, 0.0, Color(0.8, 0.82, 0.85, 0.14)],
	"rain": [Color("5c6a80"), 0.9, 0.0, Color(0.12, 0.18, 0.32, 0.34)],
	"storm": [Color("343d50"), 0.95, 0.0, Color(0.06, 0.08, 0.2, 0.42)],
	"snow": [Color("c8d2e0"), 0.8, 0.15, Color(0.85, 0.9, 1.0, 0.1)],
}


static func wall_pt(o: Vector2, k: int, side: int, s: float, h: float) -> Vector2:
	return o + Vector2(side * s, s * 0.5 - h) * k


static func floor_pt(o: Vector2, k: int, x: float, y: float, z: float = 0.0) -> Vector2:
	return o + Vector2(16.0 * (x - y), 8.0 * (x + y) - z) * k


static func wall_quad(
	o: Vector2, k: int, side: int, s0: float, h0: float, w: float, hh: float, rot: float = 0.0
) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var l: Vector2 = Vector2(corner.x * w * 0.5, corner.y * hh * 0.5).rotated(rot)
		pts.append(wall_pt(o, k, side, s0 + l.x, h0 + l.y))
	return pts


static func floor_quad(
	o: Vector2, k: int, x: float, y: float, z: float, a: float, b: float, rot: float = 0.0
) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var l: Vector2 = Vector2(corner.x * a, corner.y * b).rotated(rot)
		pts.append(floor_pt(o, k, x + l.x, y + l.y, z))
	return pts


static func qlerp(q: PackedVector2Array, u: float, v: float) -> Vector2:
	return q[0] + (q[1] - q[0]) * u + (q[3] - q[0]) * v


static func shifted(q: PackedVector2Array, d: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in q:
		out.append(p + d)
	return out


static func center(q: PackedVector2Array) -> Vector2:
	return (q[0] + q[1] + q[2] + q[3]) / 4.0


static func slip(
	c: CanvasItem, k: int, q: PackedVector2Array, paper: Color, lines: int, pin: Color, hot: bool
) -> void:
	var lift := Vector2(0, -1.5 * k) if hot else Vector2.ZERO
	c.draw_colored_polygon(shifted(q, Vector2(1.2, 1.8) * k + lift), Color(0, 0, 0, 0.28))
	q = shifted(q, lift)
	c.draw_colored_polygon(q, paper.lightened(0.12) if hot else paper)
	var w := maxf(1.0, 0.6 * k)
	for i in lines:
		var v := 0.72 - 0.2 * i
		c.draw_line(qlerp(q, 0.15, v), qlerp(q, 0.85 - 0.25 * (i % 2), v), Color(INK, 0.55), w)
	if pin.a > 0.0:
		var at := qlerp(q, 0.5, 0.92)
		c.draw_circle(at, 1.5 * k, Color(0, 0, 0, 0.3))
		c.draw_circle(at - Vector2(0, 0.4 * k), 1.4 * k, pin)
		c.draw_circle(at + Vector2(-0.5, -0.9) * k, 0.45 * k, Color(1, 1, 1, 0.7))


static func corkboard(
	c: CanvasItem, o: Vector2, k: int, s0: float, h0: float, w: float, hh: float
) -> PackedVector2Array:
	var frame := wall_quad(o, k, 1, s0 + w / 2.0, h0 + hh / 2.0, w + 3.0, hh + 3.0)
	c.draw_colored_polygon(shifted(frame, Vector2(1, 2) * k), Color(0, 0, 0, 0.25))
	c.draw_colored_polygon(frame, FRAME)
	var cork := wall_quad(o, k, 1, s0 + w / 2.0, h0 + hh / 2.0, w, hh)
	c.draw_colored_polygon(cork, CORK)
	for i in 26:
		var u := fmod(i * 0.6180339, 1.0)
		var v := fmod(i * 0.7548776 + 0.13, 1.0)
		var p := qlerp(cork, u, v)
		c.draw_rect(Rect2(p, Vector2(k, k)), CORK_DARK if i % 3 != 0 else CORK.lightened(0.18))
	return cork


static func heart(c: CanvasItem, at: Vector2, px: int, col: Color) -> void:
	for y in HEART.size():
		for x in HEART[y].length():
			if HEART[y][x] == "X":
				c.draw_rect(Rect2(at + Vector2(x - 4.5, y - 6) * px, Vector2(px, px)), col)


static func bubble(
	c: CanvasItem, tip: Vector2, text: String, bounds: Rect2, alpha: float, font_size: int = 14
) -> void:
	var font := ThemeDB.fallback_font
	var wrap := 168.0
	var sz := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, wrap, font_size)
	var box := Vector2(sz.x + 18, sz.y + 14)
	var pos := Vector2(tip.x - box.x / 2.0, tip.y - box.y - 10)
	pos.x = clampf(pos.x, bounds.position.x + 4, bounds.end.x - box.x - 4)
	pos.y = maxf(pos.y, bounds.position.y + 4)
	var r := Rect2(pos.round(), box)
	var ink := Color(INK, alpha)
	c.draw_rect(Rect2(r.position + Vector2(2, 3), r.size), Color(0, 0, 0, 0.25 * alpha))
	c.draw_rect(r, ink)
	c.draw_rect(r.grow(-2), Color(PAPER, alpha))
	var tx := clampf(tip.x, r.position.x + 12, r.end.x - 12)
	var ty := r.end.y - 1
	c.draw_colored_polygon(
		PackedVector2Array([Vector2(tx - 6, ty - 1), Vector2(tx + 6, ty - 1), Vector2(tx, ty + 8)]),
		ink
	)
	c.draw_colored_polygon(
		PackedVector2Array([Vector2(tx - 4, ty - 2), Vector2(tx + 4, ty - 2), Vector2(tx, ty + 5)]),
		Color(PAPER, alpha)
	)
	c.draw_multiline_string(
		font,
		r.position + Vector2(9, 7 + font.get_ascent(font_size)),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		wrap,
		font_size,
		-1,
		ink
	)


static func card(c: CanvasItem, below: Vector2, text: String, bounds: Rect2) -> void:
	var font := ThemeDB.fallback_font
	var fs := 16
	var wrap := 250.0
	var sz := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, wrap, fs)
	var box := Vector2(sz.x + 28, sz.y + 24)
	var pos := Vector2(below.x - box.x / 2.0, below.y + 12)
	pos.x = clampf(pos.x, bounds.position.x + 6, bounds.end.x - box.x - 6)
	pos.y = clampf(pos.y, bounds.position.y + 6, bounds.end.y - box.y - 6)
	var r := Rect2(pos.round(), box)
	c.draw_rect(Rect2(r.position + Vector2(3, 5), r.size), Color(0, 0, 0, 0.3))
	c.draw_rect(r, INK)
	c.draw_rect(r.grow(-2), PAPER)
	c.draw_circle(r.position + Vector2(box.x / 2.0, 7), 4, PIN_COLORS[0])
	c.draw_circle(r.position + Vector2(box.x / 2.0 - 1, 6), 1.5, Color(1, 1, 1, 0.7))
	c.draw_multiline_string(
		font,
		r.position + Vector2(14, 16 + font.get_ascent(fs)),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		wrap,
		fs,
		-1,
		INK
	)


static func env_at(hour: float, weather: String) -> Dictionary:
	var a: Array = DAY[0]
	var b: Array = DAY[DAY.size() - 1]
	for i in DAY.size() - 1:
		if hour >= DAY[i][0] and hour <= DAY[i + 1][0]:
			a = DAY[i]
			b = DAY[i + 1]
			break
	var t: float = (hour - a[0]) / maxf(0.001, b[0] - a[0])
	var wx: Array = SKIES.get(weather, SKIES["clear"])
	var day_amount: float = clampf(a[3] + (b[3] - a[3]) * t, 0.0, 1.0)
	var sky: Color = (a[4] as Color).lerp(b[4], t)
	sky = sky.lerp((wx[0] as Color).darkened(1.0 - maxf(day_amount, 0.25)), wx[1])
	return {
		"tint": (a[1] as Color).lerp(b[1], t),
		"weather_tint": wx[3],
		"lamp":
		clampf(
			(
				a[2]
				+ (b[2] - a[2]) * t
				+ (0.6 if weather in ["storm", "rain"] and day_amount > 0.3 else 0.0)
			),
			0.0,
			1.0
		),
		"sun": day_amount * wx[2],
		"day": day_amount,
		"sky": sky,
		"weather": weather,
		"hour": hour,
	}


static func hex(o: Vector2, k: int, cols: int, rows: int, wall_h: int) -> PackedVector2Array:
	return PackedVector2Array(
		[
			floor_pt(o, k, 0, 0, wall_h),
			floor_pt(o, k, cols, 0, wall_h),
			floor_pt(o, k, cols, 0),
			floor_pt(o, k, cols, rows),
			floor_pt(o, k, 0, rows),
			floor_pt(o, k, 0, rows, wall_h),
		]
	)


static func pane(
	c: CanvasItem,
	o: Vector2,
	k: int,
	side: int,
	s0: float,
	s1: float,
	h0: float,
	h1: float,
	env: Dictionary,
	t: float,
	moon: bool
) -> void:
	var q := wall_quad(o, k, side, (s0 + s1) / 2.0, (h0 + h1) / 2.0, s1 - s0, h1 - h0)
	var weather: String = env["weather"]
	var sky: Color = env["sky"]
	c.draw_colored_polygon(q, Color(sky, 0.94))
	var night: bool = env["day"] < 0.15
	var clear: bool = weather in ["clear", "partly"]
	if night and clear:
		for i in 3:
			var p := qlerp(q, 0.25 + 0.25 * i, 0.3 + 0.22 * ((i * 2) % 3))
			c.draw_rect(
				Rect2(p, Vector2(k, k)), Color("f8f0c8", 0.6 + 0.4 * sin(t * 2.0 + i * 2.0))
			)
		if moon:
			c.draw_circle(qlerp(q, 0.62, 0.78), 1.6 * k, Color("f2eec8"))
	elif clear and env["sun"] > 0.3 and env["day"] > 0.5:
		c.draw_circle(qlerp(q, 0.3, 0.78), 1.7 * k, Color("ffe27a"))
	if weather in ["partly", "cloudy", "fog", "storm", "rain", "snow"]:
		var cloud := (
			Color("f4f6f8", 0.85) if weather in ["partly", "snow", "fog"] else Color("9aa3ae", 0.9)
		)
		c.draw_circle(qlerp(q, 0.4, 0.82), 1.8 * k, cloud)
		c.draw_circle(qlerp(q, 0.7, 0.76), 1.5 * k, cloud)
	if weather in ["rain", "storm"]:
		for i in 6:
			var ph: float = fmod(t * 1.7 + i * 0.37, 1.0)
			var u: float = 0.12 + 0.76 * fmod(i * 0.618, 1.0)
			var top := qlerp(q, u, 0.85 - ph * 0.7)
			c.draw_line(
				top, top + Vector2(-0.5, 2.6) * k, Color("e4f0fc", 0.95), maxf(1.0, 0.6 * k)
			)
	elif weather == "snow":
		for i in 6:
			var ph: float = fmod(t * 0.5 + i * 0.29, 1.0)
			var u: float = 0.12 + 0.76 * fmod(i * 0.618, 1.0) + 0.05 * sin(t * 2 + i)
			c.draw_rect(
				Rect2(qlerp(q, clampf(u, 0.1, 0.9), 0.9 - ph * 0.8), Vector2(k, k)), Color.WHITE
			)
	if weather == "storm" and fmod(t, 7.0) < 0.18:
		c.draw_colored_polygon(q, Color(1, 1, 0.9, 0.7))


static func tint_room(c: CanvasItem, hex_poly: PackedVector2Array, env: Dictionary) -> void:
	var t: Color = env["tint"]
	if t.a > 0.005:
		c.draw_colored_polygon(hex_poly, t)
	var wt: Color = env["weather_tint"]
	if wt.a > 0.005:
		c.draw_colored_polygon(hex_poly, wt)


static func sun_patch(
	c: CanvasItem, o: Vector2, k: int, x0: float, y0: float, strength: float
) -> void:
	if strength < 0.05:
		return
	var q := PackedVector2Array(
		[
			floor_pt(o, k, x0, y0),
			floor_pt(o, k, x0 + 2.6, y0 + 0.55),
			floor_pt(o, k, x0 + 2.6, y0 + 1.3),
			floor_pt(o, k, x0, y0 + 0.75),
		]
	)
	c.draw_colored_polygon(q, Color(1.0, 0.93, 0.62, 0.3 * strength))
	var bar := Color(0.4, 0.3, 0.2, 0.16 * strength)
	c.draw_line(qlerp(q, 0.0, 0.5), qlerp(q, 1.0, 0.5), bar, k)
	c.draw_line(qlerp(q, 0.5, 0.0), qlerp(q, 0.5, 1.0), bar, k)


static func lamp_glow(c: CanvasItem, o: Vector2, k: int, strength: float) -> void:
	if strength < 0.03:
		return
	var bulb := floor_pt(o, k, 0.5, 6.5, 30)
	for i in 5:
		c.draw_circle(bulb, (46 - i * 8) * k * 0.55, Color(1.0, 0.82, 0.45, 0.065 * strength))
	var pool := PackedVector2Array()
	var mid := floor_pt(o, k, 1.5, 6.5)
	for i in 20:
		var a := TAU * i / 20.0
		pool.append(mid + Vector2(cos(a) * 62, sin(a) * 31) * k * 0.55)
	c.draw_colored_polygon(pool, Color(1.0, 0.8, 0.42, 0.13 * strength))
	c.draw_circle(bulb, 2.6 * k, Color(1.0, 0.95, 0.7, 0.9 * strength))


static func steam(c: CanvasItem, base: Vector2, k: int, t: float) -> void:
	for i in 3:
		var ph: float = fmod(t * 0.6 + i * 0.33, 1.0)
		var p := base + Vector2((i - 1) * 1.6 + sin(t * 2.0 + i * 2.0) * 1.2, -ph * 11.0) * k
		var fade := 1.0 - ph
		c.draw_circle(p, (1.3 + ph) * k, Color(0.45, 0.5, 0.65, 0.45 * fade))
		c.draw_circle(p, (0.9 + ph) * k, Color(1, 1, 1, 0.95 * fade))


static func calendar(
	c: CanvasItem,
	o: Vector2,
	k: int,
	s0: float,
	h0: float,
	today: int,
	first_wd: int,
	days: int,
	due_day: int
) -> PackedVector2Array:
	var q := wall_quad(o, k, -1, s0, h0, 13.0, 16.0)
	c.draw_colored_polygon(shifted(q, Vector2(1.2, 1.8) * k), Color(0, 0, 0, 0.25))
	c.draw_colored_polygon(q, PAPER)
	c.draw_colored_polygon(
		PackedVector2Array([q[3], qlerp(q, 0.0, 0.8), qlerp(q, 1.0, 0.8), q[2]]), Color("c8483f")
	)
	for i in 2:
		c.draw_circle(qlerp(q, 0.3 + 0.4 * i, 1.0), 1.1 * k, Color(INK, 0.9))
	for d in range(1, days + 1):
		var idx := d - 1 + first_wd
		var u := 0.12 + 0.76 * (idx % 7) / 6.0
		var v := 0.7 - 0.11 * (idx / 7) - 0.04
		var col := Color(INK, 0.35)
		var sz := 1.0
		if d == due_day:
			col = Color("c8483f")
			sz = 1.8
		elif d == today:
			col = INK
			sz = 1.8
		var p := qlerp(q, u, v)
		c.draw_rect(Rect2(p - Vector2(sz * k / 2.0, sz * k / 2.0), Vector2(sz * k, sz * k)), col)
	return q


static func caption(c: CanvasItem, at: Vector2, text: String) -> void:
	if text == "":
		return
	var font := ThemeDB.fallback_font
	var fs := 15
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	c.draw_rect(Rect2(at + Vector2(-w / 2.0 - 10, -18), Vector2(w + 20, 28)), Color(INK, 0.85))
	c.draw_string(
		font, at + Vector2(-w / 2.0, 2), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("e8b86d")
	)


static func tag(c: CanvasItem, at: Vector2, lines: Array, bounds: Rect2) -> void:
	var font := ThemeDB.fallback_font
	var fs := 13
	var w := 0.0
	for l in lines:
		w = maxf(w, font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	var box := Vector2(w + 14, 8 + 16 * lines.size())
	var pos := Vector2(at.x - box.x / 2.0, at.y)
	pos.x = clampf(pos.x, bounds.position.x + 4, bounds.end.x - box.x - 4)
	var r := Rect2(pos.round(), box)
	c.draw_rect(Rect2(r.position + Vector2(2, 3), r.size), Color(0, 0, 0, 0.25))
	c.draw_rect(r, INK)
	c.draw_rect(r.grow(-1), PAPER)
	for i in lines.size():
		c.draw_string(
			font,
			r.position + Vector2(7, 4 + 16 * i + font.get_ascent(fs)),
			lines[i],
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			fs,
			INK
		)


static func badge(c: CanvasItem, at: Vector2, n: int) -> void:
	var font := ThemeDB.fallback_font
	c.draw_circle(at, 12, INK)
	c.draw_circle(at, 10, Color("e8b86d"))
	var label := str(n)
	var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	c.draw_string(font, at + Vector2(-w / 2.0, 5.5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, INK)


static func paper_ball(c: CanvasItem, at: Vector2, k: int, spin: float, scale: float = 1.0) -> void:
	var r := 3.2 * k * scale
	c.draw_circle(at + Vector2(0.4, 0.7) * k, r, Color(0, 0, 0, 0.2))
	c.draw_circle(at, r, PAPER)
	c.draw_circle(at + Vector2(-0.7, -0.8) * k * scale, r * 0.45, Color.WHITE)
	var w := maxf(1.0, 0.5 * k)
	for i in 3:
		var a := spin + i * 2.1
		var p := at + Vector2(cos(a), sin(a)) * r * 0.55
		c.draw_line(
			p, p + Vector2(cos(a + 1.2), sin(a + 1.2)) * r * 0.7, PAPER_SHADE.darkened(0.25), w
		)
	c.draw_arc(at, r, 0.0, TAU, 14, PAPER_SHADE.darkened(0.15), w)


static func yarn(c: CanvasItem, at: Vector2, k: int, spin: float) -> void:
	var r := 3.4 * k
	c.draw_circle(at + Vector2(0.4, 0.7) * k, r, Color(0, 0, 0, 0.2))
	c.draw_circle(at, r, Color("c8483f"))
	var w := maxf(1.0, 0.55 * k)
	for i in 3:
		c.draw_arc(at, r * (0.35 + 0.22 * i), spin + i, spin + i + 2.4, 8, Color("ee8a7a"), w)
	c.draw_arc(at, r, 0.0, TAU, 14, Color("8a2f2a"), w)
	c.draw_arc(at + Vector2(r * 0.6, r * 0.5), r * 0.8, 0.2, 1.4, 6, Color("c8483f"), w)


static func confetti(c: CanvasItem, p: Vector2, col: Color, k: int, spin: float) -> void:
	var s := 1.6 * k
	(
		c
		. draw_colored_polygon(
			PackedVector2Array(
				[
					p + Vector2(cos(spin), sin(spin)) * s,
					p + Vector2(cos(spin + 1.6), sin(spin + 1.6)) * s * 0.6,
					p - Vector2(cos(spin), sin(spin)) * s,
					p - Vector2(cos(spin + 1.6), sin(spin + 1.6)) * s * 0.6,
				]
			),
			col
		)
	)
