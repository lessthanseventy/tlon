extends RefCounted

# Keys that mean something only in a row: the old code (up up down down left right left right b a) and
# four words typed anywhere in the home (never in the notepad): borges, tlon, argos, uqbar.
const Props := preload("res://props.gd")

const CODE := ["up", "up", "down", "down", "left", "right", "left", "right", "b", "a"]
const WORDS := ["borges", "tlon", "argos", "uqbar"]
const DISCO := 10.0
const SHIFT := 6.0
const MOON := 10.0
const HIST := 12
const LINES := {
	"tlon": "tlon: a room whose colours obey other laws.",
	"uqbar": "a second moon. uqbar is in no atlas.",
	"argos": ["you said my name!", "that's me! that's my name!"],
}

var _hw: WeakRef
var h:
	get:
		return _hw.get_ref()
var disco := 0.0
var shift := 0.0
var moon := 0.0
var hist: Array = []

var _beat := 0.0


func setup(home) -> void:
	_hw = weakref(home)


func _token(code: int) -> String:
	match code:
		KEY_UP:
			return "up"
		KEY_DOWN:
			return "down"
		KEY_LEFT:
			return "left"
		KEY_RIGHT:
			return "right"
	if code >= KEY_A and code <= KEY_Z:
		return char(code - KEY_A + 97)
	return ""


# a key at home; true when it finished a word or the code (and so is not also a command)
func key(code: int) -> bool:
	var tok := _token(code)
	if tok == "":
		return false
	hist.append(tok)
	if hist.size() > HIST:
		hist.pop_front()
	if hist.slice(-CODE.size()) == CODE:
		hist = []
		start_disco()
		return true
	for w in WORDS:
		if hist.size() >= w.length() and "".join(hist.slice(-w.length())) == w:
			hist = []
			word(w)
			return true
	return false


func word(w: String) -> void:
	h.eggs.find(w if w != "argos" else "argos_word")
	match w:
		"borges":
			h.finds.glow_book()
		"tlon":
			shift = SHIFT
			h.show_reply(LINES["tlon"])
		"uqbar":
			moon = MOON
			h.show_reply(LINES["uqbar"])
		"argos":
			var a = h.pets.critter("argos")
			if a.mode == "sleep":
				a.mode = "idle"
				a.anim = "idle"
			a.hops = 5
			a.wait = maxf(a.wait, 6.0)
			h.pets.say(a, LINES["argos"][h.eggs.rng.randi() % 2])
			h.sound.request("bark")


func start_disco() -> void:
	disco = DISCO
	_beat = 0.0
	h.eggs.find("konami")
	h.tv.manual = DISCO + 2.0
	h.tv.hacks.current = "spectrum"
	h.person.forced = "stretch"
	for id in ["nina", "argos"]:
		var c = h.pets.critter(id)
		c.hold = true
		c.run = false
		if c.mode == "sleep":
			c.mode = "idle"
			c.anim = "idle"
		c.path = []
		c.goal = ""
	h.sound.request("piano", 0.0)


func process(dt: float) -> void:
	shift = maxf(0.0, shift - dt)
	moon = maxf(0.0, moon - dt)
	if disco > 0.0:
		disco -= dt
		_beat -= dt
		if _beat <= 0.0:
			_beat = 0.7
			for id in ["nina", "argos"]:
				var c = h.pets.critter(id)
				if c.mode == "idle" and c.jump.is_empty():
					c.hops = 1
			h.sound.request("piano", [0, 4, 7, 12][h.eggs.rng.randi() % 4])
		if disco <= 0.0:
			disco = 0.0
			end_disco()


func end_disco() -> void:
	if h.person.forced == "stretch":
		h.person.forced = ""
	for id in ["nina", "argos"]:
		var c = h.pets.critter(id)
		c.hold = false
		c.wait = 2.0


func draw_over(c: CanvasItem) -> void:
	var o: Vector2 = h._o
	var k: int = h._k
	if disco > 0.0:
		var t: float = h._t
		var hexp := Props.hex(o, k, h.COLS, h.ROWS, h.WALL_H)
		c.draw_colored_polygon(hexp, Color.from_hsv(fposmod(t * 0.4, 1.0), 0.8, 1.0, 0.1))
		for i in 4:
			var a := t * 1.3 + i * TAU / 4.0
			var p: Vector2 = h._p(5.0 + 3.6 * cos(a), 5.0 + 3.6 * sin(a * 0.8))
			c.draw_circle(
				p, 30.0 * k * 0.5, Color.from_hsv(fposmod(t * 0.5 + i * 0.25, 1.0), 0.9, 1.0, 0.2)
			)
			c.draw_circle(
				p, 14.0 * k * 0.5, Color.from_hsv(fposmod(t * 0.5 + i * 0.25, 1.0), 0.5, 1.0, 0.25)
			)
	if shift > 0.0:
		var f := minf(1.0, shift / 1.0) * minf(1.0, (SHIFT - shift) / 0.6 + 0.001)
		var hexp := Props.hex(o, k, h.COLS, h.ROWS, h.WALL_H)
		c.draw_colored_polygon(hexp, Color.from_hsv(fposmod(h._t * 0.35, 1.0), 0.55, 0.9, 0.3 * f))
