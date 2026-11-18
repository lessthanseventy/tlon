extends RefCounted

# The TV's screen hacks: small code-drawn visualisations, no audio or screen capture. Each draws on
# the screen quad `q` (u across, v down, both 0..1) from the hack clock `t`. To add one: write
# `_name(c, q, t)` and list `name` in NAMES.
const NAMES := [
	"spectrum",
	"stars",
	"plasma",
	"logo",
	"rain",
	"life",
	"pipes",
	"moire",
	"scope",
	"sunset",
	"fireworks",
	"toasters",
	"note",
]
const SWITCH_MIN := 120.0
const SWITCH_MAX := 240.0
const FLICKER := 0.45
const GREEN := Color("5fe08a")

var current := ""
var forced := false
var t := 0.0

var _rng := RandomNumberGenerator.new()
var _order: Array = []
var _at := 0
var _left := 0.0
var _flicker := 0.0
var _grid: Array = []
var _gen_t := 0.0
var _gens := 0


func setup(seed_value: int) -> void:
	_rng.seed = seed_value if seed_value >= 0 else randi()
	_order = NAMES.duplicate()
	_shuffle()
	if not forced:
		current = _order[0]
	_left = _rng.randf_range(SWITCH_MIN, SWITCH_MAX)


func force(name: String) -> void:
	if NAMES.has(name):
		current = name
		forced = true


func _shuffle() -> void:
	var last := current
	for i in range(_order.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp: Variant = _order[i]
		_order[i] = _order[j]
		_order[j] = tmp
	if _order[0] == last and last != "":
		var swap: Variant = _order[0]
		_order[0] = _order[_order.size() - 1]
		_order[_order.size() - 1] = swap
	_at = 0


func advance() -> void:
	var before := current
	while current == before:
		_at += 1
		if _at >= _order.size():
			_shuffle()
		current = _order[_at]
	_left = _rng.randf_range(SWITCH_MIN, SWITCH_MAX)
	_flicker = FLICKER


func update(dt: float, running: bool) -> void:
	if not running:
		return
	t += dt
	_flicker = maxf(0.0, _flicker - dt)
	if not forced:
		_left -= dt
		if _left <= 0.0:
			advance()
	if current == "life":
		_gen_t += dt
		if _grid.is_empty() or _gen_t >= 0.22:
			_gen_t = 0.0
			_life_step()


func draw(c: CanvasItem, q: PackedVector2Array) -> void:
	c.draw_colored_polygon(q, Color("05060c"))
	if _flicker > 0.0:
		_static(c, q)
		return
	call("_" + current, c, q, t)


static func pt(q: PackedVector2Array, u: float, v: float) -> Vector2:
	return q[0] + (q[1] - q[0]) * u + (q[3] - q[0]) * v


static func box(
	c: CanvasItem, q: PackedVector2Array, u0: float, v0: float, u1: float, v1: float, col: Color
) -> void:
	c.draw_colored_polygon(
		PackedVector2Array([pt(q, u0, v0), pt(q, u1, v0), pt(q, u1, v1), pt(q, u0, v1)]), col
	)


static func clip(a: Vector2, b: Vector2) -> Array:
	var t0 := 0.0
	var t1 := 1.0
	var d := b - a
	for edge in 4:
		var p := 0.0
		var qv := 0.0
		match edge:
			0:
				p = -d.x
				qv = a.x
			1:
				p = d.x
				qv = 1.0 - a.x
			2:
				p = -d.y
				qv = a.y
			_:
				p = d.y
				qv = 1.0 - a.y
		if p == 0.0:
			if qv < 0.0:
				return []
			continue
		var r := qv / p
		if p < 0.0:
			if r > t1:
				return []
			t0 = maxf(t0, r)
		else:
			if r < t0:
				return []
			t1 = minf(t1, r)
	return [a + d * t0, a + d * t1]


static func seg(
	c: CanvasItem,
	q: PackedVector2Array,
	a: Vector2,
	b: Vector2,
	col: Color,
	big: float = 1.0
) -> void:
	var ends := clip(a, b)
	if ends.is_empty():
		return
	c.draw_line(
		pt(q, ends[0].x, ends[0].y),
		pt(q, ends[1].x, ends[1].y),
		col,
		maxf(1.0, (q[1] - q[0]).length() / 60.0 * big)
	)


static func dot(c: CanvasItem, q: PackedVector2Array, u: float, v: float, r: float, col: Color) -> void:
	c.draw_circle(pt(q, u, v), maxf(0.8, r * (q[1] - q[0]).length()), col)


static func tri(x: float) -> float:
	return absf(fposmod(x, 2.0) - 1.0)


func _static(c: CanvasItem, q: PackedVector2Array) -> void:
	var frame := int(t * 40.0)
	for i in 36:
		var h := float(hash(i * 7919 + frame) % 100) / 100.0
		var u := float(i % 6) / 6.0
		var v := float(i / 6) / 6.0
		box(c, q, u, v, u + 1.0 / 6.0, v + 1.0 / 6.0, Color(h, h, h, 1.0) * 0.8)


func _spectrum(c: CanvasItem, q: PackedVector2Array, time: float) -> void:
	box(c, q, 0, 0, 1, 1, Color("0d1022"))
	var n := 14
	for i in n:
		var h := 0.5 + 0.42 * sin(time * (1.8 + i * 0.31) + i * 1.7) * sin(time * 1.1 + i * 0.6)
		var u0 := 0.04 + i * (0.92 / n)
		var col := Color.from_hsv(fmod(0.95 - i * 0.045 + time * 0.02, 1.0), 0.65, 1.0)
		box(c, q, u0, 0.88 - h * 0.78, u0 + 0.92 / n * 0.78, 0.88, col)
		box(c, q, u0, 0.9, u0 + 0.92 / n * 0.78, 0.9 + h * 0.08, Color(col, 0.3))


func _stars(c: CanvasItem, q: PackedVector2Array, time: float) -> void:
	for i in 46:
		var a := float(hash(i * 31) % 628) / 100.0
		var z := fposmod(time * 0.22 + float(i) / 46.0, 1.0)
		var d := z * z * 0.75
		var u := 0.5 + cos(a) * d * 0.9
		var v := 0.5 + sin(a) * d * 0.55
		var tail := d * 0.82
		seg(
			c,
			q,
			Vector2(0.5 + cos(a) * tail * 0.9, 0.5 + sin(a) * tail * 0.55),
			Vector2(u, v),
			Color(0.7, 0.85, 1.0, z),
			1.0 + z
		)
		dot(c, q, u, v, 0.004 + 0.012 * z, Color(1, 1, 1, 0.4 + z))


func _plasma(c: CanvasItem, q: PackedVector2Array, time: float) -> void:
	var nx := 16
	var ny := 9
	for y in ny:
		for x in nx:
			var fx := float(x) / nx
			var fy := float(y) / ny
			var s := sin(fx * 6.0 + time) + sin(fy * 7.0 + time * 1.3) + sin((fx + fy) * 5.0 - time * 0.7)
			var col := Color.from_hsv(fposmod(0.55 + s * 0.12, 1.0), 0.75, 0.55 + 0.3 * sin(s * 2.0))
			box(c, q, fx, fy, fx + 1.0 / nx + 0.002, fy + 1.0 / ny + 0.002, col)


func _bounce(time: float, w: float, h: float) -> Array:
	var px := time * 0.2
	var py := time * 0.15
	var u := tri(px) * (1.0 - w)
	var v := tri(py) * (1.0 - h)
	var hit := int(px) + int(py)
	var col := Color.from_hsv(fposmod(hit * 0.23, 1.0), 0.7, 1.0)
	return [u, v, col]


func _logo(c: CanvasItem, q: PackedVector2Array, time: float) -> void:
	var w := 0.3
	var h := 0.2
	var b := _bounce(time, w, h)
	var u: float = b[0]
	var v: float = b[1]
	var col: Color = b[2]
	box(c, q, u, v, u + w, v + h, col)
	box(c, q, u + 0.02, v + 0.03, u + w - 0.02, v + h - 0.03, Color("05060c"))
	seg(c, q, Vector2(u + 0.05, v + h - 0.06), Vector2(u + w * 0.5, v + 0.06), col, 1.5)
	seg(c, q, Vector2(u + w * 0.5, v + 0.06), Vector2(u + w - 0.05, v + h - 0.06), col, 1.5)


func _note(c: CanvasItem, q: PackedVector2Array, time: float) -> void:
	var w := 0.16
	var h := 0.3
	var b := _bounce(time * 1.2, w, h)
	var u: float = b[0]
	var v: float = b[1]
	var col: Color = b[2]
	dot(c, q, u + 0.04, v + h - 0.06, 0.035, col)
	seg(c, q, Vector2(u + 0.065, v + h - 0.07), Vector2(u + 0.065, v + 0.03), col, 2.0)
	seg(c, q, Vector2(u + 0.065, v + 0.03), Vector2(u + w - 0.02, v + 0.1), col, 2.5)


func _rain(c: CanvasItem, q: PackedVector2Array, time: float) -> void:
	var cols := 18
	var rows := 10
	for i in cols:
		var speed := 0.25 + float(hash(i * 13) % 50) / 100.0
		var head := fposmod(time * speed + float(hash(i * 5) % 100) / 100.0, 1.5) * rows
		var u := float(i) / cols
		for k in 7:
			var row := int(head) - k
			if row < 0 or row >= rows:
				continue
			var fade := 1.0 - float(k) / 7.0
			var col := Color(0.85, 1.0, 0.9) if k == 0 else Color(GREEN, fade)
			box(c, q, u + 0.004, float(row) / rows + 0.01, u + 0.04, float(row + 1) / rows - 0.01, col)


func _life_step() -> void:
	var nx := 20
	var ny := 12
	_gens += 1
	if _grid.is_empty() or _gens > 70:
		_gens = 0
		_grid = []
		for i in nx * ny:
			_grid.append(1 if _rng.randf() < 0.3 else 0)
		return
	var next: Array = []
	for y in ny:
		for x in nx:
			var n := 0
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					if dx != 0 or dy != 0:
						n += _grid[((y + dy + ny) % ny) * nx + (x + dx + nx) % nx]
			var alive: int = _grid[y * nx + x]
			next.append(1 if n == 3 or (alive == 1 and n == 2) else 0)
	_grid = next


func _life(c: CanvasItem, q: PackedVector2Array, _time: float) -> void:
	var nx := 20
	var ny := 12
	if _grid.is_empty():
		_life_step()
	for y in ny:
		for x in nx:
			if _grid[y * nx + x] == 1:
				var u := float(x) / nx
				var v := float(y) / ny
				box(c, q, u + 0.005, v + 0.01, u + 1.0 / nx - 0.005, v + 1.0 / ny - 0.01, GREEN)


func _pipes(c: CanvasItem, q: PackedVector2Array, time: float) -> void:
	var cycle := int(time / 7.0)
	var prog := fposmod(time / 7.0, 1.0) * 16.0
	var r := RandomNumberGenerator.new()
	r.seed = cycle * 977 + 3
	for p in 3:
		var at := Vector2(r.randi_range(1, 14), r.randi_range(1, 7)) / Vector2(16.0, 9.0)
		var dir := Vector2(1, 0) if r.randf() < 0.5 else Vector2(0, 1)
		var col := Color.from_hsv(r.randf(), 0.7, 1.0)
		for s in 16:
			if float(s) > prog:
				break
			var step := minf(1.0, prog - s)
			var nxt := at + dir * Vector2(0.09, 0.15) * step
			seg(c, q, at, nxt, col, 4.0)
			dot(c, q, nxt.x, nxt.y, 0.014, col.lightened(0.3))
			at = nxt
			if step >= 1.0 and r.randf() < 0.4:
				dir = Vector2(dir.y, dir.x) * (1.0 if r.randf() < 0.5 else -1.0)
				dir = Vector2(absf(dir.x), absf(dir.y)) * Vector2(1, 1)
			at = Vector2(clampf(at.x, 0.03, 0.97), clampf(at.y, 0.05, 0.95))


func _moire(c: CanvasItem, q: PackedVector2Array, time: float) -> void:
	for s2 in 2:
		var centre := Vector2(0.5 + 0.18 * sin(time * 0.7 + s2 * 3.0), 0.5 + 0.12 * cos(time * 0.9 + s2))
		var col := Color.from_hsv(fposmod(0.1 + s2 * 0.5 + time * 0.03, 1.0), 0.6, 1.0, 0.8)
		for i in 22:
			var a := time * (0.25 if s2 == 0 else -0.19) + float(i) * TAU / 22.0
			seg(c, q, centre, centre + Vector2(cos(a) * 0.9, sin(a) * 0.55), col)


func _scope(c: CanvasItem, q: PackedVector2Array, time: float) -> void:
	for i in 5:
		seg(c, q, Vector2(0, 0.1 + i * 0.2), Vector2(1, 0.1 + i * 0.2), Color(0.2, 0.5, 0.3, 0.35))
	var pts := PackedVector2Array()
	var a := 3.0 + sin(time * 0.2) * 1.0
	var b := 2.0 + cos(time * 0.17)
	for i in 90:
		var s := float(i) / 90.0 * TAU
		pts.append(pt(q, 0.5 + 0.42 * sin(a * s + time * 0.8), 0.5 + 0.4 * sin(b * s)))
	c.draw_polyline(pts, GREEN, maxf(1.5, (q[1] - q[0]).length() / 70.0), true)


func _sunset(c: CanvasItem, q: PackedVector2Array, time: float) -> void:
	box(c, q, 0, 0, 1, 0.55, Color("2a1050"))
	var sun := PackedVector2Array()
	for i in 17:
		var a := PI + PI * float(i) / 16.0
		sun.append(pt(q, 0.5 + cos(a) * 0.22, 0.55 + sin(a) * 0.4))
	c.draw_colored_polygon(sun, Color("ff6a88"))
	for i in 4:
		box(c, q, 0.28, 0.4 + i * 0.035, 0.72, 0.42 + i * 0.035, Color("2a1050"))
	box(c, q, 0, 0.55, 1, 1, Color("12062a"))
	for i in 9:
		var d := fposmod(float(i) / 9.0 + time * 0.12, 1.0)
		var v := 0.55 + d * d * 0.45
		seg(c, q, Vector2(0, v), Vector2(1, v), Color("ff3df0"))
	for i in 13:
		var x := float(i - 6) / 6.0
		seg(c, q, Vector2(0.5 + x * 0.04, 0.55), Vector2(0.5 + x * 0.9, 1.0), Color("ff3df0"))


func _fireworks(c: CanvasItem, q: PackedVector2Array, time: float) -> void:
	for b in 3:
		var local := time * 0.55 + b * 0.37
		var n := int(local)
		var age := fposmod(local, 1.0)
		var h := hash(n * 131 + b * 17)
		var centre := Vector2(0.2 + float(h % 60) / 100.0, 0.25 + float(h % 31) / 100.0)
		var col := Color.from_hsv(float(h % 97) / 97.0, 0.6, 1.0)
		if age < 0.2:
			var rise := age / 0.2
			dot(c, q, centre.x, 1.0 - (1.0 - centre.y) * rise, 0.014, Color(1, 0.9, 0.6))
			continue
		var e := (age - 0.2) / 0.8
		for i in 14:
			var a := float(i) / 14.0 * TAU
			var r := 0.2 * sqrt(e)
			var at := centre + Vector2(cos(a) * r, sin(a) * r * 0.65 + e * e * 0.12)
			dot(c, q, at.x, at.y, 0.016 * (1.0 - e * 0.5), Color(col, 1.0 - e * 0.6))


func _toasters(c: CanvasItem, q: PackedVector2Array, time: float) -> void:
	box(c, q, 0, 0, 1, 1, Color("0a1230"))
	for i in 4:
		var f := fposmod(time * 0.12 + float(i) / 4.0, 1.0)
		var u := 1.1 - f * 1.3
		var v := -0.2 + f * 1.3 + (i % 2) * 0.1 - 0.1
		var flap := sin(time * 8.0 + i) * 0.04
		var body := Color("c8c8d4")
		box(c, q, u, v, u + 0.17, v + 0.15, body)
		box(c, q, u + 0.03, v + 0.03, u + 0.14, v + 0.06, Color("3a3a48"))
		var wing := PackedVector2Array(
			[pt(q, u + 0.04, v), pt(q, u + 0.14, v), pt(q, u + 0.22, v - 0.12 + flap)]
		)
		c.draw_colored_polygon(wing, Color("f2f2ff"))
