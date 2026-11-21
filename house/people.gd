extends RefCounted

# The people the home keeps and the pile by the door: the rules that need no scene (when a birthday
# is near, which day of a month it marks, whether the door has anything to take) and the two things
# drawn for them in the room, a framed photo on a small table and a tote by the door. A person is
# `{id, name, birthday, next_birthday, notes, todos}` as `GET /api/home` sends it; dates are local
# "YYYY-MM-DD" and a birthday "MM-DD" or "YYYY-MM-DD".
const PetThings := preload("res://pet_things.gd")

# the placed piece the framed photo is, in the layout
const PIECE := "photo_frame"
const SOON := 7
const WOOD := Color("a8794d")
const FRAME_WOOD := Color("c9964f")
const MAT := Color("efe6cf")
const HAIRS := [Color("3b2a2a"), Color("e3b95a"), Color("b5642f")]
const EYE := Color("2a2025")
const CROOK := Color("9a6a3a")
const WARM_SKY := Color("f7dca8")
const SHIRTS := [Color("e0674f"), Color("3f9aa0"), Color("e9b949")]
const HEIGHT := 35.0
const HILL := Color("6f9c62")
const SUN := Color("f3d27a")
const SKIN := Color("e6b48e")
const RIBBON := Color("d9534f")
const CANVAS := Color("d8c08e")
const STRIPE := Color("3f6fb0")
const UMBRELLA := Color("2f4f7a")
const INK_SOFT := Color(0.16, 0.14, 0.19, 0.7)
# the cell in the doorway, where the tote stands
const TOTE_CELL := Vector2i(0, 7)


# a birthday is "MM-DD" or "YYYY-MM-DD" naming a day that exists (29 Feb is one)
static func valid(birthday: Variant) -> bool:
	if not birthday is String:
		return false
	var parts := (birthday as String).split("-")
	if (
		parts.size() not in [2, 3]
		or (parts.size() == 3 and not (parts[0].length() == 4 and parts[0].is_valid_int()))
	):
		return false
	var m := parts[-2]
	var d := parts[-1]
	if m.length() != 2 or d.length() != 2 or not m.is_valid_int() or not d.is_valid_int():
		return false
	var month := int(m)
	return month >= 1 and month <= 12 and int(d) >= 1 and int(d) <= _days(month, 2000)


static func _days(month: int, year: int) -> int:
	return [31, 29 if _leap(year) else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1]


static func _leap(year: int) -> bool:
	return (year % 4 == 0 and year % 100 != 0) or year % 400 == 0


# the day of `month` a birthday falls on in `year`: 29 Feb is the 28th in a year with no 29th
static func day_in(birthday: String, year: int, month: int) -> int:
	var parts := birthday.split("-")
	if int(parts[-2]) != month:
		return 0
	var day := int(parts[-1])
	return mini(day, _days(month, year))


static func _unix(date: String) -> float:
	return Time.get_unix_time_from_datetime_string(date + "T00:00:00")


# the local date a birthday next falls on or after `today`, today counting; "" with none
static func next_birthday(birthday: Variant, today: String) -> String:
	if not valid(birthday):
		return ""
	var year := int(today.substr(0, 4))
	for y in [year, year + 1]:
		var month := int((birthday as String).split("-")[-2])
		var date := "%04d-%02d-%02d" % [y, month, day_in(birthday, y, month)]
		if date >= today:
			return date
	return ""


# whole days from `today` to the person's next birthday, -1 when they have none
static func days_to(person: Dictionary, today: String) -> int:
	var next: Variant = person.get("next_birthday")
	if not next is String or next == "":
		return -1
	return roundi((_unix(next) - _unix(today)) / 86400.0)


# the people whose birthday is today or within `within` days, the nearest first
static func soon(people: Array, today: String, within: int = SOON) -> Array:
	var out: Array = []
	for p in people:
		var n := days_to(p, today)
		if n >= 0 and n <= within:
			out.append({"person": p, "days": n})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["days"] < b["days"])
	return out.map(func(e: Dictionary) -> Dictionary: return e["person"])


# the people whose birthday is on the date `year`-`month`-`day`
static func on_day(people: Array, year: int, month: int, day: int) -> Array:
	return people.filter(
		func(p: Dictionary) -> bool:
			return valid(p.get("birthday")) and day_in(p["birthday"], year, month) == day
	)


# the days of a month that have a birthday: {day: true}
static func marks(people: Array, year: int, month: int) -> Dictionary:
	var out := {}
	for p in people:
		if valid(p.get("birthday")):
			var d := day_in(p["birthday"], year, month)
			if d > 0:
				out[d] = true
	return out


# "none" with nothing by the door, else "some": the tote is out
static func door_state(door: Dictionary) -> String:
	return "some" if not (door.get("notes", []) as Array).is_empty() else "none"


# is `name` a whole word of `text`, in any case
static func names(text: String, name: String) -> bool:
	if name.strip_edges() == "":
		return false
	var rx := RegEx.create_from_string(
		"(?i)(?<![\\p{L}\\p{N}_])" + _escape(name.strip_edges()) + "(?![\\p{L}\\p{N}_])"
	)
	return rx.search(text) != null


static func _escape(text: String) -> String:
	var out := ""
	for ch in text:
		out += ("\\" + ch) if ch in "\\^$.|?*+()[]{}" else ch
	return out


# the catalogue row of the framed photo
static func entry() -> Dictionary:
	return {
		"key": PIECE,
		"name": "photo frame",
		"kind": "floor",
		"anim": false,
		"faces": [],
		"tab": "home",
		"group": "living",
		"order": 1 * 1000 + 60,
	}


static func is_frame(p: Dictionary) -> bool:
	return p["p"] == PIECE


# the framed photo on its small table; `ribbon` ties a bow on the frame's corner
static func frame(s: PetThings.Pen, ribbon: bool) -> void:
	var a := 0.2
	var b := 0.8
	s.diamond(a - 0.04, a - 0.04, b + 0.04, b + 0.04, 0.0, Color(0, 0, 0, 0.16))
	for leg in [
		Vector2(a + 0.02, a + 0.02),
		Vector2(b - 0.12, a + 0.02),
		Vector2(a + 0.02, b - 0.12),
		Vector2(b - 0.12, b - 0.12)
	]:
		s.box(leg.x, leg.y, leg.x + 0.1, leg.y + 0.1, 0.0, 7.0, WOOD.darkened(0.3), "lr")
	s.box(a, a, b, b, 7.0, 9.0, WOOD)
	var y := 0.5
	s.box(0.1, y - 0.04, 0.9, y, 9.0, HEIGHT, FRAME_WOOD, "lr")
	var face := y + 0.004
	_quad(s, face, 0.14, 0.86, 10.5, 33.5, MAT)
	_quad(s, face, 0.18, 0.82, 12.0, 32.0, WARM_SKY)
	s.poly(
		[
			s.p(0.18, face, 12.0),
			s.p(0.82, face, 12.0),
			s.p(0.82, face, 16.0),
			s.p(0.5, face, 17.5),
			s.p(0.18, face, 15.0)
		],
		HILL
	)
	s.dot(0.74, face, 29.0, 2.2, SUN)
	_person(s, face, 0.35, 12.0, 25.0, SHIRTS[0], HAIRS[0], 2.7)
	_person(s, face, 0.65, 12.0, 25.0, SHIRTS[1], HAIRS[1], 2.7)
	_person(s, face, 0.5, 12.0, 19.5, SHIRTS[2], HAIRS[2], 2.3)
	s.outline(
		[
			s.p(0.18, face, 12.0),
			s.p(0.82, face, 12.0),
			s.p(0.82, face, 32.0),
			s.p(0.18, face, 32.0)
		],
		FRAME_WOOD.darkened(0.55)
	)
	if ribbon:
		_bow(s, s.p(0.86, face, HEIGHT))


# a head over shoulders on the photo's plane `y`: `head` is the height of the head's centre
static func _person(
	s: PetThings.Pen,
	y: float,
	x: float,
	base: float,
	head: float,
	shirt: Color,
	hair: Color,
	r: float
) -> void:
	var w := 0.12
	var neck := head - r
	s.poly(
		[
			s.p(x - w, y, base),
			s.p(x + w, y, base),
			s.p(x + w, y, neck - 1.5),
			s.p(x + w * 0.5, y, neck),
			s.p(x - w * 0.5, y, neck),
			s.p(x - w, y, neck - 1.5)
		],
		shirt
	)
	s.dot(x, y, head, r + 0.5, SKIN.darkened(0.45))
	s.dot(x, y, head, r, SKIN)
	s.dot(x, y, head + r * 0.45, r * 0.9, hair)
	s.dot(x, y, head - r * 0.15, r * 0.75, SKIN)
	for side in [-1.0, 1.0]:
		s.dot(x + side * 0.035, y, head - r * 0.1, 0.45, EYE)


static func _quad(
	s: PetThings.Pen, y: float, x0: float, x1: float, z0: float, z1: float, c: Color
) -> void:
	s.poly([s.p(x0, y, z0), s.p(x1, y, z0), s.p(x1, y, z1), s.p(x0, y, z1)], c)


# a small red bow at `knot` (a screen point)
static func _bow(s: PetThings.Pen, knot: Vector2) -> void:
	var k := s.k
	for side in [-1.0, 1.0]:
		var loop := [
			knot, knot + Vector2(side * 3.2, -2.2) * k, knot + Vector2(side * 3.2, 1.8) * k
		]
		s.poly(loop, RIBBON)
		var tail := [
			knot,
			knot + Vector2(side * 0.6, 1.0) * k,
			knot + Vector2(side * 1.8, 5.0) * k,
			knot + Vector2(side * 0.0, 4.2) * k
		]
		s.poly(tail, RIBBON.darkened(0.2))
	s.c.draw_rect(Rect2(knot - Vector2(0.8, 0.8) * k, Vector2(1.6, 1.6) * k), RIBBON.darkened(0.4))


# a canvas tote with two looped handles and an umbrella poking out, standing in the doorway
static func tote(s: PetThings.Pen) -> void:
	var x0 := 0.34
	var y0 := 0.08
	var x1 := 0.86
	var y1 := 0.6
	var mid := (y0 + y1) / 2.0
	var strap := CANVAS.darkened(0.5)
	s.diamond(x0 - 0.05, y0 - 0.05, x1 + 0.07, y1 + 0.07, 0.0, Color(0, 0, 0, 0.2))
	_handle(s, x0, y0, strap.darkened(0.2))
	s.line(s.p(x0 + 0.34, mid, 10.0), s.p(x0 + 0.34, mid, 31.0), UMBRELLA, 1.6)
	s.line(s.p(x0 + 0.34, mid, 31.0), s.p(x0 + 0.43, mid, 31.0), CROOK, 1.8)
	s.line(s.p(x0 + 0.43, mid, 31.0), s.p(x0 + 0.43, mid, 27.0), CROOK, 1.8)
	s.box(x0, y0, x1, y1, 0.0, 15.0, CANVAS, "lr")
	s.poly([s.p(x0, y1, 5.0), s.p(x1, y1, 5.0), s.p(x1, y1, 9.0), s.p(x0, y1, 9.0)], STRIPE)
	s.poly(
		[s.p(x1, y0, 5.0), s.p(x1, y1, 5.0), s.p(x1, y1, 9.0), s.p(x1, y0, 9.0)],
		STRIPE.darkened(0.25)
	)
	_handle(s, x0, y1, strap)


# a handle looped over the bag's rim on the plane `y`, from the bag's left edge `x0`
static func _handle(s: PetThings.Pen, x0: float, y: float, color: Color) -> void:
	var loop := [
		s.p(x0 + 0.08, y, 14.0),
		s.p(x0 + 0.09, y, 22.0),
		s.p(x0 + 0.14, y, 25.0),
		s.p(x0 + 0.26, y, 25.0),
		s.p(x0 + 0.32, y, 22.0),
		s.p(x0 + 0.34, y, 14.0)
	]
	for i in loop.size() - 1:
		s.line(loop[i], loop[i + 1], color, 1.4)
