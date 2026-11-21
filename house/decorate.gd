extends Control

# Decorate mode: the catalogue panel where the side panel is, and the pointer's work on the room.
signal done

const Pets := preload("res://pets.gd")
const PetThings := preload("res://pet_things.gd")
const Chores := preload("res://chores.gd")
const BG := Color("f3ead6")
const INK := Color("2a2530")
const QUIET := Color("6f6577")
const ACCENT := Color("c98a2e")
const WARM := Color("b0482a")
const PAD := 14.0
const TOP := 48.0
const FOOT := 88.0
const CHIP_H := 24.0
const CELL_H := 46.0
const ICON := 36.0
const FONT := 12

var active := false
var room: Control
var home
var sel := ""
var face := ""
var tab := "home"
var held: Variant = null
var pin: Variant = null
var everyone := false

var _hits: Array = []
var _scroll := 0.0
var _content := 0.0
var _mouse := Vector2.ZERO
var _message := ""
var _message_left := 0.0


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	clip_contents = true
	visible = false


func enter() -> void:
	active = true
	visible = true
	sel = ""
	held = null
	_scroll = 0.0
	queue_redraw()


func leave() -> void:
	active = false
	visible = false
	sel = ""
	held = null


# a piece to place, as `--pick NAME[:FACE]`
func pick(spec: String) -> void:
	var parts := spec.split(":")
	var e: Dictionary = home.layout.entry(parts[0])
	if e.is_empty():
		return
	sel = e["key"]
	tab = e["tab"]
	face = parts[1] if parts.size() > 1 and parts[1] in e["faces"] else _first_face(e)
	queue_redraw()


func _first_face(e: Dictionary) -> String:
	return e["faces"][0] if not e["faces"].is_empty() else ""


func _process(dt: float) -> void:
	if _message_left > 0.0:
		_message_left -= dt
		queue_redraw()


func _nope(text: String) -> void:
	_say(text)
	home.sound.request("nope")


func _say(text: String) -> void:
	_message = text
	_message_left = 2.5
	queue_redraw()


func _draw() -> void:
	if home == null:
		return
	_hits.clear()
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	_content = _sections(TOP + 6.0 - _scroll) + _scroll
	draw_rect(Rect2(0, 0, size.x, TOP), BG)
	draw_rect(Rect2(0, size.y - FOOT, size.x, FOOT), BG)
	var font := ThemeDB.fallback_font
	_tabs()
	var lines := [
		"click a piece to place it or move one", "R turns - X or right click removes", "Esc done"
	]
	for i in lines.size():
		var at := Vector2(PAD, size.y - FOOT + 38 + 16 * i)
		draw_string(font, at, lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT, QUIET)
	var status := _status()
	var tone := WARM if _message_left > 0.0 else INK
	draw_string(
		font, Vector2(PAD, size.y - FOOT + 20), status, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, tone
	)


func _status() -> String:
	if _message_left > 0.0:
		return _message
	if sel == "":
		return ""
	var name: String = home.layout.entry(sel)["name"]
	return "%s (%s)" % [name, face] if face != "" else name


func _sections(y: float) -> float:
	var layout = home.layout
	var walls: Array = layout.walls_of(tab)
	var floors: Array = layout.floors_of(tab)
	if not walls.is_empty():
		y = _head("walls", y)
		y = _chips("wall", walls, layout.wall, y)
	if not floors.is_empty():
		y = _head("floors", y)
		y = _chips("floor", floors, layout.floor_style, y)
	if tab == "home":
		y = _chips("", ["reset"], "", y + 4.0)
	if tab == "pets":
		y = _chips("", ["all animals"], "all animals" if everyone else "", y + 4.0)
	var cw := (size.x - 2.0 * PAD) / 2.0
	var group := ""
	var col := 0
	for e in layout.catalogue:
		if e["tab"] != tab or (tab == "pets" and not _listed(e)):
			continue
		if e["group"] != group:
			if col == 1:
				y += CELL_H
				col = 0
			group = e["group"]
			y = _head(group, y)
		_entry(e, Rect2(PAD + col * cw, y, cw, CELL_H))
		col += 1
		if col == 2:
			col = 0
			y += CELL_H
	return y + (CELL_H if col == 1 else 0.0) + 16.0


func _tabs() -> void:
	var font := ThemeDB.fallback_font
	var x := PAD
	for t in home.layout.tabs:
		var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT).x + 12.0
		var r := Rect2(x, 10.0, w, CHIP_H)
		draw_rect(r, Color(ACCENT, 0.35) if t == tab else Color(0, 0, 0, 0.08))
		draw_string(font, r.position + Vector2(6, 16), t, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT, INK)
		_hits.append({"rect": r, "act": "tab:" + t})
		x += w + 6.0


func _head(text: String, y: float) -> float:
	draw_string(
		ThemeDB.fallback_font, Vector2(PAD, y + 22), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ACCENT
	)
	return y + 30.0


func _chips(kind: String, names: Array, current: String, y: float) -> float:
	var font := ThemeDB.fallback_font
	var x := PAD
	for n in names:
		var label: String = n.substr(n.find(".") + 1)
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT).x + 16.0
		if x + w > size.x - PAD:
			x = PAD
			y += CHIP_H + 6.0
		var r := Rect2(x, y, w, CHIP_H)
		draw_rect(r, Color(ACCENT, 0.35) if n == current else Color(0, 0, 0, 0.08))
		draw_string(font, r.position + Vector2(8, 16), label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT, INK)
		_hit(r, kind + ":" + n if kind != "" else n)
		x += w + 6.0
	return y + CHIP_H + 8.0


func _listed(e: Dictionary) -> bool:
	return home.petlife.listed(PetThings.key_of({"p": e["key"]}), everyone)


func _pet_icon(e: Dictionary, r: Rect2) -> void:
	var key := PetThings.key_of({"p": e["key"]})
	var span: float = PetThings.THINGS[key]["h"] + 16.0
	var k := minf(0.9, 34.0 / span)
	var origin := Vector2(r.position.x + 5 + ICON / 2.0, r.position.y + 5 + (ICON - span * k) / 2.0)
	origin.y += (span - 16.0) * k
	PetThings.draw_all(PetThings.Pen.new(self, origin, k), key, {"level": {"food": 1.0, "water": 1.0}})


func _entry(e: Dictionary, r: Rect2) -> void:
	if e["key"] == sel:
		draw_rect(r.grow(-2), Color(ACCENT, 0.22))
	var id: String = home.layout.sprite_id({"p": e["key"], "f": _first_face(e)})
	if e["key"] == PetThings.PREFIX + "hay":
		id = home.petlife.HAY_PIECE
	elif e["tab"] == "pets":
		_pet_icon(e, r)
	elif e["key"] == Chores.PIECE:
		var origin := Vector2(r.position.x + 5 + ICON / 2.0, r.position.y + 5 + ICON / 2.0 + 14.0)
		Chores.basket(PetThings.Pen.new(self, origin, 1.0), "fine")
	var tex: Texture2D = room.icon(id)
	if tex != null:
		var t := tex.get_size()
		var s := minf(ICON / t.x, ICON / t.y)
		s = floorf(s) if s >= 1.0 else s
		var box := t * s
		draw_texture_rect(
			tex, Rect2(r.position + Vector2(5, 5) + (Vector2(ICON, ICON) - box) / 2.0, box), false
		)
	draw_string(
		ThemeDB.fallback_font,
		r.position + Vector2(ICON + 12, CELL_H / 2.0 + 4),
		e["name"],
		HORIZONTAL_ALIGNMENT_LEFT,
		r.size.x - ICON - 14,
		FONT,
		INK
	)
	_hit(r, "pick:" + e["key"])


func _hit(r: Rect2, act: String) -> void:
	if r.end.y > TOP and r.position.y < size.y - FOOT:
		_hits.append({"rect": r, "act": act})


func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			_scrolled(-48.0)
		MOUSE_BUTTON_WHEEL_DOWN:
			_scrolled(48.0)
		MOUSE_BUTTON_LEFT:
			for h in _hits:
				if h["rect"].has_point(event.position):
					_act(h["act"])
					return


func _scrolled(by: float) -> void:
	_scroll = clampf(_scroll + by, 0.0, maxf(0.0, _content - (size.y - TOP - FOOT)))
	queue_redraw()


func _act(act: String) -> void:
	var layout = home.layout
	var parts := act.split(":")
	match parts[0]:
		"wall", "floor":
			layout.set_style(parts[0], parts[1])
		"tab":
			tab = parts[1]
			_scroll = 0.0
		"all animals":
			everyone = not everyone
			_scroll = 0.0
		"reset":
			layout.reset(home.busy_cells())
			home.apply_layout()
			sel = ""
			held = null
			_say("back to how it was")
		"pick":
			held = null
			sel = parts[1]
			face = _first_face(layout.entry(sel))
			var out: Dictionary = home.petlife.out(sel)
			if not out.is_empty():
				held = out
				face = out["f"]
	queue_redraw()


# the pointer in the room
func room_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse = event.position
	elif event is InputEventMouseButton and event.pressed:
		_mouse = event.position
		if event.button_index == MOUSE_BUTTON_LEFT:
			_click()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_remove_or_drop()
	queue_redraw()


func key(code: int) -> bool:
	match code:
		KEY_R:
			_turn()
		KEY_X, KEY_DELETE:
			_remove_or_drop()
		KEY_ESCAPE:
			done.emit()
		_:
			return false
	return true


func _turn() -> void:
	if sel == "":
		return
	var faces: Array = home.layout.entry(sel)["faces"]
	if faces.size() > 1:
		face = faces[(faces.find(face) + 1) % faces.size()]
		home.sound.request("rotate")
	queue_redraw()


func _click() -> void:
	if sel != "":
		var p := _ghost()
		if held == null and PetThings.is_pet(p):
			p["own"] = not PetThings.fits(PetThings.key_of(p), home.pets.species_here())
		var why: String = home.layout.place(p, held, home.busy_cells())
		if why != "":
			_nope(why)
			return
		home.apply_layout()
		home.sound.request("place")
		if held != null:
			held = null
			sel = ""
		return
	var hit: Variant = _piece_at(_mouse)
	if hit == null:
		if _stays(_mouse):
			_nope("that one stays")
		return
	if hit.has("fixed"):
		_nope("that one stays")
		return
	held = hit
	sel = hit["p"]
	face = hit["f"]


func _remove_or_drop() -> void:
	var hit: Variant = held if held != null else _piece_at(_mouse)
	if hit == null:
		sel = ""
	elif hit.has("fixed"):
		_nope("that one stays")
	else:
		home.layout.remove(hit)
		home.apply_layout()
		home.sound.request("remove")
		held = null
		sel = ""


# the fixed things that are not pieces: window, board, calendar, jar, door, the pets' corner
func _stays(pos: Vector2) -> bool:
	var key: String = home._topmost(pos)
	if key in ["window", "cal", "jar"] or key.begins_with("note:"):
		return true
	return room._door_hit(pos)


func _cell(pos: Vector2) -> Vector2:
	var d: Vector2 = (pos - room._origin) / float(room._k)
	return Vector2(floorf((d.x / 16.0 + d.y / 8.0) / 2.0), floorf((d.y / 8.0 - d.x / 16.0) / 2.0))


func _at() -> Vector2:
	if pin is Vector2i:
		return room._p(room._origin, pin.x + 0.5, pin.y + 0.5)
	return _mouse


func _ghost() -> Dictionary:
	var p := {"p": sel, "f": face, "c": 0, "r": 0}
	var layout = home.layout
	var d: Vector2 = (_at() - room._origin) / float(room._k)
	var k: String = layout.kind(p)
	if k == "wall" or k == "hug":
		if face == "ne":
			p["c"] = clampi(floori(d.x / 16.0), 0, Pets.COLS - 1)
		else:
			p["r"] = clampi(floori(-d.x / 16.0), 0, Pets.ROWS - 1)
		return p
	var fp: Vector2i = layout.footprint(p)
	var x := (d.x / 16.0 + d.y / 8.0) / 2.0
	var y := (d.y / 8.0 - d.x / 16.0) / 2.0
	p["c"] = clampi(floori(x - fp.x / 2.0 + 0.5), 0, Pets.COLS - fp.x)
	p["r"] = clampi(floori(y - fp.y / 2.0 + 0.5), 0, Pets.ROWS - fp.y)
	return p


# the piece under the pointer, front to back, rugs last; nothing for a gap in a sprite
func _piece_at(pos: Vector2) -> Variant:
	var layout = home.layout
	var list: Array = layout.all()
	list.sort_custom(
		func(a, b):
			var ka: int = layout.draw_key(a)
			var kb: int = layout.draw_key(b)
			return ka > kb or (ka == kb and layout.kind(a) != "wall" and layout.kind(b) == "wall")
	)
	for p in list:
		if layout.kind(p) != "rug" and _opaque(p, pos):
			return p
	for p in list:
		if layout.kind(p) == "rug" and layout.rect(p).has_point(Vector2i(_cell(pos))):
			return p
	return null


func _opaque(p: Dictionary, pos: Vector2) -> bool:
	if PetThings.is_pet(p) or Chores.is_basket(p):
		return _over_pet(p, pos)
	var s: Dictionary = room._sprite(room._furn_id([home.layout.sprite_id(p)]))
	if s.is_empty():
		return false
	var at: Vector2 = room._p(room._origin, p["c"], p["r"]) - s["anchor"]
	var tex: Texture2D = s["tex"]
	var local := (pos - at.round()).floor()
	if local.x < 0 or local.y < 0 or local.x >= tex.get_width() or local.y >= tex.get_height():
		return false
	return tex.get_image().get_pixelv(Vector2i(local)).a > 0.1


# the thing's footprint and its height, as one outline
func _over_pet(p: Dictionary, pos: Vector2) -> bool:
	var up := Vector2(0, -maxf(8.0, home.layout.height(p)) * room._k)
	var pts := PackedVector2Array()
	for d in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
		var at: Vector2 = room._p(room._origin, p["c"] + d.x, p["r"] + d.y)
		pts.append(at)
		pts.append(at + up)
	return Geometry2D.is_point_in_polygon(pos, Geometry2D.convex_hull(pts))


func draw_ghost() -> void:
	var layout = home.layout
	if held != null:
		_outline(held, Color(ACCENT, 0.9))
	if sel == "":
		return
	var p := _ghost()
	var ok: bool = layout.check(p, held, home.busy_cells()) == ""
	var tint := Color(1, 1, 1, 0.72) if ok else Color(1, 0.42, 0.42, 0.72)
	var k: String = layout.kind(p)
	if k == "floor" or k == "rug":
		var r: Rect2i = layout.rect(p)
		var pts := _quad(r)
		room.draw_colored_polygon(pts, Color(0.4, 1, 0.5, 0.28) if ok else Color(1, 0.3, 0.3, 0.32))
	if PetThings.is_pet(p) and not home.petlife.hay(p):
		var pen := PetThings.Pen.new(
			room, room._p(room._origin, p["c"], p["r"]), room._k, PetThings.turned(p), tint
		)
		PetThings.draw_all(
			pen, PetThings.key_of(p), {"level": home.petlife.level, "wall": PetThings.perch_wall(p)}
		)
		return
	if Chores.is_basket(p):
		var pen := PetThings.Pen.new(room, room._p(room._origin, p["c"], p["r"]), room._k, false, tint)
		Chores.basket(pen, "fine")
		return
	var s: Dictionary = room._sprite(room._furn_id([layout.sprite_id(p)]))
	if home.petlife.hay(p):
		s = room._sprite(home.petlife.HAY_PIECE)
	if not s.is_empty():
		var at: Vector2 = room._p(room._origin, p["c"], p["r"]) - s["anchor"]
		room.draw_texture(s["tex"], at.round(), tint)


func _quad(r: Rect2i) -> PackedVector2Array:
	var o: Vector2 = room._origin
	return PackedVector2Array(
		[
			room._p(o, r.position.x, r.position.y),
			room._p(o, r.end.x, r.position.y),
			room._p(o, r.end.x, r.end.y),
			room._p(o, r.position.x, r.end.y),
		]
	)


func _outline(p: Dictionary, color: Color) -> void:
	var k: String = home.layout.kind(p)
	if k == "wall":
		return
	var pts := _quad(home.layout.rect(p))
	pts.append(pts[0])
	room.draw_polyline(pts, color, 2.0)
