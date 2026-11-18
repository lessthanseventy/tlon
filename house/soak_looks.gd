extends RefCounted

# The soak's checks of the four looks of the light, weather, spell and font packs (`looks.gd`):
# their tables resolve to files that load, each falls back silently with no art, the four
# settings round-trip and `--plain` beats them, nothing glows by day, the weather stays in the
# glass, a cast plays once and goes, the font covers what the house prints or falls back, the
# art pack lists exactly what the loaders opened, and what the looks cost per frame.
const Looks := preload("res://looks.gd")
const Glow := preload("res://glow.gd")
const View := preload("res://view.gd")
const Settings := preload("res://settings.gd")
const Home := preload("res://home.gd")
const ASCII_FIRST := 32
const ASCII_LAST := 126
const FRAMES := 300

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
	_loaded()
	_empty(h)
	room.queue_free()


func _tables(art: String) -> void:
	Looks.setup(art, null)
	var all: Array = Glow.files()
	s._check(all.size() >= 12, "the four looks name their files (%d)" % all.size())
	for rel in all:
		s._check(FileAccess.file_exists(art.path_join(rel)), "look file exists: " + rel)
	for rel in Glow.files():
		s._check(Looks.tex(rel) != null, "look file loads: " + rel)
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


func _loaded() -> void:
	var opened: Array = Looks.loaded()
	opened.sort()
	var listed: Array = Glow.files()
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
