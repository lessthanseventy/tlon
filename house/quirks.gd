extends RefCounted

# The person's small habits at the desk, what a hero look does for the room (a staff lights the
# fire, a blade salutes the door, a bow looses an arrow into the wall), and the rare visitor.
const Props := preload("res://props.gd")
const Pets := preload("res://pets.gd")
const Look := preload("res://look.gd")
const Guests := preload("res://guests.gd")

const SPIN := [7, 1, 3, 5]
const DESK_FACE := 5
const DURATION := {"spin": 2.4, "pencil": 5.0, "stretch": 1.8, "nod": 6.0}
const STAFF := ["staff", "wand_tome"]
const BOW := ["bow"]
const ARROW_AT := Vector2(54.0, 30.0)
const ARROW_STAYS := 150.0
const VISIT := {"in": 2.6, "stay": 2.8, "out": 2.6}
const DOORWAY := Vector2(0.45, 7.5)
const INSIDE := Vector2(2.6, 7.0)
const KIND_ID := {"hero": "visitor", "city": "visitor_city", "monster": "visitor_monster"}
# the pedestrians of the city pack (not its workers), and the monsters that are only comic: the
# animation each moves with and its shadow
const PEDESTRIANS := [
	"man_tee",
	"woman_dress",
	"student",
	"office_man",
	"business_woman",
	"jogger",
	"grandpa",
	"grandma",
	"teen_hoodie",
	"tourist",
	"woman_jeans",
	"punk",
	"man_coat",
	"girl_skirt",
]
const MONSTERS := {
	"slime": ["hop", "shadow_small"],
	"ghost": ["float", "shadow_small"],
	"pumpkin_knight": ["walk", "shadow_medium"],
	"bat": ["fly", "shadow_small"],
	"imp": ["fly", "shadow_small"],
	"golem": ["walk", "shadow_medium"],
}
# a pack's folder, its sheet cell, the anchor in it and the weight of its kind in the dice
const PACKS := {
	"city":
	{
		"dir": "isometric-city-people/Gridwright Isometric City People/",
		"cell": 32,
		"anchor": Vector2(16, 28),
		"weight": 2.0
	},
	"monster":
	{
		"dir": "isometric-monsters/Gridwright Isometric Monsters/",
		"cell": 64,
		"anchor": Vector2(32, 46),
		"weight": 2.0
	},
}
const LOOK_DIRS := [1, 0, 7]
const REACTION := {
	"Nina": ["I have seen worse.", "hm. unimpressed."],
	"Argos": ["is it friendly?", "hello?? hello monster?"]
}

var _hw: WeakRef
var h:
	get:
		return _hw.get_ref()
var fx_kind := ""
var perk := {}
var arrow := {}
var stuck := 0.0
var visitor := {}
var forced: Array = []

var _t := 0.0
var _fx_t := 0.0
var _next_fx := 120.0
var _next_perk := 600.0
var _next_visit := 1500.0
var _door_was := false
var _vlook: Look
var _vcrit: Pets.Critter


func setup(home) -> void:
	_hw = weakref(home)
	var r: RandomNumberGenerator = h.eggs.rng
	_next_fx = r.randf_range(60.0, 180.0)
	_next_perk = r.randf_range(400.0, 900.0)
	_next_visit = r.randf_range(1200.0, 3000.0)


func force(name: String) -> void:
	forced.append(name)


func visiting() -> bool:
	return not visitor.is_empty()


func process(dt: float) -> void:
	_t += dt
	stuck = maxf(0.0, stuck - dt)
	while not forced.is_empty():
		_start(forced.pop_front())
	_fidget(dt)
	_perks(dt)
	_arrow(dt)
	_visit(dt)


func _start(name: String) -> void:
	match name.get_slice(":", 0):
		"spin", "pencil", "stretch", "nod":
			fidget(name)
		"cast", "bow":
			perk = {"k": name, "st": 0, "t": 0.0}
		"salute":
			h.person.react_left = 2.4
			h.eggs.find("salute")
		"visitor":
			start_visit()
		"visitor_city", "visitor_monster":
			start_visit(name.get_slice("_", 1).get_slice(":", 0), name.get_slice(":", 1))


func fidget(kind: String) -> void:
	var p = h.person
	fx_kind = kind
	_fx_t = 0.0
	p.fx = {"left": DURATION[kind]}
	if kind == "stretch":
		p.fx["anim"] = "cheer"
	elif kind == "nod":
		p.fx["anim"] = "sit"
	h.eggs.find("fidget_" + kind)


func _end_fidget() -> void:
	var p = h.person
	p.fx = {}
	fx_kind = ""
	if p.act == "desk" and p.phase == "idle":
		p.c.dir = DESK_FACE


func _fidget(dt: float) -> void:
	var p = h.person
	if fx_kind != "":
		_fx_t += dt
		p.fx["left"] -= dt
		if fx_kind == "spin":
			p.c.dir = SPIN[int(_fx_t * 5.0) % 4]
		if p.fx["left"] <= 0.0 or p.act != "desk" or p.phase != "idle" or p.ring:
			_end_fidget()
		return
	if h.pets.freeze:
		return
	_next_fx -= dt
	if _next_fx > 0.0:
		return
	_next_fx = h.eggs.rng.randf_range(150.0, 360.0)
	if p.act != "desk" or p.phase != "idle" or not p.seated or not h.eggs.calm():
		return
	var hour: float = h._hour()
	var late := hour >= 23.5 or hour < 4.5
	var kinds := ["spin", "pencil", "stretch"]
	if late:
		kinds = ["nod", "nod", "stretch"]
	fidget(kinds[h.eggs.rng.randi() % kinds.size()])


func _perks(dt: float) -> void:
	var look = h.look
	if not look.hero():
		perk = {}
		_door_was = false
		return
	var weapon := str(look.hero_cfg.get("weapon", ""))
	var here: bool = h.door.present()
	if here and not _door_was and weapon not in STAFF and weapon not in BOW and weapon != "":
		h.person.react_left = 2.4
		h.eggs.find("salute")
	_door_was = here
	if not perk.is_empty():
		_run_perk(dt)
		return
	if h.pets.freeze:
		return
	_next_perk -= dt
	if _next_perk > 0.0 or not h.eggs.calm():
		return
	_next_perk = h.eggs.rng.randf_range(600.0, 1500.0)
	if weapon in STAFF and not h.hearth.lit and not h.eggs.piece("fireplace").is_empty():
		perk = {"k": "cast", "st": 0, "t": 0.0}
	elif weapon in BOW:
		perk = {"k": "bow", "st": 0, "t": 0.0}


func _run_perk(dt: float) -> void:
	var p = h.person
	perk["t"] += dt
	match perk["k"]:
		"cast":
			var fire: Dictionary = h.eggs.piece("fireplace")
			if perk["st"] == 0:
				var cell: Vector2i = (
					h.eggs.front_cell(fire) if not fire.is_empty() else Vector2i(-1, -1)
				)
				if cell.x < 0:
					perk = {}
					return
				var r: Rect2i = h.layout.rect(fire)
				h.eggs.spot("hearth_stand", {"cell": cell})
				p.acts["hearth"] = {
					"stand": "hearth_stand",
					"face":
					h.pets._face(
						Vector2(r.position) + Vector2(0.5, 0.5) - Vector2(cell) - Vector2(0.5, 0.5),
						5
					),
					"anim": "idle",
					"pri": 2.0
				}
				p.forced = "hearth"
				perk["st"] = 1
				perk["t"] = 0.0
			elif perk["st"] == 1 and p.act == "hearth" and p.phase == "idle":
				p.fx = {"anim": "cheer"}
				perk["st"] = 2
				perk["t"] = 0.0
			elif perk["st"] == 2 and perk["t"] > 1.4:
				h.hearth.manual = 1
				h.hearth.puff()
				h.eggs.find("cast")
				perk["st"] = 3
				perk["t"] = 0.0
			elif perk["st"] == 3 and perk["t"] > 1.6:
				p.fx = {}
				p.forced = ""
				perk = {}
			elif perk["t"] > 60.0:
				p.fx = {}
				p.forced = ""
				perk = {}
		"bow":
			if perk["st"] == 0 and p.act != "arrive" and p.phase == "idle":
				p.fx = {"anim": "shoot"}
				p.c.dir = 3
				perk["st"] = 1
				perk["t"] = 0.0
			elif perk["st"] == 1 and perk["t"] > 0.7:
				arrow = {"t": 0.0}
				perk["st"] = 2
				perk["t"] = 0.0
			elif perk["st"] == 2 and perk["t"] > 0.8:
				p.fx = {}
				p.c.dir = p.acts[p.act]["face"]
				perk = {}
			elif perk["t"] > 20.0:
				p.fx = {}
				perk = {}


func _arrow(dt: float) -> void:
	if arrow.is_empty():
		return
	arrow["t"] += dt
	if arrow["t"] >= 0.45:
		arrow = {}
		stuck = ARROW_STAYS
		h.eggs.find("bow")
		h.sound.request("rustle")


func draw_person(c: CanvasItem, f: Vector2, k: int) -> void:
	if fx_kind == "pencil":
		var base := f + Vector2(9, -33) * k
		var a := sin(_fx_t * 3.0) * 0.45
		var tip := base + Vector2(sin(a), -cos(a)) * 8.0 * k
		c.draw_line(base, tip, Color("e8b830"), maxf(1.0, 1.2 * k))
		c.draw_line(
			tip, tip + Vector2(sin(a), -cos(a)) * 1.6 * k, Color("f2a6b3"), maxf(1.0, 1.2 * k)
		)
	elif fx_kind == "nod":
		var font := ThemeDB.fallback_font
		for i in 3:
			var ph := fmod(_fx_t * 0.6 + i * 0.33, 1.0)
			c.draw_string(
				font,
				f + Vector2(8 + ph * 8, -44 * k * 0.8 - ph * 10 * k),
				"z",
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				12 + i * 3,
				Color("f1e9dc", 1.0 - ph)
			)


# the arrow in the wall, and in the air
func draw_over(c: CanvasItem) -> void:
	var k: int = h._k
	var o: Vector2 = h._o
	var to := Props.wall_pt(o, k, -1, ARROW_AT.x, ARROW_AT.y)
	if not arrow.is_empty():
		var from: Vector2 = h.pets.feet(h.person.c, o, k) + Vector2(-4, -30) * k
		var u: float = minf(arrow["t"] / 0.45, 1.0)
		var at := from.lerp(to, u)
		var dir := (to - from).normalized()
		c.draw_line(at - dir * 8.0 * k, at, Color("c9a06a"), maxf(1.0, 0.9 * k))
		c.draw_line(
			at - dir * 8.0 * k,
			at - dir * 6.0 * k + Vector2(0, -1.4 * k),
			Color("e8e4dc"),
			maxf(1.0, 0.9 * k)
		)
	elif stuck > 0.0:
		var dir := Vector2(-0.89, -0.45).normalized()
		c.draw_line(to + dir * 7.0 * k, to, Color("c9a06a"), maxf(1.0, 0.9 * k))
		c.draw_line(
			to + dir * 7.0 * k,
			to + dir * 5.0 * k + Vector2(0, -1.4 * k),
			Color("e8e4dc"),
			maxf(1.0, 0.9 * k)
		)
		c.draw_line(
			to + dir * 7.0 * k,
			to + dir * 5.0 * k + Vector2(0, 1.4 * k),
			Color("e8e4dc"),
			maxf(1.0, 0.9 * k)
		)


# which kinds of visitor may come on this date and hour: the hero and a pedestrian any day, a
# monster only 25-31 October and never at night
static func allowed(hour: float, october_week: bool) -> Array:
	var out := ["hero", "city"]
	if october_week and hour >= 6.0 and hour < 22.0:
		out.append("monster")
	return out


# the sheets of a pack's visitors that exist under the art folder, in the pack's own order
func guest_names(kind: String) -> Array:
	var pool: Array = PEDESTRIANS if kind == "city" else MONSTERS.keys()
	var dir: String = h.room.art_dir.path_join(PACKS[kind]["dir"])
	return pool.filter(
		func(n):
			return _sheets(kind, n).all(
				func(a): return FileAccess.file_exists(_sheet_path(dir, n, a, 1))
			)
	)


# a visitor's sheet at room scale k
static func _sheet_path(dir: String, name: String, anim: String, k: int) -> String:
	return dir + "Sheets/%dx/%s/%s_%s.png" % [k, name, name, anim]


func _sheets(kind: String, name: String) -> Array:
	return ["idle", "walk", "phone"] if kind == "city" else ["idle", MONSTERS[name][0]]


func _hero_ready() -> bool:
	if _vlook == null:
		_vlook = Look.new()
		_vlook.store = "user://house_visitor_never_written.json"
		_vlook.setup(h.room.art_dir)
		_vcrit = Pets.Critter.new()
	return _vlook.hero_ready and not _vlook.hero_recipes.is_empty()


# the kinds that can come now: by the house's date and hour, and whose pack is there
func kinds_now() -> Array:
	var day: float = h._now_local()
	var out: Array = []
	for kind in allowed(h._hour(), Guests.last_week_of_october(day)):
		if _hero_ready() if kind == "hero" else not guest_names(kind).is_empty():
			out.append(kind)
	return out


func _pick_kind(kinds: Array) -> String:
	var total := 0.0
	for k in kinds:
		total += PACKS[k]["weight"] if PACKS.has(k) else 1.0
	var roll: float = h.eggs.rng.randf() * total
	for k in kinds:
		roll -= PACKS[k]["weight"] if PACKS.has(k) else 1.0
		if roll <= 0.0:
			return k
	return kinds[0]


# one visitor at a time; `who` names a pedestrian or monster, else the dice pick
func start_visit(kind: String = "hero", who: String = "") -> bool:
	if visiting() or kind not in kinds_now():
		return false
	_vcrit.pos = DOORWAY
	_vcrit.dir = 7
	_vcrit.z = 0.0
	_vcrit.key = -1.0
	if kind == "hero":
		var rec: Dictionary = _vlook.hero_recipes[h.eggs.rng.randi() % _vlook.hero_recipes.size()]
		_vlook.wear = "hero"
		_vlook.hero_cfg = (rec["cfg"] as Dictionary).duplicate()
		visitor = {"t": 0.0, "kind": kind, "name": rec["name"]}
	else:
		var pool := guest_names(kind)
		var name: String = who if who in pool else pool[h.eggs.rng.randi() % pool.size()]
		var stay := "phone" if kind == "city" and h.eggs.rng.randf() < 0.35 else "idle"
		visitor = {"t": 0.0, "kind": kind, "name": name, "stay": stay}
		h.sound.request("egg_visitor")
	h.eggs.find(KIND_ID[kind])
	if kind == "monster":
		_react()
	return true


# the dog-role pet hops or hides, the cat-role pet is unimpressed
func _react() -> void:
	var r: RandomNumberGenerator = h.eggs.rng
	var argos = h.pets.critter("argos")
	var nina = h.pets.critter("nina")
	if h.eggs.loose(argos):
		if r.randf() < 0.5:
			argos.hops = 3
		else:
			h.pets.go(argos, "nook", "sit", 15.0)
			argos.wait = 9999.0
		h.pets.say(argos, REACTION["Argos"][r.randi() % 2])
	if h.eggs.loose(nina):
		h.pets.say(nina, REACTION["Nina"][r.randi() % 2])


func _visit(dt: float) -> void:
	if visitor.is_empty():
		if h.pets.freeze:
			return
		_next_visit -= dt
		if _next_visit <= 0.0:
			_next_visit = h.eggs.rng.randf_range(1500.0, 4000.0)
			var hour: float = h._hour()
			if hour >= 9.0 and hour < 21.0 and h.eggs.calm() and h.eggs.scene.is_empty():
				var kinds := kinds_now()
				if not kinds.is_empty():
					start_visit(_pick_kind(kinds))
		return
	visitor["t"] += dt
	var t: float = visitor["t"]
	var total: float = VISIT["in"] + VISIT["stay"] + VISIT["out"]
	if t < VISIT["in"]:
		_vcrit.pos = DOORWAY.lerp(INSIDE, t / VISIT["in"])
		_vcrit.dir = 7
	elif t < VISIT["in"] + VISIT["stay"]:
		_vcrit.pos = INSIDE
		_vcrit.dir = 1
		if visitor["kind"] != "hero":
			var third: float = VISIT["stay"] / LOOK_DIRS.size()
			_vcrit.dir = LOOK_DIRS[mini(int((t - VISIT["in"]) / third), LOOK_DIRS.size() - 1)]
	else:
		_vcrit.pos = INSIDE.lerp(DOORWAY, (t - VISIT["in"] - VISIT["stay"]) / VISIT["out"])
		_vcrit.dir = 3
	if t >= total:
		visitor = {}
		for id in ["argos", "nina"]:
			var c = h.pets.critter(id)
			if h.eggs.loose(c):
				h.eggs.line(c, "visitor")
				break


func _moving() -> bool:
	var t: float = visitor["t"]
	return t < VISIT["in"] or t >= VISIT["in"] + VISIT["stay"]


func _anim() -> String:
	return "walk" if _moving() else "block"


func items() -> Array:
	if visitor.is_empty():
		return []
	return [{"key": _vcrit.pos.x + _vcrit.pos.y - 1.0, "pri": 2.1, "fn": _draw_visitor}]


func _draw_visitor() -> void:
	var k: int = h._k
	var f: Vector2 = h.pets.feet(_vcrit, h._o, k)
	if visitor["kind"] != "hero":
		_draw_guest(f, k)
		return
	_vlook.draw_frame(
		h.room,
		_vlook.sheet(_vlook.current(), k),
		_vlook.anim_for(_anim()),
		_vcrit.dir,
		visitor["t"],
		f,
		k
	)


func _draw_guest(f: Vector2, k: int) -> void:
	var kind: String = visitor["kind"]
	var name: String = visitor["name"]
	var pack: Dictionary = PACKS[kind]
	var dir: String = h.room.art_dir.path_join(pack["dir"])
	var move: String = "walk" if kind == "city" else MONSTERS[name][0]
	var anim: String = move if _moving() else str(visitor.get("stay", "idle"))
	var shadow: String = "shadow_small" if kind == "city" else MONSTERS[name][1]
	var sh: Texture2D = h.pets._load(dir + "Effects/%dx/%s.png" % [k, shadow])
	if sh != null:
		h.room.draw_texture(
			sh, (f - Vector2(sh.get_width(), sh.get_height()) / 2.0).round(), Color(1, 1, 1, 0.35)
		)
	var tex: Texture2D = h.pets._load(_sheet_path(dir, name, anim, k))
	if tex == null:
		return
	var cell: int = pack["cell"] * k
	var fps: float = {"idle": 6.0, "phone": 4.0}.get(anim, 10.0)
	var frame := int(visitor["t"] * fps) % maxi(1, tex.get_width() / cell)
	h.room.draw_texture_rect_region(
		tex,
		Rect2((f - (pack["anchor"] as Vector2) * k).round(), Vector2(cell, cell)),
		Rect2(frame * cell, _vcrit.dir * cell, cell, cell)
	)
