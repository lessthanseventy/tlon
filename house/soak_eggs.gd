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
	_sound_files()
	_pets()
	_hearth()
	_calm()
	keys()
	outside()
	finds()
	secrets()
	quirks()
	delights()


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


func _sound_files() -> void:
	var art: String = s._art()
	var packed := FileAccess.file_exists(art.path_join(Sound.CUES["done"]["f"][0]))
	if not packed:
		print("sounds: packs not found under %s, files not tested" % art)
	var longest := 0.0
	for name in Sound.CUES:
		for rel in Sound.CUES[name]["f"]:
			if not packed:
				break
			var ogg := AudioStreamOggVorbis.load_from_file(art.path_join(rel))
			s._check(ogg != null and ogg.get_length() > 0.0, "%s loads: %s" % [name, rel])
			if ogg != null:
				longest = maxf(longest, ogg.get_length())
	print("sounds: %d cues, longest file %.2fs" % [Sound.CUES.size(), longest])

	var empty := DirAccess.create_temp("soak_art", true)
	var bare := Sound.new()
	bare.setup(s.root, false, empty.get_current_dir() if empty != null else "/nonexistent")
	bare.muted = false
	for name in Sound.CUES:
		bare.request(name)
	for name in bare.played:
		s._check(name in Sound.EVENTS, "%s without packs falls to synth or silence" % name)
	s._check(bare.requested.has("done") and not bare.played.has("done"), "a missing pack is silent")
	bare.request("clink")
	s._check(bare.played.has("clink"), "a missing file falls back to the synth")
	var listed := Sound.listing(empty.get_current_dir() if empty != null else "/nonexistent")
	s._check(listed.contains("clink -> synth") and listed.contains("done -> none"), "--sounds says synth or none")

	var quiet := Sound.new()
	quiet.setup(s.root, false, art)
	for name in Sound.CUES:
		quiet.request(name)
	s._check(quiet.muted and quiet.played.is_empty(), "muted requests play nothing")

	var loud := Sound.new()
	loud.setup(s.root, false, art)
	loud.muted = false
	for _i in 20:
		loud.request("done")
	s._check(loud.played.count("done") == 1, "a burst of one cue sounds once")
	loud.process(0.3)
	loud.request("done")
	s._check(loud.played.count("done") == 2, "it sounds again past its gap")
	if packed:
		s._check(loud._rot["done"] == 2, "a repeat takes the next file")
	for name in ["card_open", "save", "all_done", "egg_konami", "timer_done", "door", "closet_open"]:
		loud.request(name)
	s._check(loud.active() <= Sound.MAX_VOICES, "voices stay within the cap (%d)" % loud.active())
	s._check(loud._players.size() <= Sound.MAX_VOICES, "players stay within the cap")
	s._check(loud.played.size() >= 5, "a full house still takes the new cue")

	loud.volume = 0.95
	loud.nudge(0.1)
	s._check(is_equal_approx(loud.volume, 1.0), "volume clamps at 1")
	loud.nudge(-5.0)
	s._check(is_equal_approx(loud.volume, 0.0), "volume clamps at 0")
	var n := loud.played.size()
	loud.process(3.0)
	loud.request("save")
	s._check(loud.played.size() == n, "volume 0 plays nothing")

	var kept := Sound.new()
	kept.store = "user://soak_volume.json"
	DirAccess.remove_absolute(kept.store)
	kept.setup(null, true)
	s._check(is_equal_approx(kept.volume, 0.6) and kept.muted, "it starts muted at 0.6")
	kept.nudge(-0.2)
	var back := Sound.new()
	back.store = kept.store
	back.setup(null, true)
	s._check(is_equal_approx(back.volume, 0.4), "the volume is kept when persisting")
	DirAccess.remove_absolute(kept.store)
	var loose := Sound.new()
	loose.store = kept.store
	loose.setup(null, false)
	loose.nudge(0.1)
	s._check(not FileAccess.file_exists(kept.store), "a staged run keeps no volume")

	var made := _home()
	var h = made[1]
	h.decorating = true
	h.closet_open = true
	s._run_home(h, 0.3)
	s._check(
		h.sound.requested.has("decorate_on") and h.sound.requested.has("closet_open"),
		"the room's modes are cued"
	)
	h.eggs.find("konami")
	s._check(h.sound.requested.has("egg_konami"), "a find is cued")
	var was: float = h.sound.volume
	h.eggs.key(KEY_EQUAL)
	h.eggs.key(KEY_MINUS)
	h.eggs.key(KEY_MINUS)
	s._check(is_equal_approx(h.sound.volume, was - 0.1), "- and = change the volume")
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
	var at_fire := func():
		return (
			h.pets.critter("nina").spot.begins_with("hearth")
			or h.pets.critter("argos").spot.begins_with("hearth")
		)
	for _try in 8:
		h.eggs._furn_next["fire"] = 0.0
		s._run_home(h, 3.0, at_fire)
		if at_fire.call():
			break
	s._check(at_fire.call(), "someone lies in front of the fire")

	h.set_data(s._data([s._thing(1, 1.0, "burn me")], 0))
	h.eggs.toss_ids.append(1)
	h.tick_off(1)
	s._check(
		h._crumples.size() > 0 and h._crumples[-1]["fire"], "a note tossed in flies to the fire"
	)
	s._run_home(h, 3.0)
	s._check(h.eggs.found.has("toss") and h._bin_balls == 0, "it burns, not into the bin")
	var acts: Array = preload("res://views.gd").new(null, h)._actions(h.things.find(1), "todo")
	s._check(
		acts.any(func(r): return r["act"] == "fire"), "the item view offers the fire when it is lit"
	)

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
	h.form_open = true
	h.eggs.next_big = 0.0
	s._run_home(h, 40.0)
	s._check(h.eggs.scene.is_empty(), "nor while a form is open")
	h.form_open = false

	var kinds := _day(43)
	s._check(kinds.size() >= 3 and kinds.size() <= 60, "big things come minutes apart: %d in ten hours" % kinds.size())
	s._check(kinds == _day(43), "the same seed gives the same day")
	made[0].queue_free()


func keys() -> void:
	var made := _home(51)
	var h = made[1]
	h.eggs.start("keys")
	s._run_home(h, 60.0, func(): return h.eggs.scene.is_empty())
	s._check(h.eggs.scene.is_empty() and not h.pets.critter("nina").hold, "Nina walks the piano keys and gets down")
	s._check(h.sound.requested.has("piano"), "the keys sound")
	made[0].queue_free()


# the kinds of the big things that start in ten simulated hours
func _day(seed_value: int) -> Array:
	var made := _home(seed_value)
	var g = made[1]
	var out: Array = []
	var was := false
	for i in 36000:
		g.process(0.1)
		var on: bool = not g.eggs.scene.is_empty()
		if on and not was:
			out.append(g.eggs.scene["k"])
		was = on
	made[0].queue_free()
	return out


func outside() -> void:
	var made := _home(61)
	var h = made[1]
	var o = h.outside
	h.fake_hour = 14.0
	h.process(0.1)
	s._check(o.eligible("bird") and o.eligible("balloon") and o.eligible("plane"), "day things by day")
	s._check(not o.eligible("nightcat") and not o.eligible("star"), "night things not by day")
	h.forced_weather = "rain"
	h.process(0.1)
	s._check(not o.eligible("bird") and not o.eligible("balloon"), "nothing flies in the rain")
	h.forced_weather = "clear"
	h.fake_hour = 21.5
	h.process(0.1)
	s._check(o.eligible("nightcat") and o.eligible("star") and not o.eligible("bird"), "night things by night")
	h.eggs.next_big = 1.0e9
	o.start("nightcat")
	var nn = h.pets.critter("nina")
	s._run_home(h, 45.0, func(): return nn.spot == "sill")
	s._check(nn.spot == "sill", "Nina stares at the cat on the fence %s %s %s %s" % [nn.spot, nn.mode, nn.goal, nn.hold])
	o.start("star")
	o.wish()
	s._check(h.reply_text != "" and h.sound.requested.has("wish") and h.eggs.found.has("star"), "a wish gets a line and a chime")
	for name in ["bird", "balloon", "plane", "nightcat", "star"]:
		o.start(name)
		s._run_home(h, o.LONG[name] + 1.0)
		s._check(not o.act.has(name), "%s goes by" % name)
	h.fake_day = "12-31"
	h.fake_hour = 23.5
	s._run_home(h, 10.0)
	s._check(h.eggs.found.has("fireworks"), "fireworks at New Year")
	h.fake_day = "06-15"
	h.fake_hour = 14.0
	o.bursts = []
	s._run_home(h, 10.0)
	s._check(o.bursts.is_empty() and not o.winter(), "and not in June")
	h.fake_day = "01-10"
	s._check(o.winter(), "snow settles on the sill in winter")
	var days := {}
	for i in 36000:
		h.process(0.1)
		for k in o.act:
			days[k] = true
	s._check(days.size() >= 1 and days.size() <= 5, "outside things come by themselves, rarely")
	made[0].queue_free()


func finds() -> void:
	var made := _home(71)
	var h = made[1]
	var f = h.finds
	h.settings.store = "user://soak_settings.json"
	DirAccess.remove_absolute(h.settings.store)
	h.settings.persist = true
	h.fake_day = "03-15"
	s._check(not f.is_birthday(), "no cake on an ordinary day")
	f.toggle_birthday()
	s._check(f.is_birthday() and f.birthday == "03-15", "the calendar button says today is the birthday")
	s._check(not f.table().is_empty(), "there is a table for the cake")
	var g = load("res://settings.gd").new()
	g.store = h.settings.store
	g.setup(true)
	s._check(g.value("birthday") == "03-15", "the birthday is kept in user://")
	h.fake_day = "03-16"
	s._check(not f.is_birthday(), "and is only on its day")
	h.fake_day = "03-15"
	f.toggle_birthday()
	s._check(not f.is_birthday(), "the button takes it back")
	DirAccess.remove_absolute(h.settings.store)
	h.fake_day = "03-15"
	h.settings.persist = false
	h.settings.data = {}

	h.pets.set_voices({"Nina": {"muse": ["a Nina line"]}, "Argos": {"muse": ["an Argos line"]}})
	var titles: Array = f.TITLES.map(func(t): return t[0])
	for i in 6:
		f.pick_book()
		s._check(f.book["title"] in titles and f.book["blurb"] in ["a Nina line", "an Argos line"], "a book card: %s" % str(f.book))
	h.pets.set_voices({})
	f.pick_book()
	s._check(str(f.book["blurb"]) != "", "a book has a blurb with no voices from the server")
	f.glow_book()
	s._check(f.glow > 0.0 and h.eggs.found.has("borges"), "the shelf glows for the word")

	f.shake = 0.0
	h.fake_hour = 23.0
	f.last_touch = -1000.0
	f._t = 1000.0
	s._check(f.quiet_night(), "a quiet night")
	f.start_mouse()
	s._check(not f.mouse.is_empty() and h.eggs.found.has("mouse"), "a mouse comes out")
	f.touch()
	s._check(f.mouse.is_empty(), "a click and it is gone")
	f.start_mouse()
	var nn = h.pets.critter("nina")
	nn.mode = "idle"
	nn.pos = f.mouse_pos()
	f.process(0.1)
	s._check(f.mouse.is_empty(), "a pet near and it is gone")
	nn.mode = "sleep"
	f._t = 1001.0
	s._check(not f.quiet_night(), "not quiet right after a touch")
	h.fake_hour = 14.0
	f._t = 5000.0
	s._check(not f.quiet_night(), "never by day")

	var b: Array = f.blocks("found")
	s._check(str(b[1]["text"]).begins_with("%d of %d" % [h.eggs.found.size(), h.eggs.CATALOGUE.size()]), "the found card counts")
	made[0].queue_free()


func _type(h, text: String) -> void:
	for ch in text:
		h.key(KEY_A + ch.unicode_at(0) - 97)


func secrets() -> void:
	var made := _home(81)
	var h = made[1]
	var sc = h.secrets
	var arrows := {"up": KEY_UP, "down": KEY_DOWN, "left": KEY_LEFT, "right": KEY_RIGHT, "b": KEY_B}
	for t in ["up", "up", "down", "down", "left", "right", "left", "right", "b"]:
		h.key(arrows[t])
	s._check(sc.disco == 0.0, "nine of the ten keys do nothing")
	h.key(KEY_A)
	s._check(sc.disco > 0.0 and h.eggs.found.has("konami"), "the old code starts the disco")
	s._check(h.tv.override > 0, "the TV is on for it")
	s._run_home(h, 12.0, func(): return sc.disco <= 0.0)
	s._check(
		sc.disco == 0.0 and not h.pets.critter("nina").hold and not h.pets.critter("argos").hold,
		"the disco ends and lets the pets go"
	)
	_type(h, "borges")
	s._check(h.finds.glow > 0.0 and h.eggs.found.has("borges"), "borges lights the shelf")
	_type(h, "tlon")
	s._check(sc.shift > 0.0, "tlon shifts the colours")
	_type(h, "uqbar")
	s._check(sc.moon > 0.0, "uqbar shows a second moon")
	_type(h, "argos")
	s._check(
		h.eggs.found.has("argos_word") and h.pets.critter("argos").hops >= 1,
		"his name makes Argos hop"
	)
	s._run_home(h, 15.0, func(): return false)
	s._check(sc.shift == 0.0 and sc.moon == 0.0, "the colours and the moon go back")
	sc.hist = []
	_type(h, "xbor")
	_type(h, "gestlo")
	s._check(sc.shift == 0.0, "a word broken up does nothing")
	made[0].queue_free()


func quirks() -> void:
	var made := _home(91)
	var h = made[1]
	var q = h.quirks
	h.pets.freeze = false
	h.person.forced = "desk"
	s._run_home(h, 20.0, func(): return h.person.act == "desk" and h.person.phase == "idle")
	q.fidget("spin")
	var dirs := {}
	for i in 30:
		h.process(0.1)
		dirs[h.person.c.dir] = true
	s._check(dirs.size() >= 3, "the chair spins through directions: %s" % str(dirs.keys()))
	s._run_home(h, 6.0, func(): return q.fx_kind == "")
	s._check(
		q.fx_kind == "" and h.person.fx.is_empty() and h.person.c.dir == q.DESK_FACE,
		"the spin ends facing the desk"
	)
	q.fidget("stretch")
	s._check(h.person.anim() == "cheer", "a stretch is the cheer pose")
	s._run_home(h, 4.0, func(): return q.fx_kind == "")
	s._check(h.person.fx.is_empty(), "and ends")
	h.pets.freeze = true
	q._next_fx = 0.0
	q.process(0.1)
	s._check(q.fx_kind == "", "frozen for a photo, no fidget starts by itself")
	h.pets.freeze = false
	q.start_visit()
	var can: bool = q._vlook.hero_ready and not q._vlook.hero_recipes.is_empty()
	s._check(q.visiting() == can, "a visitor needs the hero pack")
	if q.visiting():
		s._check(not q.items().is_empty(), "and is drawn")
		s._run_home(h, 12.0, func(): return not q.visiting())
		s._check(not q.visiting(), "and leaves")
	made[0].queue_free()


func delights() -> void:
	var made := _home(101)
	var h = made[1]
	var d = h.delights
	d.start_moth()
	s._check(d.moth > 0.0 and h.eggs.found.has("moth"), "a moth comes to the lamp")
	s._run_home(h, 35.0, func(): return false)
	s._check(d.moth == 0.0, "and goes")
	d.new_look()
	s._check(
		h.pets.critter("argos").hops >= 1 and h.eggs.found.has("new_look"),
		"Argos greets a new look"
	)
	var seen := {}
	for row in h.eggs.CATALOGUE:
		s._check(not seen.has(row[0]), "catalogue id %s once" % row[0])
		seen[row[0]] = true
	made[0].queue_free()
