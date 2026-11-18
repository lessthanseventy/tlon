extends RefCounted

# The things in the pets' corner that the pets use: two bowls, a litter box and a scratching post
# for a cat, a blanket for a pig, boar or bear, a bone for a dog, wolf or fox, hay for the farm
# animals. Bowls, box, post, blanket and bone are drawn in code; the hay bale is the farm pack's
# and stands as a lent piece (`layout.guests`), so it blocks its cell like furniture. None of it
# is saved or movable; a thing whose cell is taken by the owner's furniture is not there.
const Pets := preload("res://pets.gd")
const Props := preload("res://props.gd")

const FOOD := Vector2i(7, 7)
const WATER := Vector2i(5, 7)
const LITTER := Vector2i(7, 5)
const POST := Vector2i(5, 5)
const MAT := Vector2i(7, 6)
const HAY := Vector2i(5, 6)
const HAY_PIECE := "farm.hay_round"
const BONE_KINDS := ["dog", "wolf", "fox"]
const MAT_KINDS := ["pig", "boar", "bear"]
const HAY_KINDS := ["cow", "horse", "sheep", "deer", "rabbit", "chicken"]
const SWITCH := {"litter": "litter_box", "bowls": "bowls", "things": "pet_things"}
const INK := Color("2a2530")

var level := {"food": 1.0, "water": 1.0}
var rng := RandomNumberGenerator.new()
var litter_wait := 0.0
var visits := 0

var _hw: WeakRef
var h:
	get:
		return _hw.get_ref()
var _t := 0.0
var _was_litter := {}
var _flicks: Array = []
var _pour := {}


func setup(home) -> void:
	_hw = weakref(home)
	rng.seed = home.eggs.rng.randi()
	litter_wait = rng.randf_range(120.0, 400.0)
	for name in ["litter", "post", "bone", "mat"]:
		home.eggs.spot(name, _spot(name))
	home.eggs.spot("water", {"cell": Vector2i(6, 7), "face": 3, "eat": true})


func on(key: String) -> bool:
	return bool(h.settings.value(SWITCH[key]))


func _has(kinds: Array) -> bool:
	return h.pets.species_here().any(func(s): return s in kinds)


func has_litter() -> bool:
	return on("litter") and _has(["cat"]) and _free(LITTER)


func has_post() -> bool:
	return on("things") and _has(["cat"]) and _free(POST)


func has_mat() -> bool:
	return on("things") and (_has(MAT_KINDS) or _has(BONE_KINDS)) and _free(MAT)


func has_hay() -> bool:
	return (
		on("things")
		and _has(HAY_KINDS)
		and h.layout.art
		and not h.layout.entry(HAY_PIECE).is_empty()
	)


# the cell is not the owner's furniture (the pets' corner itself never holds any)
func _free(cell: Vector2i) -> bool:
	for p in h.layout.pieces:
		if h.layout.kind(p) in ["rug", "wall"]:
			continue
		if h.layout.rect(p).has_point(cell):
			return false
	return true


# what the lent pieces need to be: the guests are chosen again when this changes
func sig() -> Array:
	return [has_hay()]


func pieces() -> Array:
	return [{"p": HAY_PIECE, "f": "", "c": HAY.x, "r": HAY.y, "fixed": true}] if has_hay() else []


func _hay() -> Dictionary:
	for p in h.layout.guests:
		if p["p"] == HAY_PIECE:
			return p
	return {}


# [spot, weight, mode, seconds] the pet may pick next, besides what its own habits give it
func options(c) -> Array:
	var out: Array = []
	if c.away:
		return out
	var sp: String = c.species
	if on("bowls"):
		out.append(["bowl", 0.7, "sit", rng.randf_range(5, 8)])
		out.append(["water", 0.5, "sit", rng.randf_range(4, 6)])
	if has_litter() and litter_wait <= 0.0 and sp == "cat" and _reach(c, "litter"):
		out.append(["litter", 2.0, "sit", rng.randf_range(4.5, 6.5)])
	if has_post() and sp == "cat" and _reach(c, "post"):
		out.append(["post", 0.6, "sit", rng.randf_range(3, 5)])
	if has_mat() and _reach(c, "mat"):
		if sp in BONE_KINDS:
			out.append(["bone", 0.8, "sit", rng.randf_range(6, 10)])
		if sp in MAT_KINDS:
			out.append(["mat", 1.0, "sleep", rng.randf_range(25, 50)])
	var hay := _hay()
	if not hay.is_empty() and sp in HAY_KINDS:
		var name := ""
		if sp == "chicken":
			name = h.eggs.perch("hay_top", hay, 0.85)
		else:
			var cell: Vector2i = h.eggs.front_cell(hay)
			if cell.x >= 0:
				var d := Vector2(HAY) + Vector2(0.5, 0.5) - Vector2(cell) - Vector2(0.5, 0.5)
				name = h.eggs.spot(
					"hay_eat", {"cell": cell, "face": h.pets._face(d, 7), "eat": true}
				)
		if name != "":
			out.append([name, 1.0, "sleep" if sp == "chicken" else "sit", rng.randf_range(8, 16)])
	return out


# registers the spot and says whether the pet can get to it
func _reach(c, name: String) -> bool:
	var cell: Vector2i = _spot(name)["cell"]
	return not h.pets._blocked(cell) and not h.pets.route(h.pets._cell_of(c.pos), cell).is_empty()


func _spot(name: String) -> Dictionary:
	return {
		"litter": {"cell": LITTER, "face": 1, "use": "litter"},
		"post": {"cell": Vector2i(6, 5), "face": 3, "use": "post"},
		"bone": {"cell": MAT, "face": 1, "use": "bone"},
		"mat": {"cell": MAT, "face": 1},
	}[name]


func process(dt: float) -> void:
	_t += dt
	litter_wait = maxf(0.0, litter_wait - dt)
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


func fill(which: String) -> void:
	level[which] = 1.0
	_pour = {"which": which, "t": 0.0}
	h.sound.request("clink")


func click(key: String) -> bool:
	if key.begins_with("bowl:"):
		fill(key.substr(5))
		return true
	return false


func draw_floor() -> void:
	if on("bowls"):
		_bowl("food", FOOD, Color("c9a86a"))
		_bowl("water", WATER, Color("7fb8e0"))
	if has_mat():
		_mat()


func _bowl(which: String, cell: Vector2i, fill_col: Color) -> void:
	var x := cell.x + 0.5
	var y := cell.y + 0.5
	var room: Control = h.room
	room.draw_colored_polygon(h._ellipse(x, y, 6.0, 3.0), Color("4a5a78"))
	room.draw_colored_polygon(h._ellipse(x, y, 4.6, 2.2, 1.0), Color("8aa0c8"))
	var lv: float = level[which]
	if lv > 0.05:
		room.draw_colored_polygon(h._ellipse(x, y, 1.0 + 2.6 * lv, 0.5 + 1.2 * lv, 1.5), fill_col)
		if which == "water":
			room.draw_colored_polygon(
				h._ellipse(x - 0.5, y - 0.2, 1.0 * lv, 0.4 * lv, 1.7), Color(1, 1, 1, 0.5)
			)
	if not _pour.is_empty() and _pour["which"] == which:
		var u: float = _pour["t"] / 0.9
		for i in 4:
			var at: Vector2 = h._p(x + (i - 1.5) * 0.12, y, 6.0 + 10.0 * u - i * 2.0)
			room.draw_circle(at, 1.2 * h._k, Color(fill_col, 1.0 - u))
	var q: PackedVector2Array = h._ellipse(x, y, 6.0, 3.0)
	h._register("bowl:" + which, q, h._p(x, y))


func _mat() -> void:
	var x := MAT.x + 0.5
	var y := MAT.y + 0.5
	var pts := PackedVector2Array(
		[
			h._p(x - 0.42, y - 0.42, 0.5),
			h._p(x + 0.42, y - 0.42, 0.5),
			h._p(x + 0.42, y + 0.42, 0.5),
			h._p(x - 0.42, y + 0.42, 0.5)
		]
	)
	h.room.draw_colored_polygon(pts, Color("8f6f9f"))
	h.room.draw_polyline(
		PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]),
		Color("6c4f7c"),
		maxf(1.0, h._k)
	)
	h.room.draw_line(
		h._p(x - 0.42, y, 0.5), h._p(x + 0.42, y, 0.5), Color("b79ac4"), maxf(1.0, h._k)
	)
	if _has(BONE_KINDS):
		var a: Vector2 = h._p(x - 0.15, y + 0.1, 1.0)
		var b: Vector2 = h._p(x + 0.15, y - 0.1, 1.0)
		h.room.draw_line(a, b, Color("f1e9dc"), 2.0 * h._k)
		for end in [a, b]:
			h.room.draw_circle(end + Vector2(0, -h._k * 0.6), 1.5 * h._k, Color("f1e9dc"))
			h.room.draw_circle(end + Vector2(0, h._k * 0.6), 1.5 * h._k, Color("f1e9dc"))


func items() -> Array:
	var out: Array = []
	if has_litter():
		var k := float(LITTER.x + LITTER.y) + 1.0
		out.append({"key": k - 1.5, "pri": 1.9, "fn": _litter_back})
		out.append({"key": k - 0.4, "pri": 2.2, "fn": _litter_front})
	if has_post():
		out.append({"key": float(POST.x + POST.y) + 0.9, "pri": 1.9, "fn": _post})
	return out


func _corners(cell: Vector2i, z: float) -> Array:
	var x := cell.x + 0.5
	var y := cell.y + 0.5
	var r := 0.4
	return [
		h._p(x - r, y - r, z), h._p(x + r, y - r, z), h._p(x + r, y + r, z), h._p(x - r, y + r, z)
	]


func _wall(a: Vector2, b: Vector2, rise: float, col: Color) -> void:
	var up := Vector2(0, -rise * h._k)
	h.room.draw_colored_polygon(PackedVector2Array([a, b, b + up, a + up]), col)


func _litter_back() -> void:
	var low := _corners(LITTER, 0.0)
	_wall(low[0], low[1], 6.0, Color("a8c4d8"))
	_wall(low[0], low[3], 6.0, Color("8fb0c8"))
	h.room.draw_colored_polygon(PackedVector2Array(_corners(LITTER, 4.0)), Color("e4d3a8"))
	for i in 5:
		var at: Vector2 = h._p(LITTER.x + 0.3 + 0.09 * i, LITTER.y + 0.35 + 0.07 * (i % 3), 4.5)
		h.room.draw_rect(Rect2(at, Vector2(h._k, h._k)), Color("c4b088"))
	for f in _flicks:
		var u: float = f["t"] / 0.5
		var at: Vector2 = h._p(
			LITTER.x + 0.5 + f["dx"], LITTER.y + 0.5, 6.0 + 9.0 * f["u"] * sin(PI * u)
		)
		h.room.draw_rect(Rect2(at, Vector2(h._k, h._k)), Color("e4d3a8", 1.0 - u))


func _litter_front() -> void:
	var low := _corners(LITTER, 0.0)
	_wall(low[3], low[2], 6.0, Color("c4dcea"))
	_wall(low[1], low[2], 6.0, Color("9fbfd4"))
	var top := _corners(LITTER, 6.0)
	h.room.draw_polyline(PackedVector2Array([top[3], top[2], top[1]]), INK, maxf(1.0, h._k * 0.8))


func _post() -> void:
	var c: Vector2 = h._p(POST.x + 0.5, POST.y + 0.5)
	h.room.draw_colored_polygon(PackedVector2Array(_corners(POST, 2.0)), Color("8a6a4a"))
	h.room.draw_rect(Rect2(c + Vector2(-1.5, -22.0) * h._k, Vector2(3, 20) * h._k), Color("c9a86a"))
	for i in 5:
		h.room.draw_rect(
			Rect2(c + Vector2(-1.5, -20.0 + i * 4.0) * h._k, Vector2(3, 1) * h._k), Color("a8845a")
		)
	h.room.draw_rect(Rect2(c + Vector2(-5, -25.0) * h._k, Vector2(10, 3) * h._k), Color("a8605a"))
