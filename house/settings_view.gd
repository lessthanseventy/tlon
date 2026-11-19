extends VBoxContainer

# The paper settings screen, and the small cog that opens it. It reads and writes `settings` and
# drives what already exists (sound, the room's layout, the finds, the chat); the address check
# goes up to main.gd, which owns the server calls.
signal check_requested(url: String)

const Paper := preload("res://paper.gd")
const Chooser := preload("res://chooser.gd")
const Settings := preload("res://settings.gd")
const Pets := preload("res://pets.gd")
const Sure := preload("res://sure.gd")
const LocalList := preload("res://local_list.gd")
const Claude := preload("res://reader_claude.gd")
const MONTHS := [
	"January", "February", "March", "April", "May", "June", "July", "August", "September",
	"October", "November", "December",
]
const DAYS := [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
# the keys of `Looks.KEYS` and what their switch says
const THINGS := {
	"litter_box": "a litter box for a cat",
	"bowls": "food and water bowls",
	"pet_things": "a post, a blanket, hay and a bone",
}
const LOOKS := {
	"glow": "a soft glow at the lights after dark",
	"weather_art": "pixel weather in the window",
	"spells": "spell effects",
	"font": "a pixel font for headings",
}

var settings
var home
var _menus := {}
var _things := {}
var sure := Sure.new()
# the reader that runs the claude program and the Telegram bot (`telegram.gd`); set by main.gd
var claude: RefCounted
var phone: Node

var _name: LineEdit
var _month
var _day
var _cat: LineEdit
var _dog: LineEdit
var _kind1: KindPicker
var _kind2: KindPicker
var _sound: Button
var _volume: HSlider
var _widget: Button
var _top: Button
var _looks := {}
var _weather_box: VBoxContainer
var _weather_on: Button
var _town: LineEdit
var _found: Label
var _forget: Button
var _reset: Button
var _chat_n: Label
var _clear: Button
var _where_server: Button
var _where_local: Button
var _server_box: VBoxContainer
var _local_say: Label
var _url: LineEdit
var _url_say: Label
var _art: Label
var _plan: VBoxContainer
var _talk_box: VBoxContainer
var _tg_on: Button
var _tg_box: VBoxContainer
var _tg_token: LineEdit
var _tg_say: Label
var _tg_state: Label
var _tg_reached: Label
var _tg_at: LineEdit
var _tg_off: Button
var _claude_on: Button
var _claude_box: VBoxContainer
var _claude_cmd: LineEdit
var _claude_found: Label
var _claude_say: Label
var _claude_last: Label
var _cmd_seen := "\u0000"
var _loading := false


# which animal a pet is: a list of the kinds and "none", and the chosen one idling beside it
class KindPicker:
	extends HBoxContainer
	signal picked(kind: String)
	var pets
	var kind := ""
	var _ids: Array = Pets.KINDS.keys() + [Pets.NONE]
	var _list := Chooser.new()
	var _t := 0.0

	func _init(the_pets) -> void:
		pets = the_pets
		add_theme_constant_override("separation", 6)
		for id in _ids:
			_list.add_item(Pets.KINDS[id]["label"] if id != Pets.NONE else "none")

		_list.item_selected.connect(
			func(i: int) -> void:
				kind = _ids[i]
				picked.emit(kind)
		)
		add_child(_list)
		var view := Control.new()
		view.custom_minimum_size = Vector2(80, 64)
		view.clip_contents = true
		view.draw.connect(_draw_kind.bind(view))
		add_child(view)

	func show_kind(k: String) -> void:
		kind = k
		_list.select(_ids.find(k))

	func _process(dt: float) -> void:
		_t += dt
		get_child(1).queue_redraw()

	func _draw_kind(view: Control) -> void:
		if kind != Pets.NONE:
			pets.draw_preview(view, kind, _t, Vector2(40, 58), 2)


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
	add_theme_constant_override("separation", 7)
	var col: VBoxContainer = self

	_head(col, "you")
	var r := _flow(col)
	r.add_child(Paper.label("name", 14, Paper.QUIET))
	_name = _field(r, "no name shown", "name")
	r = _flow(col)
	r.add_child(Paper.label("birthday", 14, Paper.QUIET))
	_month = Chooser.new()
	_month.add_item("none")
	for m in MONTHS:
		_month.add_item(m)
	_day = Chooser.new()
	for d in 31:
		_day.add_item(str(d + 1))
	for o in [_month, _day]:
		r.add_child(o)
	_month.item_selected.connect(func(_i: int) -> void: _birthday())
	_day.item_selected.connect(func(_i: int) -> void: _birthday())

	_head(col, "the pets")
	r = _flow(col)
	r.add_child(Paper.label("the first pet", 14, Paper.QUIET))
	_cat = _field(r, Settings.CAT, "cat")
	_cat.custom_minimum_size.x = 100
	_kind1 =_kind_picker(r, "pet1")
	r = _flow(col)
	r.add_child(Paper.label("the second pet", 14, Paper.QUIET))
	_dog = _field(r, Settings.DOG, "dog")
	_dog.custom_minimum_size.x = 100
	_kind2 =_kind_picker(r, "pet2")
	r = _flow(col)
	r.add_child(Paper.label("first pet's way", 14, Paper.QUIET))
	_menu(r, "pet1_personality", Pets.PERSONALITIES)
	r = _flow(col)
	r.add_child(Paper.label("second pet's way", 14, Paper.QUIET))
	_menu(r, "pet2_personality", Pets.PERSONALITIES)
	r = _flow(col)
	r.add_child(Paper.label("how much they talk", 14, Paper.QUIET))
	_menu(r, "pet_chatter", Pets.CHATTER.keys())
	r = _flow(col)
	r.add_child(Paper.label("how much they get up to", 14, Paper.QUIET))
	_menu(r, "pet_antics", ["few", "some", "lots"])
	for key in THINGS:
		r = _flow(col)
		var put := func() -> void: _put(key, _things[key].button_pressed)
		_things[key] = Paper.chip(THINGS[key], r, put, true)

	_head(col, "visitors")
	r = _flow(col)
	r.add_child(Paper.label("who comes", 14, Paper.QUIET))
	_menu(r, "visitors", ["all", "calm", "none"])
	r = _flow(col)
	r.add_child(Paper.label("how often", 14, Paper.QUIET))
	_menu(r, "visitors_rate", ["rare", "sometimes", "often"])


	_head(col, "sound")
	r = _flow(col)
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
	r = _flow(col)
	_widget = Paper.chip("start as the small widget", r, func() -> void: _put("widget", _widget.button_pressed), true)
	r = _flow(col)
	_top = Paper.chip("widget stays on top", r, func() -> void: _put("on_top", _top.button_pressed), true)

	_head(col, "weather")
	r = _flow(col)
	r.add_child(Paper.label("degrees", 14, Paper.QUIET))
	_menu(r, "degrees", ["f", "c"], ["°F", "°C"])
	_weather_box = VBoxContainer.new()
	_weather_box.add_theme_constant_override("separation", 7)
	col.add_child(_weather_box)
	r = _flow(_weather_box)
	var toggle := func() -> void: _put("weather", _weather_on.button_pressed)
	_weather_on = Paper.chip("weather outside the window", r, toggle, true)
	r = _flow(_weather_box)
	r.add_child(Paper.label("town", 14, Paper.QUIET))
	_town = _field(r, "empty: found from your internet address", "weather_town")
	_quiet(_weather_box).text = "asks wttr.in about every half hour; nothing of yours is sent"

	_head(col, "looks")
	for key in LOOKS:
		r = _flow(col)
		var put := func() -> void: _put(key, _looks[key].button_pressed)
		_looks[key] = Paper.chip(LOOKS[key], r, put, true)

	_head(col, "things to find")
	r = _flow(col)
	_found = Paper.label("", 14, Paper.INK)
	r.add_child(_found)
	_forget = Paper.chip("forget them all", r, _forget_found)

	_head(col, "the room")
	r = _flow(col)
	_reset = Paper.chip("reset the room to how it came", r, _reset_room)

	_head(col, "the phone's chat")
	r = _flow(col)
	_chat_n = Paper.label("", 14, Paper.INK)
	r.add_child(_chat_n)
	_clear = Paper.chip("clear", r, _clear_chat)

	_head(col, "where the list lives")
	r = _flow(col)
	_where_server = Paper.chip("a tlon server", r, func() -> void: _put("where", "server"), true)
	_where_local = Paper.chip("this computer", r, func() -> void: _put("where", "local"), true)
	_local_say = Paper.label("", 13, Paper.QUIET)
	_local_say.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	col.add_child(_local_say)
	_server_box = VBoxContainer.new()
	col.add_child(_server_box)
	r = _flow(_server_box)
	_url = Paper.edit(Settings.default_url(), r)
	_url.text_submitted.connect(func(_t: String) -> void: _check())
	Paper.chip("check", r, _check)
	_url_say = Paper.label("", 13, Paper.QUIET)
	_server_box.add_child(_url_say)
	_plan = VBoxContainer.new()
	_server_box.add_child(_plan)

	_talk_box = VBoxContainer.new()
	_talk_box.add_theme_constant_override("separation", 7)
	col.add_child(_talk_box)
	_telegram_section(_talk_box)
	_claude_section(_talk_box)

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
	_kind1.show_kind(Pets.kind_of(settings.value("pet1"), "nina"))
	_kind2.show_kind(Pets.kind_of(settings.value("pet2"), "argos"))
	for key in _menus:
		_menus[key][0].select(maxi(0, _menus[key][1].find(settings.value(key))))
	_menus["degrees"][0].select(_menus["degrees"][1].find(settings.degrees()))
	for key in _things:
		_things[key].set_pressed_no_signal(bool(settings.value(key)))
	_sound.set_pressed_no_signal(not home.sound.muted)
	if _volume != null:
		_volume.set_value_no_signal(float(home.sound.volume))
	_weather_on.set_pressed_no_signal(bool(settings.value("weather")))
	_town.text = str(settings.data.get("weather_town", ""))
	_widget.set_pressed_no_signal(bool(settings.value("widget")))
	_top.set_pressed_no_signal(bool(settings.value("on_top")))
	for key in _looks:
		_looks[key].set_pressed_no_signal(bool(settings.value(key)))
	_url.text = str(settings.data.get("url", ""))
	_tg_at.text = str(settings.value("telegram_list_at"))
	_claude_cmd.text = str(settings.data.get("claude_command", ""))
	for l in [_tg_token, _tg_say, _claude_say]:
		l.text = ""
	_url_say.text = "using " + settings.server_url()
	_url_say.add_theme_color_override("font_color", Paper.QUIET)
	var dir: String = home.room.art_dir
	_art.text = ("found in " if home.room.art_found else "not found in ") + dir
	_plan_rows()
	sure.key = ""
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
	sure.tick(dt)
	if visible:
		_refresh()



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


func _telegram_section(box: VBoxContainer) -> void:
	_head(box, "Telegram")
	var r := _flow(box)
	_tg_on = Paper.chip(
		"a Telegram bot in the house", r, func() -> void: _put("telegram", _tg_on.button_pressed), true
	)
	_tg_box = VBoxContainer.new()
	_tg_box.add_theme_constant_override("separation", 7)
	box.add_child(_tg_box)
	_quiet(_tg_box).text = (
		"1. message @BotFather in Telegram\n2. send it /newbot and follow the steps\n"
		+ "3. paste the token it gives you here"
	)
	r = _flow(_tg_box)
	_tg_token = Paper.edit("the bot's token", r)
	_tg_token.secret = true
	_tg_token.text_submitted.connect(func(_t: String) -> void: _tg_connect())
	Paper.chip("connect", r, _tg_connect)
	_tg_say = _quiet(_tg_box)
	_tg_state = _quiet(_tg_box)
	_tg_reached = _quiet(_tg_box)
	r = _flow(_tg_box)
	r.add_child(Paper.label("the day's list at", 14, Paper.QUIET))
	_tg_at = Paper.edit("17:30, or off", r)
	_tg_at.text_submitted.connect(func(_t: String) -> void: _tg_list_at())
	_tg_at.focus_exited.connect(_tg_list_at)
	_tg_off = Paper.chip("disconnect", r, _tg_disconnect)
	_quiet(_tg_box).text = "works while this computer is on and the house is open"


func _tg_connect() -> void:
	if phone == null:
		return
	_tg_say.text = "connecting..."
	phone.connect_bot(
		_tg_token.text,
		func(line: String) -> void:
			_tg_say.text = line
			if line.begins_with("@"):
				_tg_token.text = ""
	)


func _tg_disconnect() -> void:
	if phone != null and sure.ask("tg"):
		phone.disconnect_bot()
		_tg_say.text = ""


# "HH:MM" or "off"; anything else goes back to what was kept
func _tg_list_at() -> void:
	var t := _tg_at.text.strip_edges().to_lower()
	if t == "off" or RegEx.create_from_string("^([01]?\\d|2[0-3]):[0-5]\\d$").search(t) != null:
		_put("telegram_list_at", t)
	_tg_at.text = str(settings.value("telegram_list_at"))


func _tg_lines() -> void:
	if phone == null:
		return
	var who: String = phone.me if phone.me != "" else "your bot"
	if phone.token == "":
		_tg_state.text = "no bot connected"
	elif phone.chat == 0:
		_tg_state.text = "token saved (%s). Send %s to %s in Telegram to pair." % [
			phone.masked(), phone.code, who
		]
	else:
		_tg_state.text = "paired with %s; token %s" % [who, phone.masked()]
	var reached := ""
	if phone.problem != "":
		reached = phone.problem
	elif phone.reached_at > 0.0:
		var d: Dictionary = LocalList.parts(phone.reached_at)
		var same_day: bool = LocalList.midnight(phone.reached_at) == LocalList.midnight(home._now_local())
		var at := "%02d:%02d" % [d["hour"], d["minute"]]
		reached = "last reached: " + (at if same_day else "%02d-%02d %s" % [d["month"], d["day"], at])
	_tg_reached.text = reached


func _claude_section(box: VBoxContainer) -> void:
	_head(box, "reading with Claude")
	var r := _flow(box)
	_claude_on = Paper.chip(
		"read my messages with Claude", r, func() -> void: _put("claude", _claude_on.button_pressed), true
	)
	_claude_box = VBoxContainer.new()
	_claude_box.add_theme_constant_override("separation", 7)
	box.add_child(_claude_box)
	r = _flow(_claude_box)
	r.add_child(Paper.label("command", 14, Paper.QUIET))
	_claude_cmd = _field(r, "claude", "claude_command")
	Paper.chip("test", r, _claude_test)
	_claude_found = _quiet(_claude_box)
	_claude_say = _quiet(_claude_box)
	_claude_last = _quiet(_claude_box)
	_quiet(_claude_box).text = "your messages are sent to your own Claude account"


# a wrapped quiet line
func _quiet(parent: Control) -> Label:
	var l := Paper.label("", 13, Paper.QUIET)
	l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	parent.add_child(l)
	return l


func _claude_lines() -> void:
	var cmd := str(settings.value("claude_command")).strip_edges()
	if cmd != _cmd_seen:
		_cmd_seen = cmd
		var found: String = Claude.which(cmd if cmd != "" else "claude")
		_claude_found.text = "found: " + found if found != "" else "not found on PATH"
	var last: String = "" if claude == null else claude.last
	_claude_last.text = "" if last == "" else "last Claude reading: " + last


func _claude_test() -> void:
	if claude == null:
		return
	_put("claude_command", _claude_cmd.text.strip_edges())
	_claude_say.text = "testing..."
	claude.test(
		{"now": home._now_local(), "bias": home._bias(), "status": {}},
		func(line: String) -> void: _claude_say.text = line
	)


func _field(parent: Control, hint: String, key: String) -> LineEdit:
	var e := Paper.edit(hint, parent)
	e.custom_minimum_size.x = 150
	e.text_submitted.connect(func(t: String) -> void: _put(key, t.strip_edges()))
	e.focus_exited.connect(func() -> void: _put(key, e.text.strip_edges()))
	return e


func _menu(parent: Control, key: String, values: Array, labels: Array = []) -> void:
	var o := Chooser.new()
	for i in values.size():
		o.add_item(str(labels[i] if i < labels.size() else values[i]))
	o.item_selected.connect(func(i: int) -> void: _put(key, values[i]))
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.get_parent().add_child(o)
	_menus[key] = [o, values]


func _kind_picker(parent: Control, key: String) -> KindPicker:
	var p := KindPicker.new(home.pets)
	p.picked.connect(func(kind: String) -> void: _put(key, kind))
	parent.add_child(p)
	return p


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
	var local: bool = settings.is_local()
	_where_server.set_pressed_no_signal(not local)
	_where_local.set_pressed_no_signal(local)
	_server_box.visible = not local
	_local_say.visible = local
	_local_say.text = "kept in " + ProjectSettings.globalize_path(LocalList.STORE)
	_talk_box.visible = local
	_weather_box.visible = local
	_tg_on.set_pressed_no_signal(bool(settings.value("telegram")))
	_tg_box.visible = _tg_on.button_pressed
	_tg_lines()
	_claude_on.set_pressed_no_signal(bool(settings.value("claude")))
	_claude_box.visible = _claude_on.button_pressed
	_claude_lines()
	for l in [_tg_say, _tg_reached, _claude_say, _claude_last]:
		l.visible = l.text != ""
	_found.text = "%d of %d found" % [home.eggs.found.size(), home.eggs.CATALOGUE.size()]
	_chat_n.text = "%d messages" % home.chat.messages.size()
	for pair in [[_forget, "forget", "forget them all"], [_reset, "reset", "reset the room to how it came"], [_clear, "clear", "clear"], [_tg_off, "tg", "disconnect"]]:
		(pair[0] as Button).text = "sure?" if sure.armed(pair[1]) else pair[2]


# a row that wraps, so a wide one still fits the sidebar
func _flow(parent: Control) -> HFlowContainer:
	var r := HFlowContainer.new()
	r.add_theme_constant_override("h_separation", 6)
	r.add_theme_constant_override("v_separation", 4)
	parent.add_child(r)
	return r
