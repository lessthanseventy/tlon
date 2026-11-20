extends Control

signal pressed_empty
signal pet_menu(id: String)

const WALL_H := 48
const FRAMES := 4
const SHADOW := Color(1, 1, 1, 0.35)

# the home's furniture, floor and wall come from `home.layout`
const HOME := {
	"cols": Pets.COLS,
	"rows": Pets.ROWS,
	"windows": {"ne": [4], "nw": []},
	"door": {"row": 7},
}
const HomeScript := preload("res://home.gd")
const Pets := preload("res://pets.gd")
const Packs := preload("res://packs.gd")
const Guests := preload("res://guests.gd")

var art_dir := ""
var art_found := false
var home := HomeScript.new()
var decorate: Control
var guests := Guests.new()

var _index := {}
var _textures := {}
var _t := 0.0
var _person_shadow: Texture2D
var _k := 2
var _origin := Vector2.ZERO
var door_ajar := false


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	clip_contents = true
	_load_index()
	home.setup(self, art_dir, OS.get_cmdline_user_args())
	mouse_exited.connect(home.leave)


func show_home() -> void:
	queue_redraw()


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
	home.process(delta)
	guests.update(home)
	queue_redraw()


func _load_texture(path: String) -> Texture2D:
	if _textures.has(path):
		return _textures[path]
	var tex: Texture2D = null
	var image := Image.load_from_file(path) if FileAccess.file_exists(path) else null
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


# How much the room's own canvas is magnified to fill `area`: its art comes at 2x and 3x, and a
# whole step above (2x of either) is crisp; in an area too small for the 2x art it shrinks a little
func fit_scale(area: Vector2) -> float:
	var span: int = HOME["cols"] + HOME["rows"]
	for steps in [[3, 2.0], [2, 2.0], [3, 1.0]]:
		var k: int = steps[0]
		var s: float = steps[1]
		var need := Vector2(span * 16 * k + 16, (span * 8 + WALL_H) * k + 16) * s
		if area.x >= need.x and area.y >= need.y:
			return s
	var base := Vector2(span * 16 * 2 + 16, (span * 8 + WALL_H) * 2 + 16)
	return clampf(floorf(minf(area.x / base.x, area.y / base.y) * 20.0) / 20.0, 0.5, 1.0)


func _pick_scale() -> int:
	var span: int = HOME["cols"] + HOME["rows"]
	if size.x >= span * 16 * 3 + 16 and size.y >= (span * 8 + WALL_H) * 3 + 16:
		return 3
	if size.x >= span * 16 * 2 + 16 and size.y >= (span * 8 + WALL_H) * 2 + 16:
		return 2
	return 1


func _gui_input(event: InputEvent) -> void:
	if decorate != null and decorate.active:
		decorate.room_input(event)
		return
	if event is InputEventMouseMotion:
		mouse_default_cursor_shape = (
			Control.CURSOR_POINTING_HAND if home.hover(event.position) else Control.CURSOR_ARROW
		)
	elif (
		event is InputEventMouseButton
		and event.pressed
		and event.button_index == MOUSE_BUTTON_RIGHT
	):
		var pet: String = home.pet_at(event.position)
		if pet != "":
			pet_menu.emit(pet)
	elif (
		event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	):
		if home.click(event.position):
			return
		pressed_empty.emit()


func _draw() -> void:
	_k = _pick_scale()
	var cols: int = HOME["cols"]
	var rows: int = HOME["rows"]
	var floor_style := _style("floor")
	var plan := home.layout.rows()
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
	home.draw_floor()

	var items: Array = []
	items.append_array(home.items())
	items.append_array(guests.items(home))
	for w in _walls():
		items.append({"key": w["c"] + w["r"], "pri": 0, "wall": w})
	for d in plan.get("decor", []):
		items.append({"key": d[1] + d[2], "pri": 0.3, "furn": d})
	for f in plan["furniture"]:
		var pri := 1.8 if f[0] == "office_chair_ne" else 1.0
		items.append(
			{"key": f[1] + f[3] - 1 + f[2] + f[4] - 1, "pri": pri, "row": f[2] + f[4], "furn": f}
		)
		var s := _sprite(_furn_id(f))
		if not s.is_empty() and s["shadow"] != "":
			var sh := _sprite(s["shadow"])
			if not sh.is_empty():
				draw_texture(sh["tex"], (_p(origin, f[1], f[2]) - sh["anchor"]).round(), SHADOW)
	items.sort_custom(_before)

	for it in items:
		if it.has("wall"):
			_draw_wall(origin, it["wall"])
		elif it.has("fn"):
			it["fn"].call()
		else:
			_draw_furniture(origin, it["furn"])
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
	return home.layout.wall if key == "wall" else home.layout.floor_style


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
	var windows: Dictionary = HOME["windows"]
	for c in HOME["cols"]:
		var kind := "corner" if c == 0 else ("ne_window" if c in windows["ne"] else "ne")
		out.append({"c": c, "r": 0, "id": "wall_%s_%s" % [wall, kind], "side": "ne"})
	for r in range(1, HOME["rows"]):
		var door: bool = r == HOME["door"]["row"]
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
			var leaf := _sprite("door_panel_nw_f%d" % (3 if door_ajar else 1))
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
		var col := Color("a8744a") if door_ajar else Color("7a5238")
		draw_colored_polygon(PackedVector2Array([a, b, b - h, a - h]), col)


func _draw_rug(origin: Vector2, rug: Array) -> void:
	var s := _sprite(rug[0])
	if not s.is_empty():
		draw_texture(s["tex"], (_p(origin, rug[1], rug[2]) - s["anchor"]).round())
		return
	_flat_box(origin, rug[1], rug[2], rug[3], rug[4], 0, rug[5])


func _draw_furniture(origin: Vector2, f: Array) -> void:
	if f[0] == "plant_large":
		home.draw_plant(f)
		return
	var s := _sprite(_furn_id(f))
	if s.is_empty():
		if f.size() > 3:
			_flat_box(origin, f[1], f[2], f[3], f[4], f[5], f[6])
		return
	var at: Vector2 = (_p(origin, f[1], f[2]) - s["anchor"]).round()
	draw_texture(s["tex"], at)
	home.furn(str(f[0]), s["tex"], at)
	if str(f[0]).begins_with("clock_"):
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


func _door_hit(pos: Vector2) -> bool:
	var p := _p(_origin, 0, HOME["door"]["row"])
	var up := Vector2(0, WALL_H * _k)
	var west := p + Vector2(-16, 8) * _k
	return Geometry2D.is_point_in_polygon(pos, PackedVector2Array([p, west, west - up, p - up]))
