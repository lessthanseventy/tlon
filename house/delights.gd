extends RefCounted

# Small things the room does about the weather, the hour, the TV, a new look and a full jar.
const Props := preload("res://props.gd")
const Jar := preload("res://jar.gd")

const TV_LINES := {
	"toasters": ["Argos", "the toasters are flying!"],
	"fireworks": ["Argos", "pretty! and loud?"],
	"life": ["Nina", "too many dots. no plot."],
	"rain": ["Nina", "I prefer the real kind, indoors."],
	"pipes": ["Argos", "where do the pipes go?"],
	"stars": ["Nina", "I know those. we have met."],
}
const NEW_LOOK := {"Argos": "who is that?! oh. it's you!", "Nina": "hm. acceptable."}
const LAMP := Vector2(0.5, 6.5)

var _hw: WeakRef
var h:
	get:
		return _hw.get_ref()
var moth := 0.0
var jar_spark := 0.0
var umbrella := false

var _next_moth := 400.0
var _next_wx := 150.0
var _hack := ""
var _look_sig := ""
var _closet_was := false
var _t := 0.0


func setup(home) -> void:
	_hw = weakref(home)
	var r: RandomNumberGenerator = h.eggs.rng
	_next_moth = r.randf_range(200.0, 600.0)
	_next_wx = r.randf_range(90.0, 240.0)


func wet() -> bool:
	return h._env["weather"] in ["rain", "storm"]


func process(dt: float) -> void:
	_t += dt
	moth = maxf(0.0, moth - dt)
	jar_spark = maxf(0.0, jar_spark - dt)
	umbrella = wet()
	if umbrella:
		h.eggs.find("umbrella")
	_moth(dt)
	_weather_pets(dt)
	_tv()
	_closet()
	_jar(dt)


func night() -> bool:
	var hour: float = h._hour()
	return hour >= 20.0 or hour < 2.0


func _moth(dt: float) -> void:
	if h.pets.freeze:
		return
	_next_moth -= dt
	if _next_moth <= 0.0:
		_next_moth = h.eggs.rng.randf_range(400.0, 900.0)
		if night() and not wet():
			start_moth()


func start_moth() -> void:
	moth = 30.0
	h.eggs.find("moth")


func rain_watch() -> void:
	var n = h.pets.critter("nina")
	if h.eggs.loose(n):
		h.pets.go(n, "sill", "sit", 40.0)
		n.wait = 9999.0
		h.eggs.find("rain_watch")


func storm_hide() -> void:
	var a = h.pets.critter("argos")
	if h.eggs.loose(a):
		h.pets.go(a, "nook", "sit", 25.0)
		a.wait = 9999.0
		h.eggs.find("storm_hide")
		h.pets.say(a, "it's just the sky. it's just the sky.")


func _weather_pets(dt: float) -> void:
	if h.pets.freeze:
		return
	_next_wx -= dt
	if _next_wx > 0.0:
		return
	_next_wx = h.eggs.rng.randf_range(150.0, 400.0)
	if not h.eggs.scene.is_empty() or not h.eggs.calm():
		return
	match h._env["weather"]:
		"rain":
			rain_watch()
		"storm":
			storm_hide()


func _tv() -> void:
	var cur: String = h.tv.hacks.current
	if cur == _hack:
		return
	_hack = cur
	if not h.tv.on or h.pets.freeze or not TV_LINES.has(cur):
		return
	var row: Array = TV_LINES[cur]
	var c = h.pets.critter(str(row[0]).to_lower())
	if h.eggs.loose(c) and c.say_left <= 0.0:
		h.pets.say(c, row[1])
		h.eggs.find("tv_react")


func _closet() -> void:
	var sig := JSON.stringify(h.look.current())
	if h.closet_open and not _closet_was:
		_look_sig = sig
	if _closet_was and not h.closet_open and sig != _look_sig:
		new_look()
	_closet_was = h.closet_open


func new_look() -> void:
	h.eggs.find("new_look")
	var a = h.pets.critter("argos")
	if a.mode == "sleep":
		a.mode = "idle"
		a.anim = "idle"
	a.hops = 3
	h.pets.say(a, NEW_LOOK["Argos"])
	if h.pets.cry(a) == "bark":
		h.sound.request("bark")
	var n = h.pets.critter("nina")
	n.wait = minf(n.wait, 3.0)


func _jar(dt: float) -> void:
	var full: bool = h.jar.shown >= Jar.CAP
	if full and h.jar.clinks.any(func(cl): return cl["t"] < dt + 0.001):
		jar_spark = 6.0
		var a = h.pets.critter("argos")
		a.hops = 4
		h.pets.say(a, "the jar is full!")
		h.eggs.find("jar_full")


func items() -> Array:
	if not umbrella:
		return []
	return [{"key": 8.6, "pri": 1.7, "fn": _draw_umbrella}]


func _draw_umbrella() -> void:
	var k: int = h._k
	var at: Vector2 = h._p(1.35, 7.95)
	var c: CanvasItem = h.room
	c.draw_colored_polygon(
		PackedVector2Array(
			[
				at + Vector2(-9, 0) * k,
				at + Vector2(0, -2.5) * k,
				at + Vector2(9, 0) * k,
				at + Vector2(0, 2.5) * k
			]
		),
		Color(0.4, 0.55, 0.75, 0.4)
	)
	c.draw_line(
		at + Vector2(0, 0) * k, at + Vector2(-3, -20) * k, Color("3a2a22"), maxf(1.0, 1.1 * k)
	)
	c.draw_colored_polygon(
		PackedVector2Array(
			[at + Vector2(-12, -17) * k, at + Vector2(-3, -24) * k, at + Vector2(6, -17) * k]
		),
		Color("c8483f")
	)
	c.draw_circle(at + Vector2(1, -2) * k, 0.7 * k, Color(0.6, 0.78, 1.0, 0.8 * fposmod(_t, 1.0)))


func draw_over(c: CanvasItem) -> void:
	var k: int = h._k
	if moth > 0.0:
		var lamp: Vector2 = h._p(LAMP.x, LAMP.y, 34.0)
		var a := _t * 3.1
		var p := lamp + Vector2(cos(a) * 11.0 * k, sin(a * 1.7) * 5.0 * k - 2.0 * k)
		var fl := 1.0 if int(_t * 18.0) % 2 == 0 else 0.5
		c.draw_rect(Rect2(p + Vector2(-1.4, -0.6) * k, Vector2(1.4, 1.2) * k * fl), Color("e8e0c8"))
		c.draw_rect(Rect2(p + Vector2(0, -0.6) * k, Vector2(1.4, 1.2) * k * fl), Color("e8e0c8"))
	if jar_spark > 0.0:
		var jar_at := Props.wall_pt(h._o, k, 1, Jar.JAR_S, Jar.SHELF_H + 10.0)
		for i in 7:
			var ph := fposmod(_t * 1.2 + i * 0.14, 1.0)
			var a := i * 2.4 + _t
			var p := jar_at + Vector2(cos(a) * 12.0, sin(a) * 6.0 - ph * 14.0) * k
			var al := minf(1.0, jar_spark) * (1.0 - ph)
			c.draw_rect(Rect2(p, Vector2(k, k) * 1.6), Color("fff0a0", al))
