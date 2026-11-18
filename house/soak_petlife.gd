extends RefCounted

# The soak's checks of the pets' kinds, voices and sounds, the pet things, the picker, the visitors,
# the personalities and the settings that govern them.
const Pets := preload("res://pets.gd")
const Voices := preload("res://voices.gd")
const Sound := preload("res://sound.gd")
const Settings := preload("res://settings.gd")
const PetView := preload("res://pet_view.gd")

var s


func _init(soak) -> void:
	s = soak


func run() -> void:
	_kinds()
	_picker()
	_things()


func _home(seed_value: int, pet1: String, pet2: String) -> Control:
	var room: Control = s._room(seed_value)
	var h = room.home
	h.fake_hour = 14.0
	h.fake_day = "06-15"
	h.set_data(s._data([s._thing(1, 1.0)], 0))
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
