extends RefCounted

# The soak's checks of the pets' antics (`antics.gd`): every row of the table can be forced for
# every species allowed to do it, runs to its end and leaves the pet normal; none starts over a
# card, form, menu or ring; the setting scales how often; a seeded random run ends normal.
const Pets := preload("res://pets.gd")
const Antics := preload("res://antics.gd")

var s


func _init(soak) -> void:
	s = soak


func _home(seed_value: int = 71) -> Array:
	var room: Control = s._room(seed_value)
	var h = room.home
	h.fake_hour = 14.0
	h.set_data(s._data([s._thing(1, 1.0)], 0))
	h.pets.freeze = false
	h.eggs.next_big = 99999.0
	h.quirks._next_visit = 99999.0
	return [room, h]


func run() -> void:
	var before := _user()
	var pair := _home()
	var h = pair[1]
	_table(h)
	_gates(h)
	_rates()
	_egg(h)
	_random()
	s._check(_user() == before, "antics write nothing to user://")


func _user() -> Array:
	var out: Array = []
	for f in DirAccess.get_files_at("user://"):
		var p := "user://" + f
		out.append([f, FileAccess.get_modified_time(p)])
	return out


func kind_of(species: String) -> String:
	for k in Pets.KINDS:
		if Pets.KINDS[k]["species"] == species:
			return k
	return ""


func tidy(h, kinds: Array) -> void:
	h.antics.act = {}
	h.antics.forced = []
	for i in 2:
		var c = h.pets.critter(["nina", "argos"][i])
		h.pets.change_kind(c, kinds[i])
		c.hold = false
		c.lift = 0.0
		c.flip = false
		h.pets.place(c, ["rug", "rug2"][i], "idle")
		c.wait = 99999.0


func normal(h, c, what: String) -> void:
	s._check(not c.hold and c.lift == 0.0 and not c.flip and c.carry == "", what + ": released")
	s._check(c.mode in ["idle", "sleep"] and c.jump.is_empty(), what + ": a normal mode")
	s._check(c.anim == ("sleep" if c.mode == "sleep" else "idle"), what + ": the right animation")
	s._check(
		not h.pets._blocked(h.pets._cell_of(c.pos)) or c.z > 0.0, what + ": on a walkable cell"
	)


func _finish(h, limit: int = 400) -> bool:
	for i in limit:
		h.process(0.1)
		if h.antics.act.is_empty() and h.eggs.scene.is_empty():
			return true
	return false


func _table(h) -> void:
	var species := {}
	for name in Antics.ANTICS:
		for sp in Antics.ANTICS[name]["who"]:
			species[sp] = true
	for name in Antics.ANTICS:
		var e: Dictionary = Antics.ANTICS[name]
		var who: Array = e["who"].keys()
		for sp in who:
			var kinds: Array = []
			if sp == "*":
				kinds = ["dog_golden", "cat_black"]
			else:
				kinds = [kind_of(sp), "cat_black" if sp != "cat" else "dog_golden"]
			tidy(h, kinds)
			var c = h.pets.critter("nina")
			if e.get("need") == "asleep":
				c.mode = "sleep"
				c.anim = "sleep"
			var n: int = h.antics.started.size()
			h.antics.force(name, "nina")
			var ended := _finish(h)
			var tag := "%s as %s" % [name, sp]
			s._check(h.antics.started.size() > n, tag + " starts when forced")
			s._check(ended, tag + " runs to its end")
			normal(h, c, tag)
			normal(h, h.pets.critter("argos"), tag + " (the other)")
	s._check(species.size() >= 12, "the table covers the species")


func _gates(h) -> void:
	tidy(h, ["cat_black", "dog_golden"])
	h.antics.next["nina"] = 0.0
	h.antics.next["argos"] = 0.0
	for what in ["form", "ring"]:
		h.form_open = what == "form"
		h.ring_ids = [1] if what == "ring" else []
		for i in 30:
			h.process(0.2)
			h.antics.next["nina"] = 0.0
		s._check(h.antics.act.is_empty(), "no antic starts over a %s" % what)
	h.form_open = false
	h.ring_ids = []


func _count(setting: String) -> int:
	var pair := _home(72)
	var h = pair[1]
	h.settings.forced["pet_antics"] = setting
	h.antics.setup(h)
	for i in 4000:
		h.process(0.5)
	return h.antics.started.size()


func _rates() -> void:
	var few := _count("few")
	var some := _count("some")
	var lots := _count("lots")
	s._check(few < some and some < lots, "few < some < lots (%d %d %d)" % [few, some, lots])


func _egg(h) -> void:
	tidy(h, ["chicken_white", "dog_golden"])
	h.eggs.things = []
	h.antics.force("lay_egg", "nina")
	_finish(h)
	var eggs: Array = h.eggs.things.filter(func(t): return t["kind"] == "egg")
	s._check(eggs.size() == 1, "the hen lays an egg")
	h.eggs.take(h.eggs.things.find(eggs[0]))
	s._check(h.eggs.things.is_empty(), "a click collects it")


func _random() -> void:
	var pair := _home(73)
	var h = pair[1]
	h.settings.forced["pet_antics"] = "lots"
	h.antics.setup(h)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var kinds: Array = Pets.KINDS.keys()
	for i in 3000:
		if i % 250 == 0:
			for id in ["nina", "argos"]:
				var c = h.pets.critter(id)
				var kind: String = kinds[rng.randi() % kinds.size()]
				if rng.randf() < 0.1:
					kind = "none"
				h.pets.change_kind(c, kind)
				h.pets.set_persona(c, Pets.PERSONALITIES[rng.randi() % 6])
		h.process(0.4)
	s._check(_finish(h, 1200), "the random run's last antic ends")
	for id in ["nina", "argos"]:
		var c = h.pets.critter(id)
		s._check(
			not c.hold or c.away or not h.eggs.scene.is_empty(), "random run: %s released" % id
		)
		s._check(c.lift == 0.0 and not c.flip and c.carry == "", "random run: %s normal" % id)
