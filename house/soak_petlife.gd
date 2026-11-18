extends RefCounted

# The soak's checks of the pets' kinds, voices and sounds, the pet things, the picker, the visitors,
# the personalities and the settings that govern them.
const Pets := preload("res://pets.gd")
const Voices := preload("res://voices.gd")
const Sound := preload("res://sound.gd")
const Settings := preload("res://settings.gd")
const PetView := preload("res://pet_view.gd")
const Quirks := preload("res://quirks.gd")

var s


func _init(soak) -> void:
	s = soak


func run() -> void:
	_kinds()
	_picker()
	_things()
	_visits()


func _clear(h) -> void:
	h.quirks.visitor = {}
	h.outside.act.erase("wild")


# every kind of visitor can be forced, one at a time, and the settings are obeyed
func _visits() -> void:
	var room := _home(45, "cat_grey", "dog_golden")
	var h = room.home
	var q = h.quirks
	h.pets.freeze = false
	for kind in ["hero", "city", "farm", "wild", "monster"]:
		_clear(h)
		h.fake_day = "10-28" if kind == "monster" else "06-15"
		h.fake_hour = 14.0
		s._check(q.start_visit(kind), "a %s can be forced" % kind)
		s._check(q.visiting() and q.last_kind == kind, "and is here")
		for other in ["hero", "city", "farm", "wild"]:
			s._check(not q.start_visit(other), "never two at once (%s over %s)" % [other, kind])
		s._check(h.eggs.found.has(Quirks.KIND_ID[kind]), "%s is a find" % kind)
		for i in 400:
			h.process(0.1)
			if not q.visiting():
				break
		s._check(not q.visiting(), "and a %s leaves" % kind)
	_clear(h)
	h.fake_day = "06-15"
	var wild_seen := {}
	for i in 60:
		_clear(h)
		h.fake_hour = 2.0 if i % 2 == 0 else 13.0
		q.start_visit("wild")
		var name: String = h.outside.act["wild"]["name"]
		wild_seen[name] = true
		var when: String = Quirks.WILD[name]
		s._check(
			when == "any" or when == ("night" if i % 2 == 0 else "day"), "%s fits its hour" % name
		)
	s._check(wild_seen.size() >= 5, "wild animals vary (%d)" % wild_seen.size())
	_clear(h)
	s._check(
		(
			q.guest_names("farm").size() == Quirks.FARM.size()
			and q.guest_names("wild").size() == Quirks.WILD.size()
		),
		"every farm and wild animal has its sheets"
	)
	h.fake_hour = 14.0
	var nina = h.pets.critter("nina")
	var argos = h.pets.critter("argos")
	h.sound.requested.clear()
	_clear(h)
	h.pets.place(nina, "rug", "idle")
	h.pets.place(argos, "rug2", "idle")
	q.start_visit("wild")
	q.start_visit("wild")
	s._check(nina.goal == "sill" or nina.spot == "sill", "the cat watches from the sill")
	s._check(argos.hops > 0 and h.sound.requested.has("bark"), "the dog barks once and hops")
	h.sound.requested.clear()
	_clear(h)
	h.settings.put("pet2", "rabbit_white")
	q.start_visit("wild")
	s._check(not h.sound.requested.has("bark"), "a rabbit does not bark")
	_clear(h)
	h.settings.put("pet2", "dog_golden")
	# the setting: calm has no monster, none has nobody
	h.fake_day = "10-28"
	h.fake_hour = 14.0
	q._night_due = true
	s._check(q.kinds_now().has("monster"), "all: a monster in its week")
	h.settings.put("visitors", "calm")
	s._check(
		not q.kinds_now().has("monster") and q.kinds_now().has("city"),
		"calm: people and animals only"
	)
	s._check(not q.start_visit("monster"), "calm: no monster even when forced")
	h.settings.put("visitors", "none")
	s._check(q.kinds_now().is_empty(), "none: nobody")
	for kind in ["hero", "city", "farm", "wild", "monster"]:
		s._check(not q.start_visit(kind), "none: %s is refused" % kind)
	h.settings.put("visitors", "all")
	# the rare night monster: any date, only at night, once due
	h.fake_day = "06-15"
	h.fake_hour = 23.0
	q._night_due = false
	s._check(not q.kinds_now().has("monster"), "no monster at night when none is due")
	q._night_due = true
	s._check(q.kinds_now().has("monster"), "a due monster may come at night on any date")
	h.fake_hour = 14.0
	s._check(not q.kinds_now().has("monster"), "but not by day")
	h.fake_hour = 23.0
	h.settings.put("visitors", "calm")
	s._check(not q.kinds_now().has("monster"), "and not in calm")
	h.settings.put("visitors", "all")
	s._check(q.start_visit("monster") and not q._night_due, "it comes once")
	s._check(q._night_t >= Quirks.WEEK * 0.5, "the next is about a week of running time away")
	_clear(h)
	room.queue_free()
	_cadence()
	_deterministic()


# visits per hour by rate, with the clock held: rare < sometimes < often, and calm
func _cadence() -> void:
	var counts := {}
	for rate in ["rare", "sometimes", "often"]:
		var room := _home(46, "cat_grey", "dog_golden")
		var h = room.home
		h.settings.put("visitors_rate", rate)
		h.quirks._next_visit = 0.0
		h.pets.freeze = false
		h.fake_hour = 14.0
		for i in 4320:
			h.quirks._visit(5.0)
			h.outside.process(5.0)
		counts[rate] = h.quirks.started / 6.0
		room.queue_free()
	s._check(
		counts["rare"] < counts["sometimes"] and counts["sometimes"] < counts["often"],
		"rate: rare < sometimes < often (%s)" % [counts]
	)
	s._check(
		counts["sometimes"] >= 1.5 and counts["sometimes"] <= 4.5,
		"a few visits an hour by default (%s)" % counts["sometimes"]
	)
	var room := _home(47, "cat_grey", "dog_golden")
	var h = room.home
	h.settings.put("visitors", "none")
	h.settings.put("visitors_rate", "often")
	h.pets.freeze = false
	h.fake_hour = 14.0
	for i in 4320:
		h.quirks._visit(5.0)
		h.outside.process(5.0)
	s._check(h.quirks.started == 0, "none: no visit in six hours")
	# never during a form, a card or a ringing reminder
	h.settings.put("visitors", "all")
	h.form_open = true
	for i in 1440:
		h.quirks._visit(5.0)
		h.outside.process(5.0)
	s._check(h.quirks.started == 0, "none started under an open form")
	h.form_open = false
	h.ring_ids = [1]
	for i in 1440:
		h.quirks._visit(5.0)
		h.outside.process(5.0)
	s._check(h.quirks.started == 0, "none started under a ringing reminder")
	h.ring_ids = []
	h.card.open("clock", "clock")
	for i in 1440:
		h.quirks._visit(5.0)
		h.outside.process(5.0)
	s._check(h.quirks.started == 0, "none started under an open card")
	h.card.close()
	for i in 1440:
		h.quirks._visit(5.0)
		h.outside.process(5.0)
	s._check(h.quirks.started > 0, "and they come when it is calm again")
	room.queue_free()


# the same seed, the same visitors
func _deterministic() -> void:
	var runs: Array = []
	for n in 2:
		var room := _home(48, "cat_grey", "dog_golden")
		var h = room.home
		h.settings.put("visitors_rate", "often")
		h.pets.freeze = false
		h.fake_hour = 14.0
		var kinds: Array = []
		for i in 4320:
			var before: int = h.quirks.started
			h.quirks._visit(5.0)
			h.outside.process(5.0)
			if h.quirks.started > before:
				kinds.append(h.quirks.last_kind)
		runs.append(kinds)
		room.queue_free()
	s._check(
		runs[0] == runs[1] and not runs[0].is_empty(),
		"a seeded run has the same visitors (%d)" % runs[0].size()
	)


func _home(seed_value: int, pet1: String, pet2: String) -> Control:
	var room: Control = s._room(seed_value)
	var h = room.home
	h.fake_hour = 14.0
	h.fake_day = "06-15"
	h.set_data(s._data([s._thing(1, 1.0)], 0))
	h._env = h._env_now()
	h.settings.put("pet1", pet1)
	h.settings.put("pet2", pet2)
	return room


func _names(list: Array) -> Array:
	return list.map(func(o): return o[0])


# the things in the pets' corner: only for whom they are for, switchable, never on furniture
func _things() -> void:
	var room := _home(43, "cat_grey", "dog_golden")
	var h = room.home
	var life = h.petlife
	s._check(
		life.has_litter() and life.has_post() and life.has_mat(),
		"a cat has its box and post, a dog its bone"
	)
	s._check(life.items().size() == 3, "the box (two halves) and the post are drawn")
	s._check(not life.has_hay() and life.pieces().is_empty(), "no hay for a cat and a dog")
	s._check(
		_names(life.options(h.pets.critter("nina"))).has("bowl"), "the first pet may go to its bowl"
	)
	h.settings.put("litter_box", false)
	s._check(not life.has_litter() and life.has_post(), "the litter box switch hides the box only")
	s._check(
		not _names(life.options(h.pets.critter("nina"))).has("litter"), "and nobody is sent to it"
	)
	h.settings.put("litter_box", true)
	h.settings.put("bowls", false)
	var names := _names(life.options(h.pets.critter("argos")))
	s._check(
		not names.has("bowl") and not names.has("water"),
		"the bowls switch removes both bowls from the pets' day"
	)
	h.settings.put("bowls", true)
	h.settings.put("pet_things", false)
	s._check(
		not life.has_post() and not life.has_mat() and life.has_litter(),
		"the pet things switch hides the rest, not the box"
	)
	h.settings.put("pet_things", true)
	h.layout.pieces.append({"p": "crate", "f": "", "c": 7, "r": 5})
	s._check(not life.has_litter(), "a crate of his on the cell: no litter box")
	h.layout.pieces.pop_back()
	h.settings.put("pet1", "rabbit_white")
	s._check(not life.has_litter() and not life.has_post(), "no cat, no box and no post")
	h.settings.put("pet1", Pets.NONE)
	h.settings.put("pet2", Pets.NONE)
	s._check(
		not life.has_litter() and life.options(h.pets.critter("nina")).is_empty(),
		"no pets, no things to use"
	)
	h.settings.put("pet1", "cat_grey")
	h.settings.put("pet2", "dog_golden")
	life.level["food"] = 0.3
	s._check(life.click("bowl:food") and life.level["food"] == 1.0, "a click on the bowl fills it")
	s._check(h.sound.requested.has("clink"), "with a small sound")
	s._check(not life.click("furn:piano"), "a click elsewhere is not the bowl's")
	var cat = h.pets.critter("nina")
	h.pets.place(cat, "bowl", "sit")
	h.pets.arrive_at(cat, "bowl")
	life.level["food"] = 1.0
	s._run_home(h, 20.0)
	s._check(cat.anim == "eat" or cat.spot != "bowl", "a pet at the bowl eats")
	life.litter_wait = 0.0
	cat.hold = false
	h.pets.freeze = true
	var seen := 0
	for i in 40:
		life.litter_wait = 0.0
		h.pets.place(cat, "rug", "sit")
		s._run_home(h, 0.2)
		var before: int = life.visits
		h.pets.go(cat, "litter", "sit", 5.0)
		s._run_home(h, 14.0, func(): return cat.use == "litter")
		if cat.use == "litter":
			seen += 1
			s._run_home(h, 6.0)
			s._check(life.visits == before + 1, "each trip to the box is one visit")
		s._check(
			not h.pets._blocked(h.pets._cell_of(cat.pos)) or cat.z > 0.0,
			"the cat is never on a blocked cell"
		)
	s._check(
		seen == 40 and life.visits == 40,
		"the cat goes into the box and is counted (%d)" % life.visits
	)
	var wait: float = life.litter_wait
	s._check(wait >= 420.0, "and the next visit is minutes away (%.0f)" % wait)
	room.queue_free()
	room = _home(44, "chicken_white", "cow_holstein")
	h = room.home
	s._check(
		h.petlife.has_hay() and h.layout.guests.is_empty(),
		"farm animals want hay, lent when the room draws"
	)
	h.room.guests.update(h)
	s._check(
		h.layout.guests.any(func(p): return p["p"] == "farm.hay_round"),
		"the hay bale is a lent piece"
	)
	s._check(h.pets._blocked(Vector2i(5, 6)), "and it blocks its cell like furniture")
	var names2 := _names(h.petlife.options(h.pets.critter("nina")))
	s._check(names2.has("hay_top"), "a chicken perches on the hay")
	s._check(
		_names(h.petlife.options(h.pets.critter("argos"))).has("hay_eat"), "a cow eats from it"
	)
	h.settings.put("pet_things", false)
	h.room.guests.update(h)
	s._check(
		h.layout.guests.is_empty() and not h.pets._blocked(Vector2i(5, 6)),
		"off, the hay is gone and the cell is free"
	)
	room.queue_free()


# the card writes the settings the settings screen writes, and the room follows at once
func _picker() -> void:
	var room: Control = s._room(41)
	var h = room.home
	var view: PanelContainer = PetView.new()
	view.setup(h.settings, h)
	s.root.add_child(view)
	view.open("nina")
	s._check(view.visible, "the card opens")
	s._check(view._tiles.size() == Pets.KINDS.size() + 1, "a tile for every kind and for none")
	view._put("kind", "bear_polar")
	s._check(h.settings.value("pet1") == "bear_polar", "the card writes pet1")
	s._check(
		h.pets.kinds["nina"] == "bear_polar" and h.pets.critter("nina").species == "bear",
		"the pet changes at once"
	)
	s._check(
		view._tiles["bear_polar"].chosen and not view._tiles["cat_black"].chosen,
		"the chosen tile is lit"
	)
	view._name.text = "Bruno"
	view._put("name", "Bruno")
	s._check(
		h.settings.value("cat") == "Bruno" and Settings.pets("Nina sits") == "Bruno sits",
		"the name is used in lines"
	)
	s._check(h.pets.critter("nina").title == "Nina", "the role keeps its key")
	view.open("argos")
	view._put("kind", Pets.NONE)
	s._check(
		h.pets.critter("argos").away and h.settings.value("pet2") == Pets.NONE,
		"none takes the pet away"
	)
	view._put("kind", "horse_bay")
	s._check(
		not h.pets.critter("argos").away and h.pets.critter("argos").species == "horse",
		"and a kind brings it back"
	)
	view.open("nina")
	s._check(view._name.text == "Bruno", "the card shows the kept name")
	view.close()
	s._check(not view.visible, "the card closes")
	h.settings.put("cat", "")
	view.queue_free()
	room.queue_free()


func _kinds() -> void:
	s._check(Pets.KINDS.size() == 29, "every animal of the pack is a kind (%d)" % Pets.KINDS.size())
	var species := {}
	for kind in Pets.KINDS:
		species[Pets.KINDS[kind]["species"]] = true
	for sp in species:
		if sp in ["cat", "dog"]:
			continue
		s._check(Voices.OWN.has(sp), "%s has lines of its own" % sp)
		var own: Dictionary = Voices.OWN.get(sp, {})
		for occasion in ["pet", "wake", "muse"]:
			s._check(own.get(occasion, []).size() > 0, "%s has a %s line" % [sp, occasion])
	var pets := Pets.new()
	pets.setup("", 5)
	for sp in species:
		var cry: String = Pets.CRIES.get(sp, "")
		s._check(cry == "" or cry in Sound.EVENTS, "%s's cry is a sound" % sp)
		if cry != "":
			s._check(Sound._synth(cry, 0.0).size() > 100, "%s has a synthesised cry" % cry)
	for kind in Pets.KINDS:
		var n := pets.critter("nina")
		pets.set_kind(n, kind)
		var cry := pets.cry(n)
		s._check(
			(
				(cry == "purr") == (Pets.KINDS[kind]["species"] == "cat")
				and (cry == "bark") == (Pets.KINDS[kind]["species"] == "dog")
			),
			"%s: only a cat purrs and only a dog barks" % kind
		)
		var v := Voices.new()
		v.species = {"Nina": Pets.KINDS[kind]["species"]}
		if Voices.OWN.has(Pets.KINDS[kind]["species"]):
			s._check(v.line("Nina", "pet") != "", "%s answers a pat" % kind)
