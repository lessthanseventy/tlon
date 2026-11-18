extends Control

signal door_clicked
signal pressed_empty

const WALL_H := 48
const FRAME_FPS := 6.0
const FRAMES := 4
const SHADOW := Color(1, 1, 1, 0.35)
const DESK_SLOTS := 8
const DESK_COLS := 4
const FACE_NE := 5

# the home's furniture, floor and wall come from `home.layout`
const HOME := {
	"cols": 10,
	"rows": 10,
	"windows": {"ne": [4], "nw": []},
	"door": {"row": 7, "label": "to the office"},
	"figures": [],
}
const OFFICE_FIXED := [
	["filing_cabinet_se", 0, 1, 1, 1, 28, Color("7d8794")],
	["filing_cabinet_se", 0, 5, 1, 1, 28, Color("7d8794")],
	["filing_cabinet_se", 0, 6, 1, 1, 28, Color("7d8794")],
	["plant_large", 8, 2, 1, 1, 34, Color("5f8a4f")],
	["waste_bin", 8, 3, 1, 1, 11, Color("6f7480")],
	["plant_small", 8, 6, 1, 1, 18, Color("5f8a4f")],
]
const SKINS := ["villager", "knight", "mage", "ranger", "rogue", "barbarian", "cultist", "skeleton"]
const SKIN_FALLBACK := [
	Color("6f8fb0"),
	Color("9a9aa8"),
	Color("8a6fb0"),
	Color("5f8a4f"),
	Color("b0806f"),
	Color("b0553c"),
	Color("6f4f7a"),
	Color("c8c4b8"),
]
const MARK_COLOR := Color("e8b86d")
const INK := Color("2a2530")
const HomeScript := preload("res://home.gd")
const Packs := preload("res://packs.gd")
const Guests := preload("res://guests.gd")

var art_dir := ""
var art_found := false
var home := HomeScript.new()
var decorate: Control
var guests := Guests.new()

var _desc := HOME
var _caption := ""
var _index := {}
var _textures := {}
var _t := 0.0
var _frame := 0
var _person_shadow: Texture2D
var _k := 2
var _origin := Vector2.ZERO
var _hover_door := false
var door_ajar := false
# false when the home keeps its own list: there is no office to go to
var office_door := true


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	clip_contents = true
	_load_index()
	home.setup(self, art_dir, OS.get_cmdline_user_args())
	mouse_exited.connect(home.leave)


func show_home() -> void:
	_desc = HOME
	_caption = ""
	_hover_door = false
	queue_redraw()


# crew: [{name, status, skin}] in desk order; at most DESK_SLOTS get a desk
func show_office(crew: Array, caption: String) -> void:
	var n := clampi(crew.size(), DESK_COLS, DESK_SLOTS)
	var furniture: Array = OFFICE_FIXED.duplicate()
	var figures: Array = []
	for i in n:
		var col := 1 + 2 * (i % DESK_COLS)
		var row := 0 if i < DESK_COLS else 4
		furniture.append(["computer_desk_sw", col, row, 2, 1, 31, Color("b58a5a")])
		furniture.append(["office_chair_ne", col, row + 1, 1, 1, 26, Color("5a6f8a")])
		if i < crew.size():
			figures.append(_figure(crew[i], col, row + 1))
	_desc = {
		"cols": 9,
		"rows": 7,
		"floor": "carpet_blue",
		"wall": "wallpaper",
		"furniture": furniture,
		"rugs": [["rug_blue_nwse", 3, 2, 3, 2, Color("4a6a9a")]],
		"windows": {"ne": [2, 6], "nw": []},
		"door": {"row": 3, "label": "to the home"},
		"figures": figures,
	}
	_caption = caption
	_hover_door = false
	queue_redraw()


func _figure(c: Dictionary, col: int, row: int) -> Dictionary:
	var status: String = c["status"]
	var skin := int(c["skin"]) % SKINS.size()
	return {
		"sheet": SKINS[skin],
		"tint": SKIN_FALLBACK[skin],
		"col": col,
		"row": row,
		"dir": FACE_NE,
		"anim": status == "working" or status == "waiting",
		"alpha": 0.4 if status == "off" else (0.7 if status == "cold" else 1.0),
		"lift": 5,
		"away": status == "off",
		"name": c["name"],
		"status": status,
	}


func _load_index() -> void:
	var text := FileAccess.get_file_as_string(_interiors() + "isometric.json")
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary and parsed.has("sprites"):
		_index = Packs.extend(parsed["sprites"], art_dir)
		art_found = _person_dir() != "" and DirAccess.dir_exists_absolute(_interiors() + "PNG")


func _interiors() -> String:
	return art_dir.path_join("isometric-interiors/Gridwright Isometric Interiors/")


func _dir(s: Dictionary) -> String:
	return s.get("dir", _interiors())


func _person_dir() -> String:
	return art_dir.path_join("isometric-characters/Gridwright Isometric Characters/")


func _process(delta: float) -> void:
	_t += delta
	var f := int(_t * FRAME_FPS) % FRAMES
	if _desc == HOME:
		home.process(delta)
		guests.update(home)
		queue_redraw()
	elif f != _frame:
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
	var tex := _load_texture(_dir(s) + str(s["file"]).replace("/1x/", "/%dx/" % _k))
	if tex == null:
		return {}
	return {
		"tex": tex,
		"anchor": Vector2(s["anchor"][0], s["anchor"][1]) * _k,
		"shadow": s.get("shadow", "")
	}


# a sprite at 1x, whole, for the decorate catalogue
func icon(id: String) -> Texture2D:
	id = id % 1 if "%d" in id else id
	if not _index.has(id):
		return null
	return _load_texture(_dir(_index[id]) + str(_index[id]["file"]))


func _pick_scale() -> int:
	var span: int = _desc["cols"] + _desc["rows"]
	if size.x >= span * 16 * 3 + 16 and size.y >= (span * 8 + WALL_H) * 3 + 16:
		return 3
	if size.x >= span * 16 * 2 + 16 and size.y >= (span * 8 + WALL_H) * 2 + 16:
		return 2
	return 1


func _gui_input(event: InputEvent) -> void:
	if decorate != null and decorate.active and _desc == HOME:
		decorate.room_input(event)
		return
	if event is InputEventMouseMotion:
		var at_home := _desc == HOME and home.hover(event.position)
		var over := _door_hit(event.position)
		if over != _hover_door:
			_hover_door = over
			queue_redraw()
		mouse_default_cursor_shape = (
			Control.CURSOR_POINTING_HAND if over or at_home else Control.CURSOR_ARROW
		)
	elif (
		event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	):
		if _desc == HOME and home.click(event.position):
			return
		if _door_hit(event.position):
			door_clicked.emit()
		else:
			pressed_empty.emit()


func _door_hit(pos: Vector2) -> bool:
	if not office_door:
		return false
	var p := _p(_origin, 0, _desc["door"]["row"])
	var up := Vector2(0, WALL_H * _k)
	var west := p + Vector2(-16, 8) * _k
	return Geometry2D.is_point_in_polygon(pos, PackedVector2Array([p, west, west - up, p - up]))


func _draw() -> void:
	_k = _pick_scale()
	var cols: int = _desc["cols"]
	var rows: int = _desc["rows"]
	var floor_style := _style("floor")
	var plan := home.layout.rows() if _desc == HOME else _desc
	_origin = Vector2(
		size.x / 2.0, (size.y - (WALL_H + 8 * (cols + rows)) * _k) / 2.0 + WALL_H * _k
	)
	var origin := _origin

	for r in rows:
		for c in cols:
			var d := _sprite("floor_%s_0%d" % [floor_style, 1 + (c + r) % 2])
			var p := _p(origin, c, r)
			if d.is_empty():
				draw_colored_polygon(
					_diamond(p), Color("c9a77c") if (c + r) % 2 == 0 else Color("bf9c71")
				)
			else:
				draw_texture(d["tex"], (p - d["anchor"]).round())

	for rug in plan["rugs"]:
		_draw_rug(origin, rug)
	if _desc == HOME:
		home.draw_floor()

	var items: Array = []
	if _desc == HOME:
		items.append_array(home.items())
		items.append_array(guests.items(home))
	for w in _walls():
		items.append({"key": w["c"] + w["r"], "pri": 0, "wall": w})
	for d in plan.get("decor", []):
		items.append({"key": d[1] + d[2], "pri": 0.3, "furn": d})
	for f in plan["furniture"]:
		var pri := 1.8 if _desc == HOME and f[0] == "office_chair_ne" else 1.0
		items.append(
			{"key": f[1] + f[3] - 1 + f[2] + f[4] - 1, "pri": pri, "row": f[2] + f[4], "furn": f}
		)
		var s := _sprite(_furn_id(f))
		if not s.is_empty() and s["shadow"] != "":
			var sh := _sprite(s["shadow"])
			if not sh.is_empty():
				draw_texture(sh["tex"], (_p(origin, f[1], f[2]) - sh["anchor"]).round(), SHADOW)
	for fig in _desc["figures"]:
		items.append({"key": fig["col"] + fig["row"], "pri": 2, "fig": fig})
		if not fig.get("away", false):
			_draw_person_shadow(origin, fig)
	items.sort_custom(_before)

	for it in items:
		if it.has("wall"):
			_draw_wall(origin, it["wall"])
		elif it.has("fn"):
			it["fn"].call()
		elif it.has("furn"):
			_draw_furniture(origin, it["furn"])
		else:
			if not it["fig"].get("away", false):
				_draw_person(origin, it["fig"])
	for fig in _desc["figures"]:
		_draw_tags(origin, fig)
	_draw_door_label(origin)
	_draw_caption()
	if _desc == HOME:
		home.draw_over()
		if decorate != null and decorate.active:
			decorate.draw_ghost()


# back to front; at one depth a wide piece's row decides, so a chair sits over the table behind it
func _before(a: Dictionary, b: Dictionary) -> bool:
	if a["key"] != b["key"]:
		return a["key"] < b["key"]
	if a["pri"] != b["pri"]:
		return a["pri"] < b["pri"]
	return a.get("row", 0) < b.get("row", 0)


func _style(key: String) -> String:
	if _desc == HOME:
		return home.layout.wall if key == "wall" else home.layout.floor_style
	return _desc[key]


# a piece with frames names them "..._f%d": it is the same sprite, a few times a second
func _furn_id(f: Array) -> String:
	var id: String = f[0]
	return id % (1 + int(_t * 8.0) % FRAMES) if "%d" in id else id


func _p(origin: Vector2, c: float, r: float) -> Vector2:
	return origin + Vector2(16 * (c - r), 8 * (c + r)) * _k


func _diamond(p: Vector2) -> PackedVector2Array:
	var h := Vector2(16, 8) * _k
	return PackedVector2Array(
		[p, p + Vector2(h.x, h.y), p + Vector2(0, 2 * h.y), p + Vector2(-h.x, h.y)]
	)


func _walls() -> Array:
	var out: Array = []
	var wall := _style("wall")
	var windows: Dictionary = _desc["windows"]
	for c in _desc["cols"]:
		var kind := "corner" if c == 0 else ("ne_window" if c in windows["ne"] else "ne")
		out.append({"c": c, "r": 0, "id": "wall_%s_%s" % [wall, kind], "side": "ne"})
	for r in range(1, _desc["rows"]):
		var door: bool = r == _desc["door"]["row"]
		var kind := "nw_door" if door else ("nw_window" if r in windows["nw"] else "nw")
		out.append({"c": 0, "r": r, "id": "wall_%s_%s" % [wall, kind], "side": "nw", "door": door})
	return out


func _draw_wall(origin: Vector2, w: Dictionary) -> void:
	var s := _sprite(w["id"])
	var p := _p(origin, w["c"], w["r"])
	var door: bool = w.get("door", false)
	if not s.is_empty():
		draw_texture(s["tex"], (p - s["anchor"]).round())
		if door:
			var leaf := _sprite("door_panel_nw_f%d" % (3 if _hover_door or door_ajar else 1))
			if not leaf.is_empty():
				draw_texture(leaf["tex"], (p - leaf["anchor"]).round())
		return
	var up := Vector2(0, WALL_H * _k)
	var east := p + Vector2(16, 8) * _k
	var west := p + Vector2(-16, 8) * _k
	if w["side"] == "ne":
		draw_colored_polygon(PackedVector2Array([p, east, east - up, p - up]), Color("8d8aa3"))
	if w["side"] == "nw" or w["id"].ends_with("corner"):
		draw_colored_polygon(PackedVector2Array([p, west, west - up, p - up]), Color("77748c"))
	if door:
		var a := p.lerp(west, 0.2)
		var b := p.lerp(west, 0.8)
		var h := Vector2(0, 38 * _k)
		var col := Color("a8744a") if _hover_door or door_ajar else Color("7a5238")
		draw_colored_polygon(PackedVector2Array([a, b, b - h, a - h]), col)


func _draw_rug(origin: Vector2, rug: Array) -> void:
	var s := _sprite(rug[0])
	if not s.is_empty():
		draw_texture(s["tex"], (_p(origin, rug[1], rug[2]) - s["anchor"]).round())
		return
	_flat_box(origin, rug[1], rug[2], rug[3], rug[4], 0, rug[5])


func _draw_furniture(origin: Vector2, f: Array) -> void:
	if _desc == HOME and f[0] == "plant_large":
		home.draw_plant(f)
		return
	var s := _sprite(_furn_id(f))
	if s.is_empty():
		if f.size() > 3:
			_flat_box(origin, f[1], f[2], f[3], f[4], f[5], f[6])
		return
	var at: Vector2 = (_p(origin, f[1], f[2]) - s["anchor"]).round()
	draw_texture(s["tex"], at)
	if _desc == HOME:
		home.furn(str(f[0]), s["tex"], at)
	if _desc == HOME and str(f[0]).begins_with("clock_"):
		home.register_sprite("clock", s["tex"], at)


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


func _feet(origin: Vector2, fig: Dictionary) -> Vector2:
	return _p(origin, fig["col"], fig["row"]) + Vector2(0, 8 * _k)


func _draw_person_shadow(origin: Vector2, fig: Dictionary) -> void:
	if _person_shadow == null:
		_person_shadow = _load_texture(_person_dir() + "Effects/%dx/shadow.png" % _k)
	if _person_shadow != null:
		var a: float = fig.get("alpha", 1.0)
		draw_texture(
			_person_shadow,
			(_feet(origin, fig) - Vector2(16, 8) * _k).round(),
			Color(1, 1, 1, SHADOW.a * a)
		)


func _draw_person(origin: Vector2, fig: Dictionary) -> void:
	var name: String = fig["sheet"]
	var sheet := _load_texture(_person_dir() + "Sheets/%dx/%s/%s_idle.png" % [_k, name, name])
	var feet := _feet(origin, fig) - Vector2(0, fig.get("lift", 0) * _k)
	var alpha: float = fig.get("alpha", 1.0)
	if sheet == null:
		var body: Color = fig.get("tint", Color("6f8fb0"))
		body.a = alpha
		draw_circle(feet - Vector2(0, 14 * _k), 8 * _k, Color(Color("e0b07a"), alpha))
		draw_rect(Rect2(feet - Vector2(6 * _k, 12 * _k), Vector2(12 * _k, 12 * _k)), body)
		return
	var cell := 64 * _k
	var frame: int = _frame if fig.get("anim", false) else 0
	draw_texture_rect_region(
		sheet,
		Rect2((feet - Vector2(32, 46) * _k).round(), Vector2(cell, cell)),
		Rect2(frame * cell, fig.get("dir", 0) * cell, cell, cell),
		Color(1, 1, 1, alpha)
	)


func _tone(status: String) -> Color:
	match status:
		"working":
			return Color("8fd18a")
		"waiting":
			return MARK_COLOR
		"idle":
			return Color("f1e9dc")
	return Color("8a8294")


func _draw_tags(origin: Vector2, fig: Dictionary) -> void:
	if not fig.has("name"):
		return
	var font := ThemeDB.fallback_font
	var feet := _feet(origin, fig)
	var fs := 12
	var text: String = fig["name"]
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var at := feet + Vector2(0, 8 * _k)
	draw_rect(Rect2(at + Vector2(-w / 2.0 - 4, -12), Vector2(w + 8, 17)), Color(INK, 0.8))
	draw_string(
		font,
		at + Vector2(-w / 2.0, 1),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		fs,
		_tone(fig["status"])
	)
	if fig["status"] == "waiting":
		var m := feet - Vector2(0, 50 * _k)
		draw_circle(m, 12, INK)
		draw_circle(m, 10, MARK_COLOR)
		var bang := font.get_string_size("!", HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		draw_string(font, m + Vector2(-bang / 2.0, 6), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, INK)


func _draw_door_label(origin: Vector2) -> void:
	if not office_door:
		return
	var door: Dictionary = _desc["door"]
	var font := ThemeDB.fallback_font
	var fs := 13
	var text: String = door["label"]
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var at := _p(origin, 0, door["row"]) + Vector2(-8 * _k, (4 - WALL_H) * _k - 8)
	at.x = clampf(at.x, w / 2.0 + 10, size.x - w / 2.0 - 10)
	draw_rect(Rect2(at + Vector2(-w / 2.0 - 5, -13), Vector2(w + 10, 19)), Color(INK, 0.85))
	draw_string(
		font,
		at + Vector2(-w / 2.0, 1),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		fs,
		MARK_COLOR if _hover_door else Color("f1e9dc")
	)


func _draw_caption() -> void:
	if _caption == "":
		return
	var font := ThemeDB.fallback_font
	var fs := 15
	var w := font.get_string_size(_caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var at := Vector2(size.x / 2.0, 30)
	draw_rect(Rect2(at + Vector2(-w / 2.0 - 10, -18), Vector2(w + 20, 28)), Color(INK, 0.85))
	draw_string(
		font, at + Vector2(-w / 2.0, 2), _caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, MARK_COLOR
	)
