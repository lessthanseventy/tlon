extends RefCounted

# The pets' things: what each is, who it is for, and how it is drawn in code. A thing is a layout
# piece named `pet.<key>`; `petlife.gd` decides where it stands and what a pet does with it.
const PREFIX := "pet."
const INK := Color("2a2530")
const DOG := ["dog", "wolf", "fox"]
const FARM := ["cow", "horse", "sheep", "deer", "rabbit", "chicken"]
const HOOF := ["cow", "horse", "sheep", "deer"]
const WALLOW := ["pig", "boar"]
const BLANKET := ["pig", "boar", "bear"]
const BIG := ["cow", "horse", "bear"]
const SMALL := ["cat", "rabbit", "chicken", "fox"]
const SWITCH := {"litter": "litter_box", "bowls": "bowls", "things": "pet_things"}
# the platform tops of the tower and the cube's centre, for a thing that is perched on: [x, y, z]
const TOWER_TOP := Vector3(0.64, 0.25, 47.0)
const TOWER_BAT := Vector3(0.5, 0.78, 27.0)
const TOWER_CUBE := Vector3(0.33, 0.64, 4.5)
const TOWER_PINK := Color("f08cb4")
const SISAL := Color("e6d3a2")

# kinds: species it is for (empty: every animal); mode: flat (walked over, no blocking), walk
# (flat with walls, a pet stands in it) or solid (blocks, used from beside it); h: height in px;
# faces: the sides it can be turned to; def: put out by itself; sw: the master switch; raised: a
# flat thing drawn with the furniture, above the floor
const THINGS := {
	"bowls":
	{
		"name": "bowls",
		"group": "everyone",
		"kinds": [],
		"mode": "flat",
		"h": 0,
		"faces": [],
		"def": true,
		"sw": "bowls"
	},
	"bed_round":
	{
		"name": "round bed",
		"group": "everyone",
		"kinds": [],
		"mode": "flat",
		"h": 0,
		"faces": [],
		"def": true,
		"sw": "things",
		"no": ["chicken"]
	},
	"bed_cushion":
	{
		"name": "cushion bed",
		"group": "everyone",
		"kinds": [],
		"mode": "flat",
		"h": 0,
		"faces": ["sw", "se"],
		"def": true,
		"sw": "things",
		"no": ["chicken"]
	},
	"litter":
	{
		"name": "litter box",
		"group": "cats",
		"kinds": ["cat"],
		"mode": "walk",
		"h": 6,
		"faces": [],
		"def": true,
		"sw": "litter"
	},
	"post":
	{
		"name": "scratch post",
		"group": "cats",
		"kinds": ["cat"],
		"mode": "solid",
		"h": 27,
		"faces": [],
		"def": true,
		"sw": "things"
	},
	"tower":
	{
		"name": "cat tower",
		"group": "cats",
		"kinds": ["cat"],
		"mode": "solid",
		"h": 50,
		"faces": ["sw", "se"],
		"def": true,
		"sw": "things"
	},
	"window_perch":
	{
		"name": "window perch",
		"group": "cats",
		"kinds": ["cat"],
		"mode": "flat",
		"h": 0,
		"faces": [],
		"def": true,
		"sw": "things",
		"raised": true
	},
	"cardbox":
	{
		"name": "cardboard box",
		"group": "cats",
		"kinds": ["cat"],
		"mode": "walk",
		"h": 8,
		"faces": [],
		"def": false,
		"sw": "things"
	},
	"fish":
	{
		"name": "fish toy",
		"group": "cats",
		"kinds": ["cat"],
		"mode": "flat",
		"h": 0,
		"faces": [],
		"def": false,
		"sw": "things"
	},
	"aquarium":
	{
		"name": "aquarium",
		"group": "cats",
		"kinds": ["cat"],
		"mode": "solid",
		"h": 27,
		"faces": [],
		"def": false,
		"sw": "things"
	},
	"bone":
	{
		"name": "bone",
		"group": "dogs",
		"kinds": DOG,
		"mode": "flat",
		"h": 0,
		"faces": [],
		"def": true,
		"sw": "things"
	},
	"rope":
	{
		"name": "rope toy",
		"group": "dogs",
		"kinds": DOG,
		"mode": "flat",
		"h": 0,
		"faces": [],
		"def": false,
		"sw": "things"
	},
	"balls":
	{
		"name": "tennis balls",
		"group": "dogs",
		"kinds": DOG,
		"mode": "solid",
		"h": 12,
		"faces": [],
		"def": false,
		"sw": "things"
	},
	"perch":
	{
		"name": "perch",
		"group": "chickens",
		"kinds": ["chicken"],
		"mode": "solid",
		"h": 20,
		"faces": ["sw", "se"],
		"def": true,
		"sw": "things"
	},
	"nest":
	{
		"name": "nest box",
		"group": "chickens",
		"kinds": ["chicken"],
		"mode": "walk",
		"h": 6,
		"faces": [],
		"def": true,
		"sw": "things"
	},
	"hutch":
	{
		"name": "bunny house",
		"group": "rabbits",
		"kinds": ["rabbit"],
		"mode": "walk",
		"h": 14,
		"faces": [],
		"def": true,
		"sw": "things"
	},
	"carrot":
	{
		"name": "carrot",
		"group": "rabbits",
		"kinds": ["rabbit"],
		"mode": "flat",
		"h": 0,
		"faces": [],
		"def": false,
		"sw": "things"
	},
	"hay":
	{
		"name": "hay bale",
		"group": "farm animals",
		"kinds": FARM,
		"mode": "solid",
		"h": 14,
		"faces": [],
		"def": true,
		"sw": "things",
		"art": true
	},
	"trough":
	{
		"name": "trough",
		"group": "farm animals",
		"kinds": HOOF + WALLOW,
		"mode": "solid",
		"h": 9,
		"faces": ["sw", "se"],
		"def": true,
		"sw": "bowls"
	},
	"salt":
	{
		"name": "salt lick",
		"group": "farm animals",
		"kinds": HOOF,
		"mode": "solid",
		"h": 12,
		"faces": [],
		"def": false,
		"sw": "things"
	},
	"pool":
	{
		"name": "kiddie pool",
		"group": "pigs",
		"kinds": WALLOW,
		"mode": "flat",
		"h": 0,
		"faces": [],
		"def": true,
		"sw": "things"
	},
	"blanket":
	{
		"name": "blanket",
		"group": "pigs",
		"kinds": BLANKET,
		"mode": "flat",
		"h": 0,
		"faces": [],
		"def": true,
		"sw": "things"
	},
	"log":
	{
		"name": "scratch log",
		"group": "bears",
		"kinds": ["bear"],
		"mode": "solid",
		"h": 11,
		"faces": ["sw", "se"],
		"def": true,
		"sw": "things"
	},
	"honey":
	{
		"name": "honey pot",
		"group": "bears",
		"kinds": ["bear"],
		"mode": "solid",
		"h": 12,
		"faces": [],
		"def": false,
		"sw": "things"
	},
}
const GROUPS := ["everyone", "cats", "dogs", "chickens", "rabbits", "farm animals", "pigs", "bears"]


static func is_pet(p: Dictionary) -> bool:
	return str(p["p"]).begins_with(PREFIX)


static func key_of(p: Dictionary) -> String:
	return str(p["p"]).trim_prefix(PREFIX)


static func fits(key: String, species: Array) -> bool:
	var t: Dictionary = THINGS[key]
	return species.any(
		func(s): return (t["kinds"].is_empty() or s in t["kinds"]) and s not in t.get("no", [])
	)


# the catalogue rows the layout adds, in the order of the pets tab
static func entries() -> Array:
	var out: Array = []
	for key in THINGS:
		var t: Dictionary = THINGS[key]
		var order := GROUPS.find(t["group"]) * 100 + out.size()
		(
			out
			. append(
				{
					"key": PREFIX + key,
					"name": t["name"],
					"kind": "floor" if t["mode"] == "solid" else "flat",
					"anim": false,
					"faces": t["faces"].duplicate(),
					"tab": "pets",
					"group": t["group"],
					"order": order,
				}
			)
		)
	return out


# a pen draws in a thing's own cell coordinates: (0,0) is the cell's back corner, (1,1) the front
class Pen:
	extends RefCounted
	var c: CanvasItem
	var o := Vector2.ZERO
	var k := 2.0
	var tint := Color.WHITE
	var flip := false

	func _init(
		canvas: CanvasItem, origin: Vector2, scale: float, turned := false, mod := Color.WHITE
	):
		c = canvas
		o = origin
		k = scale
		flip = turned
		tint = mod

	func q(x: float, y: float, z: float = 0.0) -> Vector2:
		return (o + Vector2(16.0 * (x - y), 8.0 * (x + y) - z) * k).round()

	func p(x: float, y: float, z: float = 0.0) -> Vector2:
		return q(y, x, z) if flip else q(x, y, z)

	func col(color: Color) -> Color:
		return color * tint

	func poly(pts: Array, color: Color) -> void:
		c.draw_colored_polygon(PackedVector2Array(pts), col(color))

	func line(a: Vector2, b: Vector2, color: Color, w: float = 1.0) -> void:
		c.draw_line(a, b, col(color), maxf(1.0, round(w * k)))

	func outline(pts: Array, color: Color = INK) -> void:
		var closed := PackedVector2Array(pts)
		closed.append(pts[0])
		c.draw_polyline(closed, col(color), maxf(1.0, round(0.7 * k)))

	# below two pixels across the polygon cannot be triangulated: nothing is drawn
	func ell(x: float, y: float, rx: float, ry: float, z: float, color: Color) -> bool:
		if rx * k < 2.0 or ry * k < 1.0:
			return false
		var mid := p(x, y, z)
		var pts: Array = []
		for i in 20:
			var a := TAU * i / 20.0
			pts.append((mid + Vector2(cos(a) * rx, sin(a) * ry) * k).round())
		poly(pts, color)
		return true

	func dot(x: float, y: float, z: float, r: float, color: Color) -> void:
		c.draw_circle(p(x, y, z), r * k, col(color))

	# a block: `faces` picks t(op), l(eft, the side at y1) and r(ight, the side at x1)
	func box(
		x0: float,
		y0: float,
		x1: float,
		y1: float,
		z0: float,
		z1: float,
		base: Color,
		faces := "tlr",
		edge := INK
	) -> void:
		var f := faces
		if flip:
			var t := x0
			x0 = y0
			y0 = t
			t = x1
			x1 = y1
			y1 = t
			f = faces.replace("l", "x").replace("r", "l").replace("x", "r")
		if "r" in f:
			var face := [q(x1, y0, z0), q(x1, y1, z0), q(x1, y1, z1), q(x1, y0, z1)]
			poly(face, base.darkened(0.25))
			outline(face, edge)
		if "l" in f:
			var face := [q(x0, y1, z0), q(x1, y1, z0), q(x1, y1, z1), q(x0, y1, z1)]
			poly(face, base)
			outline(face, edge)
		if "t" in f:
			var face := [q(x0, y0, z1), q(x1, y0, z1), q(x1, y1, z1), q(x0, y1, z1)]
			poly(face, base.lightened(0.22))
			outline(face, edge)

	func diamond(x0: float, y0: float, x1: float, y1: float, z: float, color: Color) -> void:
		poly([p(x0, y0, z), p(x1, y0, z), p(x1, y1, z), p(x0, y1, z)], color)

	# the back inside of an open box
	func inner(
		x0: float, y0: float, x1: float, y1: float, z0: float, z1: float, base: Color
	) -> void:
		var a := [p(x0, y0, z0), p(x0, y1, z0), p(x0, y1, z1), p(x0, y0, z1)]
		var b := [p(x0, y0, z0), p(x1, y0, z0), p(x1, y0, z1), p(x0, y0, z1)]
		poly(a, base.darkened(0.12))
		poly(b, base)
		outline(a)
		outline(b)

	# the front walls of an open box, as boxes' own faces seen from outside
	func front(x0: float, y0: float, x1: float, y1: float, z1: float, base: Color) -> void:
		var a := [p(x0, y1, 0.0), p(x1, y1, 0.0), p(x1, y1, z1), p(x0, y1, z1)]
		var b := [p(x1, y0, 0.0), p(x1, y1, 0.0), p(x1, y1, z1), p(x1, y0, z1)]
		poly(a, base)
		poly(b, base.darkened(0.22))
		outline(a)
		outline(b)
		var rim := [p(x0, y1, z1), p(x1, y1, z1), p(x1, y0, z1)]
		c.draw_polyline(PackedVector2Array(rim), col(base.lightened(0.3)), maxf(1.0, round(k)))




# `part` is "" for a thing drawn in one go, "back" or "front" for one a pet stands inside
static func draw(pen: Pen, key: String, part: String, d: Dictionary) -> void:
	match key:
		"bowls":
			_bowls(pen, d)
		"bed_round":
			_bed_round(pen)
		"bed_cushion":
			_bed_cushion(pen, d.get("size", 1.0))
		"litter":
			_litter(pen, part, d)
		"post":
			_post(pen)
		"tower":
			_tower(pen, part, d)
		"cardbox":
			_cardbox(pen, part)
		"fish":
			_fish(pen)
		"aquarium":
			_aquarium(pen, d)
		"bone":
			_bone(pen)
		"rope":
			_rope(pen)
		"balls":
			_balls(pen)
		"perch":
			_perch(pen)
		"nest":
			_nest(pen, part)
		"hutch":
			_hutch(pen, part)
		"carrot":
			_carrot(pen)
		"trough":
			_trough(pen)
		"salt":
			_salt(pen)
		"pool":
			_pool(pen, d)
		"blanket":
			_blanket(pen)
		"log":
			_log(pen)
		"honey":
			_honey(pen)
		"window_perch":
			_window_perch(pen)



# a whole thing in one go, as the catalogue and the ghost show it
static func draw_all(pen: Pen, key: String, d: Dictionary) -> void:
	if THINGS[key]["mode"] == "walk":
		draw(pen, key, "back", d)
		draw(pen, key, "front", d)
	else:
		draw(pen, key, "", d)
		if key == "tower":
			draw(pen, key, "front", d)


static func _bowls(s: Pen, d: Dictionary) -> void:
	s.diamond(0.06, 0.06, 0.94, 0.94, 0.0, Color("6a6f86"))
	s.outline([s.p(0.06, 0.06), s.p(0.94, 0.06), s.p(0.94, 0.94), s.p(0.06, 0.94)], Color("3a3d52"))
	var lvl: Dictionary = d.get("level", {"food": 1.0, "water": 1.0})
	for i in 2:
		var which := "food" if i == 0 else "water"
		var at := Vector2(0.28, 0.72) if i == 0 else Vector2(0.72, 0.28)
		s.ell(at.x, at.y, 6.0, 3.0, 0.0, Color("4a5a78"))
		s.ell(at.x, at.y, 4.8, 2.3, 1.0, Color("8aa0c8"))
		var lv: float = lvl[which]
		if lv > 0.05:
			var fill := Color("c9a86a") if i == 0 else Color("7fb8e0")
			s.ell(at.x, at.y, 1.0 + 2.8 * lv, 0.5 + 1.3 * lv, 1.5, fill)
			if i == 1 and lv > 0.4:
				s.ell(at.x - 0.03, at.y - 0.02, 1.0 * lv, 0.4 * lv, 1.7, Color(1, 1, 1, 0.5))


static func _bed_round(s: Pen) -> void:
	s.ell(0.5, 0.5, 17.0, 8.5, 0.0, Color("5e3a36"))
	s.ell(0.5, 0.5, 14.5, 7.2, 1.0, Color("a8605a"))
	s.ell(0.5, 0.5, 10.0, 5.0, 1.0, Color("c98577"))


static func _bed_cushion(s: Pen, size: float) -> void:
	var a := 0.5 - 0.42 * size
	var b := 0.5 + 0.42 * size
	var e := Color("4f7f95")
	s.box(a, a, b, b, 0.0, 3.0, e, "lr")
	s.diamond(a, a, b, b, 3.0, Color("7fb0c4"))
	s.diamond(a + 0.09, a + 0.09, b - 0.09, b - 0.09, 3.0, Color("a8d0dc"))
	s.outline([s.p(a, a, 3.0), s.p(b, a, 3.0), s.p(b, b, 3.0), s.p(a, b, 3.0)])
	s.box(a + 0.02, a + 0.02, b - 0.02, a + 0.14, 3.0, 6.0, Color("5f93a8"), "tlr")


static func _tray_back(s: Pen, h: float, wall: Color) -> void:
	s.inner(0.1, 0.1, 0.9, 0.9, 0.0, h, wall)


static func _litter(s: Pen, part: String, d: Dictionary) -> void:
	var wall := Color("a8c4d8")
	if part == "back":
		_tray_back(s, 6.0, wall)
		s.diamond(0.12, 0.12, 0.88, 0.88, 4.0, Color("e4d3a8"))
		for i in 5:
			var at := s.p(0.3 + 0.09 * i, 0.35 + 0.07 * (i % 3), 4.5)
			s.c.draw_rect(Rect2(at, Vector2(s.k, s.k)), s.col(Color("c4b088")))
		for f in d.get("flicks", []):
			var u: float = f["t"] / 0.5
			var at := s.p(0.5 + f["dx"], 0.5, 6.0 + 9.0 * f["u"] * sin(PI * u))
			s.c.draw_rect(Rect2(at, Vector2(s.k, s.k)), s.col(Color("e4d3a8", 1.0 - u)))
	else:
		s.front(0.1, 0.1, 0.9, 0.9, 6.0, Color("c4dcea"))


static func _post(s: Pen) -> void:
	s.box(0.15, 0.15, 0.85, 0.85, 0.0, 2.5, Color("8a6a4a"))
	s.box(0.4, 0.4, 0.6, 0.6, 2.5, 24.0, SISAL)
	for i in 5:
		var z := 5.0 + i * 4.0
		s.line(s.p(0.4, 0.6, z), s.p(0.6, 0.6, z), Color("a8845a"))
		s.line(s.p(0.6, 0.6, z), s.p(0.6, 0.4, z), Color("86643e"))
	s.box(0.2, 0.2, 0.8, 0.8, 24.0, 27.0, Color("a8605a"))


static func _tower(s: Pen, part: String, d: Dictionary) -> void:
	var pk := TOWER_PINK
	var dark := pk.darkened(0.3)
	if part == "front":
		s.box(0.04, 0.3, 0.62, 0.98, 3.0, 16.0, pk, "lr")
		var hole := [
			s.p(0.1, 0.98, 4.0),
			s.p(0.56, 0.98, 4.0),
			s.p(0.58, 0.98, 10.0),
			s.p(0.33, 0.98, 14.5),
			s.p(0.08, 0.98, 10.0)
		]
		s.poly(hole, Color("3a1a2c"))
		s.outline(hole, Color("7a2c52"))
		var sway := sin(float(d.get("t", 0.0)) * 2.0) * 0.03
		var hang := s.p(0.7 + sway, 0.96, 18.0)
		s.line(s.p(0.7, 0.96, 24.0), hang, Color("f1e9dc"))
		s.dot(0.7 + sway, 0.96, 16.0, 3.0, Color("ffe27a"))
		s.dot(0.7 + sway, 0.96, 16.6, 1.2, Color("fff3b0"))
		s.line(hang, s.p(0.76 + sway, 0.96, 13.0), Color("f0a0c0"), 1.0)
		return
	s.box(0.02, 0.02, 0.98, 0.98, 0.0, 3.0, dark)
	s.box(0.04, 0.3, 0.62, 0.98, 3.0, 16.0, pk.darkened(0.08), "t")
	s.box(0.68, 0.06, 0.9, 0.28, 3.0, 46.0, SISAL)
	for i in 9:
		var z := 6.0 + i * 4.5
		s.line(s.p(0.68, 0.28, z), s.p(0.9, 0.28, z), Color("b8a070"))
	s.box(0.04, 0.3, 0.74, 0.98, 24.0, 27.0, pk)
	s.box(0.3, 0.0, 0.98, 0.5, 44.0, 47.0, pk.lightened(0.05))
	s.box(0.34, 0.0, 0.94, 0.12, 47.0, 50.0, dark.lightened(0.15), "tlr")


static func _cardbox(s: Pen, part: String) -> void:
	var wall := Color("c49a62")
	if part == "back":
		_tray_back(s, 8.0, wall)
		s.diamond(0.12, 0.12, 0.88, 0.88, 0.5, Color("a37a44"))
		s.box(0.06, 0.04, 0.5, 0.1, 8.0, 8.4, wall.lightened(0.1), "t")
	else:
		s.front(0.1, 0.1, 0.9, 0.9, 8.0, wall)
		s.line(s.p(0.3, 0.9, 5.5), s.p(0.7, 0.9, 5.5), Color("e8d4a8"), 1.0)


static func _fish(s: Pen) -> void:
	s.ell(0.5, 0.5, 7.0, 3.4, 1.0, Color("5fb0c8"))
	s.poly([s.p(0.72, 0.4, 1.0), s.p(0.9, 0.3, 1.0), s.p(0.9, 0.5, 1.0)], Color("3f8fb0"))
	s.ell(0.42, 0.46, 1.4, 0.8, 2.0, Color("ffffff"))
	s.dot(0.4, 0.44, 2.0, 0.6, INK)


static func _aquarium(s: Pen, d: Dictionary) -> void:
	s.box(0.08, 0.08, 0.92, 0.92, 0.0, 10.0, Color("8a5a3c"))
	var t := float(d.get("t", 0.0))
	s.box(0.12, 0.12, 0.88, 0.88, 10.0, 27.0, Color("7fc0e0"), "lr", Color("3a5a78"))
	s.box(0.12, 0.12, 0.88, 0.88, 26.0, 27.5, Color("bfe0f0"), "t", Color("3a5a78"))
	s.line(s.p(0.3, 0.88, 11.0), s.p(0.3, 0.88, 19.0), Color("3f9a5a"), 1.0)
	s.line(s.p(0.36, 0.88, 11.0), s.p(0.34, 0.88, 17.0), Color("5fba7a"), 1.0)
	var fx := 0.35 + 0.3 * (0.5 + 0.5 * sin(t * 0.7))
	s.ell(fx, 0.88, 3.0, 1.6, 18.0, Color("f08a3a"))
	s.poly(
		[s.p(fx - 0.1, 0.88, 18.0), s.p(fx - 0.18, 0.88, 21.0), s.p(fx - 0.18, 0.88, 15.0)],
		Color("f08a3a")
	)


static func _bone(s: Pen) -> void:
	s.ell(0.5, 0.5, 8.0, 3.6, 0.0, Color(0, 0, 0, 0.18))
	var a := s.p(0.35, 0.58, 1.0)
	var b := s.p(0.65, 0.42, 1.0)
	var bone := Color("f1e9dc")
	s.line(a, b, bone, 2.0)
	for end in [a, b]:
		s.c.draw_circle(end + Vector2(0, -0.8 * s.k), 1.6 * s.k, s.col(bone))
		s.c.draw_circle(end + Vector2(0, 0.8 * s.k), 1.6 * s.k, s.col(bone))


static func _rope(s: Pen) -> void:
	s.ell(0.5, 0.5, 9.0, 3.8, 0.0, Color(0, 0, 0, 0.16))
	var a := s.p(0.3, 0.64, 1.5)
	var b := s.p(0.7, 0.36, 1.5)
	s.line(a, b, Color("d9a35a"), 2.0)
	s.line(a + Vector2(0, -s.k), b + Vector2(0, -s.k), Color("b8803a"), 1.0)
	s.dot(0.3, 0.64, 1.5, 2.6, Color("c98f45"))
	s.dot(0.7, 0.36, 1.5, 2.6, Color("c98f45"))
	s.dot(0.3, 0.64, 2.2, 1.0, Color("e8c07a"))
	s.dot(0.7, 0.36, 2.2, 1.0, Color("e8c07a"))


static func _balls(s: Pen) -> void:
	var wall := Color("b8864a")
	_tray_back(s, 10.0, wall)
	s.diamond(0.14, 0.14, 0.86, 0.86, 2.0, Color("8a6034"))
	for i in 6:
		var at := Vector2(0.3 + 0.2 * (i % 3), 0.3 + 0.22 * (i / 3)) + Vector2(0.04 * (i % 2), 0)
		s.dot(at.x, at.y, 8.5, 2.7, Color("d8e84a"))
		s.line(s.p(at.x - 0.05, at.y, 9.2), s.p(at.x + 0.05, at.y, 9.8), Color("f4ffd0"), 1.0)
	s.front(0.1, 0.1, 0.9, 0.9, 10.0, wall)
	for i in 3:
		var z := 3.0 + i * 3.0
		s.line(s.p(0.1, 0.9, z), s.p(0.9, 0.9, z), wall.darkened(0.2))


static func _perch(s: Pen) -> void:
	var wood := Color("9a6a3a")
	for x in [0.12, 0.88]:
		s.line(s.p(x, 0.3, 0.0), s.p(x, 0.5, 18.0), wood.darkened(0.2), 2.0)
		s.line(s.p(x, 0.7, 0.0), s.p(x, 0.5, 18.0), wood.darkened(0.2), 2.0)
	s.line(s.p(0.06, 0.5, 18.0), s.p(0.94, 0.5, 18.0), wood, 3.0)
	s.line(s.p(0.06, 0.5, 19.2), s.p(0.94, 0.5, 19.2), wood.lightened(0.25), 1.0)


static func _nest(s: Pen, part: String) -> void:
	var wood := Color("9a6a3a")
	if part == "back":
		_tray_back(s, 6.0, wood)
		s.ell(0.5, 0.5, 10.0, 4.6, 3.0, Color("d8b04a"))
		for i in 8:
			var at := s.p(0.25 + 0.07 * i, 0.3 + 0.08 * ((i * 3) % 5), 4.0)
			s.line(at, at + Vector2(3.0 * s.k, 0), Color("f0d27a"), 1.0)
	else:
		s.front(0.1, 0.1, 0.9, 0.9, 6.0, wood)
		s.ell(0.78, 0.74, 2.6, 1.6, 4.0, Color("fff6e0"))


static func _hutch(s: Pen, part: String) -> void:
	var wood := Color("b98a5a")
	if part == "back":
		_tray_back(s, 12.0, wood)
		s.diamond(0.12, 0.12, 0.88, 0.88, 1.0, Color("d8b04a"))
		var roof := [
			s.p(0.04, 0.04, 12.0), s.p(0.96, 0.04, 12.0), s.p(0.96, 0.5, 20.0), s.p(0.04, 0.5, 20.0)
		]
		s.poly(roof, Color("c24a3a"))
		s.outline(roof)
		var low := [
			s.p(0.04, 0.5, 20.0), s.p(0.96, 0.5, 20.0), s.p(0.96, 0.62, 12.0), s.p(0.04, 0.62, 12.0)
		]
		s.poly(low, Color("a63a2c"))
		s.outline(low)
	else:
		s.front(0.1, 0.1, 0.9, 0.9, 6.0, wood)
		s.line(s.p(0.1, 0.9, 3.0), s.p(0.9, 0.9, 3.0), wood.darkened(0.2))


static func _carrot(s: Pen) -> void:
	for i in 2:
		var o := Vector2(0.0, 0.0) if i == 0 else Vector2(0.14, -0.1)
		var a := s.p(0.3 + o.x, 0.62 + o.y, 1.0)
		var b := s.p(0.66 + o.x, 0.4 + o.y, 1.0)
		s.line(a, b, Color("f08a30"), 3.0)
		s.line(a, a.lerp(b, 0.6), Color("d8701c"), 1.0)
		s.line(b, b + Vector2(3.0 * s.k, -1.0 * s.k), Color("5fba4a"), 1.0)
		s.line(b, b + Vector2(2.0 * s.k, 1.5 * s.k), Color("4a9a3a"), 1.0)


static func _trough(s: Pen) -> void:
	var wood := Color("8a5a36")
	s.inner(0.04, 0.22, 0.96, 0.78, 0.0, 9.0, wood)
	s.diamond(0.08, 0.26, 0.92, 0.74, 5.0, Color("5f9fd0"))
	s.diamond(0.2, 0.34, 0.5, 0.5, 5.2, Color("a0d0f0"))
	s.front(0.04, 0.22, 0.96, 0.78, 9.0, wood)


static func _salt(s: Pen) -> void:
	s.box(0.25, 0.25, 0.75, 0.75, 0.0, 2.5, Color("8a5a36"))
	s.box(0.32, 0.32, 0.68, 0.68, 2.5, 11.0, Color("efd4d6"))
	for i in 4:
		s.c.draw_rect(
			Rect2(s.p(0.4 + 0.07 * i, 0.68, 4.0 + 2.0 * (i % 3)), Vector2(s.k, s.k)),
			s.col(Color("c9a0a6"))
		)


static func _pool(s: Pen, d: Dictionary) -> void:
	var t := float(d.get("t", 0.0))
	s.ell(0.5, 0.5, 15.5, 7.8, 0.0, Color("2f5fa8"))
	s.ell(0.5, 0.5, 14.0, 6.9, 2.0, Color("4a8ad8"))
	s.ell(0.5, 0.5, 11.5, 5.4, 2.0, Color("86c4f2"))
	for i in 3:
		var u := fmod(t * 0.4 + i * 0.33, 1.0)
		s.ell(
			0.5 + 0.12 * (i - 1),
			0.5,
			2.0 + 5.0 * u,
			1.0 + 2.5 * u,
			2.2,
			Color(1, 1, 1, 0.35 * (1.0 - u))
		)


static func _blanket(s: Pen) -> void:
	s.diamond(0.08, 0.08, 0.92, 0.92, 0.5, Color("8f6f9f"))
	s.outline(
		[s.p(0.08, 0.08, 0.5), s.p(0.92, 0.08, 0.5), s.p(0.92, 0.92, 0.5), s.p(0.08, 0.92, 0.5)],
		Color("6c4f7c")
	)
	s.line(s.p(0.08, 0.5, 0.5), s.p(0.92, 0.5, 0.5), Color("b79ac4"))


static func _log(s: Pen) -> void:
	var bark := Color("8a5a36")
	s.box(0.12, 0.28, 0.88, 0.72, 0.0, 11.0, bark, "tl")
	var end := Color("d9b27a")
	s.ell(0.88, 0.5, 4.6, 5.4, 5.5, bark.darkened(0.25))
	s.ell(0.88, 0.5, 3.6, 4.4, 5.5, end)
	s.ell(0.88, 0.5, 1.8, 2.4, 5.5, end.darkened(0.2))
	for i in 3:
		s.line(s.p(0.3 + 0.2 * i, 0.72, 2.0), s.p(0.33 + 0.2 * i, 0.72, 9.0), Color("e8c898"))


static func _honey(s: Pen) -> void:
	s.ell(0.5, 0.5, 8.0, 3.8, 0.0, Color(0, 0, 0, 0.2))
	s.ell(0.5, 0.5, 7.4, 3.5, 1.0, Color("7a4a24"))
	s.box(0.34, 0.34, 0.66, 0.66, 1.0, 9.0, Color("b8742e"), "lr")
	s.ell(0.5, 0.5, 6.4, 3.0, 10.0, Color("e8a828"))
	s.ell(0.46, 0.46, 3.2, 1.3, 10.4, Color("f8d868"))
	s.line(s.p(0.34, 0.66, 9.5), s.p(0.34, 0.66, 5.5), Color("f0b830"), 1.0)


# hung on the wall under the window: its own cell's x runs from -1 (the wall) to 0
static func _window_perch(s: Pen) -> void:
	var wood := Color("8a5a36")
	s.line(s.p(-0.9, 0.0, 14.0), s.p(-0.9, 0.0, 19.0), wood.darkened(0.2), 2.0)
	s.line(s.p(-0.9, 0.5, 14.0), s.p(-0.9, 0.5, 19.0), wood.darkened(0.2), 2.0)
	s.box(-1.0, -0.05, -0.3, 0.55, 19.0, 21.5, wood)
	s.diamond(-0.97, 0.0, -0.33, 0.5, 21.5, Color("c98577"))
	s.diamond(-0.9, 0.07, -0.4, 0.43, 22.0, Color("e0a898"))
