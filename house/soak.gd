extends SceneTree

const Pets := preload("res://pets.gd")
const Look := preload("res://look.gd")
const Person := preload("res://person.gd")
const Jar := preload("res://jar.gd")
const Knock := preload("res://knock.gd")
const Door := preload("res://door.gd")
const Rhythm := preload("res://rhythm.gd")
const Hacks := preload("res://hacks.gd")
const Tv := preload("res://tv.gd")
const Voices := preload("res://voices.gd")
const Layout := preload("res://layout.gd")
const Packs := preload("res://packs.gd")
const Guests := preload("res://guests.gd")
const Decorate := preload("res://decorate.gd")
const Closet := preload("res://closet.gd")
const Card := preload("res://card.gd")
const EggSoak := preload("res://soak_eggs.gd")
const GuestSoak := preload("res://soak_guests.gd")
const FormSoak := preload("res://soak_forms.gd")
const ChatSoak := preload("res://soak_chat.gd")
const LocalSoak := preload("res://soak_local.gd")
const ArtSoak := preload("res://soak_art.gd")
const PackLooksSoak := preload("res://soak_looks.gd")
const TalkSoak := preload("res://soak_talk.gd")
const TelegramSoak := preload("res://soak_telegram.gd")
const DEADLINE_MS := 540000

var _srv := TCPServer.new()
var _conns: Array = []
var _log: Array = []
var _fail_jot := false
# answers the stub's /bot... paths (Telegram's API) when set: (path, params) -> {code, body}
var bot := Callable()
var served := true
var _local
var _mode := ""
var _where := "start"
var _office := {
	"weather": {"kind": "rain", "desc": "Light rain", "temp_c": 9},
	"pause": null,
	"awaiting": 1,
	"bench": [{"name": "lonnrot", "archetype": "reviewer"}],
	"roster": [{"agent": "lonnrot", "status": "waiting", "title": "Review: door", "thread_id": 7}],
	"threads": [{"id": 7, "title": "Review: door", "awaiting": "operator", "prompt": null}],
	"landings": [{"ref": "pr/1", "subject": "first", "landed_at": "2026-11-09T23:05:14Z"}],
}
var _pets_batch: Dictionary = {}
var _failures: Array = []
var _state := {
	"open":
	[
		{"id": 1, "kind": "todo", "text": "buy milk", "due_at": null, "every": null},
		{"id": 2, "kind": "todo", "text": "send photos", "due_at": null, "every": null},
	],
	"coming": [],
	"notes": ["a note"],
	"done_week": 0,
}


func _initialize() -> void:
	load("res://home.gd").scripted = true
	_run.call_deferred()


func _process(_dt: float) -> bool:
	if Time.get_ticks_msec() > DEADLINE_MS:
		print("FAIL: the soak passed its deadline in section ", _where)
		quit(1)
	_serve()
	return false


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures.append(what)
		print("FAIL: ", what)


func _run() -> void:
	seed(7)
	_where = "logic"
	_logic()
	_where = "soak"
	_soak()
	_where = "local list"
	LocalSoak.new(self).run()
	_where = "decorate"
	_decorate_logic()
	_where = "packs"
	_packs_logic()
	_where = "looks"
	_looks()
	_where = "hacks"
	await _hacks_draw()
	_where = "cards logic"
	_card_logic()
	_where = "eggs"
	EggSoak.new(self).run()
	_where = "guests"
	GuestSoak.new(self).run()
	_where = "cards"
	await _cards()
	_where = "routes"
	await _routes()
	_where = "pack looks"
	var packs := PackLooksSoak.new(self)
	packs.run()
	await packs.measure()
	_where = "art"
	ArtSoak.new(self).run()
	print("SOAK %s (%d failures)" % ["OK" if _failures.is_empty() else "FAILED", _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _soak() -> void:
	var pets := Pets.new()
	var look := Look.new()
	var person := Person.new()
	pets.setup("", 11)
	pets.blocked_cells = _layout().blocked()
	person.setup(pets, look, 5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var last := {}
	var still := {}
	var busy := 0.0
	var steps := 0
	var chair_cells := 0
	var dt := 0.1
	var settle := 0.0
	person.snap()
	while steps < 360000:
		steps += 1
		if steps % 600 == 1:
			person.open_n = rng.randi_range(0, 4)
			person.ring = rng.randf() < 0.2
			person.hour = rng.randf_range(0.0, 24.0)
			person.calm = rng.randf() < 0.7
			person.has_notes = rng.randf() < 0.6
			pets.tv_on = rng.randf() < 0.5
			if rng.randf() < 0.15:
				pets.cheer(pets.critter("argos"), "desk_stand", 3, "done", "buy milk")
			if rng.randf() < 0.1:
				pets.knock(pets.critter("nina"))
			if rng.randf() < 0.05:
				person.arrive(rng.randf() < 0.5)
				pets.cheer(pets.critter("argos"), "door", 3, "home")
			pets.settle_near(rng.randf() < 0.15)
			if rng.randf() < 0.1:
				person.stretch()
			settle = 0.0
		settle += dt
		pets.freeze = false
		pets.process(dt)
		pets.events = []
		person.process(dt, false)
		for c in pets.critters:
			var cell := Vector2i(int(floor(c.pos.x)), int(floor(c.pos.y)))
			var on_floor: bool = c.z <= 0.0 and c.jump.is_empty()
			var seat_ok: bool = (
				c.id == "person"
				and (
					person.seated
					or person.phase in ["leaving", "entering"]
					or (person.arrive_left > 3.0 and cell == Vector2i(0, 7))
				)
			)
			if on_floor and not seat_ok:
				if cell == Pets.CHAIR:
					chair_cells += 1
				if cell.x < 1 or cell.y < 1 or cell.x >= Pets.COLS or cell.y >= Pets.ROWS or pets.blocked_cells.has(cell):
					_check(false, "%s on a blocked cell %s at step %d" % [c.id, cell, steps])
					return
			var p: Vector2 = c.pos
			if c.mode == "walk" and last.get(c.id) == p:
				still[c.id] = still.get(c.id, 0.0) + dt
				if still[c.id] > 3.0:
					_check(false, "%s walking but not moving at step %d" % [c.id, steps])
					return
			else:
				still[c.id] = 0.0
			last[c.id] = p
		if person.phase == "idle":
			busy = 0.0
			if settle > 20.0:
				_check(
					person.act == person.base(),
					"person act %s != base %s (step %d)" % [person.act, person.base(), steps]
				)
		else:
			busy += dt
			if busy > 40.0:
				_check(
					false,
					(
						"person stuck in phase %s going to %s at step %d"
						% [person.phase, person.next, steps]
					)
				)
				return
	_check(chair_cells == 0, "someone stood in the chair cell %d times" % chair_cells)
	print(
		(
			"soak: %d steps (%.1f simulated hours), person act %s"
			% [steps, steps * dt / 3600.0, person.act]
		)
	)


func _looks() -> void:
	var art := OS.get_environment("TLON_ART_DIR")
	if art == "":
		art = OS.get_environment("HOME").path_join("projects/thatch/packs/x")
	var look := Look.new()
	look.store = "user://soak_none.json"
	look.setup(art)
	if not look.layered:
		print("looks: creator pack not found, composition not tested")
		return
	print("looks: %d recipes, slots %s" % [look.recipes.size(), look.opts.keys()])
	for r in look.recipes:
		var img := look._compose(r["cfg"], "")
		var seen := false
		for x in range(0, 256, 4):
			for y in range(0, 64, 2):
				if img.get_pixel(x, y).a > 0.5:
					seen = true
		_check(seen, "recipe %s composes to an empty sheet" % r["name"])
	var closet: Control = Closet.new()
	root.add_child(closet)
	closet.open(look)
	for i in closet._rows.size():
		for d in [1, 1, -1]:
			closet._step(i, d)
			_check(look.preview(closet._work, 4) != null, "preview after row %d" % i)
	closet._random()
	_check(look.preview(closet._work, 2) != null, "preview after random")
	closet.queue_free()
	_reach_everyday(look)
	_saved_looks(art)
	_hero_looks(art)
	_hero_standing(art)


func _hero_looks(art: String) -> void:
	var path := "user://soak_hero.json"
	var gone := Look.new()
	gone.store = path
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"build": "slim", "wear": "hero", "hero": {"weapon": "bow"}}))
	f.close()
	gone.setup("/none")
	_check(not gone.hero() and gone.wear == "everyday", "no hero pack: everyday")
	var closet: Control = Closet.new()
	root.add_child(closet)
	closet.open(gone)
	_check(closet._tabs == ["everyday"], "no hero pack: no hero tab")
	closet.queue_free()
	var look := Look.new()
	look.store = path
	look.setup(art)
	if not look.hero_ready:
		print("looks: hero pack not found, hero not tested")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		return
	_check(look.hero() and look.cfg["build"] == "slim", "a saved hero look loads and is worn")
	_check(look.anim_for("type") == "ready", "typing is ready")
	_check(look.anim_for("wave") == "block", "waving is block")
	for action in Look.HERO_ACT:
		_check(look.hero_anims.has(look.anim_for(action)), "hero animation for %s exists" % action)
	_check(look.hero_anims["walk"] == [8, 8, 10.0], "hero walk is read from layers.json")
	_check(look.hero_anims["cast"][0] == 42, "hero cast is read from layers.json")
	_check(look.hero_recipes.size() > 0, "hero ready-mades are read (%d)" % look.hero_recipes.size())
	for r in look.hero_recipes:
		var img := look._compose(r["cfg"], "")
		var seen := false
		for x in range(0, 256, 4):
			for y in range(0, 64, 2):
				seen = seen or img.get_pixel(x, y).a > 0.5
		_check(seen and img.get_width() == look.hero_sheet.x, "hero recipe %s composes" % r["name"])
	var made := {}
	for b in ["broad", "slim"]:
		var base: Dictionary = look.hero_cfg.duplicate()
		base["build"] = b
		for r in Look.HERO_ROWS:
			base[r[0]] = ""
			base[r[0] + "_c"] = ""
		for skin in look.hero_opts["skin"]:
			var c: Dictionary = base.duplicate()
			c["skin"] = skin
			for p in look.layer_paths(c):
				made[p] = true
		for r in Look.HERO_ROWS:
			for style in look.hero_opts[r[0]]:
				var c: Dictionary = base.duplicate()
				c[r[0]] = style
				if style == "":
					continue
				for colour in look.hero_colours(r[0], style):
					c[r[0] + "_c"] = colour
					for p in look.layer_paths(c):
						made[p] = true
	var unreachable: Array = []
	for b in ["broad", "slim"]:
		for g in DirAccess.get_directories_at(look.hero_root.path_join("Layers/" + b)):
			var dir: String = look.hero_root.path_join("Layers/%s/%s" % [b, g])
			for file in DirAccess.get_files_at(dir):
				if file.ends_with(".png") and not made.has(dir.path_join(file)):
					unreachable.append(b + "/" + g + "/" + file)
	for p in made:
		_check(FileAccess.file_exists(p), "hero closet offers a missing file %s" % p.get_file())
	_check(unreachable.is_empty(), "hero closet cannot reach: %s" % str(unreachable.slice(0, 8)))
	print("looks: %d hero layer files reached from the closet" % made.size())
	closet = Closet.new()
	root.add_child(closet)
	closet.open(look)
	_check(closet._tabs == ["everyday", "hero"], "the closet has both tabs")
	_check(closet._tab == "hero", "the closet opens on the worn tab")
	for i in closet._rows.size():
		for d in [1, 1, -1]:
			closet._step(i, d)
			var c: Dictionary = closet._work
			var ok := true
			for r in Look.HERO_ROWS:
				ok = ok and (c[r[0]] == "" or c[r[0] + "_c"] in look.hero_colours(r[0], c[r[0]]))
			_check(ok and look.preview(c, 4) != null, "hero row %d keeps a style's colour valid" % i)
	closet._random()
	_check(closet._work["kind"] == "hero" and look.preview(closet._work, 2) != null, "hero random")
	closet._switch_tab()
	_check(closet._tab == "everyday" and not closet._work.has("kind"), "Tab goes to everyday")
	closet._switch_tab()
	closet._apply()
	var back := Look.new()
	back.store = path
	back.setup(art)
	_check(back.hero() and back.hero_cfg == look.hero_cfg, "a kept hero look is saved and read back")
	closet.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# a hero stands where he would walk to: no seat offset
func _hero_standing(art: String) -> void:
	var look := Look.new()
	look.store = "user://soak_none.json"
	look.setup(art)
	if not look.hero_ready:
		return
	look.wear = "hero"
	var pets := Pets.new()
	pets.setup("", 11)
	pets.blocked_cells = _layout().blocked()
	var person := Person.new()
	person.setup(pets, look, 5)
	for want in ["desk", "sofa", "tv", "coffee", "sleep"]:
		person.forced = want
		person.snap()
		var cell: Vector2i = Pets.SPOTS[Person.ACTS[want]["stand"]]["cell"]
		_check(not person.seated, "hero does not sit for %s" % want)
		_check(person.c.pos == pets._center(cell), "hero stands on the floor for %s" % want)
	person.forced = "sofa"
	person.snap()
	person.forced = "desk"
	for i in 3000:
		person.process(0.1, false)
		pets.process(0.1)
		pets.events = []
	var cell: Vector2i = Pets.SPOTS["desk_stand"]["cell"]
	_check(person.act == "desk" and person.phase == "idle", "hero settles at the desk")
	_check(not person.seated, "hero at the desk stands")
	_check(look.anim_for(person.anim()) == "ready", "and is drawn in ready")
	look.wear = "everyday"
	person.setup(pets, look, 5)
	person.forced = "sofa"
	person.snap()
	_check(person.seated, "an everyday person still sits")


func _saved_looks(art: String) -> void:
	var path := "user://soak_person.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"build": "slim", "top": "tee", "extra": "scarf_red"}))
	f.close()
	var old := Look.new()
	old.store = path
	old.setup(art)
	_check(
		old.cfg["scarf"] == "scarf_red" and old.cfg["build"] == "slim",
		"an old `extra` loads into its slot"
	)
	_check(
		old.cfg["eyewear"] == "" and old.cfg["apron"] == "",
		"an old `extra` clears the other slots"
	)
	old.cfg["eyewear"] = "sunglasses_black"
	old.cfg["backpack"] = "backpack_red"
	old.save()
	var back := Look.new()
	back.store = path
	back.setup(art)
	_check(
		(
			back.cfg["scarf"] == "scarf_red"
			and back.cfg["eyewear"] == "sunglasses_black"
			and back.cfg["backpack"] == "backpack_red"
		),
		"eyewear, scarf and backpack are worn together and kept"
	)
	var acc: Array = back.layer_paths(back.cfg).filter(
		func(p: String) -> bool: return "/accessory/" in p
	)
	_check(acc.size() == 3, "three accessory layers compose (%d)" % acc.size())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _reach_everyday(look) -> void:
	var made := {}
	for b in ["broad", "slim"]:
		var base: Dictionary = look.cfg.duplicate()
		base["build"] = b
		for key in Look.OPTIONAL:
			base[key] = ""
		var variants: Array = []
		for skin in look.opts["skin"]:
			variants.append({"skin": skin})
		for hair in look.opts["hair"]:
			for colour in look.opts["hair_c"]:
				variants.append({"hair": hair, "hair_c": colour})
		for group in ["top", "bottom", "shoes"]:
			for style in look.opts[group]:
				for colour in look.opts[group + "_c"]:
					variants.append({group: style, group + "_c": colour})
		for key in ["beard", "hat", "eyewear", "scarf", "backpack", "apron"]:
			for value in look.opts[key]:
				variants.append({key: value})
		for v in variants:
			var c: Dictionary = base.duplicate()
			c.merge(v, true)
			for p in look.layer_paths(c):
				made[p] = true
	var unreachable: Array = []
	var absent: Array = []
	for b in ["broad", "slim"]:
		for g in DirAccess.get_directories_at(look.root.path_join("Layers/" + b)):
			if g == "held":
				continue
			var dir: String = look.root.path_join("Layers/%s/%s" % [b, g])
			for f in DirAccess.get_files_at(dir):
				if f.ends_with(".png") and not made.has(dir.path_join(f)):
					unreachable.append(b + "/" + g + "/" + f)
	for p in made:
		if not FileAccess.file_exists(p):
			absent.append(p.get_file())
	_check(unreachable.is_empty(), "closet cannot reach: %s" % str(unreachable.slice(0, 8)))
	_check(absent.is_empty(), "closet offers files that do not exist: %s" % str(absent.slice(0, 8)))
	print("looks: %d everyday layer files reached from the closet" % made.size())


func _routes() -> void:
	# The 30 s blocking soak leaves the engine catching up for a few frames; an HTTPRequest made
	# in them times out at once (measured: result TIMEOUT, no frame between request and failure).
	# Waiting 30 frames lets it settle, so the routes pass in any order.
	for _i in 30:
		await process_frame
	_srv.listen(0, "127.0.0.1")
	OS.set_environment("TLON_URL", "http://127.0.0.1:%d" % _srv.get_local_port())
	var main: Control = load("res://main.gd").new()
	main.pets_retry = 0.3
	main.pets_window = 30.0
	main.pets_every = 100.0
	main.pets_nudge = 0.3
	root.add_child(main)
	# the morning slip, up after 05:30, would hold the forms shut
	main._room.home.fake_hour = 15.0
	await create_timer(1.5).timeout
	_check(
		main._data["open"].size() == 2,
		"GET /api/home filled the room (%d open)" % main._data["open"].size()
	)
	var asks := _count("/api/home/pets")
	_check(asks >= 3, "an empty batch is asked again at the short interval (%d asks)" % asks)
	_check(not main._room.home.has_voices(), "{} leaves the pets with nothing served")
	_pets_batch = {"Nina": {"muse": ["served line"]}, "duo": []}
	await create_timer(0.8).timeout
	_check(main._room.home.has_voices(), "the next ask picks the batch up")
	asks = _count("/api/home/pets")
	await create_timer(0.8).timeout
	_check(_count("/api/home/pets") == asks, "a held batch is asked at the long interval")
	_pets_batch = {}
	main._pets_ask()
	await create_timer(0.3).timeout
	_check(main._room.home.has_voices(), "an empty answer keeps what is held")
	main._room.home.set_voices({})
	main._pets_since = Time.get_ticks_msec() / 1000.0
	main._pets_later()
	_check(is_equal_approx(main._pets_timer.time_left, 0.3), "empty and early: the short interval")
	main._pets_since = Time.get_ticks_msec() / 1000.0 - 60.0
	main._pets_later()
	_check(main._pets_timer.time_left > 90.0, "empty past the window: backs off to the long one")
	_pets_batch = {"Nina": {"muse": ["served line"]}}
	asks = _count("/api/home/pets")
	main._on_act(1, "done")
	await create_timer(1.0).timeout
	_check(_count("/api/home/pets") == asks + 1, "the open list changing asks once more")
	_check(_seen("POST", "/api/home/1/done"), "done posted")
	_check(main._data["open"].size() == 1, "done removed the thing")
	main._on_act(2, "hour")
	await create_timer(1.0).timeout
	_check(_seen("POST", "/api/home/2/later", "hour"), "later posted with until=hour")
	_check(
		main._data["open"].is_empty() and main._data["coming"].size() == 1,
		"later moved the thing to coming"
	)
	main._jot.open("buy stamps")
	main._send_jot("buy stamps")
	await create_timer(1.0).timeout
	_check(_seen("POST", "/api/home", "buy stamps"), "jot posted")
	_check(
		main._room.home.reply_text == "to do: buy stamps",
		"reply shown: '%s'" % main._room.home.reply_text
	)
	_check(not main._jot.visible, "jot hid after a reply")
	_fail_jot = true
	main._jot.open("keep me")
	main._send_jot("keep me")
	await create_timer(1.0).timeout
	_check(
		main._jot.visible and main._jot._edit.text == "keep me",
		"failed jot keeps its text in the field"
	)
	_check("not kept" in main._jot._hint.text, "failed jot says so: '%s'" % main._jot._hint.text)
	var home = main._room.home
	_check(
		is_equal_approx(home.rhythm.list_at, 9.25),
		"home_list_at read from /api/settings (%s)" % home.rhythm.list_at
	)
	_check(
		not home.door.want.is_empty() and home.door.want["name"] == "lonnrot",
		"the waiting coworker comes from /api/office"
	)
	_check(home.door.plane.is_empty(), "the first landings only prime the door")
	_office["awaiting"] = 0
	_office["roster"] = []
	_office["threads"] = []
	_office["landings"] = [
		{"ref": "pr/2", "subject": "second", "landed_at": "2026-11-10T01:00:00Z"},
		{"ref": "pr/1", "subject": "first", "landed_at": "2026-11-09T23:05:14Z"},
	]
	main._watch_door()
	await create_timer(1.0).timeout
	_check(home.door.want.is_empty(), "nobody leans in once nothing awaits")
	_check(
		not home.door.plane.is_empty() and home.door.plane["title"] == "second",
		"a new landing sends a plane"
	)
	_where = "forms"
	await FormSoak.new(self, main).run()
	_where = "settings and chat"
	await ChatSoak.new(self, main).run()
	_where = "local routes, forms and chat"
	await LocalSoak.new(self).over(main)
	_where = "claude and telegram"
	await TalkSoak.new(self).run(main)
	await TelegramSoak.new(self).run(main)
	_srv.stop()


# the stub's state as the forms and the chat set it; the local pass puts it in the list too
func seed(open: Array, coming: Array = [], extra: Dictionary = {}) -> void:
	_state["open"] = open
	_state["coming"] = coming
	_state.merge(extra, true)
	if not served:
		_local.push_state()


func add_open(row: Dictionary) -> void:
	_state["open"].append(row)
	if not served:
		_local.push_state()


# what the notepad and the chat expect back for a loose line that became a to-do
func reply_for(text: String) -> String:
	return "to do: " + text if served else "To do: %s." % text


func _count(path: String) -> int:
	var n := 0
	for l in _log:
		if l[0] == "GET" and l[1] == path:
			n += 1
	return n


func _voices_logic() -> void:
	var v := Voices.new()
	v.rng.seed = 7
	v.set_batch({"Nina": {"done": ["a {thing}", "b {thing}", "c {thing}"]}})
	var last := ""
	var same := 0
	var chunks_ok := true
	for chunk in 6:
		var seen := {}
		for i in 3:
			var l := v.line("Nina", "done", "buy milk")
			seen[l] = true
			same += 1 if l == last else 0
			last = l
		chunks_ok = chunks_ok and seen.size() == 3
	_check(chunks_ok, "no line repeats until every other has been used")
	_check(same == 0, "never the same line twice in a row")
	_check(v.line("Nina", "done", "buy milk").ends_with("buy milk"), "{thing} is filled in")
	v.set_batch({"Nina": {"done": ["a {thing}", "plain"]}})
	var only_plain := true
	for i in 12:
		only_plain = only_plain and v.line("Nina", "done") == "plain"
	_check(only_plain, "a line with {thing} and no thing to name is skipped")
	v.set_batch({"Nina": {"done": ["a {thing}"]}})
	_check(v.line("Nina", "done") == "", "all lines skipped: no bubble, not a built-in")
	_check(
		Voices.short("  a   very long thing that goes on and on and on  ").length()
		<= Voices.THING_MAX,
		"a thing is trimmed to fit a bubble"
	)
	v.set_batch({"Nina": {"pet": ["x"], "muse": ["x", "y"]}})
	var first := v.line("Nina", "pet")
	_check(first == "x" and v.line("Nina", "muse") == "y", "not twice in a row across occasions")
	v.set_batch({})
	_check(
		v.line("Nina", "pet") in Voices.FALLBACK["Nina"]["pet"],
		"nothing served: the built-in line"
	)
	_check(v.line("Nina", "tv") == "", "nothing served and no built-in: no bubble")
	v.set_batch({"Nina": {"muse": ["served"]}})
	_check(
		v.line("Nina", "pet") in Voices.FALLBACK["Nina"]["pet"],
		"the pet with nothing for an occasion falls back"
	)
	var mixed := false
	for i in 40:
		mixed = mixed or v.line("Nina", "muse") != "served"
	_check(not mixed, "a served occasion never mixes in a built-in")
	_check(Voices.bubble_time("hi") == 3.5, "a short line shows for the minimum")
	_check(Voices.bubble_time("x".repeat(130)) >= 8.5, "a long line stays long enough to read")
	_check(Voices.bubble_time("x".repeat(400)) == 9.0, "no bubble stays past the maximum")
	v.set_batch({"duo": [["Bob: hi"], ["Nina: one", "Argos: two"]]})
	_check(v.duo() == [["Nina", "one"], ["Argos", "two"]], "a malformed exchange is skipped")
	var room := _room()
	var pets = room.home.pets
	pets.set_voices({"duo": [["Nina: one", "Argos: two", "Nina: three"]]})
	pets.play_duo(pets.voices.duo())
	var order: Array = []
	var both := false
	for i in 120:
		pets.process(0.1)
		var talking: Array = []
		for id in ["nina", "argos"]:
			var c = pets.critter(id)
			if c.say_left > 0.0:
				talking.append([id, c.say_text])
		both = both or talking.size() > 1
		if talking.size() == 1 and (order.is_empty() or order[-1] != talking[0]):
			order.append(talking[0])
	var want := [["nina", "one"], ["argos", "two"], ["nina", "three"]]
	_check(order == want, "duo turns in order: " + str(order))
	_check(not both, "never two bubbles at once in a duo")
	room.queue_free()


func _seen(method: String, path: String, body_has: String = "") -> bool:
	for l in _log:
		if l[0] == method and l[1] == path and (body_has == "" or body_has in str(l[2])):
			return true
	return false


func _serve() -> void:
	if _srv.is_listening() and _srv.is_connection_available():
		_conns.append({"p": _srv.take_connection(), "buf": PackedByteArray()})
	for c in _conns.duplicate():
		var p: StreamPeerTCP = c["p"]
		p.poll()
		if p.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_conns.erase(c)
			continue
		var n := p.get_available_bytes()
		var buf: PackedByteArray = c["buf"]
		if n > 0:
			buf.append_array(p.get_data(n)[1])
			c["buf"] = buf
		var text := buf.get_string_from_utf8()
		var split := text.find("\r\n\r\n")
		if split < 0:
			continue
		var head := text.substr(0, split)
		var body := text.substr(split + 4)
		var length := 0
		for line in head.split("\r\n"):
			if line.to_lower().begins_with("content-length:"):
				length = int(line.get_slice(":", 1))
		if body.to_utf8_buffer().size() < length:
			continue
		_respond(p, head.get_slice(" ", 0), head.get_slice(" ", 1), body)
		_conns.erase(c)


func _respond(p: StreamPeerTCP, method: String, path: String, body: String) -> void:
	_log.append([method, path, body])
	var code := 200
	var out: Variant = {}
	var parsed: Variant = JSON.parse_string(body) if body != "" else {}
	if bot.is_valid() and path.begins_with("/bot"):
		var answer: Dictionary = bot.call(path, parsed)
		code = answer["code"]
		out = answer["body"]
	elif method == "GET" and path == "/api/home":
		out = _state
	elif method == "GET" and path == "/api/home/pets":
		out = _pets_batch
	elif method == "GET" and path == "/api/office":
		out = _office
	elif method == "GET" and path == "/api/settings":
		out = {"knobs": [{"key": "home_list_at", "value": "09:15"}]}
	elif method == "POST" and path.ends_with("/done"):
		var id := int(path.get_slice("/", 3))
		_state["open"] = _state["open"].filter(func(t): return int(t["id"]) != id)
	elif method == "POST" and path.ends_with("/later"):
		var id := int(path.get_slice("/", 3))
		out = {"id": id, "text": "send photos", "due_at": "2026-11-17T20:00:00Z"}
		_state["open"] = _state["open"].filter(func(t): return int(t["id"]) != id)
		_state["coming"] = [
			{"id": id, "kind": "reminder", "text": "send photos", "due_at": out["due_at"]}
		]
	elif method == "GET" and path.begins_with("/api/home/now"):
		var skip: Array = []
		if "?skip=" in path:
			skip = path.get_slice("?skip=", 1).split(",")
		var rest: Array = _state["open"].filter(func(t): return not str(t["id"]) in skip)
		out = {"pick": null if rest.is_empty() else rest[0], "say": "nothing open"}
	elif method == "POST" and path.ends_with("/drop"):
		var id := int(path.get_slice("/", 3))
		_state["open"] = _state["open"].filter(func(t): return int(t["id"]) != id)
		out = {"id": id, "text": "x"}
	elif method == "POST" and (path == "/api/home/add" or path.get_slice("/", 4) in ["edit", "plan", "revive", "answer"]):
		if _mode == "400":
			code = 400
			out = {"error": "at is more than a year back"}
		elif _mode == "404":
			code = 404
		else:
			out = {"id": 99, "text": str(parsed.get("text", "")), "reply": "ok"}
	elif method == "POST" and path == "/api/home":
		if _fail_jot:
			code = 404
		else:
			out = {"reply": "to do: " + str(parsed.get("text", ""))}
	else:
		code = 404
	var payload := JSON.stringify(out).to_utf8_buffer()
	var head := (
		"HTTP/1.1 %d X\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n"
		% [code, payload.size()]
	)
	p.put_data(head.to_utf8_buffer() + payload)
	p.disconnect_from_host()


func _iso(days_ago: float) -> String:
	var at := Time.get_unix_time_from_system() - days_ago * 86400.0
	return Time.get_datetime_string_from_unix_time(int(at)) + "Z"


func _art() -> String:
	if OS.has_environment("TLON_ART_DIR"):
		return OS.get_environment("TLON_ART_DIR")
	return OS.get_environment("HOME").path_join("projects/thatch/packs/x")


func _unix(text: String) -> float:
	return Time.get_unix_time_from_datetime_string(text)


func _logic() -> void:
	_jar_logic()
	_knock_logic()
	_rhythm_logic()
	_door_logic()
	_tv_logic()
	_voices_logic()
	_home_logic()
	_night_logic()


func _jar_logic() -> void:
	var monday := Jar.week_key(_unix("2026-11-16T09:00:00"))
	_check(Jar.week_key(_unix("2026-11-22T23:00:00")) == monday, "Sunday is in its Monday's week")
	_check(Jar.week_key(_unix("2026-11-23T00:30:00")) != monday, "Monday starts a new week")
	var jar := Jar.new()
	jar.set_count(4, monday)
	_check(jar.shown == 4 and jar.drops.is_empty(), "the first count shows at once")
	jar.set_count(5, monday)
	_check(jar.drops.size() == 1 and jar.shown == 4, "one more done queues one drop")
	for i in 20:
		jar.process(0.05)
	_check(jar.shown == 5 and jar.drops.is_empty(), "the drop lands and the jar holds it")
	jar.set_count(60, monday)
	_check(jar.shown == Jar.CAP, "the drawn marbles are capped")
	jar.set_count(2, monday + 7)
	_check(jar.shown == 2 and jar.drops.is_empty(), "a new week starts again, quietly")
	var a := Jar.new()
	var b := Jar.new()
	var c := Jar.new()
	a.set_count(1, monday)
	b.set_count(1, monday)
	c.set_count(1, monday + 7)
	var same := true
	var differs := false
	for i in Jar.CAP:
		same = same and a.colour(i) == b.colour(i)
		differs = differs or a.colour(i) != c.colour(i)
	_check(same, "a week's colours are the same every time")
	_check(differs, "another week has other colours")


func _knock_logic() -> void:
	var now := Time.get_unix_time_from_system()
	var old := {"id": 1, "since": _iso(5.0), "due_at": null}
	var older := {"id": 2, "since": _iso(9.0), "due_at": null}
	var fresh := {"id": 3, "since": _iso(1.0), "due_at": null}
	var future := {"id": 4, "since": _iso(20.0), "due_at": _iso(-1.0)}
	_check(Knock.oldest([old, older, fresh], now) == 2, "the oldest open thing is the one")
	_check(Knock.oldest([fresh], now) == -1, "nothing under three days is knocked")
	_check(Knock.oldest([future, fresh], now) == -1, "a thing with a future due is never knocked")
	_check(Knock.oldest([future, old], now) == 1, "a future due is passed over for the next oldest")
	var k := Knock.new()
	k.persist = false
	_check(k.candidate([old], now, 12.0, false) == 1, "by day the old sticky is a candidate")
	_check(k.candidate([old], now, 12.0, true) == -1, "never at night")
	_check(k.candidate([old], now, 7.0, false) == -1, "never before the morning")
	_check(k.candidate([old], now, 22.0, false) == -1, "never late in the evening")
	k.last = now - 3600.0
	_check(k.candidate([old], now, 12.0, false) == -1, "at most once every few hours")
	k.last = now - 5.0 * 3600.0
	_check(k.candidate([old], now, 12.0, false) == 1, "after the gap it can again")
	k.pending = 1
	_check(k.candidate([old], now, 12.0, false) == -1, "not while one is on its way")
	k.pending = -1
	k.id = 1
	_check(k.candidate([old], now, 12.0, false) == -1, "one knocked sticky at a time")
	k.clear()
	var pets := Pets.new()
	pets.setup("", 3)
	var nina := pets.critter("nina")
	pets.knock(nina)
	var swats := 0
	for i in 400:
		pets.process(0.1)
		for ev in pets.events:
			swats += 1 if ev == "swat" else 0
		pets.events = []
	_check(swats == 1, "Nina swats once (%d)" % swats)
	_check(nina.spot == "knocked", "Nina ends beside the sticky (%s)" % nina.spot)


func _rhythm_logic() -> void:
	_check(Rhythm.parse_time("17:30") == 17.5, "17:30 parses")
	_check(Rhythm.parse_time("") == -1.0 and Rhythm.parse_time("later") == -1.0, "no time, no beat")
	_check(Rhythm.home_due(17.6, 17.5, "", "d"), "home beat is due after the list time")
	_check(not Rhythm.home_due(17.4, 17.5, "", "d"), "not before it")
	_check(not Rhythm.home_due(17.6, 17.5, "d", "d"), "not twice a day")
	_check(not Rhythm.home_due(21.0, 17.5, "", "d"), "not hours after")
	_check(not Rhythm.home_due(17.6, -1.0, "", "d"), "not when the list is off")
	_check(Rhythm.morning_due(9.0, 9.0, "", "d"), "first run after 05:30 is a morning")
	_check(not Rhythm.morning_due(6.0, 4.0, "", "d"), "running since before 05:30 waits for 08:00")
	_check(Rhythm.morning_due(8.1, 4.0, "", "d"), "the clock passing 08:00 is a morning")
	_check(not Rhythm.morning_due(8.1, 4.0, "d", "d"), "once a day")
	_check(not Rhythm.morning_due(13.0, 13.0, "", "d"), "no morning in the afternoon")
	var r := Rhythm.new()
	r.persist = false
	_check(r.due(9.0, "d1") == "morning", "the morning comes")
	_check(r.due(9.1, "d1") == "", "and not again that day")
	_check(r.due(17.6, "d1") == "home", "then the homecoming")
	_check(r.due(17.7, "d1") == "", "and not again")
	_check(r.due(9.0, "d2") == "morning", "the next day it all comes back")


func _door_logic() -> void:
	var waiting := _office.duplicate(true)
	var v := Door.visitor(waiting)
	_check(v.get("name") == "lonnrot" and v.get("text") == "Review: door", "a waiting coworker leans in")
	var asked := {
		"threads":
		[{"id": 9, "title": "t", "awaiting": null, "prompt": {"summary": "run it?"}, "lead": "yu"}],
		"bench": [{"name": "yu"}],
		"roster": [],
	}
	_check(Door.visitor(asked).get("text") == "asks: run it?", "a prompt is the caption")
	waiting["pause"] = "pencils_down"
	_check(Door.visitor(waiting).is_empty(), "a paused office sends nobody")
	var quiet := {"awaiting": 0, "roster": [], "threads": [], "bench": []}
	_check(Door.visitor(quiet).is_empty(), "nothing waits, nobody comes")
	var d := Door.new()
	d.update_office(_office)
	for i in 30:
		d.process(0.1)
	_check(d.present(), "the coworker is at the door")
	d.update_office(quiet)
	for i in 30:
		d.process(0.1)
	_check(d.lean == 0.0 and d.shown.is_empty() and not d.present(), "and leaves when nothing waits")
	d = Door.new()
	d.update_office({"landings": [{"ref": "a", "subject": "s"}]})
	_check(d.plane.is_empty(), "landings seen at the start send nothing")
	var two := {"landings": [{"ref": "b", "subject": "t"}, {"ref": "a", "subject": "s"}]}
	d.update_office(two)
	_check(not d.plane.is_empty() and d.plane["title"] == "t", "a new landing flies in")
	d.dismiss_plane()
	d.update_office(two)
	_check(d.plane.is_empty(), "a dismissed plane does not come again")


func _tv_logic() -> void:
	var tv := Tv.new()
	tv.setup(5)
	tv.process(0.1, false, false)
	_check(not tv.on, "the TV is off when nobody watches")
	tv.process(0.1, true, false)
	_check(tv.on, "it is on while he watches")
	tv.process(0.1, true, true)
	_check(not tv.on, "it is off in the deep night")
	tv.process(0.1, false, false)
	tv.click()
	tv.process(0.1, false, false)
	_check(tv.on, "a click turns it on")
	var before: String = tv.hacks.current
	tv.click()
	_check(tv.hacks.current != before, "a click changes the channel")
	_check(Hacks.NAMES.size() >= 8, "at least eight hacks")
	var seen := {}
	var last: String = tv.hacks.current
	for i in 400:
		tv.hacks.advance()
		_check(tv.hacks.current != last, "never the same hack twice in a row")
		seen[tv.hacks.current] = true
		last = tv.hacks.current
	_check(seen.size() == Hacks.NAMES.size(), "every hack comes up")
	for n in Hacks.NAMES:
		_check(tv.hacks.has_method("_" + n), "hack %s has a drawer" % n)
	var h := Hacks.new()
	h.setup(9)
	var at := 0.0
	var changed: Array = []
	var cur: String = h.current
	for i in 36000:
		h.update(0.1, true)
		at += 0.1
		if h.current != cur:
			changed.append(at)
			cur = h.current
	var spaced := changed.size() > 8
	for i in range(1, changed.size()):
		var gap: float = changed[i] - changed[i - 1]
		spaced = spaced and gap >= 119.0 and gap <= 241.0
	_check(spaced, "a new hack every two to four minutes (%d changes in an hour)" % changed.size())
	var frozen := Hacks.new()
	frozen.setup(9)
	for i in 10:
		frozen.update(0.1, false)
	_check(frozen.t == 0.0, "an off TV runs no clock")


func _room(seed_value: int = 7) -> Control:
	var room: Control = load("res://room.gd").new()
	room.art_dir = _art()
	root.add_child(room)
	var h = room.home
	h.knock.persist = false
	h.knock.last = 0.0
	h.rhythm.persist = false
	h.rhythm.days = {"home": "", "morning": ""}
	h.pets.freeze = false
	h.pets.setup(room.art_dir, seed_value)
	h.pets.blocked_cells = h.layout.blocked()
	h.person.setup(h.pets, h.look, seed_value + 1)
	h.person.snap()
	h.person.rng.seed = seed_value + 1
	h.knock._rng.seed = seed_value + 2
	h.tv.setup(seed_value + 3)
	h.sound.persist = false
	h.sound.muted = true
	h.eggs.setup(h, seed_value + 4, false)
	h.outside.setup(h)
	h.finds.setup(h)
	h.quirks.setup(h)
	h.delights.setup(h)
	h.fake_day = "06-15"
	h.layout.setup(room._index, room.art_found, "", false)
	h.apply_layout()
	return room


func _data(items: Array, week: int = 0) -> Dictionary:
	return {"open": items, "coming": [], "notes": [], "done_week": week}


func _thing(id: int, days: float, text: String = "old thing", due: Variant = null) -> Dictionary:
	return {
		"id": id,
		"kind": "todo",
		"text": text,
		"due_at": due,
		"every": null,
		"since": _iso(days),
		"told_at": null
	}


func _run_home(h, seconds: float, until: Callable = Callable()) -> void:
	var t := 0.0
	while t < seconds:
		h.process(0.1)
		t += 0.1
		if until.is_valid() and until.call():
			return


func _home_logic() -> void:
	var room := _room()
	var h = room.home
	h.fake_hour = 12.0
	h.set_data(_data([_thing(1, 8.0)], 3))
	_check(h.jar.total == 3 and h.jar.shown == 3, "the jar starts at the week's count")
	h.set_data(_data([_thing(1, 8.0)], 4))
	_check(h.jar.drops.size() == 1, "one more done drops one marble")
	h.knock.next_check = 0.0
	_run_home(h, 120.0, func(): return h.knock.id >= 0)
	_check(h.knock.id == 1, "Nina knocks the old sticky off (%s)" % h.knock.id)
	_check(not h._slots.has(1), "the knocked sticky leaves the desk")
	h.knock.next_check = 0.0
	_run_home(h, 1.0)
	_check(h.knock.id == 1 and h.knock.pending == -1, "one knocked sticky at a time")
	h.open_item_menu(1)
	_check(h.knock.id == -1 and h._slots.has(1) and h.menu.is_open, "a click gives the paper menu")
	h.menu.close()
	h.knock.last = Time.get_unix_time_from_system()
	h.knock.next_check = 0.0
	_run_home(h, 700.0)
	_check(h.knock.id == -1 and h.knock.pending == -1, "not again within the gap")
	h.knock.last = Time.get_unix_time_from_system() - 5.0 * 3600.0
	h.fake_hour = 2.0
	for i in 8:
		h.knock.next_check = 0.0
		_run_home(h, 60.0)
	_check(h.knock.id == -1 and h.knock.pending == -1, "never at night")
	h.fake_hour = 12.0
	var future := _iso(-2.0)
	h.set_data(_data([_thing(1, 9.0, "old thing", future)]))
	for i in 8:
		h.knock.next_check = 0.0
		_run_home(h, 60.0)
	_check(h.knock.id == -1 and h.knock.pending == -1, "never for a thing due in the future")
	h.set_data(_data([_thing(5, 2.0, "water the plant")]))
	h.tick_off(5)
	_check(h.perk_left > 0.0 and h.water_left > 0.0, "the plant is watered when its reminder is done")
	_check(h.pets.critter("argos").hops > 0, "Argos celebrates a done thing")
	h.knock.last = Time.get_unix_time_from_system()
	h.set_data(_data([]))
	h.rhythm.list_at = 17.5
	h.rhythm.days = {"home": "", "morning": "x"}
	h.fake_hour = 17.6
	h.set_data(_data([_thing(6, 0.2, "pay the thing")]))
	_run_home(h, 1.0)
	_check(h.person.bag == "carry" or h.person.act == "arrive", "he comes home at the list time")
	_run_home(h, 6.0)
	_check(h.rhythm.kind == "home" and h.rhythm.rows.size() == 1, "the slip of what is open unrolls")
	_check(h.rhythm.days["home"] == h._day_key(), "the homecoming is remembered for the day")
	h.dismiss_slip()
	_run_home(h, 2.0)
	_check(h.rhythm.kind == "", "a click or Esc puts the slip away")
	_run_home(h, 300.0)
	_check(h.rhythm.kind == "" and h.person.arrive_left == 0.0, "the homecoming is once a day")
	h.rhythm.days = {"home": h._day_key(), "morning": ""}
	h.rhythm.first_hour = 9.0
	h.fake_hour = 9.0
	_run_home(h, 3.0)
	_check(h.person.stretch_left > 0.0 or h.rhythm.kind == "morning", "he stretches in the morning")
	_check(h.rhythm.days["morning"] == h._day_key(), "the morning is remembered for the day")
	room.queue_free()


func _night_logic() -> void:
	var room := _room()
	var h = room.home
	h.fake_hour = 1.0
	h.set_data(_data([]))
	_run_home(h, 600.0)
	_check(h.person.act == "sleep", "he sleeps late at night (%s)" % h.person.act)
	_check(h.pets.critter("nina").spot == "sofa", "Nina settles on the sofa")
	_check(h.pets.critter("argos").spot == "rug", "Argos settles by him")
	_check(not h.tv.on and h._deep > 0.9, "the TV is off and the lights are low")
	h.person.forced = "tv"
	h.fake_hour = 14.0
	_run_home(h, 8.0)
	_check(h.tv.on, "he turns the TV on when he sits down to watch")
	room.queue_free()


func _card_logic() -> void:
	_check(Card.until_text(130 * 60.0) == "in 2 h 10 min", "in 2 h 10 min: " + Card.until_text(7800.0))
	_check(Card.until_text(25 * 60.0) == "in 25 min", "in 25 min")
	_check(Card.until_text(2 * 3600.0) == "in 2 h", "in 2 h")
	_check(Card.until_text(25 * 3600.0) == "in 1 day 1 h", "in 1 day 1 h")
	_check(Card.until_text(3 * 86400.0) == "in 3 days", "in 3 days")
	_check(Card.until_text(20.0) == "now", "under half a minute is now")
	var nov := Card.month_info(2026, 11)
	_check(nov["first"] == 0 and nov["days"] == 30, "November 2026 starts on a Sunday, 30 days")
	_check(Card.days_in(2028, 2) == 29 and Card.days_in(2026, 12) == 31, "days in a month")
	var from := Card.unix(2026, 11, 1)
	var to := Card.unix(2026, 12, 1)
	var days := func(list: Array) -> Array:
		return list.map(func(at): return Time.get_datetime_dict_from_unix_time(int(at))["day"])
	var due := Card.unix(2026, 11, 3, 9, 0)
	_check(days.call(Card.occurrences(due, "week", from, to)) == [3, 10, 17, 24], "every week")
	_check(days.call(Card.occurrences(due, "", from, to)) == [3], "once")
	_check(days.call(Card.occurrences(due, "day", from, to)).size() == 28, "every day from the 3rd")
	var late := Card.unix(2026, 1, 31, 9, 0)
	_check(days.call(Card.occurrences(late, "month", Card.unix(2026, 2, 1), from)).has(28), "month end")
	_check(Card.occurrences(late, "month", Card.unix(2026, 2, 1), Card.unix(2026, 3, 1)).size() == 1, "once a month")
	_every_logic()


func _every_logic() -> void:
	var days := func(list: Array) -> Array:
		return list.map(func(at): return Time.get_datetime_dict_from_unix_time(int(at))["day"])
	var nov := Card.unix(2026, 11, 1)
	var dec := Card.unix(2026, 12, 1)
	var due := Card.unix(2026, 11, 3, 9, 0)
	_check(days.call(Card.occurrences(due, "1 week", nov, dec)) == [3, 10, 17, 24], "1 week is every week")
	_check(days.call(Card.occurrences(due, "2 week", nov, dec)) == [3, 17], "every other week")
	_check(days.call(Card.occurrences(due, "6 week", nov, dec)) == [3], "every 6 weeks: one in the month")
	_check(days.call(Card.occurrences(due, "6 week", dec, Card.unix(2027, 1, 1))) == [15], "every 6 weeks lands on the 15th of December")
	_check(days.call(Card.occurrences(due, "3 day", nov, dec)) == [3, 6, 9, 12, 15, 18, 21, 24, 27, 30], "every 3 days")
	var k31 := Card.unix(2026, 1, 31, 9, 0)
	var want := {2: 28, 3: 31, 4: 30, 5: 31, 6: 30}
	for m in want:
		var got: Array = days.call(Card.occurrences(k31, "month", Card.unix(2026, m, 1), Card.unix(2026, m + 1, 1)))
		_check(got == [want[m]], "monthly from the 31st in month %d: %s" % [m, str(got)])
	var q := Card.unix(2026, 1, 15, 8, 30)
	var hits: Array = []
	for m in range(1, 13):
		hits.append(Card.occurrences(q, "3 month", Card.unix(2026, m, 1), Card.unix(2026 + m / 12, m % 12 + 1, 1)).size())
	_check(hits == [1, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0], "every 3 months: Jan, Apr, Jul, Oct (%s)" % str(hits))
	_check(Card.occurrences(due, "garbage", nov, dec) == [due], "an unknown every counts as once")
	_check(Card.every_words("week") == "every week" and Card.every_words("day") == "every day", "every week, every day")
	_check(Card.every_words("2 week") == "every other week", "2 weeks is every other week")
	_check(Card.every_words("6 week") == "every 6 weeks", "every 6 weeks")
	_check(Card.every_words("3 month") == "every 3 months", "every 3 months")
	_check(Card.every_words("1 month") == "every month", "1 month is every month")


# the point of a hit area nobody sits over, for each key
func _hit_points(h) -> Dictionary:
	var pts := {}
	for x in range(0, 1100, 4):
		for y in range(0, 700, 4):
			var key: String = h._topmost(Vector2(x, y))
			if not pts.has(key):
				pts[key] = []
			if pts[key].size() < 60:
				pts[key].append(Vector2(x, y))
	return pts


func _cards() -> void:
	var room := _room()
	room.size = Vector2(1100, 700)
	var h = room.home
	h.fake_hour = 8.0
	h.fake_day = "03-15"
	h.pets.freeze = true
	var day := Time.get_datetime_dict_from_unix_time(int(h._now_local()))
	var bias: float = h._bias()
	var iso := func(d: int, hour: int, minute: int) -> String:
		var at := Card.unix(day["year"], day["month"], d, hour, minute) - bias
		return Time.get_datetime_string_from_unix_time(int(at)) + "Z"
	var today := int(h._now_local() / 86400.0)
	var soon := Time.get_datetime_string_from_unix_time(int(today * 86400.0 + 10.1666667 * 3600.0 - bias)) + "Z"
	var data := {
		"open": [],
		"coming":
		[
			{"id": 1, "kind": "reminder", "text": "water the plant", "due_at": soon, "every": "week"},
			{"id": 2, "kind": "reminder", "text": "pay rent", "due_at": iso.call(20, 10, 0), "every": null},
		],
		"notes": ["a", "b", "c", "d", "e", "f", "g"],
		"done_week": 3,
	}
	h.set_data(data)
	h.set_weather({"kind": "rain", "desc": "Light rain", "temp_c": 9})
	for _i in 4:
		await process_frame
	if not room.art_found:
		print("cards: no art, hit areas not tested")
		room.queue_free()
		return
	var pts := _hit_points(h)
	var empty: Vector2 = pts[""][pts[""].size() - 1]
	var things := {
		"calendar": "cal", "jar": "jar", "weather": "window", "clock": "clock",
		"plant": "plant", "tv": "tv", "board": "board",
	}
	for kind in things:
		var key: String = things[kind]
		_check(pts.has(key), "%s has a hit area" % kind)
		if not pts.has(key):
			continue
		h.click(pts[key][0])
		_check(h.card.kind == kind and h.card.key == key, "a click on %s opens its card" % key)
		_check(not h.card_blocks().is_empty(), "the %s card has something to say" % kind)
		await process_frame
		var out: bool = h.click(empty)
		_check(not h.card.is_open() and out, "a click outside closes the %s card" % kind)
		h.click(pts[key][0])
		h.close_card()
		_check(not h.card.is_open(), "Esc closes the %s card" % kind)
		h.click(pts[key][0])
		await process_frame
		for p in pts[key]:
			if not h.card._box.has_point(p):
				h.click(p)
				_check(not h.card.is_open(), "the same thing again closes the %s card" % kind)
				break
		h.close_card()
	print("cards: %d things open their card from their hit area" % things.size())
	h.click(pts["note:0"][0] if pts.has("note:0") else pts["board"][0])
	_check(h.card.kind == "board", "a note opens the board card")
	h.close_card()
	h.click(pts["cal"][0])
	await process_frame
	var jar_pt := Vector2(-1, -1)
	for p in pts["jar"]:
		if not h.card._box.has_point(p):
			jar_pt = p
	_check(jar_pt.x >= 0, "a jar point outside the calendar card")
	h.click(jar_pt)
	_check(h.card.kind == "jar", "another thing replaces the card: one at a time (%s)" % h.card.kind)
	h.close_card()
	for state in ["jot_open", "closet_open", "decorating"]:
		h.set(state, true)
		h.click(pts["cal"][0])
		_check(not h.card.is_open(), "no card while %s" % state)
		h.set(state, false)
	h.menu.show_at(1, Vector2(300, 300), "x", [{"label": "a", "act": "done"}])
	h.click(pts["cal"][0])
	_check(not h.card.is_open() and not h.menu.is_open, "no card over a menu; its click only closes it")
	h.click(pts["cal"][0])
	_check(h.card.kind == "calendar", "the card opens once the menu is gone")
	h.jot_open = true
	h.process(0.1)
	_check(not h.card.is_open(), "opening the notepad closes the card")
	h.jot_open = false
	h.rhythm.kind = "home"
	h.click(pts["cal"][0])
	_check(not h.card.is_open(), "no card over the day's slip")
	h.rhythm.kind = ""
	h.open_card("calendar")
	_check(h.card.kind == "calendar", "--card opens by name")

	var month: Dictionary = h.card_blocks()[0]
	_check(month["t"] == "month" and month["marks"].has(20), "the reminder is marked on its day")
	_check(month["marks"].has(Time.get_datetime_dict_from_unix_time(today * 86400)["day"]), "and the weekly one today")
	h.card.kind = "clock"
	var clock: Array = h.card_blocks()
	_check("in 2 h 10 min" in str(clock), "the clock says how long: %s" % str(clock.slice(2)))
	h.card.kind = "plant"
	_check("water the plant" in str(h.card_blocks()), "the plant says when it is next watered")
	h.set_data(data.merged({"coming": []}, true))
	_check("needs water" in str(h.card_blocks()), "no watering due: a plain line")
	h.card.kind = "weather"
	_check("Light rain" in str(h.card_blocks()) and "9°C (48°F)" in str(h.card_blocks()), "the weather in words")
	h.card.kind = "jar"
	var plain: Array = h.card_blocks()
	_check(plain.size() == 2 and "3 done" in str(plain), "the jar without names says the count only")
	h.set_data(
		data.merged(
			{
				"done":
				[
					{"text": "older", "done_at": "2026-11-14T10:00:00Z"},
					{"text": "newest", "done_at": "2026-11-16T10:00:00Z"},
					{"text": "middle", "done_at": "2026-11-15T10:00:00Z"},
				]
			},
			true
		)
	)
	var named: Array = h.card_blocks()
	_check(named.size() == 5 and "newest" in named[2]["text"] and "older" in named[4]["text"], "the jar lists names newest first")
	h.set_data(data.merged({"done_week": 0}, true))
	_check("fresh" in str(h.card_blocks()), "an empty week says so")
	h.card.kind = "board"
	_check(h.card_blocks().size() == 8 and h.card.page == 0, "the board shows a page of notes")
	h.card.page = 5
	_check(h.card_blocks().size() == 5 and h.card.page == 1, "the board pages clamp")
	h.card.kind = "tv"
	h.tv.force_on(true)
	h.tv.hacks.force("plasma")
	h.card.key = "tv"
	await process_frame
	await process_frame
	var button: Rect2 = h.card._buttons[0]["rect"]
	var last: String = h.tv.hacks.current
	var always := true
	for i in 40:
		h.click(button.get_center())
		always = always and h.tv.hacks.current != last
		last = h.tv.hacks.current
	_check(always and h.card.kind == "tv", "Next always shows a different picture")
	room.queue_free()


func _hacks_draw() -> void:
	var canvas := Control.new()
	canvas.size = Vector2(200, 120)
	var h := Hacks.new()
	h.setup(1)
	var drawn := []
	canvas.draw.connect(
		func() -> void:
			var q := PackedVector2Array([Vector2(10, 10), Vector2(190, 10), Vector2(190, 110), Vector2(10, 110)])
			for n in Hacks.NAMES:
				h.force(n)
				h.update(1.5, true)
				h.draw(canvas, q)
				drawn.append(n)
	)
	root.add_child(canvas)
	await process_frame
	await process_frame
	_check(drawn.size() >= Hacks.NAMES.size(), "every hack draws (%d)" % drawn.size())
	canvas.queue_free()


func _layout() -> RefCounted:
	return _layout_of(Packs.extend(_interiors(), _art()))


func _layout_of(sprites: Dictionary, path: String = "", keep: bool = false) -> RefCounted:
	var l := Layout.new()
	l.setup(sprites, true, path, keep)
	return l


func _interiors() -> Dictionary:
	var dir := _art().path_join("isometric-interiors/Gridwright Isometric Interiors/")
	return JSON.parse_string(FileAccess.get_file_as_string(dir + "isometric.json"))["sprites"]


func _random_piece(l: RefCounted, rng: RandomNumberGenerator) -> Dictionary:
	var e: Dictionary = l.catalogue[rng.randi() % l.catalogue.size()]
	var faces: Array = e["faces"]
	var p := {
		"p": e["key"],
		"f": faces[rng.randi() % faces.size()] if not faces.is_empty() else "",
		"c": rng.randi_range(0, 9),
		"r": rng.randi_range(0, 9)
	}
	if l.kind(p) in ["wall", "hug"]:
		p["r" if p["f"] == "ne" else "c"] = 0
	return p


func _walkers_ok(h) -> String:
	for c in h.pets.critters:
		if c.z > 0.0 or not c.jump.is_empty():
			continue
		var cell := Vector2i(int(floor(c.pos.x)), int(floor(c.pos.y)))
		var p = h.person
		var seat_ok: bool = (
			c.id == "person"
			and (
				p.seated
				or p.phase in ["leaving", "entering"]
				or (p.arrive_left > 3.0 and cell == Vector2i(0, 7))
			)
		)
		var off: bool = cell.x < 1 or cell.y < 1 or cell.x >= Pets.COLS or cell.y >= Pets.ROWS
		if not seat_ok and (off or h.pets.blocked_cells.has(cell)):
			return "%s on the blocked cell %s" % [c.id, cell]
	return ""


func _decorate_logic() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	var l := _layout()
	_check(Pets.COLS == 10 and Pets.ROWS == 10, "the home is 10x10")
	_check(
		l.pieces.size() == Layout.DEFAULTS.size(), "every default piece stands (%d)" % l.pieces.size()
	)
	_check(l.reaches(l.blocked(), []), "the default layout reaches every spot from the door")
	var pets := Pets.new()
	pets.setup("", 3)
	pets.blocked_cells = l.blocked()
	_check(
		not pets.route(Vector2i(1, 7), Vector2i(9, 8)).is_empty(), "a path from the door to the far end"
	)

	var covered := {}
	for e in l.catalogue:
		for f in (e["faces"] if not e["faces"].is_empty() else [""]):
			covered[l.sprite_id({"p": e["key"], "f": f}).replace("%d", "1")] = true
	var missing: Array = []
	for key in l.index:
		var file: String = l.index[key]["file"]
		var skip := false
		for dir in ["/floors/", "/walls/", "/doors/", "/shadows/"]:
			skip = skip or dir in file
		if not skip and not covered.has(key):
			if not (key.ends_with("_f2") or key.ends_with("_f3") or key.ends_with("_f4")):
				missing.append(key)
	_check(missing.is_empty(), "every placeable sprite is in the catalogue: %s" % [missing])
	_check(l.walls_of("home").size() == 6 and l.floors_of("home").size() == 10, "6 wall styles and 10 floor styles of the interiors")

	_check(l.check({"p": "bookshelf", "f": "se", "c": 4, "r": 4}, null, []) == l.BUSY, "not on a spot")
	_check(
		l.check({"p": "side_table", "f": "", "c": 4, "r": 0}, null, []) == l.STAYS,
		"not on the desk"
	)
	_check(
		l.check({"p": "fireplace", "f": "ne", "c": 3, "r": 0}, null, []) == l.STAYS,
		"not over the board"
	)
	_check(
		l.check({"p": "painting", "f": "nw", "c": 0, "r": 4}, null, []) == l.STAYS,
		"not over the window"
	)
	_check(l.check({"p": "crate", "f": "", "c": 6, "r": 6}, null, []) == l.STAYS, "not on the bed")
	_check(
		l.check({"p": "crate", "f": "", "c": 0, "r": 7}, null, []) == l.STAYS, "not in the doorway"
	)
	_check(
		l.check({"p": "crate", "f": "", "c": 8, "r": 4}, null, [Vector2i(8, 4)]) == l.BUSY,
		"not where someone stands"
	)
	_check(
		l.check({"p": "rug_red", "f": "nesw", "c": 4, "r": 4}, null, []) == "",
		"a rug may lie on a spot"
	)
	_check(
		l.check({"p": "crate", "f": "", "c": 9, "r": 9}, null, []) == l.NO_ROOM,
		"not on another piece"
	)
	_check(
		l.check({"p": "dining_table", "f": "nwse", "c": 9, "r": 8}, null, []) == l.NO_ROOM,
		"not out of the room"
	)
	for c in [Vector2i(7, 2), Vector2i(8, 3), Vector2i(7, 4)]:
		l.place({"p": "crate", "f": "", "c": c.x, "r": c.y}, null, [])
	_check(
		l.check({"p": "crate", "f": "", "c": 6, "r": 3}, null, []) == l.SHUTS,
		"a spot is not shut off from the door"
	)
	l.reset([])
	_check(l.pieces.size() == Layout.DEFAULTS.size(), "reset brings the default back")

	for n in 30:
		var built := _layout()
		var accepted := 0
		for i in 80:
			var p := _random_piece(built, rng)
			if built.place(p, null, []) == "":
				accepted += 1
				_check(built.reaches(built.blocked(), []), "layout %d reaches every spot" % n)
		_check(accepted > 0, "random layout %d took some pieces" % n)

	_decorate_files(rng)
	_decorate_walk(2024)
	_decorate_regressions()
	_decorate_pointer()


func _decorate_files(rng: RandomNumberGenerator) -> void:
	var path := "user://soak_layout.json"
	var l := _layout()
	l.path = path
	l.persist = true
	for i in 60:
		l.place(_random_piece(l, rng), null, [])
	l.set_style("wall", "brick")
	l.set_style("floor", "marble")
	var back := _layout()
	back.path = path
	_check(back.load_file(), "a saved layout loads")
	_check(
		back.pieces == l.pieces and back.wall == "brick" and back.floor_style == "marble",
		"save and load round-trip (%d pieces)" % l.pieces.size()
	)
	var mine := FileAccess.open(path, FileAccess.WRITE)
	mine.store_string(
		JSON.stringify(
			{
				"v": 1,
				"wall": "plaster",
				"floor": "nope",
				"pieces":
				[
					{"p": "no_such_thing", "f": "", "c": 2, "r": 2},
					{"p": "round_table", "f": "", "c": 3, "r": 3},
					{"p": "sofa", "f": "up", "c": 4, "r": 3},
					{"p": "bookshelf", "f": "se", "c": 4, "r": 4},
					"junk",
				]
			}
		)
	)
	mine.close()
	var odd := _layout()
	odd.path = path
	_check(odd.load_file(), "a file with strangers in it still loads")
	_check(
		odd.pieces.size() == 1,
		"unknown, malformed and misplaced pieces are skipped, the rest kept (%d)" % odd.pieces.size()
	)
	_check(odd.wall == "plaster" and odd.floor_style == "oak", "a known style is kept, an unknown one is not")
	var junk := FileAccess.open(path, FileAccess.WRITE)
	junk.store_string("{not json")
	junk.close()
	var bad := _layout()
	bad.path = path
	_check(not bad.load_file() and bad.pieces.size() == Layout.DEFAULTS.size(), "unparsable: default")
	DirAccess.remove_absolute(path)
	var none := _layout()
	none.path = path
	_check(not none.load_file() and none.pieces.size() == Layout.DEFAULTS.size(), "missing: default")
	var quiet := _layout()
	quiet.path = path
	quiet.place({"p": "crate", "f": "", "c": 9, "r": 5}, null, [])
	_check(not FileAccess.file_exists(path), "a layout that is not kept writes nothing")

	var room := _room()
	var staged = load("res://home.gd").new()
	staged.setup(room, _art(), ["--demo"])
	_check(staged.layout.path == "" and not staged.layout.persist, "--demo keeps no layout")
	var told = load("res://home.gd").new()
	told.setup(room, _art(), ["--demo", "--layout", path])
	_check(told.layout.path == path and told.layout.persist, "--layout names the file")
	room.queue_free()


func _decorate_walk(seed_value: int, limit: int = 24000) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var room := _room(seed_value)
	var h = room.home
	var adds := 0
	var moves := 0
	var removes := 0
	var refused := 0
	var steps := 0
	while steps < limit:
		steps += 1
		if steps % 600 == 1:
			var items: Array = []
			for i in rng.randi_range(0, 4):
				items.append(_thing(i + 1, 1.0))
			h.set_data(_data(items))
			h.fake_hour = rng.randf_range(0.0, 24.0)
		if steps % 150 == 0:
			var l = h.layout
			var movable: Array = l.pieces
			var roll := rng.randf()
			var busy: Array = h.busy_cells()
			if roll < 0.55 or movable.is_empty():
				if l.place(_random_piece(l, rng), null, busy) == "":
					adds += 1
				else:
					refused += 1
			elif roll < 0.8:
				var pick: Dictionary = movable[rng.randi() % movable.size()]
				var to := _random_piece(l, rng)
				to["p"] = pick["p"]
				to["f"] = pick["f"]
				if l.kind(to) in ["wall", "hug"]:
					to["r" if to["f"] == "ne" else "c"] = 0
				if l.place(to, pick, busy) == "":
					moves += 1
				else:
					refused += 1
			else:
				l.remove(movable[rng.randi() % movable.size()])
				removes += 1
			h.apply_layout()
			_check(
				l.reaches(h.pets.blocked_cells, h.busy_cells()),
				"every spot stays reachable at step %d (seed %d): %s" % [steps, seed_value, _unreached(h)]
			)
		h.process(0.1)
		var why := _walkers_ok(h)
		if why != "":
			_check(false, "%s at step %d" % [why, steps])
			break
	if limit >= 24000:
		_check(adds > 20 and moves > 5 and removes > 5, "decorating happened: %d added, %d moved, %d removed, %d refused" % [adds, moves, removes, refused])
	print("decorate: %d steps, %d added, %d moved, %d removed, %d refused" % [steps, adds, moves, removes, refused])
	room.queue_free()


func _click_at(deco: Control, at: Vector2, button: int = MOUSE_BUTTON_LEFT) -> void:
	var move := InputEventMouseMotion.new()
	move.position = at
	deco.room_input(move)
	var press := InputEventMouseButton.new()
	press.position = at
	press.button_index = button
	press.pressed = true
	deco.room_input(press)


func _decorate_pointer() -> void:
	var room := _room()
	room.size = Vector2(800, 700)
	room._k = 2
	room._origin = Vector2(400, 150)
	var h = room.home
	var deco: Control = Decorate.new()
	deco.room = room
	deco.home = h
	var left := [false]
	deco.done.connect(func() -> void: left[0] = true)
	deco.enter()
	var cell := func(c: float, r: float) -> Vector2: return room._p(room._origin, c + 0.5, r + 0.5)
	var has := func(id: String, c: int, r: int, f: String = "") -> bool:
		return h.layout.pieces.any(func(p): return p["p"] == id and p["c"] == c and p["r"] == r and p["f"] == f)

	deco.pick("bookshelf:se")
	_click_at(deco, cell.call(2, 8))
	_check(has.call("bookshelf", 2, 8, "se"), "a click puts the chosen piece under the pointer")
	_check(deco.sel == "bookshelf", "the piece stays chosen for the next one")
	deco.key(KEY_R)
	_check(deco.face == "ne", "R turns the piece to the next side")
	_click_at(deco, cell.call(6, 3), MOUSE_BUTTON_RIGHT)
	_check(deco.sel == "", "a right click on the floor lets go of the piece")

	var s: Dictionary = room._sprite("bookshelf_se")
	var body: Vector2 = room._p(room._origin, 2, 8) - s["anchor"] + s["tex"].get_size() / 2.0
	_click_at(deco, body)
	_check(deco.held != null and deco.sel == "bookshelf", "a click on a placed piece picks it up")
	_click_at(deco, cell.call(6, 9))
	_check(has.call("bookshelf", 6, 9, "se") and deco.held == null, "a click moves it")
	_check(not has.call("bookshelf", 2, 8, "se"), "the old place is empty")

	var moved: Vector2 = room._p(room._origin, 6, 9) - s["anchor"] + s["tex"].get_size() / 2.0
	_click_at(deco, moved)
	deco.key(KEY_X)
	_check(not has.call("bookshelf", 6, 9, "se") and deco.held == null, "X removes the held piece")
	deco.pick("crate")
	_click_at(deco, cell.call(4, 4))
	_check(deco._message == "someone is there", "a refused click says why: %s" % deco._message)
	_check(not has.call("crate", 4, 4), "and puts nothing down")
	deco.sel = ""

	var desk: Dictionary = room._sprite("computer_desk_sw")
	_click_at(deco, room._p(room._origin, 4, 0) - desk["anchor"] + desk["tex"].get_size() / 2.0)
	_check(deco._message == "that one stays", "a fixed piece says it stays")

	deco.pick("painting:nw")
	_click_at(deco, cell.call(0, 3))
	_check(has.call("painting", 0, 3, "nw"), "a wall piece goes on the wall under the pointer")
	_click_at(deco, cell.call(8, 6), MOUSE_BUTTON_RIGHT)
	_check(deco.sel == "", "right click with a piece chosen only lets go of it")
	_check(deco.key(KEY_ESCAPE) and left[0], "Esc leaves the mode")
	room.queue_free()


# what `Layout.reaches` could not reach, for a failing message
func _unreached(h) -> String:
	var blocked: Dictionary = h.pets.blocked_cells
	var seen := {Layout.DOOR_FRONT: true}
	var queue: Array = [Layout.DOOR_FRONT]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_back()
		for d in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]:
			var n: Vector2i = cur + d
			if seen.has(n) or blocked.has(n) or n.x < 1 or n.y < 1:
				continue
			if n.x >= Pets.COLS or n.y >= Pets.ROWS:
				continue
			seen[n] = true
			queue.append(n)
	var out: Array = []
	for name in Pets.SPOTS:
		if not seen.has(Pets.SPOTS[name]["cell"]):
			out.append("spot " + name)
	for c in h.pets.critters:
		out.append("%s at %s mode %s jump %s" % [c.id, str(c.pos), c.mode, str(c.jump)])
	for t in h.pets.toys:
		out.append("toy at %s hop %s" % [str(t["pos"]), str(t["hop"])])
	return "; ".join(out) + " | busy " + str(h.busy_cells())


# seeds that once let a toy hop into a pocket no one can reach, and a small sweep besides
func _decorate_regressions() -> void:
	for s in [54, 10, 9]:
		_decorate_walk(s, 6000)
	for s in range(100, 106):
		_decorate_walk(s, 3000)


func _packs_logic() -> void:
	var l := _layout()
	_packs_catalogue(l)
	_packs_files()
	_packs_routes(l)
	_packs_meals()
	_packs_october()


func _file_ok(l: RefCounted, key: String) -> bool:
	if not l.index.has(key):
		return false
	var s: Dictionary = l.index[key]
	var dir: String = s.get("dir", _art().path_join("isometric-interiors/Gridwright Isometric Interiors/"))
	return FileAccess.file_exists(dir + str(s["file"]))


func _packs_catalogue(l: RefCounted) -> void:
	var count := {}
	for e in l.catalogue:
		count[e["tab"]] = int(count.get(e["tab"], 0)) + 1
		_check(e["tab"] in l.tabs, "%s is on a tab that exists" % e["key"])
		for f in (e["faces"] if not e["faces"].is_empty() else [""]):
			var p := {"p": e["key"], "f": f, "c": 0, "r": 0}
			var id: String = l.sprite_id(p)
			var frames: Array = [1, 2, 3, 4] if "%d" in id else [0]
			for n in frames:
				var key: String = id % n if n > 0 else id
				_check(_file_ok(l, key), "%s has its texture" % key)
			var fp: Vector2i = l.footprint(p)
			_check(fp.x >= 1 and fp.y >= 1 and fp.x <= 3 and fp.y <= 3, "%s has a sane footprint %s" % [id, fp])
			var key1: String = id % 1 if "%d" in id else id
			var sh := str(l.index[key1].get("shadow", ""))
			_check(sh == "" or _file_ok(l, sh), "%s has its shadow" % key1)
	for tab in ["castle", "mansion", "garden"]:
		_check(int(count.get(tab, 0)) > 10, "the %s tab has pieces (%s)" % [tab, count.get(tab, 0)])
	for style in l.walls:
		for part in Packs.WALL_PARTS:
			_check(_file_ok(l, "wall_%s%s" % [style, part]), "wall %s%s has its texture" % [style, part])
	for style in l.floors:
		for n in [1, 2]:
			_check(_file_ok(l, "floor_%s_0%d" % [style, n]), "floor %s has variant %d" % [style, n])
	var shown := []
	for tab in l.tabs:
		shown.append("%s %d pieces %d walls %d floors" % [tab, count.get(tab, 0), l.walls_of(tab).size(), l.floors_of(tab).size()])
	print("packs: ", "; ".join(shown))
	_check(count.get("home", 0) == 45, "the interiors still give 45 pieces (%s)" % count.get("home", 0))


func _write_layout(path: String, doc: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(doc))
	f.close()


func _read_layout(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _norm(doc: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(doc))


func _packs_files() -> void:
	var path := "user://soak_packs.json"
	var rows: Array = Layout.DEFAULTS.map(func(r): return {"p": r[0], "f": r[1], "c": r[2], "r": r[3]})
	var fixtures: Array = [
		{"v": 1, "wall": "wallpaper", "floor": "oak", "pieces": rows},
		{
			"v": 1,
			"wall": "brick",
			"floor": "marble",
			"pieces":
			[
				{"p": "bookshelf", "f": "se", "c": 9, "r": 3},
				{"p": "crate", "f": "", "c": 8, "r": 8},
				{"p": "rug_red", "f": "nesw", "c": 7, "r": 7},
				{"p": "painting", "f": "ne", "c": 8, "r": 0},
			],
		},
	]
	for doc in fixtures:
		_write_layout(path, doc)
		var l := _layout_of(Packs.extend(_interiors(), _art()), path, true)
		_check(l.pieces.size() == doc["pieces"].size() and l.wall == doc["wall"], "an old layout file loads whole (%d)" % l.pieces.size())
		for i in l.pieces.size():
			_check(l.pieces[i] == doc["pieces"][i], "old piece %s keeps its meaning" % doc["pieces"][i])
		l.save()
		_check(_read_layout(path) == _norm(doc), "an old layout file saves back as it was")
		var bare := _layout_of(_interiors(), path, true)
		bare.save()
		_check(_read_layout(path) == _norm(doc), "an old layout file saves back as it was without the packs")

	var held := {
		"v": 1,
		"wall": "castle.ashlar",
		"floor": "mansion.parquet",
		"pieces":
		[
			{"p": "castle.throne", "f": "se", "c": 5, "r": 3},
			{"p": "bookshelf", "f": "se", "c": 9, "r": 3},
			{"p": "mansion.cobweb", "f": "ne", "c": 8, "r": 0},
		],
	}
	_write_layout(path, held)
	var gone := _layout_of(_interiors(), path, true)
	_check(gone.pieces.size() == 1 and gone.pieces[0]["p"] == "bookshelf", "a piece of a missing pack loads without it")
	_check(gone.wall == "wallpaper" and gone.floor_style == "oak", "a style of a missing pack falls back")
	gone.place({"p": "crate", "f": "", "c": 8, "r": 8}, null, [])
	var after := _read_layout(path)
	_check(after["pieces"].size() == 4 and after["wall"] == "castle.ashlar" and after["floor"] == "mansion.parquet", "saving keeps what the missing packs held")
	gone.set_style("wall", "brick")
	_check(_read_layout(path)["wall"] == "brick", "choosing another wall replaces the kept one")
	var back := _layout_of(Packs.extend(_interiors(), _art()), path, true)
	_check(back.pieces.any(func(p): return p["p"] == "castle.throne"), "the pack's piece is back when the pack is")
	_write_layout(path, held)
	var reset := _layout_of(_interiors(), path, true)
	reset.reset([])
	_check(_read_layout(path)["pieces"].size() == Layout.DEFAULTS.size(), "reset forgets what the missing packs held")
	DirAccess.remove_absolute(path)

	var l := _layout()
	var before: Array = l.pieces.duplicate(true)
	l.guests = [{"p": "mansion.cobweb", "f": "ne", "c": 1, "r": 0, "fixed": true}]
	l.path = path
	l.persist = true
	l.save()
	_check(_read_layout(path)["pieces"].size() == before.size(), "guests are not saved")
	DirAccess.remove_absolute(path)


func _packs_routes(l: RefCounted) -> void:
	var big: Array = []
	for e in l.catalogue:
		for f in (e["faces"] if not e["faces"].is_empty() else [""]):
			var fp: Vector2i = l.footprint({"p": e["key"], "f": f, "c": 0, "r": 0})
			if e["kind"] == "floor" and fp.x * fp.y >= 3:
				big.append({"p": e["key"], "f": f, "c": 0, "r": 0})
	_check(big.size() >= 10, "there are big new pieces to try (%d)" % big.size())
	var pets := Pets.new()
	pets.setup("", 3)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var placed := 0
	var built := _layout()
	for i in 400:
		var p: Dictionary = big[rng.randi() % big.size()].duplicate()
		p["c"] = rng.randi_range(0, 9)
		p["r"] = rng.randi_range(0, 9)
		if built.place(p, null, []) == "":
			placed += 1
			pets.blocked_cells = built.blocked()
			for s in Pets.SPOTS.values().filter(func(s): return s["cell"] != Layout.DOOR_FRONT):
				_check(not pets.route(Layout.DOOR_FRONT, s["cell"]).is_empty(), "a route to %s with %s placed" % [s["cell"], p["p"]])
	_check(placed >= 4, "the big pieces went down (%d)" % placed)


func _packs_meals() -> void:
	var hours := {}
	for q in 96:
		var hour := q / 4.0
		var m := Guests.meal(hour)
		var want := -1
		if hour >= 7.0 and hour < 9.0:
			want = 0
		elif hour >= 12.0 and hour < 13.0:
			want = 1
		elif hour >= 18.0 and hour < 20.0:
			want = 2
		_check(m == want, "the meal at %s is %d, not %d" % [hour, want, m])
		hours[hour] = m
	_check(Guests.picks(20000, 2) == Guests.picks(20000, 2), "a meal's food is the same all meal")
	var seen := {}
	for day in 20:
		seen[str(Guests.picks(20000 + day, 0))] = true
	_check(seen.size() > 1, "the food changes from day to day")
	var room := _room()
	var h = room.home
	var guests := Guests.new()
	_check(h.layout.pieces.any(func(p): return p["p"] == "dining_table"), "the default layout has a dining table")
	for q in 96:
		var hour := q / 4.0
		h.fake_hour = hour
		var shown: int = guests.items(h).size()
		_check(shown == (1 if hours[hour] >= 0 else 0), "food at %s is %d" % [hour, shown])
	h.fake_hour = 19.0
	h.layout.pieces = h.layout.pieces.filter(func(p): return p["p"] != "dining_table")
	_check(guests.items(h).is_empty(), "no food with no table")
	h.layout.pieces.append({"p": "round_table", "f": "", "c": 6, "r": 7})
	_check(guests.items(h).size() == 1, "food on a round table too")
	room.art_dir = "/none"
	_check(guests.items(h).is_empty(), "no food without the pack")
	room.queue_free()


func _packs_october() -> void:
	var room := _room()
	var h = room.home
	var guests := Guests.new()
	var days := ["10-20", "10-24", "10-25", "10-28", "10-31", "11-01", "11-02"]
	for day in days:
		h.fake_day = day
		guests.update(h)
		var l = h.layout
		var inside: bool = day in ["10-25", "10-28", "10-31"]
		_check(l.guests.is_empty() == not inside, "guests on %s: %d" % [day, l.guests.size()])
		if inside:
			_check(l.guests.size() >= 2 and l.guests.size() <= 3, "two or three guests (%d)" % l.guests.size())
			var all: Array = l.guests.duplicate()
			for g in all:
				l.guests = all.filter(func(o): return not is_same(o, g))
				_check(l.check(g, null, h.busy_cells()) == "", "guest %s stands on a free cell" % [g])
				_check(not g["p"].begins_with("mansion.") or g["p"] in Guests.SEASONAL, "only the season's pieces")
			l.guests = all
			_check(l.reaches(l.blocked(), h.busy_cells()), "the guests shut no path")
			for g in all:
				if l.kind(g) == "floor":
					_check(h.pets.blocked_cells.has(Vector2i(g["c"], g["r"])), "pets walk round the guest at %s" % [g])
		else:
			_check(not h.pets.blocked_cells.is_empty(), "the room still has furniture to walk round")
	h.fake_day = "10-28"
	guests.update(h)
	var first: Array = h.layout.guests.duplicate(true)
	var again := Guests.new()
	h.layout.guests = []
	h.layout.version += 1
	again.update(h)
	_check(h.layout.guests == first, "the same week gives the same guests")
	var drawn := false
	for it in h.layout.rows()["furniture"] + h.layout.rows()["decor"]:
		drawn = drawn or str(it[0]).begins_with("mansion.")
	_check(drawn, "guests are drawn with the room")
	h.layout = _layout_of(_interiors())
	h.layout.guests = []
	var none := Guests.new()
	none.update(h)
	_check(h.layout.guests.is_empty(), "no guests without the mansion")
	room.queue_free()
