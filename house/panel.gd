extends PanelContainer

signal ticked(id: int)

const INK := Color("f1e9dc")
const QUIET := Color("a89fb0")
const ACCENT := Color("e8b86d")
const WARM := Color("f0a07a")
const DAYS := ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
const MONTHS := [
	"", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
]

var _box: VBoxContainer
var _status: Label
var _last := ""


func _ready() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("2a2530")
	style.set_content_margin_all(18)
	add_theme_stylebox_override("panel", style)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	add_child(outer)

	var title := _label("the house", 24, ACCENT)
	outer.add_child(title)
	_status = _label("can't reach tlon", 13, QUIET)
	_status.visible = false
	outer.add_child(_status)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 6)
	scroll.add_child(_box)


func set_reachable(ok: bool) -> void:
	_status.visible = not ok


func show_data(data: Dictionary) -> void:
	var key := JSON.stringify(data)
	if key == _last:
		return
	_last = key
	for child in _box.get_children():
		child.queue_free()
		_box.remove_child(child)
	_section("Still open", data["open"], "Nothing waiting. Enjoy it.", true)
	_section("Coming up", data["coming"], "Nothing coming up.", false)
	_notes(data["notes"])


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _heading(text: String) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 10
	_box.add_child(spacer)
	_box.add_child(_label(text, 18, ACCENT))


func _section(title: String, things: Array, empty: String, tickable: bool) -> void:
	_heading(title)
	if things.is_empty():
		_box.add_child(_label(empty, 15, QUIET))
	for thing in things:
		_box.add_child(_row(thing, tickable))


func _row(thing: Dictionary, tickable: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	if tickable:
		var tick := Button.new()
		tick.custom_minimum_size = Vector2(26, 26)
		tick.focus_mode = Control.FOCUS_NONE
		tick.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		tick.add_theme_stylebox_override("normal", _ring(false))
		tick.add_theme_stylebox_override("hover", _ring(true))
		tick.add_theme_stylebox_override("pressed", _ring(true))
		tick.tooltip_text = "done"
		tick.pressed.connect(func(): ticked.emit(int(thing["id"])))
		row.add_child(tick)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 0)
	col.add_child(_label(str(thing["text"]), 16, INK))
	var when := _when(thing)
	if when != "":
		col.add_child(_label(when, 13, WARM if tickable else QUIET))
	row.add_child(col)
	return row


func _notes(notes: Array) -> void:
	_heading("Notes")
	if notes.is_empty():
		_box.add_child(_label("No notes yet.", 15, QUIET))
	for n in notes:
		_box.add_child(_label("- " + str(n), 15, INK))


func _when(thing: Dictionary) -> String:
	var parts: Array[String] = []
	if thing.get("due_at") != null:
		parts.append(_local(str(thing["due_at"])))
	if thing.get("every") != null:
		parts.append("every " + str(thing["every"]))
	return "  -  ".join(parts)


func _local(iso: String) -> String:
	var unix := Time.get_unix_time_from_datetime_string(iso.trim_suffix("Z"))
	unix += int(Time.get_time_zone_from_system()["bias"]) * 60
	var then := Time.get_datetime_dict_from_unix_time(int(unix))
	var now_unix := (
		Time.get_unix_time_from_system() + int(Time.get_time_zone_from_system()["bias"]) * 60
	)
	var today := int(now_unix / 86400)
	var day := int(unix / 86400)
	var clock := "%02d:%02d" % [then["hour"], then["minute"]]
	if day == today:
		return "today " + clock
	if day == today + 1:
		return "tomorrow " + clock
	return "%s %d %s %s" % [DAYS[then["weekday"]], then["day"], MONTHS[then["month"]], clock]


func _ring(filled: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = ACCENT if filled else Color(0, 0, 0, 0)
	s.set_border_width_all(2)
	s.border_color = ACCENT
	s.set_corner_radius_all(13)
	return s
