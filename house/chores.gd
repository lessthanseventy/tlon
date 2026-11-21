extends RefCounted

# A chore is a repeating reminder whose text names one of the room's chore things. The thing shows
# how near the chore is (`state`) as an object, never as text; `home.gd` holds which row stands for
# which thing and `props`-style drawers below put it in the room.
const PetThings := preload("res://pet_things.gd")
const Card := preload("res://card.gd")

# the placed piece the laundry basket is, in the layout
const PIECE := "laundry_basket"
const STATES := ["fine", "soon", "due"]
const MOMENT := 1.1
const HOLD := 8.0
const PAUSE := 0.35
const PILLS_AT := Vector3(5.1, 0.42, 17.0)
# the first row whose words match wins: `any` is a whole word of the text, and so is one of `with`
# when it is not empty; `names` adds the pets' own names to `with`
const TABLE := [
	{"thing": "laundry", "any": ["laundry", "washing"], "with": []},
	{
		"thing": "bins",
		"any": ["trash", "bins", "bin", "garbage", "recycling", "rubbish"],
		"with": []
	},
	{"thing": "bowls", "any": ["feed"], "with": ["cat", "dog", "pets"], "names": true},
	{"thing": "pills", "any": ["meds", "medication", "pills", "vitamins"], "with": []},
	{"thing": "plant", "any": ["water"], "with": ["plant", "plants"]},
]
const NAMES := {
	"laundry": "laundry",
	"bins": "bins",
	"bowls": "feeding",
	"pills": "meds",
	"plant": "watering",
}
const WEEKDAYS := ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
const WICKER := Color("c79a5c")
const CLOTHES := [Color("5b86c9"), Color("e3a0b4"), Color("f0e2b0"), Color("7fb98a")]
const BAG := Color("4f7d68")
const BIN_RIM := 8.0
const LID := Color("8f98a8")
const AMBER := Color("d08a2e")
const INK_SOFT := Color(0.16, 0.14, 0.19, 0.7)
const CAP := Color("f1ece0")
const FOOD_LEVEL := {"fine": 1.0, "soon": 0.4, "due": 0.0}

static var _words := RegEx.create_from_string("[\\p{L}\\p{N}]+")


# the thing a chore's text names, "" for none; `names` are the pets' own names
static func thing_of(text: String, names: Array = []) -> String:
	var words: Array = []
	for m in _words.search_all(text.to_lower()):
		words.append(m.get_string())
	for row in TABLE:
		if not words.any(func(w: String) -> bool: return w in row["any"]):
			continue
		var with: Array = row["with"].duplicate()
		if row.get("names", false):
			for n in names:
				if str(n) != "":
					with.append(str(n).to_lower())
		if with.is_empty() or words.any(func(w: String) -> bool: return w in with):
			return row["thing"]
	return ""


# the seconds between two times of a repeating reminder, 0 for a rhythm that does not read
static func interval(every: String) -> float:
	var e := Card.parse_every(every)
	if e.is_empty():
		return 0.0
	var unit: float = {"day": 86400.0, "week": 604800.0, "month": 2592000.0}[e["unit"]]
	return unit * float(e["n"])


# `due` and `now` are local unix seconds: due today or gone by, past half of the way from the last
# time to the next, else far off
static func state(due: float, every: String, now: float) -> String:
	if int(due / 86400.0) <= int(now / 86400.0):
		return "due"
	var gap := interval(every)
	return "soon" if gap > 0.0 and due - now < gap / 2.0 else "fine"


static func urgency(s: String) -> int:
	return STATES.find(s)


# "due today", "due since Tue", "tomorrow", "Thursday", "28 Nov"
static func phrase(s: String, due: float, now: float) -> String:
	var d := Time.get_datetime_dict_from_unix_time(int(due))
	var gap := int(due / 86400.0) - int(now / 86400.0)
	if s == "due":
		if gap == 0:
			return "due today"
		return "due since " + (WEEKDAYS[d["weekday"]].substr(0, 3) if gap > -7 else date(d))
	if gap == 1:
		return "tomorrow"
	return WEEKDAYS[d["weekday"]] if gap <= 6 else date(d)


static func date(d: Dictionary) -> String:
	return "%d %s" % [d["day"], MONTHS[d["month"] - 1]]


static func hover(thing: String, s: String, due: float, now: float) -> String:
	return "%s · %s" % [NAMES[thing], phrase(s, due, now)]


# the catalogue row of the basket
static func entry() -> Dictionary:
	return {
		"key": PIECE,
		"name": "laundry basket",
		"kind": "floor",
		"anim": false,
		"faces": [],
		"tab": "home",
		"group": "bedroom",
		"order": 5 * 1000 + 50,
	}


static func is_basket(p: Dictionary) -> bool:
	return p["p"] == PIECE


# the basket in its cell: empty, a heap below the rim, a heap over it with a sleeve down the side.
# `lift` (0..1) is the clothes leaving, drawn above the old state while they fade
static func basket(s: PetThings.Pen, state_name: String, lift: float = 0.0) -> void:
	var a := 0.2
	var b := 0.8
	var h := 12.0
	s.diamond(a - 0.04, a - 0.04, b + 0.08, b + 0.08, 0.0, Color(0, 0, 0, 0.16))
	s.inner(a, a, b, b, 0.0, h, WICKER.darkened(0.22))
	s.diamond(a, a, b, b, 0.5, WICKER.darkened(0.45))
	match state_name:
		"soon":
			_heap(s, h - 1.0, 1.15, false, 1.0)
		"due":
			_heap(s, h + 1.0, 1.0, true, 1.0)
	if lift > 0.0:
		_heap(s, h + 1.0 + lift * 12.0, 1.0, true, 1.0 - lift)
	s.front(a, a, b, b, h, WICKER)
	for z in [3.5, 7.5]:
		s.line(s.p(a, b, z), s.p(b, b, z), WICKER.darkened(0.28), 0.5)
		s.line(s.p(b, a, z), s.p(b, b, z), WICKER.darkened(0.45), 0.5)
	if state_name == "due":
		_sleeve(s, h)


# the pile of clothes: the lowest cloth at `z`, `size` its width, `tall` with more cloth on top
static func _heap(s: PetThings.Pen, z: float, size: float, tall: bool, alpha: float) -> void:
	var c: Color = CLOTHES[0]
	s.ell(0.5, 0.5, 8.0 * size, 4.0 * size, z, Color(c, alpha))
	var up: Color = CLOTHES[1]
	if tall:
		s.ell(0.43, 0.5, 6.0, 3.0, z + 3.5, Color(up, alpha))
		var top: Color = CLOTHES[2]
		s.ell(0.58, 0.46, 4.6, 2.3, z + 6.0, Color(top, alpha))
	else:
		s.ell(0.58, 0.5, 4.2, 2.1, z + 1.0, Color(up, alpha))


static func _sleeve(s: PetThings.Pen, h: float) -> void:
	var tone: Color = CLOTHES[3]
	var x := 0.62
	s.poly(
		[
			s.p(x - 0.09, 0.8, h + 5.0),
			s.p(x + 0.09, 0.8, h + 5.0),
			s.p(x + 0.1, 0.8, h - 8.0),
			s.p(x - 0.08, 0.8, h - 8.0)
		],
		tone
	)
	s.outline(
		[
			s.p(x - 0.09, 0.8, h + 5.0),
			s.p(x + 0.09, 0.8, h + 5.0),
			s.p(x + 0.1, 0.8, h - 8.0),
			s.p(x - 0.08, 0.8, h - 8.0)
		],
		INK_SOFT
	)
	s.line(s.p(x - 0.08, 0.8, h - 5.5), s.p(x + 0.1, 0.8, h - 5.5), tone.darkened(0.35), 1.2)


# the bin's lid over its mouth (`Pets.BIN_TOP` a little above the sprite's rim): shut, lifted at the
# back, or flipped up behind the bin
static func bin_lid(s: PetThings.Pen, state_name: String) -> void:
	var at := Vector2(6.5, 0.5)
	var z := BIN_RIM
	if state_name == "fine":
		s.ell(at.x, at.y, 6.2, 3.1, z - 0.6, LID.darkened(0.3))
		s.ell(at.x, at.y, 5.6, 2.8, z + 0.4, LID)
		s.ell(at.x, at.y, 1.3, 0.7, z + 1.4, LID.lightened(0.35))
		return
	s.ell(at.x, at.y, 5.0, 2.5, z, Color("1d1b22"))
	if state_name == "soon":
		s.ell(at.x - 0.1, at.y - 0.14, 5.6, 2.8, z + 2.6, LID.darkened(0.3))
		s.ell(at.x - 0.1, at.y - 0.14, 5.0, 2.5, z + 3.4, LID)


# the lid set down on the floor beside the bin
static func lid_down(s: PetThings.Pen) -> void:
	s.ell(6.26, 1.2, 5.6, 2.8, 0.0, LID.darkened(0.3))
	s.ell(6.26, 1.2, 5.0, 2.5, 1.0, LID)
	s.ell(6.26, 1.2, 1.4, 0.8, 2.4, LID.lightened(0.35))


# a tied bag on the floor in front of the bin; `fade` (0..1) lifts it away
static func bag(s: PetThings.Pen, fade: float = 0.0) -> void:
	var at := Vector2(6.78, 1.14)
	var rise := fade * 12.0
	var a := 1.0 - fade
	s.ell(at.x, at.y, 5.4, 2.2, 0.0, Color(0, 0, 0, 0.22 * a))
	s.ell(at.x, at.y, 4.6, 3.6, 3.0 + rise, Color(BAG.darkened(0.25), a))
	s.ell(at.x - 0.02, at.y - 0.02, 4.0, 3.4, 5.4 + rise, Color(BAG, a))
	s.ell(at.x - 0.1, at.y - 0.08, 1.4, 0.8, 7.6 + rise, Color(BAG.lightened(0.5), 0.7 * a))
	var tip := s.p(at.x, at.y, 8.0 + rise)
	s.poly(
		[tip + Vector2(-1.6, 1) * s.k, tip + Vector2(0, -3.6) * s.k, tip + Vector2(1.6, 1) * s.k],
		Color(BAG.darkened(0.1), a)
	)


# the fly over the bag, one small loop
static func fly(s: PetThings.Pen, t: float) -> void:
	var u := t * 2.4
	var at := s.p(6.7 + 0.16 * cos(u), 1.05 + 0.12 * sin(u * 1.3), 14.0 + 3.0 * sin(u * 2.0))
	s.c.draw_rect(Rect2(at, Vector2(1.5, 1.5) * s.k), INK_SOFT)


# the pill bottle on the desk top at `at` (cell units, z the desk's): on its side, upright, or
# upright with the cap off and set down beside it
static func bottle(s: PetThings.Pen, at: Vector3, state_name: String) -> void:
	var x := at.x
	var y := at.y
	var z := at.z
	if state_name == "fine":
		s.ell(x + 0.04, y, 7.0, 3.0, z, Color(0, 0, 0, 0.2))
		s.box(x - 0.13, y - 0.06, x + 0.11, y + 0.06, z, z + 4.8, AMBER, "tlr")
		s.box(x + 0.11, y - 0.06, x + 0.2, y + 0.06, z, z + 4.8, CAP, "tlr")
		s.box(x - 0.06, y + 0.06, x + 0.05, y + 0.062, z + 0.8, z + 4.0, CAP.darkened(0.05), "l")
		return
	s.ell(x, y, 5.0, 2.4, z, Color(0, 0, 0, 0.2))
	s.box(x - 0.08, y - 0.08, x + 0.08, y + 0.08, z, z + 9.0, AMBER, "tlr")
	s.box(x - 0.08, y + 0.08, x + 0.07, y + 0.082, z + 2.0, z + 6.5, CAP, "l")
	if state_name == "soon":
		s.box(x - 0.09, y - 0.09, x + 0.09, y + 0.09, z + 9.0, z + 11.6, CAP, "tlr")
	else:
		s.diamond(x - 0.07, y - 0.07, x + 0.07, y + 0.07, z + 9.0, Color("2a1a10"))
		s.ell(x + 0.34, y + 0.14, 3.6, 1.8, z + 0.5, CAP.darkened(0.1))
		s.ell(x + 0.34, y + 0.14, 3.6, 1.6, z + 2.0, CAP)


# a few sparks rising from `at` (a screen point) for the moment a chore is done
static func sparks(canvas: CanvasItem, at: Vector2, k: float, u: float) -> void:
	for i in 5:
		var ang := float(i) * 1.25 + 0.4
		var rise := u * (10.0 + 4.0 * float(i % 3))
		var p := at + Vector2(cos(ang) * 8.0 * u, -rise - 4.0) * k
		canvas.draw_circle(p, 1.2 * k, Color("f6e7a8", 1.0 - u))
