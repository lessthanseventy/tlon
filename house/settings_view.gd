extends PanelContainer

# The paper settings screen, and the small cog that opens it. It reads and writes `settings` and
# drives what already exists (sound, the room's layout, the finds, the chat); the address check
# goes up to main.gd, which owns the server calls.
signal closed
signal check_requested(url: String)

const Paper := preload("res://paper.gd")
const Settings := preload("res://settings.gd")
const Sure := preload("res://sure.gd")
const MONTHS := [
	"January", "February", "March", "April", "May", "June", "July", "August", "September",
	"October", "November", "December",
]
const DAYS := [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

var settings
var home
var sure := Sure.new()

var _scroll: ScrollContainer
var _name: LineEdit
var _month: OptionButton
var _day: OptionButton
var _cat: LineEdit
var _dog: LineEdit
var _sound: Button
var _volume: HSlider
var _widget: Button
var _top: Button
var _found: Label
var _forget: Button
var _reset: Button
var _chat_n: Label
var _clear: Button
var _url: LineEdit
var _url_say: Label
var _art: Label
var _plan: VBoxContainer
var _loading := false


class Cog:
	extends Control
	signal pressed
	var _hover := false

	func _init() -> void:
		custom_minimum_size = Vector2(26, 26)
		size = custom_minimum_size
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func() -> void: _lit(true))
		mouse_exited.connect(func() -> void: _lit(false))

	func _lit(on: bool) -> void:
		_hover = on
		queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == 1:
			accept_event()
			pressed.emit()

	func _draw() -> void:
		var c := size / 2.0
		var col := Color(0.93, 0.88, 0.78, 0.95 if _hover else 0.5)
		for i in 8:
			var dir := Vector2.from_angle(i * TAU / 8.0)
			draw_line(c + dir * 6.0, c + dir * 10.5, col, 3.5)
		draw_circle(c, 7.5, col)
		draw_circle(c, 3.0, Color(0.12, 0.1, 0.14, 0.9))


func setup(the_settings, the_home) -> void:
	settings = the_settings
	home = the_home


func _ready() -> void:
	visible = false
	add_theme_stylebox_override("panel", Paper.panel(14))
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	add_child(outer)
	outer.add_child(Paper.label("Settings", 20, Paper.INK))
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.custom_minimum_size = Vector2(450, 300)
	outer.add_child(_scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 7)
	_scroll.add_child(col)
	outer.add_child(Paper.label("Esc closes", 12, Paper.QUIET))

	_head(col, "you")
	var r := Paper.row(col)
	r.add_child(Paper.label("name", 14, Paper.QUIET))
	_name = _field(r, "no name shown", "name")
	r = Paper.row(col)
	r.add_child(Paper.label("birthday", 14, Paper.QUIET))
	_month = OptionButton.new()
	_month.add_item("none")
	for m in MONTHS:
		_month.add_item(m)
	_day = OptionButton.new()
	for d in 31:
		_day.add_item(str(d + 1))
	for o in [_month, _day]:
		Paper.skin(o)
		r.add_child(o)
	_month.item_selected.connect(func(_i: int) -> void: _birthday())
	_day.item_selected.connect(func(_i: int) -> void: _birthday())

	_head(col, "the pets")
	r = Paper.row(col)
	r.add_child(Paper.label("the cat", 14, Paper.QUIET))
	_cat = _field(r, Settings.CAT, "cat")
	r = Paper.row(col)
	r.add_child(Paper.label("the dog", 14, Paper.QUIET))
	_dog = _field(r, Settings.DOG, "dog")

	_head(col, "sound")
	r = Paper.row(col)
	_sound = Paper.chip("sound", r, _toggle_sound, true)
	if "volume" in home.sound:
		_volume = HSlider.new()
		_volume.min_value = 0.0
		_volume.max_value = 1.0
		_volume.step = 0.05
		_volume.custom_minimum_size = Vector2(160, 20)
		_volume.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_volume.value_changed.connect(func(v: float) -> void: home.sound.volume = v)
		r.add_child(_volume)

	_head(col, "window")
	r = Paper.row(col)
	_widget = Paper.chip("start as the small widget", r, func() -> void: _put("widget", _widget.button_pressed), true)
	r = Paper.row(col)
	_top = Paper.chip("widget stays on top", r, func() -> void: _put("on_top", _top.button_pressed), true)

	_head(col, "things to find")
	r = Paper.row(col)
	_found = Paper.label("", 14, Paper.INK)
	r.add_child(_found)
	_forget = Paper.chip("forget them all", r, _forget_found)

	_head(col, "the room")
	r = Paper.row(col)
	_reset = Paper.chip("reset the room to how it came", r, _reset_room)

	_head(col, "the phone's chat")
	r = Paper.row(col)
	_chat_n = Paper.label("", 14, Paper.INK)
	r.add_child(_chat_n)
	_clear = Paper.chip("clear", r, _clear_chat)

	_head(col, "where the list lives")
	r = Paper.row(col)
	var server := Paper.chip("a tlon server", r, func() -> void: pass, true)
	server.set_pressed_no_signal(true)
	server.disabled = true
	var local := Paper.chip("this computer - coming soon", r, func() -> void: pass, true)
	local.disabled = true
	r = Paper.row(col)
	_url = Paper.edit(Settings.default_url(), r)
	_url.text_submitted.connect(func(_t: String) -> void: _check())
	Paper.chip("check", r, _check)
	_url_say = Paper.label("", 13, Paper.QUIET)
	col.add_child(_url_say)
	_plan = VBoxContainer.new()
	col.add_child(_plan)

	_head(col, "the art")
	_art = Paper.label("", 13, Paper.INK)
	_art.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	col.add_child(_art)


func open() -> void:
	_loading = true
	_name.text = settings.data.get("name", "")
	var mmdd := str(settings.value("birthday"))
	var parts := mmdd.split("-")
	_month.select(int(parts[0]) if parts.size() == 2 else 0)
	_day.select(int(parts[1]) - 1 if parts.size() == 2 else 0)
	_day.disabled = _month.selected == 0
	_cat.text = settings.data.get("cat", "")
	_dog.text = settings.data.get("dog", "")
	_sound.set_pressed_no_signal(not home.sound.muted)
	if _volume != null:
		_volume.set_value_no_signal(float(home.sound.volume))
	_widget.set_pressed_no_signal(bool(settings.value("widget")))
	_top.set_pressed_no_signal(bool(settings.value("on_top")))
	_url.text = str(settings.data.get("url", ""))
	_url_say.text = "using " + settings.server_url()
	_url_say.add_theme_color_override("font_color", Paper.QUIET)
	var dir: String = home.room.art_dir
	_art.text = ("found in " if home.room.art_found else "not found in ") + dir
	_plan_rows()
	sure.key = ""
	_loading = false
	_refresh()
	visible = true
	_scroll.scroll_vertical = 0


func close() -> void:
	if not visible:
		return
	if get_viewport().gui_get_focus_owner() != null:
		get_viewport().gui_get_focus_owner().release_focus()
	visible = false
	closed.emit()


func _process(dt: float) -> void:
	sure.tick(dt)
	if visible:
		_refresh()


func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()


func fit(room: Vector2) -> void:
	_scroll.custom_minimum_size.y = clampf(room.y - 120.0, 160.0, 480.0)


# the address check came back
func url_result(ok: bool) -> void:
	_url_say.text = "reachable" if ok else "not reachable"
	_url_say.add_theme_color_override("font_color", Paper.INK if ok else Paper.WARM)


func _head(parent: Control, text: String) -> void:
	var gap := Control.new()
	gap.custom_minimum_size.y = 4
	parent.add_child(gap)
	var l := Paper.label(text, 13, Paper.QUIET)
	parent.add_child(l)


func _field(parent: Control, hint: String, key: String) -> LineEdit:
	var e := Paper.edit(hint, parent)
	e.text_submitted.connect(func(t: String) -> void: _put(key, t.strip_edges()))
	e.focus_exited.connect(func() -> void: _put(key, e.text.strip_edges()))
	return e


func _put(key: String, v: Variant) -> void:
	if not _loading:
		settings.put(key, v)


func _birthday() -> void:
	_day.disabled = _month.selected == 0
	if _month.selected == 0:
		_put("birthday", "")
		return
	var m: int = _month.selected
	if _day.selected + 1 > DAYS[m - 1]:
		_day.select(DAYS[m - 1] - 1)
	_put("birthday", "%02d-%02d" % [m, _day.selected + 1])


func _toggle_sound() -> void:
	if home.sound.muted == _sound.button_pressed:
		home.sound.toggle()


func _forget_found() -> void:
	if sure.ask("forget"):
		home.eggs.forget()


func _reset_room() -> void:
	if sure.ask("reset"):
		home.layout.reset(home.busy_cells())
		home.apply_layout()


func _clear_chat() -> void:
	if sure.ask("clear"):
		home.chat.clear()


func _check() -> void:
	var u := _url.text.strip_edges().trim_suffix("/")
	if u != "" and not (u.begins_with("http://") or u.begins_with("https://")):
		_url_say.text = "an address starts with http://"
		_url_say.add_theme_color_override("font_color", Paper.WARM)
		return
	_put("url", u)
	_url_say.text = "checking..."
	_url_say.add_theme_color_override("font_color", Paper.QUIET)
	check_requested.emit(settings.server_url())


# the server's own times, only what its settings already say
func _plan_rows() -> void:
	for c in _plan.get_children():
		c.queue_free()
	for pair in [["home_list_at", "the daily list at"], ["home_review_on", "the weekly review on"]]:
		if home.knobs.has(pair[0]):
			_plan.add_child(Paper.label("%s %s  (the server's)" % [pair[1], home.knobs[pair[0]]], 13, Paper.INK))


func _refresh() -> void:
	_found.text = "%d of %d found" % [home.eggs.found.size(), home.eggs.CATALOGUE.size()]
	_chat_n.text = "%d messages" % home.chat.messages.size()
	for pair in [[_forget, "forget", "forget them all"], [_reset, "reset", "reset the room to how it came"], [_clear, "clear", "clear"]]:
		(pair[0] as Button).text = "sure?" if sure.armed(pair[1]) else pair[2]
