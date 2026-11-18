extends RefCounted

# The soak's checks of the surprises (`eggs.gd`, `hearth.gd`, `sound.gd`, ...): their logic, not pixels.
const Sound := preload("res://sound.gd")
const Pets := preload("res://pets.gd")

var s


func _init(soak) -> void:
	s = soak


func _home(seed_value: int = 7, items: Array = []) -> Array:
	var room: Control = s._room(seed_value)
	var h = room.home
	h.fake_hour = 14.0
	h.set_data(s._data(items if not items.is_empty() else [s._thing(1, 1.0)], 0))
	return [room, h]


func run() -> void:
	_sound()
	_pets()
	_hearth()
	_calm()


func _sound() -> void:
	var a := Sound.new()
	a.store = "user://soak_sound.json"
	a.persist = true
	DirAccess.remove_absolute(a.store)
	a.setup(null, true)
	s._check(a.muted, "sound starts muted")
	a.request("clink")
	s._check(a.requested == ["clink"], "a muted request is still recorded")
	a.toggle()
	s._check(not a.muted and a.mark_left > 0.0, "M unmutes and shows the speaker mark")
	var b := Sound.new()
	b.store = a.store
	b.setup(null, true)
	s._check(not b.muted, "the choice is kept in user://")
	b.toggle()
	var c := Sound.new()
	c.store = a.store
	c.setup(null, true)
	s._check(c.muted, "and kept when it is muted again")
	DirAccess.remove_absolute(a.store)
	for name in Sound.EVENTS:
		var w: AudioStreamWAV = a._stream(name, 0.0)
		s._check(w.data.size() > 100, "%s synthesizes" % name)
		var peak := 0
		for i in range(0, w.data.size() - 1, 2):
			peak = maxi(peak, absi(w.data.decode_s16(i)))
		s._check(peak <= int(Sound.PEAK * 32767.0) + 1, "%s never clips (%d)" % [name, peak])

	var made := _home()
	var h = made[1]
	h.eggs.pet_click(h.pets.critter("nina"))
	h.eggs.pet_click(h.pets.critter("argos"))
	h.set_data(s._data([s._thing(1, 1.0)], 0))
	h.tick_off(1)
	h.jar.set_count(1, h.jar.week, 0.0)
	s._run_home(h, 3.0)
	h.forced_weather = "rain"
	s._run_home(h, 0.5)
	h.ring_ids = [1]
	s._run_home(h, 0.5)
	for name in ["purr", "bark", "rustle", "clink", "rain", "ring"]:
		s._check(h.sound.requested.has(name), "%s is requested by its event" % name)
	s._check(h.sound.muted, "the room stays muted")
	made[0].queue_free()


func _pets() -> void:
	var made := _home(21)
	var h = made[1]
	var nina = h.pets.critter("nina")
	var argos = h.pets.critter("argos")
	s._check(h.eggs.start("push"), "a push starts")
	s._check(not h.eggs.start("zoomies"), "one big thing at a time")
	var seen := {"off": false}
	s._run_home(
		h,
		60.0,
		func():
			seen["off"] = seen["off"] or h.eggs.mug_off or h.eggs.pen_off
			return h.eggs.scene.is_empty() and seen["off"]
	)
	s._check(seen["off"], "Nina pushes the mug or the pen off")
	s._check(not nina.hold and h.eggs.scene.is_empty(), "and then lets go")
	s._run_home(h, 70.0)
	s._check(not h.eggs.mug_off and not h.eggs.pen_off, "it is back on the desk after a while")
	s._check(s._walkers_ok(h) == "", s._walkers_ok(h))

	for seed_value in [3, 4, 5, 6, 8]:
		var m := _home(seed_value)
		var hh = m[1]
		hh.eggs.start("bring")
		var gave := {"it": false}
		s._run_home(
			hh,
			100.0,
			func():
				gave["it"] = gave["it"] or not hh.eggs.things.is_empty() or hh.pets.toys.size() > 1
				return hh.eggs.scene.is_empty() and gave["it"]
		)
		var ar = hh.pets.critter("argos")
		s._check(
			hh.eggs.scene.is_empty() and ar.carry == "" and not ar.hold,
			"Argos brings it and lets go (seed %d)" % seed_value
		)
		s._check(s._walkers_ok(hh) == "", s._walkers_ok(hh))
		m[0].queue_free()

	h.eggs.scene = {}
	h.eggs.start("zoomies")
	s._run_home(h, 80.0, func(): return h.eggs.scene.is_empty())
	s._check(
		h.eggs.scene.is_empty() and not nina.hold and not argos.hold, "a lap, then both carry on"
	)
	s._check(s._walkers_ok(h) == "", s._walkers_ok(h))

	h.layout.pieces.append({"p": "crate", "f": "", "c": 6, "r": 4})
	h.apply_layout()
	h.eggs._box_next = 0.0
	s._run_home(h, 120.0, func(): return nina.spot == "box")
	s._check(nina.spot == "box", "Nina ends up in the crate")
	s._check(
		nina.z > 0.0 or nina.goal == "box" or not nina.jump.is_empty(),
		"on top of it, not in the floor"
	)
	h.layout.pieces.pop_back()
	h.apply_layout()

	var blocked_at: Vector2i = h.pets.blocked_cells.keys()[0]
	var p: Vector2 = (
		h._o
		+ Vector2(16.0 * (blocked_at.x - blocked_at.y), 8.0 * (blocked_at.x + blocked_at.y)) * h._k
	)
	h._geometry()
	p = (
		h._o
		+ Vector2(16.0 * (blocked_at.x - blocked_at.y), 8.0 * (blocked_at.x + blocked_at.y)) * h._k
	)
	h.eggs.set_laser(true, p)
	var bad := ""
	for i in 300:
		h.process(0.1)
		h.eggs.set_laser(true, p)
		bad = bad if bad != "" else s._walkers_ok(h)
	s._check(bad == "", "the laser sends nobody onto a blocked cell: " + bad)
	s._check(nina.hold and argos.hold, "both follow the dot")
	var cell: Vector2i = h.eggs.cell_at(p)
	s._check(cell == blocked_at, "the pointer maps back to its cell (%s %s)" % [cell, blocked_at])
	h.eggs.set_laser(false, p)
	s._run_home(h, 4.0)
	s._check(not nina.hold and not argos.hold, "the dot goes off and they carry on")

	for i in 19:
		h.eggs.pet_click(argos)
	s._check(not argos.flip, "nineteen pats is not enough")
	h.eggs.pet_click(argos)
	s._check(argos.flip and argos.hold, "the twentieth flops him belly up")
	s._run_home(h, 30.0)
	s._check(not argos.flip and not argos.hold, "and he gets up again")
	for i in 13:
		h.eggs.pet_click(nina)
		h.process(0.1)
	s._check(not h.eggs._sulking, "she bears thirteen")
	h.eggs.pet_click(nina)
	s._check(h.eggs._sulking and nina.hold, "too many pats and Nina leaves")
	s._run_home(h, 70.0)
	s._check(not nina.hold, "and comes back")
	made[0].queue_free()


func _hearth() -> void:
	var made := _home(31)
	var h = made[1]
	h.fake_day = "06-15"
	s._run_home(h, 1.0)
	s._check(not h.hearth.lit, "no fire on a warm clear day")
	h.forced_weather = "snow"
	s._run_home(h, 1.0)
	s._check(h.hearth.lit, "a snowy day lights the fire")
	h.hearth.toggle()
	s._run_home(h, 1.0)
	s._check(not h.hearth.lit, "a click puts it out")
	h.hearth.toggle()
	s._check(h.hearth.lit, "and lights it again")
	h.hearth.manual = -1
	h.forced_weather = "clear"
	h.fake_day = "12-20"
	h.fake_hour = 19.0
	s._run_home(h, 1.0)
	s._check(h.hearth.lit, "a winter evening lights it")
	h.fake_hour = 11.0
	s._run_home(h, 1.0)
	s._check(not h.hearth.lit, "but not a winter morning")
	h.temp_c = 2
	s._run_home(h, 1.0)
	s._check(h.hearth.lit, "cold lights it")
	h.temp_c = null
	h.hearth.manual = 1
	h.eggs._furn_next["fire"] = 0.0
	s._run_home(h, 20.0)
	s._check(
		(
			h.pets.critter("nina").spot.begins_with("hearth")
			or h.pets.critter("argos").spot.begins_with("hearth")
		),
		"someone lies in front of the fire"
	)

	h.set_data(s._data([s._thing(1, 1.0, "burn me")], 0))
	h.eggs.toss_ids.append(1)
	h.tick_off(1)
	s._check(
		h._crumples.size() > 0 and h._crumples[-1]["fire"], "a note tossed in flies to the fire"
	)
	s._run_home(h, 3.0)
	s._check(h.eggs.found.has("toss") and h._bin_balls == 0, "it burns, not into the bin")
	h.open_item_menu(1)
	s._check(
		h.menu.rows.any(func(r): return r["act"] == "fire"),
		"the menu offers the fire when it is lit"
	)
	h.menu.close()

	h.fake_hour = 14.0
	h.look.wear = "everyday"
	h.hearth.piano_click()
	s._check(h.hearth.play.size() > 0, "a click on the piano starts a tune")
	s._run_home(h, 60.0, func(): return h.hearth.play.is_empty())
	s._check(h.hearth.play.is_empty(), "and it ends")
	s._check(
		h.sound.requested.has("piano") and not h.sound.requested.has("bad_piano"), "he plays well"
	)
	s._check(h.person.act != "piano" or h.person.forced == "", "he leaves the bench")
	if h.look.hero_ready:
		h.look.wear = "hero"
		h.sound.requested = []
		h.hearth.piano_click()
		s._run_home(h, 60.0, func(): return h.hearth.play.is_empty())
		s._check(h.sound.requested.has("bad_piano"), "a hero plays badly")
		h.look.wear = "everyday"
	s._check(s._walkers_ok(h) == "", s._walkers_ok(h))
	made[0].queue_free()


func _calm() -> void:
	var made := _home(41)
	var h = made[1]
	h.eggs.next_big = 0.0
	h.card.open("jar", "jar")
	s._run_home(h, 40.0)
	s._check(h.eggs.scene.is_empty(), "nothing big starts while a card is open")
	h.card.close()
	h.menu.show_at(1, Vector2(100, 100), "x", [{"label": "Done", "act": "done"}])
	h.eggs.next_big = 0.0
	s._run_home(h, 40.0)
	s._check(h.eggs.scene.is_empty(), "nor while a menu is open")
	h.menu.close()

	var kinds: Array = []
	var starts := 0
	var seen := ""
	var m2 := _home(43)
	var g = m2[1]
	g.pets.freeze = false
	for i in 36000:
		g.process(0.1)
		if g.eggs.scene.is_empty():
			seen = ""
		elif seen != g.eggs.scene["k"] or g.eggs.scene["t"] < 0.2:
			if seen == "":
				starts += 1
				kinds.append(g.eggs.scene["k"])
			seen = g.eggs.scene["k"]
	s._check(
		starts >= 3 and starts <= 60, "big things come minutes apart: %d in ten hours" % starts
	)
	var again := _home(43)
	var g2 = again[1]
	var kinds2: Array = []
	seen = ""
	for i in 36000:
		g2.process(0.1)
		if g2.eggs.scene.is_empty():
			seen = ""
		elif seen == "":
			seen = g2.eggs.scene["k"]
			kinds2.append(seen)
	s._check(
		kinds == kinds2, "the same seed gives the same day: %s vs %s" % [str(kinds), str(kinds2)]
	)
	m2[0].queue_free()
	again[0].queue_free()
	made[0].queue_free()
