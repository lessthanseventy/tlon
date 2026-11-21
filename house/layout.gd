extends RefCounted

# The home's furniture: what stands where, the wall and the floor. Pieces the room's behaviour is
# tied to are FIXED; everything else is plain and can be moved, saved and loaded.
const Pets := preload("res://pets.gd")
const Packs := preload("res://packs.gd")
const PetThings := preload("res://pet_things.gd")
const Chores := preload("res://chores.gd")
const People := preload("res://people.gd")
const Money := preload("res://money.gd")

const SIDES := ["sw", "se", "ne", "nw", "nwse", "nesw"]
const FRONT := {
	"se": Vector2i(1, 0), "sw": Vector2i(0, 1), "ne": Vector2i(0, -1), "nw": Vector2i(-1, 0)
}
const GROUPS := [
	[
		"living",
		[
			"sofa",
			"armchair",
			"tv_stand",
			"piano",
			"fireplace",
			"side_table",
			"floor_lamp",
			"bookshelf"
		]
	],
	["dining", ["dining_chair", "dining_table", "round_table", "stool"]],
	["bedroom", ["bed_single", "bed_double", "nightstand", "wardrobe", "dresser"]],
	["kitchen", ["kitchen_counter", "kitchen_sink", "stove", "fridge"]],
	["bathroom", ["bathtub", "toilet", "wash_basin"]],
	["office", ["computer_desk", "office_chair", "filing_cabinet", "waste_bin"]],
	["shop", ["shop_counter", "goods_shelf", "display_table", "tavern_table", "barrel", "crate"]],
	["plants", ["plant_small", "plant_large"]],
	["rugs", ["rug_red", "rug_blue", "rug_round"]],
	["on the wall", ["painting", "mirror", "clock", "curtains_red", "wall_shelf", "wall_cabinet"]],
]
const FIXED := [
	["computer_desk", "sw", 4, 0],
	["office_chair", "ne", 4, 1],
	["tv_stand", "se", 0, 2],
	["sofa", "se", 0, 4],
	["wardrobe", "sw", 1, 0],
	["waste_bin", "", 6, 0],
	["plant_large", "", 7, 0],
	["floor_lamp", "", 0, 6],
]
const DEFAULTS := [
	["plant_small", "", 0, 0],
	["laundry_basket", "", 0, 10],
	["photo_frame", "ne", 10, 0],
	["armchair", "se", 0, 1],
	["rug_blue", "nwse", 1, 4],
	["painting", "ne", 0, 0],
	["clock", "ne", 7, 0],
	["painting", "nw", 0, 6],
	["fireplace", "ne", 8, 0],
	["bookshelf", "sw", 9, 0],
	["rug_red", "nesw", 8, 1],
	["armchair", "ne", 8, 2],
	["side_table", "", 9, 2],
	["piano", "se", 0, 8],
	["wall_shelf", "nw", 0, 8],
	["mirror", "nw", 0, 9],
	["rug_round", "", 4, 8],
	["dining_table", "nwse", 4, 8],
	["piggy_bank", "", 5, 8],
	["dining_chair", "ne", 4, 9],
	["dining_chair", "ne", 5, 9],
	["plant_small", "", 10, 10],
]
# what each plain piece is drawn as with no art: footprint, height at 1x, colour
const BOXES := {
	"plant_small": [1, 1, 14, Color("5f8a4f")],
	"armchair_se": [1, 1, 17, Color("9a4f58")],
	"rug_blue_nwse": [3, 2, 0, Color("4a6a9a")],
	"wardrobe_sw": [1, 1, 44, Color("8a5a3c")],
	"computer_desk_sw": [2, 1, 31, Color("b58a5a")],
	"office_chair_ne": [1, 1, 26, Color("5a6f8a")],
	"waste_bin": [1, 1, 11, Color("6f7480")],
	"plant_large": [1, 1, 34, Color("5f8a4f")],
	"tv_stand_se": [1, 2, 40, Color("6f5a48")],
	"sofa_se": [1, 2, 17, Color("9a4f58")],
	"floor_lamp": [1, 1, 33, Color("d9b86a")],
	"laundry_basket": [1, 1, 12, Color("c79a5c")],
	"photo_frame": [1, 1, 35, Color("a8794d")],
	"piggy_bank": [1, 1, 20, Color("f0a5b8")],
}
# wall segments the board, window, calendar, jar and door use; nothing else goes there
const WALL_FIXED := {"ne": [2, 3, 4, 5, 6], "nw": [1, 4, 5, 7]}
# the pets' bed and bowls
const PETS_CORNER := Rect2i(5, 5, 3, 3)
const DOOR_CELL := Vector2i(0, 7)
const DOOR_FRONT := Vector2i(1, 7)
const TALL := 36
const LOW := 20
const STAYS := "that one stays"
const NO_ROOM := "no room there"
const BUSY := "someone is there"
const SHUTS := "that would shut a path"
const ONCE := "that one is already out"
const SAVED := 4
# the version from which the pets' things were put by the current rule
const THINGS_SAVED := 2
# where the basket and the piggy bank stood by default before `SAVED` 4
const OLD_DEFAULTS := {"laundry_basket": Vector2i(1, 1), "piggy_bank": Vector2i(6, 4)}
# the tables a piggy bank may stand on, and how high the middle of each one's top is drawn (the
# sprite's `height` is its rim, a few pixels above)
const TABLE_TOPS := {"dining_table": 17, "round_table": 15, "tavern_table": 15}
# default pieces added after layouts were first saved: a saved layout is offered each once
const NEWER := ["laundry_basket", "photo_frame", "piggy_bank"]
# the pets' spots that move with their thing: their old cells stay free ground
const MOVING_SPOTS := ["bed", "bowl"]

var index := {}
var art := false
var wall := "wallpaper"
var floor_style := "oak"
var pieces: Array = []
var path := ""
var persist := false
var catalogue: Array = []
var walls: Array = []
var floors: Array = []
var tabs: Array = []
# visitors for a season: drawn and walked around like fixed pieces, never saved, never stand in the
# way of a piece being placed (they step aside on the next change)
var guests: Array = []
var version := 0
# the pet things put out once, so one the owner took away is not put back
var pets_seen: Array = []
# the `NEWER` pieces this layout has been offered, so one taken out stays out
var offered: Array = NEWER.duplicate()
var money_shown := false
# a file saved before `SAVED`: the pets' things in it were put by the first rule
var old_things := false

var _fixed: Array = []
# what the file holds of a pack that is not here, kept so saving does not delete it
var _dormant: Array = []
var _dormant_wall := ""
var _dormant_floor := ""


func setup(sprites: Dictionary, with_art: bool, file: String, save_it: bool) -> void:
	index = sprites
	art = with_art
	path = file
	persist = save_it
	pets_seen = []
	old_things = false
	offered = NEWER.duplicate()
	catalogue = []
	version += 1
	_fixed = FIXED.map(func(r): return _piece(r, true))
	if art:
		_scan()
	else:
		catalogue.append_array(PetThings.entries())
		catalogue.append(Chores.entry())
		catalogue.append(People.entry())
		catalogue.append(Money.entry())
	pieces = _defaults([])
	if art and path != "":
		load_file()


func _piece(row: Array, fixed: bool = false) -> Dictionary:
	var p := {"p": row[0], "f": row[1], "c": row[2], "r": row[3]}
	if fixed:
		p["fixed"] = true
	return p


func _defaults(busy: Array) -> Array:
	var out: Array = []
	for row in DEFAULTS:
		var p := _piece(row)
		if not art and not BOXES.has(_base(p)):
			continue
		pieces = out
		if check(p, null, busy) == "":
			out.append(p)
	return out


func _scan() -> void:
	var found := {}
	var frame := RegEx.create_from_string("_f(\\d)$")
	var side := RegEx.create_from_string("_(nwse|nesw|sw|se|ne|nw)$")
	for key in index:
		var s: Dictionary = index[key]
		var file: String = s["file"]
		if "/floors/" in file:
			if key.ends_with("_01"):
				floors.append(key.trim_prefix("floor_").trim_suffix("_01"))
			continue
		if "/walls/" in file:
			if s.get("wall") == "ne" and s.get("opening") == null and s["style"] not in walls:
				walls.append(s["style"])
			continue
		if "/doors/" in file or "/shadows/" in file:
			continue
		var id: String = key
		var anim := false
		var m := frame.search(id)
		if m != null:
			if m.get_string(1) != "1":
				continue
			id = id.substr(0, m.get_start())
			anim = true
		var face := ""
		m = side.search(id)
		if m != null:
			face = m.get_string(1)
			id = id.substr(0, m.get_start())
		var e := _entry(id)
		if e.is_empty():
			var kind := "floor"
			if s.get("rug", false):
				kind = "rug"
			elif s.get("on_wall", false):
				kind = "wall"
			elif s.has("wall"):
				kind = "hug"
			e = {
				"key": id,
				"name": id.substr(id.find(".") + 1).replace("_", " "),
				"kind": kind,
				"anim": anim,
				"faces": [],
				"tab": s.get("tab", "home"),
			}
			if s.has("group"):
				e["group"] = s["group"]
				e["order"] = s["order"]
			catalogue.append(e)
		if face != "" and face not in e["faces"]:
			e["faces"].append(face)
	catalogue.append_array(PetThings.entries())
	catalogue.append(Chores.entry())
	catalogue.append(People.entry())
	catalogue.append(Money.entry())
	for i in catalogue.size():
		var e: Dictionary = catalogue[i]
		e["faces"].sort_custom(func(a, b): return SIDES.find(a) < SIDES.find(b))
		if not e.has("group"):
			e["group"] = _group(e["key"])
			e["order"] = _group_rank(e["group"]) * 1000 + i
		e["rank"] = Packs.TABS.find(e["tab"]) * 1000000 + e["order"]
	catalogue.sort_custom(func(a, b): return a["rank"] < b["rank"])
	tabs = Packs.TABS.filter(
		func(t): return catalogue.any(func(e): return e["tab"] == t) or t == "home"
	)


func _group(key: String) -> String:
	for g in GROUPS:
		if key in g[1]:
			return g[0]
	return "other"


func _group_rank(group: String) -> int:
	for i in GROUPS.size():
		if GROUPS[i][0] == group:
			return i
	return GROUPS.size()


func _entry(key: String) -> Dictionary:
	for e in catalogue:
		if e["key"] == key:
			return e
	return {}


func entry(key: String) -> Dictionary:
	return _entry(key)


func _base(p: Dictionary) -> String:
	var id: String = p["p"] + ("_" + p["f"] if p["f"] != "" else "")
	var e := _entry(p["p"])
	return id + "_f1" if e.get("anim", false) else id


func sprite_id(p: Dictionary) -> String:
	var base := _base(p)
	return base.trim_suffix("_f1") + "_f%d" if base.ends_with("_f1") else base


func kind(p: Dictionary) -> String:
	var e := _entry(p["p"])
	if not e.is_empty():
		return e["kind"]
	return "rug" if p["p"].begins_with("rug_") else "floor"


func footprint(p: Dictionary) -> Vector2i:
	if PetThings.is_pet(p):
		return Vector2i(1, 1)
	var base := _base(p)
	if index.has(base):
		var f: Array = index[base]["footprint"]
		return Vector2i(int(f[0]), int(f[1]))
	if BOXES.has(base):
		return Vector2i(BOXES[base][0], BOXES[base][1])
	return Vector2i(1, 1)


func height(p: Dictionary) -> int:
	if PetThings.is_pet(p):
		return int(PetThings.THINGS[PetThings.key_of(p)]["h"])
	var base := _base(p)
	if index.has(base):
		return int(index[base].get("height", 0))
	return BOXES[base][2] if BOXES.has(base) else 0


func all() -> Array:
	return _solid() + guests


# a pet thing that is not out (its animal or its switch is gone) takes no room, nor does the piggy
# bank while there is no money to show
func _solid() -> Array:
	return (
		_fixed
		+ pieces.filter(
			func(p): return not p.get("hide", false) and (money_shown or not Money.is_piggy(p))
		)
	)


# the piggy bank comes into the room, or goes out of it, with the money; coming in onto a cell
# something else has taken since, it goes to the nearest cell it may stand on
func show_money(on: bool) -> void:
	if on == money_shown:
		return
	money_shown = on
	version += 1
	if not on:
		return
	for p in pieces:
		if Money.is_piggy(p) and check(p, p, []) != "":
			var cell: Variant = _nearest(p["p"], p["f"], Vector2i(p["c"], p["r"]), p)
			if cell != null:
				p["c"] = cell.x
				p["r"] = cell.y
				save()


# the laundry basket where it stands, {} when it has been taken away
func basket() -> Dictionary:
	for p in _solid():
		if Chores.is_basket(p):
			return p
	return {}


# the framed photo where it stands, {} when it has been taken away
func frame() -> Dictionary:
	for p in _solid():
		if People.is_frame(p):
			return p
	return {}


# the piggy bank where it stands, {} when it has been taken away
func piggy() -> Dictionary:
	for p in _solid():
		if Money.is_piggy(p):
			return p
	return {}


# the pet things standing in the room, hidden ones not counted
func pet_pieces() -> Array:
	return pieces.filter(func(p): return PetThings.is_pet(p) and not p.get("hide", false))


func rect(p: Dictionary) -> Rect2i:
	var f := footprint(p)
	return Rect2i(p["c"], p["r"], f.x, f.y)


func draw_key(p: Dictionary) -> int:
	if kind(p) == "wall":
		return p["c"] + p["r"]
	var r := rect(p)
	return r.end.x - 1 + r.end.y - 1


# furniture [id, col, row, cols, rows, height, colour], what hangs [id, col, row], rugs
# [id, col, row, cols, rows, colour]: the rows the room draws
func rows() -> Dictionary:
	var out := {"furniture": [], "decor": [], "rugs": []}
	for p in all():
		if (
			PetThings.is_pet(p)
			or Chores.is_basket(p)
			or People.is_frame(p)
			or Money.is_piggy(p)
		):
			continue
		var id := sprite_id(p)
		var f := footprint(p)
		var box: Array = BOXES.get(_base(p), [1, 1, 0, Color("8a7a6a")])
		match kind(p):
			"wall":
				out["decor"].append([id, p["c"], p["r"]])
			"rug":
				out["rugs"].append([id, p["c"], p["r"], f.x, f.y, box[3]])
			_:
				out["furniture"].append([id, p["c"], p["r"], f.x, f.y, box[2], box[3]])
	return out


# the cells the pets and the person cannot walk on
func blocked(extra: Variant = null, skip: Variant = null) -> Dictionary:
	var out := {}
	var list := all()
	if extra != null:
		list = list + [extra]
	for p in list:
		if is_same(p, skip) or kind(p) in ["rug", "wall", "flat"]:
			continue
		var r := rect(p)
		for x in range(maxi(r.position.x, 1), r.end.x):
			for y in range(maxi(r.position.y, 1), r.end.y):
				out[Vector2i(x, y)] = true
	return out


# the cells a person or a pet steps onto to use a piece: the side a piece faces (a piece on a wall
# faces away from it), the door's, and the pets' spots
func in_front() -> Dictionary:
	var out := {DOOR_FRONT: true, DOOR_FRONT + Vector2i(1, 0): true}
	for cell in _spot_cells():
		out[cell] = true
	for p in all():
		var side: String = p["f"]
		if kind(p) == "hug":
			side = {"ne": "sw", "nw": "se"}.get(side, "")
		if PetThings.is_pet(p) or kind(p) not in ["floor", "hug"] or not FRONT.has(side):
			continue
		var r := rect(p)
		for x in range(r.position.x, r.end.x):
			for y in range(r.position.y, r.end.y):
				var cell: Vector2i = Vector2i(x, y) + FRONT[side]
				if not r.has_point(cell):
					out[cell] = true
	return out


func _wall_fixed(cell: Vector2i) -> bool:
	return (
		(cell.y == 0 and cell.x in WALL_FIXED["ne"]) or (cell.x == 0 and cell.y in WALL_FIXED["nw"])
	)


# "" when the piece may stand as it is, else the reason; `skip` is the piece being moved and
# `busy` the cells somebody stands on
func check(p: Dictionary, skip: Variant, busy: Array) -> String:
	if art and p["f"] not in _faces(p):
		return NO_ROOM
	var k := kind(p)
	if k == "wall" or k == "hug":
		return _check_wall(p, skip)
	var r := rect(p)
	if r.position.x < 0 or r.position.y < 0 or r.end.x > Pets.COLS or r.end.y > Pets.ROWS:
		return NO_ROOM
	if k == "rug":
		return ""
	if PetThings.is_pet(p):
		return _check_pet(p, skip, busy, r)
	var top := table_under(p)
	for o in _solid():
		if is_same(o, skip) or kind(o) == "rug":
			continue
		var ok := kind(o)
		if ok == "wall":
			if height(p) >= TALL and r.has_point(Vector2i(o["c"], o["r"])):
				return NO_ROOM
		elif r.intersects(rect(o)) and not is_same(o, top):
			return STAYS if o.has("fixed") else NO_ROOM
	if r.intersects(PETS_CORNER) or r.has_point(DOOR_CELL):
		return STAYS
	if height(p) > LOW:
		for x in range(r.position.x, r.end.x):
			for y in range(r.position.y, r.end.y):
				if _wall_fixed(Vector2i(x, y)):
					return STAYS
	for cell in _spot_cells() + busy:
		if r.has_point(cell):
			return BUSY
	return "" if reaches(blocked(p, skip), busy) else SHUTS


# the table a piggy bank stands on, {} for any other piece or a bank on the floor
func table_under(p: Dictionary) -> Dictionary:
	if not Money.is_piggy(p):
		return {}
	var r := rect(p)
	for o in _solid():
		if o["p"] in TABLE_TOPS and rect(o).encloses(r):
			return o
	return {}


# how high up a piece stands: the table top under a piggy bank, else the floor
func lift(p: Dictionary) -> int:
	var table := table_under(p)
	return 0 if table.is_empty() else TABLE_TOPS[table["p"]]


# the corner, in cell units, the piggy bank is drawn from: its cell's, or on a table the one that
# puts it in the middle of the top, so no part of it hangs over an edge
func seat(p: Dictionary) -> Vector2:
	var table := table_under(p)
	if table.is_empty():
		return Vector2(p["c"], p["r"])
	var r := rect(table)
	return Vector2(r.position) + Vector2(r.size) / 2.0 - Vector2(0.5, 0.5)


# a pet thing: once, never on another piece, and a pet can get to it
func _check_pet(p: Dictionary, skip: Variant, busy: Array, r: Rect2i) -> String:
	var flat: bool = kind(p) == "flat"
	if flat and (r.position.x < 1 or r.position.y < 1):
		return NO_ROOM
	for o in _solid():
		if is_same(o, skip) or kind(o) == "rug":
			continue
		var why := ""
		if kind(o) == "wall":
			why = NO_ROOM if height(p) >= TALL and r.has_point(Vector2i(o["c"], o["r"])) else ""
		elif PetThings.is_pet(o) and o["p"] == p["p"]:
			why = ONCE
		elif r.intersects(rect(o)):
			why = STAYS if o.has("fixed") else NO_ROOM
		if why != "":
			return why
	if (height(p) > LOW and _wall_fixed(r.position)) or (not flat and _on_spot(r, busy)):
		return STAYS if height(p) > LOW else BUSY
	var shut := blocked(p, skip)
	if not reaches(shut, busy):
		return SHUTS
	return "" if _usable(r.position, flat, _flood(shut)) else SHUTS


func _on_spot(r: Rect2i, busy: Array) -> bool:
	return (_spot_cells() + busy).any(func(c): return r.has_point(c))


# a walk-over thing is walked to, a solid one from a cell beside it
func _usable(cell: Vector2i, flat: bool, seen: Dictionary) -> bool:
	if flat:
		return seen.has(cell)
	return [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)].any(
		func(d): return seen.has(cell + d)
	)


func _spot_cells() -> Array:
	var out: Array = []
	for name in Pets.SPOTS:
		if name not in MOVING_SPOTS:
			out.append(Pets.SPOTS[name]["cell"])
	return out


func _faces(p: Dictionary) -> Array:
	var e := _entry(p["p"])
	return e["faces"] if not e.is_empty() and not e["faces"].is_empty() else [""]


func _check_wall(p: Dictionary, skip: Variant) -> String:
	var ne: bool = p["f"] == "ne"
	var cell := Vector2i(p["c"], p["r"])
	var along: int = cell.x if ne else cell.y
	var across: int = cell.y if ne else cell.x
	if across != 0 or along < 0 or along >= (Pets.COLS if ne else Pets.ROWS):
		return NO_ROOM
	if along in WALL_FIXED["ne" if ne else "nw"]:
		return STAYS
	for o in _solid():
		if is_same(o, skip):
			continue
		var ok := kind(o)
		if ok == "wall" or ok == "hug":
			if o["f"] == p["f"] and o["c"] == p["c"] and o["r"] == p["r"]:
				return NO_ROOM
		elif ok == "floor" and rect(o).has_point(cell):
			if kind(p) == "hug" or height(o) >= TALL:
				return STAYS if o.has("fixed") else NO_ROOM
	return ""


# every spot and every cell in `busy` can be walked to from the door
func reaches(blocked_cells: Dictionary, busy: Array) -> bool:
	var seen := _flood(blocked_cells)
	for cell in _spot_cells():
		if not seen.has(cell):
			return false
	for cell in busy:
		if not seen.has(cell) and not blocked_cells.has(cell):
			return false
	return true


# every cell that can be walked to from the door
func _flood(blocked_cells: Dictionary) -> Dictionary:
	var seen := {DOOR_FRONT: true}
	var queue: Array = [DOOR_FRONT]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_back()
		for d in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]:
			var n: Vector2i = cur + d
			if (
				seen.has(n)
				or blocked_cells.has(n)
				or n.x < 1
				or n.y < 1
				or n.x >= Pets.COLS
				or n.y >= Pets.ROWS
			):
				continue
			seen[n] = true
			queue.append(n)
	return seen


# put a new piece down, or with `moving` set move that piece to where `p` says
func place(p: Dictionary, moving: Variant, busy: Array) -> String:
	var why := check(p, moving, busy)
	if why != "":
		return why
	if moving != null:
		moving["f"] = p["f"]
		moving["c"] = p["c"]
		moving["r"] = p["r"]
	else:
		pieces.append(p)
	version += 1
	save()
	return ""


func remove(p: Dictionary) -> void:
	pieces = pieces.filter(func(o): return not is_same(o, p))
	version += 1
	save()


func set_style(what: String, style: String) -> void:
	if what == "wall":
		wall = style
		_dormant_wall = ""
	else:
		floor_style = style
		_dormant_floor = ""
	save()


func walls_of(tab: String) -> Array:
	return walls.filter(func(s): return Packs.tab_of(s) == tab)


func floors_of(tab: String) -> Array:
	return floors.filter(func(s): return Packs.tab_of(s) == tab)


func reset(busy: Array) -> void:
	wall = "wallpaper"
	floor_style = "oak"
	_dormant = []
	_dormant_wall = ""
	_dormant_floor = ""
	pets_seen = []
	old_things = false
	offered = NEWER.duplicate()
	pieces = _defaults(busy)
	version += 1
	save()


func save() -> void:
	if not persist or path == "":
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		var saved: Array = pieces.map(_row)
		var doc := {
			"v": SAVED,
			"wall": _dormant_wall if _dormant_wall != "" else wall,
			"floor": _dormant_floor if _dormant_floor != "" else floor_style,
			"pieces": saved + _dormant,
		}
		doc["offered"] = offered
		if not pets_seen.is_empty():
			doc["pets_seen"] = pets_seen
		f.store_string(JSON.stringify(doc))


func _row(p: Dictionary) -> Dictionary:
	var row := {"p": p["p"], "f": p["f"], "c": p["c"], "r": p["r"]}
	if p.get("own", false):
		row["own"] = true
	return row


# a missing or unreadable file leaves the default; a piece that cannot stand is skipped, one of a
# pack that is not here is kept for the file. The furniture is read before the pets' things, so a
# thing that was hidden under a piece put there since is the one that gives way.
func load_file() -> bool:
	if not FileAccess.file_exists(path):
		return false
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return false
	var d: Variant = json.data
	if not d is Dictionary or not d.get("pieces") is Array:
		return false
	_dormant = []
	_dormant_wall = ""
	_dormant_floor = ""
	if str(d.get("wall")) in walls:
		wall = d["wall"]
	elif _absent(str(d.get("wall"))):
		_dormant_wall = d["wall"]
	if str(d.get("floor")) in floors:
		floor_style = d["floor"]
	elif _absent(str(d.get("floor"))):
		_dormant_floor = d["floor"]
	var rows: Array = []
	for i in d["pieces"].size():
		rows.append([i, d["pieces"][i]])
	rows.sort_custom(func(a, b): return _load_order(a) < _load_order(b))
	var out: Array = []
	var dropped: Array = []
	var old_file: bool = not (d.get("v") is float and d["v"] >= SAVED)
	var lost_frame := false
	for pair in rows:
		var row: Variant = pair[1]
		if not row is Dictionary or not (row.get("p") is String and row.get("f") is String):
			continue
		if not (row.get("c") is float and row.get("r") is float):
			continue
		var p := {"p": row["p"], "f": row["f"], "c": int(row["c"]), "r": int(row["r"]), "_i": pair[0]}
		if row.get("own", false) == true:
			p["own"] = true
		if _entry(p["p"]).is_empty():
			if _absent(p["p"]):
				_dormant.append(p)
			continue
		pieces = out
		if check(p, null, []) == "":
			out.append(p)
		elif PetThings.is_pet(p):
			dropped.append(PetThings.key_of(p))
		elif People.is_frame(p) and old_file:
			lost_frame = true
	out.sort_custom(func(a, b): return a["_i"] < b["_i"])
	for p in out:
		p.erase("_i")
	pieces = out
	old_things = not (d.get("v") is float and d["v"] >= THINGS_SAVED)
	if old_file:
		if lost_frame and frame().is_empty():
			_offer(People.PIECE)
		_move_old_defaults()
	pets_seen = []
	if d.get("pets_seen") is Array:
		pets_seen = d["pets_seen"].filter(func(k): return k is String and k not in dropped)
	offered = (
		d["offered"].filter(func(k): return k is String) if d.get("offered") is Array else []
	)
	var offering := false
	for key in NEWER:
		if key not in offered:
			offered.append(key)
			offering = true
			if not pieces.any(func(p): return p["p"] == key):
				_offer(key)
	if offering:
		save()
	version += 1
	return true


# a piece still on its old default cell goes to the current default, once, when that cell is free
func _move_old_defaults() -> void:
	for key in OLD_DEFAULTS:
		for piece in pieces:
			if piece["p"] != key or Vector2i(piece["c"], piece["r"]) != OLD_DEFAULTS[key]:
				continue
			var row: Array = DEFAULTS.filter(func(r): return r[0] == key)[0]
			var moved := _piece([key, row[1], row[2], row[3]])
			if check(moved, piece, []) == "":
				piece["c"] = moved["c"]
				piece["r"] = moved["r"]


# a default piece new to a saved layout goes at its default cell, else the nearest cell it may
# stand on
func _offer(key: String) -> void:
	var row: Array = DEFAULTS.filter(func(r): return r[0] == key)[0]
	var cell: Variant = _nearest(key, row[1], Vector2i(row[2], row[3]), null)
	if cell != null:
		pieces.append(_piece([key, row[1], cell.x, cell.y]))


# the cell nearest `near` that `key` may stand on, null when there is none
func _nearest(key: String, face: String, near: Vector2i, skip: Variant) -> Variant:
	var cells: Array = []
	for c in Pets.COLS:
		for r in Pets.ROWS:
			cells.append(Vector2i(c, r))
	cells.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool:
			return (
				[(a - near).length_squared(), a.x, a.y] < [(b - near).length_squared(), b.x, b.y]
			)
	)
	for cell in cells:
		if check(_piece([key, face, cell.x, cell.y]), skip, []) == "":
			return cell
	return null


func _pet_row(row: Variant) -> bool:
	return row is Dictionary and str(row.get("p", "")).begins_with(PetThings.PREFIX)


# a file's rows are placed in order, the piggy bank after the tables it may stand on and the pet
# things after all
func _load_order(pair: Array) -> Array:
	var bank: bool = pair[1] is Dictionary and str(pair[1].get("p", "")) == Money.PIECE
	return [_pet_row(pair[1]), bank, pair[0]]


# named for one of our packs, and that pack is not in the catalogue
func _absent(id: String) -> bool:
	var ns := Packs.pack_of(id)
	return ns != "" and not catalogue.any(func(e): return e["key"].begins_with(ns + "."))
