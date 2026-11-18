extends RefCounted

# The room's small surprises. One big thing at a time, minutes apart, never while a card, menu,
# notepad, closet or decorating is up; everything takes its dice from `rng` and its time from the
# home's own clock, so a staged run or the soak replays it. `force(name)` starts one on demand.
const Props := preload("res://props.gd")
const Pets := preload("res://pets.gd")

const STORE := "user://house_found.json"
const BIG_GAP := Vector2(420.0, 1200.0)
const FIRST_BIG := Vector2(120.0, 360.0)
const FLOP_AT := 20
const SULK_AT := 14
const SULK_GAP := 5.0
const PET_RUN_GAP := 4.0
const ZOOM_CELLS := [
	Vector2i(2, 2),
	Vector2i(8, 2),
	Vector2i(8, 8),
	Vector2i(2, 8),
	Vector2i(5, 5),
	Vector2i(2, 5),
	Vector2i(5, 8),
	Vector2i(8, 5),
	Vector2i(5, 2)
]
const DOOR_FRONT := Vector2i(1, 7)
const MUG_AT := Vector2(4.27, 0.33)
const QUICK := [
	"flop", "sulk", "box", "piano", "fire", "bird", "balloon", "nightcat", "star", "plane", "fireworks",
	"mouse", "book", "globe", "found", "disco", "tlon", "uqbar", "argos", "borges",
	"spin", "pencil", "stretch", "nod", "cast", "bow", "salute", "visitor",
	"moth", "rainwatch", "storm", "jarfull", "newlook"
]
const BRING := ["slipper", "yarn", "crumple"]
const LINES := {
	"push": {"Nina": ["gravity is a theory.", "it was in my way.", "I regret nothing."]},
	"zoom": {"Nina": ["3 a.m. in the afternoon.", "ignore that."], "Argos": ["WHEEE", "I ran!"]},
	"bring": {"Argos": ["look what I found!", "a gift!", "I brought it. all of it."]},
	"box": {"Nina": ["if it fits, I sit."]},
	"flop": {"Argos": ["belly. now.", "this is the best part."]},
	"sulk": {"Nina": ["I have left the room. spiritually."]},
	"laser":
	{"Nina": ["it is MINE", "the dot. the dot."], "Argos": ["are we hunting?", "Nina! wait!"]},
	"hearth": {"Nina": ["warm. mine."], "Argos": ["warm...", "good fire."]},
	"bed": {"Nina": ["the bed is a cat's."], "Argos": ["soft"]},
	"watch": {"Argos": ["go Nina go!"], "Nina": ["amateurs."]},
}
# every secret there is, by id: the found card counts these and names the ones he has met
const CATALOGUE := [
	["push", "Nina and the edge of the desk"],
	["bring", "Argos brings a gift"],
	["zoomies", "zoomies"],
	["box", "Nina in a box"],
	["laser", "the red dot"],
	["flop", "Argos, belly up"],
	["sulk", "Nina leaves the room"],
	["hearth", "both by the fire"],
	["bed", "a nap on the bed"],
	["keys", "Nina on the piano"],
	["piano", "the piano"],
	["piano_hero", "a hero at the piano"],
	["fire", "the fireplace"],
	["toss", "a note into the fire"],
	["bird", "a bird on the sill"],
	["balloon", "a balloon"],
	["plane", "a plane"],
	["nightcat", "a cat on the fence"],
	["star", "a shooting star"],
	["fireworks", "New Year fireworks"],
	["sillsnow", "snow on the sill"],
	["snowman", "a snowman on the sill"],
	["lantern", "a lit pumpkin"],
	["cake", "the birthday cake"],
	["book", "a book from the shelf"],
	["borges", "the Library of Babel"],
	["globe", "the snow globe"],
	["mouse", "the mouse"],
	["fidget_spin", "a spin of the chair"],
	["fidget_pencil", "the balancing pencil"],
	["fidget_stretch", "a stretch"],
	["fidget_nod", "nodding off"],
	["cast", "a spell at the hearth"],
	["salute", "a salute at the door"],
	["bow", "an arrow in the wall"],
	["visitor", "a visitor"],
	["konami", "the old code"],
	["tlon", "Tlon"],
	["uqbar", "Uqbar"],
	["argos_word", "his name"],
	["umbrella", "an umbrella by the door"],
	["moth", "a moth at the lamp"],
	["rain_watch", "Nina watches the rain"],
	["storm_hide", "Argos in the storm"],
	["tv_react", "the pets and the TV"],
	["new_look", "a new look"],
	["jar_full", "a full jar"],
]

var _hw: WeakRef
var h:
	get:
		return _hw.get_ref()
var rng := RandomNumberGenerator.new()
var found := {}
var persist := false
var scene := {}
var things: Array = []
var fall := {}
var next_big := 0.0
var t := 0.0
var laser_on := false
var laser_pin := false
var firework_forced := false
var laser_at := Vector2.ZERO
var laser_cell := Vector2i(-1, -1)
var toss_ids: Array = []
var mug_off := false
var pen_off := false
var forced: Array = []

var _pet_run := {"id": "", "n": 0, "last": -99.0}
var _laser_t := 0.0
var _sulk := 0.0
var _sulking := false
var _flop := 0.0
var _box_next := 0.0
var _furn_next := {}
var _spot_n := 0


func setup(home, seed_value: int, persist_it: bool) -> void:
	_hw = weakref(home)
	found = {}
	persist = persist_it
	rng.seed = seed_value if seed_value >= 0 else randi()
	next_big = rng.randf_range(FIRST_BIG.x, FIRST_BIG.y)
	_box_next = rng.randf_range(25.0, 55.0)
	for k in ["fire", "piano", "bed"]:
		_furn_next[k] = rng.randf_range(90.0, 240.0)
	if persist and FileAccess.file_exists(STORE):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(STORE))
		if d is Dictionary and d.get("found") is Array:
			for id in d["found"]:
				found[str(id)] = true


# met a secret: counted once, kept in user://house_found.json ({"found": [id, ...]})
func find(id: String) -> void:
	h.sound.request("egg_" + id)
	if found.has(id):
		return
	found[id] = true
	if persist:
		var f := FileAccess.open(STORE, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify({"found": found.keys()}))


func calm() -> bool:
	return not (
		h._cards_blocked()
		or h.card.is_open()
		or h.menu.is_open
		or not h.ring_ids.is_empty()
		or h.person.arrive_left > 0.0
		or h.person.stretch_left > 0.0
		or h.knock.pending >= 0
		or not h.knock.flying.is_empty()
	)


func line(c, key: String) -> void:
	var opts: Array = LINES.get(key, {}).get(c.title, [])
	if not opts.is_empty() and c.say_left <= 0.0:
		h.pets.say(c, opts[rng.randi() % opts.size()])


func loose(c) -> bool:
	return c.mode in ["idle", "sleep"] and c.jump.is_empty() and c.goal == "" and not c.hold


func spot(name: String, def: Dictionary) -> String:
	h.pets.spots[name] = def
	return name


func cell_at(pos: Vector2) -> Vector2i:
	var a: float = (pos.x - h._o.x) / (16.0 * h._k)
	var b: float = (pos.y - h._o.y) / (8.0 * h._k)
	return Vector2i(floori((a + b) / 2.0), floori((b - a) / 2.0))


# the nearest cell a pet could stand on and reach from `from`
func free_cell(want: Vector2i, from: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := INF
	for x in range(1, Pets.COLS):
		for y in range(1, Pets.ROWS):
			var c := Vector2i(x, y)
			var d := Vector2(c - want).length()
			if d >= best_d or h.pets._blocked(c):
				continue
			if c != from and h.pets.route(from, c).is_empty():
				continue
			best = c
			best_d = d
	return best


func piece(prefix: String) -> Dictionary:
	for p in h.layout.pieces:
		if str(p["p"]).begins_with(prefix):
			return p
	return {}


func front_cell(p: Dictionary) -> Vector2i:
	var r: Rect2i = h.layout.rect(p)
	var best := Vector2i(-1, -1)
	var best_d := INF
	for x in range(r.position.x - 1, r.end.x + 1):
		for y in range(r.position.y - 1, r.end.y + 1):
			var c := Vector2i(x, y)
			if r.has_point(c) or h.pets._blocked(c):
				continue
			if c != DOOR_FRONT and h.pets.route(DOOR_FRONT, c).is_empty():
				continue
			var d := Vector2(c).distance_to(Vector2(5, 5))
			if d < best_d:
				best = c
				best_d = d
	return best


# a pet-sized perch on a piece: reach it from the front, jump onto the top
func perch(name: String, p: Dictionary, lift: float = 0.85) -> String:
	var r: Rect2i = h.layout.rect(p)
	var cell := front_cell(p)
	if cell.x < 0:
		return ""
	return spot(
		name,
		{
			"cell": cell,
			"perch": Vector2(r.position.x + r.size.x / 2.0, r.position.y + r.size.y / 2.0),
			"z": float(h.layout.height(p)) * lift,
			"key": float(h.layout.draw_key(p)) + 0.6,
			"face": 7,
		}
	)


func process(dt: float) -> void:
	t += dt
	_pet_run["last"] += dt
	_sulk = maxf(0.0, _sulk - dt)
	if _flop > 0.0:
		_flop -= dt
		if _flop <= 0.0:
			var a = h.pets.critter("argos")
			a.flip = false
			a.hold = false
			a.mode = "idle"
			a.anim = "idle"
			a.wait = 1.0
	if _sulking and _sulk <= 0.0:
		_sulking = false
		_release(h.pets.critter("nina"), 1.0)
	_laser(dt)
	_scene(dt)
	_things(dt)
	if h.pets.freeze and forced.is_empty():
		return
	_director(dt)
	_ambient(dt)


func _director(dt: float) -> void:
	if not scene.is_empty():
		return
	next_big -= dt
	if next_big > 0.0:
		return
	if not calm() or not h._seen_data or laser_on or _flop > 0.0 or _sulk > 0.0:
		next_big = 20.0
		return
	next_big = rng.randf_range(BIG_GAP.x, BIG_GAP.y)
	var hour: float = h._hour()
	var picks: Array = []
	if hour >= 8.0 and hour < 22.0:
		picks.append_array(["push", "bring", "zoomies"])
	elif hour >= 22.0 or hour < 3.0:
		picks.append("zoomies")
	if not picks.is_empty():
		start(picks[rng.randi() % picks.size()])


func start(name: String) -> bool:
	if not scene.is_empty():
		return false
	var nina = h.pets.critter("nina")
	var argos = h.pets.critter("argos")
	match name:
		"push":
			var item := "mug" if rng.randf() < 0.5 else "pen"
			h.pets.go(nina, "desk", "push", 8.0)
			nina.hold = true
			nina.run = false
			scene = {"k": "push", "st": 0, "t": 0.0, "item": item}
		"bring":
			var item: String = BRING[rng.randi() % BRING.size()]
			if item == "yarn" and h.pets._toy_of("yarn").is_empty():
				item = "slipper"
			var from := Vector2i(2, 6)
			if item == "crumple":
				from = Vector2i(6, 1)
			elif item == "yarn":
				from = h.pets._cell_of(h.pets._toy_of("yarn")["pos"])
			from = free_cell(from, h.pets._cell_of(argos.pos))
			var dest := free_cell(h.pets._cell_of(h.person.c.pos) + Vector2i(0, 1), from)
			if from.x < 0 or dest.x < 0:
				return false
			scene = {
				"k": "bring",
				"st": 0,
				"t": 0.0,
				"item": item,
				"from": from,
				"dest": dest,
				"lay": Vector2.ZERO
			}
			if item != "yarn":
				things.append(
					{
						"kind": item,
						"pos": Vector2(from) + Vector2(0.5, 0.5),
						"life": 40.0,
						"src": true
					}
				)
			argos.hold = true
			argos.run = true
			h.pets.go(argos, spot("bring_from", {"cell": from}), "sit", 0.1)
		"keys":
			var pn := piece("piano")
			var pk := perch("piano_top", pn, 0.95) if not pn.is_empty() else ""
			if pk == "":
				return false
			var r: Rect2i = h.layout.rect(pn)
			var along := Vector2(0, 1) if r.size.y >= r.size.x else Vector2(1, 0)
			var mid := Vector2(r.position.x + r.size.x / 2.0, r.position.y + r.size.y / 2.0)
			h.pets.go(nina, pk, "sit", 1.0)
			nina.hold = true
			scene = {"k": "keys", "st": 0, "t": 0.0, "a": mid - along * 0.35, "b": mid + along * 0.35, "n": 0.0}
		"zoomies":
			var runner = nina if rng.randf() < 0.5 else argos
			var seen = argos if runner == nina else nina
			var cells: Array = []
			var from: Vector2i = h.pets._cell_of(runner.pos)
			for c in ZOOM_CELLS:
				if not h.pets._blocked(c) and (c == from or not h.pets.route(from, c).is_empty()):
					cells.append(c)
			if cells.size() < 3:
				return false
			var lap: Array = []
			for i in 5:
				lap.append(cells[(i * 3 + rng.randi() % 2) % cells.size()])
			runner.hold = true
			runner.run = true
			seen.hold = true
			scene = {
				"k": "zoomies", "st": 0, "t": 0.0, "who": runner, "seen": seen, "lap": lap, "i": 0
			}
			_zoom_next()
		_:
			return false
	find(name)
	return true


func force(name: String) -> void:
	forced.append(name)


func _arrived(c) -> bool:
	return c.goal == "" and c.jump.is_empty() and c.mode in ["idle", "sleep"] and c.path.is_empty()


func _release(c, wait: float = 1.0) -> void:
	c.hold = false
	c.run = false
	c.wait = wait


func _scene(dt: float) -> void:
	if not forced.is_empty():
		if forced[0] in QUICK:
			_quick(forced.pop_front())
		elif scene.is_empty():
			start(forced.pop_front())
	if scene.is_empty():
		return
	scene["t"] += dt
	var nina = h.pets.critter("nina")
	var argos = h.pets.critter("argos")
	match scene["k"]:
		"push":
			if scene["st"] == 0 and nina.mode == "swat":
				scene["st"] = 1
			elif scene["st"] == 1 and nina.mode == "idle" and nina.bat_t < 0.0 and scene["t"] > 1.0:
				scene["st"] = 2
				scene["t"] = 0.0
				line(nina, "push")
			elif scene["st"] == 2 and scene["t"] > 5.0:
				_release(nina)
				scene = {}
			elif scene["t"] > 40.0:
				_release(nina)
				scene = {}
		"bring":
			var item: String = scene["item"]
			var st: int = scene["st"]
			if st == 0 and _arrived(argos) and argos.spot == "bring_from":
				argos.carry = item
				_take(item, scene["from"])
				h.pets.go(argos, spot("bring_to", {"cell": scene["dest"], "face": 5}), "sit", 0.1)
				scene["st"] = 1
			elif st == 1 and _arrived(argos) and argos.spot == "bring_to":
				argos.carry = ""
				argos.run = false
				var lay := Vector2(scene["dest"]) + Vector2(0.5, 0.5) + Vector2(0.0, 0.45)
				if item == "yarn":
					h.pets.toys.append(
						{"kind": "yarn", "pos": lay, "z": 0.0, "hits": 0, "hop": {}, "spin": 0.0}
					)
				else:
					things.append({"kind": item, "pos": lay, "life": 45.0})
				argos.dir = 5
				argos.anim = "idle"
				line(argos, "bring")
				scene["st"] = 2
				scene["t"] = 0.0
			elif st == 2 and scene["t"] > 7.0:
				_release(argos, 2.0)
				scene = {}
			elif scene["t"] > 90.0:
				argos.carry = ""
				_release(argos)
				scene = {}
		"keys":
			if scene["st"] == 0 and _arrived(nina) and nina.z > 0.0:
				scene["st"] = 1
				scene["t"] = 0.0
			elif scene["st"] == 1:
				var u: float = 0.5 - 0.5 * cos(scene["t"] * 1.6)
				nina.pos = (scene["a"] as Vector2).lerp(scene["b"], u)
				nina.dir = h.pets._face(scene["b"] - scene["a"], nina.dir)
				nina.mode = "idle"
				nina.anim = "walk"
				scene["n"] += dt
				if scene["n"] > 0.5:
					scene["n"] = 0.0
					h.sound.request("piano", rng.randi_range(-5, 12))
					h.hearth.notes.append({"t": 0.0, "dx": rng.randf_range(-6.0, 6.0)})
				if scene["t"] > 6.0:
					nina.anim = "idle"
					_release(nina)
					scene = {}
			elif scene["t"] > 40.0:
				_release(nina)
				scene = {}
		"zoomies":
			var who = scene["who"]
			var seen = scene["seen"]
			if seen.mode in ["idle", "sleep"] and seen.jump.is_empty():
				seen.mode = "idle"
				seen.anim = "idle"
				seen.dir = h.pets._face(who.pos - seen.pos, seen.dir)
			if scene["st"] == 0 and _arrived(who):
				_zoom_next()
			elif scene["st"] == 1 and scene["t"] > 1.0:
				who.anim = "idle"
				line(who, "zoom")
				line(seen, "watch")
				scene["st"] = 2
				scene["t"] = 0.0
			elif scene["st"] == 2 and scene["t"] > 3.0:
				_release(who, 2.0)
				_release(seen, 2.0)
				scene = {}
			elif scene["t"] > 60.0:
				_release(who)
				_release(seen)
				scene = {}


func _zoom_next() -> void:
	var lap: Array = scene["lap"]
	var i: int = scene["i"]
	if i >= lap.size():
		scene["st"] = 1
		scene["t"] = 0.0
		return
	scene["i"] = i + 1
	h.pets.go(scene["who"], spot("zoom_%d" % i, {"cell": lap[i]}), "sit", 0.1)


func _take(item: String, cell: Vector2i) -> void:
	if item == "yarn":
		var toy: Dictionary = h.pets._toy_of("yarn")
		h.pets.toys.erase(toy)
		return
	for th in things:
		if th.get("src", false):
			things.erase(th)
			return


func _things(dt: float) -> void:
	for th in things:
		th["life"] -= dt
	for th in things.filter(func(th): return th["life"] <= 0.0):
		_put_back(th)
	things = things.filter(func(th): return th["life"] > 0.0)
	if not fall.is_empty():
		fall["t"] += dt / 0.6
		if fall["t"] >= 1.0:
			things.append(
				{"kind": fall["kind"], "pos": fall["to"], "life": 55.0, "back": fall["kind"]}
			)
			fall = {}


# Nina's push reached the edge: the thing goes over
func pushed() -> void:
	var item: String = scene.get("item", "pen")
	if item == "mug":
		mug_off = true
	else:
		pen_off = true
	fall = {"kind": item, "t": 0.0, "to": Vector2(5.55, 1.7)}


func _laser(dt: float) -> void:
	var nina = h.pets.critter("nina")
	var argos = h.pets.critter("argos")
	if not laser_on:
		if nina.spot in ["laser"] and nina.hold and scene.is_empty():
			_release(nina, 1.5)
			_release(argos, 2.0)
		return
	_laser_t -= dt
	var want := cell_at(laser_at)
	if _laser_t > 0.0:
		return
	_laser_t = 0.35
	if not scene.is_empty():
		return
	find("laser")
	for c in [nina, argos]:
		if not c.hold:
			c.hold = true
			if c.mode == "sleep":
				c.mode = "idle"
	var from: Vector2i = h.pets._cell_of(nina.pos)
	var cell := free_cell(want, from)
	if cell.x < 0:
		return
	if cell != laser_cell or nina.mode != "walk":
		laser_cell = cell
		nina.run = true
		h.pets.go(nina, spot("laser", {"cell": cell}), "sit", 0.1)
	var af: Vector2i = h.pets._cell_of(argos.pos)
	var ncell: Vector2i = h.pets._cell_of(nina.pos)
	var trail := free_cell(ncell + Vector2i(1, 1), af)
	if trail.x >= 0 and trail != ncell and (argos.mode != "walk" or rng.randf() < 0.3):
		argos.run = true
		h.pets.go(argos, spot("laser2", {"cell": trail}), "sit", 0.1)
	if rng.randf() < 0.05:
		line(nina if rng.randf() < 0.5 else argos, "laser")


func set_laser(on: bool, pos: Vector2) -> void:
	if laser_pin:
		return
	laser_on = on and calm()
	laser_at = pos
	if laser_on:
		_laser_t = minf(_laser_t, 0.0)


func laser_draw(bounds: Rect2) -> void:
	if not laser_on:
		return
	var p := laser_at
	var w := 0.7 + 0.3 * sin(t * 18.0)
	h.room.draw_circle(p, 9.0 * w, Color(1.0, 0.1, 0.1, 0.18))
	h.room.draw_circle(p, 4.5, Color(1.0, 0.15, 0.12, 0.7))
	h.room.draw_circle(p, 2.2, Color(1.0, 0.85, 0.8))


# a click on a pet: returns true when the click was taken here
func pet_click(c) -> bool:
	if c.id == "nina" and _sulk > 0.0:
		h.pets.say(c, "...")
		return true
	var same: bool = _pet_run["id"] == c.id and _pet_run["last"] < PET_RUN_GAP
	_pet_run["n"] = _pet_run["n"] + 1 if same else 1
	_pet_run["id"] = c.id
	_pet_run["last"] = 0.0
	if c.id == "argos" and _pet_run["n"] >= FLOP_AT:
		_pet_run["n"] = 0
		_do_flop(c)
		return true
	if c.id == "nina" and _pet_run["n"] >= SULK_AT:
		_pet_run["n"] = 0
		_do_sulk(c)
		return true
	if c.id == "nina":
		h.sound.request("purr")
	elif c.id == "argos":
		h.sound.request("bark")
	return false


func _do_flop(c) -> void:
	find("flop")
	c.hold = true
	c.flip = true
	c.mode = "sleep"
	c.anim = "sleep"
	c.path = []
	c.jump = {}
	c.goal = ""
	_flop = 22.0
	line(c, "flop")


func _do_sulk(c) -> void:
	find("sulk")
	_sulk = 60.0
	c.hold = true
	c.run = false
	_sulking = true
	var cell: Vector2i = h.pets.spots["corner"]["cell"]
	h.pets.go(c, spot("sulk", {"cell": cell, "face": 3}), "sit", 1.0)
	line(c, "sulk")


func _ambient(dt: float) -> void:
	if not scene.is_empty() or laser_on or not calm():
		return
	_box_next -= dt
	if _box_next <= 0.0:
		_box_next = rng.randf_range(150.0, 300.0)
		if not _box():
			_box_next = 30.0
	for k in _furn_next:
		_furn_next[k] -= dt
		if _furn_next[k] > 0.0:
			continue
		_furn_next[k] = rng.randf_range(600.0, 1500.0) if k == "piano" else rng.randf_range(120.0, 320.0)
		match k:
			"fire":
				_hearth()
			"bed":
				_bed()
			"piano":
				if scene.is_empty() and not piece("piano").is_empty() and loose(h.pets.critter("nina")):
					start("keys")


# Nina into a crate or barrel that stands in the room; false when there is none
func _box() -> bool:
	var nina = h.pets.critter("nina")
	var crate := piece("crate")
	if crate.is_empty():
		crate = piece("barrel")
	if crate.is_empty():
		return false
	if loose(nina) and nina.spot != "box":
		var name := perch("box", crate, 0.8)
		if name != "":
			h.pets.go(nina, name, "sleep" if rng.randf() < 0.4 else "sit", rng.randf_range(40.0, 90.0))
			nina.wait = 9999.0
			find("box")
			line(nina, "box")
	return true


func _hearth() -> void:
	var fire := piece("fireplace")
	if fire.is_empty() or not h.fire_on():
		return
	var cell := front_cell(fire)
	if cell.x < 0:
		return
	for id in ["nina", "argos"]:
		var c = h.pets.critter(id)
		if loose(c) and rng.randf() < 0.7:
			var name := spot(
				"hearth_" + id,
				{
					"cell":
					(
						cell
						+ (
							Vector2i(1, 0)
							if id == "argos" and h.pets.critter("nina").spot == "hearth_nina"
							else Vector2i.ZERO
						)
					),
					"face": 5
				}
			)
			if h.pets._blocked(spots_cell(name)):
				name = spot("hearth_" + id, {"cell": cell, "face": 5})
			h.pets.go(c, name, "sleep", rng.randf_range(40.0, 80.0))
			c.wait = 9999.0
			find("hearth")
			line(c, "hearth")


func spots_cell(name: String) -> Vector2i:
	return h.pets.spots[name]["cell"]


func _bed() -> void:
	var bed := piece("bed_")
	if bed.is_empty():
		return
	var c = h.pets.critter("nina" if rng.randf() < 0.6 else "argos")
	if not loose(c):
		return
	var name := ""
	if c.id == "nina":
		name = perch("bed_top", bed, 0.9)
	else:
		var cell := front_cell(bed)
		if cell.x >= 0:
			name = spot("bed_front", {"cell": cell, "face": 5})
	if name != "":
		h.pets.go(c, name, "sleep", rng.randf_range(50.0, 110.0))
		c.wait = 9999.0
		find("bed")
		line(c, "bed")


func items() -> Array:
	var out: Array = []
	for th in things:
		out.append(
			{"key": th["pos"].x + th["pos"].y - 1.0, "pri": 1.75, "fn": _draw_thing.bind(th)}
		)
	if not fall.is_empty():
		var p: Vector2 = fall["to"]
		out.append({"key": p.x + p.y - 0.5, "pri": 1.75, "fn": _draw_fall})
	return out


func thing_poly(kind: String, at: Vector2) -> PackedVector2Array:
	var r: float = 7.0 * h._k
	return PackedVector2Array(
		[
			at + Vector2(-r, -r),
			at + Vector2(r, -r),
			at + Vector2(r, r * 0.5),
			at + Vector2(-r, r * 0.5)
		]
	)


func _draw_thing(th: Dictionary) -> void:
	var at: Vector2 = h._p(th["pos"].x, th["pos"].y)
	draw_thing(h.room, th["kind"], at, h._k, t)
	h._register(
		"thing:%d" % things.find(th), thing_poly(th["kind"], at + Vector2(0, -3 * h._k)), at
	)


func _draw_fall() -> void:
	var u: float = minf(fall["t"], 1.0)
	var from: Vector2 = (
		h._p(MUG_AT.x, MUG_AT.y, 17.0) if fall["kind"] == "mug" else h._p(5.0, 0.55, 17.0)
	)
	var to: Vector2 = h._p(fall["to"].x, fall["to"].y)
	var at := from + (to - from) * Vector2(u, u * u)
	draw_thing(h.room, fall["kind"], at, h._k, t * 8.0)


# small things drawn in code: the pushed mug and pen, a slipper, yarn-free gifts
static func draw_thing(c: CanvasItem, kind: String, at: Vector2, k: int, spin: float) -> void:
	match kind:
		"mug":
			c.draw_rect(Rect2(at + Vector2(-2.5, -5) * k, Vector2(5, 5) * k), Color("e8e4dc"))
			c.draw_rect(Rect2(at + Vector2(-2.5, -5) * k, Vector2(5, 1) * k), Color("3a2a22"))
			c.draw_arc(
				at + Vector2(3, -2.5) * k,
				1.6 * k,
				-1.5,
				1.5,
				6,
				Color("e8e4dc"),
				maxf(1.0, 0.8 * k)
			)
		"pen":
			c.draw_line(
				at + Vector2(-4, 0) * k,
				at + Vector2(4, -1) * k,
				Color("3a6ab0"),
				maxf(1.0, 1.2 * k)
			)
			c.draw_line(
				at + Vector2(4, -1) * k,
				at + Vector2(5, -1) * k,
				Color("2a2530"),
				maxf(1.0, 1.2 * k)
			)
		"slipper":
			c.draw_rect(Rect2(at + Vector2(-5, -3) * k, Vector2(10, 4) * k), Color("a8605a"))
			c.draw_rect(Rect2(at + Vector2(-5, -3) * k, Vector2(4, 4) * k), Color("c8786f"))
			c.draw_rect(Rect2(at + Vector2(-5, 0) * k, Vector2(10, 1) * k), Color("6b3b36"))
		"crumple":
			Props.paper_ball(c, at + Vector2(0, -2 * k), k, 0.7, 1.1)


# a click on a thing lying on the floor puts it away
func take(i: int) -> void:
	if i >= 0 and i < things.size():
		var th: Dictionary = things[i]
		things.remove_at(i)
		_put_back(th)
		h.sound.request("rustle")


func _put_back(th: Dictionary) -> void:
	if th.get("back", "") == "mug":
		mug_off = false
	elif th.get("back", "") == "pen":
		pen_off = false


func furn_click(name: String) -> void:
	match name:
		"piano":
			h.hearth.piano_click()
		"fireplace":
			h.hearth.toggle()


func draw_over(bounds: Rect2) -> void:
	laser_draw(bounds)


func draw_desk() -> void:
	if not mug_off:
		draw_thing(h.room, "mug", h._p(MUG_AT.x, MUG_AT.y, 17.0), h._k, 0.0)
	if not pen_off:
		draw_thing(h.room, "pen", h._p(5.0, 0.55, 17.0), h._k, 0.0)


# a key at home: M is the speaker; the rest are words and the old code (see `secrets.gd`)
func key(code: int) -> bool:
	if code == KEY_M:
		h.sound.toggle()
		return true
	if code == KEY_MINUS or code == KEY_EQUAL:
		h.sound.nudge(-0.1 if code == KEY_MINUS else 0.1)
		return true
	return h.secrets.key(code)


# staged on demand: things that need no scene of their own
func _quick(name: String) -> void:
	match name:
		"flop":
			_do_flop(h.pets.critter("argos"))
		"sulk":
			_do_sulk(h.pets.critter("nina"))
		"box":
			if piece("crate").is_empty():
				h.layout.pieces.append({"p": "crate", "f": "", "c": 6, "r": 4})
				h.apply_layout()
			_box()
		"piano":
			h.hearth.piano_click()
		"fire":
			h.hearth.manual = 1
		"mouse":
			h.finds.start_mouse()
		"book":
			h.finds.pick_book()
			h.card.open("book", "furn:bookshelf")
		"globe":
			h.finds.shake = 4.0
		"found":
			h.card.open("found", "mousehole")
		"disco":
			h.secrets.start_disco()
		"tlon", "uqbar", "argos", "borges":
			h.secrets.word(name)
		"spin", "pencil", "stretch", "nod", "cast", "bow", "salute", "visitor":
			h.quirks.force(name)
		"moth":
			h.delights.start_moth()
		"rainwatch":
			h.delights.rain_watch()
		"storm":
			h.delights.storm_hide()
		"jarfull":
			h.delights.jar_spark = 6.0
			h.pets.critter("argos").hops = 4
		"newlook":
			h.delights.new_look()
		"fireworks":
			firework_forced = true
		_:
			h.outside.start(name)
