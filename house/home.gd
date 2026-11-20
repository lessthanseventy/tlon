extends RefCounted

signal acted(id: int, what: String)
# a click on a thing that has a view of its own: "item" (id), "open" (the desk's list), "add"
# (the notepad), "closet", "chat" or "pet" (id); things with blocks open through `card`
signal viewed(kind: String, arg: Variant)

const Props := preload("res://props.gd")
const Pets := preload("res://pets.gd")
const Look := preload("res://look.gd")
const Person := preload("res://person.gd")
const Tv := preload("res://tv.gd")
const View := preload("res://view.gd")
const Focus := preload("res://focus.gd")
const Jar := preload("res://jar.gd")
const Knock := preload("res://knock.gd")
const Rhythm := preload("res://rhythm.gd")
const Layout := preload("res://layout.gd")
const Card := preload("res://card.gd")
const Sound := preload("res://sound.gd")
const Eggs := preload("res://eggs.gd")
const Petlife := preload("res://petlife.gd")
const Hearth := preload("res://hearth.gd")
const Outside := preload("res://outside.gd")
const Finds := preload("res://finds.gd")
const Secrets := preload("res://secrets.gd")
const Quirks := preload("res://quirks.gd")
const Delights := preload("res://delights.gd")
const Antics := preload("res://antics.gd")
const Things := preload("res://things.gd")
const Sure := preload("res://sure.gd")
const Settings := preload("res://settings.gd")
const Forecast := preload("res://forecast.gd")
const Chat := preload("res://chat.gd")
const Looks := preload("res://looks.gd")
const Glow := preload("res://glow.gd")
const Spells := preload("res://spells.gd")
const Fonts := preload("res://fonts.gd")
const When := preload("res://when.gd")
const Chores := preload("res://chores.gd")
const PetThings := preload("res://pet_things.gd")

const LAYOUT_STORE := "user://house_layout.json"
const WALL_H := 48
const COLS := Pets.COLS
const ROWS := Pets.ROWS
const DAYS := ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
const DAYS_FULL := ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
const CARD_KEYS := {
	"cal": "calendar",
	"jar": "jar",
	"window": "weather",
	"clock": "clock",
	"plant": "plant",
	"board": "board",
	"more": "board",
	"mousehole": "found",
	"furn:bookshelf": "book",
	"furn:fireplace": "fireplace",
	"furn:piano": "piano",
	"globe": "globe",
}
const NAMES := {
	"cal": "the calendar",
	"window": "the window",
	"clock": "the clock",
	"plant": "the plant",
	"board": "the board",
	"wardrobe": "the closet  (C)",
	"pad": "jot something  (N)",
	"furn:bookshelf": "the bookshelf",
	"furn:fireplace": "the fireplace",
	"furn:piano": "the piano",
	"globe": "the snow globe",
	"mousehole": "a mouse hole",
}
const NAME_STAYS := 2.0
const FURN_KEYS := ["piano", "fireplace", "bookshelf"]
const NOTES_PER_PAGE := 5
const SKY_WORDS := {
	"clear": "a clear sky",
	"partly": "some cloud, some sun",
	"cloudy": "overcast, the cloud low and grey",
	"fog": "fog, the skyline gone",
	"rain": "rain on the glass",
	"storm": "a storm, rain and lightning",
	"snow": "snow coming down",
}
const MONTH_DAYS := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
const TODO_COLOR := Color("f6e27a")
const REMINDER_COLOR := Color("f2a6b3")
const CONFETTI := [
	Color("e8b86d"), Color("d9534f"), Color("4f8fd9"), Color("5fb37a"), Color("f2a6b3")
]
const BOARD := {"s": 33.0, "h": 13.0, "w": 30.0, "hh": 31.0}
const STACK := Vector3(5.62, 0.55, 17.0)
const MUG := Vector3(4.27, 0.33, 17.0)
const PAD := Vector3(5.3, 0.88, 17.0)
const PHONE := Vector3(4.62, 0.58, 17.0)
# wall slots (plane 1 = the north-east wall, s along it, h up) and the desk top
const SLOTS := [
	{"s": 69.0, "h": 19.0, "rot": 0.15},
	{"s": 80.0, "h": 22.0, "rot": -0.1},
	{"s": 88.0, "h": 39.0, "rot": 0.08},
	{"s": 98.0, "h": 35.0, "rot": -0.12},
	{"s": 90.0, "h": 29.5, "rot": 0.18},
	{"s": 106.0, "h": 40.0, "rot": 0.1},
	{"desk": Vector2(4.52, 0.8), "rot": 0.35},
]
const NOTE_SPOTS := {
	1: [Vector2(15, 16)],
	2: [Vector2(9, 18), Vector2(21, 12)],
	3: [Vector2(9, 21), Vector2(21, 22), Vector2(15, 9)],
	4: [Vector2(8, 22), Vector2(22, 23), Vector2(9, 9), Vector2(22, 10)],
}
const NOTE_TILT := [-0.1, 0.07, 0.05, -0.07]

# a scripted run (the soak) keeps nothing in user://, whatever its arguments
static var scripted := false

# set by `setup`: nothing is read from or kept in user://
var staged := false
# set by `setup`: `--drive`, a live run that keeps its files in user://
var drive := false
var keeps := false

var room: Control
var pets := Pets.new()
var look := Look.new()
var person := Person.new()
var tv := Tv.new()
var focus := Focus.new()
var jar := Jar.new()
var knock := Knock.new()
var sound := Sound.new()
var eggs := Eggs.new()
var petlife := Petlife.new()
var hearth := Hearth.new()
var outside := Outside.new()
var spells := Spells.new()
var finds := Finds.new()
var secrets := Secrets.new()
var quirks := Quirks.new()
var delights := Delights.new()
var antics := Antics.new()
var rhythm := Rhythm.new()
var layout := Layout.new()
var perk_left := 0.0
var water_left := 0.0
var fake_day := ""
var done_week := 0
var weather_desc := ""
var temp_c: Variant = null
var forecast: Array = []
# today's and tomorrow's meetings as the server gives them; [] over the local list
var meetings: Array = []
var reply_text := ""
var reply_left := 0.0
var ring_ids: Array = []
var _rang := {}
var _rang_new := false
var _watching := false
var _night_next := 120.0
var open: Array = []
var coming: Array = []
var notes: Array = []
var weather := "clear"
var forced_weather := ""
var fake_hour := -1.0
var say_who := ""
var say_occasion := "pet"
var force_bat := false
var jot_open := false
var closet_open := false
var decorating := false
var card := Card.new()
var things := Things.new()
var sure := Sure.new()
var settings := Settings.new()
var chat := Chat.new()
var knobs := {}
var form_open := false
var done: Variant = null
var show_note := -1
var window_frame := PackedVector2Array()

var _t := 0.0
var _o := Vector2.ZERO
var _k := 2
var _env := {}
var _slots := {}
var _crumples: Array = []
var _confetti: Array = []
var _hits: Array = []
var _used := {}
var _images := {}
var _hover := ""
var _hover_at := Vector2.ZERO
var selected := ""
var _hover_time := 0.0
var _bin_balls := 0
var _chores := {}
var _chore_sig: Array = []
var _moment := {}
var _next_text := ""
var _had_open := false
var _seen_data := false
var _scripted := {}
var _say_done := false
var _arg_duo := false
var _deep := 0.0
var _arg_antic := ["", "", 0.0]
var _ringing := 0
var _arg_jar := -1
var _arg_drop := false
var _arg_knocked := -1
var _arg_beat := ""
var _slip_delay := -1.0
var _slip_kind := ""
var _t_args := 0.0
var _cal := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _arg_menu := -1
var _arg_then := ""
var _arg_card := ""
var _arg_reply := ""
var _arg_ring := -1
var _rung: Array = []
var _attention := false


func setup(canvas: Control, art_dir: String, args: Array) -> void:
	room = canvas
	var seed_value := -1
	var nina_at := ""
	var argos_at := ""
	var layout_file := ""
	var look_spec := ""
	for i in args.size():
		var next: String = args[i + 1] if i + 1 < args.size() else ""
		match args[i]:
			"--at":
				set_at(next)
			"--weather":
				forced_weather = next
			"--say":
				say_who = next
			"--occasion":
				say_occasion = next
			"--duo":
				_arg_duo = true
			"--nina":
				nina_at = next
			"--argos":
				argos_at = next
			"--pets":
				settings.forced.merge(pets_spec(next), true)
			"--note":
				show_note = int(next)
			"--seed":
				seed_value = int(next)
			"--bat":
				force_bat = true
			"--hover":
				_scripted["hover"] = _point(next)
			"--click":
				_scripted["click"] = _point(next)
			"--hack":
				tv.hacks.force(next)
			"--tv":
				tv.force_on(next == "on")
			"--jar":
				_arg_jar = int(next)
			"--jar-drop":
				_arg_drop = true
			"--knocked":
				_arg_knocked = int(next)
			"--egg":
				eggs.forced = Array(next.split(",", false))
			"--antic":
				_arg_antic[0] = next
			"--antic-who":
				_arg_antic[1] = next
			"--antic-t":
				_arg_antic[2] = float(next)
			"--laser":
				eggs.laser_at = _point(next)
				eggs.laser_pin = true
				eggs.laser_on = true
			"--widget":
				settings.forced["widget"] = true
			"--plain", "--looks":
				var wanted := next.split(",") if args[i] == "--looks" else PackedStringArray()
				for key in Looks.KEYS:
					settings.forced[key] = key in wanted
			"--local":
				settings.forced["where"] = "local"
			"--birthday":
				finds.birthday_forced = true
			"--homecoming":
				_arg_beat = "home"
			"--morning":
				_arg_beat = "morning"
			"--date":
				fake_day = next
			"--person":
				person.forced = next
			"--then":
				_arg_then = next
			"--card":
				_arg_card = next
			"--menu":
				_arg_menu = int(next)
			"--reply":
				_arg_reply = next
			"--ring":
				_arg_ring = int(next)
			"--layout":
				layout_file = next
			"--look":
				look_spec = next
			"--now":
				var parts := next.split(":")
				focus.persist = false
				focus.id = int(parts[0])
				focus.minutes = int(parts[1]) if parts.size() > 1 else 25
				if parts.size() > 2:
					focus.started = (
						Time.get_unix_time_from_system() - float(parts[2]) * focus.minutes * 60.0
					)
	if "--shot" in args and seed_value < 0:
		seed_value = 7
	drive = "--drive" in args
	if drive and "--demo" not in args:
		settings.forced["where"] = "local"
	staged = scripted or "--demo" in args or "--shot" in args or "--local" in args or drive
	keeps = not staged or drive
	settings.setup(keeps)
	Looks.setup(art_dir, settings)
	Fonts.apply()
	chat.setup(keeps)
	pets.on_say = _pet_said
	if "--demo" in args:
		focus.persist = false
	elif focus.persist:
		focus.load_saved()
	things.setup(self)
	knock.persist = keeps
	rhythm.persist = keeps
	rhythm.load_days()
	if layout_file == "" and keeps:
		layout_file = LAYOUT_STORE
	layout.setup(room._index, room.art_found, layout_file, layout_file != "")
	pets.blocked_cells = layout.blocked()
	pets.is_night = _env_now()["day"] < 0.15
	pets.kinds["nina"] = Pets.kind_of(settings.value("pet1"), "nina")
	pets.kinds["argos"] = Pets.kind_of(settings.value("pet2"), "argos")
	pets.personalities["nina"] = Pets.persona_of(settings.value("pet1_personality"), "nina")
	pets.personalities["argos"] = Pets.persona_of(settings.value("pet2_personality"), "argos")
	pets.chatter = Pets.CHATTER.get(str(settings.value("pet_chatter")), 1.0)
	pets.setup(art_dir, seed_value)
	settings.changed.connect(_on_setting)
	look.setup(art_dir)
	look.stage(look_spec)
	person.setup(pets, look, seed_value)
	tv.setup(seed_value)
	knock.setup(seed_value)
	sound.setup(room, keeps, art_dir)
	eggs.setup(self, seed_value, keeps)
	petlife.setup(self)
	pets.life_options = petlife.options
	petlife.sync()
	hearth.setup(self)
	outside.setup(self)
	finds.setup(self)
	secrets.setup(self)
	quirks.setup(self)
	delights.setup(self)
	antics.setup(self)
	person.snap()
	if "--shot" in args:
		pets.freeze = true
	if pets.is_night:
		pets.place(pets.critter("nina"), "desk", "sleep")
		pets.place(pets.critter("argos"), "bed", "sleep")
		petlife.night_place()
	_place_arg("nina", nina_at)
	_place_arg("argos", argos_at)


# the cells somebody or something rests on or is headed for: furniture never goes there
func busy_cells() -> Array:
	var out: Array = []
	for c in pets.critters:
		if c.away:
			continue
		var targets: Array = [c.pos]
		if not c.jump.is_empty():
			targets.append(c.jump["to"])
		for at in targets:
			out.append(Vector2i(int(floor(at.x)), int(floor(at.y))))
	for t in pets.toys:
		out.append(pets._cell_of(t["pos"]))
		if not (t["hop"] as Dictionary).is_empty():
			out.append(pets._cell_of(t["hop"]["to"]))
	return out.filter(func(cell): return cell.x >= 1 and cell.y >= 1)


# the furniture changed: the walkers' grid follows
func apply_layout() -> void:
	pets.blocked_cells = layout.blocked()
	pets.reroute()


func set_at(text: String) -> void:
	var hm := text.split(":")
	fake_hour = float(hm[0]) + (float(hm[1]) / 60.0 if hm.size() > 1 else 0.0)


# `cat=KIND,dog=KIND` as the settings keys it stands for
func pets_spec(text: String) -> Dictionary:
	var out := {}
	for p in text.split(",", false):
		out["pet1" if p.get_slice("=", 0) == "cat" else "pet2"] = p.get_slice("=", 1)
	return out


func _point(text: String) -> Vector2:
	var xy := text.split(",")
	return Vector2(float(xy[0]), float(xy[1]))


func _place_arg(id: String, spec: String) -> void:
	if spec == "":
		return
	var parts := spec.split(":")
	var mode: String = (
		parts[1] if parts.size() > 1 else ("sleep" if parts[0] in ["sofa", "bed"] else "sit")
	)
	if pets.spots.has(parts[0]):
		var c: Pets.Critter = pets.critter(id)
		pets.place(c, parts[0], "sit" if mode in ["walk", "run"] else mode)
		if mode in ["walk", "run"]:
			c.anim = mode
		elif pets.spots[parts[0]].has("use") and mode == "sit":
			pets.arrive_at(c, parts[0])


func _on_setting(key: String) -> void:
	if key == "font":
		Fonts.apply()
	if key == "pet_chatter":
		pets.chatter = Pets.CHATTER.get(str(settings.value(key)), 1.0)
	if key in ["pet1_personality", "pet2_personality"]:
		var who := "nina" if key == "pet1_personality" else "argos"
		pets.set_persona(pets.critter(who), Pets.persona_of(settings.value(key), who))
	if key in ["pet1", "pet2"]:
		var id := "nina" if key == "pet1" else "argos"
		var c: Pets.Critter = pets.critter(id)
		var kind := Pets.kind_of(settings.value(key), id)
		if kind == pets.kinds[id]:
			return
		if not eggs.scene.is_empty():
			eggs.release_scene()
		if c.id == "nina":
			knock.pending = -1
		pets.change_kind(c, kind)


func set_voices(v: Dictionary) -> void:
	pets.set_voices(v)


func has_voices() -> bool:
	return pets.voices.has_any()


func set_weather(w: Variant) -> void:
	if w is Dictionary and w.get("kind") is String:
		weather = w["kind"]
		weather_desc = str(w.get("desc", ""))
		temp_c = w.get("temp_c")


func set_forecast(days: Variant) -> void:
	forecast = days if days is Array else []


# the weather the room has none of: what it shows with no report at all
func clear_weather() -> void:
	weather = "clear"
	weather_desc = ""
	temp_c = null
	forecast = []


func today() -> String:
	return Time.get_date_string_from_unix_time(int(_now_local()))


func set_data(d: Dictionary) -> void:
	open = d["open"]
	coming = d["coming"]
	notes = d["notes"]
	done_week = int(d.get("done_week", 0))
	done = d["done"] if d.get("done") is Array else null
	meetings = d["meetings"] if d.get("meetings") is Array else []
	things.set_data(d)
	var ids: Array = []
	ring_ids = []
	for item in open:
		ids.append(int(item["id"]))
		if item.get("told_at") != null:
			ring_ids.append(int(item["id"]))
		if _arg_ring == int(item["id"]) and ring_ids.find(_arg_ring) < 0:
			ring_ids.append(_arg_ring)
		if int(item["id"]) == focus.id:
			focus.text = str(item["text"])
	if focus.active() and not ids.has(focus.id):
		focus.clear()
	if knock.id >= 0 and not ids.has(knock.id):
		knock.clear()
	_assign_slots(ids)
	for rang_id in _rang.keys():
		if not ring_ids.has(rang_id):
			_rang.erase(rang_id)
	for item in open:
		var item_id := int(item["id"])
		if ring_ids.has(item_id) and _rang.get(item_id, "none") != item.get("told_at"):
			_rang[item_id] = item.get("told_at")
			_rang_new = true
			pets.nudge("desk", "ring", str(item["text"]))
			chat.told(int(item["id"]), str(item.get("told_at")), str(item["text"]))
	pets.has_open = not open.is_empty()
	_feed_person()
	jar.set_count(_arg_jar if _arg_jar >= 0 else done_week, Jar.week_key(_now_local()), 0.9)
	if not _seen_data:
		person.snap()
		_first_data(ids)
	_had_open = pets.has_open
	_seen_data = true


func _assign_slots(ids: Array) -> void:
	for id in _slots.keys():
		if not ids.has(id):
			_slots.erase(id)
	for id in ids:
		if _slots.has(id) or _off_desk(id):
			continue
		for s in SLOTS.size():
			if not _slots.values().has(s):
				_slots[id] = s
				break


func _off_desk(id: int) -> bool:
	return id == knock.id or id == int(knock.flying.get("id", -1))


func _first_data(ids: Array) -> void:
	if _deep_night():
		_deep = 1.0
		pets.place(pets.critter("nina"), "sofa", "sleep")
		pets.place(pets.critter("argos"), "rug", "sleep")
		pets.settle = true
	if _arg_knocked >= 0 and ids.has(_arg_knocked):
		knock.id = _arg_knocked
		_slots.erase(_arg_knocked)
		pets.place(pets.critter("nina"), "knocked", "sit")


func _deep_night() -> bool:
	var hour := _hour()
	return (hour >= 23.0 or hour < 5.5) and person.calm


func _feed_person() -> void:
	person.open_n = open.size()
	person.has_notes = not notes.is_empty()
	person.hour = _hour()
	person.ring = not ring_ids.is_empty()
	person.calm = true
	for item in open:
		if item["kind"] == "reminder":
			person.calm = false


func show_reply(text: String) -> void:
	reply_text = text
	reply_left = 7.0
	pets.nudge("desk", "jot")


func take_attention() -> bool:
	for id in ring_ids:
		if not _rung.has(id):
			_rung.append(id)
			_attention = true
	var ask := _attention
	_attention = false
	return ask


func _bias() -> float:
	return float(Time.get_time_zone_from_system()["bias"]) * 60.0


func _now_local() -> float:
	var n := Time.get_unix_time_from_system() + _bias()
	if fake_day != "":
		var year: int = Time.get_datetime_dict_from_unix_time(int(n))["year"]
		var md := fake_day.split("-")
		n = Time.get_unix_time_from_datetime_dict(
			{
				"year": year,
				"month": int(md[0]),
				"day": int(md[1]),
				"hour": 12,
				"minute": 0,
				"second": 0
			}
		)
	if fake_hour >= 0.0:
		n = floorf(n / 86400.0) * 86400.0 + fake_hour * 3600.0
	return n


func _hour() -> float:
	return fmod(_now_local() / 3600.0, 24.0)


func _env_now() -> Dictionary:
	return Props.env_at(_hour(), forced_weather if forced_weather != "" else weather)


func _clock(unix: float, past: String = "since ") -> String:
	return When.text(unix, _now_local(), past)


func meeting_time(m: Dictionary) -> String:
	if m.get("all_day", false):
		return "all day"
	var t := Time.get_datetime_dict_from_unix_time(int(_local(str(m["starts_at"]))))
	return "%02d:%02d" % [t["hour"], t["minute"]]


func _due(item: Dictionary) -> float:
	return Time.get_unix_time_from_datetime_string(str(item["due_at"]).trim_suffix("Z")) + _bias()


func _next_reminder() -> Dictionary:
	var best := {}
	var best_at := INF
	for item in coming:
		if item.get("due_at") == null:
			continue
		var at := _due(item)
		if at < best_at:
			best_at = at
			best = item
	if best.is_empty():
		return {}
	return {"at": best_at, "text": str(best["text"])}


func _cap(text: String, n: int) -> String:
	return text if text.length() <= n else text.substr(0, n - 1) + "..."


func process(dt: float) -> void:
	_t += dt
	sure.tick(dt)
	_env = _env_now()
	pets.is_night = _env["day"] < 0.15
	pets.jot_open = jot_open
	var nina: Pets.Critter = pets.critter("nina")
	if jot_open and nina.spot == "pad":
		nina.wait = minf(nina.wait, 0.5)
	_bin_balls += pets.process(dt)
	_feed_person()
	person.process(dt, pets.freeze)
	var deep := _seen_data and _deep_night()
	_deep = move_toward(_deep, 1.0 if deep else 0.0, dt / 4.0)
	if _deep > 0.0:
		var tint: Color = _env["tint"]
		_env["tint"] = Color(tint.r, tint.g, tint.b * 0.8, minf(0.8, tint.a + 0.22 * _deep))
		_env["lamp"] = float(_env["lamp"]) * (1.0 - 0.75 * _deep)
	if _seen_data:
		pets.settle_near(deep)
	tv.process(dt, person.watching(), _deep > 0.5)
	pets.tv_on = tv.on
	if person.watching() and not _watching and not pets.freeze:
		pets.nudge("tv", "tv")
	_watching = person.watching()
	_night_next -= dt
	if _night_next <= 0.0:
		_night_next = pets.rng.randf_range(600.0, 1200.0)
		if pets.is_night and not deep and not pets.freeze:
			pets.nudge("desk", "night")
	jar.process(dt)
	room.door_ajar = person.arrive_left > 3.0 or not quirks.visitor.is_empty()
	rhythm.process(dt)
	perk_left = maxf(0.0, perk_left - dt)
	water_left = maxf(0.0, water_left - dt)
	_chore_moments(dt)
	_beats(dt)
	_knocking(dt)
	sound.process(dt, self)
	eggs.process(dt)
	petlife.process(dt)
	hearth.process(dt)
	spells.process(dt)
	outside.process(dt)
	finds.process(dt)
	secrets.process(dt)
	quirks.process(dt)
	delights.process(dt)
	antics.process(dt)
	if _t > 0.3 and _seen_data and _arg_antic[0] != "":
		antics.staged = _arg_antic.duplicate()
		_arg_antic[0] = ""
	sound.loop("rain", _env["weather"] in ["rain", "storm"])
	if jar.clinks.any(func(cl): return cl["t"] < dt + 0.001):
		sound.request("clink")
	if ring_ids.size() > _ringing or _rang_new:
		sound.request("ring")
	_rang_new = false
	_ringing = ring_ids.size()
	if card.is_open() and decorating:
		card.close()
	if _t > 0.45 and _arg_card != "":
		open_card(_arg_card)
		_arg_card = ""
	if focus.finished():
		person.stretch()
	reply_left = maxf(0.0, reply_left - dt)
	_t_args += dt
	if _t > 0.3 and (_arg_menu >= 0 or _arg_reply != ""):
		if _arg_menu >= 0:
			open_item(_arg_menu)
			_arg_menu = -1
		if _arg_reply != "":
			show_reply(_arg_reply)
			_arg_reply = ""
	if _t > 0.3 and _arg_then != "":
		person.forced = _arg_then
		_arg_then = ""
	if _t > 0.3 and _arg_drop:
		_arg_drop = false
		jar.set_count(jar.total + 1, jar.week, 0.0)
	if _t > 0.3 and _arg_beat != "":
		_begin_beat(_arg_beat)
		_arg_beat = ""
	if _t > 0.4 and not _scripted.is_empty():
		if _scripted.has("hover"):
			hover(_scripted["hover"])
		if _scripted.has("click"):
			click(_scripted["click"])
		_scripted = {}
	if say_who != "" and not _say_done and _t > 0.3:
		_say_done = true
		var c: Pets.Critter = pets.critter(say_who.to_lower())
		if c != null:
			pets.speak(c, say_occasion, "buy milk" if say_occasion in ["done", "old", "ring"] else "")
	if _arg_duo and _t > 0.3:
		_arg_duo = false
		pets.play_duo(pets.voices.duo())
	for cr in _crumples.duplicate():
		cr["t"] += dt
		if cr["t"] >= cr["life"]:
			_land(cr)
			_crumples.erase(cr)
	for p in _confetti:
		p["v"].y += 260.0 * dt
		p["pos"] += p["v"] * dt
		p["t"] += dt
	_confetti = _confetti.filter(func(p): return p["t"] < 3.2)


func _geometry() -> void:
	_k = room._k
	_o = room._origin


func _p(x: float, y: float, z: float = 0.0) -> Vector2:
	return Props.floor_pt(_o, _k, x, y, z)


func _slot_quad(slot: int, scale: float = 1.0, extra_rot: float = 0.0) -> PackedVector2Array:
	var s: Dictionary = SLOTS[slot]
	if s.has("desk"):
		var d: Vector2 = s["desk"]
		return Props.floor_quad(
			_o, _k, d.x, d.y, 17.0, 0.17 * scale, 0.17 * scale, s["rot"] + extra_rot
		)
	return Props.wall_quad(
		_o, _k, 1, s["s"], s["h"], 6.5 * scale, 6.5 * scale, s["rot"] + extra_rot
	)


func _item_color(item: Dictionary) -> Color:
	return REMINDER_COLOR if item["kind"] == "reminder" else TODO_COLOR


func _stack_top(n: int) -> Vector2:
	return _p(STACK.x, STACK.y, STACK.z + minf(n, 10) * 1.1 + 1.0)


func tick_off(id: int) -> void:
	_chore_done(id)
	_geometry()
	var found := {}
	for item in open:
		if int(item["id"]) == id:
			found = item
	if found.is_empty():
		return
	var from := _anchor(id)
	var slot: int = _slots.get(id, -1)
	_slots.erase(id)
	if id == knock.id:
		knock.clear()
	pets.cheer(
		pets.critter("argos"),
		"desk_stand",
		3,
		"all_done" if open.size() == 1 else "done",
		str(found["text"])
	)
	if found["text"].to_lower().contains("plant") and found["text"].to_lower().contains("water"):
		perk_left = 600.0
		water_left = 4.0
	sound.request("rustle")
	sound.request("done")
	var fire := eggs.toss_ids.has(id) and hearth.lit
	eggs.toss_ids.erase(id)
	var miss: bool = (
		not fire and not pets.critter("nina").away and (force_bat or pets.rng.randf() < 0.4)
	)
	(
		_crumples
		. append(
			{
				"t": 0.0,
				"life": 1.05,
				"from": (from - _o) / _k,
				"slot": slot,
				"color": _item_color(found),
				"miss": miss,
				"fire": fire,
			}
		)
	)
	if open.size() == 1:
		_celebrate()


func send_later(id: int) -> void:
	_geometry()
	var found := {}
	for item in open:
		if int(item["id"]) == id:
			found = item
	if found.is_empty():
		return
	var from := _anchor(id)
	_slots.erase(id)
	if id == knock.id:
		knock.clear()
	(
		_crumples
		. append(
			{
				"t": 0.0,
				"life": 1.1,
				"from": (from - _o) / _k,
				"slot": -1,
				"color": _item_color(found),
				"miss": false,
				"fly": true,
			}
		)
	)


# an agenda's pile, from the shelf or from Today
func open_agenda(id: int) -> void:
	if not things.agenda(id).is_empty():
		viewed.emit("agenda", id)


# a thing on the desk, the stack or a row: its view opens in the sidebar
func open_item(id: int) -> void:
	if things.find(id).is_empty():
		return
	if id == knock.id:
		knock.clear()
		_assign_slots(_open_ids())
	viewed.emit("item", id)


func _celebrate() -> void:
	_geometry()
	sound.request("all_done")
	var at := _p(4.0, 2.0, 70.0)
	for i in 46:
		(
			_confetti
			. append(
				{
					"pos":
					(
						at
						+ (
							Vector2(pets.rng.randf_range(-130, 130), pets.rng.randf_range(-30, 20))
							* _k
							/ 2.0
						)
					),
					"v": Vector2(pets.rng.randf_range(-60, 60), pets.rng.randf_range(-170, -40)),
					"t": -pets.rng.randf_range(0.0, 0.4),
					"color": CONFETTI[i % CONFETTI.size()],
					"spin": pets.rng.randf_range(0, TAU),
				}
			)
		)


func _land(cr: Dictionary) -> void:
	if cr.get("fly", false):
		return
	if cr.get("fire", false):
		hearth.puff()
		return
	if not cr["miss"]:
		_bin_balls += 1
		return
	var toy: Dictionary = pets.drop_toy(_center(6, 1))
	var nina: Pets.Critter = pets.critter("nina")
	pets.chase(nina, toy, 2)


func _center(c: int, r: int) -> Vector2:
	return Vector2(c + 0.5, r + 0.5)


func _bin_rim() -> Vector2:
	return _p(Pets.BIN_TOP.x, Pets.BIN_TOP.y, Pets.BIN_Z + 1.0)


func items() -> Array:
	var out: Array = [
		{"key": 3.0, "pri": 0.4, "fn": _draw_calendar},
		{"key": 3.0, "pri": 0.5, "fn": _draw_board},
		{"key": 4.0, "pri": 0.5, "fn": _draw_pane_ne},
		{"key": 6.0, "pri": 0.5, "fn": _draw_window},
		{"key": 1.0, "pri": 1.1, "fn": _draw_wardrobe},
		{"key": 3.0, "pri": 1.2, "fn": _draw_tv},
		{"key": 5.0, "pri": 1.2, "fn": _draw_monitor},
		{"key": 5.0, "pri": 1.5, "fn": _draw_desk_things},
		{"key": 5.0, "pri": 1.55, "fn": _draw_pad_phone},
		{"key": 6.0, "pri": 1.5, "fn": _draw_bin_balls},
		{"key": 6.0, "pri": 1.52, "fn": _draw_chore_bin},
		{"key": 7.0, "pri": 1.3, "fn": _draw_chore_bag},
		{"key": 5.0, "pri": 1.56, "fn": _draw_chore_pills},
		{"key": 2.0, "pri": 1.0, "fn": _draw_chore_basket},
		{"key": 6.0, "pri": 1.6, "fn": _draw_jar},
		{"key": 3.0, "pri": 0.6, "fn": _draw_bunting},
	]
	if knock.id >= 0:
		out.append(
			{"key": Knock.LANDS_AT.x + Knock.LANDS_AT.y - 1.0, "pri": 1.7, "fn": _draw_knocked}
		)
	if person.bag == "down":
		out.append({"key": Person.BAG_AT.x + Person.BAG_AT.y - 1.0, "pri": 1.7, "fn": _draw_bag})
	out.append_array(eggs.items())
	out.append_array(petlife.items())
	out.append_array(finds.items())
	out.append_array(quirks.items())
	out.append_array(delights.items())
	for t in pets.toys:
		out.append({"key": t["pos"].x + t["pos"].y - 1.0, "pri": 1.8, "fn": _draw_toy.bind(t)})
	for c in pets.critters:
		if c.away:
			continue
		var pri := person.pri() if c.id == "person" else 2.0
		out.append({"key": pets.sort_key(c), "pri": pri, "fn": _draw_critter.bind(c)})
	return out


func _draw_critter(c: Pets.Critter) -> void:
	if c.id == "person":
		person.draw(room, _o, _k)
		quirks.draw_person(room, pets.feet(c, _o, _k), _k)
	else:
		pets.draw(room, c, _o, _k)
		if c.carry != "":
			var at: Vector2 = pets.feet(c, _o, _k) + Pets.NECK[c.dir] * _k + Vector2(0, 3 * _k)
			Eggs.draw_thing(room, c.carry, at, _k, _t)


func _px(base: Vector2, pts: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(base + (p as Vector2) * _k)
	return out


func _tv_quad() -> PackedVector2Array:
	if room._sprite("tv_stand_se").is_empty():
		return PackedVector2Array(
			[_p(1.0, 3.85, 36), _p(1.0, 2.15, 36), _p(1.0, 2.15, 16), _p(1.0, 3.85, 16)]
		)
	var base := _p(0, 2) - Vector2(32, 40) * _k
	return _px(base, [Vector2(13, 26), Vector2(32, 16.5), Vector2(32, 31), Vector2(13, 41)])


func _monitor_quad() -> PackedVector2Array:
	if room._sprite("computer_desk_sw").is_empty():
		return PackedVector2Array(
			[_p(4.35, 0.4, 44), _p(5.25, 0.4, 44), _p(5.25, 0.4, 33), _p(4.35, 0.4, 33)]
		)
	var base := _p(4, 0) - Vector2(16, 24) * _k
	return _px(base, [Vector2(21, 1), Vector2(33, 7), Vector2(33, 18), Vector2(21, 12)])


func _draw_window() -> void:
	var frame := View.draw(
		room, _o, _k, _env, _t, _hover == "window", outside.draw.bind(room, _k, _env)
	)
	window_frame = frame
	_draw_season(frame)
	_register("window", frame, Props.qlerp(frame, 0.5, 0.0))
	outside.hits(room, frame)


func _draw_pad_phone() -> void:
	var pad := Props.notepad(room, _o, _k, PAD.x, PAD.y, PAD.z)
	_register("pad", pad, Props.qlerp(pad, 0.5, 1.0))
	var ph := Props.phone(room, _o, _k, PHONE.x, PHONE.y, PHONE.z, not ring_ids.is_empty(), _t)
	_register("phone", ph, Props.qlerp(ph, 0.5, 1.0))
	if chat.unread:
		var dot := Props.center(ph) + Vector2(3.0, -3.0) * _k
		room.draw_circle(dot, 2.4 * _k, Color("f3ead6"))
		room.draw_circle(dot, 1.7 * _k, Color("d9534f"))


func _draw_wardrobe() -> void:
	var hex := PackedVector2Array(
		[_p(1, 0, 44), _p(2, 0, 44), _p(2, 0), _p(2, 1), _p(1, 1), _p(1, 1, 44)]
	)
	_register("wardrobe", hex, _p(1.5, 1.0))


func _draw_tv() -> void:
	var q := _tv_quad()
	tv.screen(room, q)
	_register("tv", q, Props.qlerp(q, 0.5, 1.0))


func _draw_monitor() -> void:
	if not focus.active():
		return
	var q := _monitor_quad()
	room.draw_colored_polygon(q, Color("1c2438"))
	var lines := 3
	for i in lines:
		var v := 0.22 + 0.24 * i
		room.draw_line(
			Props.qlerp(q, 0.12, v),
			Props.qlerp(q, 0.88 - 0.25 * (i % 2), v),
			Color("e8b86d", 0.9),
			maxf(1.0, 0.8 * _k)
		)
	if focus.running():
		var p := focus.progress()
		room.draw_line(
			Props.qlerp(q, 0.08, 0.92),
			Props.qlerp(q, 0.08 + 0.84 * p, 0.92),
			Color("8fd18a"),
			maxf(1.0, _k)
		)


func _draw_toy(t: Dictionary) -> void:
	var at := _p(t["pos"].x, t["pos"].y, t["z"] + 2.0)
	if t["z"] > 0.5 and t["z"] < 10.0:
		room.draw_circle(_p(t["pos"].x, t["pos"].y), 2.4 * _k, Color(0, 0, 0, 0.18))
	if t["kind"] == "yarn":
		var q := PackedVector2Array(
			[
				at + Vector2(-6, -6) * _k,
				at + Vector2(6, -6) * _k,
				at + Vector2(6, 5) * _k,
				at + Vector2(-6, 5) * _k
			]
		)
		_register("toy:%d" % pets.toys.find(t), q, at)
		Props.yarn(room, at, _k, t["spin"])
	else:
		Props.paper_ball(room, at, _k, t["spin"])


func draw_floor() -> void:
	_geometry()
	_hits.clear()
	if _env.is_empty():
		_env = _env_now()
	var hour := _hour()
	Props.sun_patch(
		room, _o, _k, lerpf(0.4, 2.2, clampf((hour - 8.0) / 9.0, 0.0, 1.0)), 5.05, _env["sun"]
	)
	petlife.draw_floor()
	for c in pets.critters:
		if c.id != "person":
			pets.draw_shadow(room, c, _o, _k)
		else:
			if not person.seated:
				room._draw_person_shadow(_o, {"col": c.pos.x - 0.5, "row": c.pos.y - 0.5})


func _ellipse(x: float, y: float, rx: float, ry: float, z: float = 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var mid := _p(x, y, z)
	for i in 24:
		var a := TAU * i / 24.0
		pts.append(mid + Vector2(cos(a) * rx, sin(a) * ry) * _k)
	return pts


func draw_plant(f: Array) -> void:
	var s: Dictionary = room._sprite("plant_large")
	if s.is_empty():
		room._flat_box(_o, f[1], f[2], f[3], f[4], f[5], f[6])
		return
	var stage := 0 if open.size() <= 2 or perk_left > 0.0 else (1 if open.size() <= 5 else 2)
	var thirst := chore_state("plant")
	if thirst != "":
		stage = 0 if perk_left > 0.0 else Chores.urgency(thirst)
	var tex: Texture2D = s["tex"]
	var top: Vector2 = (room._p(_o, f[1], f[2]) - s["anchor"]).round()
	var split := 27 * _k
	room.draw_texture_rect_region(
		tex,
		Rect2(top + Vector2(0, split), Vector2(tex.get_width(), tex.get_height() - split)),
		Rect2(0, split, tex.get_width(), tex.get_height() - split)
	)
	register_sprite("plant", tex, top)
	var pivot := top + Vector2(tex.get_width() / 2.0, split)
	var lean: float = [0.0, 0.09, 0.2][stage]
	var squash: float = [1.0, 0.94, 0.84][stage]
	var tint: Color = [Color.WHITE, Color(0.97, 0.96, 0.78), Color(0.9, 0.82, 0.55)][stage]
	if thirst != "":
		lean = [0.0, 0.1, 0.36][stage]
		squash = [1.0, 0.92, 0.72][stage]
		tint = [Color.WHITE, Color(0.96, 0.93, 0.68), Color(0.84, 0.7, 0.4)][stage]
	room.draw_set_transform(pivot, lean, Vector2(1, squash))
	room.draw_texture_rect_region(
		tex,
		Rect2(Vector2(-tex.get_width() / 2.0, -split), Vector2(tex.get_width(), split)),
		Rect2(0, 0, tex.get_width(), split),
		tint
	)
	room.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if stage == 0:
		for spot in [Vector2(13, 14), Vector2(19, 8), Vector2(11, 22), Vector2(20, 23)]:
			room.draw_rect(Rect2(top + spot * _k, Vector2(2, 2) * _k), Color("f2a6b3"))
			room.draw_rect(
				Rect2(top + spot * _k + Vector2(_k * 0.5, _k * 0.5), Vector2(_k, _k)),
				Color("ffe27a")
			)
	elif stage == 2:
		var leaf := top + Vector2(25, 41) * _k
		room.draw_rect(Rect2(leaf, Vector2(3, 1.5) * _k), Color("a07a3a"))


func _draw_pane_ne() -> void:
	Props.pane(room, _o, _k, 1, 68.0, 74.0, 18.0, 32.0, _env, _t, true)


func _register(key: String, poly: PackedVector2Array, below: Vector2) -> void:
	_hits.append({"key": key, "poly": poly, "below": below})


# a thing drawn from a sprite (the clock, the plant) is hit where the sprite has pixels
func fire_on() -> bool:
	return hearth.lit


# a piece the room reacts to: hit where its sprite has pixels
func furn(id: String, tex: Texture2D, at: Vector2) -> void:
	for name in FURN_KEYS:
		if id.begins_with(name):
			register_sprite("furn:" + name, tex, at)
			if name == "bookshelf" and finds.glow > 0.0:
				room.draw_texture(tex, at, Color(1.8, 1.5, 0.7, 0.45 * minf(1.0, finds.glow)))
			if name == "fireplace":
				hearth.dress(room, at, _k, id)


func register_sprite(key: String, tex: Texture2D, at: Vector2) -> void:
	if not _used.has(tex):
		_images[tex] = tex.get_image()
		_used[tex] = Rect2(_images[tex].get_used_rect())
	var r: Rect2 = _used[tex]
	r.position += at
	var poly := PackedVector2Array(
		[r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	)
	_register(key, poly, Vector2(r.get_center().x, r.end.y))
	_hits[-1]["img"] = _images[tex]
	_hits[-1]["at"] = at


func _draw_board() -> void:
	var cork := Props.corkboard(room, _o, _k, BOARD["s"], BOARD["h"], BOARD["w"], BOARD["hh"])
	_register("board", cork, Props.qlerp(cork, 0.5, 1.0))
	var n := mini(notes.size(), 4)
	var spots: Array = NOTE_SPOTS.get(n, [])
	for i in n:
		var at: Vector2 = spots[i]
		var q := Props.wall_quad(
			_o, _k, 1, BOARD["s"] + at.x, BOARD["h"] + at.y, 10.0, 8.0, NOTE_TILT[i]
		)
		var hot: bool = _hover == "note:%d" % i or selected == "note:%d" % i
		Props.slip(room, _k, q, Props.SLIP_COLORS[i % 4], 2 + i % 2, Props.PIN_COLORS[i % 4], hot)
		_register("note:%d" % i, q, Props.qlerp(q, 0.5, 0.0))
	if notes.size() > 4:
		var tag := Props.wall_pt(_o, _k, 1, BOARD["s"] + 27.0, BOARD["h"] - 2.5)
		var r := Rect2(tag - Vector2(15, 9), Vector2(30, 18))
		room.draw_rect(Rect2(r.position + Vector2(2, 3), r.size), Color(0, 0, 0, 0.25))
		room.draw_rect(r, Props.INK)
		room.draw_rect(r.grow(-2), Color("e8b86d"))
		var font := ThemeDB.fallback_font
		var label := "+%d" % (notes.size() - 4)
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		room.draw_string(
			font,
			r.position + Vector2((30 - w) / 2.0, 13.5),
			label,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			14,
			Props.INK
		)
		_register(
			"more",
			PackedVector2Array(
				[
					r.position,
					r.position + Vector2(r.size.x, 0),
					r.end,
					r.position + Vector2(0, r.size.y)
				]
			),
			tag + Vector2(0, 9)
		)
	if notes.is_empty():
		var empty := Props.qlerp(cork, 0.5, 0.5)
		room.draw_circle(empty, 1.4 * _k, Props.PIN_COLORS[1])
		room.draw_circle(empty + Vector2(-0.5, -0.9) * _k, 0.45 * _k, Color(1, 1, 1, 0.7))


func _draw_calendar() -> void:
	var now := _now_local()
	var d := Time.get_datetime_dict_from_unix_time(int(now))
	var month_days: int = MONTH_DAYS[d["month"] - 1]
	if d["month"] == 2 and (d["year"] % 4 == 0 and (d["year"] % 100 != 0 or d["year"] % 400 == 0)):
		month_days = 29
	var first_wd: int = ((d["weekday"] - (d["day"] - 1)) % 7 + 7) % 7
	var nxt := _next_reminder()
	var due_day := -1
	_next_text = ""
	if not nxt.is_empty():
		var nd := Time.get_datetime_dict_from_unix_time(int(nxt["at"]))
		if nd["month"] == d["month"] and nd["year"] == d["year"]:
			due_day = nd["day"]
		_next_text = "next: %s - %s" % [_clock(nxt["at"]), _cap(nxt["text"], 28)]
	var q := Props.calendar(room, _o, _k, 24.0, 31.0, d["day"], first_wd, month_days, due_day)
	_cal = q
	_register("cal", q, Props.qlerp(q, 0.5, 0.0))


func _draw_desk_things() -> void:
	var hour := _hour()
	if hour >= 5.5 and hour < 11.5 and not eggs.mug_off:
		Props.steam(room, _p(MUG.x, MUG.y, MUG.z), _k, _t)
	eggs.draw_desk()
	for item in open:
		var id := int(item["id"])
		if not _slots.has(id):
			continue
		var q := _slot_quad(_slots[id])
		var hot: bool = _hover == "item:%d" % id or selected == "item:%d" % id
		Props.slip(room, _k, q, _item_color(item), 2, Color(0, 0, 0, 0), hot)
		room.draw_colored_polygon(
			PackedVector2Array([Props.qlerp(q, 0, 0.8), Props.qlerp(q, 1, 0.8), q[2], q[3]]),
			Color(0, 0, 0, 0.12)
		)
		_register("item:%d" % id, q, Props.qlerp(q, 0.5, 0.0))
	var n := open.size()
	if n == 0:
		return
	var layers := mini(n, 10)
	var shade := Props.floor_quad(_o, _k, STACK.x + 0.04, STACK.y + 0.04, STACK.z, 0.23, 0.19)
	room.draw_colored_polygon(shade, Color(0, 0, 0, 0.22))
	var top := PackedVector2Array()
	for i in layers:
		var q := Props.floor_quad(
			_o,
			_k,
			STACK.x + 0.02 * sin(i * 2.3),
			STACK.y + 0.02 * cos(i * 1.7),
			STACK.z + i * 1.1,
			0.23,
			0.19,
			0.12 * sin(i * 1.9)
		)
		room.draw_colored_polygon(
			q, Props.PAPER if i % 2 == 0 else Props.PAPER_SHADE.lightened(0.2)
		)
		room.draw_line(q[3], q[2], Props.PAPER_SHADE.darkened(0.35), maxf(1.0, 0.5 * _k))
		top = q
	room.draw_line(
		Props.qlerp(top, 0.2, 0.4),
		Props.qlerp(top, 0.8, 0.4),
		Color(Props.INK, 0.5),
		maxf(1.0, 0.5 * _k)
	)
	room.draw_line(
		Props.qlerp(top, 0.2, 0.6),
		Props.qlerp(top, 0.65, 0.6),
		Color(Props.INK, 0.5),
		maxf(1.0, 0.5 * _k)
	)
	var span := PackedVector2Array(
		[
			_p(STACK.x - 0.25, STACK.y),
			_p(STACK.x, STACK.y - 0.2),
			_p(STACK.x + 0.25, STACK.y),
			_p(STACK.x, STACK.y + 0.2)
		]
	)
	_register("stack", span, _p(STACK.x, STACK.y + 0.2, STACK.z))
	Props.badge(room, _p(STACK.x + 0.5, STACK.y + 0.22, STACK.z + 13.0), n)


func _draw_bin_balls() -> void:
	var rim := _p(Pets.BIN_TOP.x, Pets.BIN_TOP.y, Pets.BIN_Z)
	for i in mini(_bin_balls, 3):
		Props.paper_ball(
			room, rim + Vector2((i - 1) * 2.2, -1.0 - (i % 2) * 1.5) * _k, _k, i * 1.7, 0.8
		)


func draw_over() -> void:
	_geometry()
	var hexp := Props.hex(_o, _k, COLS, ROWS, WALL_H)
	Props.tint_room(room, hexp, _env)
	Props.lamp_glow(room, _o, _k, _env["lamp"], not Glow.shown())
	Glow.draw(room, self)
	_draw_knock_flight()
	for cr in _crumples:
		_draw_crumple(cr)
	for p in _confetti:
		if p["t"] >= 0.0:
			Props.confetti(room, p["pos"], p["color"], _k, p["spin"] + p["t"] * 6.0)
	var bounds := Rect2(Vector2.ZERO, room.size)
	for c in pets.critters:
		if not c.away:
			_draw_extras(c, bounds)
	_draw_water()
	hearth.draw_over(room)
	spells.draw(room, _k)
	eggs.draw_over(bounds)
	secrets.draw_over(room)
	quirks.draw_over(room)
	delights.draw_over(room)
	antics.draw_over(room)
	sound.draw_mark(room, Vector2(14, 14), 2)
	_draw_selected()
	_draw_name(bounds)


func _draw_extras(c: Pets.Critter, bounds: Rect2) -> void:
	var f := pets.feet(c, _o, _k)
	for h in c.hearts:
		if h["t"] < 0.0:
			continue
		var rise: float = h["t"] / 1.4
		Props.heart(
			room,
			f + Vector2(h["dx"], -(c.head + 2) * _k - rise * 5 * _k),
			2,
			Color("e8576b", 1.0 - rise)
		)
	if c.mode == "sleep" and c.id != "person":
		var font := ThemeDB.fallback_font
		for i in 3:
			var ph := fmod(_t * 0.5 + i * 0.33, 1.0)
			var at := f + Vector2(8 + ph * 10, -(c.head + 2) * _k * 0.6 - ph * 16 * _k * 0.5)
			room.draw_string(
				font, at, "z", HORIZONTAL_ALIGNMENT_LEFT, -1, 12 + i * 3, Color("f1e9dc", 1.0 - ph)
			)
	if c.say_left > 0.0 and c.say_text != "":
		var fade := minf(1.0, c.say_left / 0.4)
		var lift := 7 if c.pat_t >= 0.0 or not c.hearts.is_empty() else 3
		Props.bubble(room, f + Vector2(0, -(c.head + lift) * _k), c.say_text, bounds, fade)
	elif _hover == "pet:" + c.id and c.id != "person" and _t - _hover_time <= NAME_STAYS:
		Props.tag(room, f + Vector2(0, 6), [Settings.pets(c.title)], bounds)


func _draw_crumple(cr: Dictionary) -> void:
	var t: float = cr["t"]
	var from: Vector2 = _o + (cr["from"] as Vector2) * _k
	if cr.get("fly", false):
		var f := t / float(cr["life"])
		var at := _arc(from, Props.center(_cal), f)
		var s := (1.0 - 0.55 * f) * 3.4 * _k
		var pts := PackedVector2Array()
		for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			pts.append(at + (corner as Vector2).rotated(f * 7.0) * s)
		room.draw_colored_polygon(Props.shifted(pts, Vector2(1, 2) * _k), Color(0, 0, 0, 0.2))
		room.draw_colored_polygon(pts, cr["color"])
		room.draw_polyline(
			PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), Color(Props.INK, 0.6), 1.0
		)
		return
	if t < 0.3:
		var squash := t / 0.3
		if cr["slot"] >= 0:
			var q := _slot_quad(cr["slot"], 1.0 - 0.55 * squash, squash * 2.6)
			room.draw_colored_polygon(q, cr["color"])
		Props.paper_ball(room, from, _k, squash * 5.0, 0.35 + 0.65 * squash)
		return
	var u: float = (t - 0.3) / (float(cr["life"]) - 0.3)
	var target := _p(6.5, 1.5, 0.0) if cr["miss"] else _bin_rim()
	if cr.get("fire", false):
		target = hearth.mouth()
	for i in range(3, 0, -1):
		var back := maxf(0.0, u - 0.06 * i)
		room.draw_circle(_arc(from, target, back), (3.0 - i * 0.6) * _k, Color(Props.PAPER, 0.35))
	Props.paper_ball(room, _arc(from, target, u), _k, t * 14.0, 1.2)


func _arc(from: Vector2, to: Vector2, u: float) -> Vector2:
	return from.lerp(to, u) + Vector2(0, -44.0 * _k * u * (1.0 - u))


func _ago(iso: String) -> String:
	var secs := (
		Time.get_unix_time_from_system()
		- Time.get_unix_time_from_datetime_string(iso.trim_suffix("Z"))
	)
	if secs < 90.0:
		return "just now"
	if secs < 3600.0:
		return "%d min ago" % roundi(secs / 60.0)
	if secs < 86400.0:
		return "%d h ago" % roundi(secs / 3600.0)
	var days := int(secs / 86400.0)
	return "yesterday" if days == 1 else "%d days ago" % days


# the short name of what the pointer is on; it goes when the pointer leaves or has been still
func _name_of(key: String) -> String:
	var thing := chore_of_key(key)
	if thing != "":
		return _chore_name(thing)
	if key.begins_with("note:"):
		var i := int(key.substr(5))
		return _cap(str(notes[i]), 34) if i < notes.size() else ""
	if key == "more":
		return "more notes"
	if key.begins_with("item:"):
		for item in open:
			if int(item["id"]) == int(key.substr(5)):
				return _cap(str(item["text"]), 34)
		return ""
	match key:
		"window":
			var sky := weather_desc if weather_desc != "" else weather
			if temp_c != null:
				sky += ", " + Settings.temp(temp_c, settings.degrees())
			return sky
		"jar":
			return jar.hover_text()
		"stack":
			return "the desk: %d open" % open.size()
		"phone":
			for item in open:
				if ring_ids.has(int(item["id"])):
					return _cap(str(item["text"]), 34)
			return "the phone  (K)"
	return NAMES.get(key, "")


func _draw_name(bounds: Rect2) -> void:
	var key := _hover
	if show_note >= 0 and key == "":
		key = "note:%d" % show_note
	elif _t - _hover_time > NAME_STAYS:
		return
	if key == "" or key.begins_with("pet:"):
		return
	var text := _name_of(key)
	if text == "":
		return
	for h in _hits:
		if h["key"] == key:
			Props.tag(room, h["below"], [text], bounds)
			return


func _draw_selected() -> void:
	if selected == "":
		return
	var pts := PackedVector2Array()
	if selected.begins_with("pet:") or selected == "person":
		var c: Pets.Critter = pets.critter(selected.substr(4) if selected != "person" else "person")
		if c != null and not c.away:
			var r := pets.hit_rect(c, _o, _k)
			pts = PackedVector2Array(
				[r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
			)
	else:
		for h in _hits:
			if h["key"] == selected:
				pts = h["poly"]
	if pts.size() < 3:
		return
	var closed := pts.duplicate()
	closed.append(pts[0])
	room.draw_polyline(closed, Color(0, 0, 0, 0.55), 4.0)
	room.draw_polyline(closed, Color("e8c77a"), 2.0)


func _every(item: Dictionary) -> String:
	return "" if item.get("every") == null else str(item["every"])


# the reminders with a time: the ones coming and the open ones with a due time
func _timed() -> Array:
	var out: Array = []
	for item in coming + open:
		if item.get("due_at") != null and item["kind"] == "reminder":
			out.append(item)
	return out


func _upcoming(items: Array, n: int) -> Array:
	var now := _now_local()
	var out := items.filter(func(i): return _due(i) >= now)
	out.sort_custom(func(a, b): return _due(a) < _due(b))
	return out.slice(0, n)


func _repeats(item: Dictionary) -> String:
	var every := _every(item)
	return "" if every == "" else Card.every_words(every)


# what the open card shows, built fresh each frame from what the home holds
func card_blocks() -> Array:
	match card.kind:
		"calendar":
			return things.calendar_blocks()
		"jar":
			return _jar_blocks()
		"weather":
			return _weather_blocks()
		"clock":
			return things.clock_blocks(_clock_blocks())
		"board":
			return things.board_blocks()
		"fireplace":
			return _fireplace_blocks()
		"piano":
			return [
				{"t": "title", "text": "The piano"},
				{"t": "text", "text": "Nobody has to play it."},
				{"t": "buttons", "items": [{"label": "play a few bars", "act": "play"}]},
			]
		"globe":
			return [
				{"t": "title", "text": "The snow globe"},
				{"t": "buttons", "items": [{"label": "shake it", "act": "shake"}]},
			]
		"plant":
			return _plant_blocks()
		"book":
			return [_shelf_block()]
		"found":
			return finds.found_blocks()
	return []


func _shelf_block() -> Dictionary:
	return {
		"t": "shelf",
		"notes": things.note_list(),
		"someday": things.someday.map(func(s): return {"id": s["id"], "text": s["text"]}),
		"projects": things.projects.map(_project_row),
		"agendas": things.agendas,
	}


func _project_row(p: Dictionary) -> Dictionary:
	var next: Variant = p.get("next")
	var sub := "next: " + str(next["text"]) if next is Dictionary else ""
	return {"id": p["id"], "text": p["text"], "sub": sub}


func _jar_blocks() -> Array:
	var blocks: Array = [{"t": "title", "text": "Done this week"}]
	if jar.total == 0:
		blocks.append({"t": "text", "text": "a fresh week"})
		return blocks
	blocks.append({"t": "text", "text": "%d done" % jar.total})
	if done is Array:
		var names: Array = (done as Array).filter(func(i): return i is Dictionary and i.has("text"))
		names.sort_custom(func(a, b): return str(a.get("done_at")) > str(b.get("done_at")))
		for item in names.slice(0, 10):
			var at := ""
			if item.get("done_at") != null:
				at = "  " + _clock(_local(str(item["done_at"])), "")
			blocks.append({"t": "text", "text": "- %s%s" % [item["text"], at]})
		if names.size() > 10:
			blocks.append({"t": "dim", "text": "and %d more" % (names.size() - 10)})
	return blocks


func _local(iso: String) -> float:
	return Time.get_unix_time_from_datetime_string(iso.trim_suffix("Z")) + _bias()


func _weather_blocks() -> Array:
	var sky: String = SKY_WORDS.get(weather, weather)
	var blocks: Array = [
		{"t": "title", "text": weather_desc if weather_desc != "" else weather.capitalize()},
		{"t": "text", "text": "Outside there is %s." % sky},
	]
	if temp_c != null:
		blocks.append({"t": "text", "text": Settings.temp(temp_c, settings.degrees())})
	var hour := _hour()
	var part := "night"
	if hour >= 5.5 and hour < 12.0:
		part = "morning"
	elif hour >= 12.0 and hour < 17.0:
		part = "afternoon"
	elif hour >= 17.0 and hour < 21.0:
		part = "evening"
	blocks.append({"t": "dim", "text": "It is %s." % part})
	var today := today()
	var unit := settings.degrees()
	var rows := Forecast.upcoming(forecast, today)
	if not rows.is_empty():
		blocks.append({"t": "gap"})
	for day in rows:
		blocks.append(
			{
				"t": "day",
				"name": Forecast.name_of(day["date"], today),
				"kind": day["kind"],
				"temps": "%s / %s" % [Settings.temp(day["high_c"], unit), Settings.temp(day["low_c"], unit)],
				"wet": Forecast.wet_text(day),
			}
		)
	return blocks


func _clock_blocks() -> Array:
	var now := _now_local()
	var d := Time.get_datetime_dict_from_unix_time(int(now))
	var blocks: Array = [
		{"t": "title", "text": "%02d:%02d" % [d["hour"], d["minute"]]},
		{
			"t": "text",
			"text": "%s %d %s" % [DAYS_FULL[d["weekday"]], d["day"], Card.MONTHS[d["month"] - 1]]
		},
		{"t": "gap"},
	]
	var next := _upcoming(_timed(), 1)
	if next.is_empty():
		blocks.append({"t": "text", "text": "Nothing coming up."})
	else:
		var at := _due(next[0])
		blocks.append({"t": "dim", "text": "Next up"})
		blocks.append({"t": "text", "text": str(next[0]["text"])})
		blocks.append({"t": "text", "text": "%s, %s" % [_clock(at), Card.until_text(at - now)]})
	if rhythm.list_at >= 0.0:
		var at := rhythm.list_at
		blocks.append({"t": "gap"})
		blocks.append(
			{
				"t": "dim",
				"text": "The day's list comes at %02d:%02d." % [int(at), roundi(fmod(at, 1.0) * 60.0)]
			}
		)
	return blocks


func _fireplace_blocks() -> Array:
	var blocks: Array = [
		{"t": "title", "text": "The fireplace"},
		{"t": "text", "text": "It is lit." if hearth.lit else "It is out."},
		{
			"t": "buttons",
			"items": [{"label": "put it out" if hearth.lit else "light it", "act": "fire_toggle"}],
		},
	]
	if hearth.lit and not open.is_empty():
		blocks.append({"t": "gap"})
		blocks.append({"t": "dim", "text": "Into the fire"})
		for item in open.slice(0, 6):
			blocks.append(
				{"t": "row", "text": str(item["text"]), "act": "fire:%d" % int(item["id"])}
			)
	return blocks


func _watering() -> Dictionary:
	var found: Array = []
	for item in _timed():
		var low := str(item["text"]).to_lower()
		if _every(item) != "" and (low.contains("water") or low.contains("plant")):
			found.append(item)
	var next := _upcoming(found, 1)
	if not next.is_empty():
		return next[0]
	return found[0] if not found.is_empty() else {}


func _plant_blocks() -> Array:
	var blocks: Array = [{"t": "title", "text": "The plant"}]
	var item := _watering()
	if item.is_empty():
		blocks.append({"t": "text", "text": "Nothing says it needs water."})
		return blocks
	var at := _due(item)
	blocks.append({"t": "text", "text": "Next: " + str(item["text"])})
	blocks.append({"t": "text", "text": "%s, %s" % [_clock(at), Card.until_text(at - _now_local())]})
	blocks.append({"t": "dim", "text": _repeats(item)})
	return blocks


# The chore things: thing -> {item, state, due}. A repeating reminder that names a thing stands for
# it; of two for one thing the more urgent does, and the other stays in the lists.
func chores() -> Dictionary:
	var now := _now_local()
	var sig := [open, coming, int(now), Settings.cat, Settings.dog]
	var same := _chore_sig.size() == 5 and sig.slice(2) == _chore_sig.slice(2)
	if same and is_same(open, _chore_sig[0]) and is_same(coming, _chore_sig[1]):
		return _chores
	_chore_sig = sig
	_chores = {}
	for item in coming + open:
		if item["kind"] != "reminder" or item.get("every") == null or item.get("due_at") == null:
			continue
		var thing := Chores.thing_of(str(item["text"]), [Settings.cat, Settings.dog])
		if thing == "":
			continue
		var due := _due(item)
		var row := {"item": item, "due": due, "state": Chores.state(due, str(item["every"]), now)}
		if not _chores.has(thing) or _chore_before(row, _chores[thing]):
			_chores[thing] = row
	return _chores


func _chore_before(a: Dictionary, b: Dictionary) -> bool:
	var ua := Chores.urgency(a["state"])
	var ub := Chores.urgency(b["state"])
	if ua != ub:
		return ua > ub
	if a["due"] != b["due"]:
		return a["due"] < b["due"]
	return int(a["item"]["id"]) < int(b["item"]["id"])


# is the thing in the room: the bin, the desk and the large plant always are
func chore_present(thing: String) -> bool:
	match thing:
		"laundry":
			return not layout.basket().is_empty()
		"bowls":
			return not (
				layout
				. pet_pieces()
				. filter(func(p): return PetThings.key_of(p) == "bowls")
				. is_empty()
			)
	return true


# the thing the row stands for in the room, "" when it is in the lists
func chore_thing_of(id: int) -> String:
	var all := chores()
	for thing in all:
		if int(all[thing]["item"]["id"]) == id and chore_present(thing):
			return thing
	return ""


# the state its thing shows, "" with no chore for it; a thing just done shows what it was a moment
func chore_state(thing: String) -> String:
	var all := chores()
	if not all.has(thing) or not chore_present(thing):
		return ""
	var m: Variant = _moment.get(thing)
	if m != null:
		return m["from"] if m["t"] < Chores.PAUSE else "fine"
	return all[thing]["state"]


# 0..1 over the part of the moment after the thing has changed, -1 when none is on
func chore_moment(thing: String) -> float:
	var m: Variant = _moment.get(thing)
	if m == null or m["t"] < Chores.PAUSE:
		return -1.0
	return clampf((m["t"] - Chores.PAUSE) / (Chores.MOMENT - Chores.PAUSE), 0.0, 1.0)


func _chore_moments(dt: float) -> void:
	for thing in _moment.keys():
		_moment[thing]["t"] += dt
		if _moment[thing]["t"] > Chores.MOMENT:
			_moment.erase(thing)


func _chore_done(id: int) -> void:
	var thing := chore_thing_of(id)
	if thing == "":
		return
	_moment[thing] = {"t": 0.0, "from": chore_state(thing)}
	if thing == "bowls":
		petlife.fill("food")


func chore_hit(thing: String) -> String:
	return "plant" if thing == "plant" else "chore:" + thing


# the thing a hit key is, when a chore stands for it
func chore_of_key(key: String) -> String:
	var thing := key.substr(6) if key.begins_with("chore:") else ("plant" if key == "plant" else "")
	return thing if thing != "" and chore_state(thing) != "" else ""


# the hit key of the thing a row stands for, "" for a row that is in the lists
func chore_hit_of(id: int) -> String:
	var thing := chore_thing_of(id)
	return chore_hit(thing) if thing != "" else ""


func _chore_name(thing: String) -> String:
	var row: Dictionary = chores()[thing]
	return Chores.hover(thing, chore_state(thing), row["due"], _now_local())


# a hit over a cell box from `z0` to `z1`
func _chore_box(key: String, x0: float, y0: float, x1: float, y1: float, z1: float) -> void:
	var pts := PackedVector2Array()
	for at in [Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)]:
		pts.append(_p(at.x, at.y))
		pts.append(_p(at.x, at.y, z1))
	_register(key, Geometry2D.convex_hull(pts), _p((x0 + x1) / 2.0, y1))


func _draw_chore_basket() -> void:
	var piece := layout.basket()
	if piece.is_empty():
		return
	var c: int = piece["c"]
	var r: int = piece["r"]
	var state_name := chore_state("laundry")
	var lift := chore_moment("laundry")
	var pen := PetThings.Pen.new(room, _p(c, r), _k)
	Chores.basket(pen, state_name if state_name != "" else "fine", maxf(lift, 0.0))
	if state_name != "":
		_chore_box("chore:laundry", c + 0.15, r + 0.15, c + 0.85, r + 0.85, 14.0)
	if lift >= 0.0 and lift < 1.0:
		Chores.sparks(room, _p(c + 0.5, r + 0.5, 12.0), _k, lift)


func _draw_chore_bin() -> void:
	var state_name := chore_state("bins")
	if state_name == "":
		return
	var pen := PetThings.Pen.new(room, _o, _k)
	Chores.bin_lid(pen, state_name)
	_chore_box("chore:bins", 6.1, 0.1, 6.9, 0.9, 13.0)


func _draw_chore_bag() -> void:
	var state_name := chore_state("bins")
	var gone := chore_moment("bins")
	if state_name == "":
		return
	var pen := PetThings.Pen.new(room, _o, _k)
	if state_name == "due":
		Chores.lid_down(pen)
		Chores.bag(pen)
		Chores.fly(pen, _t)
	elif gone >= 0.0 and gone < 1.0:
		Chores.bag(pen, gone)
		Chores.sparks(room, _p(6.78, 1.14, 8.0), _k, gone)


func _draw_chore_pills() -> void:
	var state_name := chore_state("pills")
	if state_name == "":
		return
	var pen := PetThings.Pen.new(room, _o, _k)
	Chores.bottle(pen, Chores.PILLS_AT, state_name)
	var at := Chores.PILLS_AT
	_chore_box("chore:pills", at.x - 0.16, at.y - 0.1, at.x + 0.16, at.y + 0.1, at.z + 10.0)
	var done := chore_moment("pills")
	if done >= 0.0:
		Chores.sparks(room, _p(at.x, at.y, at.z + 8.0), _k, done)


# the chore sets both bowls, so whichever one is in view shows it
func chore_levels(level: Dictionary) -> Dictionary:
	var state_name := chore_state("bowls")
	if state_name == "":
		return level
	var shown: float = Chores.FOOD_LEVEL[state_name]
	return {"food": shown, "water": shown}


# the pets' bowls piece is one hit while a chore stands for it
func chore_bowls_hit(p: Dictionary) -> void:
	if chore_state("bowls") != "":
		_chore_box("chore:bowls", p["c"] + 0.05, p["r"] + 0.05, p["c"] + 0.95, p["r"] + 0.95, 3.0)


# the pet under the pointer, "" when none
func pet_at(pos: Vector2) -> String:
	var key := _topmost(pos)
	return key.substr(4) if key.begins_with("pet:") else ""


func _topmost(pos: Vector2) -> String:
	for c in pets.critters:
		if c.id != "person" and not c.away and pets.hit_rect(c, _o, _k).has_point(pos):
			return "pet:" + c.id
	for i in range(_hits.size() - 1, -1, -1):
		if Geometry2D.is_point_in_polygon(pos, _hits[i]["poly"]) and _opaque(_hits[i], pos):
			return _hits[i]["key"]
	if pets.hit_rect(pets.critter("person"), _o, _k).has_point(pos):
		return "person"
	return ""


func hover(pos: Vector2) -> bool:
	finds.touch()
	var key := _topmost(pos)
	if key != _hover or pos.distance_to(_hover_at) > 1.0:
		_hover_time = _t
	_hover = key
	_hover_at = pos
	return key != ""


# what a click on the room does: a thing with a view of its own tells the sidebar (`viewed`), the
# rest answer on the spot; true when something was there
func click(pos: Vector2) -> bool:
	if decorating:
		return false
	finds.touch()
	var key := _topmost(pos)
	var thing := chore_of_key(key)
	if thing != "":
		open_item(int(chores()[thing]["item"]["id"]))
		return true
	var wants := _card_kind(key)
	if wants != "":
		things.reset()
		if wants == "book":
			finds.book = {}
		card.open(wants, key)
		if wants == "piano":
			hearth.piano_click()
		elif wants == "globe":
			finds.shake = 4.0
			eggs.find("globe")
			sound.request("clink")
		return true
	if key.begins_with("pet:"):
		var c: Pets.Critter = pets.critter(key.substr(4))
		if not eggs.pet_click(c):
			pets.pat(c, "pet")
		viewed.emit("pet", key.substr(4))
		return true
	if key.begins_with("thing:"):
		eggs.take(int(key.substr(6)))
		return true
	if petlife.click(key):
		return true
	if key == "star":
		outside.wish()
		return true
	if key.begins_with("toy:"):
		var ti := int(key.substr(4))
		if ti >= 0 and ti < pets.toys.size():
			antics.throw_toy(pets.toys[ti])
		return true
	if key == "cake":
		finds.candles = false
		show_reply("make a wish.")
		sound.request("wish")
		return true
	if key.begins_with("item:"):
		open_item(int(key.substr(5)))
		return true
	match key:
		"tv":
			tv.click()
			return true
		"stack":
			viewed.emit("open", null)
			return true
		"person":
			person.poke()
			return true
		"wardrobe":
			viewed.emit("closet", null)
			return true
		"pad":
			viewed.emit("add", true)
			return true
		"phone":
			if ring_ids.is_empty():
				viewed.emit("chat", null)
			else:
				open_item(ring_ids[0])
			return true
	return key != ""


func _cards_blocked() -> bool:
	return decorating


func _card_kind(key: String) -> String:
	return "board" if key.begins_with("note:") else CARD_KEYS.get(key, "")


func close_card() -> void:
	card.close()


# a click inside an open view's blocks; true when it was one of ours
func card_act(a: String) -> bool:
	match a:
		"fire_toggle":
			hearth.toggle()
			return true
		"play":
			hearth.piano_click()
			return true
		"shake":
			finds.shake = 4.0
			eggs.find("globe")
			sound.request("clink")
			return true
	if a.begins_with("fire:"):
		var id := int(a.substr(5))
		eggs.toss_ids.append(id)
		acted.emit(id, "done")
		return true
	return things.act(a)


func key(code: int) -> bool:
	if card.kind == "calendar" and code in [KEY_LEFT, KEY_RIGHT]:
		things.act("mprev" if code == KEY_LEFT else "mnext")
		return true
	return eggs.key(code)


# `name` is a card kind: calendar jar weather clock plant board; a staged one may follow
# its kind after a colon: calendar:DAY[:MONTHS_AHEAD], board:TAB[:PROJECT_ID]
func open_card(name: String) -> void:
	if _cards_blocked():
		return
	var parts := name.split(":")
	for key in _hits.map(func(h: Dictionary) -> String: return h["key"]):
		if _card_kind(key) == parts[0]:
			things.reset()
			card.open(parts[0], key)
			if parts[0] == "calendar" and parts.size() > 1:
				things.day = int(parts[1])
				things.mo = int(parts[2]) if parts.size() > 2 else 0
			if parts[0] == "board" and parts.size() > 1:
				things.tab = parts[1]
				things.proj = int(parts[2]) if parts.size() > 2 else 0
			return


# what now: the pick the Now line shows
func show_pick(row: Dictionary, say: String) -> void:
	things.pick = row
	things.say = say


func leave() -> void:
	_hover = ""
	antics.trigger("door_wait")


func _pet_said(id: String, text: String) -> void:
	if id in ["nina", "argos"] and not pets.freeze:
		chat.pet_said("cat" if id == "nina" else "dog", text)


# what the server now says is ringing: a told reminder dealt with elsewhere loses its buttons
func sync_chat(d: Dictionary) -> void:
	var ringing: Array = []
	for item in d.get("open", []):
		if item.get("told_at") != null:
			ringing.append(int(item["id"]))
	chat.sync(ringing)


func set_list_at(text: String) -> void:
	rhythm.list_at = Rhythm.parse_time(text)


func dismiss_slip() -> void:
	rhythm.dismiss()


func _open_ids() -> Array:
	var ids: Array = []
	for item in open:
		ids.append(int(item["id"]))
	return ids


func _anchor(id: int) -> Vector2:
	if id == knock.id:
		return _p(Knock.LANDS_AT.x, Knock.LANDS_AT.y, 2.0)
	if _slots.has(id):
		return Props.center(_slot_quad(_slots[id]))
	return _stack_top(open.size())


func _day_key() -> String:
	var d := Time.get_datetime_dict_from_unix_time(int(_now_local()))
	return "%04d-%02d-%02d" % [d["year"], d["month"], d["day"]]


func _beats(dt: float) -> void:
	if _slip_delay >= 0.0:
		_slip_delay -= dt
		if _slip_delay < 0.0:
			_show_slip(_slip_kind)
	if pets.freeze or not _seen_data:
		return
	var which := rhythm.due(_hour(), _day_key())
	if which != "":
		_begin_beat(which)


func _begin_beat(which: String) -> void:
	_slip_kind = which
	if which == "home":
		person.arrive(true)
		pets.cheer(pets.critter("argos"), "door", 3, "home")
		_slip_delay = 3.2
	else:
		person.stretch("morning.")
		pets.nudge("board", "morning")
		_slip_delay = 1.2


func _show_slip(which: String) -> void:
	_geometry()
	var rows: Array = []
	if which == "home":
		for item in open:
			rows.append(
				{"id": int(item["id"]), "label": _cap(str(item["text"]), 36), "color": _item_color(item)}
			)
		rhythm.show_slip("home", "Still open", rows)
		chat.slip("Still open", rows.map(func(r: Dictionary) -> String: return r["label"]))
		return
	var today := int(_now_local() / 86400.0)
	for item in coming:
		if item.get("due_at") != null and int(_due(item) / 86400.0) == today:
			rows.append(
				{
					"id": -1,
					"label": _clock(_due(item)) + "  " + _cap(str(item["text"]), 28),
					"color": REMINDER_COLOR
				}
			)
	if rows.is_empty():
		rows = [{"id": -1, "label": "nothing on the list today", "color": Color("5fb37a")}]
	rhythm.show_slip("morning", "Today", rows)
	chat.slip("Today", rows.map(func(r: Dictionary) -> String: return r["label"]))


func _knocking(dt: float) -> void:
	for ev in pets.events:
		if ev == "swat":
			if eggs.scene.get("k") == "push":
				eggs.pushed()
			else:
				_swat()
	pets.events = []
	if not knock.flying.is_empty():
		knock.flying["t"] += dt
		if knock.flying["t"] >= 0.7:
			var id := int(knock.flying["id"])
			knock.flying = {}
			if _open_ids().has(id):
				knock.id = id
	if pets.freeze or not _seen_data or pets.critter("nina").away:
		return
	var id := knock.due(dt, open, Time.get_unix_time_from_system(), _hour(), pets.is_night)
	if id >= 0:
		knock.pending = id
		for item in open:
			if int(item["id"]) == id:
				pets.knock_thing = str(item["text"])
		pets.knock(pets.critter("nina"))


func _swat() -> void:
	var id := knock.pending
	knock.pending = -1
	if id < 0 or not _open_ids().has(id):
		return
	_geometry()
	var from := _anchor(id)
	var color := REMINDER_COLOR
	for item in open:
		if int(item["id"]) == id:
			color = _item_color(item)
	knock.fell(id, Time.get_unix_time_from_system())
	knock.flying["from"] = (from - _o) / _k
	knock.flying["color"] = color
	_slots.erase(id)


func _draw_knock_flight() -> void:
	if knock.flying.is_empty():
		return
	var u: float = minf(knock.flying["t"] / 0.7, 1.0)
	var from: Vector2 = _o + (knock.flying["from"] as Vector2) * _k
	var to := _p(Knock.LANDS_AT.x, Knock.LANDS_AT.y, 0.5)
	var at := _arc(from, to, u)
	var pts := PackedVector2Array()
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		pts.append(at + (corner as Vector2).rotated(u * 9.0) * 3.4 * _k)
	room.draw_colored_polygon(Props.shifted(pts, Vector2(1, 2) * _k), Color(0, 0, 0, 0.2))
	room.draw_colored_polygon(pts, knock.flying["color"])


func _draw_knocked() -> void:
	var q := Props.floor_quad(_o, _k, Knock.LANDS_AT.x, Knock.LANDS_AT.y, 0.3, 0.27, 0.27, 0.5)
	var hot: bool = _hover == "item:%d" % knock.id or selected == "item:%d" % knock.id
	var color := TODO_COLOR
	for item in open:
		if int(item["id"]) == knock.id:
			color = _item_color(item)
	Props.slip(room, _k, q, color, 2, Color(0, 0, 0, 0), hot)
	_register("item:%d" % knock.id, q, Props.qlerp(q, 0.5, 0.0))


func _draw_bag() -> void:
	Person.draw_bag(room, _p(Person.BAG_AT.x, Person.BAG_AT.y), _k)


func _draw_jar() -> void:
	var poly := jar.draw(room, _o, _k)
	_register("jar", poly, (poly[2] + poly[3]) / 2.0)


func _draw_water() -> void:
	if water_left <= 0.0:
		return
	var top := _p(7.5, 0.4, 44.0)
	var tilt := -0.5 * minf(1.0, water_left)
	room.draw_set_transform(top + Vector2(-14, -4) * _k, tilt, Vector2.ONE)
	room.draw_rect(Rect2(Vector2(-6, -3) * _k, Vector2(9, 6) * _k), Color("7a8fa8"))
	room.draw_rect(Rect2(Vector2(3, -2) * _k, Vector2(6, 1.2) * _k), Color("7a8fa8"))
	room.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for i in 8:
		var ph := fposmod(_t * 1.5 + i * 0.125, 1.0)
		var at := top + Vector2(-4 + (i % 4) * 2.5, -2 + ph * 20) * _k
		room.draw_circle(at, 1.1 * _k, Color("8fc8ff", 1.0 - ph * 0.7))


func _season() -> String:
	var d := Time.get_datetime_dict_from_unix_time(int(_now_local()))
	var m: int = d["month"]
	var day: int = d["day"]
	if m == 12 or (m == 1 and day <= 6):
		return "lights"
	if m == 10 and day >= 25:
		return "pumpkin"
	if m == 2 and day >= 10 and day <= 14:
		return "hearts"
	return ""


func _celebrating() -> bool:
	if finds.is_birthday():
		return true
	var today := int(_now_local() / 86400.0)
	var texts: Array = notes.duplicate()
	for item in open:
		texts.append(str(item["text"]))
	for item in coming:
		if item.get("due_at") != null and int(_due(item) / 86400.0) == today:
			texts.append(str(item["text"]))
	for t in texts:
		var low := str(t).to_lower()
		for word in ["birthday", "bday", "anniversary"]:
			if low.contains(word):
				return true
	return false


func _draw_season(frame: PackedVector2Array) -> void:
	match _season():
		"lights":
			for i in 11:
				var u := i / 10.0
				var at := Props.qlerp(frame, u, 0.0) + Vector2(0, sin(u * PI) * 3.0 * _k + 2.0)
				var col := Color.from_hsv(fposmod(i * 0.17, 1.0), 0.6, 1.0)
				var tw := 0.55 + 0.45 * sin(_t * 3.0 + i * 1.7)
				room.draw_circle(at, 2.6 * _k, Color(col, 0.25 * tw))
				room.draw_circle(at, 1.0 * _k, Color(col, 0.6 + 0.4 * tw))
		"pumpkin":
			var at := Props.qlerp(frame, 0.82, 1.0) + Vector2(0, -3 * _k)
			room.draw_circle(at, 3.4 * _k, Color("e8842c"))
			room.draw_circle(at + Vector2(-1.6, 0) * _k, 2.2 * _k, Color("f0963c"))
			room.draw_rect(Rect2(at + Vector2(-0.4, -4.6) * _k, Vector2(1, 1.8) * _k), Color("4a6a2a"))
			if _env["day"] < 0.3:
				var glow := Color("ffd86a", 0.75 + 0.25 * sin(_t * 7.0))
				room.draw_rect(Rect2(at + Vector2(-2.2, -1.2) * _k, Vector2(1.3, 1.3) * _k), glow)
				room.draw_rect(Rect2(at + Vector2(0.9, -1.2) * _k, Vector2(1.3, 1.3) * _k), glow)
				room.draw_rect(Rect2(at + Vector2(-1.4, 1.0) * _k, Vector2(2.8, 0.9) * _k), glow)
				eggs.find("lantern")
		"hearts":
			Props.heart(room, Props.qlerp(frame, 0.82, 0.96), maxi(1, _k - 1), Color("e8576b"))


func _draw_bunting() -> void:
	if not _celebrating():
		return
	var n := 12
	var prev := Vector2.ZERO
	for i in n + 1:
		var s := 36.0 + i * (66.0 / n)
		var sag := sin(float(i) / n * PI) * 3.0
		var at := Props.wall_pt(_o, _k, 1, s, 46.0 - sag)
		if i > 0:
			room.draw_line(prev, at, Color(Props.INK, 0.6), 1.0)
			var mid := (prev + at) / 2.0
			var col: Color = CONFETTI[i % CONFETTI.size()]
			room.draw_colored_polygon(
				PackedVector2Array([prev, at, mid + Vector2(0, 5 * _k)]), col
			)
		prev = at


# a thing drawn from a sprite is hit where the sprite has a pixel, not over its whole box
func _opaque(hit: Dictionary, pos: Vector2) -> bool:
	if not hit.has("img"):
		return true
	var img: Image = hit["img"]
	var p: Vector2i = (pos - hit["at"]).floor()
	if p.x < 0 or p.y < 0 or p.x >= img.get_width() or p.y >= img.get_height():
		return false
	return img.get_pixelv(p).a > 0.1
