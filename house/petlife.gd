extends RefCounted

# What the pets use: bowls, beds, a litter box, a post and a tower, toys, a perch and a nest, hay,
# a trough, a pool, a log. Each is a layout piece named `pet.<key>` (`pet_things.gd` says what it
# is and draws it; `layout.gd` keeps it like furniture, saved and movable). This file puts them
# out when an animal that uses them lives here, hides them when it does not or a master switch is
# off, registers where a pet goes for each and what it does there.
const Pets := preload("res://pets.gd")
const PetThings := preload("res://pet_things.gd")

# where a thing is first put before the open floor along the front edges and the walls; the rest of
# the things go by the rule in `_default`
const PLACES := {"window_perch": [Vector2i(1, 5)]}
# where the first rule put the things in the 10x10 room, to tell one it placed from one he moved
const OLD_SIZE := 10
const OLD_PLACES := {
	"litter": [Vector2i(1, 1)],
	"bowls": [Vector2i(5, 1)],
	"post": [Vector2i(9, 6)],
	"tower": [Vector2i(9, 4)],
	"bone": [Vector2i(1, 8)],
	"blanket": [Vector2i(1, 8)],
	"bed_round": [Vector2i(1, 9)],
	"bed_cushion": [Vector2i(9, 8)],
	"window_perch": [Vector2i(1, 5)],
}
# a new thing is put this many cells from the others when the room has such a place
const APART := 3
# what a pet may say on arriving at the thing that is its own, now and then
const THING_LINES := {
	"kennel": ["my house. it has a roof.", "i live here. it's small and perfect."],
	"howl": ["a good rock. the moon agrees.", "i have notes for the moon."],
	"den": ["a hole of my own. wonderful.", "nobody knows this place. you do. fine."],
	"apples": ["one for now. one for later.", "i'm only checking they're fresh."],
	"pail": ["the bell is mine too.", "milk is grass, taking its time."],
	"basket": ["soft. i helped.", "wool, mostly mine."],
	"stump": ["a good stump. mossy.", "i stand here. it's enough."],
	"window_perch": ["the street is on. i'm watching.", "birds, officially."],
}
const HAY_PIECE := "farm.hay_round"
const NIGHT_HOME := {
	"nina": ["roost", "hutch", "bed_cushion", "bed", "kennel"],
	"argos": ["roost", "hutch", "bed", "bed_cushion", "kennel"],
}

var level := {"food": 1.0, "water": 1.0}
var rng := RandomNumberGenerator.new()
var litter_wait := 0.0
var visits := 0
# the chance a pet says a line on arriving at its thing, and the seconds before it may again
var thing_say := 0.35

var _hw: WeakRef
var h:
	get:
		return _hw.get_ref()
var _t := 0.0
var _was_litter := {}
var _at := {}
var _hush := {}
var _flicks: Array = []
var _pour := {}
var _sing := 0.0
var _stamp: Array = []
var _spots := {}


func setup(home) -> void:
	_hw = weakref(home)
	rng.seed = home.eggs.rng.randi()
	litter_wait = rng.randf_range(120.0, 400.0)


func on(key: String) -> bool:
	return bool(h.settings.value(PetThings.SWITCH[key]))


# a thing is out when its master switch is on and an animal that uses it lives here, or the
# owner put it there by hand for none
func shown(key: String, own: bool = false) -> bool:
	var t: Dictionary = PetThings.THINGS[key]
	if not on(t["sw"]) or (t.get("art", false) and not h.layout.index.has(HAY_PIECE)):
		return false
	return own or PetThings.fits(key, h.pets.species_here())


# the live piece of a thing, or an empty one
func piece(key: String) -> Dictionary:
	for p in h.layout.pet_pieces():
		if PetThings.key_of(p) == key:
			return p
	return {}


func has(key: String) -> bool:
	sync()
	return not piece(key).is_empty()


func has_litter() -> bool:
	return has("litter")


func has_post() -> bool:
	return has("post")


func has_hay() -> bool:
	return has("hay")


# what the lent pieces need to be (the hay is a pet piece: none are lent)
func sig() -> Array:
	return []


func pieces() -> Array:
	return []


# whether the pets tab lists a thing: what the animals here use, or all of them
func listed(key: String, everyone: bool) -> bool:
	return everyone or PetThings.fits(key, h.pets.species_here()) or not _any(key).is_empty()


# the piece of a thing the catalogue names (`pet.key`), standing or hidden, or an empty one
func out(entry_key: String) -> Dictionary:
	return _any(entry_key.trim_prefix(PetThings.PREFIX)) if entry_key.begins_with(PetThings.PREFIX) else {}


func hay(p: Dictionary) -> bool:
	return PetThings.is_pet(p) and PetThings.key_of(p) == "hay"


func _any(key: String) -> Dictionary:

	for p in h.layout.pieces:
		if p["p"] == PetThings.PREFIX + key:
			return p
	return {}


func sync() -> void:
	if _stamp == _stamp_now():
		return
	var changed := false
	var back: Array = []
	for p in h.layout.pieces:
		if not PetThings.is_pet(p):
			continue
		var out := shown(PetThings.key_of(p), p.get("own", false))
		if out and p.get("hide", false):
			back.append(p)
		elif not out and not p.get("hide", false):
			p["hide"] = true
			changed = true
	for p in back:
		p.erase("hide")
		changed = true
		if h.layout.check(p, p, h.busy_cells()) != "" and not _relocate(p):
			p["hide"] = true
	changed = _replace_old() or changed
	changed = _put_out() or changed
	if changed:
		h.layout.version += 1
		h.apply_layout()
	_stamp = _stamp_now()
	_register()


func _stamp_now() -> Array:
	return [
		h.pets.species_here(),
		on("litter"),
		on("bowls"),
		on("things"),
		h.layout.version,
		h.layout.art,
	]


# the things nobody has put out yet and an animal here uses, once each, the tallest first
func _put_out() -> bool:
	var did := false
	var keys: Array = PetThings.THINGS.keys()
	keys.sort_custom(func(a, b): return PetThings.THINGS[a]["h"] > PetThings.THINGS[b]["h"])
	for key in keys:
		if not PetThings.THINGS[key]["def"] or key in h.layout.pets_seen or not shown(key):
			continue
		if not _any(key).is_empty():
			h.layout.pets_seen.append(key)
			continue
		var p := _default(key)
		if p.is_empty():
			continue
		h.layout.pieces.append(p)
		h.layout.pets_seen.append(key)
		did = true
	return did


# the things the first rule put out that are still where it put them are put again by this one;
# what he moved stays
func _replace_old() -> bool:
	if not h.layout.old_things:
		return false
	h.layout.old_things = false
	var unmoved: Array = []
	for p in h.layout.pieces:
		if PetThings.is_pet(p) and not p.get("own", false):
			if _old_pick(PetThings.key_of(p), p) == Vector2i(p["c"], p["r"]):
				unmoved.append(p)
	var did := false
	for p in unmoved:
		did = _relocate(p) or did
	return did


# where the first rule would put a thing: its own places, then the cells against a wall of the
# 10x10 room, nearest first
func _old_pick(key: String, skip: Dictionary) -> Vector2i:
	for cell in OLD_PLACES.get(key, []) + _edge_cells(OLD_SIZE):
		var p := {"p": PetThings.PREFIX + key, "f": _face_of(key), "c": cell.x, "r": cell.y}
		if h.layout.check(p, skip, h.busy_cells()) == "":
			return cell
	return Vector2i(-1, -1)


func _relocate(p: Dictionary) -> bool:
	var q := _default(PetThings.key_of(p), p)
	if q.is_empty():
		return false
	p["f"] = q["f"]
	p["c"] = q["c"]
	p["r"] = q["r"]
	return true


func _face_of(key: String) -> String:
	var faces: Array = PetThings.THINGS[key]["faces"]
	return faces[0] if not faces.is_empty() else ""


# the first cell for a thing that can hold it, never in front of a piece or at a spot, on no other
# thing (hidden ones too), and as far from the others as the room allows: 2 cells from any thing or
# piece, and `APART` from the things with some height for a thing with some
func _default(key: String, skip: Variant = null) -> Dictionary:
	var wall_mount: bool = key == "window_perch"
	var clear: Dictionary = {} if wall_mount else h.layout.in_front()
	var tall: bool = PetThings.THINGS[key]["h"] > 0
	var others: Array = []
	var raised: Array = []
	var pieces: Array = []
	for o in h.layout.all():
		if not PetThings.is_pet(o):
			if h.layout.kind(o) in ["floor", "hug"]:
				var r: Rect2i = h.layout.rect(o)
				for x in range(r.position.x, r.end.x):
					for y in range(r.position.y, r.end.y):
						pieces.append(Vector2i(x, y))
		elif not is_same(o, skip):
			others.append(Vector2i(o["c"], o["r"]))
			if PetThings.THINGS[PetThings.key_of(o)]["h"] > 0:
				raised.append(Vector2i(o["c"], o["r"]))
	for o in h.layout.pieces:
		if o.get("hide", false) and PetThings.is_pet(o) and not is_same(o, skip):
			others.append(Vector2i(o["c"], o["r"]))
	var cells: Array = PLACES.get(key, []) + _wall_cells()
	var fits := {}
	var gaps: Array = [[0, 1, false]]
	if not wall_mount:
		gaps = [[APART, 2, true], [2, 2, true], [0, 1, false]] if tall else [[0, 2, true], [0, 1, false]]
	for gap in gaps:
		var near: Array = others + pieces if gap[2] else others
		for cell in cells:
			if clear.has(cell) or _gap(cell, near) < gap[1]:
				continue
			if tall and _gap(cell, raised) < gap[0]:
				continue
			if not fits.has(cell):
				var p := {"p": PetThings.PREFIX + key, "f": _face_of(key), "c": cell.x, "r": cell.y}
				fits[cell] = p if h.layout.check(p, skip, h.busy_cells()) == "" else {}
			if not fits[cell].is_empty():
				return fits[cell]
	return {}


func _gap(cell: Vector2i, others: Array) -> int:
	var out := 99
	for o in others:
		out = mini(out, maxi(absi(cell.x - o.x), absi(cell.y - o.y)))
	return out


# the open floor along the two front edges first, from the corner out, one edge then the other,
# then the cells against a wall
func _wall_cells() -> Array:
	var out: Array = []
	for k in Pets.ROWS - 1:
		out.append(Vector2i(Pets.COLS - 1, Pets.ROWS - 1 - k))
		if k > 0:
			out.append(Vector2i(Pets.COLS - 1 - k, Pets.ROWS - 1))
	for cell in _edge_cells(Pets.COLS):
		if cell not in out:
			out.append(cell)
	return out


# the walkable cells of a room `size` square that are against a wall, nearest first
func _edge_cells(size: int) -> Array:
	var out: Array = []
	var rects := _wall_rects()
	for x in range(1, size):
		for y in range(1, size):
			var cell := Vector2i(x, y)
			if _against(cell, rects, size) and not h.layout.PETS_CORNER.has_point(cell):
				out.append(cell)
	out.sort_custom(func(a, b): return mini(a.x, a.y) < mini(b.x, b.y))
	return out


# a wall or the room's edge on one side, or beside a piece that stands against one
func wall_side(cell: Vector2i) -> bool:
	return _against(cell, _wall_rects(), Pets.COLS)


# the floor pieces that stand against a wall
func _wall_rects() -> Array:
	var out: Array = []
	for p in h.layout.all():
		if not PetThings.is_pet(p) and h.layout.kind(p) == "floor":
			var r: Rect2i = h.layout.rect(p)
			if r.position.x <= 1 or r.position.y <= 1:
				out.append(r)
	return out


func _against(cell: Vector2i, rects: Array, size: int) -> bool:
	if cell.x <= 1 or cell.y <= 1 or cell.x >= size - 1 or cell.y >= size - 1:
		return true
	for d in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]:
		for r in rects:
			if r.has_point(cell + d):
				return true
	return false


func _front(p: Dictionary) -> Dictionary:
	var cell: Vector2i = h.eggs.front_cell(p)
	if cell.x < 0:
		return {}
	var d := Vector2(p["c"] - cell.x, p["r"] - cell.y)
	return {"cell": cell, "face": h.pets._face(d, 7)}


func _perch(p: Dictionary, at: Vector3, bonus: float, extra: Dictionary = {}) -> Dictionary:
	var front := _front(p)
	if front.is_empty():
		return {}
	var flip: bool = p["f"] == "se"
	var out := {
		"cell": front["cell"],
		"perch": Vector2(p["c"] + (at.y if flip else at.x), p["r"] + (at.x if flip else at.y)),
		"z": at.z,
		"key": float(h.layout.draw_key(p)) + bonus,
		"face": front["face"],
	}
	out.merge(extra)
	return out


func _spot(name: String, def: Dictionary) -> void:
	if def.is_empty():
		return
	h.eggs.spot(name, def)
	_spots[name] = true


func _register() -> void:
	_spots = {}
	h.pets.spots["sill"] = Pets.SPOTS["sill"].duplicate()
	var round := piece("bed_round")
	h.pets.spots["bed"]["cell"] = (
		Vector2i(round["c"], round["r"]) if not round.is_empty() else Vector2i(6, 6)
	)
	for p in h.layout.pet_pieces():
		_register_one(p, PetThings.key_of(p))


# where a cat sits on the window perch: on its ledge, or on top of its post
func _perch_seat(p: Dictionary) -> Dictionary:
	var c: int = p["c"]
	var r: int = p["r"]
	var seat := {"cell": Vector2i(c, r), "z": PetThings.PERCH_Z}
	match PetThings.perch_wall(p):
		"nw":
			seat.merge({"perch": Vector2(c - 0.75, r + 0.2), "key": c + r + 0.2, "face": 3})
		"ne":
			seat.merge({"perch": Vector2(c + 0.2, r - 0.75), "key": c + r + 0.2, "face": 5})
		_:
			seat.merge({"perch": Vector2(c + 0.5, r + 0.5), "key": c + r + 0.6, "face": 7})
	return seat


func _register_one(p: Dictionary, key: String) -> void:
	var cell := Vector2i(p["c"], p["r"])
	var front := _front(p)
	match key:
		"bowls":
			_spot("bowl", {"cell": cell, "face": 7, "eat": true})
			_spot("water", {"cell": cell, "face": 3, "eat": true})
		"bed_round":
			_spots["bed"] = true
		"bed_cushion":
			_spot("bed_cushion", {"cell": cell, "face": 5})
		"litter":
			_spot("litter", {"cell": cell, "face": 1, "use": "litter"})
		"post", "log", "balls":
			if not front.is_empty():
				front["use"] = "bone" if key == "balls" else "post"
				_spot(key, front)
		"tower":
			_spot("tower_top", _perch(p, PetThings.TOWER_TOP, 0.6))
			_spot("tower_cube", _perch(p, PetThings.TOWER_CUBE, 0.7))
			_spot("tower_bat", _perch(p, PetThings.TOWER_BAT, 0.6, {"use": "post"}))
		"cardbox", "nest", "hutch", "den":
			_spot(key, {"cell": cell, "face": 5 if key == "hutch" else 1})
		"kennel", "pail", "basket", "stump":
			_spot(key, front)
		"howl":
			_spot(key, _perch(p, Vector3(0.5, 0.5, 17.0), 0.6))
		"fish", "rope":
			_spot(key, {"cell": cell, "face": 1, "use": "post"})
		"bone":
			_spot(key, {"cell": cell, "face": 1, "use": "bone"})
		"carrot":
			_spot(key, {"cell": cell, "face": 1, "eat": true})
		"aquarium":
			_spot(key, front)
		"birdcage":
			_spot("cage", front)
		"perch":
			_spot("roost", _perch(p, Vector3(0.5, 0.5, 19.0), 0.6))
		"window_perch":
			var seat := _perch_seat(p)
			_spot(key, seat)
			if PetThings.perch_wall(p) == "nw" and p["r"] in Pets.WINDOW_ROWS:
				_spot("sill", seat)
		"pool":
			_spot(key, {"cell": cell, "face": 3})
		"blanket":
			_spot("mat", {"cell": cell, "face": 1})
		"trough", "salt", "apples":
			if not front.is_empty():
				front["eat"] = true
				_spot(key, front)
		"hay":
			if h.eggs.perch("hay_top", p, 0.85) != "":
				_spots["hay_top"] = true
			if not front.is_empty():
				_spot("hay_eat", {"cell": front["cell"], "face": front["face"], "eat": true})


# [spot, weight, mode, seconds] the pet may pick next, besides what its own habits give it
func options(c) -> Array:
	sync()
	var out: Array = []
	if c.away:
		return out
	var night: bool = h.pets.is_night
	for p in h.layout.pet_pieces():
		var key := PetThings.key_of(p)
		if not PetThings.fits(key, [c.species]):
			continue
		for o in _habits(c, key, night):
			if _spots.has(o[0]) and _reach(c, o[0]):
				out.append(o)
	return out


func _secs(a: float, b: float) -> float:
	return rng.randf_range(a, b)


func _habits(c, key: String, night: bool) -> Array:
	var out: Array = []
	match key:
		"bowls":
			out = [["bowl", 0.7, "sit", _secs(5, 8)], ["water", 0.5, "sit", _secs(4, 6)]]
		"bed_cushion":
			out = [["bed_cushion", 8.0 if night else 1.5, "sleep", _secs(30, 60)]]
		"bed_round":
			out = [["bed", 8.0 if night else 1.5, "sleep", _secs(30, 60)]]
		"litter":
			out = [["litter", 2.0, "sit", _secs(4.5, 6.5)]] if litter_wait <= 0.0 else []
		"tower":
			out = [
				["tower_top", 1.0, "sit", _secs(15, 30)],
				["tower_cube", 5.0 if night else 0.9, "sleep", _secs(25, 45)],
				["tower_bat", 0.7, "sit", _secs(5, 9)],
			]
		"perch":
			out = [["roost", 8.0 if night else 1.0, "sleep" if night else "sit", _secs(25, 50)]]
		"hutch", "den", "kennel":
			out = [[key, 4.0 if night else 1.0, "sleep", _secs(25, 50)]]
		"basket":
			out = [["basket", 1.0, "sleep", _secs(25, 50)]]
		"window_perch":
			out = [
				["window_perch", 0.3 if night else 1.2, "sit" if night else "sleep", _secs(25, 45)]
			]
		"hay":
			out = [["hay_top" if c.species == "chicken" else "hay_eat", 1.0, "sit", _secs(8, 16)]]
		"blanket":
			out = [["mat", 1.0, "sleep", _secs(25, 50)]]
		_:
			out = _plain(key)
	return out.filter(func(o): return _owns(c, key, o[0]))


# the habits that are one stop with one weight
func _plain(key: String) -> Array:
	var rows := {
		"post": [0.6, 3, 5],
		"cardbox": [0.8, 10, 20],
		"fish": [0.5, 3, 5],
		"aquarium": [0.5, 8, 14],
		"bone": [0.8, 6, 10],
		"rope": [0.7, 5, 8],
		"balls": [0.6, 5, 8],
		"nest": [1.0, 10, 20],
		"carrot": [0.8, 4, 7],
		"trough": [0.9, 5, 9],
		"salt": [0.5, 4, 6],
		"pool": [1.0, 15, 30],
		"log": [0.7, 4, 6],
		"howl": [0.7, 6, 10],
		"apples": [0.8, 5, 9],
		"pail": [0.7, 6, 10],
		"stump": [0.6, 8, 14],
	}
	if not rows.has(key):
		return []
	var r: Array = rows[key]
	return [[key, r[0], "sit", _secs(r[1], r[2])]]


# a bed is slept in by the pet it is for; the round one is the second pet's
func _owns(c, key: String, spot: String) -> bool:
	if key == "bed_round" or key == "bed_cushion":
		return _bed_of(c) == spot
	return true


# the bed a pet sleeps in: its own kind first, the other when only that one is out
func _bed_of(c) -> String:
	var order := ["bed_cushion", "bed_round"] if c.id == "nina" else ["bed_round", "bed_cushion"]
	for key in order:
		if not piece(key).is_empty():
			return "bed" if key == "bed_round" else key
	return ""


# where a pet is put for the night, if it has a place of its own
func night_spot(c) -> String:
	sync()
	if c.away:
		return ""
	for name in NIGHT_HOME[c.id]:
		if not _spots.has(name):
			continue
		var bed: bool = name == "bed" or name == "bed_cushion"
		if (bed and _bed_of(c) == name) or (name == "roost" and c.species == "chicken"):
			return name
		if (name == "hutch" and c.species == "rabbit") or (name == "kennel" and c.species == "dog"):
			return name
	return ""


func night_place() -> void:
	for id in ["nina", "argos"]:
		var c = h.pets.critter(id)
		var name := night_spot(c)
		if name != "":
			h.pets.place(c, name, "sleep")


func _reach(c, name: String) -> bool:
	var cell: Vector2i = h.pets.spots[name]["cell"]
	var from: Vector2i = h.pets._cell_of(c.pos)
	return cell == from or (not h.pets._blocked(cell) and not h.pets.route(from, cell).is_empty())


func process(dt: float) -> void:
	sync()
	_t += dt
	litter_wait = maxf(0.0, litter_wait - dt)
	_sing = maxf(0.0, _sing - dt)
	if _spots.has("cage") and _sing <= 0.0 and rng.randf() < dt / 30.0:
		_chirp()
	if not _pour.is_empty():
		_pour["t"] += dt
		if _pour["t"] > 0.9:
			_pour = {}
	for id in ["nina", "argos"]:
		var c = h.pets.critter(id)
		var in_box: bool = not c.away and c.use == "litter" and c.mode == "idle"
		if in_box and not _was_litter.get(id, false):
			visits += 1
			litter_wait = rng.randf_range(420.0, 900.0)
			h.sound.request("rustle")
		_was_litter[id] = in_box
		_arrivals(c, dt)
		if in_box and rng.randf() < dt * 3.0:
			_flicks.append(
				{"t": 0.0, "dx": rng.randf_range(-0.4, 0.4), "u": rng.randf_range(0.5, 1.0)}
			)
		if not c.away and c.anim == "eat" and c.mode == "idle":
			var which := "water" if c.spot == "water" else ("food" if c.spot == "bowl" else "")
			if which != "":
				level[which] = maxf(0.0, level[which] - dt * 0.02)
	for f in _flicks:
		f["t"] += dt
	_flicks = _flicks.filter(func(f): return f["t"] < 0.5)


# the wolf's howl and a pet's line, once on arriving at its thing
func _arrivals(c, dt: float) -> void:
	_hush[c.id] = maxf(0.0, _hush.get(c.id, 0.0) - dt)
	var at := ""
	if not c.away and c.goal == "" and c.jump.is_empty() and c.mode in ["idle", "sleep"]:
		at = c.spot if THING_LINES.has(c.spot) else ""
	if at == _at.get(c.id, ""):
		return
	_at[c.id] = at
	if at == "howl":
		h.sound.request("howl")
	if at != "" and c.say_left <= 0.0 and _hush[c.id] <= 0.0 and rng.randf() < thing_say:
		h.pets.say(c, THING_LINES[at][rng.randi() % 2])
		_hush[c.id] = rng.randf_range(120.0, 300.0)


func fill(which: String) -> void:
	level[which] = 1.0
	_pour = {"which": which, "t": 0.0}
	h.sound.request("clink")


func _chirp() -> void:
	_sing = 1.6
	h.sound.request("squeak")


func click(key: String) -> bool:
	if key.begins_with("bowl:"):
		fill(key.substr(5))
		return true
	if key == "cage":
		_chirp()
		return true
	return false


func size_of(species: String) -> float:
	if species in PetThings.SMALL:
		return 0.8
	return 1.15 if species in PetThings.BIG else 1.0


func _pen(p: Dictionary) -> PetThings.Pen:
	return PetThings.Pen.new(h.room, h._p(p["c"], p["r"]), h._k, PetThings.turned(p))


func _data(key: String) -> Dictionary:
	var d := {"t": _t, "level": level, "flicks": _flicks, "sing": _sing}
	if key == "bed_cushion":
		var who = h.pets.critter("nina")
		if _bed_of(who) != "bed_cushion":
			who = h.pets.critter("argos")
		d["size"] = size_of(who.species)
	return d


# what lies on the floor, before the pets' shadows
func draw_floor() -> void:
	sync()
	var flat: Array = h.layout.pet_pieces().filter(
		func(p): return _on_floor(PetThings.THINGS[PetThings.key_of(p)])
	)
	flat.sort_custom(func(a, b): return a["c"] + a["r"] < b["c"] + b["r"])
	for p in flat:
		var key := PetThings.key_of(p)
		PetThings.draw(_pen(p), key, "", _data(key))
		if key == "bowls":
			_bowls_fx(p)


func _on_floor(t: Dictionary) -> bool:
	return t["mode"] == "flat" and not t.get("raised", false)


func _bowls_fx(p: Dictionary) -> void:
	for i in 2:
		var which := "food" if i == 0 else "water"
		var at := Vector2(0.28, 0.72) if i == 0 else Vector2(0.72, 0.28)
		var x: float = p["c"] + at.x
		var y: float = p["r"] + at.y
		if not _pour.is_empty() and _pour["which"] == which:
			var u: float = _pour["t"] / 0.9
			var tone := Color("c9a86a") if i == 0 else Color("7fb8e0")
			for j in 4:
				var pt: Vector2 = h._p(x + (j - 1.5) * 0.12, y, 6.0 + 10.0 * u - j * 2.0)
				h.room.draw_circle(pt, 1.2 * h._k, Color(tone, 1.0 - u))
		h._register("bowl:" + which, h._ellipse(x, y, 6.0, 3.0), h._p(x, y))


func items() -> Array:
	sync()
	var out: Array = []
	for p in h.layout.pet_pieces():
		var key := PetThings.key_of(p)
		var mode: String = PetThings.THINGS[key]["mode"]
		var k := float(p["c"] + p["r"])
		if mode == "walk":
			out.append({"key": k - 0.5, "pri": 1.9, "fn": _draw.bind(p, "back")})
			out.append({"key": k + 0.6, "pri": 2.2, "fn": _draw.bind(p, "front")})
		elif mode == "solid" or not _on_floor(PetThings.THINGS[key]):
			var at := k + (0.1 if mode == "flat" else 0.0)
			out.append({"key": at, "pri": 1.0, "fn": _draw.bind(p, "")})
			if key == "tower":
				out.append({"key": k + 0.9, "pri": 1.0, "fn": _draw.bind(p, "front")})
	return out


func _draw(p: Dictionary, part: String) -> void:
	var key := PetThings.key_of(p)
	if key == "hay":
		var s: Dictionary = h.room._sprite(HAY_PIECE)
		if not s.is_empty():
			h.room.draw_texture(s["tex"], (h._p(p["c"], p["r"]) - s["anchor"]).round())
		return
	var pen := _pen(p)
	var d := _data(key)
	d["wall"] = PetThings.perch_wall(p)
	PetThings.draw(pen, key, part, d)
	if key == "birdcage":
		var hull := PackedVector2Array(
			[pen.p(0.1, 0.9), pen.p(0.9, 0.9), pen.p(0.9, 0.1), pen.p(0.9, 0.1, 33.0)]
		)
		hull.append_array([pen.p(0.1, 0.1, 33.0), pen.p(0.1, 0.9, 33.0)])
		h._register("cage", hull, pen.p(0.5, 0.5))
