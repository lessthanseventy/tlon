extends VBoxContainer

# "who is this?": the small paper card a pet's right click opens. It writes the same settings the
# settings screen does (the pet's animal, its name) and the room follows at once.

const Paper := preload("res://paper.gd")
const Pets := preload("res://pets.gd")
const Settings := preload("res://settings.gd")
const ROLES := {
	"nina": {"kind": "pet1", "name": "cat", "way": "pet1_personality"},
	"argos": {"kind": "pet2", "name": "dog", "way": "pet2_personality"},
}
const TILE := Vector2(54, 56)

var settings
var home
var role := "nina"

var _name: LineEdit
var _way: OptionButton
var _kind_label: Label
var _lines: Label
var _tiles := {}
var _loading := false
var _t := 0.0


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
	add_theme_constant_override("separation", 7)
	var col: VBoxContainer = self
	col.add_child(Paper.heading("who is this?", 15, Paper.INK))
	var r := Paper.row(col)
	r.add_child(Paper.label("name", 14, Paper.QUIET))
	_name = Paper.edit("", r)
	_name.text_submitted.connect(func(t: String) -> void: _put("name", t.strip_edges()))
	_name.focus_exited.connect(func() -> void: _put("name", _name.text.strip_edges()))
	r = Paper.row(col)
	r.add_child(Paper.label("way", 14, Paper.QUIET))
	_way = OptionButton.new()
	for p in Pets.PERSONALITIES:
		_way.add_item(p)
	Paper.skin(_way)
	_way.item_selected.connect(func(i: int) -> void: _put("way", Pets.PERSONALITIES[i]))
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
	_kind_label = Paper.label("", 14, Paper.INK)
	col.add_child(_kind_label)
	r = Paper.row(col)
	Paper.chip("pat", r, _pat, false)
	_lines = Paper.label("", 13, Paper.QUIET)
	_lines.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lines.custom_minimum_size.x = 40
	col.add_child(_lines)


func open(id: String) -> void:
	role = id
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
	visible = false




func _process(dt: float) -> void:
	if not visible:
		return
	_t += dt
	for tile in _tiles.values():
		tile.t = _t
		tile.queue_redraw()


func _kind() -> String:
	return Pets.kind_of(settings.value(ROLES[role]["kind"]), role)


func _say(kind: String) -> void:
	_kind_label.text = "no pet" if kind == Pets.NONE else Pets.KINDS[kind]["label"]


func _refresh() -> void:
	for kind in _tiles:
		_tiles[kind].chosen = kind == _kind()
	_say(_kind())
	_way.select(Pets.PERSONALITIES.find(Pets.persona_of(settings.value(ROLES[role]["way"]), role)))
	var who := "cat" if role == "nina" else "dog"
	var said: Array = home.chat.messages.filter(func(m: Dictionary) -> bool: return m["who"] == who)
	_lines.text = "\n".join(said.slice(-3).map(func(m: Dictionary) -> String: return "- " + str(m["text"])))


func _put(what: String, v: Variant) -> void:
	if _loading:
		return
	settings.put(ROLES[role][what], v)
	_refresh()


func _pat() -> void:
	home.pets.pat(home.pets.critter(role), "pet")
