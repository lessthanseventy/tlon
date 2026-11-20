extends VBoxContainer

# A pet's view: who it is, what it is doing now, a few things to do with it and its things, and
# what it said lately. "change who this is" opens the controls that write the same settings the
# settings screen does (the pet's animal, its name, its way) and the room follows at once.

const Paper := preload("res://paper.gd")
const Fonts := preload("res://fonts.gd")
const Chooser := preload("res://chooser.gd")
const Pets := preload("res://pets.gd")
const Settings := preload("res://settings.gd")
const Blocks := preload("res://blocks.gd")
const Views := preload("res://views.gd")
const PetNow := preload("res://pet_now.gd")
const PetThings := preload("res://pet_things.gd")
const ROLES := {
	"nina": {"kind": "pet1", "name": "cat", "way": "pet1_personality"},
	"argos": {"kind": "pet2", "name": "dog", "way": "pet2_personality"},
}
const TILE := Vector2(54, 56)
const SHOWN := 6
const LATELY := 3
const FOOD := ["bowls", "carrot", "trough", "apples", "salt", "hay"]
const PLAY := ["balls", "bone", "rope", "fish", "post", "log", "tower"]
const PLAY_SPOT := {"tower": ["tower_bat"]}
const BEDS := ["bed_round", "bed_cushion", "hutch", "den", "kennel", "basket", "blanket"]
const CHASERS := ["cat", "dog", "fox", "wolf"]

var settings
var home
var role := "nina"
var editing := false

var _name: LineEdit
var _way
var _kind_label: Label
var _tiles := {}
var _loading := false
var _t := 0.0
var _tick := 0.0
var _page: VBoxContainer
var _edit: VBoxContainer
var _portrait: Portrait
var _title: Label
var _sub: Label
var _alive: VBoxContainer
var _now: Label
var _acts: VBoxContainer
var _acts_sig := ""
var _things: VBoxContainer
var _things_sig := ""
var _more := false
var _lately: VBoxContainer
var _lately_sig := ""
var _shown := []


# the pet's idle frame, drawn large on the paper
class Portrait:
	extends Control
	var pets
	var kind := ""
	var t := 0.0

	func _init(the_pets) -> void:
		pets = the_pets
		custom_minimum_size = Vector2(108, 104)
		clip_contents = true

	func _draw() -> void:
		if kind != "":
			pets.draw_preview(self, kind, t, Vector2(size.x / 2.0, size.y - 6), 3)


# one animal, drawn idling on a paper tile; the chosen one is gold
class Tile:
	extends Control
	signal picked
	var pets
	var kind := ""
	var chosen := false
	var t := 0.0

	func _init(the_pets, the_kind: String) -> void:
		pets = the_pets
		kind = the_kind
		custom_minimum_size = TILE
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == 1:
			accept_event()
			picked.emit()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Paper.GOLD if chosen else Color("e4d8bd"))
		draw_rect(Rect2(Vector2.ZERO, size), Paper.INK, false, 2.0)
		if kind == Pets.NONE:
			draw_string(
				ThemeDB.fallback_font,
				Vector2(0, 33),
				"none",
				HORIZONTAL_ALIGNMENT_CENTER,
				size.x,
				14,
				Paper.INK
			)
		else:
			pets.draw_preview(self, kind, t, Vector2(size.x / 2.0, 50), 1)



func setup(the_settings, the_home) -> void:
	settings = the_settings
	home = the_home


func _ready() -> void:
	visible = false
	_page = VBoxContainer.new()
	_page.add_theme_constant_override("separation", 8)
	add_child(_page)
	_edit = VBoxContainer.new()
	_edit.add_theme_constant_override("separation", 7)
	_edit.visible = false
	add_child(_edit)
	_build_page()
	_build_edit()


func _build_page() -> void:
	var head := Paper.row(_page)
	head.add_theme_constant_override("separation", 10)
	_portrait = Portrait.new(home.pets)
	head.add_child(_portrait)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	names.add_theme_constant_override("separation", 2)
	head.add_child(names)
	_title = Paper.label("", Fonts.BODY, Paper.INK)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.custom_minimum_size.x = 40
	names.add_child(_title)
	_sub = Blocks.wrapped("", Fonts.SMALL, Paper.QUIET)
	names.add_child(_sub)
	_alive = VBoxContainer.new()
	_alive.add_theme_constant_override("separation", 8)
	_page.add_child(_alive)
	var now := VBoxContainer.new()
	now.add_theme_constant_override("separation", 0)
	_alive.add_child(now)
	now.add_child(Paper.label("Right now", Fonts.LABEL, Paper.QUIET))
	_now = Blocks.wrapped("", Fonts.BODY, Paper.INK)
	now.add_child(_now)
	_acts = VBoxContainer.new()
	_alive.add_child(_acts)
	_things = VBoxContainer.new()
	_things.add_theme_constant_override("separation", 2)
	_alive.add_child(_things)
	_lately = VBoxContainer.new()
	_lately.add_theme_constant_override("separation", 2)
	_alive.add_child(_lately)
	var r := Paper.row(_page)
	Paper.chip("change who this is", r, _open_edit, false)


func _build_edit() -> void:
	var col := _edit
	var r := Paper.row(col)
	Paper.chip("Back", r, back, false, "quiet")
	col.add_child(Paper.section("Who is this?"))
	r = Paper.row(col)
	r.add_child(Paper.label("name", Fonts.SMALL, Paper.QUIET))
	_name = Paper.edit("", r)
	_name.text_submitted.connect(func(t: String) -> void: _put("name", t.strip_edges()))
	_name.focus_exited.connect(func() -> void: _put("name", _name.text.strip_edges()))
	r = Paper.row(col)
	r.add_child(Paper.label("way", Fonts.SMALL, Paper.QUIET))
	_way = Chooser.new()
	for p in Pets.PERSONALITIES:
		_way.add_item(p)
	_way.item_selected.connect(func(i: int) -> void: _put("way", Pets.PERSONALITIES[i]))
	_way.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(_way)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	col.add_child(grid)
	for kind in Pets.KINDS.keys() + [Pets.NONE]:
		var tile := Tile.new(home.pets, kind)
		tile.picked.connect(func() -> void: _put("kind", kind))
		tile.mouse_entered.connect(func() -> void: _say(kind))
		tile.mouse_exited.connect(func() -> void: _say(_kind()))
		grid.add_child(tile)
		_tiles[kind] = tile
	_kind_label = Paper.label("", Fonts.BODY, Paper.INK)
	col.add_child(_kind_label)


func open(id: String) -> void:
	role = id
	editing = false
	_page.visible = true
	_edit.visible = false
	_more = false
	_loading = true
	_name.placeholder_text = Settings.CAT if id == "nina" else Settings.DOG
	_name.text = settings.data.get(ROLES[id]["name"], "")
	_loading = false
	_refresh()
	visible = true


func close() -> void:
	if not visible:
		return
	if get_viewport().gui_get_focus_owner() != null:
		get_viewport().gui_get_focus_owner().release_focus()
	editing = false
	visible = false


# true when it was the controls that were up, now put away for the pet itself
func back() -> bool:
	if not editing:
		return false
	if get_viewport().gui_get_focus_owner() != null:
		get_viewport().gui_get_focus_owner().release_focus()
	editing = false
	_page.visible = true
	_edit.visible = false
	_refresh()
	return true


func _open_edit() -> void:
	editing = true
	_page.visible = false
	_edit.visible = true


func _process(dt: float) -> void:
	if not visible:
		return
	_t += dt
	if editing:
		for tile in _tiles.values():
			tile.t = _t
			tile.queue_redraw()
		return
	_portrait.t = _t
	_portrait.queue_redraw()
	_tick -= dt
	if _tick <= 0.0:
		_tick = 0.25
		var shown := [_kind(), settings.value(ROLES[role]["way"]), Settings.cat, Settings.dog]
		if shown != _shown:
			_shown = shown
			_refresh()
		else:
			_live()


func _kind() -> String:
	return Pets.kind_of(settings.value(ROLES[role]["kind"]), role)


func _say(kind: String) -> void:
	_kind_label.text = "no pet" if kind == Pets.NONE else Pets.KINDS[kind]["label"]


func _refresh() -> void:
	var kind := _kind()
	var way := Pets.persona_of(settings.value(ROLES[role]["way"]), role)
	for k in _tiles:
		_tiles[k].chosen = k == kind
	_say(kind)
	_way.select(Pets.PERSONALITIES.find(way))
	_title.text = Settings.cat if role == "nina" else Settings.dog
	_portrait.visible = kind != Pets.NONE
	_portrait.kind = "" if kind == Pets.NONE else kind
	_sub.text = "no pet here" if kind == Pets.NONE else "%s · %s" % [Pets.KINDS[kind]["label"], way]
	_live()


func _put(what: String, v: Variant) -> void:
	if _loading:
		return
	settings.put(ROLES[role][what], v)
	_refresh()


# the parts that follow the pet: what it does, what can be done, its things, its lines
func _live() -> void:
	_alive.visible = _kind() != Pets.NONE
	if not _alive.visible:
		return
	var c = home.pets.critter(role)
	_now.text = PetNow.phrase(PetNow.state_of(c, home.antics.act))
	var acts := _actions(c)
	var sig := JSON.stringify(acts)
	if sig != _acts_sig:
		_acts_sig = sig
		_clear(_acts)
		Blocks.build(_acts, [{"t": "buttons", "items": acts}], _do)
	var rows := _rows(c)
	sig = JSON.stringify([rows.map(func(r: Dictionary) -> String: return r["key"]), _more])
	if sig != _things_sig:
		_things_sig = sig
		_fill_things(rows, c)
	_fill_lately()


func _clear(box: Control) -> void:
	for n in box.get_children():
		box.remove_child(n)
		n.queue_free()


func _fill_things(rows: Array, c) -> void:
	_clear(_things)
	if rows.is_empty():
		return
	Views.heading(_things, "Its things")
	for r in rows.slice(0, rows.size() if _more else SHOWN):
		var row := Blocks.Row.new(r["name"], "", false, false, true)
		row.pressed.connect(func() -> void: _go(c, r["spot"], r["mode"]))
		_things.add_child(row)
	if rows.size() > SHOWN:
		var label := "less" if _more else "%d more..." % (rows.size() - SHOWN)
		var more := Blocks.Row.new(label, "", false, true)
		more.pressed.connect(
			func() -> void:
				_more = not _more
				_things_sig = ""
		)
		_things.add_child(more)


func _fill_lately() -> void:
	var who := "cat" if role == "nina" else "dog"
	var said: Array = home.chat.messages.filter(func(m: Dictionary) -> bool: return m["who"] == who)
	var lines: Array = said.slice(-LATELY).map(
		func(m: Dictionary) -> String: return "- " + str(m["text"])
	)
	var sig := "\n".join(lines)
	if sig == _lately_sig:
		return
	_lately_sig = sig
	_clear(_lately)
	if lines.is_empty():
		return
	Views.heading(_lately, "Lately")
	for l in lines:
		_lately.add_child(Views.quiet(l, 13))


func _antic_of(c) -> bool:
	var a: Dictionary = home.antics.act
	return not a.is_empty() and c.id in [a["id"], a["pid"]]


# a scene of the room's has the pet: nothing but a pat then
func _busy(c) -> bool:
	return c.hold and not _antic_of(c)


func _actions(c) -> Array:
	if c.away:
		return []
	var out: Array = [{"label": "pat", "act": "pat"}]
	if _busy(c):
		return out
	if _call_spot(c) != "":
		out.append({"label": "call over", "act": "call"})
	if _food(c) != "":
		out.append({"label": "treat", "act": "treat"})
	if not _plays(c).is_empty():
		out.append({"label": "play", "act": "play"})
	if _bed(c) != "":
		out.append({"label": "off to bed", "act": "bed"})
	return out


func _do(what: String) -> void:
	var c = home.pets.critter(role)
	if c.away:
		return
	if what == "pat":
		home.pets.pat(c, "pet")
		return
	if _busy(c):
		return
	match what:
		"call":
			_go(c, _call_spot(c), "sit")
		"treat":
			_go(c, _food(c), "sit")
		"play":
			var plays := _plays(c)
			var pick: String = plays[home.pets.rng.randi() % plays.size()]
			if pick == "yarn":
				_free(c)
				home.pets.chase(c, home.pets._toy_of("yarn"), 3)
			else:
				_go(c, pick, "sit")
		"bed":
			_go(c, _bed(c), "sleep")


# lets go of what the pet was in the middle of, then sends it to a spot
func _go(c, spot: String, mode: String) -> void:
	if spot == "" or c.away or _busy(c):
		return
	_free(c)
	home.pets.go(c, spot, mode, 60.0 if mode == "sleep" else 12.0)


func _free(c) -> void:
	if _antic_of(c):
		home.antics._end(c, false)
	if c.mode in ["bat", "stalk", "swat"]:
		c.bat_t = -1.0
		c.bat_toy = {}
		home.pets._settle(c, "idle")


func _reachable(c, spot: String) -> bool:
	if not home.pets.spots.has(spot):
		return false
	var cell: Vector2i = home.pets.spots[spot]["cell"]
	var from: Vector2i = home.pets._cell_of(c.pos)
	var free: bool = not home.pets._blocked(cell) and not home.pets.route(from, cell).is_empty()
	return cell == from or free


# where a thing takes the pet, or "" when it is not out, not for this animal or out of reach
func _spot(c, key: String, spots: Array = []) -> String:
	if not PetThings.fits(key, [c.species]) or not home.petlife.has(key):
		return ""
	for spot in spots if not spots.is_empty() else PetNow.spots_of(key):
		if key == "hay" and (spot == "hay_top") != (c.species == "chicken"):
			continue
		if _reachable(c, spot):
			return spot
	return ""


func _rows(c) -> Array:
	var out: Array = []
	var seen := {}
	for p in home.layout.pet_pieces():
		var key := PetThings.key_of(p)
		var spot := _spot(c, key) if not seen.has(key) else ""
		seen[key] = true
		if spot != "":
			out.append(
				{"key": key, "name": PetThings.THINGS[key]["name"], "spot": spot, "mode": _mode(key)}
			)
	return out


func _mode(key: String) -> String:
	return "sleep" if key in BEDS else "sit"


func _call_spot(c) -> String:
	return home.antics.next_to(home.pets._cell_of(home.pets.critter("person").pos), c, 0)


func _food(c) -> String:
	for key in FOOD:
		var spot := _spot(c, key)
		if spot != "":
			return spot
	return ""


func _plays(c) -> Array:
	var out: Array = []
	for key in PLAY:
		var spot := _spot(c, key, PLAY_SPOT.get(key, []))
		if spot != "":
			out.append(spot)
	if c.species in CHASERS and not home.pets._toy_of("yarn").is_empty():
		out.append("yarn")
	return out


func _bed(c) -> String:
	var spot: String = home.petlife.night_spot(c)
	return spot if spot != "" and _reachable(c, spot) else ""
