extends RefCounted

# The soak's checks of the pets' things as pieces of the room: put out by themselves, hidden with
# their animal and their switch, movable and followed by the pets, saved, migrated from an old
# layout, never on another piece, against a wall.
const Pets := preload("res://pets.gd")
const PetThings := preload("res://pet_things.gd")
const Decorate := preload("res://decorate.gd")

const SIGNATURE := {
	"dog": "kennel",
	"wolf": "howl",
	"fox": "den",
	"horse": "apples",
	"cow": "pail",
	"sheep": "basket",
	"deer": "stump",
}

# the default furniture of the 10x10 room
const OLD_ROWS := [
	["plant_small", "", 0, 0],
	["armchair", "se", 0, 1],
	["rug_blue", "nwse", 1, 4],
	["painting", "ne", 0, 0],
	["clock", "ne", 7, 0],
	["painting", "nw", 0, 6],
	["fireplace", "ne", 8, 0],
	["bookshelf", "sw", 9, 0],
	["rug_red", "nesw", 8, 1],
	["armchair", "ne", 8, 2],
	["side_table", "", 9, 2],
	["piano", "se", 0, 8],
	["wall_shelf", "nw", 0, 8],
	["mirror", "nw", 0, 9],
	["rug_round", "", 3, 8],
	["dining_table", "nwse", 3, 8],
	["dining_chair", "ne", 3, 9],
	["dining_chair", "ne", 4, 9],
	["plant_small", "", 9, 9],
]
var s
var _tmp: DirAccess


func _init(soak) -> void:
	s = soak


func run() -> void:
	_tmp = DirAccess.create_temp("house-petthings-soak")
	_defaults()
	_combos()
	_species()
	_switches()
	_moved()
	_window()
	await _cage()
	_decorating()
	_pointer()
	_migration()
	_old_room()
	_replaced()
	_night()
	_quiet()
	await _drawn()


func _home(seed_value: int, pet1: String, pet2: String) -> Control:
	var room: Control = s._room(seed_value)
	var h = room.home
	h.fake_hour = 14.0
	h.fake_day = "06-15"
	h.set_data(s._data([s._thing(1, 1.0)], 0))
	h._env = h._env_now()
	h.settings.put("pet1", pet1)
	h.settings.put("pet2", pet2)
	h.petlife.sync()
	return room


func _cell(p: Dictionary) -> Vector2i:
	return Vector2i(p["c"], p["r"])


# no piece shares a cell with another, solid things block and flat ones do not, and nobody
# stands inside a blocked cell
func _sound(h, what: String) -> void:
	h.apply_layout()
	h.petlife.sync()
	var l = h.layout
	var all: Array = l.all().filter(func(p): return l.kind(p) not in ["rug", "wall"])
	for i in all.size():
		for j in range(i + 1, all.size()):
			if l.rect(all[i]).intersects(l.rect(all[j])):
				s._check(false, "%s: %s and %s share a cell" % [what, all[i]["p"], all[j]["p"]])
	for p in l.pieces:
		if PetThings.is_pet(p) and p.get("hide", false):
			s._check(
				not h.pets.blocked_cells.has(_cell(p)), "%s: hidden %s blocks" % [what, p["p"]]
			)
	for p in l.pet_pieces():
		var solid: bool = l.kind(p) == "floor"
		s._check(
			h.pets.blocked_cells.has(_cell(p)) == solid,
			"%s: %s blocks as it should" % [what, p["p"]]
		)
	s._check(l.reaches(h.pets.blocked_cells, h.busy_cells()), "%s: every spot reachable" % what)


func _keys(h) -> Array:
	return h.layout.pet_pieces().map(func(p): return PetThings.key_of(p))


func _wall_sides(h, what: String) -> void:
	for p in h.layout.pet_pieces():
		s._check(
			h.petlife.wall_side(_cell(p)),
			"%s: %s at %s is against a wall" % [what, p["p"], _cell(p)]
		)


# a cat and a dog: what each uses is out, against the walls, nothing else
func _defaults() -> void:
	var room := _home(80, "cat_grey", "dog_golden")
	var h = room.home
	var keys := _keys(h)
	keys.sort()
	var want := [
		"bed_cushion", "bed_round", "bone", "bowls", "kennel", "litter", "post", "tower", "window_perch"
	]
	s._check(keys == want, "a cat and a dog get their things: %s" % [keys])
	_sound(h, "cat and dog")
	_wall_sides(h, "cat and dog")
	_in_front(h, "cat and dog")
	for key in h.petlife.THING_LINES:
		var lines: Array = h.petlife.THING_LINES[key]
		s._check(PetThings.THINGS.has(key) and lines.size() == 2, "%s has two lines" % key)
		for text in lines:
			s._check(text == text.to_lower() and text.length() <= 40, "a short lowercase line: %s" % text)
	for key in ["cardbox", "fish", "aquarium", "rope", "balls"]:
		s._check(h.petlife.piece(key).is_empty(), "%s waits in the pets tab" % key)
	var tower: Dictionary = h.petlife.piece("tower")
	s._check(tower["f"] in ["sw", "se"] and not tower.has("own"), "the tower is put out for a cat")
	for p in h.layout.pet_pieces():
		var c: Vector2i = _cell(p)
		s._check(
			not (c.x in range(3, 9) and c.y in range(3, 9)),
			"%s is not in the middle of the floor (%s)" % [p["p"], c]
		)
	room.queue_free()


# every species alone, and a farm pair: its things are out, against walls, on nothing
func _combos() -> void:
	var one := {}
	for kind in Pets.KINDS:
		one[Pets.KINDS[kind]["species"]] = kind
	for sp in one:
		var room := _home(81, one[sp], Pets.NONE)
		var h = room.home
		_sound(h, sp)
		_wall_sides(h, sp)
		_in_front(h, sp)
		for key in PetThings.THINGS:
			var t: Dictionary = PetThings.THINGS[key]
			var out: bool = not h.petlife.piece(key).is_empty()
			var wanted: bool = t["def"] and PetThings.fits(key, [sp]) and h.petlife.shown(key)
			s._check(out == wanted, "%s: %s %s" % [sp, key, "out" if out else "not out"])
		for who in SIGNATURE:
			var out: bool = not h.petlife.piece(SIGNATURE[who]).is_empty()
			s._check(out == (who == sp), "%s: the %s is %s" % [sp, SIGNATURE[who], out])
		if SIGNATURE.has(sp):
			_visit(h, SIGNATURE[sp])
		if sp == "cat":
			_visit(h, "window_perch")
		room.queue_free()
	for pair in [
		["chicken_white", "cow_holstein"], ["rabbit_white", "pig_pink"], ["bear_black", "deer_doe"]
	]:
		var room := _home(82, pair[0], pair[1])
		_sound(room.home, str(pair))
		_in_front(room.home, str(pair), false)
		_wall_sides(room.home, str(pair))
		room.queue_free()


# the pet sent to a thing's spot ends up there
func _visit(h, key: String) -> void:
	var c = h.pets.critter("nina")
	h.pets.freeze = true
	h.petlife.thing_say = 1.0
	h.sound.requested.clear()
	h.pets.place(c, "rug", "sit")
	c.say_left = 0.0
	h.pets.go(c, key, "sit", 5.0)
	s._run_home(h, 30.0, func(): return c.goal == "" and c.mode not in ["walk", "jump"])
	var cell: Vector2i = h.pets.spots[key]["cell"]
	var there: bool = c.z > 0.0 if h.pets.spots[key].has("perch") else h.pets._cell_of(c.pos) == cell
	s._check(c.spot == key and there, "%s goes to the %s" % [c.species, key])
	s._run_home(h, 0.5)
	var lines: Array = h.petlife.THING_LINES.get(key, [])
	s._check(lines.is_empty() or c.say_text in lines, "%s says a line of the %s (%s)" % [c.species, key, c.say_text])
	var howls: int = h.sound.requested.count("howl")
	s._check(howls == (1 if key == "howl" else 0), "%s: the howl is asked for %d times" % [key, howls])
	s._run_home(h, 3.0)
	s._check(h.sound.requested.count("howl") == howls, "and not again while it stays on the %s" % key)


# a thing goes with its animal and comes back where it was
func _species() -> void:
	var room := _home(83, "cat_grey", "dog_golden")
	var h = room.home
	var tower: Dictionary = h.petlife.piece("tower")
	var at := _cell(tower)
	var face: String = tower["f"]
	h.settings.put("pet1", "rabbit_white")
	h.petlife.sync()
	s._check(
		not h.layout.pet_pieces().any(func(p): return p["p"] == "pet.tower"), "no cat, no tower"
	)
	s._check(tower.get("hide", false), "the tower is hidden, not gone")
	s._check(h.layout.pieces.any(func(p): return is_same(p, tower)), "and stays in the layout")
	s._check(not h.pets.blocked_cells.has(at), "a hidden tower blocks nothing")
	s._check(not h.petlife.piece("hutch").is_empty(), "a rabbit gets its house")
	s._check(not h.petlife.piece("bowls").is_empty(), "bowls stay for anyone")
	_sound(h, "rabbit and dog")
	h.settings.put("pet1", "cat_grey")
	h.petlife.sync()
	var back: Dictionary = h.petlife.piece("tower")
	s._check(
		not back.is_empty() and _cell(back) == at and back["f"] == face,
		"the cat's return brings the tower back where it stood"
	)
	var seen: int = h.layout.pets_seen.count("tower")
	s._check(seen == 1, "the tower is put out once (%d)" % seen)
	h.settings.put("pet1", Pets.NONE)
	h.settings.put("pet2", Pets.NONE)
	h.petlife.sync()
	s._check(h.layout.pet_pieces().is_empty(), "no pets, no things")
	_sound(h, "no pets")
	h.settings.put("pet1", "cat_grey")
	h.settings.put("pet2", "dog_golden")
	h.petlife.sync()
	s._check(_cell(h.petlife.piece("tower")) == at, "both back: the tower is where it was")
	room.queue_free()


# each master switch hides its things and the things come back in place
func _switches() -> void:
	var room := _home(84, "cat_grey", "dog_golden")
	var h = room.home
	var cells := {}
	for p in h.layout.pet_pieces():
		cells[p["p"]] = _cell(p)
	var rows := {
		"litter_box": ["litter"],
		"bowls": ["bowls"],
		"pet_things": ["post", "tower", "bone", "bed_round", "bed_cushion", "window_perch", "kennel"],
	}
	for sw in rows:
		h.settings.put(sw, false)
		h.petlife.sync()
		for key in rows[sw]:
			s._check(h.petlife.piece(key).is_empty(), "%s off hides the %s" % [sw, key])
		var others := _keys(h)
		s._check(others.size() == cells.size() - rows[sw].size(), "%s off hides only its own" % sw)
		_sound(h, sw + " off")
		h.settings.put(sw, true)
		h.petlife.sync()
		for key in rows[sw]:
			var p: Dictionary = h.petlife.piece(key)
			s._check(not p.is_empty() and _cell(p) == cells["pet." + key], "%s is back" % key)
	room.queue_free()


# a moved thing is where the pet goes
func _moved() -> void:
	var room := _home(85, "cat_grey", "dog_golden")
	var h = room.home
	var l = h.layout
	var cat = h.pets.critter("nina")
	var dog = h.pets.critter("argos")
	h.pets.freeze = true
	var to := {"litter": Vector2i(3, 1), "bowls": Vector2i(2, 9), "tower": Vector2i(2, 8)}
	to["bed_round"] = Vector2i(9, 3)
	to["bed_cushion"] = Vector2i(9, 5)
	to["post"] = Vector2i(9, 7)
	to["bone"] = Vector2i(7, 9)
	for key in to:
		var p: Dictionary = h.petlife.piece(key)
		var want := Dictionary(p).duplicate()
		want["c"] = to[key].x
		want["r"] = to[key].y
		var why: String = l.place(want, p, h.busy_cells())
		s._check(why == "", "%s moves to %s (%s)" % [key, to[key], why])
	h.apply_layout()
	h.petlife.sync()
	_sound(h, "moved")
	var spots := {
		"litter": "litter",
		"bowls": "bowl",
		"bed_round": "bed",
		"bed_cushion": "bed_cushion",
		"bone": "bone"
	}
	for key in spots:
		var cell: Vector2i = h.pets.spots[spots[key]]["cell"]
		s._check(cell == to[key], "the %s spot follows its piece to %s (%s)" % [key, to[key], cell])
	var who := {"litter": cat, "bowl": cat, "bone": dog, "bed": dog, "bed_cushion": cat}
	for name in who:
		var c = who[name]
		h.pets.place(c, "rug", "sit")
		h.petlife.litter_wait = 0.0
		h.pets.go(c, name, "sit", 5.0)
		s._run_home(
			h,
			30.0,
			func(): return h.pets._cell_of(c.pos) == h.pets.spots[name]["cell"] and c.mode != "walk"
		)
		s._check(
			h.pets._cell_of(c.pos) == h.pets.spots[name]["cell"],
			"%s goes to %s (%s)" % [c.id, name, h.pets.spots[name]["cell"]]
		)
	h.pets.place(cat, "rug", "sit")
	h.pets.go(cat, "tower_top", "sit", 5.0)
	s._run_home(h, 30.0, func(): return cat.z > 20.0 and cat.mode != "jump")
	s._check(cat.z > 20.0, "the cat climbs the moved tower (z %.0f)" % cat.z)
	s._check(
		Vector2i(floori(cat.pos.x), floori(cat.pos.y)) == to["tower"],
		"and is on it at %s" % [to["tower"]]
	)
	h.pets.place(cat, "rug", "sit")
	h.pets.go(cat, "post", "sit", 5.0)
	s._run_home(h, 30.0, func(): return cat.use == "post")
	s._check(cat.use == "post", "the cat scratches the moved post")
	var next := Vector2(h.pets.spots["post"]["cell"]) - Vector2(to["post"])
	s._check(
		maxf(absf(next.x), absf(next.y)) == 1.0,
		"from the cell beside it (%s, %s)" % [h.pets.spots["post"]["cell"], to["post"]]
	)
	room.queue_free()


# a cat sent to the window sits on the perch; without it the sill is the window's own
func _window() -> void:
	var room := _home(95, "cat_grey", Pets.NONE)
	var h = room.home
	var cat = h.pets.critter("nina")
	var perch: Dictionary = h.petlife.piece("window_perch")
	s._check(_cell(perch) == Vector2i(1, 5), "a cat has its window perch at the sill (%s)" % [perch])
	s._check(h.pets.spots["sill"]["z"] == PetThings.PERCH_Z, "the sill is the perch")
	h.pets.freeze = true
	h.pets.place(cat, "rug", "sit")
	h.pets.go(cat, "sill", "sit", 5.0)
	s._run_home(h, 30.0, func(): return cat.z > 20.0 and cat.mode != "jump")
	s._check(cat.z == PetThings.PERCH_Z and cat.spot == "sill", "a cat sent to the window ends up on it")
	s._check(PetThings.perch_wall(perch) == "nw", "at the window it is a ledge on the north-west wall")
	var sill_own: float = Pets.SPOTS["sill"]["z"]
	var forms := {Vector2i(8, 8): "", Vector2i(5, 1): "ne", Vector2i(1, 2): "nw"}
	for cell in forms:
		var want := Dictionary(perch).duplicate()
		want["c"] = cell.x
		want["r"] = cell.y
		var why: String = h.layout.place(want, perch, h.busy_cells())
		s._check(why == "", "the perch moves to %s (%s)" % [cell, why])
		h.apply_layout()
		h.petlife.sync()
		s._check(PetThings.perch_wall(perch) == forms[cell], "the perch at %s is the %s form" % [cell, forms[cell]])
		s._check(h.pets.spots["sill"]["z"] == sill_own, "away from the window the sill is its own")
		var seat: Dictionary = h.pets.spots["window_perch"]
		s._check(seat["z"] == PetThings.PERCH_Z, "a cat can use the perch at %s" % [cell])
		h.pets.place(cat, "rug", "sit")
		h.pets.go(cat, "window_perch", "sit", 5.0)
		s._run_home(h, 30.0, func(): return cat.z > 20.0 and cat.mode != "jump")
		s._check(cat.z == PetThings.PERCH_Z and cat.spot == "window_perch", "and is on it at %s" % [cell])
	var back := Dictionary(perch).duplicate()
	back["c"] = 1
	back["r"] = 5
	s._check(h.layout.place(back, perch, h.busy_cells()) == "", "the perch goes back to the window")
	h.apply_layout()
	h.petlife.sync()
	s._check(h.pets.spots["sill"]["z"] == PetThings.PERCH_Z, "and is the sill again")
	h.layout.remove(perch)
	h.apply_layout()
	h.petlife.sync()
	s._check(h.pets.spots["sill"]["z"] == Pets.SPOTS["sill"]["z"], "the sill is its own without it")
	room.queue_free()


# a bird cage is not put out by itself; once added it is hit by a click, and a cat goes to watch it
func _cage() -> void:
	var room := _home(96, "cat_grey", "dog_golden")
	room.size = Vector2(800, 700)
	var h = room.home
	var cat = h.pets.critter("nina")
	s._check(h.petlife.piece("birdcage").is_empty(), "no bird cage unless he adds one")
	s._check(not h.antics._need("cage", cat), "and nothing to watch")
	var at: Dictionary = h.petlife._default("birdcage")
	var p := {"p": "pet.birdcage", "f": "", "c": at["c"], "r": at["r"]}
	s._check(h.layout.place(p, null, h.busy_cells()) == "", "a bird cage is added")
	h.apply_layout()
	h.petlife.sync()
	_sound(h, "bird cage")
	s._check(h.pets.spots.has("cage") and h.antics._need("cage", cat), "a cat has the cage to watch")
	h.pets.freeze = true
	h.pets.place(cat, "rug", "idle")
	cat.hold = false
	h.antics.act = {}
	s._check(h.antics.begin("cage_watch", cat, false), "a cat starts to watch it")
	s._check(h.antics.act.get("legs") == ["cage"], "and goes beside it")
	room.queue_redraw()
	for i in 3:
		await s.process_frame
	var hit: Array = h._hits.filter(func(x): return x["key"] == "cage")
	s._check(hit.size() == 1, "the cage is hit (%d of %d hits)" % [hit.size(), h._hits.size()])
	s._check(h.petlife.click("cage") and h.sound.requested.has("squeak"), "a click makes it sing")
	room.queue_free()


# every thing: added, turned, moved, taken out, put out again, and never onto another piece
func _decorating() -> void:
	var room := _home(86, "cat_grey", "dog_golden")
	var h = room.home
	var l = h.layout
	for key in PetThings.THINGS:
		var t: Dictionary = PetThings.THINGS[key]
		var old: Dictionary = h.petlife.piece(key)
		if not old.is_empty():
			l.remove(old)
		h.apply_layout()
		var fits := PetThings.fits(key, h.pets.species_here())
		var p := {"p": PetThings.PREFIX + key, "f": "", "c": 0, "r": 0, "own": not fits}
		if not t["faces"].is_empty():
			p["f"] = t["faces"][0]
		var spot: Dictionary = h.petlife._default(key)
		s._check(not spot.is_empty(), "%s has a free place" % key)
		if spot.is_empty():
			continue
		p["c"] = spot["c"]
		p["r"] = spot["r"]
		s._check(l.place(p, null, h.busy_cells()) == "", "%s is added" % key)
		s._check(l.place(p.duplicate(), null, h.busy_cells()) == l.ONCE, "%s only once" % key)
		h.apply_layout()
		h.petlife.sync()
		s._check(not p.get("hide", false), "%s stands (%s)" % [key, "own" if p["own"] else "fits"])
		if t["faces"].size() > 1:
			var turned := p.duplicate()
			turned["f"] = t["faces"][1]
			s._check(
				l.place(turned, p, h.busy_cells()) == "" and p["f"] == t["faces"][1],
				"%s turns" % key
			)
		var moved: Dictionary = h.petlife._default(key, p)
		var from := _cell(p)
		for cell in h.petlife._wall_cells():
			var q := {"p": p["p"], "f": p["f"], "c": cell.x, "r": cell.y}
			if cell != from and l.place(q, p, h.busy_cells()) == "":
				break
		s._check(_cell(p) != from or not moved.is_empty(), "%s moves" % key)
		_sound(h, "decorating " + key)
		l.remove(p)
		h.apply_layout()
		s._check(h.petlife.piece(key).is_empty(), "%s comes out" % key)
		s._check(l.place(p.duplicate(), null, h.busy_cells()) == "", "%s goes in again" % key)
		h.apply_layout()
		h.petlife.sync()
		s._check(not h.petlife.piece(key).is_empty(), "%s stands again" % key)
		for o in l.all():
			if l.kind(o) in ["rug", "wall"] or PetThings.is_pet(o):
				continue
			var onto := {"p": p["p"], "f": p["f"], "c": o["c"], "r": o["r"]}
			s._check(
				l.check(onto, p, h.busy_cells()) != "",
				"%s is refused on %s at %s" % [key, o["p"], _cell(o)]
			)
		l.remove(h.petlife.piece(key))
		h.apply_layout()
	_sound(h, "every thing out")
	room.queue_free()


# the pointer: the pets tab, the filter, a click puts a thing down, a click picks it up
func _pointer() -> void:
	var room := _home(87, "cat_grey", "dog_golden")
	room.size = Vector2(800, 700)
	room._k = 2
	room._origin = Vector2(400, 150)
	var h = room.home
	var deco: Control = Decorate.new()
	deco.room = room
	deco.home = h
	deco.enter()
	s._check("pets" in h.layout.tabs, "the catalogue has a pets tab")
	var fitted: Array = h.layout.catalogue.filter(
		func(e): return e["tab"] == "pets" and deco._listed(e)
	)
	deco.everyone = true
	var every: Array = h.layout.catalogue.filter(
		func(e): return e["tab"] == "pets" and deco._listed(e)
	)
	s._check(
		fitted.size() < every.size() and every.size() == PetThings.THINGS.size(),
		"the tab lists what fits (%d), all animals lists all (%d)" % [fitted.size(), every.size()]
	)
	deco.everyone = false
	deco._act("tab:pets")
	var cell := func(c: float, r: float) -> Vector2: return room._p(room._origin, c + 0.5, r + 0.5)
	deco.pick("pet.cardbox")
	s._click_at(deco, cell.call(4, 6))
	s._check(not h.petlife.out("pet.cardbox").is_empty(), "a click puts the cardboard box down")
	var box: Dictionary = h.petlife.out("pet.cardbox")
	s._check(box.get("own", false) == false, "a thing a cat uses is not a decoration")
	deco.sel = ""
	s._click_at(deco, cell.call(4, 6))
	s._check(deco.held != null and deco.held["p"] == "pet.cardbox", "a click on it picks it up")
	s._click_at(deco, cell.call(3, 3))
	s._check(_cell(box) == Vector2i(3, 3), "and the next click puts it down")
	deco.pick("pet.cardbox")
	s._check(deco.held == null, "choosing it again is a new one")
	deco._act("pick:pet.tower")
	s._check(
		deco.held != null and deco.held["p"] == "pet.tower",
		"choosing a thing already out picks that one up"
	)
	deco.held = null
	deco.sel = ""
	s._click_at(deco, cell.call(3, 3), MOUSE_BUTTON_RIGHT)
	s._check(h.petlife.out("pet.cardbox").is_empty(), "right click takes it out")
	deco.leave()
	room.queue_free()


func _rows(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


# an old file with furniture on every cell a thing would be put: nothing of his is touched
func _migration() -> void:
	var room := _home(88, "cat_grey", "dog_golden")
	var h = room.home
	var l = h.layout
	var path := _tmp.get_current_dir().path_join("old_layout.json")
	var rows: Array = []
	for p in l.pieces:
		if not PetThings.is_pet(p):
			rows.append({"p": p["p"], "f": p["f"], "c": p["c"], "r": p["r"]})
	var taken: Array = []
	for key in h.petlife.PLACES:
		for cell in h.petlife.PLACES[key]:
			if cell not in taken and key != "window_perch":
				taken.append(cell)
				rows.append({"p": "crate", "f": "", "c": cell.x, "r": cell.y})
	var old := {"v": 1, "wall": "wallpaper", "floor": "oak", "pieces": rows}
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(old))
	f.close()
	l.pieces = l._defaults([])
	l.pets_seen = []
	l.path = path
	l.persist = true
	s._check(l.load_file(), "the old layout loads")
	var crates: int = l.pieces.filter(func(p): return p["p"] == "crate").size()
	s._check(
		crates == taken.size(), "all his furniture is kept (%d of %d)" % [crates, taken.size()]
	)
	h.apply_layout()
	h.petlife.sync()
	h.apply_layout()
	l.save()
	var keys := _keys(h)
	keys.sort()
	s._check(
		keys
		== [
			"bed_cushion",
			"bed_round",
			"bone",
			"bowls",
			"kennel",
			"litter",
			"post",
			"tower",
			"window_perch"
		],
		"the things are added to it (%s)" % [keys]
	)
	_sound(h, "migrated")
	_wall_sides(h, "migrated")
	for p in h.layout.pet_pieces():
		s._check(_cell(p) not in taken, "%s avoided his furniture (%s)" % [p["p"], _cell(p)])
	var back := _rows(path)
	var kept: Array = back["pieces"].filter(func(r): return not str(r["p"]).begins_with("pet."))
	s._check(
		kept == JSON.parse_string(JSON.stringify(rows)), "his furniture is saved back as it was"
	)
	s._check(
		back.get("pets_seen") is Array and back["pets_seen"].size() == 9,
		"the things are marked put out"
	)
	var cells := {}
	for p in h.layout.pet_pieces():
		cells[p["p"]] = [p["f"], _cell(p)]
	room.queue_free()
	room = _home(89, "cat_grey", "dog_golden")
	h = room.home
	h.layout.pieces = h.layout._defaults([])
	h.layout.pets_seen = []
	h.layout.path = path
	h.layout.persist = true
	h.layout.load_file()
	h.apply_layout()
	h.petlife.sync()
	var same := true
	for p in h.layout.pet_pieces():
		same = same and cells.get(p["p"]) == [p["f"], _cell(p)]
	s._check(
		same and h.layout.pet_pieces().size() == cells.size(),
		"a second start finds the things where they were"
	)
	var tower: Dictionary = h.petlife.piece("tower")
	var spot := Vector2i(-1, -1)
	for cell in h.petlife._wall_cells():
		var moved := {"p": "pet.tower", "f": "se", "c": cell.x, "r": cell.y}
		if cell != _cell(tower) and h.layout.place(moved, tower, h.busy_cells()) == "":
			spot = cell
			break
	s._check(spot.x > 0 and tower["f"] == "se", "he turns and moves the tower")
	h.layout.remove(h.petlife.piece("post"))
	h.apply_layout()
	h.petlife.sync()
	room.queue_free()
	room = _home(90, "cat_grey", "dog_golden")
	h = room.home
	h.layout.pieces = h.layout._defaults([])
	h.layout.pets_seen = []
	h.layout.path = path
	h.layout.persist = true
	h.layout.load_file()
	h.apply_layout()
	h.petlife.sync()
	var t2: Dictionary = h.petlife.piece("tower")
	s._check(
		not t2.is_empty() and t2["f"] == "se" and _cell(t2) == spot,
		"a moved and turned tower is kept"
	)
	s._check(h.petlife.piece("post").is_empty(), "a post he took out is not put back")
	var own := {"p": "pet.aquarium", "f": "", "c": 0, "r": 0, "own": true}
	for cell in h.petlife._wall_cells():
		own["c"] = cell.x
		own["r"] = cell.y
		if h.layout.place(own, null, h.busy_cells()) == "":
			break
	h.layout.save()
	s._check(
		_rows(path)["pieces"].any(
			func(r): return r["p"] == "pet.aquarium" and r.get("own") == true
		),
		"a thing put out by hand is saved as his"
	)
	room.queue_free()
	room = _home(91, "cat_grey", "dog_golden")
	h = room.home
	h.layout.pieces = h.layout._defaults([])
	h.layout.pets_seen = []
	h.layout.path = path
	h.layout.persist = true
	h.layout.load_file()
	h.apply_layout()
	h.petlife.sync()
	s._check(not h.petlife.piece("aquarium").is_empty(), "and comes back as his")
	var fresh = s._layout_of(h.room._index, path, false)
	s._check(fresh.pieces.size() > 0, "a layout with no pets in the room still reads the file")
	room.queue_free()


# the room as a 10x10 house saved it: the first default furniture, the things where the first rule
# put them, and a post he moved
func _ten_file(post: Vector2i) -> String:
	var rows: Array = OLD_ROWS.map(func(r): return {"p": r[0], "f": r[1], "c": r[2], "r": r[3]})
	var things := {
		"litter": Vector2i(1, 1),
		"bowls": Vector2i(5, 1),
		"post": post,
		"tower": Vector2i(9, 4),
		"bone": Vector2i(1, 8),
		"bed_round": Vector2i(1, 9),
		"bed_cushion": Vector2i(9, 8),
		"window_perch": Vector2i(1, 5),
	}
	var seen: Array = []
	for key in things:
		seen.append(key)
		var face: String = "sw" if key in ["tower", "bed_cushion"] else ""
		rows.append({"p": "pet." + key, "f": face, "c": things[key].x, "r": things[key].y})
	var path := _tmp.get_current_dir().path_join("ten_layout.json")
	var f := FileAccess.open(path, FileAccess.WRITE)
	var doc := {"v": 1, "wall": "wallpaper", "floor": "oak", "pieces": rows, "pets_seen": seen}
	f.store_string(JSON.stringify(doc))
	f.close()
	return path


# a layout saved in the 10x10 room loads into the 11x11 one with every piece at its cell
func _old_room() -> void:
	var room := _home(87, "cat_grey", Pets.NONE)
	var path := _ten_file(Vector2i(6, 9))
	var l = s._layout_of(room._index, path, false)
	var got: Array = l.pieces.filter(func(p): return not PetThings.is_pet(p))
	got = got.map(func(p): return [p["p"], p["f"], p["c"], p["r"]])
	s._check(got == OLD_ROWS, "a 10x10 layout loads with every piece at its cell (%s)" % [got])
	var things: Array = l.pet_pieces().map(func(p): return [p["p"], _cell(p)])
	s._check(things.size() == 8, "and its things at their cells (%s)" % [things])
	room.queue_free()


# a thing still where the first rule put it is put again by the current one, once; one he moved
# stays; a saved file is read as the current version
func _replaced() -> void:
	var path := _ten_file(Vector2i(6, 9))
	var room := _home(97, "cat_grey", "dog_golden")
	var h = room.home
	h.layout.pieces = h.layout._defaults([])
	h.layout.path = path
	h.layout.persist = true
	s._check(h.layout.load_file() and h.layout.old_things, "a version 1 file is read as the first rule's")
	h.apply_layout()
	h.petlife.sync()
	s._check(not h.layout.old_things, "and its things are looked at once")
	var old := {
		"litter": Vector2i(1, 1),
		"bowls": Vector2i(5, 1),
		"tower": Vector2i(9, 4),
		"bone": Vector2i(1, 8),
		"bed_round": Vector2i(1, 9),
		"bed_cushion": Vector2i(9, 8),
	}
	for key in old:
		var at: Vector2i = _cell(h.petlife.piece(key))
		s._check(at != old[key], "%s is put again (was %s, is %s)" % [key, old[key], at])
	s._check(_cell(h.petlife.piece("post")) == Vector2i(6, 9), "a post he moved stays")
	s._check(_cell(h.petlife.piece("window_perch")) == Vector2i(1, 5), "the perch stays at the window")
	_in_front(h, "replaced")
	_sound(h, "replaced")
	var cells := {}
	for p in h.layout.pet_pieces():
		cells[p["p"]] = _cell(p)
	h.layout.save()
	s._check(_rows(path)["v"] == h.layout.SAVED, "it is saved as the current version")
	h.petlife._stamp = []
	h.petlife.sync()
	var same := true
	for p in h.layout.pet_pieces():
		same = same and cells[p["p"]] == _cell(p)
	s._check(same, "and nothing is moved a second time")
	room.queue_free()
	room = _home(98, "cat_grey", "dog_golden")
	h = room.home
	h.layout.pieces = h.layout._defaults([])
	h.layout.path = path
	h.layout.persist = true
	s._check(h.layout.load_file() and not h.layout.old_things, "a saved file is read as current")
	h.apply_layout()
	h.petlife.sync()
	same = true
	for p in h.layout.pet_pieces():
		same = same and cells[p["p"]] == _cell(p)
	s._check(same, "and a second start finds the things where they were")
	room.queue_free()


# no thing in the default room stands where a person or a pet steps up to a piece, and no two
# with some height touch (unless the room is too full for that: `apart` off)
func _in_front(h, what: String, apart: bool = true) -> void:
	var clear := {}
	for cell in [Vector2i(1, 1), Vector2i(1, 2), Vector2i(1, 3), Vector2i(1, 4), Vector2i(1, 5)]:
		clear[cell] = "the armchair, the wardrobe, the TV and the sofa"
	for cell in [Vector2i(5, 1), Vector2i(8, 1), Vector2i(9, 1), Vector2i(1, 7), Vector2i(2, 7)]:
		clear[cell] = "the desk, the fireplace, the bookshelf and the door"
	for cell in [Vector2i(1, 8), Vector2i(1, 9)]:
		clear[cell] = "the piano"
	var front: Dictionary = h.layout.in_front()
	var solid: Array = []
	for p in h.layout.pieces:
		if not PetThings.is_pet(p) or p["p"] == "pet.window_perch":
			continue
		var at := _cell(p)
		s._check(not clear.has(at) and not front.has(at), "%s: %s at %s is in front of a piece" % [what, p["p"], at])
		if PetThings.THINGS[PetThings.key_of(p)]["h"] > 0:
			solid.append(at)
	if not apart:
		return
	for i in solid.size():
		for j in range(i + 1, solid.size()):
			var d: Vector2i = (solid[i] - solid[j]).abs()
			s._check(maxi(d.x, d.y) >= 2, "%s: things at %s and %s touch" % [what, solid[i], solid[j]])


# an untouched house writes no layout file; a change in decorate mode writes one
func _quiet() -> void:
	var path := _tmp.get_current_dir().path_join("quiet_layout.json")
	var room := _home(94, "cat_grey", "dog_golden")
	var h = room.home
	h.layout.pieces = h.layout._defaults([])
	h.layout.pets_seen = []
	h.layout.path = path
	h.layout.persist = true
	h.petlife._stamp = []
	h.petlife.sync()
	s._check(h.layout.pet_pieces().size() == 9, "the things are put out in memory")
	s._run_home(h, 5.0)
	h.settings.put("pet1", "rabbit_white")
	s._run_home(h, 2.0)
	h.settings.put("pet1", "cat_grey")
	s._run_home(h, 2.0)
	s._check(not FileAccess.file_exists(path), "a run and a species change write no layout")
	var box := {"p": "pet.cardbox", "f": "", "c": 2, "r": 9}
	h.layout.place(box, null, h.busy_cells())
	s._check(FileAccess.file_exists(path), "a change in decorate mode writes it")
	var saved := _rows(path)
	s._check(saved["pets_seen"].size() >= 7 and saved["pieces"].size() > 7,
		"with the things in it %s" % [saved["pets_seen"]])
	room.queue_free()



# each pet sleeps in its bed at night, a chicken on its perch, a rabbit in its house
func _night() -> void:
	var room := _home(92, "cat_grey", "dog_golden")
	var h = room.home
	h.pets.is_night = true
	h.petlife.night_place()
	var cat = h.pets.critter("nina")
	var dog = h.pets.critter("argos")
	s._check(cat.spot == "bed_cushion" and cat.mode == "sleep", "the cat sleeps in its cushion bed")
	s._check(dog.spot == "bed" and dog.mode == "sleep", "the dog sleeps in its round bed")
	s._check(h.pets._cell_of(cat.pos) == _cell(h.petlife.piece("bed_cushion")), "on the bed's cell")
	h.layout.remove(h.petlife.piece("bed_round"))
	h.layout.remove(h.petlife.piece("bed_cushion"))
	h.apply_layout()
	h.petlife.sync()
	h.petlife.night_place()
	s._check(dog.spot == "kennel" and dog.mode == "sleep", "with no bed the dog sleeps by its house")
	room.queue_free()
	room = _home(93, "chicken_white", "rabbit_white")
	h = room.home
	h.pets.is_night = true
	h.petlife.night_place()
	s._check(
		h.pets.critter("nina").spot == "roost" and h.pets.critter("nina").z > 0.0,
		"a chicken roosts"
	)
	s._check(h.pets.critter("argos").spot == "hutch", "a rabbit sleeps in its house")
	room.queue_free()


# every thing draws, both ways round, with and without a tint, and its icon
func _drawn() -> void:
	var canvas := Control.new()
	canvas.size = Vector2(400, 300)
	var count := [0]
	canvas.draw.connect(
		func() -> void:
			for key in PetThings.THINGS:
				for turned in [false, true]:
					for tint in [Color.WHITE, Color(1, 0.4, 0.4, 0.7)]:
						var pen := PetThings.Pen.new(canvas, Vector2(200, 100), 2.0, turned, tint)
						for lv in [0.0, 0.05, 0.5, 1.0]:
							var d := {"level": {"food": lv, "water": lv}, "size": 1.15, "t": lv * 9.0}
							PetThings.draw_all(pen, key, d)
							count[0] += 1
			var tiny := PetThings.Pen.new(canvas, Vector2(200, 100), 2.0)
			s._check(not tiny.ell(0.5, 0.5, 0.4, 0.2, 0.0, Color.RED), "a tiny ellipse is not drawn")
	)
	s.root.add_child(canvas)
	await s.process_frame
	await s.process_frame
	s._check(count[0] >= PetThings.THINGS.size() * 4, "every thing draws (%d)" % count[0])
	canvas.queue_free()
