extends Control

const COLS := 8
const ROWS := 8
const WALL_H := 48
const FRAME_FPS := 6.0
const FRAMES := 4
const SHADOW := Color(1, 1, 1, 0.35)

# id, min col, min row, footprint (cols, rows), height at 1x, fallback colour
const FURNITURE := [
	["bookshelf_sw", 1, 0, 1, 1, 39, Color("8a5a3c")],
	["bookshelf_sw", 2, 0, 1, 1, 39, Color("8a5a3c")],
	["computer_desk_sw", 4, 0, 2, 1, 31, Color("b58a5a")],
	["office_chair_ne", 4, 1, 1, 1, 26, Color("5a6f8a")],
	["plant_large", 7, 0, 1, 1, 34, Color("5f8a4f")],
	["bookshelf_se", 0, 2, 1, 1, 39, Color("8a5a3c")],
	["side_table", 0, 3, 1, 1, 14, Color("b58a5a")],
	["sofa_se", 0, 4, 1, 2, 17, Color("9a4f58")],
	["floor_lamp", 0, 6, 1, 1, 33, Color("d9b86a")],
]
const RUG := ["rug_blue_nwse", 1, 4, 3, 2, Color("4a6a9a")]
const WALL_WINDOWS := {"ne": [4], "nw": [5]}
const PERSON := {"name": "villager", "col": 3, "row": 5}

var art_dir := ""
var open_count := 0
var art_found := false

var _index := {}
var _textures := {}
var _t := 0.0
var _frame := 0
var _person_sheet: Texture2D
var _person_shadow: Texture2D
var _k := 2


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	clip_contents = true
	_load_index()


func _load_index() -> void:
	var text := FileAccess.get_file_as_string(_interiors() + "isometric.json")
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary and parsed.has("sprites"):
		_index = parsed["sprites"]
		art_found = _person_dir() != "" and DirAccess.dir_exists_absolute(_interiors() + "PNG")


func _interiors() -> String:
	return art_dir.path_join("isometric-interiors/Gridwright Isometric Interiors/")


func _person_dir() -> String:
	return art_dir.path_join("isometric-characters/Gridwright Isometric Characters/")


func _process(delta: float) -> void:
	_t += delta
	var f := int(_t * FRAME_FPS) % FRAMES
	if f != _frame:
		_frame = f
		queue_redraw()


func _load_texture(path: String) -> Texture2D:
	if _textures.has(path):
		return _textures[path]
	var tex: Texture2D = null
	var image := Image.load_from_file(path)
	if image != null:
		tex = ImageTexture.create_from_image(image)
	_textures[path] = tex
	return tex


func _sprite(id: String) -> Dictionary:
	if not _index.has(id):
		return {}
	var s: Dictionary = _index[id]
	var tex := _load_texture(_interiors() + str(s["file"]).replace("/1x/", "/%dx/" % _k))
	if tex == null:
		return {}
	return {
		"tex": tex,
		"anchor": Vector2(s["anchor"][0], s["anchor"][1]) * _k,
		"shadow": s.get("shadow", "")
	}


func _pick_scale() -> int:
	if size.x >= COLS * 32 * 3 + 16 and size.y >= (ROWS * 16 + WALL_H) * 3 + 16:
		return 3
	return 2


func _draw() -> void:
	_k = _pick_scale()
	var origin := Vector2(
		size.x / 2.0, (size.y - (WALL_H + 8 * (COLS + ROWS)) * _k) / 2.0 + WALL_H * _k
	)
	var drawn_any := false

	for r in ROWS:
		for c in COLS:
			var d := _sprite("floor_oak_0%d" % (1 + (c + r) % 2))
			var p := _p(origin, c, r)
			if d.is_empty():
				draw_colored_polygon(
					_diamond(p), Color("c9a77c") if (c + r) % 2 == 0 else Color("bf9c71")
				)
			else:
				draw_texture(d["tex"], (p - d["anchor"]).round())
				drawn_any = true

	_draw_rug(origin)

	var items: Array = []
	for w in _walls():
		items.append({"key": w["c"] + w["r"], "pri": 0, "wall": w})
	for f in FURNITURE:
		items.append({"key": f[1] + f[3] - 1 + f[2] + f[4] - 1, "pri": 1, "furn": f})
		var s := _sprite(f[0])
		if not s.is_empty() and s["shadow"] != "":
			var sh := _sprite(s["shadow"])
			if not sh.is_empty():
				draw_texture(sh["tex"], (_p(origin, f[1], f[2]) - sh["anchor"]).round(), SHADOW)
	items.append({"key": PERSON["col"] + PERSON["row"], "pri": 2, "person": true})
	items.sort_custom(
		func(a, b): return a["key"] < b["key"] or (a["key"] == b["key"] and a["pri"] < b["pri"])
	)

	_draw_person_shadow(origin)
	for it in items:
		if it.has("wall"):
			_draw_wall(origin, it["wall"])
		elif it.has("furn"):
			_draw_furniture(origin, it["furn"])
		else:
			_draw_person(origin)
	_draw_badge(origin)


func _p(origin: Vector2, c: float, r: float) -> Vector2:
	return origin + Vector2(16 * (c - r), 8 * (c + r)) * _k


func _diamond(p: Vector2) -> PackedVector2Array:
	var h := Vector2(16, 8) * _k
	return PackedVector2Array(
		[p, p + Vector2(h.x, h.y), p + Vector2(0, 2 * h.y), p + Vector2(-h.x, h.y)]
	)


func _walls() -> Array:
	var out: Array = []
	for c in COLS:
		var kind := "corner" if c == 0 else ("ne_window" if c in WALL_WINDOWS["ne"] else "ne")
		out.append({"c": c, "r": 0, "id": "wall_plaster_" + kind, "side": "ne"})
	for r in range(1, ROWS):
		var kind := "nw_window" if r in WALL_WINDOWS["nw"] else "nw"
		out.append({"c": 0, "r": r, "id": "wall_plaster_" + kind, "side": "nw"})
	return out


func _draw_wall(origin: Vector2, w: Dictionary) -> void:
	var s := _sprite(w["id"])
	var p := _p(origin, w["c"], w["r"])
	if not s.is_empty():
		draw_texture(s["tex"], (p - s["anchor"]).round())
		return
	var up := Vector2(0, WALL_H * _k)
	var east := p + Vector2(16, 8) * _k
	var west := p + Vector2(-16, 8) * _k
	if w["side"] == "ne":
		draw_colored_polygon(PackedVector2Array([p, east, east - up, p - up]), Color("8d8aa3"))
	if w["side"] == "nw" or w["id"].ends_with("corner"):
		draw_colored_polygon(PackedVector2Array([p, west, west - up, p - up]), Color("77748c"))


func _draw_rug(origin: Vector2) -> void:
	var s := _sprite(RUG[0])
	if not s.is_empty():
		draw_texture(s["tex"], (_p(origin, RUG[1], RUG[2]) - s["anchor"]).round())
		return
	_flat_box(origin, RUG[1], RUG[2], RUG[3], RUG[4], 0, RUG[5])


func _draw_furniture(origin: Vector2, f: Array) -> void:
	var s := _sprite(f[0])
	if s.is_empty():
		_flat_box(origin, f[1], f[2], f[3], f[4], f[5], f[6])
		return
	draw_texture(s["tex"], (_p(origin, f[1], f[2]) - s["anchor"]).round())


func _flat_box(origin: Vector2, c: int, r: int, fc: int, fr: int, h: float, col: Color) -> void:
	var up := Vector2(0, h * _k)
	var back := _p(origin, c, r)
	var right := _p(origin, c + fc, r)
	var left := _p(origin, c, r + fr)
	var front := _p(origin, c + fc, r + fr)
	if h > 0:
		draw_colored_polygon(
			PackedVector2Array([left, front, front - up, left - up]), col.darkened(0.25)
		)
		draw_colored_polygon(
			PackedVector2Array([front, right, right - up, front - up]), col.darkened(0.4)
		)
	draw_colored_polygon(PackedVector2Array([back - up, right - up, front - up, left - up]), col)


func _person_frame_pos(origin: Vector2) -> Vector2:
	var feet := _p(origin, PERSON["col"], PERSON["row"]) + Vector2(0, 8 * _k)
	return feet


func _draw_person_shadow(origin: Vector2) -> void:
	if _person_shadow == null:
		_person_shadow = _load_texture(_person_dir() + "Effects/%dx/shadow.png" % _k)
	if _person_shadow != null:
		draw_texture(
			_person_shadow, (_person_frame_pos(origin) - Vector2(16, 8) * _k).round(), SHADOW
		)


func _draw_person(origin: Vector2) -> void:
	var name: String = PERSON["name"]
	var sheet := _load_texture(_person_dir() + "Sheets/%dx/%s/%s_idle.png" % [_k, name, name])
	var feet := _person_frame_pos(origin)
	if sheet == null:
		draw_circle(feet - Vector2(0, 14 * _k), 8 * _k, Color("e0b07a"))
		draw_rect(
			Rect2(feet - Vector2(6 * _k, 12 * _k), Vector2(12 * _k, 12 * _k)), Color("6f8fb0")
		)
		return
	var cell := 64 * _k
	draw_texture_rect_region(
		sheet,
		Rect2((feet - Vector2(32, 46) * _k).round(), Vector2(cell, cell)),
		Rect2(_frame * cell, 0, cell, cell)
	)


func _draw_badge(origin: Vector2) -> void:
	if open_count <= 0:
		return
	var desk := _p(origin, 5, 0) + Vector2(0, -52 * _k)
	var font := ThemeDB.fallback_font
	var radius := 13.0
	draw_circle(desk, radius + 2, Color("2a2530"))
	draw_circle(desk, radius, Color("e8b86d"))
	var label := str(open_count)
	var fs := 18
	var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(
		font, desk + Vector2(-w / 2.0, 6), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("2a2530")
	)
