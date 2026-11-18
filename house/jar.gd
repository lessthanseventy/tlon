extends RefCounted

# The done jar: one marble per thing done this week (the server's `done_week`), on a wall shelf.
const Props := preload("res://props.gd")
const CAP := 27
const ROWS := [5, 4, 5, 4, 5, 4]
const MARBLE := 2.4
const ROW_H := 2.1
const SHELF_S := Vector2(91.0, 109.0)
const SHELF_H := 17.0
const JAR_S := 100.0
const FALL := 0.55
const CLINK := 0.4
const COLORS := [
	Color("d9534f"),
	Color("4f8fd9"),
	Color("5fb37a"),
	Color("e8b86d"),
	Color("a77bd9"),
	Color("f2a6b3"),
	Color("5fd0c8"),
	Color("f0efe6"),
]

var total := 0
var shown := 0
var week := -1
var drops: Array = []
var clinks: Array = []

var _ready_for_drops := false


static func week_key(unix_local: float) -> int:
	var days := int(floor(unix_local / 86400.0))
	return days - posmod(days + 3, 7)


func colour(slot: int) -> Color:
	return COLORS[hash(week * 31 + slot * 7919) % COLORS.size()]


func slot_pos(slot: int) -> Vector2:
	var row := 0
	var left := slot
	while left >= ROWS[row]:
		left -= ROWS[row]
		row += 1
	var n: int = ROWS[row]
	var x := 6.0 + (left - (n - 1) / 2.0) * MARBLE
	return Vector2(x - 6.0, -(1.6 + MARBLE / 2.0 + row * ROW_H))


func set_count(n: int, wk: int, delay: float = 0.0) -> void:
	if not _ready_for_drops or wk != week or n < total:
		week = wk
		total = n
		shown = mini(n, CAP)
		drops = []
		_ready_for_drops = true
		return
	var add := n - total
	total = n
	if add > 3:
		shown = mini(n, CAP)
		drops = []
		return
	for i in add:
		if shown + drops.size() < CAP:
			drops.append({"t": -(delay + i * 0.4)})


func process(dt: float) -> void:
	for d in drops:
		d["t"] += dt
	while not drops.is_empty() and drops[0]["t"] >= FALL:
		clinks.append({"t": 0.0, "slot": shown})
		shown += 1
		drops.pop_front()
	for cl in clinks:
		cl["t"] += dt
	clinks = clinks.filter(func(cl): return cl["t"] < CLINK)


func hover_text() -> String:
	return "%d done this week" % total if total > 0 else "a fresh week"


func draw(c: CanvasItem, o: Vector2, k: int) -> PackedVector2Array:
	var a := Props.wall_pt(o, k, 1, SHELF_S.x, SHELF_H)
	var b := Props.wall_pt(o, k, 1, SHELF_S.y, SHELF_H)
	var dv := Vector2(-5, 2.5) * k
	var lip := Vector2(0, 1.8 * k)
	c.draw_colored_polygon(
		PackedVector2Array([a + dv + lip, b + dv + lip, b + dv + lip * 2.0, a + dv + lip * 2.0]),
		Color("6b4528")
	)
	c.draw_colored_polygon(PackedVector2Array([a, b, b + dv, a + dv]), Color("a8744a"))
	c.draw_colored_polygon(
		PackedVector2Array([a + dv, b + dv, b + dv + lip, a + dv + lip]), Color("8a5a3c")
	)
	var base := Props.wall_pt(o, k, 1, JAR_S, SHELF_H) + dv * 0.55
	var body := Rect2(base + Vector2(-7, -15) * k, Vector2(14, 15) * k)
	c.draw_rect(body, Color(0.78, 0.92, 1.0, 0.18))
	for i in mini(shown, CAP):
		var hop := 0.0
		for cl in clinks:
			if cl["slot"] == i:
				hop = 2.4 * sin(PI * cl["t"] / CLINK) * (1.0 - cl["t"] / CLINK)
		_marble(c, base + (slot_pos(i) - Vector2(0, hop)) * k, k, colour(i), 1.0)
	for d in drops:
		var u: float = d["t"] / FALL
		if u < 0.0:
			continue
		var land := slot_pos(shown + drops.find(d))
		var y := lerpf(-27.0, land.y, u * u)
		_marble(c, base + Vector2(land.x, y) * k, k, colour(shown + drops.find(d)), 1.0)
	for cl in clinks:
		var u: float = cl["t"] / CLINK
		var at: Vector2 = base + slot_pos(cl["slot"]) * k
		var fade := 1.0 - u
		for i in 4:
			var ang := -PI / 2.0 + (i - 1.5) * 0.7
			var r0 := (2.0 + u * 2.0) * k
			var r1 := (3.6 + u * 3.5) * k
			c.draw_line(
				at + Vector2(cos(ang), sin(ang)) * r0 + Vector2(0, -2 * k),
				at + Vector2(cos(ang), sin(ang)) * r1 + Vector2(0, -2 * k),
				Color(1, 1, 0.85, fade),
				maxf(1.0, 0.7 * k)
			)
	c.draw_rect(body, Color(0.85, 0.96, 1.0, 0.75), false, maxf(1.0, 0.6 * k))
	c.draw_rect(
		Rect2(body.position + Vector2(1.5, 1.5) * k, Vector2(1.4, 9) * k), Color(1, 1, 1, 0.35)
	)
	var neck := Rect2(body.position + Vector2(2, -3) * k, Vector2(10, 3) * k)
	c.draw_rect(neck, Color(0.78, 0.92, 1.0, 0.25))
	c.draw_rect(neck, Color(0.85, 0.96, 1.0, 0.75), false, maxf(1.0, 0.6 * k))
	c.draw_rect(Rect2(neck.position + Vector2(-0.5, -2) * k, Vector2(11, 2.4) * k), Color("c8483f"))
	return PackedVector2Array(
		[
			body.position + Vector2(0, -5 * k),
			body.position + Vector2(body.size.x, -5 * k),
			body.end,
			body.position + Vector2(0, body.size.y),
		]
	)


func _marble(c: CanvasItem, at: Vector2, k: int, col: Color, alpha: float) -> void:
	if alpha <= 0.0:
		return
	var r := MARBLE / 2.0 * k * 0.95
	c.draw_circle(at, r, col.darkened(0.25))
	c.draw_circle(at, r * 0.82, col)
	c.draw_circle(at + Vector2(-0.3, -0.35) * k, r * 0.32, Color(1, 1, 1, 0.8))
