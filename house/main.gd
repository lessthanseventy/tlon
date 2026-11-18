extends Control

const STAGED_TEXT := [
	"name", "cat", "dog", "pet1", "pet2", "birthday", "claude_command", "pet1_personality",
	"pet2_personality", "pet_chatter", "pet_antics", "visitors", "visitors_rate", "degrees",
	"weather_town",
]
const STAGED_FLAGS := ["claude", "telegram", "litter_box", "bowls", "pet_things", "weather"]
const POLL_SECONDS := 5.0
const SLOW_SECONDS := 300.0
const WATCH_SECONDS := 60.0
const AWAY_FOR_GREETING := 20.0
const PANEL_WIDTH := 300
const BACKDROP := Color("1f1b24")
const RoomScript := preload("res://room.gd")
const ORDER := ["waiting", "working", "idle", "cold", "off"]
const LIVE := ["waiting", "working", "idle"]
const WAITING_SHOWN := 5
const DecorateScript := preload("res://decorate.gd")
const WIDGET_SIZE := Vector2i(656, 432)
const WIDGET_STORE := "user://house_widget.json"
const FormScript := preload("res://form.gd")
const SettingsView := preload("res://settings_view.gd")
const Pets := preload("res://pets.gd")
const Settings := preload("res://settings.gd")
const PetView := preload("res://pet_view.gd")
const ChatView := preload("res://chat_view.gd")
const BackendHttp := preload("res://backend_http.gd")
const BackendLocal := preload("res://backend_local.gd")
const LocalList := preload("res://local_list.gd")
const ReaderClaude := preload("res://reader_claude.gd")
const Telegram := preload("res://telegram.gd")
const Wttr := preload("res://wttr.gd")

# false in a staged or scripted run: nothing is sent to Claude or anywhere else
var talk_live := false
var pets_retry := 20.0
var pets_every := 300.0
var pets_nudge := 60.0
var pets_window := 180.0

var _demo := false
var _shot := ""
var _backend: Node
var _claude := ReaderClaude.new()
var _wttr := Wttr.new()
var _phone := Telegram.new()
var _fixture := ""
var _probing := false
var _starters := false
var _forecast_arg: Variant = null

var _data := {"open": [], "coming": [], "notes": [], "done_week": 0, "done": null}
var _form: PanelContainer
var _settings_view: PanelContainer
var _pet_view: PanelContainer
var _chat_view: PanelContainer
var _cog: Control
var _skip: Array = []
var _again := false
var _demo_ids := 1000
var _jot: PanelContainer
var _closet: Control
var _decorate: Control
var _widget := false
var _drag := false
var _drag_mouse := Vector2i.ZERO
var _drag_win := Vector2i.ZERO
var _prev_size := Vector2i(1100, 700)
var _jot_seq := 0
var _office := {}
var _at := "home"
var _inflight := ""
var _reach := {}
var _busy := false
var _slow_step := ""
var _pets_busy := false
var _pets_stale := false
var _pets_timer: Timer
var _pets_nudged: Timer
var _pets_since := 0.0
var _ids: Array = []
var _ids_known := false
var _watch_busy := false
var _away_at := 0.0

var _room: Control
var _panel: PanelContainer


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--sounds" in args:
		print(preload("res://sound.gd").listing(_art_dir()))
		set_process(false)
		get_tree().quit()
		return
	_demo = "--demo" in args
	if "--office" in args:
		_at = "office"
	if "--shot" in args:
		_shot = args[args.find("--shot") + 1]

	var bg := ColorRect.new()
	bg.color = BACKDROP
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_room = RoomScript.new()
	_room.set_anchors_preset(Control.PRESET_FULL_RECT)
	_room.offset_right = -PANEL_WIDTH
	_room.art_dir = _art_dir()
	_room.door_clicked.connect(_toggle)
	add_child(_room)

	_panel = preload("res://panel.gd").new()
	_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_panel.offset_left = -PANEL_WIDTH
	_panel.offset_right = 0
	_panel.ticked.connect(_on_ticked)
	_panel.door_pressed.connect(_toggle)
	_panel.focus = _room.home.focus
	_panel.opened.connect(func(id: int) -> void: _room.home.open_item_menu(id))
	_panel.now_cleared.connect(func() -> void: _room.home.focus.clear())
	_panel.timer_pressed.connect(_on_timer)
	_panel.add_pressed.connect(_add_thing)
	_panel.now_pressed.connect(_what_now)
	add_child(_panel)
	talk_live = not _room.home.staged
	_wttr.live = talk_live
	_wttr.reported.connect(_on_wttr)
	add_child(_wttr)
	_set_up_phone()
	_use_backend(args)
	if "--forecast" in args:
		_forecast_arg = _staged_forecast(args[args.find("--forecast") + 1])
	_decorate = DecorateScript.new()
	_decorate.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_decorate.offset_left = -PANEL_WIDTH
	_decorate.offset_right = 0
	_decorate.room = _room
	_decorate.home = _room.home
	_decorate.done.connect(func() -> void: _set_decorate(false))
	add_child(_decorate)
	_room.decorate = _decorate
	_room.home.acted.connect(_on_act)
	_room.pressed_empty.connect(_begin_drag)

	_add_note(Control.PRESET_BOTTOM_LEFT, "Art by Gridwright")
	if not _room.art_found:
		_add_note(Control.PRESET_TOP_LEFT, "art not found")

	_jot = preload("res://jot.gd").new()
	_jot.submitted.connect(_send_jot)
	_jot.cancelled.connect(func() -> void: _jot_seq += 1)
	add_child(_jot)
	_closet = preload("res://closet.gd").new()
	_closet.set_anchors_preset(Control.PRESET_FULL_RECT)
	_closet.tabbed.connect(func() -> void: _room.home.sound.request("tab"))
	_closet.applied.connect(func() -> void: _room.home.sound.request("save"))
	add_child(_closet)
	_form = FormScript.new()
	_form.submitted.connect(
		func(req: Dictionary) -> void: _write(req["path"], req["body"], _form_saved)
	)
	_form.acted.connect(func(id: int, what: String) -> void: _act(id, what, _form.finish))
	add_child(_form)
	_room.home.things.form_wanted.connect(_open_form)
	_room.home.things.post.connect(func(path: String, body: Dictionary) -> void: _write(path, body))
	_settings_view = SettingsView.new()
	_settings_view.setup(_room.home.settings, _room.home)
	_settings_view.claude = _claude
	_settings_view.phone = _phone
	_settings_view.check_requested.connect(_check_server)
	add_child(_settings_view)
	_pet_view = PetView.new()
	_pet_view.setup(_room.home.settings, _room.home)
	add_child(_pet_view)
	_room.pet_menu.connect(_open_pet_view)
	_room.home.settings.changed.connect(_on_setting)
	_chat_view = ChatView.new()
	_chat_view.setup(_room.home.chat, _room.home)
	_chat_view.sent.connect(_send_chat)
	_chat_view.acted.connect(_chat_act)
	add_child(_chat_view)
	_cog = SettingsView.Cog.new()
	_cog.pressed.connect(func() -> void: _toggle_settings())
	add_child(_cog)

	if _demo:
		var demo: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://demo.json"))
		_office = demo.get("office", {})
		if "--empty" in args:
			demo.merge({"open": [], "coming": [], "notes": []}, true)
		_room.home.set_weather(demo.get("weather"))
		if "--no-voices" not in args:
			_room.home.set_voices(demo.get("pets", {}))
		if "--visitor" in args:
			_room.home.set_office(_office)
		demo["forecast"] = _dated(demo.get("forecast", []))
		_apply(demo)
		if "--tick-demo" in args:
			get_tree().create_timer(0.75).timeout.connect(func(): _on_ticked(1))
			if "--tick-all" in args:
				get_tree().create_timer(1.1).timeout.connect(func(): _on_ticked(2))
				get_tree().create_timer(1.4).timeout.connect(func(): _on_ticked(3))
	else:
		var slow_timer := Timer.new()
		slow_timer.wait_time = SLOW_SECONDS
		slow_timer.timeout.connect(_slow_poll)
		add_child(slow_timer)
		slow_timer.start()
		_pets_timer = Timer.new()
		_pets_timer.one_shot = true
		_pets_timer.timeout.connect(_pets_ask)
		add_child(_pets_timer)
		_pets_nudged = Timer.new()
		_pets_nudged.one_shot = true
		_pets_nudged.timeout.connect(_pets_ask)
		add_child(_pets_nudged)
		var watch_timer := Timer.new()
		watch_timer.wait_time = WATCH_SECONDS
		watch_timer.timeout.connect(_watch_door)
		add_child(watch_timer)
		watch_timer.start()
		var timer := Timer.new()
		timer.wait_time = POLL_SECONDS
		timer.timeout.connect(_poll)
		add_child(timer)
		timer.start()
		if _probing:
			_first_start()
		else:
			_slow_poll()
			_pets_ask()
			_watch_door()
	_enter(_at)
	if _room.home.settings.value("widget"):
		_set_widget(true)
	if "--unread" in args:
		_room.home.chat.unread = true
	if "--pet-card" in args:
		var who: String = args[args.find("--pet-card") + 1]
		get_tree().create_timer(0.4).timeout.connect(func() -> void: _open_pet_view(who))
	if "--settings" in args:
		var spec: String = args[args.find("--settings") + 1]
		get_tree().create_timer(0.4).timeout.connect(func() -> void: _stage_settings(spec))
	if "--chat" in args:
		var spec: String = args[args.find("--chat") + 1]
		get_tree().create_timer(0.4).timeout.connect(func() -> void: _stage_chat(spec))
	if "--tell" in args:
		var lines := args[args.find("--tell") + 1].split(";", false)
		get_tree().create_timer(0.4).timeout.connect(
			func() -> void:
				for line in lines:
					_tell(line, func(_ok: bool, _reply: String) -> void: pass)
				_open_chat()
		)
	if "--closet" in args:
		get_tree().create_timer(0.3).timeout.connect(
			func() -> void:
				_open_closet()
				if "--tab" in args:
					_closet.pick_tab(args[args.find("--tab") + 1])
		)
	if "--decorate" in args:
		_set_decorate(true)
		if "--pick" in args:
			_decorate.pick(args[args.find("--pick") + 1])
		if "--cell" in args:
			var rc := args[args.find("--cell") + 1].split(",")
			_decorate.pin = Vector2i(int(rc[0]), int(rc[1]))
	if "--typing" in args:
		var text: String = args[args.find("--typing") + 1]
		get_tree().create_timer(0.3).timeout.connect(
			func() -> void:
				_jot.open(text)
				if "--sending" in args:
					_jot.sending(true)
		)

	if "--form" in args:
		var form_spec: String = args[args.find("--form") + 1]
		get_tree().create_timer(0.4).timeout.connect(func() -> void: _stage_form(form_spec))
	if "--what-now" in args:
		get_tree().create_timer(0.4).timeout.connect(_what_now)
	if _shot != "":
		var wait := float(args[args.find("--wait") + 1]) if "--wait" in args else 1.5
		await get_tree().create_timer(wait).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_shot)
		get_tree().quit()


func _use_backend(args: Array) -> void:
	var settings = _room.home.settings
	var at := args.find("--local") + 1
	_fixture = args[at] if at > 0 and at < args.size() else ""
	_probing = settings.fresh and not OS.has_environment("TLON_URL")
	if settings.is_local():
		_at = "home"
	_make_backend()


# the list's home: a tlon server, or the house's own file; what was in flight to the old one is lost
func _make_backend() -> void:
	var home = _room.home
	var node: Node
	if home.settings.is_local():
		var local := BackendLocal.new()
		var keep: bool = not home.staged
		var path := LocalList.STORE if keep else ""
		if _fixture not in ["", "starters"]:
			path = _fixture
			keep = false
		local.setup(path, Callable(home, "_now_local"), home._bias(), keep)
		if (_fixture == "starters" or _starters) and local.list.fresh:
			local.list.starters()
		if local.list.notice != "":
			home.show_reply(local.list.notice)
		node = local
	else:
		node = BackendHttp.new()
		node.base = home.settings.server_url()
	_install(node)


func _install(node: Node) -> void:
	if _backend != null:
		remove_child(_backend)
		_backend.queue_free()
	_busy = false
	_again = false
	_pets_busy = false
	_watch_busy = false
	_slow_step = ""
	_reach = {}
	_backend = node
	_backend.changed.connect(_refresh)
	_backend.told.connect(
		func(row: Dictionary) -> void:
			if _phone_on():
				_phone.on_told(row)
	)
	add_child(_backend)
	_apply_where()
	_apply_weather()
	_apply_talk()
	if _backend.local and _phone_on():
		for row in _backend.started:
			_phone.on_told(row)


# what only means something with a server is not shown over the house's own list
func _apply_where() -> void:
	var served: bool = not _backend.local
	_room.office_door = served
	_panel.set_door_visible(served)
	_panel.set_reachable(true)
	if not served and _at == "office":
		_enter("home")


func _set_up_phone() -> void:
	var home = _room.home
	_phone.persist = not home.staged
	_phone.load_state()
	_phone.clock = Callable(home, "_now_local")
	_phone.bias = home._bias()
	_phone.status = func() -> Dictionary: return _backend.list.status() if _backend.local else {}
	_phone.rng.randomize()
	_phone.heard.connect(_phone_heard)
	_phone.tapped.connect(_phone_tapped)
	add_child(_phone)


# over the house's own list the weather comes from wttr.in, unless he has turned it off; over a
# server it is the server's
func _apply_weather() -> void:
	var settings = _room.home.settings
	var was := _wttr.on
	_wttr.on = _backend.local and bool(settings.value("weather"))
	_wttr.town = Wttr.town_of(str(settings.value("weather_town")))
	if _wttr.on:
		_wttr.poke()
	elif was:
		_wttr.clear()
		_room.home.clear_weather()


func _on_wttr() -> void:
	_room.home.set_weather(_wttr.report)
	_room.home.set_forecast(_wttr.days)


# Claude and Telegram work only over the house's own list, and only while their setting is on
func _apply_talk() -> void:
	var settings = _room.home.settings
	var cmd := str(settings.value("claude_command")).strip_edges()
	_claude.command = cmd if cmd != "" else "claude"
	if _backend.local:
		_backend.claude = _claude if talk_live and settings.value("claude") else null
	_phone.live = talk_live
	_phone.list_at = str(settings.value("telegram_list_at"))
	if _phone_on():
		_phone.start()
	else:
		_phone.stop()


func _phone_on() -> bool:
	return _backend.local and talk_live and _room.home.settings.value("telegram")


# a line from the paired chat goes the way the chat's own do, marked as from the phone
func _phone_heard(text: String, finish: Callable) -> void:
	_tell(
		text,
		func(ok: bool, reply: String) -> void: finish.call(reply if ok else "I couldn't keep that."),
		"phone"
	)


func _phone_tapped(id: int, what: String, finish: Callable) -> void:
	_act(
		id,
		what,
		func() -> void:
			_room.home.chat.resolve(id, what)
			finish.call()
	)


# the first start of a house with no settings yet: the default address is asked once; with nobody
# there the house keeps its own list, with a few gentle things on it
func _first_start() -> void:
	var probe := BackendHttp.new()
	add_child(probe)
	probe.check(
		_backend.base,
		func(ok: bool) -> void:
			probe.queue_free()
			_probing = false
			if not ok:
				_starters = true
				_room.home.settings.put("where", "local")
				_starters = false
			_slow_poll()
			_pets_ask()
			_watch_door()
			_poll()
	)


func _art_dir() -> String:
	return preload("res://art.gd").dir(OS.get_cmdline_user_args())


func _add_note(preset: Control.LayoutPreset, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color("a89fb0"))
	l.set_anchors_preset(preset)
	l.position = Vector2(12, 0)
	l.grow_vertical = (
		Control.GROW_DIRECTION_BEGIN
		if preset == Control.PRESET_BOTTOM_LEFT
		else Control.GROW_DIRECTION_END
	)
	l.offset_left = 12
	l.offset_top = -28 if preset == Control.PRESET_BOTTOM_LEFT else 8
	add_child(l)


static func _home_data(d: Dictionary) -> Dictionary:
	return {
		"open": d.get("open", []),
		"coming": d.get("coming", []),
		"notes": d.get("notes", []),
		"done_week": d.get("done_week", 0),
		"done": d.get("done"),
		"waiting": d.get("waiting", []),
		"someday": d.get("someday", []),
		"projects": d.get("projects", []),
		"note_rows": d.get("note_rows", []),
		"forecast": d.get("forecast", []),
	}


# `--forecast none|JSON`: the card's days for a picture, JSON rows as the server's with `in_days`
# (0 is today) where a date would go, so a staged forecast never goes stale
func _staged_forecast(spec: String) -> Array:
	var rows: Variant = JSON.parse_string(spec) if spec != "none" else []
	return _dated(rows) if rows is Array else []


func _dated(rows: Array) -> Array:
	var today := Time.get_unix_time_from_datetime_string(_room.home.today() + "T00:00:00")
	return rows.map(
		func(row: Variant) -> Variant:
			if not row is Dictionary or not row.has("in_days"):
				return row
			var at := Time.get_date_string_from_unix_time(int(today) + int(row["in_days"]) * 86400)
			return row.merged({"date": at})
	)


func _apply(data: Dictionary) -> void:
	_data = _home_data(data)
	_room.home.set_data(_data)
	if _forecast_arg != null:
		_room.home.set_forecast(_forecast_arg)
	elif not _backend.local:
		_room.home.set_forecast(_data["forecast"])
	var ids: Array = []
	for t in _data["open"]:
		ids.append(int(t["id"]))
	ids.sort()
	if _ids_known and ids != _ids and _pets_nudged != null:
		_pets_nudged.start(pets_nudge)
	_ids = ids
	_ids_known = true
	if _at == "home":
		_room.show_home()
		_panel.show_data(_data)
	if _room.home.take_attention() and _shot == "":
		DisplayServer.window_request_attention()


func _toggle() -> void:
	if _backend.local:
		return
	_enter("office" if _at == "home" else "home")


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if _closet.visible or _jot.visible or _overlay() or event.ctrl_pressed or event.alt_pressed:
		return
	if event.keycode == KEY_TAB:
		get_viewport().set_input_as_handled()
		_toggle()
		return
	if get_viewport().gui_get_focus_owner() != null:
		return
	if _decorate.active and _decorate.key(event.keycode):
		get_viewport().set_input_as_handled()
		return
	if _at == "home" and not _decorate.active and _room.home.key(event.keycode):
		get_viewport().set_input_as_handled()
		return
	match event.keycode:
		KEY_D:
			if _at == "home":
				get_viewport().set_input_as_handled()
				_set_decorate(not _decorate.active)
		KEY_N, KEY_SLASH, KEY_ENTER, KEY_KP_ENTER:
			if _at == "home":
				get_viewport().set_input_as_handled()
				_jot.open()
		KEY_C:
			if _at == "home":
				get_viewport().set_input_as_handled()
				_open_closet()
		KEY_I:
			if _at == "home":
				get_viewport().set_input_as_handled()
				_add_thing()
		KEY_COMMA:
			if _at == "home":
				get_viewport().set_input_as_handled()
				_open_settings()
		KEY_K:
			if _at == "home":
				get_viewport().set_input_as_handled()
				_open_chat()
		KEY_H:
			if _at == "home":
				get_viewport().set_input_as_handled()
				_what_now()
		KEY_W:
			get_viewport().set_input_as_handled()
			_set_widget(not _widget)
		KEY_ESCAPE:
			_room.home.menu.close()
			_room.home.close_card()
			_room.home.dismiss_slip()


func _process(_dt: float) -> void:
	_room.home.jot_open = _jot.visible
	_room.home.closet_open = _closet.visible
	_room.home.decorating = _decorate.active
	if _overlay() and _form_blocked():
		_form.close()
		_settings_view.close()
		_pet_view.close()
		_chat_view.close()
	_room.home.form_open = _overlay()
	var room_w := size.x - (0 if _widget else PANEL_WIDTH)
	_cog.visible = _at == "home" and not _decorate.active and not _closet.visible
	_cog.position = Vector2(room_w - 34.0, 8.0)
	for v in [_form, _settings_view, _pet_view, _chat_view]:
		if v.visible:
			if v == _settings_view or v == _chat_view:
				v.fit(size)
			v.size = v.get_combined_minimum_size()
			v.position = ((Vector2(room_w, size.y) - v.size) / 2.0).round()
	var at_mouse := _room.get_local_mouse_position()
	_room.home.eggs.set_laser(
		_at == "home"
		and Input.is_key_pressed(KEY_P)
		and not _jot.visible
		and not _closet.visible
		and not _decorate.active
		and Rect2(Vector2.ZERO, _room.size).has_point(at_mouse),
		at_mouse
	)
	if _jot.visible:
		var w := size.x - (0 if _widget else PANEL_WIDTH)
		_jot.size = _jot.get_combined_minimum_size()
		_jot.position = Vector2((w - _jot.size.x) / 2.0, size.y - _jot.size.y - 56).round()
	if _drag:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			get_window().position = _drag_win + (DisplayServer.mouse_get_position() - _drag_mouse)
		else:
			_drag = false
			_save_widget()


func _set_decorate(on: bool) -> void:
	if on == _decorate.active:
		return
	if on and (_at != "home" or _widget):
		return
	if on and not _room.home.layout.art:
		_room.home.reply_text = "decorating needs the art, and it was not found"
		_room.home.reply_left = 4.0
		return
	_panel.visible = not on
	if on:
		_decorate.enter()
	else:
		_decorate.leave()


func _form_blocked() -> bool:
	var h = _room.home
	return _jot.visible or _closet.visible or _decorate.active or h.menu.is_open or h.rhythm.kind != ""


func _overlay() -> bool:
	return _form.visible or _settings_view.visible or _pet_view.visible or _chat_view.visible


func _open_pet_view(id: String) -> bool:
	if _at != "home" or _form_blocked() or _overlay():
		return false
	_room.home.close_card()
	_pet_view.open(id)
	return true


func _open_settings() -> bool:
	if _at != "home" or _form_blocked() or _overlay():
		return false
	_room.home.close_card()
	_settings_view.open()
	return true


func _toggle_settings() -> void:
	if _settings_view.visible:
		_settings_view.close()
	else:
		_open_settings()


func _open_chat() -> bool:
	if _at != "home" or _form_blocked() or _overlay():
		return false
	_room.home.close_card()
	_chat_view.open()
	return true


# mode "new" (a preset for the form) or "edit" ({row, due}); false when something else is up
func _open_form(mode: String, spec: Dictionary) -> bool:
	if (
		_at != "home"
		or _widget
		or _form_blocked()
		or _settings_view.visible
		or _pet_view.visible
		or _chat_view.visible
	):
		return false
	var home = _room.home
	home.close_card()
	var today: Dictionary = home.things.today()
	if mode == "edit":
		_form.open_edit(spec["row"], spec["due"], today)
	else:
		_form.open_new(spec, today)
	home.form_open = true
	return true


func _add_thing() -> void:
	_open_form("new", {"kinds": ["todo", "reminder", "note", "waiting", "project"]})


func _what_now() -> void:
	_skip = []
	_ask_now()


func _ask_now() -> void:
	if _demo:
		var rows: Array = _data["open"].filter(func(t): return not _skip.has(int(t["id"])))
		var pick: Variant = rows[0].duplicate() if not rows.is_empty() else null
		if pick != null:
			pick["why"] = "it has sat the longest"
		_show_pick(pick, "nothing open")
		return
	var query := "" if _skip.is_empty() else "?skip=" + ",".join(_skip.map(str))
	_backend.fetch(
		"/api/home/now" + query,
		func(reached: bool, code: int, parsed: Variant) -> void:
			if reached and code == 200 and parsed is Dictionary:
				_show_pick(parsed.get("pick"), str(parsed.get("say", "")))
			else:
				_trouble(_why(reached, code, parsed)),
		8.0
	)


func _show_pick(pick: Variant, say: String) -> void:
	if pick == null:
		_skip = []
	_room.home.show_pick(pick if pick is Dictionary else {}, say)


# `--form KIND;key=value;...` or `--form edit:ID;...` (keys: kinds text who steps date time every
# error), for a picture
func _stage_form(spec: String) -> void:
	var parts := spec.split(";")
	var kv := {}
	for p in parts.slice(1):
		kv[p.get_slice("=", 0)] = p.substr(p.find("=") + 1)
	var today: Dictionary = _room.home.things.today()
	var fill := {}
	for k in ["text", "who", "steps", "time", "every"]:
		if kv.has(k):
			fill[k] = str(kv[k]).replace("\\n", "\n")
	if kv.has("date"):
		var d := str(kv["date"]).split("-")
		fill["date"] = {
			"y": int(d[0]) if d.size() == 3 else int(today["y"]),
			"m": int(d[-2]),
			"d": int(d[-1])
		}
	if parts[0].begins_with("edit:"):
		var home = _room.home
		var row: Dictionary = home.things.find(int(parts[0].substr(5)))
		_open_form("edit", {"row": row, "due": home._due(row) if row.get("due_at") != null else -1.0})
	else:
		var preset := {"kinds": str(kv.get("kinds", parts[0])).split(",")}
		_open_form("new", preset)
	_form.fill(fill)
	if kv.has("error"):
		_form.fail(kv["error"])


func _open_closet() -> void:
	if not _widget:
		_closet.open(_room.home.look)


func _begin_drag() -> void:
	if _widget:
		_drag = true
		_drag_mouse = DisplayServer.mouse_get_position()
		_drag_win = get_window().position


func _save_widget() -> void:
	var f := FileAccess.open(WIDGET_STORE, FileAccess.WRITE)
	if f != null:
		var p := get_window().position
		f.store_string(JSON.stringify({"x": p.x, "y": p.y}))


func _set_widget(on: bool) -> void:
	if on == _widget:
		return
	var w := get_window()
	if on:
		_prev_size = w.size
	else:
		_save_widget()
	_set_decorate(false)
	_widget = on
	_panel.visible = not on
	_room.offset_right = 0 if on else -PANEL_WIDTH
	w.borderless = on
	w.always_on_top = on and _room.home.settings.value("on_top")
	w.size = WIDGET_SIZE if on else _prev_size
	if on and FileAccess.file_exists(WIDGET_STORE):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(WIDGET_STORE))
		if d is Dictionary:
			w.position = Vector2i(int(d.get("x", 0)), int(d.get("y", 0)))


func _on_act(id: int, what: String) -> void:
	_act(id, what)


# `ok` runs once the server has said yes
func _act(id: int, what: String, ok: Callable = Callable()) -> void:
	if what in ["done", "delete", "hour", "tomorrow"] and _phone_on():
		ok = _then(ok, func() -> void: _phone.handled(id, what))
	match what:
		"done":
			_write("/api/home/%d/done" % id, {}, _then(ok, func() -> void: _remove(id)))
		"delete":
			_write("/api/home/%d/drop" % id, {}, _then(ok, func() -> void: _gone(id)))
		"revive":
			_write("/api/home/%d/revive" % id, {}, ok)
		"nottoday":
			var close := func() -> void: _room.home.close_card()
			_write("/api/home/%d/answer" % id, {"choice": "nottoday"}, _then(ok, close))
		"else":
			_skip.append(id)
			_ask_now()
		"hour", "tomorrow":
			_later(id, what, ok)
		"now":
			for item in _data["open"]:
				if int(item["id"]) == id:
					_room.home.focus.set_now(id, str(item["text"]))
		"unnow":
			_room.home.focus.clear()
		"office":
			_enter("office")
		"closet":
			_open_closet()
		"jot":
			_jot.open()
		"chat":
			_open_chat()


func _then(first: Callable, second: Callable) -> Callable:
	return func() -> void:
		second.call()
		if first.is_valid():
			first.call()


# A change the server keeps. It answers yes (the room is read again at once, `ok` runs) or a line
# for `_trouble`; asking the server nothing in the demo.
func _write(path: String, body: Dictionary, ok: Callable = Callable()) -> void:
	if _demo:
		_demo_write(path, body)
		if ok.is_valid():
			ok.call()
		return
	_post(
		path,
		body,
		func(reached: bool, code: int, parsed: Variant) -> void:
			_panel.set_reachable(reached)
			if reached:
				_refresh()
			if reached and code == 200:
				if ok.is_valid():
					ok.call()
			else:
				_trouble(_why(reached, code, parsed))
	)


func _form_saved() -> void:
	_room.home.sound.request("save")
	_form.finish()


static func _why(reached: bool, code: int, parsed: Variant) -> String:
	if not reached:
		return "couldn't reach tlon - nothing was changed"
	if code == 400 and parsed is Dictionary and parsed.get("error") is String:
		return parsed["error"]
	if code == 404:
		return "that one is not there any more"
	return "tlon answered %d" % code


# one line where he is looking: the form, else the open card, else a slip
func _trouble(line: String) -> void:
	_room.home.sound.request("error")
	if _form.visible:
		_form.fail(line)
	elif _chat_view.visible:
		_chat_view.flash(line)
	elif _room.home.card.is_open():
		_room.home.things.flash = line
	else:
		_room.home.show_reply(line)


# read the room again now; one already on its way may have started before the change
func _refresh() -> void:
	if _demo or _at != "home":
		return
	if _busy:
		_again = true
	else:
		_poll()


func _gone(id: int) -> void:
	_room.home.sound.request("delete")
	for key in ["open", "coming", "waiting", "someday", "projects"]:
		_data[key] = _data[key].filter(func(t): return int(t["id"]) != id)
	_data["note_rows"] = _data["note_rows"].filter(func(t): return int(t["id"]) != id)
	if _room.home.card.kind == "pick":
		_room.home.close_card()
	_apply(_data)


func _demo_write(path: String, body: Dictionary) -> void:
	var parts := path.split("/")
	if path == "/api/home/add":
		_demo_ids += 1
		var row := {"id": _demo_ids, "kind": body["kind"], "text": body["text"], "due_at": null}
		row["every"] = body.get("every")
		if body["kind"] == "note":
			_data["notes"] = [body["text"]] + _data["notes"]
			_data["note_rows"] = [{"id": _demo_ids, "text": body["text"]}] + _data["note_rows"]
		elif body["kind"] == "reminder":
			var bias := float(Time.get_time_zone_from_system()["bias"]) * 60.0
			var utc := Time.get_unix_time_from_datetime_string(str(body["at"])) - bias
			row["due_at"] = Time.get_datetime_string_from_unix_time(int(utc)) + "Z"
			_data["coming"] = _data["coming"] + [row]
		elif body["kind"] == "todo":
			_data["open"] = _data["open"] + [row]
		_apply(_data)
	elif parts.size() == 5 and parts[4] == "drop":
		_gone(int(parts[3]))

func _on_timer(what: String) -> void:
	var f: RefCounted = _room.home.focus
	match what:
		"cycle":
			f.cycle()
		"toggle":
			if f.running():
				f.stop()
			else:
				f.start()


func _post(path: String, payload: Dictionary, done: Callable, timeout: float = 6.0) -> void:
	_backend.send(path, payload, done, timeout)


func _later(id: int, until: String, ok: Callable = Callable()) -> void:
	var hours := 1.0 if until == "hour" else 24.0
	var moved := func(_ok: bool, code: int, body: Variant) -> void:
		if code == 200:
			if ok.is_valid():
				ok.call()
			var due := Time.get_datetime_string_from_unix_time(
				int(Time.get_unix_time_from_system() + hours * 3600.0)
			)
			if body is Dictionary and body.get("due_at") != null:
				due = str(body["due_at"]).trim_suffix("Z")
			_moved(id, due + "Z")
		else:
			_panel.set_reachable(code > 0)
			_trouble(_why(code > 0, code, body))
			_apply(_data)
	if _demo:
		moved.call(true, 200, null)
	else:
		_post("/api/home/%d/later" % id, {"until": until}, moved)


func _moved(id: int, due_at: String) -> void:
	var row := {}
	for item in _data["open"]:
		if int(item["id"]) == id:
			row = item.duplicate()
	if row.is_empty():
		return
	_room.home.send_later(id)
	row["kind"] = "reminder"
	row["due_at"] = due_at
	row["told_at"] = null
	_data["open"] = _data["open"].filter(func(t): return int(t["id"]) != id)
	_data["coming"] = _data["coming"] + [row]
	_apply(_data)
	if not _demo:
		_poll()


func _send_jot(text: String) -> void:
	_jot.sending(true)
	_jot_seq += 1
	var seq := _jot_seq
	_tell(
		text,
		func(ok: bool, reply: String) -> void:
			if seq != _jot_seq:
				return
			if ok:
				_jot.finish()
				_room.home.sound.request("save")
				_room.home.show_reply(reply)
			else:
				_jot.fail("couldn't reach tlon — not kept")
				_room.home.sound.request("error")
	)


# A line to the home, from the notepad or the chat: both are kept in the chat's history. `done`
# gets (reached, the reply); the room is read again at once.
func _tell(text: String, done: Callable, via: String = "") -> void:
	var chat = _room.home.chat
	var marks := {"via": via} if via != "" else {}
	chat.add("me", text, marks)
	var finished := func(ok: bool, code: int, body: Variant) -> void:
		var reached: bool = ok and code == 200
		var reply := "kept"
		if reached and body is Dictionary and body.get("reply") is String:
			reply = body["reply"]
		if reached:
			chat.add("home", reply, marks)
			if _demo:
				var id: int = 100 + _data["open"].size()
				_data["open"] = _data["open"] + [
					{"id": id, "kind": "todo", "text": text, "due_at": null, "every": null}
				]
				_apply(_data)
			else:
				_refresh()
		else:
			chat.retract(text)
		done.call(reached, reply)
	if _demo:
		get_tree().create_timer(1.4).timeout.connect(
			func() -> void: finished.call(true, 200, {"reply": "to do: " + text})
		)
	else:
		_post("/api/home", {"text": text}, finished, 40.0)


func _send_chat(text: String) -> void:
	_tell(text, func(ok: bool, _reply: String) -> void: _chat_view.finish(ok, text))


# a button under a told reminder: the same routes the paper menu calls
func _chat_act(id: int, what: String) -> void:
	_act(
		id,
		what,
		func() -> void:
			_room.home.chat.resolve(id, what)
			_chat_view.acting = -1
	)


func _check_server(url: String) -> void:
	if _demo:
		_settings_view.url_result(true)
		return
	var probe := BackendHttp.new()
	add_child(probe)
	probe.check(
		url,
		func(ok: bool) -> void:
			probe.queue_free()
			_settings_view.url_result(ok)
	)


func _on_setting(key: String) -> void:
	match key:
		"url":
			if not _backend.local:
				_backend.base = _room.home.settings.server_url()
			_refresh()
		"weather", "weather_town":
			_apply_weather()
		"where":
			_room.home.clear_weather()
			_make_backend()
			_room.home.set_voices({})
			if _backend.local:
				_room.home.set_office({})
			_refresh()
		"cat", "dog", "pet1", "pet2", "pet1_personality", "pet2_personality":
			_pets_changed()
		"on_top":
			if _widget:
				get_window().always_on_top = _room.home.settings.value("on_top")
		"claude", "claude_command", "telegram", "telegram_list_at":
			_apply_talk()


func _enter(where: String) -> void:
	if where == "office" and _backend.local:
		return
	_room.home.close_card()
	if where == "home" and _at == "office" and _away_at > 0.0:
		if Time.get_ticks_msec() / 1000.0 - _away_at >= AWAY_FOR_GREETING:
			_room.home.came_back()
	if where == "office":
		_away_at = Time.get_ticks_msec() / 1000.0
	if where == "home" and not _demo:
		_watch_door()
	_set_decorate(false)
	_at = where
	var other := "office" if where == "home" else "home"
	get_window().title = "the house - the " + where
	_panel.set_room(where, "to the " + other + "  >")
	_panel.set_reachable(_reach.get(where, true))
	if where == "home":
		_apply(_data)
	else:
		_show_office()
	if not _demo:
		_poll()


func _poll() -> void:
	if _busy or _probing:
		return
	_busy = true
	_inflight = _at
	_backend.fetch("/api/home" if _at == "home" else "/api/office", _on_polled, 4.0)


func _on_polled(reached: bool, code: int, body: Variant) -> void:
	_busy = false
	if _again:
		_again = false
		_poll.call_deferred()
	var polled := _inflight
	var parsed: Variant = body if code == 200 else null
	var ok: bool = reached and parsed is Dictionary
	_reach[polled] = ok
	if ok:
		if polled == "home":
			_data = _home_data(parsed)
			_room.home.sync_chat(_data)
			if _phone_on():
				_phone.sync(
					_data["open"]
					. filter(func(t): return t.get("told_at") != null)
					. map(func(t): return int(t["id"]))
				)
		else:
			_office = parsed
			_room.home.set_weather(parsed.get("weather"))
	if polled == _at:
		_panel.set_reachable(ok)
		if ok:
			_enter_view()
	else:
		_poll()


func _enter_view() -> void:
	if _at == "home":
		_apply(_data)
	else:
		_show_office()


func _show_office() -> void:
	var view := _office_view(_office)
	_room.show_office(view["figures"], view["caption"])
	_panel.show_office(view["panel"])



func _office_view(d: Dictionary) -> Dictionary:
	var roster: Array = d.get("roster", [])
	var threads: Array = d.get("threads", [])
	var ranked: Array = []
	for i in d.get("bench", []).size():
		var who: Dictionary = d["bench"][i]
		var best := {}
		for r in roster:
			if (
				r["agent"] == who["name"]
				and (
					best.is_empty()
					or ORDER.find(r.get("status", "off")) < ORDER.find(best["status"])
				)
			):
				best = r
		var status: String = best.get("status", "off")
		var asks := ""
		for t in threads:
			if (
				t["id"] == best.get("thread_id")
				and (t.get("awaiting") != null or t.get("prompt") != null)
			):
				asks = _asks(t)
		var doing := "off shift"
		match status:
			"waiting":
				doing = asks if asks != "" else "waiting on you"
			"working":
				doing = str(best.get("title", "working"))
			"idle":
				doing = (
					"idle" + ("" if best.get("title", "") == "" else "  -  " + str(best["title"]))
				)
			"cold":
				doing = "cold"
		(
			ranked
			. append(
				{
					"name": who["name"],
					"role": who.get("archetype", "") if who.get("archetype") != null else "",
					"status": status,
					"doing": doing,
					"skin": i,
					"tier": 0 if status in LIVE else 1,
					"seq": i,
				}
			)
		)
	ranked.sort_custom(
		func(a, b): return a["tier"] < b["tier"] or (a["tier"] == b["tier"] and a["seq"] < b["seq"])
	)

	var waiting: Array = []
	for t in threads:
		if t.get("awaiting") != null or t.get("prompt") != null:
			waiting.append({"title": t["title"], "why": _asks(t)})
	var live := ranked.filter(func(c): return c["status"] in ["waiting", "working"]).size()
	var pause: Variant = d.get("pause")
	var paused := ""
	var caption := ""
	match pause:
		"pencils_down":
			paused = "Pencils down: nothing new starts, everyone stops after their turn."
			caption = "the office is closed - pencils down"
		"lights_out":
			paused = "Lights out: the office is closed."
			caption = "the office is closed - lights out"
		_:
			if live == 0:
				caption = "the office is quiet"

	var shown: Array = ranked.slice(0, RoomScript.DESK_SLOTS)
	return {
		"figures": shown,
		"caption": caption,
		"panel":
		{
			"crew": shown,
			"more": ranked.size() - shown.size(),
			"waiting": waiting.slice(0, WAITING_SHOWN),
			"waiting_count": maxi(int(d.get("awaiting", 0)), waiting.size()),
			"paused": paused,
		},
	}


func _asks(t: Dictionary) -> String:
	if t.get("prompt") != null:
		return "asks: " + str(t["prompt"]["summary"])
	return "awaits " + str(t["awaiting"])


func _on_ticked(id: int) -> void:
	_act(id, "done")


func _slow_poll() -> void:
	if _slow_step != "" or _probing or _backend.local:
		return
	_slow_step = "settings"
	_backend.fetch("/api/settings", _on_slow, 8.0)


func _slow_office() -> void:
	_slow_step = "office"
	_backend.fetch("/api/office", _on_slow, 8.0)


func _on_slow(reached: bool, code: int, body: Variant) -> void:
	var step := _slow_step
	_slow_step = ""
	var parsed: Variant = body if code == 200 else null
	if step == "settings":
		if reached and parsed is Dictionary:
			for knob in parsed.get("knobs", []):
				_room.home.knobs[str(knob.get("key"))] = knob.get("value")
				if knob.get("key") == "home_list_at":
					_room.home.set_list_at(str(knob.get("value", "")))
		_slow_office()
		return
	if not reached or not parsed is Dictionary:
		return
	if step == "office":
		_room.home.set_weather(parsed.get("weather"))


# the pets' own names, animals and personalities, for a server that writes lines to suit them; a pet
# that is not in the room sends nothing
func _pets_path() -> String:
	var settings = _room.home.settings
	var parts: PackedStringArray = []
	for who in [["nina", "pet1", "cat", "pet1_personality"], ["argos", "pet2", "dog", "pet2_personality"]]:
		var kind := Pets.kind_of(settings.value(who[1]), who[0])
		if kind == Pets.NONE:
			continue
		var name: String = Settings.cat if who[0] == "nina" else Settings.dog
		var way := Pets.persona_of(settings.value(who[3]), who[0])
		for pair in [["name", name], ["species", Pets.KINDS[kind]["species"]], ["personality", way]]:
			parts.append("%s_%s=%s" % [who[0], pair[0], str(pair[1]).uri_encode()])
	return "/api/home/pets" + ("?" + "&".join(parts) if not parts.is_empty() else "")


func _pets_changed() -> void:
	if _pets_nudged != null and not _backend.local:
		_pets_nudged.start(minf(pets_nudge, 2.0))


func _pets_ask() -> void:
	if _pets_busy:
		_pets_stale = true
		return
	if _probing:
		return
	if not _room.home.has_voices() and _pets_since == 0.0:
		_pets_since = Time.get_ticks_msec() / 1000.0
	_pets_busy = true
	_backend.fetch(_pets_path(), _on_pets, 8.0)


func _on_pets(reached: bool, code: int, body: Variant) -> void:
	_pets_busy = false
	var parsed: Variant = body if code == 200 else null
	if reached and parsed is Dictionary and not parsed.is_empty():
		_room.home.set_voices(parsed)
	_pets_later()
	if _pets_stale:
		_pets_stale = false
		_pets_ask()


func _pets_later() -> void:
	var wait := pets_every
	if _room.home.has_voices():
		_pets_since = 0.0
	elif Time.get_ticks_msec() / 1000.0 - _pets_since < pets_window:
		wait = pets_retry
	_pets_timer.start(wait)


func _watch_door() -> void:
	if _at != "home" or _watch_busy or _probing or _backend.local:
		return
	_watch_busy = true
	_backend.fetch("/api/office", _on_watch, 6.0)


func _on_watch(reached: bool, code: int, body: Variant) -> void:
	_watch_busy = false
	var parsed: Variant = body if code == 200 else null
	if reached and parsed is Dictionary:
		_room.home.set_weather(parsed.get("weather"))
		_room.home.set_office(parsed)


func _remove(id: int) -> void:
	_room.home.tick_off(id)
	var at := Time.get_datetime_string_from_system(true) + "Z"
	for t in _data["open"]:
		if int(t["id"]) == id and _data.get("done") is Array:
			_data["done"] = [{"text": t["text"], "done_at": at}] + _data["done"]
	var kept: Array = _data["open"].filter(func(t): return int(t["id"]) != id)
	_data["open"] = kept
	_data["done_week"] = int(_data.get("done_week", 0)) + 1
	_apply(_data)


# `--settings "key=value;scroll;armed=reset"` (keys name cat dog birthday widget), for a picture
func _stage_settings(spec: String) -> void:
	var settings = _room.home.settings
	for p in spec.split(";", false):
		var key := p.get_slice("=", 0)
		var val := p.substr(p.find("=") + 1) if "=" in p else ""
		if key in STAGED_TEXT:
			settings.put(key, val)
		elif key in STAGED_FLAGS:
			settings.put(key, val == "on")
		elif key == "phone":
			_stage_phone(val)
	_open_settings()
	for p in spec.split(";", false):
		match p.get_slice("=", 0):
			"scroll":
				var to := p.substr(p.find("=") + 1) if "=" in p else ""
				_settings_view._scroll.scroll_vertical = int(to) if to != "" else 100000
			"armed":
				_settings_view.sure.ask(p.get_slice("=", 1))


# `phone=pairing|paired` in `--settings`: the bot's state for a picture, a made-up token
func _stage_phone(how: String) -> void:
	_phone.token = "12345:staged-0000abcd"
	_phone.me = "@house_demo_bot"
	_phone.code = "4821"
	_phone.chat = 7 if how == "paired" else 0
	_phone.reached_at = _room.home._now_local() - 90.0 if how == "paired" else 0.0


# `--chat "empty|talk,reminder,acted,pet,reading,fail"`, for a picture: a made-up conversation
func _stage_chat(spec: String) -> void:
	var chat = _room.home.chat
	var kinds := spec.split(",", false)
	var now := Time.get_unix_time_from_system()
	if "empty" not in kinds:
		chat.messages = [
			{"t": now - 7200, "who": "me", "text": "remind me to call the plumber tomorrow"},
			{"t": now - 7190, "who": "home", "text": "Reminder set: call the plumber, tomorrow 09:00."},
			{"t": now - 3000, "who": "me", "text": "what is left today?"},
			{"t": now - 2990, "who": "home", "text": "Still open: buy milk, send photos, water the plant."},
		]
		if "pet" in kinds:
			chat.messages.append({"t": now - 900, "who": "cat", "text": "I was not asleep, peasant."})
		if "reminder" in kinds or "acted" in kinds:
			var m := {"t": now - 120, "who": "home", "text": chat.BELL + "stretch and drink water", "id": 1, "told_at": "x"}
			if "acted" in kinds:
				m["done"] = "hour"
			chat.messages.append(m)
	if "phone" in kinds:
		chat.messages.append(
			{"t": now - 60, "who": "me", "text": "pick up the parcel tomorrow at 5pm", "via": "phone"}
		)
		chat.messages.append(
			{"t": now - 59, "who": "home", "text": "Reminder set: pick up the parcel, tomorrow 17:00.", "via": "phone"}
		)
	if "reading" in kinds:
		chat.messages.append({"t": now - 5, "who": "me", "text": "move the dentist to friday"})
		_chat_view.reading = true
	_open_chat()
	if "fail" in kinds:
		_chat_view.finish(false, "buy stamps")
