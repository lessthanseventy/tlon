extends RefCounted

# Small objects to find in the room: the birthday cake, the bookshelf's books, the snow globe, the
# mouse and its hole (whose card counts the secrets he has found).
const Props := preload("res://props.gd")
const Settings := preload("res://settings.gd")

const TITLES := [
	["Ficciones", "stories that fold into themselves"],
	["The Aleph", "a point that holds every point"],
	["Labyrinths", "paths that fork and then agree"],
	["The Book of Sand", "it has no first page and no last"],
	["A Universal History of Infamy", "rogues, told elegantly"],
	["Dreamtigers", "a small book of sketches and mirrors"],
	["The Maker", "short pieces, long shadows"],
	["Collected Fictions", "everything, in one heavy volume"],
	["The Garden of Forking Paths", "a spy, a maze, a book"],
	["The Library of Babel", "every book, and most of them nonsense"],
	["Tlon, Uqbar, Orbis Tertius", "an encyclopedia of a place that is not there"],
	["The Book of Imaginary Beings", "a zoo with no cages"],
	["In Praise of Darkness", "late poems, calm"],
	["Seven Nights", "lectures about dreams and a few other things"],
	["Fervor de Buenos Aires", "the city, in his first poems"],
	["The Total Library", "an essay with a very large room in it"],
]
const BUILT_IN := [
	"this one smells like dust. I like it.",
	"read it twice. it was different the second time.",
	"I sat on it. that counts as reading.",
	"a lot of mirrors in there.",
]
const BABEL := [
	"The Library is unlimited and cyclical.",
	"Everything: the minutely detailed history of the future.",
	"It is a sphere whose exact centre is any hexagon.",
	"For every sensible line there are leagues of cacophony.",
]
const WIDTHS := 40.0
const MOUSE_HOLE := Vector2(2.25, 0.6)

var _hw: WeakRef
var h:
	get:
		return _hw.get_ref()
var birthday: String:
	get:
		return str(h.settings.value("birthday"))
var birthday_forced := false
var candles := true
var book := {}
var shake := 0.0
var mouse := {}
var last_touch := 0.0
var glow := 0.0
var line_left := 0.0
var line_text := ""

var _mouse_next := 600.0
var _t := 0.0


func setup(home) -> void:
	_hw = weakref(home)
	_mouse_next = h.eggs.rng.randf_range(300.0, 900.0)


func today_key() -> String:
	var d := Time.get_datetime_dict_from_unix_time(int(h._now_local()))
	return "%02d-%02d" % [d["month"], d["day"]]


func is_birthday() -> bool:
	return birthday_forced or (birthday != "" and birthday == today_key())


# the calendar card's button: today is, or is no longer, his birthday
func toggle_birthday() -> void:
	h.settings.put("birthday", "" if birthday == today_key() else today_key())
	candles = true


func touch() -> void:
	last_touch = _t
	if not mouse.is_empty():
		_scare()


func process(dt: float) -> void:
	_t += dt
	shake = maxf(0.0, shake - dt)
	glow = maxf(0.0, glow - dt)
	line_left = maxf(0.0, line_left - dt)
	if not mouse.is_empty():
		_run_mouse(dt)
	elif not h.pets.freeze:
		_mouse_next -= dt
		if _mouse_next <= 0.0:
			_mouse_next = h.eggs.rng.randf_range(900.0, 2400.0)
			if quiet_night():
				start_mouse()


func quiet_night() -> bool:
	var hour: float = h._hour()
	return (
		(hour >= 22.0 or hour < 5.0)
		and _t - last_touch > 300.0
		and h.eggs.calm()
		and not h.jot_open
	)


func start_mouse() -> void:
	if mouse.is_empty():
		mouse = {"t": 0.0, "out": h.eggs.rng.randf_range(1.2, 2.0)}
		h.eggs.find("mouse")


func _scare() -> void:
	mouse = {}
	h.sound.request("squeak")


# a pet that is up and near sends it home
func _run_mouse(dt: float) -> void:
	mouse["t"] += dt
	var at := mouse_pos()
	for id in ["nina", "argos"]:
		var c = h.pets.critter(id)
		if not c.away and c.mode != "sleep" and c.pos.distance_to(at) < 4.0:
			_scare()
			return
	if mouse["t"] > 6.0:
		mouse = {}


func mouse_pos() -> Vector2:
	if mouse.is_empty():
		return MOUSE_HOLE
	var t: float = mouse["t"]
	var f := clampf(t / 1.5, 0.0, 1.0) if t < 4.5 else clampf((6.0 - t) / 1.5, 0.0, 1.0)
	return Vector2(MOUSE_HOLE.x + 0.15 * sin(t * 3.0), MOUSE_HOLE.y + 1.6 * f)


func pick_book() -> void:
	var r: RandomNumberGenerator = h.eggs.rng
	var t: Array = TITLES[r.randi() % TITLES.size()]
	var who: String = "Nina" if r.randf() < 0.5 else "Argos"
	if h.pets.critter(who.to_lower()).away:
		who = "Argos" if who == "Nina" else "Nina"
	if h.pets.critter(who.to_lower()).away:
		who = ""
	var said: String = h.pets.line(who, "muse")
	if said == "" or said.contains("{thing}"):
		said = BUILT_IN[r.randi() % BUILT_IN.size()]
	book = {"title": t[0], "about": t[1], "who": who, "blurb": said}
	h.eggs.find("book")


func _said(b: Dictionary) -> String:
	var who: String = b.get("who", "")
	return str(b.get("blurb", "")) if who == "" else "%s: %s" % [who, b.get("blurb", "")]


func glow_book() -> void:
	glow = 5.0
	line_text = BABEL[h.eggs.rng.randi() % BABEL.size()]
	h.show_reply(line_text)
	line_left = 7.0
	h.eggs.find("borges")


func blocks(kind: String) -> Array:
	if kind == "book":
		return [
			{"t": "title", "text": str(book.get("title", ""))},
			{"t": "dim", "text": "Jorge Luis Borges - " + str(book.get("about", ""))},
			{"t": "gap"},
			{"t": "text", "text": Settings.pets(_said(book))},
		]
	var out: Array = [{"t": "title", "text": "Found so far"}]
	var n: int = h.eggs.found.size()
	out.append({"t": "text", "text": "%d of %d" % [n, h.eggs.CATALOGUE.size()]})
	for row in h.eggs.CATALOGUE:
		if h.eggs.found.has(row[0]):
			out.append({"t": "dim", "text": "- " + Settings.pets(str(row[1]))})
	return out


func table() -> Dictionary:
	for name in ["dining_table", "round_table", "side_table"]:
		var p: Dictionary = h.eggs.piece(name)
		if not p.is_empty():
			return p
	return {}


func globe_spot() -> Vector3:
	var p: Dictionary = h.eggs.piece("side_table")
	if p.is_empty():
		return Vector3(5.9, 0.45, 17.0)
	var r: Rect2i = h.layout.rect(p)
	return Vector3(r.position.x + 0.5, r.position.y + 0.5, float(h.layout.height(p)))


func items() -> Array:
	var out: Array = []
	var gs := globe_spot()
	out.append({"key": gs.x + gs.y - 0.4, "pri": 1.9, "fn": _draw_globe})
	if is_birthday() and not table().is_empty():
		var r: Rect2i = h.layout.rect(table())
		out.append({"key": float(h.layout.draw_key(table())) + 0.5, "pri": 1.9, "fn": _draw_cake})
	out.append({"key": 3.0, "pri": 0.6, "fn": _draw_hole})
	if not mouse.is_empty():
		var p := mouse_pos()
		out.append({"key": p.x + p.y - 1.0, "pri": 1.7, "fn": _draw_mouse})
	return out


func _draw_hole() -> void:
	var k: int = h._k
	var a := Props.wall_pt(h._o, k, 1, 16.0 * MOUSE_HOLE.x, 0.0)
	c_hole(a, k)
	h._register(
		"mousehole",
		PackedVector2Array(
			[
				a + Vector2(-5, -9) * k,
				a + Vector2(6, -9) * k,
				a + Vector2(6, 3) * k,
				a + Vector2(-5, 3) * k
			]
		),
		a
	)


func c_hole(a: Vector2, k: int) -> void:
	var c: CanvasItem = h.room
	c.draw_colored_polygon(
		(
			PackedVector2Array(
				[
					a + Vector2(-4, 0) * k,
					a + Vector2(-4, -4) * k,
					a + Vector2(-2, -6.5) * k,
					a + Vector2(2, -6.5) * k,
					a + Vector2(4, -4) * k,
					a + Vector2(4, 0) * k
				]
			)
			. duplicate()
		),
		Color("1a1218")
	)
	c.draw_line(a + Vector2(-5, 0.6) * k, a + Vector2(5, 0.6) * k, Color("6b4528"), maxf(1.0, k))


func _draw_mouse() -> void:
	var k: int = h._k
	var p := mouse_pos()
	var at: Vector2 = h._p(p.x, p.y)
	var c: CanvasItem = h.room
	c.draw_rect(Rect2(at + Vector2(-2, -2.6) * k, Vector2(4, 2.4) * k), Color("a8a4a0"))
	c.draw_circle(at + Vector2(2.4, -1.6) * k, 1.2 * k, Color("a8a4a0"))
	c.draw_circle(at + Vector2(1.6, -3) * k, 0.8 * k, Color("e8b0b8"))
	c.draw_rect(Rect2(at + Vector2(3.2, -1.9) * k, Vector2(k * 0.6, k * 0.6)), Props.INK)
	c.draw_line(
		at + Vector2(-2, -1) * k,
		at + Vector2(-5, -2 + sin(_t * 8.0)) * k,
		Color("e8b0b8"),
		maxf(1.0, 0.6 * k)
	)


func _draw_globe() -> void:
	var k: int = h._k
	var gs := globe_spot()
	var at: Vector2 = h._p(gs.x, gs.y, gs.z)
	var c: CanvasItem = h.room
	c.draw_rect(Rect2(at + Vector2(-3, -2) * k, Vector2(6, 2) * k), Color("6b4528"))
	c.draw_circle(at + Vector2(0, -6) * k, 4.2 * k, Color(0.8, 0.92, 1.0, 0.45))
	c.draw_colored_polygon(
		PackedVector2Array(
			[at + Vector2(-1.6, -2.4) * k, at + Vector2(1.6, -2.4) * k, at + Vector2(0, -5) * k]
		),
		Color("c8483f")
	)
	var n := 12 if shake > 0.0 else 4
	for i in n:
		var ph := fposmod(_t * (2.0 if shake > 0.0 else 0.3) + i * 0.37, 1.0)
		var sx := sin(i * 2.1 + _t * (6.0 if shake > 0.0 else 1.0)) * 3.0
		c.draw_rect(Rect2(at + Vector2(sx, -9.5 + ph * 7.0) * k, Vector2(k, k) * 0.9), Color.WHITE)
	c.draw_circle(at + Vector2(-1.5, -8) * k, 0.9 * k, Color(1, 1, 1, 0.5))
	var r := 6.0 * k
	h._register(
		"globe",
		PackedVector2Array(
			[
				at + Vector2(-r, -r * 2.0),
				at + Vector2(r, -r * 2.0),
				at + Vector2(r, 0),
				at + Vector2(-r, 0)
			]
		),
		at
	)


func _draw_cake() -> void:
	var k: int = h._k
	var p: Dictionary = table()
	var r: Rect2i = h.layout.rect(p)
	var at: Vector2 = h._p(
		r.position.x + r.size.x / 2.0, r.position.y + r.size.y / 2.0, float(h.layout.height(p))
	)
	var c: CanvasItem = h.room
	c.draw_rect(Rect2(at + Vector2(-6, -1) * k, Vector2(12, 1.2) * k), Color("e8e4dc"))
	c.draw_rect(Rect2(at + Vector2(-5, -5) * k, Vector2(10, 4) * k), Color("f2a6b3"))
	c.draw_rect(Rect2(at + Vector2(-5, -6) * k, Vector2(10, 1.4) * k), Color("fff4e0"))
	c.draw_rect(Rect2(at + Vector2(-3.5, -8.5) * k, Vector2(7, 2.6) * k), Color("e8b86d"))
	for i in 3:
		var x := -2.4 + i * 2.4
		c.draw_rect(
			Rect2(at + Vector2(x, -11) * k, Vector2(0.9, 2.6) * k),
			Color("4f8fd9") if i != 1 else Color("d9534f")
		)
		if candles:
			var fl := 0.8 + 0.2 * sin(_t * 9.0 + i)
			c.draw_circle(at + Vector2(x + 0.45, -12) * k, 1.1 * k * fl, Color("ffd86a"))
			c.draw_circle(at + Vector2(x + 0.45, -12) * k, 2.4 * k * fl, Color(1, 0.85, 0.4, 0.2))
	var q := 8.0 * k
	h._register(
		"cake",
		PackedVector2Array(
			[
				at + Vector2(-q, -q * 1.7),
				at + Vector2(q, -q * 1.7),
				at + Vector2(q, 0),
				at + Vector2(-q, 0)
			]
		),
		at
	)
	h.eggs.find("cake")
