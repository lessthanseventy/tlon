extends RefCounted

const Pets := preload("res://pets.gd")
const Look := preload("res://look.gd")

const ACTS := {
	"desk":
	{
		"stand": "desk_stand",
		"seat": Vector2(4.5, 1.5),
		"z": 11.0,
		"key": 5.0,
		"face": 5,
		"anim": "type",
		"pri": 1.6
	},
	"sofa":
	{
		"stand": "sofa_stand",
		"seat": Vector2(0.55, 4.55),
		"z": 7.0,
		"key": 6.03,
		"face": 7,
		"anim": "sit",
		"pri": 2.0
	},
	"tv":
	{
		"stand": "sofa_stand",
		"seat": Vector2(0.55, 4.55),
		"z": 7.0,
		"key": 6.03,
		"face": 5,
		"anim": "sit",
		"pri": 2.0
	},
	"coffee":
	{
		"stand": "sofa_stand",
		"seat": Vector2(0.55, 4.55),
		"z": 7.0,
		"key": 6.03,
		"face": 7,
		"anim": "eat",
		"held": "cup_white",
		"pri": 2.0
	},
	"sleep":
	{
		"stand": "sofa_stand",
		"seat": Vector2(0.55, 4.55),
		"z": 7.0,
		"key": 6.03,
		"face": 7,
		"anim": "sit",
		"still": true,
		"pri": 2.0
	},
	"board": {"stand": "board_stand", "face": 5, "anim": "idle", "pri": 2.0},
	"stretch": {"stand": "mid", "face": 7, "anim": "cheer", "pri": 2.0},
	"arrive": {"stand": "door_in", "face": 7, "anim": "pickup", "pri": 2.0},
}
const DOORWAY := Vector2(0.45, 7.5)
const BAG_AT := Vector2(2.25, 7.95)
const LINES := [
	"hm?",
	"still here.",
	"just thinking.",
	"all good.",
	"the cat has opinions.",
	"nice room, this.",
]

var acts := ACTS.duplicate(true)
var fx := {}
var pets
var look
var c
var rng := RandomNumberGenerator.new()
var act := ""
var next := ""
var phase := "idle"
var seated := false
var ring := false
var open_n := 0
var has_notes := false
var hour := 12.0
var calm := true
var forced := ""
var stretch_left := 0.0
var arrive_left := 0.0
var bag := ""
var bag_left := 0.0
var react_left := 0.0
var t := 0.0

var _tw := 0.0
var _from := Vector2.ZERO
var _from_z := 0.0
var _exc := ""
var _exc_left := 0.0
var _exc_next := 30.0
var _was_hero := false


func setup(p, l, seed_value: int) -> void:
	pets = p
	look = l
	c = pets.critter("person")
	rng.seed = seed_value if seed_value >= 0 else randi()
	_exc_next = rng.randf_range(15.0, 30.0)
	_was_hero = look.hero()


# a hero has no sitting: he stands on the floor cell he would walk to
func _sits(a: Dictionary) -> bool:
	return a.has("seat") and not look.hero()


func base() -> String:
	if ring:
		return "desk"
	if stretch_left > 0.0:
		return "stretch"
	if arrive_left > 0.0:
		return "arrive"
	if forced != "":
		return forced
	if _exc != "":
		return _exc
	if (hour >= 23.0 or hour < 5.5) and calm:
		return "sleep"
	if open_n > 0:
		return "desk"
	return "sofa"


func snap() -> void:
	var want := base()
	var a: Dictionary = acts[want]
	c.jump = {}
	c.path = []
	c.mode = "idle"
	c.anim = "idle"
	if _sits(a):
		c.pos = a["seat"]
		c.z = a["z"]
		c.key = a["key"]
		seated = true
	else:
		c.pos = pets._center(pets.spots[a["stand"]]["cell"])
		c.z = 0.0
		c.key = -1.0
		seated = false
	c.dir = a["face"]
	c.spot = a["stand"]
	act = want
	next = want
	phase = "idle"


func process(dt: float, freeze: bool) -> void:
	if look.hero() != _was_hero:
		_was_hero = look.hero()
		snap()
	t += dt
	stretch_left = maxf(0.0, stretch_left - dt)
	react_left = maxf(0.0, react_left - dt)
	if phase == "idle" and act == "arrive" and bag == "carry":
		bag = "down"
		bag_left = 150.0
	if bag == "down":
		bag_left -= dt
		if bag_left <= 0.0:
			bag = ""
	if arrive_left > 0.0 and phase == "idle" and act == "arrive":
		arrive_left = maxf(0.0, arrive_left - dt)
	if not freeze:
		_excursions(dt)
	var want := base()
	match phase:
		"idle":
			if want != act:
				_switch(want)
		"leaving":
			_tw += dt / 0.4
			var to: Vector2 = pets._center(pets.spots[acts[act]["stand"]]["cell"])
			var e := minf(_tw, 1.0)
			c.pos = _from.lerp(to, e)
			c.z = lerpf(_from_z, 0.0, e) + 3.0 * sin(PI * e)
			if _tw >= 1.0:
				seated = false
				c.z = 0.0
				c.key = -1.0
				_go()
		"walking":
			if want != next:
				next = want
				_go()
			elif c.mode != "walk" and c.jump.is_empty():
				_arrived()
		"entering":
			_tw += dt / 0.45
			var a: Dictionary = acts[next]
			var e := minf(_tw, 1.0)
			c.pos = _from.lerp(a["seat"], e)
			c.z = lerpf(0.0, a["z"], e) + 3.0 * sin(PI * e)
			c.dir = a["face"]
			c.key = a["key"] if e > 0.5 else -1.0
			if _tw >= 1.0:
				seated = true
				_settle(next)


func _switch(want: String) -> void:
	var a: Dictionary = acts[want]
	var cur: Dictionary = acts[act]
	next = want
	if seated and a.has("seat") and cur.get("seat") == a["seat"]:
		_settle(want)
		return
	if seated:
		phase = "leaving"
		_tw = 0.0
		_from = c.pos
		_from_z = c.z
		return
	_go()


func _go() -> void:
	c.z = 0.0
	c.key = -1.0
	pets.go(c, acts[next]["stand"], "sit", 9999.0)
	phase = "walking"


func _arrived() -> void:
	var a: Dictionary = acts[next]
	c.dir = a["face"]
	if _sits(a):
		phase = "entering"
		_tw = 0.0
		_from = c.pos
	else:
		_settle(next)


func _settle(name: String) -> void:
	act = name
	phase = "idle"
	c.dir = acts[name]["face"]
	c.mode = "idle"
	c.anim = "idle"
	if not seated:
		c.key = -1.0
	else:
		c.key = acts[name]["key"]
		c.pos = acts[name]["seat"]


func _excursions(dt: float) -> void:
	if _exc != "":
		_exc_left -= dt
		if _exc_left <= 0.0:
			_exc = ""
			_exc_next = rng.randf_range(25.0, 50.0)
		return
	if ring or stretch_left > 0.0 or arrive_left > 0.0 or phase != "idle":
		return
	_exc_next -= dt
	if _exc_next > 0.0:
		return
	_exc_next = rng.randf_range(25.0, 50.0)
	var picks: Array = []
	if has_notes and hour >= 7.0 and hour < 22.0:
		picks.append("board")
	if hour >= 6.0 and hour < 11.5:
		picks.append("coffee")
	if open_n == 0 and hour >= 10.0 and hour < 23.0 and rng.randf() < 0.6:
		picks.append("tv")
	if picks.is_empty():
		return
	_exc = picks[rng.randi() % picks.size()]
	_exc_left = rng.randf_range(40.0, 80.0) if _exc == "tv" else rng.randf_range(9.0, 15.0)


func watching() -> bool:
	return act == "tv" and phase == "idle" or (phase == "entering" and next == "tv")


func stretch(line: String = "time. stand up, stretch a bit?") -> void:
	stretch_left = 5.5
	pets.say(c, line)


func arrive(with_bag: bool) -> void:
	_exc = ""
	arrive_left = 4.5
	bag = "carry" if with_bag else ""
	seated = false
	c.jump = {}
	c.path = []
	c.pos = DOORWAY
	c.z = 0.0
	c.key = -1.0
	c.dir = 7
	c.mode = "idle"
	c.anim = "idle"
	c.spot = "door"
	act = "board"
	next = "arrive"
	phase = "idle"


func poke() -> void:
	react_left = 1.8
	pets.say(c, LINES[rng.randi() % LINES.size()])
	c.pat_t = 0.0


func pri() -> float:
	if phase == "idle" or phase == "entering":
		return acts[next if phase == "entering" else act].get("pri", 2.0)
	return 2.0


func anim() -> String:
	match phase:
		"walking":
			return "walk"
		"leaving", "entering":
			return "sit"
	if fx.has("anim") and phase == "idle":
		return fx["anim"]
	if react_left > 0.0 and not seated:
		return "wave"
	return acts[act]["anim"]


func draw(canvas: CanvasItem, o: Vector2, k: int) -> void:
	var f: Vector2 = pets.feet(c, o, k)
	var a := anim()
	var cur: Dictionary = acts[act]
	if look.layered or look.hero():
		var held: String = cur.get("held", "") if a == "eat" and not look.hero() else ""
		var tex: Texture2D = look.sheet(look.current(), k, held)
		var still: bool = a == "sit" and cur.get("still", false)
		look.draw_frame(canvas, tex, look.anim_for(a), c.dir, t, f, k, still)
	else:
		look.draw_flat(canvas, f, k, a in ["sit", "type", "eat"], t)
	var font := ThemeDB.fallback_font
	if bag == "carry":
		draw_bag(canvas, f + Vector2(9, -13) * k, k)
	if act == "sleep" and phase == "idle":
		for i in 3:
			var ph := fmod(t * 0.5 + i * 0.33, 1.0)
			var at := f + Vector2(8 + ph * 10, -46 * k * 0.8 - ph * 10 * k)
			canvas.draw_string(
				font, at, "z", HORIZONTAL_ALIGNMENT_LEFT, -1, 12 + i * 3, Color("f1e9dc", 1.0 - ph)
			)
	if ring and phase == "idle":
		var m := f + Vector2(0, -46 * k)
		canvas.draw_circle(m, 11, Color("2a2530"))
		canvas.draw_circle(m, 9, Color("e8b86d"))
		canvas.draw_string(
			font, m + Vector2(-3, 6), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("2a2530")
		)


static func draw_bag(canvas: CanvasItem, at: Vector2, k: int) -> void:
	var r := Rect2(at - Vector2(4, 0) * k, Vector2(8, 9) * k)
	canvas.draw_rect(Rect2(r.position + Vector2(1, 1) * k, r.size), Color(0, 0, 0, 0.2))
	canvas.draw_rect(r, Color("c9a06a"))
	canvas.draw_rect(Rect2(r.position, Vector2(r.size.x, 2 * k)), Color("a8804a"))
	canvas.draw_arc(at + Vector2(0, 0.5 * k), 2.6 * k, PI, TAU, 8, Color("7a5a38"), maxf(1.0, 0.7 * k))
