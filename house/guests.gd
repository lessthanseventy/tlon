extends RefCounted

# What the room lends for a while, none of it the owner's layout: a meal on the table at mealtimes
# (food-icons pack) and, in the last week of October, the mansion's cobwebs and candles.
const FOOD := "food-icons/Gridwright Food & Cooking Icons/PNG/1x/"
const TABLES := ["dining_table", "round_table", "tavern_table"]
const ICON := 16.0
# name, from hour, to hour, dishes, drinks
const MEALS := [
	[
		"breakfast",
		7.0,
		9.0,
		[
			"bakery/croissant",
			"bakery/pancakes",
			"bakery/toast",
			"bakery/waffle",
			"meals/omelette",
			"meals/porridge"
		],
		["drinks/coffee", "drinks/tea", "drinks/juice_orange", "drinks/milk"],
	],
	[
		"lunch",
		12.0,
		13.0,
		[
			"meals/sandwich",
			"meals/salad",
			"meals/soup_tomato",
			"meals/burger",
			"meals/rice_bowl",
			"meals/taco"
		],
		["drinks/lemonade", "drinks/water", "drinks/juice_apple"],
	],
	[
		"dinner",
		18.0,
		20.0,
		[
			"meals/spaghetti",
			"meals/steak_dinner",
			"meals/pizza",
			"meals/curry",
			"meals/stew",
			"meals/ramen"
		],
		["drinks/water", "drinks/wine_glass", "drinks/juice_grape"],
	],
]
const SEASONAL := ["mansion.cobweb", "mansion.candles", "mansion.cobweb"]

var _seen: Array = []


# the meal the hour falls in, else -1
static func meal(hour: float) -> int:
	for i in MEALS.size():
		if hour >= MEALS[i][1] and hour < MEALS[i][2]:
			return i
	return -1


# one dish and one drink, the same for the whole meal of that day
static func picks(day: int, which: int) -> Array:
	var r := RandomNumberGenerator.new()
	r.seed = day * 10 + which
	var row: Array = MEALS[which]
	return [row[3][r.randi() % row[3].size()], row[4][r.randi() % row[4].size()]]


static func last_week_of_october(unix: float) -> bool:
	var d := Time.get_datetime_dict_from_unix_time(int(unix))
	return d["month"] == 10 and d["day"] >= 25


func table(h) -> Dictionary:
	for name in TABLES:
		for p in h.layout.pieces:
			if p["p"] == name:
				return p
	return {}


func items(h) -> Array:
	var which := meal(h._hour())
	var t := table(h)
	if which < 0 or t.is_empty() or h.finds.is_birthday():
		return []
	var tex: Array = []
	for name in picks(int(h._now_local() / 86400.0), which):
		var file: String = h.room.art_dir.path_join(FOOD) + name + ".png"
		if FileAccess.file_exists(file):
			tex.append(h.room._load_texture(file))
	if tex.is_empty():
		return []
	return [
		{"key": float(h.layout.draw_key(t)) + 0.5, "pri": 1.9, "fn": _draw_meal.bind(h, t, tex)}
	]


func _draw_meal(h, t: Dictionary, tex: Array) -> void:
	var r: Rect2i = h.layout.rect(t)
	var cells: Array = []
	for x in r.size.x:
		for y in r.size.y:
			cells.append(Vector2(r.position.x + x + 0.5, r.position.y + y + 0.5))
	var side: float = ICON * h._k
	for i in mini(tex.size(), cells.size()):
		var at: Vector2 = h._p(cells[i].x, cells[i].y, float(h.layout.height(t)))
		h.room.draw_texture_rect(
			tex[i], Rect2(at + Vector2(-side / 2.0, -side * 0.42), Vector2(side, side)), false
		)


# the guests follow the date and the layout: chosen again when either changes
func update(h) -> void:
	var on: bool = h.layout.art and last_week_of_october(h._now_local())
	var stamp := [on, h.layout.version, h.petlife.sig()]
	if stamp == _seen:
		return
	_seen = stamp
	var before: Array = h.layout.guests
	h.layout.guests = _choose(h) if on else h.petlife.pieces()
	if h.layout.guests != before:
		h.apply_layout()


func _choose(h) -> Array:
	var l = h.layout
	var r := RandomNumberGenerator.new()
	r.seed = Time.get_datetime_dict_from_unix_time(int(h._now_local()))["year"]
	var busy: Array = h.busy_cells()
	var out: Array = h.petlife.pieces()
	var sides: Array = []
	l.guests = out
	for name in SEASONAL:
		var e: Dictionary = l.entry(name)
		if e.is_empty():
			continue
		var cands := _spots(e)
		for i in range(cands.size() - 1, 0, -1):
			var j := r.randi() % (i + 1)
			var tmp: Dictionary = cands[i]
			cands[i] = cands[j]
			cands[j] = tmp
		for p in cands:
			if p["f"] in sides or l.check(p, null, busy) != "":
				continue
			if p["f"] != "":
				sides.append(p["f"])
			p["fixed"] = true
			out.append(p)
			break
	return out


# every place the piece could go: along the walls for what hangs, round the edge for the rest
func _spots(e: Dictionary) -> Array:
	var out: Array = []
	for f in e["faces"] if not e["faces"].is_empty() else [""]:
		for i in 10:
			if e["kind"] == "wall":
				out.append(
					{"p": e["key"], "f": f, "c": i if f == "ne" else 0, "r": 0 if f == "ne" else i}
				)
			else:
				for j in 10:
					if i in [1, 9] or j in [1, 9]:
						out.append({"p": e["key"], "f": f, "c": i, "r": j})
	return out
