extends RefCounted

# What happens outside the window: a bird on the sill, a balloon, a cat on the fence at night, a shooting
# star that can be wished on, a plane, snow on the sill in winter, fireworks at New Year.
const View := preload("res://view.gd")
const Props := preload("res://props.gd")

const EVERY := {
	"bird": Vector2(150.0, 420.0),
	"balloon": Vector2(600.0, 1500.0),
	"nightcat": Vector2(500.0, 1200.0),
	"star": Vector2(400.0, 1000.0),
	"plane": Vector2(700.0, 1800.0),
}
const LONG := {"bird": 22.0, "balloon": 70.0, "nightcat": 50.0, "star": 3.2, "plane": 16.0}
const WISHES := [
	"wish heard. no promises.",
	"it will probably come true.",
	"a small one will fit.",
	"the sky took it.",
	"that is a kind thing to want.",
	"noted, with a chime.",
	"somewhere a cat approves.",
	"it saw you.",
]
const FIRE_COLORS := [
	Color("ff6a5a"), Color("ffd86a"), Color("7ad0ff"), Color("b88aff"), Color("8affb0")
]

var _hw: WeakRef
var h:
	get:
		return _hw.get_ref()
var act := {}
var wished := ""
var bursts: Array = []

var _next := {}
var _burst_next := 0.0


func setup(home) -> void:
	_hw = weakref(home)
	for k in EVERY:
		var e: Vector2 = EVERY[k]
		_next[k] = h.eggs.rng.randf_range(e.x * 0.15, e.y * 0.4)


func start(name: String) -> void:
	if not act.has(name):
		var r: RandomNumberGenerator = h.eggs.rng
		act[name] = {"t": 0.0, "v": r.randf(), "w": r.randf()}
		h.eggs.find(name)


func eligible(name: String) -> bool:
	var day: float = h._env["day"]
	var w: String = h._env["weather"]
	var fair := w in ["clear", "partly", "cloudy"]
	match name:
		"bird":
			return day > 0.5 and fair
		"balloon", "plane":
			return day > 0.5 and w in ["clear", "partly"]
		"nightcat", "star":
			return day < 0.2 and w in ["clear", "partly"]
	return false


func process(dt: float) -> void:
	for k in act.keys():
		act[k]["t"] += dt
		if act[k]["t"] >= LONG[k]:
			act.erase(k)
	if not h.pets.freeze:
		for k in _next:
			_next[k] -= dt
			if _next[k] <= 0.0:
				var e: Vector2 = EVERY[k]
				_next[k] = h.eggs.rng.randf_range(e.x, e.y)
				if eligible(k) and not act.has(k):
					start(k)
	if act.has("nightcat"):
		var n = h.pets.critter("nina")
		if h.eggs.loose(n) and n.spot != "sill" and not act["nightcat"].has("looked"):
			act["nightcat"]["looked"] = true
			h.pets.go(n, "sill", "sit", 40.0)
			n.wait = 9999.0
			h.eggs.find("nightcat")
	if _fireworks():
		_burst_next -= dt
		if _burst_next <= 0.0:
			_burst_next = h.eggs.rng.randf_range(0.8, 2.0)
			bursts.append(
				{
					"t": 0.0,
					"u": h.eggs.rng.randf_range(0.2, 0.8),
					"v": h.eggs.rng.randf_range(0.45, 0.85),
					"c": FIRE_COLORS[h.eggs.rng.randi() % FIRE_COLORS.size()]
				}
			)
			h.eggs.find("fireworks")
	for b in bursts:
		b["t"] += dt
	bursts = bursts.filter(func(b): return b["t"] < 1.6)


func _fireworks() -> bool:
	if h.eggs.firework_forced:
		return true
	var d := Time.get_datetime_dict_from_unix_time(int(h._now_local()))
	var hour: float = h._hour()
	return (
		(int(d["month"]) == 12 and int(d["day"]) == 31 and hour >= 23.0)
		or (int(d["month"]) == 1 and int(d["day"]) == 1 and hour < 1.0)
	)


func winter() -> bool:
	return int(Time.get_datetime_dict_from_unix_time(int(h._now_local()))["month"]) in [12, 1, 2]


func star_at(q: PackedVector2Array) -> Vector2:
	var f: float = act["star"]["t"] / LONG["star"]
	return Props.qlerp(q, lerpf(0.88, 0.4, f), lerpf(0.92, 0.55, f))


# drawn in the glass: balloon, plane, the fence cat, the star, fireworks
func draw(q: PackedVector2Array, c: CanvasItem, k: int, env: Dictionary) -> void:
	if h.secrets.moon > 0.0:
		var m := Props.qlerp(q, 0.3, 0.74)
		var a := minf(1.0, h.secrets.moon / 1.5)
		c.draw_circle(m, 4.4 * k, Color("f0b060", 0.5 * a))
		c.draw_circle(m + Vector2(1.0, -0.6) * k, 3.4 * k, Color("f8d890", a))
	if act.has("balloon"):
		var a: Dictionary = act["balloon"]
		var f: float = a["t"] / LONG["balloon"]
		var p := Props.qlerp(q, lerpf(-0.05, 1.05, f), 0.55 + 0.2 * a["v"] + 0.02 * sin(a["t"]))
		var col := Color("d9534f") if a["w"] < 0.5 else Color("4f8fd9")
		c.draw_line(p + Vector2(-2, 4) * k, p + Vector2(-1, 8) * k, Props.INK, 1.0)
		c.draw_line(p + Vector2(2, 4) * k, p + Vector2(1, 8) * k, Props.INK, 1.0)
		c.draw_circle(p, 4.2 * k, col)
		c.draw_circle(p + Vector2(-1.4, -1) * k, 1.4 * k, col.lightened(0.3))
		c.draw_rect(Rect2(p + Vector2(-1, 8) * k, Vector2(2, 1.6) * k), Color("8a5a3c"))
	if act.has("plane"):
		var a: Dictionary = act["plane"]
		var f: float = a["t"] / LONG["plane"]
		var p := Props.qlerp(q, lerpf(1.05, -0.05, f), 0.82 + 0.1 * a["v"])
		for i in 10:
			c.draw_circle(
				p + Vector2(4 + i * 2.6, 0.6 * i) * k,
				0.7 * k,
				Color(1, 1, 1, 0.5 * (1.0 - i / 10.0))
			)
		c.draw_rect(Rect2(p + Vector2(-3, -0.6) * k, Vector2(6, 1.4) * k), Color("e8ecef"))
		c.draw_rect(Rect2(p + Vector2(-1, -2.4) * k, Vector2(2, 4.6) * k), Color("c8ccd2"))
		c.draw_rect(Rect2(p + Vector2(2.4, -1.6) * k, Vector2(1, 1.6) * k), Color("c8ccd2"))
	if act.has("nightcat"):
		var a: Dictionary = act["nightcat"]
		var fade := clampf(minf(a["t"], LONG["nightcat"] - a["t"]) / 2.0, 0.0, 1.0)
		var p := Props.qlerp(q, 0.62, 0.17)
		var ink := Color(0.04, 0.04, 0.07, fade)
		c.draw_rect(
			Rect2(p + Vector2(-12, 1.5) * k, Vector2(26, 1.2) * k), Color(0.1, 0.09, 0.12, fade)
		)
		c.draw_rect(Rect2(p + Vector2(-3, -5) * k, Vector2(6, 6.5) * k), ink)
		c.draw_circle(p + Vector2(0, -6.5) * k, 3.0 * k, ink)
		c.draw_colored_polygon(
			PackedVector2Array(
				[p + Vector2(-3, -8) * k, p + Vector2(-2, -11) * k, p + Vector2(-0.6, -8.5) * k]
			),
			ink
		)
		c.draw_colored_polygon(
			PackedVector2Array(
				[p + Vector2(3, -8) * k, p + Vector2(2, -11) * k, p + Vector2(0.6, -8.5) * k]
			),
			ink
		)
		c.draw_arc(p + Vector2(4, 0) * k, 4.0 * k, -1.2, 1.4, 8, ink, 1.6 * k)
		var gl := Color("f2d34a", fade * (0.7 + 0.3 * sin(h._t * 2.0)))
		c.draw_rect(Rect2(p + Vector2(-1.6, -7) * k, Vector2(k, k)), gl)
		c.draw_rect(Rect2(p + Vector2(0.8, -7) * k, Vector2(k, k)), gl)
	if act.has("star"):
		var p := star_at(q)
		var f: float = act["star"]["t"] / LONG["star"]
		for i in 8:
			c.draw_circle(
				p + Vector2(5 + i * 3.2, -2.2 * i) * k * 0.6,
				(1.4 - i * 0.14) * k * 0.7,
				Color(1, 0.97, 0.8, (1.0 - i / 8.0) * (1.0 - f))
			)
		c.draw_circle(p, 1.6 * k, Color(1, 1, 0.9, 1.0 - f * 0.5))
	for b in bursts:
		var u: float = b["t"] / 1.6
		var p := Props.qlerp(q, b["u"], b["v"])
		for i in 14:
			var ang := TAU * i / 14.0
			var at := p + Vector2(cos(ang), sin(ang) + u * 0.6) * (3.0 + u * 11.0) * k
			c.draw_rect(Rect2(at, Vector2(k, k) * 1.2), Color(b["c"], (1.0 - u) * 0.95))


# over the sill: snow in winter, the bird; and the star's hit area
func hits(c: CanvasItem, _frame: PackedVector2Array) -> void:
	var o: Vector2 = h._o
	var k: int = h._k
	var q := View.quad(o, k)
	if winter():
		var d := Vector2(3.6, 1.8) * k
		var a := Props.wall_pt(o, k, -1, View.S0 - 1.0, View.H0 - 1.0)
		var b := Props.wall_pt(o, k, -1, View.S1 + 1.0, View.H0 - 1.0)
		var top := PackedVector2Array([a + d * 0.1, b + d * 0.1, b + d * 0.9, a + d * 0.9])
		c.draw_colored_polygon(top, Color("f4f8fc"))
		for i in 6:
			var u := (i + 0.5) / 6.0
			c.draw_circle(
				Props.qlerp(top, u, 0.1) + Vector2(0, -1) * k, (1.6 + (i % 2)) * k, Color("f4f8fc")
			)
		h.eggs.find("sillsnow")
		if h._env["weather"] == "snow":
			var s := Props.qlerp(top, 0.8, 0.5) + Vector2(0, -2.0) * k
			c.draw_circle(s, 3.0 * k, Color("fbfdff"))
			c.draw_circle(s + Vector2(0, -4.4) * k, 2.2 * k, Color("fbfdff"))
			c.draw_rect(Rect2(s + Vector2(-0.9, -5.2) * k, Vector2(k, k)), Props.INK)
			c.draw_rect(Rect2(s + Vector2(0.9, -5.2) * k, Vector2(k, k)), Props.INK)
			c.draw_rect(Rect2(s + Vector2(0, -4.3) * k, Vector2(2.4, 0.9) * k), Color("e8842c"))
			h.eggs.find("snowman")
	if act.has("bird"):
		var a: Dictionary = act["bird"]
		var t: float = a["t"]
		var u0: float = 0.25 + 0.5 * a["v"]
		var left: float = LONG["bird"] - t
		var p := Props.qlerp(q, u0 + 0.02 * sin(t * 0.7), 0.0) + Vector2(0, -3.0 * k)
		var hop := maxf(0.0, sin(t * 5.0)) * 2.0 * k if fmod(t, 4.0) < 1.0 else 0.0
		p.y -= hop
		if left < 2.0:
			var f := 1.0 - left / 2.0
			p += Vector2(f * 60.0 * k, -f * 40.0 * k)
			var fl := sin(t * 30.0)
			c.draw_line(p, p + Vector2(-2, -3 + 3 * fl) * k, Color("5a4030"), 1.4 * k)
			c.draw_line(p, p + Vector2(2, -3 - 3 * fl) * k, Color("5a4030"), 1.4 * k)
		c.draw_circle(p, 2.3 * k, Color("8a5a3c"))
		c.draw_circle(p + Vector2(-1.8, -0.4) * k, 1.4 * k, Color("e0684a"))
		c.draw_circle(p + Vector2(2.2, -1.6) * k, 1.4 * k, Color("8a5a3c"))
		c.draw_rect(Rect2(p + Vector2(3.4, -1.8) * k, Vector2(1.4, 0.8) * k), Color("e8b86d"))
		c.draw_rect(Rect2(p + Vector2(2.6, -2.2) * k, Vector2(k * 0.7, k * 0.7)), Props.INK)
		c.draw_line(p + Vector2(-3, 0.6) * k, p + Vector2(-6, 2.4) * k, Color("5a4030"), 1.2 * k)
		h.eggs.find("bird")
	if act.has("star"):
		var p := star_at(q)
		var r := 9.0 * k
		h._register(
			"star",
			PackedVector2Array(
				[p + Vector2(-r, -r), p + Vector2(r, -r), p + Vector2(r, r), p + Vector2(-r, r)]
			),
			p
		)


# a click on the star: a wish
func wish() -> void:
	h.spells.play("wish", star_at(View.quad(h._o, h._k)))
	act.erase("star")
	wished = WISHES[h.eggs.rng.randi() % WISHES.size()]
	h.show_reply(wished)
	h.sound.request("wish")
	h.eggs.find("star")
