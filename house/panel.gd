extends PanelContainer

signal ticked(id: int)
signal door_pressed
signal opened(id: int)
signal now_cleared
signal timer_pressed(what: String)

const INK := Color("f1e9dc")
const QUIET := Color("a89fb0")
const ACCENT := Color("e8b86d")
const WARM := Color("f0a07a")
const DAYS := ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
const MONTHS := [
	"", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
]

const GOOD := Color("8fd18a")

var _title: Label
var _door: Button
var _box: VBoxContainer
var _status: Label
var _last := ""
var focus
var _now_card: PanelContainer
var _now_text: Label
var _timer_ring: Ring
var _len_btn: Button
var _go_btn: Button


func _ready() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("2a2530")
	style.set_content_margin_all(18)
	add_theme_stylebox_override("panel", style)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	add_child(outer)

	var head := HBoxContainer.new()
	_title = _label("the home", 24, ACCENT)
	head.add_child(_title)
	_door = Button.new()
	_door.focus_mode = Control.FOCUS_NONE
	_door.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_door.add_theme_font_size_override("font_size", 13)
	_door.pressed.connect(func(): door_pressed.emit())
	head.add_child(_door)
	outer.add_child(head)
	_status = _label("can't reach tlon", 13, QUIET)
	_status.visible = false
	outer.add_child(_status)
	_build_now(outer)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 6)
	scroll.add_child(_box)


class Ring:
	extends Control
	var focus

	func _init() -> void:
		custom_minimum_size = Vector2(34, 34)

	func _process(_dt: float) -> void:
		if visible and focus != null and focus.running():
			queue_redraw()

	func _draw() -> void:
		var mid := size / 2.0
		draw_arc(mid, 13, 0, TAU, 28, Color(0.1, 0.09, 0.12, 0.25), 4.0)
		if focus != null and focus.running():
			draw_arc(mid, 13, -PI / 2, -PI / 2 + TAU * focus.progress(), 28, Color("5fa86a"), 5.0)


func _build_now(outer: VBoxContainer) -> void:
	_now_card = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("f8efb8")
	style.set_border_width_all(2)
	style.border_color = Color("2a2530")
	style.set_content_margin_all(10)
	_now_card.add_theme_stylebox_override("panel", style)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	_now_card.add_child(col)
	var top := HBoxContainer.new()
	var tag := _label("NOW", 12, Color("2a2530"))
	top.add_child(tag)
	var drop := Button.new()
	drop.text = "x"
	drop.flat = true
	drop.focus_mode = Control.FOCUS_NONE
	drop.tooltip_text = "not now"
	drop.add_theme_color_override("font_color", Color("2a2530"))
	drop.pressed.connect(func(): now_cleared.emit())
	top.add_child(drop)
	col.add_child(top)
	_now_text = _label("", 17, Color("2a2530"))
	col.add_child(_now_text)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_timer_ring = Ring.new()
	row.add_child(_timer_ring)
	_len_btn = Button.new()
	_len_btn.focus_mode = Control.FOCUS_NONE
	_len_btn.tooltip_text = "click to change: 10 / 25 / 45"
	_len_btn.pressed.connect(func(): timer_pressed.emit("cycle"))
	row.add_child(_len_btn)
	_go_btn = Button.new()
	_go_btn.focus_mode = Control.FOCUS_NONE
	_go_btn.pressed.connect(func(): timer_pressed.emit("toggle"))
	row.add_child(_go_btn)
	col.add_child(row)
	_now_card.visible = false
	outer.add_child(_now_card)


func _process(_dt: float) -> void:
	if focus == null:
		return
	_now_card.visible = focus.active() and focus.text != ""
	if not _now_card.visible:
		return
	_timer_ring.focus = focus
	_now_text.text = focus.text
	_len_btn.text = "%d min" % focus.minutes if not focus.running() else focus.clock()
	_len_btn.disabled = focus.running()
	_go_btn.text = "stop" if focus.running() else "start"


func set_room(room: String, door_text: String) -> void:
	_title.text = "the " + room
	_door.text = door_text
	_last = ""


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
	if int(data.get("done_week", 0)) > 0:
		var spacer := Control.new()
		spacer.custom_minimum_size.y = 10
		_box.add_child(spacer)
		_box.add_child(_label("%d done this week" % int(data["done_week"]), 13, QUIET))


# view: {crew: [{name, role, status, doing}], more, waiting: [{title, why}], waiting_count, paused}
func show_office(view: Dictionary) -> void:
	var key := JSON.stringify(view)
	if key == _last:
		return
	_last = key
	for child in _box.get_children():
		child.queue_free()
		_box.remove_child(child)
	if view["paused"] != "":
		_box.add_child(_label(view["paused"], 15, WARM))
	_heading("Waiting on you")
	if view["waiting"].is_empty() and view["waiting_count"] == 0:
		_box.add_child(_label("Nothing needs you.", 15, QUIET))
	for w in view["waiting"]:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 0)
		col.add_child(_label(str(w["title"]), 16, INK))
		col.add_child(_label(str(w["why"]), 13, WARM))
		_box.add_child(col)
	if view["waiting_count"] > view["waiting"].size():
		_box.add_child(_label("%d in all" % view["waiting_count"], 13, QUIET))
	_heading("The crew")
	if view["crew"].is_empty():
		_box.add_child(_label("Nobody on the bench.", 15, QUIET))
	for c in view["crew"]:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 0)
		var who := str(c["name"])
		if c["role"] != "":
			who += "  -  " + str(c["role"])
		col.add_child(_label(who, 16, _status_color(c["status"])))
		col.add_child(_label(str(c["doing"]), 13, QUIET))
		_box.add_child(col)
	if view["more"] > 0:
		_box.add_child(_label("+%d more" % view["more"], 15, QUIET))


func _status_color(status: String) -> Color:
	match status:
		"working":
			return GOOD
		"waiting":
			return ACCENT
		"idle":
			return INK
	return QUIET


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
	if tickable:
		col.mouse_filter = Control.MOUSE_FILTER_STOP
		col.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		col.tooltip_text = "Done, later, or now"
		col.gui_input.connect(
			func(ev: InputEvent) -> void:
				if (
					ev is InputEventMouseButton
					and ev.pressed
					and ev.button_index == MOUSE_BUTTON_LEFT
				):
					opened.emit(int(thing["id"]))
		)
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
