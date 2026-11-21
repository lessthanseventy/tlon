extends SceneTree

const Pets := preload("res://pets.gd")
const Settings := preload("res://settings.gd")
const Look := preload("res://look.gd")
const Person := preload("res://person.gd")
const Hacks := preload("res://hacks.gd")
const Layout := preload("res://layout.gd")
const Packs := preload("res://packs.gd")
const Guests := preload("res://guests.gd")
const Decorate := preload("res://decorate.gd")
const Closet := preload("res://closet.gd")
const Card := preload("res://card.gd")
const EggSoak := preload("res://soak_eggs.gd")
const GuestSoak := preload("res://soak_guests.gd")
const PetLifeSoak := preload("res://soak_petlife.gd")
const PetThingsSoak := preload("res://soak_petthings.gd")
const FormSoak := preload("res://soak_forms.gd")
const ChatSoak := preload("res://soak_chat.gd")
const SidebarSoak := preload("res://soak_sidebar.gd")
const ChoreSoak := preload("res://soak_chores.gd")
const PeopleSoak := preload("res://soak_people.gd")
const LocalSoak := preload("res://soak_local.gd")
const ArtSoak := preload("res://soak_art.gd")
const PackLooksSoak := preload("res://soak_looks.gd")
const TalkSoak := preload("res://soak_talk.gd")
const TelegramSoak := preload("res://soak_telegram.gd")
const WeatherSoak := preload("res://soak_weather.gd")
const AnticSoak := preload("res://soak_antics.gd")
const DriveSoak := preload("res://soak_drive.gd")
# stops a hang, not slow work: the soak takes about 7 minutes on a quiet machine and about twice
# that on a loaded one; the task wraps it in `timeout 1000`
const DEADLINE_MS := 900000

# what the stub of wttr.in (`?format=j1` on any path) answers
var wttr_code := 200
var wttr_body: Variant = {}
var _srv := TCPServer.new()
var _conns: Array = []
var _log: Array = []
var _fail_jot := false
# answers the stub's /bot... paths (Telegram's API) when set: (path, params) -> {code, body}
var bot := Callable()
# answers the people and the door routes when set: (method, path, body) -> {code, body} or null
var stub := Callable()
# holds the answers to reads of the home until `release_reads`, each built when the read arrives
var hold_reads := false
var _held: Array = []
var served := true
var _local
var _mode := ""
var _where := "start"
var _weather := {"weather": {"kind": "rain", "desc": "Light rain", "temp_c": 9}}
var _pets_batch: Dictionary = {}
var _failures: Array = []
var _state := _fresh_state()


class EngineErrors:
	extends Logger
	var seen: Array = []

	func _log_error(
		_function: String,
		file: String,
		line: int,
		code: String,
		rationale: String,
		_editor_notify: bool,
		error_type: int,
		_backtraces: Array
	) -> void:
		if error_type == Logger.ERROR_TYPE_SCRIPT or "triangulation failed" in rationale + code:
			var what := "%s (%s:%d)" % [rationale if rationale != "" else code, file, line]
			if not seen.has(what):
				seen.append(what)


var _errors := EngineErrors.new()


func _initialize() -> void:
	OS.add_logger(_errors)
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


func _fresh_state() -> Dictionary:
	return {
		"open":
		[
			{"id": 1, "kind": "todo", "text": "buy milk", "due_at": null, "every": null},
			{"id": 2, "kind": "todo", "text": "send photos", "due_at": null, "every": null},
		],
		"coming": [],
		"notes": ["a note"],
		"done_week": 0,
	}


# name -> what runs it, in the suite's order
func _sections() -> Array:
	return [
		["home", _home_section],
		["sim", _soak],
		["decorate", _decorate_logic],
		["packs", _packs_logic],
		["looks", _looks],
		["hacks", _hacks_draw],
		["eggs", func(): EggSoak.new(self).run()],
		["guests", func(): GuestSoak.new(self).run()],
		["petlife", func(): PetLifeSoak.new(self).run()],
		["antics", func(): AnticSoak.new(self).run()],
		["petthings", func(): await PetThingsSoak.new(self).run()],
		["cards", _cards],
		["routes", _on_main.bind(_routes)],
		["forms", _on_main.bind(func(main): await FormSoak.new(self, main).run())],
		["sidebar", _on_main.bind(func(main): await SidebarSoak.new(self, main).run())],
		["chores", _on_main.bind(func(main): await ChoreSoak.new(self, main).run())],
		["people", _on_main.bind(func(main): await PeopleSoak.new(self, main).people())],
		["door", _on_main.bind(func(main): await PeopleSoak.new(self, main).door())],
		["chat", _on_main.bind(func(main): await ChatSoak.new(self, main).run())],
		["local", _on_main.bind(func(main): await LocalSoak.new(self).over(main))],
		["talk", _on_main.bind(func(main): await TalkSoak.new(self).run(main))],
		["telegram", _on_main.bind(func(main): await TelegramSoak.new(self).run(main))],
		["weather", func(): await WeatherSoak.new(self).run()],
		["drive", func(): await DriveSoak.new(self).run()],
		["packlooks", _packlooks],
		["art", func(): ArtSoak.new(self).run()],
	]


func _packlooks() -> void:
	var packs := PackLooksSoak.new(self)
	packs.run()
	await packs.measure()


func _home_section() -> void:
	_voices_duo()
	_home_logic()
	_night_logic()


# the sections to run: those named after `--` in the suite's order, else all; none for `--list`
# or a name that is not one
func _wanted(all: Array) -> Array:
	var names: Array = all.map(func(e): return e[0])
	var args := Array(OS.get_cmdline_user_args())
	if "--list" in args:
		print("\n".join(names))
		print("SOAK LIST (%d sections)" % names.size())
		return []
	for a in args:
		if not a in names:
			print("unknown section '%s'; the sections are: %s" % [a, " ".join(names)])
			return []
	return all if args.is_empty() else all.filter(func(e): return e[0] in args)


func _run() -> void:
	var todo := _wanted(_sections())
	if todo.is_empty():
		quit(0 if "--list" in OS.get_cmdline_user_args() else 2)
		return
	var times: Array = []
	for entry in todo:
		_where = entry[0]
		_reset()
		var nodes := root.get_children()
		var files := _user_files()
		var began := Time.get_ticks_msec()
		await entry[1].call()
		await _leave(entry[0], nodes, files)
		var took := (Time.get_ticks_msec() - began) / 1000.0
		print("SECTION %s: %.1fs" % [entry[0], took])
		times.append([entry[0], took])
	_where = "end"
	for e in _errors.seen:
		_check(false, "the engine reported: " + e)
	for t in times:
		print("  %-10s %6.1fs" % [t[0], t[1]])
	print("SOAK took %.0fs of %.0fs" % [Time.get_ticks_msec() / 1000.0, DEADLINE_MS / 1000.0])
	print("SOAK %s (%d failures)" % ["OK" if _failures.is_empty() else "FAILED", _failures.size()])
	quit(0 if _failures.is_empty() else 1)


# every section starts from the same rng, stub server and flags
func _reset() -> void:
	seed(7)
	_state = _fresh_state()
	_log = []
	_conns = []
	_fail_jot = false
	_mode = ""
	wttr_code = 200
	wttr_body = {}
	bot = Callable()
	stub = Callable()
	hold_reads = false
	_held = []
	served = true
	_local = null
	_weather = {"weather": {"kind": "rain", "desc": "Light rain", "temp_c": 9}}
	_pets_batch = {}
	_srv.stop()


func _user_files() -> Array:
	return Array(DirAccess.get_files_at("user://"))


# a section leaves no node in the tree, no file in user://, no server listening
func _leave(name: String, nodes: Array, files: Array) -> void:
	await process_frame
	for n in root.get_children():
		if not nodes.has(n):
			_check(false, "%s left %s in the tree" % [name, n.name])
			n.free()
	for f in _user_files():
		if not files.has(f):
			_check(false, "%s left user://%s" % [name, f])
			DirAccess.remove_absolute("user://" + f)
	_srv.stop()
	OS.unset_environment("TLON_URL")


# the house over the stub server, as the routes need it; torn down after
func _on_main(body: Callable) -> void:
	await process_frame
	_srv.listen(0, "127.0.0.1")
	OS.set_environment("TLON_URL", "http://127.0.0.1:%d" % _srv.get_local_port())
	var main: Control = load("res://main.gd").new()
	main.pets_retry = 0.3
	main.pets_window = 30.0
	main.pets_every = 100.0
	main.pets_nudge = 0.3
	root.add_child(main)
	main._room.home.fake_hour = 15.0
	await _until(func(): return main._data["open"].size() == 2, "the house reads the stub's list")
	await body.call(main)
	main.queue_free()
	await process_frame


# until `done` holds, at most `secs`; a bound passed without it fails the soak, naming `what` and
# the line that asked
func _until(done: Callable, what: String = "", secs: float = 8.0) -> bool:
	var at := get_stack()
	var end := Time.get_ticks_msec() + int(secs * 1000.0)
	while not done.call():
		if Time.get_ticks_msec() >= end:
			var from := ""
			if at.size() > 1:
				from = " (%s:%d)" % [str(at[1]["source"]).get_file(), at[1]["line"]]
			var wanted := what if what != "" else _line_at(at)
			_check(false, "waited %ss and it did not come: %s%s" % [secs, wanted, from])
			return false
		await create_timer(0.02).timeout
	return true


# the source line that asked, for a wait that was given no name
func _line_at(stack: Array) -> String:
	if stack.size() < 2:
		return "a condition"
	var lines := FileAccess.get_file_as_string(str(stack[1]["source"])).split("\n")
	var n: int = int(stack[1]["line"]) - 1
	return str(lines[n]).strip_edges() if n < lines.size() else "a condition"


# a window in which nothing is awaited: the caller then checks that nothing happened
func _quiet(secs: float) -> void:
	await create_timer(secs).timeout


# the same window counted in the product's own frames, for what per-frame code would do
func _quiet_frames(n: int = 3) -> void:
	for _i in n:
		await process_frame


# the requests a node has in flight
func _requests(node: Node) -> int:
	return node.get_children().filter(
		func(c): return c is HTTPRequest and not c.is_queued_for_deletion()
	).size()


# until the house has had no request in flight over two frames in a row: what it asked has been
# answered and applied. The local list answers by call_deferred, which a frame flushes.
func _answered(main: Control) -> bool:
	var end := Time.get_ticks_msec() + 8000
	var idle := 0
	while idle < 2:
		await process_frame
		idle = idle + 1 if _requests(main._backend) == 0 else 0
		if Time.get_ticks_msec() >= end:
			_check(false, "waited 8s and the house's requests were still in flight")
			return false
	return true


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


func _routes(main: Control) -> void:
	await _until(func(): return _count("/api/home/pets") >= 3, "three asks for the pets' lines")
	_check(
		main._data["open"].size() == 2,
		"GET /api/home filled the room (%d open)" % main._data["open"].size()
	)
	var asks := _count("/api/home/pets")
	_check(asks >= 3, "an empty batch is asked again at the short interval (%d asks)" % asks)
	_check(not main._room.home.has_voices(), "{} leaves the pets with nothing served")
	_pets_batch = {"Nina": {"muse": ["served line"]}, "duo": []}
	await _until(func(): return main._room.home.has_voices(), "the next ask picks the batch up")
	_check(main._room.home.has_voices(), "the next ask picks the batch up")
	asks = _count("/api/home/pets")
	_check(
		main._pets_timer.time_left > 90.0 and _count("/api/home/pets") == asks,
		"a held batch is asked at the long interval"
	)
	_pets_batch = {}
	main._pets_ask()
	await _until(
		func(): return _count("/api/home/pets") > asks and not main._pets_busy,
		"the empty answer to the ask"
	)
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
	await _until(func(): return _count("/api/home/pets") > asks, "the ask after the list changed")
	await _until(
		func():
			return (
				main._pets_nudged.is_stopped()
				and not main._pets_busy
				and _requests(main._backend) == 0
			),
		"the list's changes applied and the nudged asks answered"
	)
	asks = _count("/api/home/pets")
	await _quiet(0.6)
	_check(_count("/api/home/pets") == asks, "the open list settling asks no more")
	var first := _last_query("/api/home/pets")
	_check(
		first
		== (
			"nina_name=Nina&nina_species=cat&nina_personality=sassy"
			+ "&argos_name=Rocky&argos_species=dog&argos_personality=sweet"
		),
		"the pets ask names, animals and ways (%s)" % first
	)
	var settings = main._room.home.settings
	asks = _count("/api/home/pets")
	settings.put("cat", "Mimi Q")
	settings.put("pet1", "fox_red")
	settings.put("pet2_personality", "bold")
	await _until(func(): return _count("/api/home/pets") > asks, "the ask after the settings changed")
	await _quiet(0.6)
	_check(_count("/api/home/pets") == asks + 1, "changes made together ask once more")
	var again := _last_query("/api/home/pets")
	_check(
		again
		== (
			"nina_name=Mimi%20Q&nina_species=fox&nina_personality=sassy"
			+ "&argos_name=Rocky&argos_species=dog&argos_personality=bold"
		),
		"the chosen values are sent, encoded (%s)" % again
	)
	_check(Settings.pets("Nina and Argos") == "Mimi Q and Rocky", "the chosen name is what is shown")
	settings.put("pet2", "none")
	await _until(func(): return _count("/api/home/pets") > asks + 1, "the ask with no second pet")
	_check(
		not "argos_" in _last_query("/api/home/pets"), "a pet that is none sends nothing"
	)
	settings.put("pet2", "dog_golden")
	settings.put("cat", "")
	settings.put("pet1", "cat_black")
	settings.put("pet2_personality", "sweet")
	await _until(func(): return _count("/api/home/pets") >= asks + 3, "each change was asked about")
	_check(_count("/api/home/pets") >= asks + 3, "each change was asked about")
	_check(_seen("POST", "/api/home/1/done"), "done posted")
	_check(main._data["open"].size() == 1, "done removed the thing")
	main._on_act(2, "hour")
	await _until(func(): return main._data["coming"].size() == 1, "later moved the thing to coming")
	_check(_seen("POST", "/api/home/2/later", "hour"), "later posted with until=hour")
	_check(
		main._data["open"].is_empty() and main._data["coming"].size() == 1,
		"later moved the thing to coming"
	)
	main._open_add()
	main._sidebar.jot.open("buy stamps")
	var jot = main._sidebar.jot
	main._send_jot("buy stamps")
	await _until(func(): return jot._kept.visible, "the notepad shows what was kept")
	_check(_seen("POST", "/api/home", "buy stamps"), "jot posted")
	_check(
		jot._kept.visible and jot._said.text == "to do: buy stamps" and not jot._change.visible,
		"a reply with no row is read back as it is, with OK only: '%s'" % jot._said.text
	)
	jot.accepted.emit()
	_check(main._sidebar.view == "home", "OK is back to Home")
	main._open_add()
	jot.open("keep: hang the picture")
	main._send_jot("keep: hang the picture")
	await _until(func(): return jot._kept.visible, "the notepad shows what was kept")
	_check(
		jot._kept.visible and jot._summary.text == "To-do" and jot._said.text == "hang the picture" and jot._change.visible,
		"the row the answer carries is what it was read as: '%s' '%s'" % [jot._summary.text, jot._said.text]
	)
	jot.change_wanted.emit()
	await _until(func(): return main._sidebar.view == "edit", "Change opens the form")
	_check(
		main._sidebar.view == "edit" and main._sidebar.form._text.text == "hang the picture",
		"Change opens that thing's form, prefilled"
	)
	main._sidebar.back()
	main._open_add()
	jot.open("race: paint the door")
	main._send_jot("race: paint the door")
	await _until(func(): return jot._kept.visible, "the notepad shows what was kept")
	_check(
		jot._summary.text == "To-do" and jot._said.text == "paint the door" and jot._change.visible,
		"another thing appearing at the same time does not change what is read back: '%s'" % jot._said.text
	)
	jot.accepted.emit()
	main._open_add()
	jot.open("note: wifi is on the fridge")
	main._send_jot("note: wifi is on the fridge")
	await _until(func(): return jot._kept.visible, "the notepad shows what was kept")
	_check(
		jot._summary.text == "Note" and jot._said.text == "wifi is on the fridge",
		"a note's row, which has no kind, is read as a note: '%s' '%s'" % [jot._summary.text, jot._said.text]
	)
	jot.accepted.emit()
	main._open_add()
	_fail_jot = true
	main._open_add()
	main._sidebar.jot.open("keep me")
	main._send_jot("keep me")
	await _until(func(): return "not kept" in main._sidebar.jot._hint.text, "the failed jot says so")
	_check(
		main._sidebar.jot.visible and main._sidebar.jot._edit.text == "keep me",
		"failed jot keeps its text in the field"
	)
	_check("not kept" in main._sidebar.jot._hint.text, "failed jot says so: '%s'" % main._sidebar.jot._hint.text)
	var home = main._room.home
	await _until(
		func(): return is_equal_approx(home.rhythm.list_at, 9.25), "the house reads home_list_at from /api/settings"
	)
	_check(
		is_equal_approx(home.rhythm.list_at, 9.25),
		"home_list_at read from /api/settings (%s)" % home.rhythm.list_at
	)
	_weather = {"weather": {"kind": "snow", "desc": "Light snow", "temp_c": -2}}
	main._watch_weather()
	await _until(func(): return home.weather == "snow", "the weather arrives from /api/office")
	_check(
		home.weather == "snow" and home.weather_desc == "Light snow",
		"the weather comes from /api/office"
	)
	_weather = {"weather": {"kind": "rain", "desc": "Light rain", "temp_c": 9}}


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
		if l[0] == "GET" and l[1].get_slice("?", 0) == path:
			n += 1
	return n


func _voices_duo() -> void:
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
	var query := path.get_slice("?", 1) if "?" in path else ""
	_log.append([method, path, body, query])
	var code := 200
	var out: Variant = {}
	var parsed: Variant = JSON.parse_string(body) if body != "" else {}
	var mine: Variant = stub.call(method, path, parsed) if stub.is_valid() else null
	if mine is Dictionary:
		code = mine["code"]
		out = mine["body"]
	elif bot.is_valid() and path.begins_with("/bot"):
		var answer: Dictionary = bot.call(path, parsed)
		code = answer["code"]
		out = answer["body"]
	elif method == "GET" and path.ends_with("?format=j1"):
		code = wttr_code
		out = wttr_body
	elif method == "GET" and path == "/api/home":
		out = _state
	elif method == "GET" and path.get_slice("?", 0) == "/api/home/pets":
		out = _pets_batch
	elif method == "GET" and path == "/api/office":
		out = _weather
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
		if _state.has("note_rows"):
			_state["note_rows"] = _state["note_rows"].filter(func(t): return int(t["id"]) != id)
		var piles: Array = _state.get("people", []).duplicate()
		if _state.has("door"):
			piles.append(_state["door"])
		for pile in piles:
			pile["notes"] = pile["notes"].filter(func(n): return int(n["id"]) != id)
		out = {"id": id, "text": "x"}
	elif method == "POST" and (path == "/api/home/add" or path.get_slice("/", 4) in ["edit", "plan", "revive", "answer"]):
		if _mode == "400":
			code = 400
			out = {"error": "at is more than a year back"}
		elif _mode == "404":
			code = 404
		else:
			out = {"id": 99, "text": str(parsed.get("text", "")), "reply": "ok"}
	elif method == "POST" and path.begins_with("/api/home/proposals/"):
		var id := int(path.get_slice("/", 4))
		var proposals: Array = _state.get("proposals", [])
		for prop in proposals:
			if int(prop["id"]) == id and path.ends_with("/take"):
				_state["open"].append({"id": 900 + id, "kind": "todo", "text": prop["text"], "due_at": null})
		_state["proposals"] = proposals.filter(func(x): return int(x["id"]) != id)
		out = {"id": id}
	elif method == "POST" and path == "/api/home":
		if _fail_jot:
			code = 404
		else:
			var said := str(parsed.get("text", ""))
			out = {"reply": "to do: " + said, "row": null}
			if said.begins_with("keep: ") or said.begins_with("race: "):
				if said.begins_with("race: "):
					_state["open"].append(
						{"id": 959, "kind": "todo", "text": "from elsewhere", "due_at": null, "every": null}
					)
				var made := {"id": 960, "kind": "todo", "text": said.get_slice(": ", 1), "due_at": null, "every": null}
				_state["open"].append(made)
				out["row"] = made
			elif said.begins_with("note: "):
				var made := {"id": 961, "text": said.get_slice(": ", 1)}
				_state["note_rows"] = _state.get("note_rows", []) + [made]
				out["row"] = made
	else:
		code = 404
	var payload := JSON.stringify(out).to_utf8_buffer()
	var head := (
		"HTTP/1.1 %d X\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n"
		% [code, payload.size()]
	)
	if hold_reads and method == "GET" and path == "/api/home":
		_held.append([p, head.to_utf8_buffer() + payload])
		return
	p.put_data(head.to_utf8_buffer() + payload)
	p.disconnect_from_host()


func release_reads() -> void:
	for held in _held:
		held[0].put_data(held[1])
		held[0].disconnect_from_host()
	_held = []


func _iso(days_ago: float) -> String:
	var at := Time.get_unix_time_from_system() - days_ago * 86400.0
	return Time.get_datetime_string_from_unix_time(int(at)) + "Z"


func _art() -> String:
	if OS.has_environment("TLON_ART_DIR"):
		return OS.get_environment("TLON_ART_DIR")
	return OS.get_environment("HOME").path_join("projects/thatch/packs/x")


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
	h.petlife.setup(h)
	h.outside.setup(h)
	h.finds.setup(h)
	h.quirks.setup(h)
	h.delights.setup(h)
	h.antics.setup(h)
	h.antics.quiet = true
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
	h.open_item(1)
	_check(h.knock.id == -1 and h._slots.has(1), "opening the item puts the sticky back")
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
	if not room.art_found:
		print("cards: no art, hit areas not tested")
		room.queue_free()
		return
	var keys := ["cal", "jar", "window", "clock", "plant", "board"]
	await _until(
		func(): return keys.all(func(k): return h._hits.any(func(x): return x["key"] == k)),
		"the cards' hit areas are drawn"
	)
	var pts := _hit_points(h)
	var empty: Vector2 = pts[""][pts[""].size() - 1]
	var things := {
		"calendar": "cal", "jar": "jar", "weather": "window", "clock": "clock",
		"plant": "plant", "board": "board",
	}
	for kind in things:
		var key: String = things[kind]
		_check(pts.has(key), "%s has a hit area" % kind)
		if not pts.has(key):
			continue
		if kind == "plant":
			var seen: Array = []
			var watch := func(k: String, a: Variant) -> void: seen.append([k, a])
			h.viewed.connect(watch)
			h.click(pts[key][0])
			h.viewed.disconnect(watch)
			_check(seen == [["item", 1]], "with a watering chore the plant opens its item view: %s" % str(seen))
			continue
		h.click(pts[key][0])
		_check(h.card.kind == kind and h.card.key == key, "a click on %s opens its view" % key)
		_check(not h.card_blocks().is_empty(), "the %s view has something to say" % kind)
		h.close_card()
		_check(not h.card.is_open(), "going back closes the %s view" % kind)
	print("cards: %d things open their view from their hit area" % things.size())
	_check(pts.has("tv"), "the TV has a hit area")
	if pts.has("tv"):
		h.click(pts["tv"][0])
		_check(h.tv.on and not h.card.is_open(), "a click turns the TV on and opens no view")
		h.click(pts["tv"][0])
		_check(not h.tv.on and not h.card.is_open(), "a second click turns it off")
	h.click(pts["note:0"][0] if pts.has("note:0") else pts["board"][0])
	_check(h.card.kind == "board", "a note opens the board view")
	h.close_card()
	h.click(pts["cal"][0])
	h.click(pts["jar"][0])
	_check(h.card.kind == "jar", "another thing replaces the view: one at a time (%s)" % h.card.kind)
	h.close_card()
	h.decorating = true
	h.click(pts["cal"][0])
	_check(not h.card.is_open(), "no view while decorating")
	h.decorating = false
	h.rhythm.kind = "home"
	h.click(pts["cal"][0])
	_check(h.card.kind == "calendar", "a slip never stops a click on a thing")
	h.rhythm.dismiss()
	h.close_card()
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
	h.settings.forced["degrees"] = "c"
	_check("Light rain" in str(h.card_blocks()) and "9°C" in str(h.card_blocks()), "the weather in words")
	h.settings.forced["degrees"] = "f"
	_check("48°F" in str(h.card_blocks()), "the weather in Fahrenheit")
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
	await _until(func(): return drawn.size() >= Hacks.NAMES.size(), "the canvas draws every hack")
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
	_check(Pets.COLS == 11 and Pets.ROWS == 11, "the home is 11x11")
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
		l.check({"p": "crate", "f": "", "c": 10, "r": 10}, null, []) == l.NO_ROOM,
		"not on another piece"
	)
	_check(
		l.check({"p": "dining_table", "f": "nwse", "c": 10, "r": 8}, null, []) == l.NO_ROOM,
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
				"offered": ["laundry_basket", "photo_frame"],
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
		if e["tab"] == "pets" or e["key"] in ["laundry_basket", "photo_frame"]:
			continue
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
	_check(count.get("home", 0) == 47, "the interiors still give 45 pieces, the laundry basket and the photo frame (%s)" % count.get("home", 0))


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
		doc["offered"] = Layout.NEWER.duplicate()
		_write_layout(path, doc)
		var l := _layout_of(Packs.extend(_interiors(), _art()), path, true)
		_check(l.pieces.size() == doc["pieces"].size() and l.wall == doc["wall"], "an old layout file loads whole (%d)" % l.pieces.size())
		for i in l.pieces.size():
			_check(l.pieces[i] == doc["pieces"][i], "old piece %s keeps its meaning" % doc["pieces"][i])
		l.save()
		var kept := _norm(doc)
		kept["v"] = float(Layout.SAVED)
		_check(_read_layout(path) == kept, "an old layout file saves back as it was, in the current version")
		var bare := _layout_of(_interiors(), path, true)
		bare.save()
		_check(_read_layout(path) == kept, "an old layout file saves back as it was without the packs")

	var held := {
		"v": 1,
		"offered": ["laundry_basket", "photo_frame"],
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


func _last_query(path: String) -> String:
	for i in range(_log.size() - 1, -1, -1):
		if _log[i][0] == "GET" and _log[i][1].get_slice("?", 0) == path:
			return _log[i][3]
	return ""
