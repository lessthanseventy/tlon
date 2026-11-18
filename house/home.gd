extends RefCounted

const Props := preload("res://props.gd")
const Pets := preload("res://pets.gd")

const WALL_H := 48
const COLS := 8
const ROWS := 8
const DAYS := ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
const MONTH_DAYS := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
const TODO_COLOR := Color("f6e27a")
const REMINDER_COLOR := Color("f2a6b3")
const CONFETTI := [
	Color("e8b86d"), Color("d9534f"), Color("4f8fd9"), Color("5fb37a"), Color("f2a6b3")
]
const BOARD := {"s": 33.0, "h": 13.0, "w": 30.0, "hh": 31.0}
const STACK := Vector3(5.62, 0.55, 17.0)
const MUG := Vector3(4.27, 0.33, 17.0)
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

var room: Control
var pets := Pets.new()
var open: Array = []
var coming: Array = []
var notes: Array = []
var weather := "clear"
var forced_weather := ""
var fake_hour := -1.0
var say_who := ""
var force_bat := false
var show_note := -1

var _t := 0.0
var _o := Vector2.ZERO
var _k := 2
var _env := {}
var _slots := {}
var _crumples: Array = []
var _confetti: Array = []
var _hits: Array = []
var _hover := ""
var _hover_at := Vector2.ZERO
var _locked := ""
var _bin_balls := 0
var _next_text := ""
var _had_open := false
var _seen_data := false
var _scripted := {}
var _say_done := false


func setup(canvas: Control, art_dir: String, args: Array) -> void:
	room = canvas
	var seed_value := -1
	var nina_at := ""
	var argos_at := ""
	for i in args.size():
		var next: String = args[i + 1] if i + 1 < args.size() else ""
		match args[i]:
			"--at":
				var hm := next.split(":")
				fake_hour = float(hm[0]) + (float(hm[1]) / 60.0 if hm.size() > 1 else 0.0)
			"--weather":
				forced_weather = next
			"--say":
				say_who = next
			"--nina":
				nina_at = next
			"--argos":
				argos_at = next
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
	if "--shot" in args and seed_value < 0:
		seed_value = 7
	pets.is_night = _env_now()["day"] < 0.15
	pets.setup(art_dir, seed_value)
	if "--shot" in args:
		pets.freeze = true
	if pets.is_night:
		pets.place(pets.critter("nina"), "desk", "sleep")
		pets.place(pets.critter("argos"), "bed", "sleep")
	_place_arg("nina", nina_at)
	_place_arg("argos", argos_at)


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
	if Pets.SPOTS.has(parts[0]):
		pets.place(pets.critter(id), parts[0], mode)


func set_voices(v: Dictionary) -> void:
	pets.set_voices(v)


func set_weather(w: Variant) -> void:
	if w is Dictionary and w.get("kind") is String:
		weather = w["kind"]


func set_data(d: Dictionary) -> void:
	open = d["open"]
	coming = d["coming"]
	notes = d["notes"]
	var ids: Array = []
	for item in open:
		ids.append(int(item["id"]))
	for id in _slots.keys():
		if not ids.has(id):
			_slots.erase(id)
	for id in ids:
		if _slots.has(id):
			continue
		for s in SLOTS.size():
			if not _slots.values().has(s):
				_slots[id] = s
				break
	pets.has_open = not open.is_empty()
	var spot := "board" if pets.has_open else "lounge"
	if not _seen_data:
		pets.place(pets.critter("person"), spot, "sit")
	elif pets.has_open != _had_open:
		pets.go(pets.critter("person"), spot, "sit", 9999.0)
	_had_open = pets.has_open
	_seen_data = true


func _bias() -> float:
	return float(Time.get_time_zone_from_system()["bias"]) * 60.0


func _now_local() -> float:
	var n := Time.get_unix_time_from_system() + _bias()
	if fake_hour >= 0.0:
		n = floorf(n / 86400.0) * 86400.0 + fake_hour * 3600.0
	return n


func _hour() -> float:
	return fmod(_now_local() / 3600.0, 24.0)


func _env_now() -> Dictionary:
	return Props.env_at(_hour(), forced_weather if forced_weather != "" else weather)


func _clock(unix: float) -> String:
	var d := Time.get_datetime_dict_from_unix_time(int(unix))
	var day := int(unix / 86400.0)
	var today := int(_now_local() / 86400.0)
	var at := "%02d:%02d" % [d["hour"], d["minute"]]
	if day == today:
		return "today " + at
	if day == today + 1:
		return "tomorrow " + at
	return "%s %s" % [DAYS[d["weekday"]], at]


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
	_env = _env_now()
	pets.is_night = _env["day"] < 0.15
	pets.bubble_cap = 4.5
	_bin_balls += pets.process(dt)
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
			pets.say(c, pets.line(c.title, "pet" if c.id == "nina" else "pat"))
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
	_geometry()
	var found := {}
	for item in open:
		if int(item["id"]) == id:
			found = item
	if found.is_empty():
		return
	var from := _stack_top(open.size())
	var slot := -1
	if _slots.has(id):
		slot = _slots[id]
		from = Props.center(_slot_quad(slot))
	_slots.erase(id)
	var miss: bool = force_bat or pets.rng.randf() < 0.4
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
			}
		)
	)
	if open.size() == 1:
		_celebrate()


func _celebrate() -> void:
	_geometry()
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
	var argos: Pets.Critter = pets.critter("argos")
	pets.pat(argos, "done")
	pets.say(argos, pets.line("Argos", "done"))
	if pets.critter("nina").mode != "bat":
		pets.say(pets.critter("nina"), pets.line("Nina", "done"))


func _land(cr: Dictionary) -> void:
	if not cr["miss"]:
		_bin_balls += 1
		return
	var toy: Dictionary = pets.drop_toy(_center(6, 1))
	var nina: Pets.Critter = pets.critter("nina")
	pets.chase(nina, toy, 2)
	pets.say(nina, pets.line("Nina", "paper"))


func _center(c: int, r: int) -> Vector2:
	return Vector2(c + 0.5, r + 0.5)


func _bin_rim() -> Vector2:
	return _p(Pets.BIN_TOP.x, Pets.BIN_TOP.y, Pets.BIN_Z + 1.0)


func items() -> Array:
	var out: Array = [
		{"key": 3.0, "pri": 0.4, "fn": _draw_calendar},
		{"key": 3.0, "pri": 0.5, "fn": _draw_board},
		{"key": 4.0, "pri": 0.5, "fn": _draw_pane_ne},
		{"key": 5.0, "pri": 0.5, "fn": _draw_pane_nw},
		{"key": 5.0, "pri": 1.5, "fn": _draw_desk_things},
		{"key": 6.0, "pri": 1.5, "fn": _draw_bin_balls},
	]
	for t in pets.toys:
		out.append({"key": t["pos"].x + t["pos"].y - 1.0, "pri": 1.8, "fn": _draw_toy.bind(t)})
	for c in pets.critters:
		out.append({"key": pets.sort_key(c), "pri": 2.0, "fn": _draw_critter.bind(c)})
	return out


func _draw_critter(c: Pets.Critter) -> void:
	pets.draw(room, c, _o, _k)


func _draw_toy(t: Dictionary) -> void:
	var at := _p(t["pos"].x, t["pos"].y, t["z"] + 2.0)
	if t["z"] > 0.5 and t["z"] < 10.0:
		room.draw_circle(_p(t["pos"].x, t["pos"].y), 2.4 * _k, Color(0, 0, 0, 0.18))
	if t["kind"] == "yarn":
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
	_draw_bed()
	for c in pets.critters:
		if c.id != "person":
			pets.draw_shadow(room, c, _o, _k)
		else:
			room._draw_person_shadow(_o, {"col": c.pos.x - 0.5, "row": c.pos.y - 0.5})


func _ellipse(x: float, y: float, rx: float, ry: float, z: float = 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var mid := _p(x, y, z)
	for i in 24:
		var a := TAU * i / 24.0
		pts.append(mid + Vector2(cos(a) * rx, sin(a) * ry) * _k)
	return pts


func _draw_bed() -> void:
	room.draw_colored_polygon(_ellipse(6.5, 6.5, 17.0, 8.5), Color("5e3a36"))
	room.draw_colored_polygon(_ellipse(6.5, 6.5, 14.5, 7.2, 1.0), Color("a8605a"))
	room.draw_colored_polygon(_ellipse(6.5, 6.5, 10.0, 5.0, 1.0), Color("c98577"))
	room.draw_colored_polygon(_ellipse(7.5, 7.5, 6.0, 3.0), Color("4a5a78"))
	room.draw_colored_polygon(_ellipse(7.5, 7.5, 4.6, 2.2, 1.0), Color("8aa0c8"))
	room.draw_colored_polygon(_ellipse(7.5, 7.5, 3.6, 1.7, 1.5), Color("c9a86a"))


func draw_plant(f: Array) -> void:
	var s: Dictionary = room._sprite("plant_large")
	if s.is_empty():
		room._flat_box(_o, f[1], f[2], f[3], f[4], f[5], f[6])
		return
	var stage := 0 if open.size() <= 2 else (1 if open.size() <= 5 else 2)
	var tex: Texture2D = s["tex"]
	var top: Vector2 = (room._p(_o, f[1], f[2]) - s["anchor"]).round()
	var split := 27 * _k
	room.draw_texture_rect_region(
		tex,
		Rect2(top + Vector2(0, split), Vector2(tex.get_width(), tex.get_height() - split)),
		Rect2(0, split, tex.get_width(), tex.get_height() - split)
	)
	var pivot := top + Vector2(tex.get_width() / 2.0, split)
	var lean: float = [0.0, 0.09, 0.2][stage]
	var squash: float = [1.0, 0.94, 0.84][stage]
	var tint: Color = [Color.WHITE, Color(0.97, 0.96, 0.78), Color(0.9, 0.82, 0.55)][stage]
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


func _draw_pane_nw() -> void:
	Props.pane(room, _o, _k, -1, 84.0, 90.0, 19.0, 32.0, _env, _t, false)


func _register(key: String, poly: PackedVector2Array, below: Vector2) -> void:
	_hits.append({"key": key, "poly": poly, "below": below})


func _draw_board() -> void:
	var cork := Props.corkboard(room, _o, _k, BOARD["s"], BOARD["h"], BOARD["w"], BOARD["hh"])
	var n := mini(notes.size(), 4)
	var spots: Array = NOTE_SPOTS.get(n, [])
	for i in n:
		var at: Vector2 = spots[i]
		var q := Props.wall_quad(
			_o, _k, 1, BOARD["s"] + at.x, BOARD["h"] + at.y, 10.0, 8.0, NOTE_TILT[i]
		)
		var hot: bool = _hover == "note:%d" % i or _locked == "note:%d" % i
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
	var q := Props.calendar(room, _o, _k, 56.0, 31.0, d["day"], first_wd, month_days, due_day)
	_register("cal", q, Props.qlerp(q, 0.5, 0.0))


func _draw_desk_things() -> void:
	var hour := _hour()
	if hour >= 5.5 and hour < 11.5:
		Props.steam(room, _p(MUG.x, MUG.y, MUG.z), _k, _t)
	for item in open:
		var id := int(item["id"])
		if not _slots.has(id):
			continue
		var q := _slot_quad(_slots[id])
		var hot: bool = _hover == "item:%d" % id or _locked == "item:%d" % id
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
	Props.lamp_glow(room, _o, _k, _env["lamp"])
	for cr in _crumples:
		_draw_crumple(cr)
	for p in _confetti:
		if p["t"] >= 0.0:
			Props.confetti(room, p["pos"], p["color"], _k, p["spin"] + p["t"] * 6.0)
	var bounds := Rect2(Vector2.ZERO, room.size)
	for c in pets.critters:
		_draw_extras(c, bounds)
	Props.caption(room, Vector2(room.size.x / 2.0, 30), _next_text)
	_draw_card(bounds)


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
	elif _hover == "pet:" + c.id and c.id != "person":
		Props.tag(room, f + Vector2(0, 6), [c.title], bounds)


func _draw_crumple(cr: Dictionary) -> void:
	var t: float = cr["t"]
	var from: Vector2 = _o + (cr["from"] as Vector2) * _k
	if t < 0.3:
		var squash := t / 0.3
		if cr["slot"] >= 0:
			var q := _slot_quad(cr["slot"], 1.0 - 0.55 * squash, squash * 2.6)
			room.draw_colored_polygon(q, cr["color"])
		Props.paper_ball(room, from, _k, squash * 5.0, 0.35 + 0.65 * squash)
		return
	var u: float = (t - 0.3) / (float(cr["life"]) - 0.3)
	var target := _p(6.5, 1.5, 0.0) if cr["miss"] else _bin_rim()
	for i in range(3, 0, -1):
		var back := maxf(0.0, u - 0.06 * i)
		room.draw_circle(_arc(from, target, back), (3.0 - i * 0.6) * _k, Color(Props.PAPER, 0.35))
	Props.paper_ball(room, _arc(from, target, u), _k, t * 14.0, 1.2)


func _arc(from: Vector2, to: Vector2, u: float) -> Vector2:
	return from.lerp(to, u) + Vector2(0, -44.0 * _k * u * (1.0 - u))


func _draw_card(bounds: Rect2) -> void:
	var key := _hover if _hover != "" else _locked
	if show_note >= 0 and key == "":
		key = "note:%d" % show_note
	if key == "":
		return
	var text := ""
	if key.begins_with("note:"):
		var i := int(key.substr(5))
		if i < notes.size():
			text = str(notes[i])
	elif key == "more":
		var rest: Array = []
		for i in range(4, mini(notes.size(), 10)):
			rest.append("- " + str(notes[i]))
		text = "\n".join(rest)
	elif key.begins_with("item:"):
		var id := int(key.substr(5))
		for item in open:
			if int(item["id"]) == id:
				text = str(item["text"])
				if item.get("due_at") != null:
					text += "\n" + _clock(_due(item))
	elif key == "stack":
		var rest: Array = []
		for item in open.slice(0, 8):
			rest.append("- " + str(item["text"]))
		text = "\n".join(rest)
	elif key == "cal":
		var rest: Array = []
		for item in coming.slice(0, 5):
			rest.append(
				(
					(_clock(_due(item)) + "  " if item.get("due_at") != null else "")
					+ str(item["text"])
				)
			)
		text = "\n".join(rest) if not rest.is_empty() else "Nothing coming up."
	if text == "":
		return
	for h in _hits:
		if h["key"] == key:
			Props.card(room, h["below"], text, bounds)
			return


func _topmost(pos: Vector2) -> String:
	for c in pets.critters:
		if c.id != "person" and pets.hit_rect(c, _o, _k).has_point(pos):
			return "pet:" + c.id
	for i in range(_hits.size() - 1, -1, -1):
		if Geometry2D.is_point_in_polygon(pos, _hits[i]["poly"]):
			return _hits[i]["key"]
	return ""


func hover(pos: Vector2) -> bool:
	var key := _topmost(pos)
	_hover = key
	return key != ""


func click(pos: Vector2) -> bool:
	var key := _topmost(pos)
	if key.begins_with("pet:"):
		var c: Pets.Critter = pets.critter(key.substr(4))
		pets.pat(c, "pet" if c.id == "nina" else ("belly" if pets.rng.randf() < 0.25 else "pat"))
		return true
	if key != "":
		_locked = "" if _locked == key else key
		return true
	_locked = ""
	return false


func leave() -> void:
	_hover = ""
