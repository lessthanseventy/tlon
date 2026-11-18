extends RefCounted

# The soak's checks of the choice of pets (kinds, none, one, two, species) and the visitors.
const Pets := preload("res://pets.gd")
const Settings := preload("res://settings.gd")
const Voices := preload("res://voices.gd")
const Quirks := preload("res://quirks.gd")
const ANIMAL := "isometric-animals/Gridwright Isometric Animals/"
const CRIES := ["purr", "bark", "meow"]

var s


func _init(soak) -> void:
	s = soak


func run() -> void:
	_sheets()
	_settings()
	_voices()
	_simulations()
	_homes()
	_visitors()
	_pack_list()


func _sheets() -> void:
	var art: String = s._art()
	s._check(Pets.KINDS.size() >= 10, "the pets offer a choice")
	for kind in Pets.KINDS:
		for k in [1, 2, 3]:
			for anim in Pets.ANIMS:
				var path: String = art.path_join(ANIMAL) + "Sheets/%dx/%s/%s_%s.png" % [k, kind, kind, anim]
				var img := Image.load_from_file(path) if FileAccess.file_exists(path) else null
				s._check(
					img != null and img.get_height() == 512 * k and img.get_width() % (64 * k) == 0,
					"%s has its %s sheet at %dx" % [kind, anim, k]
				)
		for name in [Pets.KINDS[kind]["shadow"]]:
			s._check(FileAccess.file_exists(art.path_join(ANIMAL) + "Effects/1x/%s.png" % name), "%s has its shadow" % kind)


func _settings() -> void:
	var path := "user://soak_pets_settings.json"
	DirAccess.remove_absolute(path)
	var a := Settings.new()
	a.store = path
	a.setup(true)
	s._check(a.value("pet1") == "cat_black" and a.value("pet2") == "dog_golden", "no pet keys are the cat and the dog")
	a.put("pet1", "rabbit_white")
	a.put("pet2", Pets.NONE)
	var b := Settings.new()
	b.store = path
	b.setup(true)
	s._check(b.value("pet1") == "rabbit_white" and b.value("pet2") == "none", "the pet keys round-trip")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string('{"pet1": "zebra", "zzz": 1}')
	f.close()
	var c := Settings.new()
	c.store = path
	c.setup(true)
	c.put("pet2", "pig_pink")
	s._check(FileAccess.get_file_as_string(path).contains("zzz"), "other keys are kept")
	s._check(Pets.kind_of(c.value("pet1"), "nina") == "cat_black", "an unknown kind is the default")
	s._check(Pets.kind_of("none", "argos") == "none" and Pets.kind_of(5, "argos") == "dog_golden", "none is a kind")
	DirAccess.remove_absolute(path)
	var d := Settings.new()
	d.put("cat", "Mimi")
	d.put("pet1", "fox_red")
	s._check(Settings.pets("Nina sits") == "Mimi sits" and d.value("dog") == "Argos", "names stay whatever the animal")
	d.put("cat", "")


func _voices() -> void:
	var v := Voices.new()
	v.species = {"Nina": "rabbit", "Argos": "rabbit"}
	for i in 20:
		s._check(v.line("Argos", "muse") != "Is Nina a small dog?", "a rabbit is no small dog")
	v.species = {"Nina": "cat", "Argos": "dog"}
	s._check(v.line("Argos", "muse") == "Is Nina a small dog?", "a dog wonders")
	s._check(Voices.fits("the bed is a cat's.", ["dog"]) == false and Voices.fits("anything", []), "fits")
	var pets := Pets.new()
	pets.setup("", 3)
	pets.set_kind(pets.critter("nina"), "rabbit_brown")
	s._check(pets.cry(pets.critter("nina")) == "", "a rabbit has no cry")
	pets.set_kind(pets.critter("nina"), "cat_grey")
	s._check(pets.cry(pets.critter("nina")) == "purr", "a cat purrs")
	pets.set_kind(pets.critter("argos"), "dog_brown")
	s._check(pets.cry(pets.critter("argos")) == "bark", "a dog barks")


# a pair on the grid for `seconds`: every animation used is in the table, nobody stands on a blocked cell,
# and a pet that is not there never moves
func _sim(kinds: Dictionary, seconds: float, label: String) -> void:
	var pets := Pets.new()
	pets.kinds = kinds.duplicate()
	pets.setup("", 11)
	pets.blocked_cells = s._layout().blocked()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var dt := 0.2
	var start := {}
	for c in pets.critters:
		start[c.id] = c.pos
	var steps := int(seconds / dt)
	for i in steps:
		if i % 300 == 1:
			pets.tv_on = rng.randf() < 0.5
			pets.is_night = rng.randf() < 0.3
			pets.settle_near(rng.randf() < 0.15)
			if rng.randf() < 0.3:
				pets.cheer(pets.critter("argos"), "desk_stand", 3, "done", "buy milk")
			if rng.randf() < 0.2:
				pets.knock(pets.critter("nina"))
		pets.process(dt)
		pets.events = []
		for c in pets.critters:
			if c.id == "person":
				continue
			if c.away:
				if c.pos != start[c.id] or c.say_left > 0.0:
					s._check(false, "%s: an absent pet moved or spoke" % label)
					return
				continue
			if not c.anim in Pets.ANIMS:
				s._check(false, "%s: %s plays %s, not in the table" % [label, c.id, c.anim])
				return
			var cell := Vector2i(int(floor(c.pos.x)), int(floor(c.pos.y)))
			if c.z <= 0.0 and c.jump.is_empty() and pets.blocked_cells.has(cell):
				s._check(false, "%s: %s on a blocked cell" % [label, c.id])
				return


func _simulations() -> void:
	_sim({"nina": "fox_red", "argos": "pig_spotted"}, 36000.0, "ten hours")
	for kind in Pets.KINDS:
		_sim({"nina": kind, "argos": "dog_golden"}, 900.0, kind + " first")
		_sim({"nina": "cat_black", "argos": kind}, 900.0, kind + " second")
	_sim({"nina": Pets.NONE, "argos": Pets.NONE}, 3600.0, "none")
	_sim({"nina": Pets.NONE, "argos": "rabbit_white"}, 3600.0, "second only")
	_sim({"nina": "chicken_brown", "argos": Pets.NONE}, 3600.0, "first only")


func _homes() -> void:
	var names := [
		"push", "bring", "zoomies", "box", "keys", "flop", "sulk", "piano", "fire", "mouse", "book",
		"found", "disco", "argos", "salute", "visitor_monster", "storm", "rainwatch", "newlook",
		"jarfull", "tv",
	]
	for combo in [["none", "none"], ["cat_black", "none"], ["none", "dog_golden"], ["rabbit_white", "pig_pink"], ["cat_black", "dog_golden"]]:
		var room: Control = s._room(21)
		var h = room.home
		h.fake_hour = 14.0
		h.fake_day = "10-28"
		h.set_data(s._data([s._thing(1, 9.0)], 0))
		h.settings.put("pet1", combo[0])
		h.settings.put("pet2", combo[1])
		for n in names:
			h.eggs.force(n)
			s._run_home(h, 8.0)
			for id in ["nina", "argos"]:
				var c = h.pets.critter(id)
				if c.away:
					s._check(c.say_text == "" and c.say_left <= 0.0, "%s: absent %s stays quiet after %s" % [combo, id, n])
		h.eggs.pet_click(h.pets.critter("nina"))
		h.eggs.pet_click(h.pets.critter("argos"))
		h.delights.new_look()
		h.secrets.word("argos")
		h.tick_off(1)
		h.came_back()
		h.person.poke()
		h.card.open("found", "mousehole")
		s._run_home(h, 60.0)
		s._check(h.knock.pending < 0, "%s: no knock is left waiting" % [combo])
		for m in h.chat.messages:
			var who: String = m["who"]
			if who in ["cat", "dog"]:
				s._check(not h.pets.critter("nina" if who == "cat" else "argos").away, "%s: a line from an absent pet" % [combo])
		var cries: Array = h.sound.requested.filter(func(x): return x in CRIES)
		if combo[0] == "none" or combo[0] == "rabbit_white":
			s._check(not cries.has("purr") and not cries.has("meow"), "%s: a non-cat never purrs (%s)" % [combo, cries])
		if combo[1] != "dog_golden":
			s._check(not cries.has("bark"), "%s: a non-dog never barks (%s)" % [combo, cries])
		else:
			s._check(cries.has("bark"), "a dog barks")
		for id in ["nina", "argos"]:
			var c = h.pets.critter(id)
			if c.away:
				s._check(h._topmost(h._p(c.pos.x, c.pos.y)) != "pet:" + id, "%s: an absent pet is not under the pointer" % [combo])
		room.queue_free()


func _visitors() -> void:
	s._check(Quirks.allowed(14.0, false) == ["hero", "city", "farm", "wild"], "no monster outside 25-31 October")
	s._check(Quirks.allowed(14.0, true).has("monster"), "a monster in its week")
	s._check(not Quirks.allowed(22.5, true).has("monster") and not Quirks.allowed(3.0, true).has("monster"), "never a monster at night")
	var room: Control = s._room(33)
	var h = room.home
	var q = h.quirks
	h.fake_hour = 14.0
	h.fake_day = "06-15"
	h.set_data(s._data([s._thing(1, 1.0)], 0))
	s._check(q.guest_names("city").size() == Quirks.PEDESTRIANS.size(), "every pedestrian has its sheets")
	s._check(q.guest_names("monster").size() == Quirks.MONSTERS.size(), "every monster has its sheets")
	s._check(not q.start_visit("monster"), "no monster in June")
	s._check(q.start_visit("city") and q.visiting() and h.eggs.found.has("visitor_city"), "a pedestrian comes and is found")
	s._check(not q.start_visit("hero") and q.visitor["kind"] == "city", "one visitor at a time")
	s._check(h.sound.requested.has("egg_visitor"), "the door cue plays")
	s._run_home(h, 12.0, func(): return not q.visiting())
	s._check(not q.visiting(), "and leaves")
	h.fake_day = "10-28"
	var seen := {}
	for i in 40:
		q.visitor = {}
		h.outside.act.erase("wild")
		q.start_visit(q._pick_kind(q.kinds_now()))
		seen[q.last_kind] = true
	s._check(seen.has("monster") and seen.has("city"), "the dice give each kind in the week")
	q.visitor = {}
	h.outside.act.erase("wild")
	h.fake_hour = 23.0
	s._check(not q.start_visit("monster"), "no monster at 23:00")
	h.fake_hour = 14.0
	s._check(q.start_visit("monster", "ghost") and q.visitor["name"] == "ghost" and h.eggs.found.has("visitor_monster"), "a monster in its week, found")
	var saved := FileAccess.file_exists("user://house_visitor_never_written.json")
	s._check(not saved, "a visitor is never saved")
	# spacing: a trigger that comes while one is here starts nobody, and the gap after is 15-35 minutes
	q.visitor = {}
	h.outside.act.erase("wild")
	var gaps := 0
	for i in 200:
		q._next_visit = 0.0
		h.fake_hour = 14.0
		q._visit(0.1)
		if q._next_visit < 900.0 or q._next_visit > 2100.0:
			gaps += 1
		q.visitor = {}
		h.outside.act.erase("wild")
	s._check(gaps == 0, "visitors are 15-35 minutes apart")
	h.fake_hour = 22.0
	q.visitor = {}
	q._next_visit = 0.0
	q._visit(0.1)
	s._check(q.visitor.is_empty(), "nobody comes to the door after 21:00 by the dice")
	q.visitor = {}
	h.outside.act.erase("wild")
	h.fake_day = "06-15"
	var art: String = room.art_dir
	room.art_dir = "/nonexistent"
	s._check(q.guest_names("city").is_empty() and q.guest_names("monster").is_empty(), "no pack, no such visitors")
	room.art_dir = art
	room.queue_free()


func _pack_list() -> void:
	var out := "user://soak_art_list.txt"
	var code := OS.execute(
		OS.get_executable_path(),
		[
			"--headless", "--path", ProjectSettings.globalize_path("res://"), "--script",
			"res://art_pack.gd", "--", "--art-dir", s._art(), "--out", ProjectSettings.globalize_path(out),
		],
	)
	s._check(code == 0, "the art list names only files that exist")
	var names := FileAccess.get_file_as_string(out).split("\n", false)
	var listed := {}
	for n in names:
		listed[n] = true
		s._check(FileAccess.file_exists(s._art().path_join(n)), "listed and there: " + n)
	for kind in Pets.KINDS:
		s._check(listed.has(ANIMAL + "Sheets/2x/%s/%s_run.png" % [kind, kind]), "the list holds " + kind)
	s._check(listed.has(ANIMAL + "Effects/2x/shadow_large.png"), "and the large shadow")
	s._check(not listed.has(ANIMAL + "Sheets/1x/cat_black/cat_black_death.png"), "nor a sheet nothing plays")
	for p in Quirks.PEDESTRIANS:
		s._check(listed.has(Quirks.PACKS["city"]["dir"] + "Sheets/3x/%s/%s_phone.png" % [p, p]), "the list holds " + p)
	for m in Quirks.MONSTERS:
		s._check(listed.has(Quirks.PACKS["monster"]["dir"] + "Sheets/1x/%s/%s_%s.png" % [m, m, Quirks.MONSTERS[m][0]]), "the list holds " + m)
	DirAccess.remove_absolute(out)
