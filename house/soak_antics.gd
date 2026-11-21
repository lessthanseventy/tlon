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
	h.antics.quiet = false
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
	_alone(h)
	_events(h)
	_world(h)
	_clicks(h)
	_rates()
	_egg(h)
	_random()
	pair[0].queue_free()
	s._check(_user() == before, "antics write nothing to user://")


func _user() -> Array:
	var out: Array = []
	for f in ["house_settings", "house_found", "house_layout", "house_sound", "house_rhythm"]:
		var p := "user://%s.json" % f
		out.append([f, FileAccess.get_modified_time(p) if FileAccess.file_exists(p) else 0])
	return out


func kind_of(species: String) -> String:
	for k in Pets.KINDS:
		if Pets.KINDS[k]["species"] == species:
			return k
	return ""


func tidy(h, kinds: Array) -> void:
	h.antics.act = {}
	h.antics.forced = []
	h.antics.next = {"nina": 99999.0, "argos": 99999.0}
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


func _settle(h) -> void:
	for i in 600:
		var calm: bool = h.antics.act.is_empty()
		for id in ["nina", "argos"]:
			var c = h.pets.critter(id)
			calm = calm and c.mode in ["idle", "sleep"] and c.goal == "" and c.jump.is_empty()
		if calm:
			return
		h.process(0.1)


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
			if e.get("pair", false):
				h.pets.set_persona(c, "bold" if e.get("only", false) else "sweet")
				h.pets.set_persona(h.pets.critter("argos"), "shy" if e.has("bpers") else "sweet")
			if e.get("need") == "asleep":
				c.mode = "sleep"
				c.anim = "sleep"
			var n: int = h.antics.started.size()
			h.antics.force(name, "nina")
			var ended := _finish(h)
			_settle(h)
			var tag := "%s as %s" % [name, sp]
			s._check(h.antics.started.size() > n, tag + " starts when forced")
			s._check(ended, tag + " runs to its end")
			normal(h, c, tag)
			normal(h, h.pets.critter("argos"), tag + " (the other)")
	s._check(species.size() >= 12, "the table covers the species")


func _w(h, name: String, kind: String) -> float:
	tidy(h, [kind, "dog_golden"])
	return h.antics._weight(name, h.pets.critter("nina"))


func _world(h) -> void:
	h.fake_hour = 12.0
	h.forced_weather = "clear"
	h.process(0.1)
	s._check(_w(h, "sunbathe", "cat_black") > 0.0, "a clear noon has the sun patch")
	h.fake_hour = 21.0
	h.process(0.1)
	s._check(_w(h, "sunbathe", "cat_black") == 0.0, "no sun patch at night")
	h.fake_hour = 12.0
	h.forced_weather = "snow"
	h.process(0.1)
	s._check(_w(h, "sunbathe", "cat_black") == 0.0, "no sun patch in snow")
	s._check(_w(h, "snow_watch", "cat_black") > 0.0, "snow is watched")
	h.forced_weather = "clear"
	h.process(0.1)
	s._check(_w(h, "snow_watch", "cat_black") == 0.0, "no snow watching in the clear")
	h.tv.force_on(true)
	h.tv.hacks.current = "life"
	s._check(_w(h, "tv_hunt", "cat_black") > 0.0, "the cat hunts the life cells")
	s._check(_w(h, "tv_hunt", "dog_golden") == 0.0, "a dog does not")
	h.tv.hacks.current = "fireworks"
	s._check(_w(h, "tv_bark", "dog_golden") > 0.0, "the dog barks at fireworks")
	h.tv.force_on(false)
	h.quirks.visitor = {"kind": "monster", "t": 0.0, "name": "x"}
	s._check(_w(h, "visitor_puff", "cat_black") > 0.0, "a cat puffs at a monster")
	s._check(_w(h, "visitor_follow", "cat_black") == 0.0, "and does not follow a monster")
	h.quirks.visitor = {}
	h.forced_weather = ""
	h.fake_hour = 14.0


func _clicks(h) -> void:
	var ignored := 0
	var tricks := 0
	for i in 400:
		tidy(h, ["cat_black", "dog_golden"])
		h.pets.set_persona(h.pets.critter("nina"), "sassy")
		h.antics._click_t = 0.0
		if h.antics.click(h.pets.critter("nina"), 2, 0.1):
			tricks += 1
			ignored += int(h.antics.act["name"] == "trick_ignore")
		h.antics.act = {}
	s._check(tricks == 400, "a quick second click is always taken")
	s._check(ignored > 60 and ignored < 140, "a sassy pet ignores about one in four (%d)" % ignored)
	for kind in ["cat_black", "dog_golden", "pig_pink"]:
		tidy(h, [kind, "dog_golden"])
		h.antics._click_t = 0.0
		s._check(h.antics.click(h.pets.critter("nina"), 6, 5.0), "%s is rewarded for pats" % kind)
		_finish(h)
		normal(h, h.pets.critter("nina"), "pats " + kind)
	for name in ["trick_sit", "trick_spin", "trick_dead", "trick_ignore"]:
		tidy(h, ["cat_black", "dog_golden"])
		h.antics.force(name, "nina")
		_finish(h)
		normal(h, h.pets.critter("nina"), name)
	tidy(h, ["cat_black", "dog_golden"])
	var toy := {
		"kind": "yarn", "pos": Vector2(4.5, 4.5), "z": 0.0, "spin": 0.0, "hop": {}, "hits": 0
	}
	h.pets.toys.append(toy)
	h.antics.throw_toy(toy)
	s._check(not (toy["hop"] as Dictionary).is_empty(), "the toy is thrown")
	s._check(h.pets.critter("argos").mode != "sit", "the dog goes after it")
	for i in 150:
		h.process(0.1)
	h.pets.toys.erase(toy)
	tidy(h, ["cat_black", "dog_golden"])


func _alone(h) -> void:
	for name in Antics.ANTICS:
		if not Antics.ANTICS[name].get("pair", false):
			continue
		tidy(h, ["cat_black", "dog_golden"])
		h.pets.change_kind(h.pets.critter("argos"), "none")
		var n: int = h.antics.started.count(name)
		h.antics.force(name, "nina")
		_finish(h, 20)
		s._check(h.antics.started.count(name) == n, "%s never runs with one pet gone" % name)
		s._check(h.antics._weight(name, h.pets.critter("nina")) == 0.0, "%s has no weight" % name)


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
		var name: String = str(h.antics.act.get("name", ""))
		s._check(name in ["", "phone_watch"], "no antic starts over a %s (%s)" % [what, name])
	h.form_open = false
	h.ring_ids = []
	h.antics.act = {}
	h.pets.critter("nina").hold = false
	h.pets.critter("argos").hold = false


func _events(h) -> void:
	tidy(h, ["cat_black", "dog_golden"])
	h.process(0.1)
	var n: int = h.antics.started.count("cheer_done")
	h.jar.total += 1
	h.process(0.1)
	_finish(h)
	h.process(0.1)
	s._check(h.antics.started.count("cheer_done") == n + 1, "a thing done is cheered once")
	tidy(h, ["cat_black", "dog_golden"])
	n = h.antics.started.count("birthday_hop")
	h.finds.birthday_forced = true
	for i in 120:
		h.process(0.1)
	h.finds.birthday_forced = false
	s._check(h.antics.started.count("birthday_hop") == n + 2, "both hop once on the birthday")


func _count(setting: String) -> int:
	var pair := _home(72)
	var h = pair[1]
	h.settings.forced["pet_antics"] = setting
	h.antics.setup(h)
	for i in 4000:
		h.process(0.5)
	var n: int = h.antics.started.size()
	pair[0].queue_free()
	return n


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
	pair[0].queue_free()
