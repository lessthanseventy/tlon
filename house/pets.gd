extends RefCounted

const Voices := preload("res://voices.gd")
const Settings := preload("res://settings.gd")
const COLS := 10
const ROWS := 10
const CHAIR := Vector2i(4, 1)
const DIRS := {"se": 7, "nw": 3, "sw": 1, "ne": 5}
const FPS := {"idle": 6.0, "walk": 10.0, "run": 14.0, "sleep": 3.0, "attack": 12.0, "eat": 4.0}
const NECK := {
	0: Vector2(0, -12),
	1: Vector2(-5, -11),
	2: Vector2(-9, -10),
	3: Vector2(-5, -12),
	4: Vector2(0, -13),
	5: Vector2(5, -12),
	6: Vector2(9, -10),
	7: Vector2(5, -10),
}
const SPOTS := {
	"rug": {"cell": Vector2i(2, 4)},
	"rug2": {"cell": Vector2i(3, 5)},
	"lamp": {"cell": Vector2i(1, 6)},
	"door": {"cell": Vector2i(1, 7)},
	"mid": {"cell": Vector2i(4, 4)},
	"corner": {"cell": Vector2i(7, 3)},
	"nook": {"cell": Vector2i(6, 2)},
	"bed": {"cell": Vector2i(6, 6), "face": 5},
	"bowl": {"cell": Vector2i(6, 7), "face": 7, "eat": true},
	"board": {"cell": Vector2i(3, 2), "face": 5},
	"lounge": {"cell": Vector2i(5, 4), "face": 7},
	"sofa":
	{"cell": Vector2i(1, 4), "perch": Vector2(0.55, 5.45), "z": 10.0, "key": 6.05, "face": 7},
	"desk":
	{"cell": Vector2i(3, 1), "perch": Vector2(4.95, 0.74), "z": 17.0, "key": 5.6, "face": 1},
	"sill": {"cell": Vector2i(1, 5), "perch": Vector2(0.35, 5.2), "z": 23.5, "key": 6.2, "face": 3},
	"tv": {"cell": Vector2i(1, 3), "face": 3},
	"desk_stand": {"cell": Vector2i(4, 2), "face": 5},
	"door_in": {"cell": Vector2i(2, 7), "face": 7},
	"knocked": {"cell": Vector2i(6, 2), "face": 5},
	"pad": {"cell": Vector2i(3, 1), "perch": Vector2(5.3, 0.85), "z": 17.0, "key": 5.6, "face": 1},
	"sofa_stand": {"cell": Vector2i(1, 4), "face": 7},
	"board_stand": {"cell": Vector2i(2, 1), "face": 5},
}
const BIN_TOP := Vector2(6.5, 0.5)
const BIN_Z := 11.0
const NONE := "none"
const ROLE_KINDS := {"nina": "cat_black", "argos": "dog_golden"}
# The animals either pet may be, in the order the settings offer them. Every one has all of
# ANIMS in the pack, so each animation plays under its own name; `species` keys what a pet says
# and sounds like (voices.gd `SPECIES`, `cry`), `shadow` is the pack's own for the animal.
const ANIMS := ["idle", "walk", "run", "sleep", "attack", "eat"]
const KINDS := {
	"cat_black": {"label": "black cat", "species": "cat", "head": 18.0, "shadow": "shadow_small"},
	"cat_grey": {"label": "grey cat", "species": "cat", "head": 18.0, "shadow": "shadow_small"},
	"cat_orange": {"label": "orange cat", "species": "cat", "head": 18.0, "shadow": "shadow_small"},
	"dog_golden":
	{"label": "golden dog", "species": "dog", "head": 20.0, "shadow": "shadow_medium"},
	"dog_black":
	{"label": "black & white dog", "species": "dog", "head": 20.0, "shadow": "shadow_medium"},
	"dog_brown": {"label": "brown dog", "species": "dog", "head": 20.0, "shadow": "shadow_medium"},
	"rabbit_brown":
	{"label": "brown rabbit", "species": "rabbit", "head": 18.0, "shadow": "shadow_small"},
	"rabbit_white":
	{"label": "white rabbit", "species": "rabbit", "head": 18.0, "shadow": "shadow_small"},
	"fox_red": {"label": "red fox", "species": "fox", "head": 17.0, "shadow": "shadow_small"},
	"fox_arctic": {"label": "arctic fox", "species": "fox", "head": 17.0, "shadow": "shadow_small"},
	"chicken_white":
	{"label": "white chicken", "species": "chicken", "head": 15.0, "shadow": "shadow_small"},
	"chicken_brown":
	{"label": "brown chicken", "species": "chicken", "head": 15.0, "shadow": "shadow_small"},
	"pig_pink": {"label": "pink pig", "species": "pig", "head": 16.0, "shadow": "shadow_medium"},
	"pig_spotted":
	{"label": "spotted pig", "species": "pig", "head": 16.0, "shadow": "shadow_medium"},
	"sheep_white":
	{"label": "white sheep", "species": "sheep", "head": 19.0, "shadow": "shadow_medium"},
}

var spots := SPOTS.duplicate(true)
var toys: Array = []
var critters: Array = []
var blocked_cells := {}
var voices := Voices.new()
var on_say := Callable()
var rng := RandomNumberGenerator.new()
var kinds := ROLE_KINDS.duplicate()
var animals_dir := ""
var chars_dir := ""
var freeze := false
var is_night := false
var has_open := false
var tv_on := false
var jot_open := false
var settle := false
var events: Array = []
var knock_thing := ""
var duo_turns: Array = []
var duo_left := 0.0
var duo_next := 90.0

var _tex := {}


class Critter:
	extends RefCounted
	var id := ""
	var title := ""
	var pack := "animals"
	var sheet := ""
	var species := ""
	var shadow := "shadow_medium"
	var away := false
	var speed := 1.4
	var head := 22.0
	var pos := Vector2.ZERO
	var z := 0.0
	var dir := 7
	var anim := "idle"
	var anim_t := 0.0
	var mode := "idle"
	var path: Array = []
	var goal := ""
	var spot := ""
	var wait := 4.0
	var key := -1.0
	var jump := {}
	var pat_t := -1.0
	var bat_t := -1.0
	var bat_toy := {}
	var plan := {}
	var say_text := ""
	var say_left := 0.0
	var say_next := 40.0
	var hearts: Array = []
	var run := false
	var hops := 0
	var flip := false
	var hold := false
	var carry := ""


func setup(art_dir: String, seed_value: int) -> void:
	animals_dir = art_dir.path_join("isometric-animals/Gridwright Isometric Animals/")
	chars_dir = art_dir.path_join("isometric-characters/Gridwright Isometric Characters/")
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	voices.rng.seed = rng.randi()
	var nina := _make("nina", "Nina", "animals", "cat_black", 1.5, 18.0)
	var argos := _make("argos", "Argos", "animals", "dog_golden", 1.25, 20.0)
	var person := _make("person", "", "chars", "villager", 1.3, 46.0)
	critters = [nina, argos, person]
	set_kind(nina, kinds["nina"])
	set_kind(argos, kinds["argos"])
	place(nina, "sofa", "sleep" if not is_night else "sit")
	place(argos, "rug", "sit")
	place(person, "board", "sit")
	person.pos = _center(spots["board"]["cell"])
	person.dir = 5
	toys = [
		{
			"kind": "yarn",
			"pos": _center(Vector2i(5, 5)),
			"z": 0.0,
			"hits": 0,
			"hop": {},
			"spin": 0.0
		}
	]


func _make(
	id: String, title: String, pack: String, sheet: String, speed: float, head: float
) -> Critter:
	var c := Critter.new()
	c.id = id
	c.title = title
	c.pack = pack
	c.sheet = sheet
	c.speed = speed
	c.head = head
	c.wait = rng.randf_range(4.0, 9.0)
	c.say_next = rng.randf_range(25.0, 60.0)
	return c


func critter(id: String) -> Critter:
	for c in critters:
		if c.id == id:
			return c
	return null


# the kind a settings value names for a pet, else that pet's own
static func kind_of(value: Variant, id: String) -> String:
	var k := str(value)
	return k if k == NONE or KINDS.has(k) else ROLE_KINDS[id]


func set_kind(c: Critter, kind: String) -> void:
	kinds[c.id] = kind
	c.away = kind == NONE
	if c.away:
		c.species = ""
		voices.species.erase(c.title)
		return
	var k: Dictionary = KINDS[kind]
	c.sheet = kind
	c.species = k["species"]
	voices.species[c.title] = c.species
	c.head = k["head"]
	c.shadow = k["shadow"]


# the pet is another animal (or gone) now: whatever it was doing is dropped and it starts over
func change_kind(c: Critter, kind: String) -> void:
	set_kind(c, kind)
	c.hold = false
	c.run = false
	c.flip = false
	c.hops = 0
	c.carry = ""
	c.hearts = []
	c.bat_toy = {}
	c.plan = {}
	c.say_left = 0.0
	c.pat_t = -1.0
	c.bat_t = -1.0
	c.wait = 5.0
	if not c.away:
		place(c, "sofa" if c.id == "nina" else "rug", "sit")


# the pet's own voice: a cat purrs and a dog barks, nothing else makes either sound
func cry(c: Critter) -> String:
	return {"cat": "purr", "dog": "bark"}.get(c.species, "")


func species_here() -> Array:
	return (
		critters
		. filter(func(c): return not c.away and c.id != "person")
		. map(func(c): return c.species)
	)


# both pets in the room, as the pair scenes need
func pair() -> bool:
	return not (critter("nina").away or critter("argos").away)


func _center(cell: Vector2i) -> Vector2:
	return Vector2(cell.x + 0.5, cell.y + 0.5)


func _blocked(cell: Vector2i) -> bool:
	return (
		cell.x < 1
		or cell.y < 1
		or cell.x >= COLS
		or cell.y >= ROWS
		or cell == CHAIR
		or blocked_cells.has(cell)
	)


# after the furniture changed: whoever is walking plans the rest of the way again
func reroute() -> void:
	for c in critters:
		if c.mode != "walk" or c.path.is_empty() or not c.jump.is_empty():
			continue
		if not c.bat_toy.is_empty():
			_walk_to_toy(c)
		else:
			c.path = route(_cell_of(c.pos), _cell_of(c.path[c.path.size() - 1]))


func place(c: Critter, spot: String, mode: String) -> void:
	var s: Dictionary = spots[spot]
	c.spot = spot
	c.path = []
	c.jump = {}
	c.goal = ""
	if s.has("perch"):
		c.pos = s["perch"]
		c.z = s["z"]
		c.key = s["key"]
	else:
		c.pos = _center(s["cell"])
		c.z = 0.0
		c.key = -1.0
	c.dir = s.get("face", 7)
	_settle(c, mode)


func _settle(c: Critter, mode: String) -> void:
	c.mode = mode
	c.anim = "sleep" if mode == "sleep" else "idle"
	c.anim_t = 0.0


func route(from: Vector2i, to: Vector2i) -> Array:
	if from == to:
		return []
	var prev := {from: from}
	var queue: Array = [from]
	var found := false
	while not queue.is_empty() and not found:
		var cur: Vector2i = queue.pop_front()
		for d in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]:
			var n: Vector2i = cur + d
			if prev.has(n) or _blocked(n):
				continue
			prev[n] = cur
			if n == to:
				found = true
				break
			queue.append(n)
	if not found:
		return []
	var out: Array = []
	var at := to
	while at != from:
		out.push_front(_center(at))
		at = prev[at]
	return out


func _cell_of(p: Vector2) -> Vector2i:
	return Vector2i(clampi(int(floor(p.x)), 1, COLS - 1), clampi(int(floor(p.y)), 1, ROWS - 1))


func go(c: Critter, spot: String, mode: String, dur: float) -> void:
	if c.away:
		return
	var s: Dictionary = spots[spot]
	c.plan = {"spot": spot, "mode": mode, "dur": dur}
	c.goal = spot
	if not c.jump.is_empty():
		return
	if c.z > 0.0:
		var from_cell: Vector2i = spots[c.spot]["cell"]
		_start_jump(c, _center(from_cell), 0.0, -1.0, true)
		return
	_walk(c, s["cell"])


func _walk(c: Critter, cell: Vector2i) -> void:
	c.path = route(_cell_of(c.pos), cell)
	c.mode = "walk"
	c.anim = "run" if c.run else "walk"
	if c.path.is_empty():
		_arrive(c)


func _start_jump(c: Critter, to: Vector2, to_z: float, to_key: float, then_go: bool) -> void:
	c.jump = {
		"from": c.pos, "from_z": c.z, "to": to, "to_z": to_z, "t": 0.0, "key": to_key, "go": then_go
	}
	c.mode = "jump"
	c.anim = "idle"
	c.key = maxf(c.key, to_key)
	c.dir = _face(to - c.pos, c.dir)


func _face(d: Vector2, fallback: int) -> int:
	if d.length() < 0.01:
		return fallback
	if absf(d.x) >= absf(d.y):
		return DIRS["se"] if d.x > 0 else DIRS["nw"]
	return DIRS["sw"] if d.y > 0 else DIRS["ne"]


func _arrive(c: Critter) -> void:
	var spot: String = c.plan.get("spot", c.goal)
	var s: Dictionary = spots.get(spot, {})
	if s.has("perch") and c.z <= 0.0:
		_start_jump(c, s["perch"], s["z"], s["key"], false)
		return
	if spot != "":
		c.spot = spot
	c.goal = ""
	if s.has("face"):
		c.dir = s["face"]
	var mode: String = c.plan.get("mode", "sit")
	if s.get("eat", false) and mode == "sit":
		c.mode = "idle"
		c.anim = "eat"
		c.anim_t = 0.0
	elif mode == "chase":
		_begin_bat(c)
		return
	elif mode == "knock" or mode == "push":
		_begin_swat(c)
		return
	elif mode == "cheer":
		c.run = false
		_settle(c, "idle")
		c.pat_t = 0.0
		c.hops -= 1
	else:
		_settle(c, "sleep" if mode == "sleep" else "idle")
	c.wait = c.plan.get("dur", 6.0)
	if c.id == "person":
		c.wait = 9999.0


func process(dt: float) -> int:
	var landed := 0
	_duo(dt)
	for c in critters:
		_step(c, dt)
	for t in toys.duplicate():
		if _step_toy(t, dt):
			toys.erase(t)
			landed += 1
	return landed


func _step(c: Critter, dt: float) -> void:
	if c.away:
		return
	c.anim_t += dt
	if c.pat_t >= 0.0:
		c.pat_t += dt
		if c.pat_t > 0.42:
			c.pat_t = -1.0
	elif c.hops > 0 and c.mode == "idle" and c.jump.is_empty():
		c.hops -= 1
		c.pat_t = 0.0
	for h in c.hearts:
		h["t"] += dt
	c.hearts = c.hearts.filter(func(h): return h["t"] < 1.4)
	if c.say_left > 0.0:
		c.say_left -= dt
	if not c.jump.is_empty():
		_step_jump(c, dt)
		return
	if c.mode == "walk":
		_step_walk(c, dt)
		return
	if c.mode == "bat":
		_step_bat(c, dt)
		return
	if c.mode == "stalk":
		_step_stalk(c)
		return
	if c.mode == "swat":
		_step_swat(c, dt)
		return
	if freeze or c.hold:
		return
	c.wait -= dt
	if c.say_left <= 0.0 and c.id != "person":
		c.say_next -= dt
		if c.say_next <= 0.0:
			c.say_next = rng.randf_range(40.0, 90.0)
			if c.mode != "sleep" and _quiet():
				speak(c, "muse")
	if c.wait <= 0.0:
		_decide(c)


func _step_walk(c: Critter, dt: float) -> void:
	var move := c.speed * (1.9 if c.run else 1.0) * dt
	while move > 0.0 and not c.path.is_empty():
		var wp: Vector2 = c.path[0]
		var d := wp - c.pos
		c.dir = _face(d, c.dir)
		if d.length() <= move:
			c.pos = wp
			move -= d.length()
			c.path.pop_front()
		else:
			c.pos += d.normalized() * move
			move = 0.0
	if c.path.is_empty():
		_arrive(c)


func _step_jump(c: Critter, dt: float) -> void:
	var j: Dictionary = c.jump
	j["t"] += dt / 0.45
	var t: float = minf(j["t"], 1.0)
	c.pos = (j["from"] as Vector2).lerp(j["to"], t)
	c.z = lerpf(j["from_z"], j["to_z"], t) + 9.0 * 4.0 * t * (1.0 - t)
	if j["t"] >= 1.0:
		c.z = j["to_z"]
		c.pos = j["to"]
		if j["to_z"] <= 0.0:
			c.key = -1.0
		else:
			c.key = j["key"]
		var again: bool = j["go"]
		c.jump = {}
		if c.plan.get("mode") == "chase":
			_walk_to_toy(c)
		elif again:
			_walk(c, spots[c.plan["spot"]]["cell"])
		else:
			c.mode = "idle"
			_arrive(c)


func _decide(c: Critter) -> void:
	match c.id:
		"nina":
			_decide_nina(c)
		"argos":
			_decide_argos(c)
		_:
			c.wait = 9999.0


func _pick(options: Array, current: String) -> Array:
	var total := 0.0
	for o in options:
		if o[0] != current:
			total += o[1]
	var roll := rng.randf() * total
	for o in options:
		if o[0] == current:
			continue
		roll -= o[1]
		if roll <= 0.0:
			return o
	return options[0]


func cheer(c: Critter, spot: String, hops: int, occasion: String, thing: String = "") -> void:
	c.run = true
	c.hops = hops
	speak(c, occasion, thing)
	go(c, spot, "cheer", 4.0)


func knock(c: Critter) -> void:
	c.run = false
	go(c, "desk", "knock", 6.0)


func _begin_swat(c: Critter) -> void:
	c.dir = 5
	c.mode = "swat"
	c.anim = "attack"
	c.anim_t = 0.0
	c.bat_t = 0.0


func _step_swat(c: Critter, dt: float) -> void:
	var before: float = c.bat_t
	c.bat_t += dt
	if before < 0.25 and c.bat_t >= 0.25:
		events.append("swat")
	if c.bat_t >= 0.7:
		c.bat_t = -1.0
		c.mode = "idle"
		c.anim = "idle"
		if c.plan.get("mode") == "push":
			c.dir = 7
			c.wait = 5.0
			return
		speak(c, "old", knock_thing)
		go(c, "knocked", "sit", 30.0)
		c.wait = 9999.0


func settle_near(on: bool) -> void:
	if on == settle:
		return
	settle = on
	for id in ["nina", "argos"]:
		var c := critter(id)
		if c.mode in ["idle", "sleep"] and c.jump.is_empty() and c.goal == "":
			c.wait = minf(c.wait, 0.5)


func _settled(c: Critter, spot: String) -> bool:
	if c.spot == spot and c.mode == "sleep":
		c.wait = 40.0
		return true
	go(c, spot, "sleep", 40.0)
	c.wait = 9999.0
	return true


func _decide_nina(c: Critter) -> void:
	c.run = false
	if settle and _settled(c, "sofa"):
		return
	var options: Array = [
		["pad", 0.0 if jot_open or is_night else 0.9, "sit", rng.randf_range(15, 30)],
		["sofa", 1.0 if is_night else 3.0, "sleep", rng.randf_range(25, 45)],
		[
			"desk",
			6.0 if is_night else 1.5,
			"sleep" if is_night else "sit",
			rng.randf_range(30, 60) if is_night else rng.randf_range(10, 20)
		],
		["rug", 2.0, "sit", rng.randf_range(8, 14)],
		["lamp", 1.0, "sit", rng.randf_range(6, 10)],
		["mid", 1.0, "sit", rng.randf_range(5, 9)],
		["sill", 1.2, "sit", rng.randf_range(15, 30)],
		["tv", 7.0 if tv_on else 0.0, "sit", rng.randf_range(12, 25)],
		["yarn", 2.5, "chase", 0.0],
	]
	var pick := _pick(options, c.spot)
	if pick[0] == "yarn":
		var toy := _toy_of("yarn")
		if toy.is_empty():
			return _decide_nina(c)
		chase(c, toy, 3)
		return
	if c.mode == "sleep" and pick[2] != "sleep" and rng.randf() < 0.5 and _quiet():
		speak(c, "wake")
	go(c, pick[0], pick[2], pick[3])
	c.wait = 9999.0


func _decide_argos(c: Critter) -> void:
	c.run = false
	if settle and _settled(c, "rug"):
		return
	var wander := ["lamp", "door", "mid", "corner", "nook", "rug2"]
	var options: Array = [
		["bed", 3.0, "sleep", rng.randf_range(30, 60)],
		["rug", 2.0, "sit", rng.randf_range(8, 14)],
		["bowl", 1.0, "sit", rng.randf_range(5, 8)],
		["board", 1.5, "sit", rng.randf_range(6, 10)],
		[wander[rng.randi() % wander.size()], 4.0, "sit", rng.randf_range(4, 9)],
	]
	var pick := _pick(options, c.spot)
	go(c, pick[0], pick[2], pick[3])
	c.wait = 9999.0


func _toy_of(kind: String) -> Dictionary:
	for t in toys:
		if t["kind"] == kind:
			return t
	return {}


func chase(c: Critter, toy: Dictionary, hits: int) -> void:
	if c.away:
		return
	toy["hits"] = hits
	c.bat_toy = toy
	c.run = true
	c.plan = {"spot": "", "mode": "chase", "dur": 0.0}
	if not c.jump.is_empty():
		return
	if c.z > 0.0:
		_start_jump(c, _center(spots[c.spot]["cell"]), 0.0, -1.0, false)
		return
	_walk_to_toy(c)


func _toy_cell(toy: Dictionary) -> Vector2i:
	return _cell_of(toy["pos"])


func _walk_to_toy(c: Critter) -> void:
	var toy: Dictionary = c.bat_toy
	if toy.is_empty() or not toys.has(toy):
		_end_chase(c)
		return
	var tc := _toy_cell(toy)
	var here := _cell_of(c.pos)
	var best: Array = []
	var order := [Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1)]
	if toy["kind"] == "paper":
		order = [Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0)]
	for d in order:
		var n: Vector2i = tc + d
		if _blocked(n):
			continue
		if n == here:
			_begin_bat(c)
			return
		var r := route(here, n)
		if not r.is_empty() and (best.is_empty() or r.size() < best.size()):
			best = r
	if best.is_empty():
		_end_chase(c)
		return
	c.mode = "walk"
	c.anim = "run"
	c.path = best


func _end_chase(c: Critter) -> void:
	c.bat_toy = {}
	c.run = false
	c.plan = {}
	_settle(c, "idle")
	c.wait = 4.0


func _begin_bat(c: Critter) -> void:
	var toy: Dictionary = c.bat_toy
	if toy.is_empty() or not toys.has(toy):
		_end_chase(c)
		return
	c.dir = _face(toy["pos"] - c.pos, c.dir)
	c.mode = "bat"
	c.anim = "attack"
	c.anim_t = 0.0
	c.bat_t = 0.0


func _step_bat(c: Critter, dt: float) -> void:
	var before: float = c.bat_t
	c.bat_t += dt
	if before < 0.25 and c.bat_t >= 0.25:
		_launch(c)
	if c.bat_t >= 0.7:
		c.bat_t = -1.0
		var toy: Dictionary = c.bat_toy
		if toy.is_empty() or not toys.has(toy) or toy["hits"] <= 0:
			_end_chase(c)
		else:
			c.mode = "stalk"
			c.anim = "idle"


func _step_stalk(c: Critter) -> void:
	var toy: Dictionary = c.bat_toy
	if toy.is_empty() or not toys.has(toy) or (toy["hop"] as Dictionary).is_empty():
		c.anim = "run"
		_walk_to_toy(c)


func _launch(c: Critter) -> void:
	var toy: Dictionary = c.bat_toy
	if toy.is_empty() or not toys.has(toy):
		return
	toy["hits"] -= 1
	var from: Vector2 = toy["pos"]
	if toy["kind"] == "paper" and toy["hits"] <= 0:
		toy["hop"] = {
			"from": from,
			"to": BIN_TOP,
			"to_z": BIN_Z,
			"t": 0.0,
			"dur": 0.7,
			"peak": 16.0,
			"bin": true
		}
		return
	var dest := _toy_dest(from, c.dir)
	toy["hop"] = {
		"from": from, "to": dest, "to_z": 0.0, "t": 0.0, "dur": 0.55, "peak": 7.0, "bin": false
	}


func _toy_dest(from: Vector2, dir: int) -> Vector2:
	var step := Vector2.ZERO
	match dir:
		7:
			step = Vector2(1, 0)
		3:
			step = Vector2(-1, 0)
		1:
			step = Vector2(0, 1)
		_:
			step = Vector2(0, -1)
	for dist in [2.0, 1.0, 3.0]:
		var p: Vector2 = from + step * float(dist)
		var to := _cell_of(p)
		var inside := p.x >= 1.0 and p.y >= 1.0 and p.x < COLS and p.y < ROWS
		# a hop clears furniture, but a toy never lands where nobody can walk to it
		if inside and not _blocked(to) and not route(_cell_of(from), to).is_empty():
			return _center(to)
	return from


func _step_toy(t: Dictionary, dt: float) -> bool:
	var h: Dictionary = t["hop"]
	if h.is_empty():
		return false
	h["t"] += dt / h["dur"]
	var f: float = minf(h["t"], 1.0)
	t["pos"] = (h["from"] as Vector2).lerp(h["to"], f)
	t["z"] = lerpf(0.0, h["to_z"], f) + h["peak"] * 4.0 * f * (1.0 - f)
	t["spin"] += dt * 14.0
	if h["t"] >= 1.0:
		t["pos"] = h["to"]
		t["z"] = h["to_z"]
		var in_bin: bool = h["bin"]
		t["hop"] = {}
		return in_bin
	return false


func pat(c: Critter, occasion: String) -> void:
	c.pat_t = 0.0
	for i in 3:
		c.hearts.append({"t": -0.18 * i, "dx": rng.randf_range(-8.0, 8.0)})
	if c.mode == "sleep":
		c.mode = "idle"
		c.anim = "idle"
		c.wait = 5.0
		speak(c, "wake")
	else:
		c.wait = maxf(c.wait, 4.0)
		speak(c, occasion)


func say(c: Critter, text: String) -> void:
	if text == "" or c.away:
		return
	c.say_text = Settings.pets(text)
	c.say_left = Voices.bubble_time(text)
	if on_say.is_valid():
		on_say.call(c.id, text)


func set_voices(v: Dictionary) -> void:
	if v == voices.batch:
		return
	voices.set_batch(v)
	duo_turns = []


func line(who: String, occasion: String, thing: String = "") -> String:
	return voices.line(who, occasion, thing)


func speak(c: Critter, occasion: String, thing: String = "") -> void:
	say(c, line(c.title, occasion, thing))


func nearest(spot: String) -> Critter:
	var at := _center(spots[spot]["cell"])
	var best: Critter = null
	for id in ["nina", "argos"]:
		var c := critter(id)
		if c.away or c.mode == "sleep" or c.say_left > 0.0 or not duo_turns.is_empty():
			continue
		if best == null or c.pos.distance_to(at) < best.pos.distance_to(at):
			best = c
	return best


func nudge(spot: String, occasion: String, thing: String = "") -> void:
	var c := nearest(spot)
	if c != null:
		speak(c, occasion, thing)


func _quiet() -> bool:
	return (
		duo_turns.is_empty()
		and critter("nina").say_left <= 0.0
		and critter("argos").say_left <= 0.0
	)


func _duo(dt: float) -> void:
	if not duo_turns.is_empty():
		duo_left -= dt
		if duo_left <= 0.0:
			_duo_turn()
		return
	if freeze or not pair():
		return
	duo_next -= dt
	if duo_next > 0.0:
		return
	duo_next = 10.0
	for id in ["nina", "argos"]:
		var c := critter(id)
		if c.mode != "idle" or c.goal != "" or not c.jump.is_empty() or c.say_left > 0.0:
			return
	var turns := voices.duo()
	if turns.is_empty():
		return
	duo_next = rng.randf_range(150.0, 300.0)
	play_duo(turns)


func play_duo(turns: Array) -> void:
	if not pair():
		return
	duo_turns = turns.duplicate()
	_duo_turn()


func _duo_turn() -> void:
	for id in ["nina", "argos"]:
		critter(id).say_left = 0.0
	if duo_turns.is_empty():
		return
	var turn: Array = duo_turns.pop_front()
	var c := critter(str(turn[0]).to_lower())
	say(c, turn[1])
	duo_left = c.say_left


func drop_toy(to: Vector2) -> Dictionary:
	var toy := {"kind": "paper", "pos": to, "z": 0.0, "hits": 2, "hop": {}, "spin": 0.0}
	toys.append(toy)
	return toy


func _load(path: String) -> Texture2D:
	if _tex.has(path):
		return _tex[path]
	var tex: Texture2D = null
	var image := Image.load_from_file(path) if FileAccess.file_exists(path) else null
	if image != null:
		tex = ImageTexture.create_from_image(image)
	_tex[path] = tex
	return tex


func feet(c: Critter, o: Vector2, k: int) -> Vector2:
	var hop: float = 0.0
	if c.pat_t >= 0.0:
		hop = 7.0 * sin(PI * c.pat_t / 0.42)
	return Vector2(16.0 * (c.pos.x - c.pos.y), 8.0 * (c.pos.x + c.pos.y) - c.z - hop) * k + o


func sort_key(c: Critter) -> float:
	return c.key if c.key >= 0.0 else c.pos.x + c.pos.y - 1.0


func hit_rect(c: Critter, o: Vector2, k: int) -> Rect2:
	var f := feet(c, o, k)
	var w := 13.0 if c.pack == "animals" else 10.0
	return Rect2(f - Vector2(w, c.head + 4) * k, Vector2(w * 2, c.head + 6) * k)


func draw_shadow(canvas: CanvasItem, c: Critter, o: Vector2, k: int) -> void:
	if c.z > 0.5 or c.away:
		return
	var tex := _load(animals_dir + "Effects/%dx/%s.png" % [k, c.shadow])
	var f := feet(c, o, k)
	if tex == null:
		return
	canvas.draw_texture(
		tex, (f - Vector2(tex.get_width(), tex.get_height()) / 2.0).round(), Color(1, 1, 1, 0.35)
	)


func draw(canvas: CanvasItem, c: Critter, o: Vector2, k: int) -> void:
	var f := feet(c, o, k)
	var base := animals_dir if c.pack == "animals" else chars_dir
	var anim := c.anim
	if c.pack == "chars":
		anim = "walk" if c.mode == "walk" else "idle"
	var tex := _load(base + "Sheets/%dx/%s/%s_%s.png" % [k, c.sheet, c.sheet, anim])
	if tex == null:
		_draw_flat(canvas, c, f, k)
		return
	var cell := 64 * k
	var frames := maxi(1, tex.get_width() / cell)
	var frame := int(c.anim_t * FPS.get(anim, 6.0)) % frames
	if c.flip:
		canvas.draw_set_transform(f + Vector2(0, -8 * k), PI, Vector2.ONE)
		f = Vector2(0, 8 * k)
	canvas.draw_texture_rect_region(
		tex,
		Rect2((f - Vector2(32, 46) * k).round(), Vector2(cell, cell)),
		Rect2(frame * cell, c.dir * cell, cell, cell)
	)
	if c.flip:
		canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	if c.species == "cat":
		_draw_collar(canvas, c, f, k)


# a kind's idle frame facing the viewer's right, feet on `at`, for the settings screen
func draw_preview(canvas: CanvasItem, kind: String, t: float, at: Vector2, k: int) -> void:
	var tex := _load(animals_dir + "Sheets/%dx/%s/%s_idle.png" % [k, kind, kind])
	if tex == null:
		return
	var cell := 64 * k
	var frame := int(t * FPS["idle"]) % maxi(1, tex.get_width() / cell)
	canvas.draw_texture_rect_region(
		tex,
		Rect2((at - Vector2(32, 46) * k).round(), Vector2(cell, cell)),
		Rect2(frame * cell, DIRS["se"] * cell, cell, cell)
	)


func _draw_collar(canvas: CanvasItem, c: Critter, f: Vector2, k: int) -> void:
	var neck: Vector2 = NECK[c.dir]
	var at: Vector2 = f + neck * k
	if c.mode == "sleep":
		at = f + Vector2(0, -7) * k
	canvas.draw_rect(Rect2((at - Vector2(k, 0.5 * k)).round(), Vector2(2 * k, k)), Color("d9a93a"))
	var gem := Color("7be0d0") if int(c.anim_t * 3.0) % 5 != 0 else Color.WHITE
	canvas.draw_rect(Rect2((at + Vector2(0, -0.5 * k)).round(), Vector2(k, k)), gem)


func _draw_flat(canvas: CanvasItem, c: Critter, f: Vector2, k: int) -> void:
	if c.id == "person":
		canvas.draw_circle(f - Vector2(0, 40 * k), 6 * k, Color("e0b07a"))
		canvas.draw_rect(
			Rect2(f - Vector2(5 * k, 34 * k), Vector2(10 * k, 30 * k)), Color("6f8fb0")
		)
		return
	var cat: bool = c.species == "cat"
	var body := Color("231f2b") if cat else Color("d9a95a")
	var asleep: bool = c.mode == "sleep"
	var wob := sin(c.anim_t * 6.0) * 0.4 * k if c.mode == "walk" else 0.0
	var long := 9.0 if cat else 12.0
	var tall := 5.0 if asleep else (8.0 if cat else 10.0)
	var side := Vector2(1, 0) if c.dir in [7, 6, 5] else Vector2(-1, 0)
	canvas.draw_rect(
		Rect2(f + Vector2(-long * k / 2.0, (-tall - 3) * k + wob), Vector2(long * k, tall * k)),
		body
	)
	var head := f + Vector2(side.x * (long * 0.5) * k, (-tall - 5) * k + wob)
	canvas.draw_circle(head, 4 * k, body)
	canvas.draw_rect(Rect2(head + Vector2(-4 * k, -6 * k), Vector2(2 * k, 3 * k)), body)
	canvas.draw_rect(Rect2(head + Vector2(2 * k, -6 * k), Vector2(2 * k, 3 * k)), body)
	if cat:
		var eye := Color("f2d34a")
		canvas.draw_rect(Rect2(head + Vector2(-2 * k, -k), Vector2(k, k)), eye)
		canvas.draw_rect(Rect2(head + Vector2(k, -k), Vector2(k, k)), eye)
		canvas.draw_rect(Rect2(head + Vector2(-2 * k, 3 * k), Vector2(4 * k, k)), Color("d9a93a"))
		canvas.draw_rect(Rect2(head + Vector2(-k, 3 * k), Vector2(k, k)), Color("7be0d0"))
	canvas.draw_rect(
		Rect2(f + Vector2(-side.x * long * 0.5 * k - k, (-tall - 7) * k), Vector2(2 * k, 5 * k)),
		body
	)
