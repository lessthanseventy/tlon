extends RefCounted

# The soak's checks of the pets' kinds, voices and sounds, the pet things, the picker, the visitors,
# the personalities and the settings that govern them.
const Pets := preload("res://pets.gd")
const Voices := preload("res://voices.gd")
const Sound := preload("res://sound.gd")
const Settings := preload("res://settings.gd")
const PetView := preload("res://pet_view.gd")
const PetNow := preload("res://pet_now.gd")
const PetThings := preload("res://pet_things.gd")
const Antics := preload("res://antics.gd")
const Quirks := preload("res://quirks.gd")

var s


func _init(soak) -> void:
	s = soak


func run() -> void:
	_kinds()
	_picker()
	_pet_view()
	_pet_words()
	_things()
	_visits()
	_ways()
	_settings()


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
	h.petlife.sync()
	return room


func _names(list: Array) -> Array:
	return list.map(func(o): return o[0])


# the things the pets use: only for whom they are for, switchable, never on furniture
func _things() -> void:
	var room := _home(43, "cat_grey", "dog_golden")
	var h = room.home
	var life = h.petlife
	s._check(
		life.has_litter() and life.has_post() and life.has("bone"),
		"a cat has its box and post, a dog its bone"
	)
	s._check(life.items().size() >= 4, "the box (two halves), the post and the tower are drawn")
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
		not life.has_post() and not life.has("bone") and life.has_litter(),
		"the pet things switch hides the rest, not the box"
	)
	h.settings.put("pet_things", true)
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
	s._run_home(h, 20.0, func(): return cat.anim == "eat")
	s._check(cat.anim == "eat", "a pet at the bowl eats")
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
	var hay: Dictionary = h.petlife.piece("hay")
	s._check(h.petlife.has_hay() and not hay.is_empty(), "farm animals want hay, a piece of the room")
	s._check(h.pets._blocked(Vector2i(hay["c"], hay["r"])), "and it blocks its cell like furniture")
	var names2 := _names(h.petlife.options(h.pets.critter("nina")))
	s._check(names2.has("hay_top"), "a chicken perches on the hay")
	s._check(
		_names(h.petlife.options(h.pets.critter("argos"))).has("hay_eat"), "a cow eats from it"
	)
	h.settings.put("pet_things", false)
	h.petlife.sync()
	s._check(
		not h.petlife.has_hay() and not h.pets._blocked(Vector2i(hay["c"], hay["r"])),
		"off, the hay is gone and the cell is free"
	)
	room.queue_free()


# the phrase for forced states, and a phrase for every antic there is
func _pet_words() -> void:
	var base := {
		"away": false, "mode": "idle", "anim": "idle", "spot": "", "goal": "", "use": "",
		"plan": "", "hopping": false, "antic": ""
	}
	for row in [
		[{"mode": "sleep", "spot": "bed"}, "asleep on the round bed"],
		[{"mode": "sleep", "spot": "bed_cushion"}, "asleep on the cushion bed"],
		[{"mode": "sleep", "spot": "ant_nx_nina_0"}, "asleep"],
		[{"mode": "idle", "spot": "sill"}, "resting at the window"],
		[{"mode": "idle", "spot": "sofa"}, "resting on the sofa"],
		[{"mode": "idle", "spot": "kennel"}, "resting in the dog house"],
		[{"mode": "idle", "spot": "bowl", "anim": "eat"}, "eating at the bowls"],
		[
			{"mode": "idle", "spot": "post", "anim": "attack", "use": "post"},
			"playing at the scratch post"
		],
		[{"mode": "idle", "spot": "litter", "use": "litter"}, "in the litter box"],
		[{"mode": "idle", "spot": "knocked"}, "sitting by what it knocked down"],
		[{"mode": "idle", "spot": "ant_nx_nina_0"}, "hanging out"],
		[{"mode": "walk", "goal": "tower_top"}, "on its way to the cat tower"],
		[{"mode": "walk"}, "wandering"],
		[{"mode": "bat"}, "after the yarn"],
		[{"mode": "swat", "plan": "knock"}, "knocking something off the desk"],
		[{"mode": "idle", "spot": "sill", "antic": "cage_watch"}, "watching the bird cage"],
		[{"mode": "sleep", "spot": "bed", "antic": "dream"}, "dreaming"],
		[{"antic": "no_such_antic", "spot": "rug"}, "resting on the rug"],
		[{"away": true}, "not here"],
	]:
		var state := base.duplicate()
		state.merge(row[0], true)
		var said: String = PetNow.phrase(state)
		s._check(said == row[1], "%s reads \"%s\" (%s)" % [str(row[0]), row[1], said])
	for name in Antics.ANTICS:
		s._check(PetNow.ANTIC.has(name), "the antic %s has a phrase" % name)
	for key in PetThings.THINGS:
		s._check(
			PetNow.noun(PetNow.spots_of(key)[0]) == "the " + PetThings.THINGS[key]["name"],
			"the thing %s reads by its name" % key
		)


# a pet's view: its words follow its state, each button sends it, "change who this is" is behind a
# button
func _pet_view() -> void:
	var room := _home(46, "cat_grey", "dog_golden")
	var h = room.home
	h.pets.freeze = true
	h.pets.toys = []
	var cat = h.pets.critter("nina")
	var dog = h.pets.critter("argos")
	var view = PetView.new()
	view.setup(h.settings, h)
	s.root.add_child(view)
	view.open("nina")
	s._check(view._page.visible and not view._edit.visible, "a pet's view opens on the pet")
	s._check(view._sub.text == "grey cat · sassy", "its kind and way are named: %s" % view._sub.text)
	var labels := func(c) -> Array: return view._actions(c).map(func(a): return a["label"])
	var did := func(what: String, c, until: Callable) -> void:
		view._do(what)
		s._run_home(h, 30.0, until)
	h.pets.place(cat, "rug", "idle")
	s._check(
		labels.call(cat) == ["pat", "call over", "treat", "play", "off to bed"],
		"a cat is patted, called, treated, played with and sent to bed: %s" % str(labels.call(cat))
	)
	did.call("call", cat, func(): return cat.goal == "" and cat.mode == "idle")
	var person: Vector2i = h.pets._cell_of(h.pets.critter("person").pos)
	var here: Vector2i = h.pets._cell_of(cat.pos)
	s._check(
		absi(here.x - person.x) + absi(here.y - person.y) == 1, "call over brings it beside the person"
	)
	did.call("treat", cat, func(): return cat.anim == "eat")
	s._check(cat.spot == "bowl" and cat.anim == "eat", "a treat sends it to its bowl to eat")
	h.pets.rng.seed = 5
	did.call("play", cat, func(): return cat.use != "")
	s._check(cat.use == "post" and cat.spot in ["post", "tower_bat"], "play is a post: %s" % cat.spot)
	view._live()
	s._check(view._now.text.begins_with("playing "), "and the view says so: %s" % view._now.text)
	did.call("bed", cat, func(): return cat.mode == "sleep")
	s._check(
		cat.mode == "sleep" and cat.spot == h.petlife.night_spot(cat),
		"off to bed sends it to its night home and it sleeps"
	)
	view._live()
	s._check(view._now.text == "asleep on the cushion bed", "asleep: %s" % view._now.text)
	h.pets.place(cat, "rug", "idle")
	h.antics.quiet = true
	s._check(h.antics.trigger("pounce", "nina"), "an antic can be forced")
	s._run_home(h, 10.0, func(): return h.antics.act["st"] == "play")
	view._live()
	s._check(view._now.text == "pouncing on nothing", "its antic is its words: %s" % view._now.text)
	did.call("call", cat, func(): return cat.goal == "" and cat.mode == "idle")
	s._check(h.antics.act.is_empty() and not cat.hold, "a button lets go of the antic")
	var rows: Array = view._rows(cat).map(func(r): return r["name"])
	s._check(
		rows.has("litter box") and rows.has("scratch post") and not rows.has("bone"),
		"its things are the ones its kind uses: %s" % str(rows)
	)
	s._check(
		view._things.get_child_count() == 1 + view.SHOWN + 1, "six of them show, the rest are behind more"
	)
	view._things.get_child(1 + rows.find("scratch post")).pressed.emit()
	s._check(cat.plan["spot"] == "post", "a row sends it to that thing")
	view._things.get_child(view._things.get_child_count() - 1).pressed.emit()
	view._live()
	s._check(view._things.get_child_count() == 1 + rows.size() + 1, "more shows the rest")
	h.settings.put("bowls", false)
	s._check(not labels.call(cat).has("treat"), "no bowls, no treat button")
	h.settings.put("bowls", true)
	view.open("argos")
	h.pets.place(dog, "rug", "idle")
	s._check(labels.call(dog).has("play"), "a dog can be played with: %s" % str(labels.call(dog)))
	did.call("play", dog, func(): return dog.use != "")
	s._check(dog.use == "bone" and dog.spot == "bone", "play is its bone")
	h.settings.put("pet_things", false)
	s._check(not labels.call(dog).has("play"), "no toys out, no play button")
	h.settings.put("pet_things", true)
	view._open_edit()
	s._check(
		view.editing and view._edit.visible and not view._page.visible,
		"change who this is opens the controls"
	)
	view._put("kind", "bear_polar")
	s._check(
		h.settings.value("pet2") == "bear_polar" and h.pets.critter("argos").species == "bear",
		"a kind chosen there changes the pet"
	)
	s._check(view.back() and not view.editing and view._page.visible, "back returns to the pet")
	s._check(view._portrait.kind == "bear_polar" and not view.back(), "which shows the new one")
	view._put("kind", Pets.NONE)
	s._check(
		not view._alive.visible and view._portrait.kind == "" and view._sub.text == "no pet here",
		"no pet, only its header and the way back to the controls"
	)
	view.queue_free()
	room.queue_free()


# the card writes the settings the settings screen writes, and the room follows at once
func _picker() -> void:
	var room: Control = s._room(41)
	var h = room.home
	var view = PetView.new()
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


# each personality moves a number, and the line pool and the settings follow
func _ways() -> void:
	var room := _home(49, "cat_grey", "dog_golden")
	var h = room.home
	var nina = h.pets.critter("nina")
	var rows := func() -> Array:
		return [["sofa", 2.0, "sleep", 10.0], ["rug", 2.0, "sit", 10.0], ["yarn", 2.0, "chase", 0.0]]
	var sleep := {}
	var talk := {}
	var pools := {}
	for p in Pets.PERSONALITIES:
		h.settings.put("pet1_personality", p)
		s._check(nina.persona == p and h.pets.personalities["nina"] == p, "%s is set at once" % p)
		var out: Array = h.pets._weigh(nina, rows.call())
		sleep[p] = out[0][1]
		talk[p] = h.pets.talk_scale(nina)
		pools[p] = h.pets.voices._offline("Nina", "pet")
		s._check(not pools[p].is_empty(), "%s has lines" % p)
	s._check(sleep["lazy"] > sleep["sassy"] and sleep["sassy"] > sleep["bold"], "lazy sleeps more, bold less")
	s._check(sleep["mischievous"] < sleep["sassy"], "mischievous sleeps less")
	s._check(talk["lazy"] > talk["sassy"] and talk["sassy"] > talk["bold"], "bold talks most, lazy least")
	var seen := []
	for p in Pets.PERSONALITIES:
		s._check(not seen.has(pools[p]), "%s says what no other says" % p)
		seen.append(pools[p])
	h.settings.put("pet1_personality", "mischievous")
	var play: Array = h.pets._weigh(nina, rows.call())
	s._check(play[2][1] > 5.0, "mischievous plays with the yarn more")
	h.settings.put("pet1_personality", "sassy")
	nina.persona = "sassy"
	var runs := {}
	for p in ["sassy", "lazy", "bold", "shy"]:
		h.settings.put("pet1_personality", p)
		var n := 0
		for i in 300:
			if h.pets._runs(nina, "sit"):
				n += 1
		runs[p] = n
	s._check(runs["bold"] > 50 and runs["sassy"] == 0 and runs["lazy"] == 0, "bold runs, the others walk (%s)" % [runs])
	s._check(not h.pets._runs(nina, "sleep"), "nobody runs to sleep")
	h.settings.put("pet1_personality", "lazy")
	var lazy_speed: float = nina.speed
	h.settings.put("pet1_personality", "bold")
	s._check(nina.speed > lazy_speed, "bold walks faster than lazy")
	h.pets.freeze = false
	h.settings.put("pet1_personality", "shy")
	h.pets.place(nina, "rug", "idle")
	h.pets.pat(nina, "pet")
	s._check(nina.pat_t < 0.0, "a shy pet does not answer a pat at once")
	for i in 30:
		h.pets.process(0.1)
	s._check(nina.pat_t >= 0.0 or nina.say_left > 0.0 or nina.hearts.size() > 0, "but does, a moment later")
	h.settings.put("pet1_personality", "sassy")
	h.pets.pat(nina, "pet")
	s._check(nina.pat_t == 0.0, "a sassy one answers at once")
	h.settings.put("pet1_personality", "no such way")
	s._check(Pets.persona_of("no such way", "nina") == "sassy", "an unknown way is the pet's own")
	for p in ["sassy", "sweet", "lazy", "mischievous", "shy", "bold"]:
		h.settings.put("pet2_personality", p)
		s._check(h.pets.critter("argos").persona == p, "the second pet is %s" % p)
	# the visitors move them by personality
	var react := {}
	for p in ["sweet", "shy", "bold", "mischievous", "lazy"]:
		_clear(h)
		h.settings.put("pet2_personality", p)
		var dog = h.pets.critter("argos")
		h.pets.place(dog, "rug2", "idle")
		h.pets.freeze = false
		h.quirks.start_visit("city")
		react[p] = dog.goal if dog.goal != "" else dog.spot
		_clear(h)
	s._check(react["shy"] == "nook" and react["bold"] == "door_in" and react["mischievous"] == "mid", "visitors: shy hides, bold greets (%s)" % [react])
	s._check(react["lazy"] == "rug2", "lazy does not get up")
	# the big things come sooner for a mischievous pet
	h.settings.put("pet1_personality", "mischievous")
	h.settings.put("pet2_personality", "mischievous")
	var quick: float = h.eggs.pace()
	h.settings.put("pet1_personality", "lazy")
	h.settings.put("pet2_personality", "lazy")
	s._check(quick < 1.0 and h.eggs.pace() > 1.0, "mischievous hurries the big things, lazy slows them")
	# chatter
	for k in Pets.CHATTER:
		h.settings.put("pet_chatter", k)
		s._check(is_equal_approx(h.pets.chatter, Pets.CHATTER[k]), "chatter %s is obeyed" % k)
	s._check(Pets.CHATTER["quiet"] > Pets.CHATTER["normal"] and Pets.CHATTER["normal"] > Pets.CHATTER["chatty"], "quiet waits longer")
	room.queue_free()


# every key round-trips through the file, an absent key is the default, and the switches hide
func _settings() -> void:
	var keys := {
		"pet1_personality": ["bold", "sassy"],
		"pet2_personality": ["shy", "sweet"],
		"pet_chatter": ["chatty", "normal"],
		"visitors": ["calm", "all"],
		"visitors_rate": ["often", "sometimes"],
		"litter_box": [false, true],
		"bowls": [false, true],
		"pet_things": [false, true],
	}
	var path := "user://soak_ways_settings.json"
	DirAccess.remove_absolute(path)
	var a := Settings.new()
	a.store = path
	a.setup(true)
	for k in keys:
		s._check(a.value(k) == keys[k][1], "%s starts as %s" % [k, keys[k][1]])
		a.put(k, keys[k][0])
	var b := Settings.new()
	b.store = path
	b.setup(true)
	for k in keys:
		s._check(b.value(k) == keys[k][0], "%s round-trips" % k)
	DirAccess.remove_absolute(path)
	var room := _home(50, "cat_grey", "dog_golden")
	var h = room.home
	h.settings.put("pet1_personality", "bold")
	h.settings.put("litter_box", false)
	s._check(not h.petlife.has_litter(), "the litter box is gone with its switch")
	h.settings.put("litter_box", true)
	s._check(h.petlife.has_litter(), "and back")
	h.settings.put("bowls", false)
	s._check(not h.petlife.has("bowls"), "no bowls with its switch")
	h.settings.put("bowls", true)
	h.settings.put("pet_things", false)
	s._check(not h.petlife.has_post() and not h.petlife.has("bone") and not h.petlife.has_hay(), "no post, blanket or hay with its switch")
	h.settings.put("pet_things", true)
	s._check(h.petlife.has_post(), "and back again")
	room.queue_free()
