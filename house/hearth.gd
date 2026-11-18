extends RefCounted

# The fireplace (lit by itself when it is cold, snowy or a winter evening; a click toggles it) and
# the piano (a click and the person plays a few bars).
const Props := preload("res://props.gd")

const COLD_C := 8.0
const WINTER := [11, 12, 1, 2]
const BARS := 22
const BOX := Rect2(13.0, 38.0, 9.0, 13.0)
const SCALE := [0, 2, 4, 7, 9, 12, 14]

var _hw: WeakRef
var h:
	get:
		return _hw.get_ref()
var manual := -1
var lit := false
var sparks: Array = []
var notes: Array = []
var play := {}
var hero_play := false

var _mark := 0.0


func setup(home) -> void:
	_hw = weakref(home)


func auto_lit() -> bool:
	var d := Time.get_datetime_dict_from_unix_time(int(h._now_local()))
	var hour: float = h._hour()
	var w: String = h.forced_weather if h.forced_weather != "" else h.weather
	if w == "snow":
		return true
	if h.temp_c != null and float(h.temp_c) < COLD_C:
		return true
	return int(d["month"]) in WINTER and hour >= 16.5 and hour < 23.5


func has_fireplace() -> bool:
	return not h.eggs.piece("fireplace").is_empty()


# a click: the fire goes out if it burns and burns if it is out, until the weather changes its mind
func toggle() -> void:
	manual = 0 if lit else 1
	lit = manual == 1
	h.eggs.find("fire")
	h.sound.request("rustle")


func process(dt: float) -> void:
	var want := auto_lit() if manual < 0 else manual == 1
	lit = want and has_fireplace()
	h.sound.loop("crackle", lit)
	for s in sparks:
		s["t"] += dt
	sparks = sparks.filter(func(s): return s["t"] < s["life"])
	for n in notes:
		n["t"] += dt
	notes = notes.filter(func(n): return n["t"] < 1.8)
	if lit and h.eggs.rng.randf() < dt * 3.0 and not h.pets.freeze:
		_spark()
	_play(dt)


func _spark() -> void:
	sparks.append(
		{
			"t": 0.0,
			"life": h.eggs.rng.randf_range(0.6, 1.2),
			"dx": h.eggs.rng.randf_range(-4.0, 4.0)
		}
	)


# the screen point of the firebox, or the origin with no fireplace
func mouth() -> Vector2:
	var p: Dictionary = h.eggs.piece("fireplace")
	if p.is_empty():
		return Vector2.ZERO
	var s: Dictionary = h.room._sprite(h.layout.sprite_id(p) % 1)
	var at: Vector2 = h._p(p["c"], p["r"])
	if not s.is_empty():
		at -= s["anchor"]
	return at + Vector2(17.0, 43.0) * h._k


# a crumpled note reaches the fire
func puff() -> void:
	h.eggs.find("toss")
	for i in 7:
		_spark()
	h.sound.request("rustle")


# over the sprite: an unlit fire is a dark firebox
func dress(c: CanvasItem, at: Vector2, k: int) -> void:
	if not lit:
		c.draw_rect(Rect2(at + BOX.position * k, BOX.size * k), Color("1c1820"))
		c.draw_rect(
			Rect2(at + (BOX.position + Vector2(1, 9)) * k, Vector2(6, 2) * k), Color("3a3430")
		)


func draw_over(c: CanvasItem) -> void:
	if lit:
		var m := mouth()
		var fl: float = 0.75 + 0.25 * sin(h._t * 9.0) * sin(h._t * 5.3)
		c.draw_circle(m, 26.0 * h._k * fl, Color(1.0, 0.55, 0.2, 0.07))
		c.draw_circle(m, 14.0 * h._k * fl, Color(1.0, 0.65, 0.25, 0.1))
	for s in sparks:
		var u: float = s["t"] / s["life"]
		var m := mouth()
		var at: Vector2 = m + Vector2(s["dx"] * h._k + sin(s["t"] * 6.0) * 2.0, -u * 20.0 * h._k)
		c.draw_rect(Rect2(at, Vector2(h._k, h._k)), Color(1.0, 0.75, 0.3, 1.0 - u))
	var pn: Dictionary = h.eggs.piece("piano")
	if not pn.is_empty():
		for n in notes:
			var u: float = n["t"] / 1.8
			var r: Rect2i = h.layout.rect(pn)
			var at: Vector2 = h._p(r.position.x + 0.7, r.position.y + r.size.y / 2.0, 34.0)
			at += Vector2(n["dx"] * h._k, -u * 26.0 * h._k)
			_note(c, at, Color(Props.INK, 1.0 - u))


func _note(c: CanvasItem, at: Vector2, col: Color) -> void:
	c.draw_circle(at, 2.2 * h._k * 0.7, col)
	c.draw_line(
		at + Vector2(1.5, 0) * h._k * 0.7,
		at + Vector2(1.5, -7) * h._k * 0.7,
		col,
		maxf(1.0, 0.8 * h._k)
	)
	c.draw_line(
		at + Vector2(1.5, -7) * h._k * 0.7,
		at + Vector2(4, -5) * h._k * 0.7,
		col,
		maxf(1.0, 0.8 * h._k)
	)


# a click on the piano: he sits and plays a few bars (a hero stands and plays badly)
func piano_click() -> void:
	var p: Dictionary = h.eggs.piece("piano")
	if p.is_empty() or not play.is_empty() or not h.eggs.calm():
		return
	var cell: Vector2i = h.eggs.front_cell(p)
	if cell.x < 0:
		return
	var r: Rect2i = h.layout.rect(p)
	var bench := Vector2(cell) + Vector2(0.5, 0.5)
	var to := Vector2(r.position.x + r.size.x / 2.0, r.position.y + r.size.y / 2.0)
	h.eggs.spot("piano_stand", {"cell": cell})
	h.person.acts["piano"] = {
		"stand": "piano_stand",
		"seat": bench,
		"z": 5.0,
		"key": float(h.layout.draw_key(p)) + 0.4,
		"face": h.pets._face(to - bench, 3),
		"anim": "type",
		"pri": 2.0
	}
	hero_play = h.look.hero()
	play = {"left": float(BARS), "next": 0.0, "n": 0}
	h.person.forced = "piano"
	h.eggs.find("piano_hero" if hero_play else "piano")


func _play(dt: float) -> void:
	if play.is_empty():
		return
	if h.person.act != "piano" or h.person.phase != "idle":
		play["wait"] = float(play.get("wait", 0.0)) + dt
		if float(play["wait"]) > 40.0:
			stop()
		return
	play["left"] -= dt
	play["next"] -= dt
	if play["next"] <= 0.0:
		play["next"] = 0.42
		var rng: RandomNumberGenerator = h.eggs.rng
		var semi: int = SCALE[rng.randi() % SCALE.size()]
		if hero_play:
			semi = rng.randi_range(-3, 14)
		h.sound.request("bad_piano" if hero_play else "piano", semi)
		notes.append({"t": 0.0, "dx": rng.randf_range(-6.0, 6.0)})
		play["n"] += 1
	if play["left"] <= 0.0:
		stop()


func stop() -> void:
	play = {}
	if h.person.forced == "piano":
		h.person.forced = ""
