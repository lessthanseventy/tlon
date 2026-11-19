extends RefCounted

# The soak's checks of the four looks of the light, weather, spell and font packs (`looks.gd`):
# their tables resolve to files that load, each falls back silently with no art, the four
# settings round-trip and `--plain` beats them, nothing glows by day, the weather stays in the
# glass, a cast plays once and goes, the font covers what the house prints or falls back, the
# art pack lists exactly what the loaders opened, and what the looks cost per frame.
const Looks := preload("res://looks.gd")
const Glow := preload("res://glow.gd")
const Weather := preload("res://weather.gd")
const Spells := preload("res://spells.gd")
const Fonts := preload("res://fonts.gd")
const View := preload("res://view.gd")
const Settings := preload("res://settings.gd")
const Home := preload("res://home.gd")
const ASCII_FIRST := 32
const ASCII_LAST := 126
const FRAMES := 100

var s


func _init(soak) -> void:
	s = soak


func _all(h, on: bool) -> void:
	for key in Looks.KEYS:
		h.settings.forced[key] = on


func _night(h, hour: float = 21.0) -> void:
	h.fake_hour = hour
	h.fake_day = "11-18"
	h.process(0.1)
	h._geometry()


func run() -> void:
	var art: String = s._art()
	_tables(art)
	_settings()
	var room: Control = s._room(31)
	var h = room.home
	Looks.setup(art, h.settings)
	_all(h, true)
	_glow(h)
	_weather(h)
	_spells(h)
	_loaded()
	_fonts(art, h)
	_empty(h)
	room.queue_free()


func _tables(art: String) -> void:
	Looks.setup(art, null)
	var all: Array = Glow.files() + Weather.files() + Spells.files() + Fonts.files()
	s._check(all.size() >= 12, "the four looks name their files (%d)" % all.size())
	for rel in all:
		s._check(FileAccess.file_exists(art.path_join(rel)), "look file exists: " + rel)
	for rel in Glow.files() + Weather.files() + Spells.files():
		s._check(Looks.tex(rel) != null, "look file loads: " + rel)
	for name in Spells.EFFECTS:
		var e: Dictionary = Spells.EFFECTS[name]
		s._check(
			Looks.tex(e["file"]).get_size() == Vector2(e["frames"] * Spells.CELL, Spells.CELL),
			"%s is a row of %d frames" % [name, e["frames"]]
		)
	for name in Weather.LAYERS:
		var l: Dictionary = Weather.LAYERS[name]
		var size := Looks.tex(l["file"]).get_size()
		var per: int = int(size.x / Weather.TILE) * int(size.y / Weather.TILE)
		s._check(per == l["frames"], "%s has its %d frames in the sheet" % [name, l["frames"]])
	s._check(Looks.tex("nope/not-there.png") == null, "a file that is not there is no texture")


func _settings() -> void:
	var path := "user://soak_looks_settings.json"
	DirAccess.remove_absolute(path)
	var a := Settings.new()
	a.store = path
	a.setup(true)
	for key in Looks.KEYS:
		s._check(a.value(key) == (key != "weather_art"), "%s starts as designed" % key)
		a.put(key, key == "weather_art")
	var b := Settings.new()
	b.store = path
	b.setup(true)
	for key in Looks.KEYS:
		s._check(b.value(key) == (key == "weather_art"), "%s round-trips" % key)
	DirAccess.remove_absolute(path)
	var room: Control = s._room(32)
	var plain = Home.new()
	plain.setup(room, room.art_dir, ["--plain"])
	for key in Looks.KEYS:
		s._check(plain.settings.value(key) == false, "--plain turns %s off" % key)
	var only = Home.new()
	only.setup(room, room.art_dir, ["--looks", "glow,font"])
	s._check(
		only.settings.value("glow") and only.settings.value("font"), "--looks turns the named on"
	)
	s._check(
		not only.settings.value("spells") and not only.settings.value("weather_art"),
		"and the others off"
	)
	room.queue_free()


func _glow(h) -> void:
	_night(h, 13.0)
	s._check(Glow.plan(h).is_empty(), "nothing glows by day")
	_night(h, 21.0)
	var ids := Glow.plan(h)
	s._check(ids.size() >= 2, "the lamp glows at night (%d)" % ids.size())
	h.tv.force_on(true)
	h.hearth.manual = 1
	h.hearth.process(0.1)
	_night(h, 21.0)
	var lit := Glow.plan(h)
	s._check(lit.size() > ids.size(), "a lit fire and the TV glow too (%d)" % lit.size())
	var room_outline: PackedVector2Array = lit[0]["clip"]
	for g in lit:
		s._check(g["tex"] != null and g["color"].a > 0.0, "a glow has a texture and a colour")
		s._check(not g["clip"].is_empty(), "a glow is kept inside a polygon")
	s._check(room_outline.size() == 6, "the lamp is kept inside the room's outline")
	var flick := []
	for i in 40:
		flick.append(Glow.flicker(i * 0.1))
	s._check(flick.min() >= 0.85 and flick.max() <= 1.0, "the flicker is gentle")
	s._check(flick == _again(), "and the same every time")
	_all(h, false)
	s._check(Glow.plan(h).is_empty() and not Glow.shown(), "glow off draws nothing")
	_all(h, true)
	_night(h, 21.0)
	h.fake_day = "06-15"
	h.window_frame = View.quad(h._o, h._k)
	var june := Glow.plan(h).size()
	h.fake_day = "10-28"
	s._check(h._season() == "pumpkin", "the pumpkin season")
	s._check(Glow.plan(h).size() > june, "the pumpkin glows after dark")
	h.fake_day = "11-18"
	var canvas := Control.new()
	canvas.size = Vector2(900, 700)
	canvas.draw.connect(func() -> void: Glow.draw(canvas, h))
	s.root.add_child(canvas)
	canvas.queue_redraw()
	canvas.queue_free()


func _again() -> Array:
	var out := []
	for i in 40:
		out.append(Glow.flicker(i * 0.1))
	return out


func _weather(h) -> void:
	var q := View.quad(Vector2(100, 100), 2)
	var box := Rect2(q[0], Vector2.ZERO)
	for p in q:
		box = box.expand(p)
	for w in ["rain", "storm", "snow", "fog"]:
		var plan := Weather.plan(q, 2, w, 3.0, 1.0)
		s._check(not plan.is_empty(), "%s is drawn from the pack" % w)
		for g in plan:
			for p in g["poly"]:
				s._check(box.grow(0.01).has_point(p), "%s stays inside the glass" % w)
	for w in ["clear", "partly", "cloudy"]:
		s._check(Weather.plan(q, 2, w, 3.0, 1.0).is_empty(), "%s has no overlay" % w)
	var plain := Weather.plan(q, 2, "storm", 3.0, 1.0).size()
	for flash in [3, 6, 9]:
		var t: float = flash * Weather.FLASH_EVERY - 4.2 + 0.05
		var plan := Weather.plan(q, 2, "storm", t, 1.0)
		s._check(plan.size() > plain, "a bolt strikes on flash %d" % flash)
		for g in plan:
			for p in g["poly"]:
				s._check(box.grow(0.01).has_point(p), "a bolt stays inside the glass")
	s._check(Weather.plan(q, 2, "storm", 1.5, 1.0).size() == plain, "and not between flashes")
	h.settings.forced["weather_art"] = false
	s._check(not Weather.shown("rain") and Weather.plan(q, 2, "rain", 1.0, 1.0).is_empty(), "off")
	h.settings.forced["weather_art"] = true


func _spells(h) -> void:
	h.pets.freeze = false
	h.look.stage("wear=hero,recipe=mage,weapon=staff")
	s._check(h.look.hero(), "a staff hero can be staged")
	h.quirks.perk = {"k": "cast", "st": 2, "t": 1.5}
	h.quirks.process(0.1)
	s._check(h.spells.live.size() == 1, "a cast plays one effect")
	s._check(h.spells.live[0]["name"] == "cast", "the cast effect")
	var canvas := Control.new()
	canvas.draw.connect(func() -> void: h.spells.draw(canvas, 2))
	s.root.add_child(canvas)
	canvas.queue_redraw()
	canvas.queue_free()
	for i in 30:
		h.spells.process(0.1)
	s._check(h.spells.live.is_empty(), "and it is gone after its second")
	h.fake_hour = 23.0
	h.forced_weather = "clear"
	h.process(0.1)
	h._geometry()
	h.outside.start("star")
	h.outside.wish()
	s._check(h.spells.live.size() == 1 and h.spells.live[0]["name"] == "wish", "a wish sparkles")
	h.spells.process(5.0)
	s._check(h.spells.live.is_empty(), "once")
	h.settings.forced["spells"] = false
	s._check(not h.spells.play("cast", Vector2.ZERO) and h.spells.live.is_empty(), "off plays none")
	h.settings.forced["spells"] = true
	for name in Spells.EFFECTS:
		var e: Dictionary = Spells.EFFECTS[name]
		s._check(
			float(e["frames"]) / float(e["fps"]) <= 1.1 and e["fps"] <= 10.0, "%s is ~1 s" % name
		)


func _fonts(art: String, h) -> void:
	Looks.setup(art, h.settings)
	var f := Fonts.heading()
	s._check(f is FontFile, "the heading font is the pack's")
	s._check(
		f.fixed_size == Fonts.DESIGN_SIZE and f.antialiasing == TextServer.FONT_ANTIALIASING_NONE,
		"drawn at its design size, unsmoothed"
	)
	s._check(f.fallbacks.size() == 1, "with the default font as the fallback")
	var plain := ThemeDB.fallback_font
	var lacking := ""
	var wanted := _characters()
	for c in wanted:
		if not f.has_char(c.unicode_at(0)):
			lacking += c
			s._check(f.fallbacks[0] == plain, "%s falls back to the default font" % c.unicode_at(0))
	print(
		"font: %d characters in the house's strings, Round lacks: %s" % [wanted.length(), lacking]
	)
	for c in range(ASCII_FIRST, ASCII_LAST + 1):
		s._check(f.has_char(c), "Round has " + char(c))
	var theme := ThemeDB.get_default_theme()
	Fonts.apply()
	s._check(theme.get_font("font", Fonts.HEADING) == f, "a heading label takes it")


# every character in the strings of the house's own scripts (the soak's own files left out)
func _characters() -> String:
	var seen := {}
	for file in DirAccess.get_files_at("res://"):
		if file.get_extension() != "gd" or file.begins_with("soak"):
			continue
		for c in FileAccess.get_file_as_string("res://" + file):
			if c.unicode_at(0) > 31:
				seen[c] = true
	var out := ""
	for c in seen:
		out += c
	return out


func _loaded() -> void:
	var opened: Array = Looks.loaded()
	opened.append(Fonts.FILE)
	opened.sort()
	var listed: Array = Glow.files() + Weather.files() + Spells.files() + Fonts.files()
	var unique := {}
	for rel in listed:
		unique[rel] = true
	var names: Array = unique.keys()
	names.sort()
	var missed := names.filter(func(r): return r not in opened)
	var extra := opened.filter(func(r): return r not in names)
	s._check(missed.is_empty() and extra.is_empty(), "the pack lists exactly what the looks opened: %s %s" % [missed, extra])


func _empty(h) -> void:
	Looks.setup("/nonexistent-art-dir", h.settings)
	_all(h, true)
	_night(h, 21.0)
	s._check(Glow.plan(h).is_empty() and not Glow.shown(), "no art: no glow")
	var q := View.quad(Vector2(100, 100), 2)
	s._check(Weather.plan(q, 2, "storm", 12.4, 1.0).is_empty(), "no art: no weather overlay")
	s._check(not h.spells.play("cast", Vector2.ZERO), "no art: no spell")
	s._check(Fonts.heading() == ThemeDB.fallback_font, "no art: the default font")
	Looks.setup(s._art(), h.settings)


# milliseconds per frame, the process and the draw commands of the room, over FRAMES frames; the
# dummy renderer draws no pixels, so this is the script's own cost
func measure() -> void:
	var room: Control = s._room(33)
	room.size = Vector2(800, 700)
	var h = room.home
	h.forced_weather = "storm"
	h.fake_hour = 21.0
	h.hearth.manual = 1
	h.tv.force_on(true)
	var ms := {}
	for mode in ["plain", "all four on"]:
		_all(h, mode != "plain")
		h.settings.forced["weather_art"] = mode != "plain"
		for i in 30:
			await s.process_frame
		var t0 := Time.get_ticks_usec()
		for i in FRAMES:
			room.queue_redraw()
			await s.process_frame
		ms[mode] = (Time.get_ticks_usec() - t0) / 1000.0 / FRAMES
	print(
		(
			"frame cost over %d frames: plain %.3f ms, all four on %.3f ms"
			% [FRAMES, ms["plain"], ms["all four on"]]
		)
	)
	room.queue_free()
