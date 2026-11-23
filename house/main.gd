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
const BACKDROP := Color("1f1b24")
const RoomScript := preload("res://room.gd")
const DecorateScript := preload("res://decorate.gd")
const Sidebar := preload("res://sidebar.gd")
const WIDGET_SIZE := Vector2i(720, 464)
const WIDGET_STORE := "user://house_widget.json"
const DriveScript := preload("res://drive.gd")
const Pets := preload("res://pets.gd")
const Settings := preload("res://settings.gd")
const BackendHttp := preload("res://backend_http.gd")
const BackendLocal := preload("res://backend_local.gd")
const LocalList := preload("res://local_list.gd")
const ReaderClaude := preload("res://reader_claude.gd")
const Telegram := preload("res://telegram.gd")
const Notices := preload("res://notices.gd")
const CalendarFeed := preload("res://calendar_feed.gd")
const Wttr := preload("res://wttr.gd")
const Adopt := preload("res://adopt.gd")
const Background := preload("res://background.gd")
const Chores := preload("res://chores.gd")
const People := preload("res://people.gd")
const Money := preload("res://money.gd")
const SHORT_CENTS := 60000

# false in a staged or scripted run: nothing is sent to Claude or anywhere else
var talk_live := false
# no window, no drawing: only what keeps reminders and Telegram going
var headless := false
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
var _notices := Notices.new()
var _calendar := CalendarFeed.new()
var _fixture := ""
var _probing := false
var _starters := false
var _forecast_arg: Variant = null

var _data := {"open": [], "coming": [], "notes": [], "done_week": 0, "done": null}
var _skip: Array = []
var _again := false
# keys of moves settled and still listed: a second press on one is ignored, not a 400
var _settling: Array = []
# writes answered; the write a read began after; the latest read begun after a write that came
var _writes := 0
var _poll_gen := 0
var _loaded_gen := -1
var _demo_ids := 1000
var _demo_rows: Array = []
var _money_spec := {}
var _decorate: Control
var _widget := false
var _drag := false
var _drag_mouse := Vector2i.ZERO
var _drag_win := Vector2i.ZERO
var _prev_size := Vector2i(1100, 700)
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
var _kept := false
var _tray: Node
var _quit := func() -> void: get_tree().quit()

var _room: Control
var _sidebar: PanelContainer
var _pick_ids: Array = []


func _ready() -> void:
	Adopt.adopt(OS.get_user_data_dir())
	var args := OS.get_cmdline_user_args()
	if "--sounds" in args:
		print(preload("res://sound.gd").listing(_art_dir()))
		set_process(false)
		get_tree().quit()
		return
	if Background.TELL_FLAG in args:
		_hand_over(args)
		return
	_demo = "--demo" in args
	if "--shot" in args:
		_shot = args[args.find("--shot") + 1]

	var bg := ColorRect.new()
	bg.color = BACKDROP
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_room = RoomScript.new()
	_room.art_dir = _art_dir()
	add_child(_room)

	talk_live = not _room.home.staged
	var hidden: bool = Background.FLAG in args or DisplayServer.get_name() == "headless"
	if not _room.home.staged and not Background.claim(
		Time.get_unix_time_from_system(), Background.LIVE, Background.SHOW, not hidden
	):
		get_tree().quit()
		return
	_wttr.live = talk_live
	_wttr.reported.connect(_on_wttr)
	add_child(_wttr)
	_set_up_calendar()
	_set_up_phone()
	_sidebar = Sidebar.new()
	_sidebar.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_sidebar.offset_left = -Sidebar.WIDTH
	_sidebar.offset_right = 0
	add_child(_sidebar)
	_sidebar.setup(_room.home, _claude, _phone)
	_sidebar.settings_view.calendar = _calendar
	_sidebar.settings_view.quit_requested.connect(func() -> void: _quit.call())
	_sidebar.close_requested.connect(func() -> void: _quit.call())
	_sidebar.jot_submitted.connect(_send_jot)
	_sidebar.chat_sent.connect(_send_chat)
	_sidebar.chat_acted.connect(_chat_act)
	_sidebar.move_settled.connect(_settle_move)
	_sidebar.check_requested.connect(_check_server)
	_sidebar.money_ui.forecast_wanted.connect(_fetch_forecast)

	_sidebar.money_ui.seen_wanted.connect(_notice_seen)
	_sidebar.form_submitted.connect(
		func(req: Dictionary) -> void: _write(req["path"], req["body"], _form_saved)
	)
	_sidebar.form_acted.connect(
		func(id: int, what: String) -> void: _act(id, what, _sidebar.form_done)
	)
	_sidebar.closet.tabbed.connect(func() -> void: _room.home.sound.request("tab"))
	_sidebar.closet.applied.connect(func() -> void: _room.home.sound.request("save"))
	if not _room.home.staged:
		_keep_house(args)
	_use_backend(args)
	if "--forecast" in args:
		_forecast_arg = _staged_forecast(args[args.find("--forecast") + 1])
	_decorate = DecorateScript.new()
	_decorate.room = _room
	_decorate.home = _room.home
	_decorate.done.connect(func() -> void: _set_decorate(false))
	_sidebar.attach_decorate(_decorate)
	_room.decorate = _decorate
	_room.home.acted.connect(_on_act)
	_room.home.viewed.connect(_on_viewed)
	_room.pressed_empty.connect(_on_empty)
	_room.pet_menu.connect(func(who: String) -> void: _on_viewed("pet", who))

	_add_note(Control.PRESET_BOTTOM_LEFT, "Art by Gridwright")
	if not _room.art_found:
		_add_note(Control.PRESET_TOP_LEFT, "art not found")

	_room.home.things.form_wanted.connect(_open_form)
	_room.home.things.post.connect(func(path: String, body: Dictionary) -> void: _write(path, body))
	_room.home.things.post_kept.connect(
		func(path: String, body: Dictionary, ok: Callable) -> void: _write(path, body, ok)
	)
	_room.home.things.meetings_wanted.connect(_fetch_meetings)
	_room.home.settings.changed.connect(_on_setting)

	if _demo:
		var demo: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://demo.json"))
		if "--empty" in args:
			demo.merge({"open": [], "coming": [], "notes": []}, true)
		_room.home.set_weather(demo.get("weather"))
		if "--no-voices" not in args:
			_room.home.set_voices(demo.get("pets", {}))
		demo["forecast"] = _dated(demo.get("forecast", []))
		demo["agendas"] = _demo_agendas(demo.get("agendas", []))
		demo["people"] = _demo_people(demo.get("people", []))
		_money_spec = demo.get("money_forecast", {})
		if demo.get("money") is Dictionary:
			_stage_money(demo, args[args.find("--money") + 1] if "--money" in args else "")
			if demo.has("money"):
				demo["money"] = Money.staged_summary(demo["money"], _room.home.today())
		demo["open"] = _demo_due(demo.get("open", []))
		demo["coming"] = _demo_due(demo.get("coming", []))
		_demo_rows = _demo_meetings(demo.get("meetings", []))
		demo["meetings"] = _demo_rows.filter(func(m: Dictionary) -> bool: return m["day"] != "")
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
		watch_timer.timeout.connect(_watch_weather)
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
			_watch_weather()
	get_window().title = "Asterion"
	_apply(_data)
	if not _demo:
		_poll()
	if _room.home.settings.value("widget"):
		_set_widget(true)
	if "--unread" in args:
		_room.home.chat.unread = true
	if "--pet-card" in args:
		var who: String = args[args.find("--pet-card") + 1]
		get_tree().create_timer(0.4).timeout.connect(func() -> void: _on_viewed("pet", who))
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
				_sidebar.focus_chat()
		)
	if "--closet" in args:
		get_tree().create_timer(0.3).timeout.connect(
			func() -> void:
					_open_closet()
					if "--tab" in args:
						_sidebar.closet.pick_tab(args[args.find("--tab") + 1])
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
					_open_add()
					_sidebar.jot.open(text)
					if "--sending" in args:
						_sidebar.jot.sending(true)
		)

	if "--form" in args:
		var form_spec: String = args[args.find("--form") + 1]
		get_tree().create_timer(0.4).timeout.connect(func() -> void: _stage_form(form_spec))
	if "--what-now" in args:
		get_tree().create_timer(0.4).timeout.connect(_what_now)
	if _room.home.drive:
		var at := args.find("--drive") + 1
		var drive := DriveScript.new()
		add_child(drive)
		drive.start(self, int(args[at]) if at < args.size() and args[at].is_valid_int() else 0)
	if _shot != "":
		var wait := float(args[args.find("--wait") + 1]) if "--wait" in args else 1.5
		await get_tree().create_timer(wait).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_shot)
		get_tree().quit()


# the house that is the one running: its heartbeat, its close button, its tray
func _keep_house(args: Array) -> void:
	_kept = true
	var beat := Timer.new()
	beat.wait_time = Background.BEAT
	beat.timeout.connect(
		func() -> void:
			Background.beat(Time.get_unix_time_from_system())
			if Background.shown():
				_show_window()
			for line in Background.told():
				_tell(line, _tell_done.bind(line))
	)
	add_child(beat)
	beat.start()
	if DisplayServer.get_name() == "headless":
		go_headless()
		return
	_apply_background()
	if Background.FLAG in args and _background_on():
		_to_background()


# `--tell "<line>"`: this launch is not a house. It drops the line for the running one, or starts
# one hidden when none beats (it reads the line on its first beat), and quits.
func _hand_over(args: Array) -> void:
	set_process(false)
	var i := args.find(Background.TELL_FLAG) + 1
	var line: String = str(args[i]) if i < args.size() else ""
	if line.strip_edges() != "" and Background.hand(line):
		if not Background.alive(Time.get_unix_time_from_system()):
			OS.create_process(
				OS.get_executable_path(), Background.house_args(OS.get_cmdline_args())
			)
	get_tree().quit()


# the reply to a told line: a desktop notice (the chat line is `_tell`'s own)
func _tell_done(ok: bool, reply: String, line: String) -> void:
	Background.notify(
		OS.get_name(), reply if ok else "couldn't reach the house: \"%s\" not kept" % line
	)


func go_headless() -> void:
	headless = true
	for n in [_room, _sidebar]:
		n.visible = false
		n.process_mode = Node.PROCESS_MODE_DISABLED
	set_process(false)


func _background_on() -> bool:
	return not _room.home.staged and bool(_room.home.settings.value("background"))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_quit.call()
	elif what == NOTIFICATION_EXIT_TREE and _kept:
		Background.release()


func _to_background() -> void:
	if _tray != null:
		get_window().visible = false
	else:
		get_window().mode = Window.MODE_MINIMIZED


func _show_window() -> void:
	if headless:
		return
	var w := get_window()
	w.visible = true
	if w.mode == Window.MODE_MINIMIZED:
		w.mode = Window.MODE_WINDOWED
	w.grab_focus()


# the login entry and the tray follow the setting; a run from the engine (no exported app) has no
# app of its own to start at login
func _apply_background() -> void:
	if _room.home.staged:
		return
	var on := _background_on()
	if OS.has_feature("template"):
		var home := OS.get_environment("HOME" if OS.get_name() != "Windows" else "USERPROFILE")
		var e := Background.entry(
			OS.get_name(), OS.get_executable_path(), home, OS.get_environment("XDG_CONFIG_HOME")
		)
		Background.set_autostart(on, e)
	if on:
		_make_tray()
	elif _tray != null:
		_tray.queue_free()
		_tray = null
		_show_window()


func _make_tray() -> void:
	if _tray != null or not DisplayServer.has_feature(DisplayServer.FEATURE_STATUS_INDICATOR):
		return
	var menu := PopupMenu.new()
	menu.add_item("Show", 0)
	menu.add_item("Hide to tray", 2)
	menu.add_item("Quit", 1)
	menu.id_pressed.connect(
		func(id: int) -> void:
			if id == 0:
				_show_window()
			elif id == 2:
				_to_background()
			else:
				_quit.call()
	)
	add_child(menu)
	var tray := StatusIndicator.new()
	tray.tooltip = "Asterion"
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			if Vector2(x - 15.5, y - 15.5).length() <= 13.0:
				img.set_pixel(x, y, Color("e0b252"))
	tray.icon = ImageTexture.create_from_image(img)
	tray.pressed.connect(
		func(button: int, _at: Vector2i) -> void:
			if button == MOUSE_BUTTON_LEFT:
				_show_window()
	)
	add_child(tray)
	tray.menu = tray.get_path_to(menu)
	_tray = tray


func _use_backend(args: Array) -> void:
	var settings = _room.home.settings
	var at := args.find("--local") + 1
	_fixture = args[at] if at > 0 and at < args.size() else ""
	_probing = settings.fresh and not OS.has_environment("TLON_URL") and not _room.home.drive
	if _fixture == "" and _room.home.drive and not _room.home.drive_server:
		_fixture = "starters"
	_make_backend()


# the list's home: a tlon server, or the house's own file; what was in flight to the old one is lost
func _make_backend() -> void:
	var home = _room.home
	var node: Node
	if home.settings.is_local():
		var local := BackendLocal.new()
		var keep: bool = home.keeps
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
	_backend = node
	_backend.changed.connect(_refresh)
	_backend.told.connect(
		func(row: Dictionary) -> void:
			if _phone_on():
				_phone.on_told(row)
	)
	_backend.told_agenda.connect(
		func(text: String) -> void:
			if _phone_on():
				_phone.on_agenda(text)
	)
	add_child(_backend)
	_sidebar.set_reachable(true)
	_apply_weather()
	_apply_calendar()
	_apply_talk()
	if _backend.local and _phone_on():
		for row in _backend.started:
			_phone.on_told(row)


func _set_up_calendar() -> void:
	var home = _room.home
	_calendar.persist = not home.staged
	_calendar.live = talk_live
	_calendar.load_state()
	_calendar.clock = Callable(home, "_now_local")
	_calendar.bias = home._bias()
	_calendar.fetched.connect(_refresh)
	add_child(_calendar)


# over the house's own list the meetings come from its calendar feed, when one is set
func _apply_calendar() -> void:
	if _backend.local:
		_backend.calendar = _calendar
		_calendar.start()
	else:
		_calendar.stop()


func _set_up_phone() -> void:
	var home = _room.home
	_phone.persist = not home.staged
	_phone.load_state()
	_phone.clock = Callable(home, "_now_local")
	_phone.bias = home._bias()
	_phone.status = func() -> Dictionary:
		if not _backend.local:
			return {}
		var st: Dictionary = _backend.list.status()
		st["notices"] = _backend.bank.notices()
		return st
	_phone.rng.randomize()
	_phone.heard.connect(_phone_heard)
	_phone.tapped.connect(_phone_tapped)
	_phone.moved.connect(_phone_moved)
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
		_backend.bank.live = talk_live
	_phone.live = talk_live
	_phone.list_at = str(settings.value("telegram_list_at"))
	_phone.morning_at = str(settings.value("telegram_morning_at"))
	if _phone_on():
		_phone.start()
	else:
		_phone.stop()


# a new urgent move as a desktop notice, only where Telegram is not paired to carry it
func _desktop_notices() -> void:
	if not (_backend.local and talk_live):
		return
	var home = _room.home
	var rings := _notices.fresh(
		_backend.list.status().get("moves", []),
		get_window().has_focus(),
		str(home.settings.value("telegram_list_at")),
		str(home.settings.value("telegram_morning_at")),
		home._now_local()
	)
	if _phone_on() and _phone.is_paired():
		return
	for m in rings:
		Notices.raise(OS.get_name(), m)


func _phone_on() -> bool:
	return _backend.local and talk_live and _room.home.settings.value("telegram")


# a line from the paired chat goes the way the chat's own do, marked as from the phone
func _phone_heard(text: String, finish: Callable) -> void:
	_tell(
		text,
		func(ok: bool, reply: String) -> void: finish.call(reply if ok else "I couldn't keep that."),
		"phone"
	)


func _phone_moved(key: String, choice: String, finish: Callable) -> void:
	_settle_move(key, choice, finish)


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
			_watch_weather()
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
		"agendas": d.get("agendas", []),
		"people": d.get("people", []),
		"door": d.get("door", {"id": null, "notes": []}),
		"money": d.get("money"),
		"proposals": d.get("proposals", []),
		"moves": d.get("moves", []),
		"forecast": d.get("forecast", []),
		"meetings": d.get("meetings", []),
	}


# `--forecast none|JSON`: the card's days for a picture, JSON rows as the server's with `in_days`
# (0 is today) where a date would go, so a staged forecast never goes stale
func _staged_forecast(spec: String) -> Array:
	var rows: Variant = JSON.parse_string(spec) if spec != "none" else []
	return _dated(rows) if rows is Array else []


# the month's meetings for the calendar view: from the server, or in the demo from `_demo_rows`
func _fetch_meetings(key: String, from: String, to: String) -> void:
	var things = _room.home.things
	if _demo:
		things.set_meetings(
			key, _demo_rows.filter(func(m: Dictionary) -> bool: return m["date"] >= from and m["date"] <= to)
		)
		return
	_backend.fetch(
		"/api/home/meetings?from=%s&to=%s" % [from, to],
		func(reached: bool, code: int, body: Variant) -> void:
			if reached and code == 200 and body is Array:
				things.set_meetings(key, body)
	)


# the forecast the Money view opens with: from the server, in the demo staged from `money_forecast`
func _fetch_forecast(gen: int) -> void:
	var view = _sidebar.money_ui
	if _demo:
		var staged: Dictionary = Money.staged_forecast(_money_spec, _room.home.today())
		view.got_forecast.call_deferred(gen, true, 200, staged)
		return
	_backend.fetch(
		"/api/home/money/forecast",
		func(reached: bool, code: int, body: Variant) -> void:
			view.got_forecast(gen, reached, code, body)
	)


# the operator cleared a notice: the server forgets it; the demo has no server to tell
func _notice_seen(key: String) -> void:
	if not _demo:
		_post("/api/home/money/notices/seen", {"key": key}, func(_r, _c, _b) -> void: pass)



# demo meetings are `{title, mins, tentative}` with `in_min` (minutes from now), `tomorrow`
# (local "HH:MM") or `in_days` (and `from`, or `all_day`), so the demo never goes stale: the
# server's rows, UTC, with their local `date` and, for today and tomorrow, their `day`
func _demo_meetings(rows: Array) -> Array:
	var today := Time.get_unix_time_from_datetime_string(_room.home.today() + "T00:00:00")
	var bias: float = _room.home._bias()
	var out: Array = []
	for row in rows:
		var start: float = Time.get_unix_time_from_system() + float(row.get("in_min", 0)) * 60.0
		var all_day: bool = row.get("all_day", false)
		var hm := str(row.get("tomorrow", row.get("from", "00:00"))).split(":")
		if row.has("tomorrow") or row.has("in_days"):
			var days: int = 1 if row.has("tomorrow") else int(row["in_days"])
			start = today + days * 86400.0 + int(hm[0]) * 3600.0 + int(hm[1]) * 60.0 - bias
		var length: float = 86400.0 if all_day else float(row["mins"]) * 60.0
		var local_day := int((start + bias) / 86400.0)
		var gap := local_day - int(today / 86400.0)
		out.append(
			{
				"title": row["title"],
				"starts_at": Time.get_datetime_string_from_unix_time(int(start)) + "Z",
				"ends_at": Time.get_datetime_string_from_unix_time(int(start + length)) + "Z",
				"tentative": row.get("tentative", false),
				"all_day": all_day,
				"date": Time.get_date_string_from_unix_time(int(start + bias)),
				"day": "today" if gap == 0 else ("tomorrow" if gap == 1 else ""),
			}
		)
	return out


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
	if _demo:
		_demo_todos(_data)
	_room.home.set_data(_data)
	var listed: Array = _room.home.things.moves.map(func(m: Dictionary) -> Variant: return m["key"])
	_settling = _settling.filter(func(k: String) -> bool: return k in listed)
	_room.home.chat.sync_moves(_data["moves"], data.get("moves_settled", {}))
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
	_room.show_home()
	if ids != _pick_ids:
		_pick_ids = ids
		_ask_now(true)
	if _room.home.take_attention() and _shot == "":
		DisplayServer.window_request_attention()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var focus := get_viewport().gui_get_focus_owner()
	var typing: bool = focus is LineEdit or focus is TextEdit
	if event.keycode == KEY_ESCAPE:
		_escape(typing)
		return
	if typing or event.ctrl_pressed or event.alt_pressed:
		return
	if _sidebar.view == "moves" and _sidebar.move_key(event.keycode):
		get_viewport().set_input_as_handled()
		return
	if _decorate.active and _decorate.key(event.keycode):
		get_viewport().set_input_as_handled()
		return
	if not _decorate.active and _room.home.key(event.keycode):
		get_viewport().set_input_as_handled()
		return
	match event.keycode:
		KEY_D:
			get_viewport().set_input_as_handled()
			_set_decorate(not _decorate.active)
		KEY_N, KEY_SLASH, KEY_ENTER, KEY_KP_ENTER:
			get_viewport().set_input_as_handled()
			_open_add()
		KEY_C:
			get_viewport().set_input_as_handled()
			_open_closet()
		KEY_I:
			get_viewport().set_input_as_handled()
			_add_thing()
		KEY_COMMA:
			get_viewport().set_input_as_handled()
			_open_settings()
		KEY_K:
			get_viewport().set_input_as_handled()
			_open_chat()
		KEY_H:
			get_viewport().set_input_as_handled()
			_what_now()
		KEY_W:
			get_viewport().set_input_as_handled()
			_set_widget(not _widget)


# Esc: decorating lets go, an open view goes back, else the day's slip is put away
func _escape(typing: bool) -> void:
	if _decorate.active:
		_decorate.key(KEY_ESCAPE)
	elif _sidebar.is_open():
		get_viewport().gui_release_focus()
		_sidebar.back()
	elif typing:
		get_viewport().gui_release_focus()
	else:
		_room.home.dismiss_slip()
	get_viewport().set_input_as_handled()


func _process(_dt: float) -> void:
	var home = _room.home
	var view: String = _sidebar.view
	home.jot_open = view == "add" and _sidebar.jot.visible
	home.closet_open = view == "closet"
	home.decorating = _decorate.active
	home.form_open = _sidebar.takes_text()
	if _widget and view != "home":
		_set_widget(false)
	_fit_room()
	var at_mouse := _room.get_local_mouse_position()
	home.eggs.set_laser(
		Input.is_key_pressed(KEY_P)
		and not home.jot_open
		and not home.closet_open
		and not _decorate.active
		and Rect2(Vector2.ZERO, _room.size).has_point(at_mouse),
		at_mouse
	)
	if _drag:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			get_window().position = _drag_win + (DisplayServer.mouse_get_position() - _drag_mouse)
		else:
			_drag = false
			_save_widget()


# the room takes the window but for the sidebar, drawn as large as whole steps of its art allow
func _fit_room() -> void:
	var area := Vector2(size.x - (0.0 if _widget else float(Sidebar.WIDTH)), size.y)
	var s: float = _room.fit_scale(area)
	_room.scale = Vector2(s, s)
	_room.position = Vector2.ZERO
	_room.size = area / s


func _set_decorate(on: bool) -> void:
	if on == _decorate.active:
		return
	if on and _widget:
		return
	if on and not _room.home.layout.art:
		_room.home.reply_text = "decorating needs the art, and it was not found"
		_room.home.reply_left = 4.0
		return
	if on:
		_sidebar.open_decorate()
	else:
		_sidebar.back()


func _on_viewed(kind: String, arg: Variant) -> void:
	match kind:
		"item":
			_sidebar.open_item(int(arg))
		"agenda":
			_sidebar.open_agenda(int(arg))
		"open":
			_sidebar.open_desk()
		"add":
			_open_add()
		"closet":
			_open_closet()
		"chat":
			_open_chat()
		"pet":
			_sidebar.open_pet(str(arg))
		"people":
			_sidebar.open_people()
		"door":
			_sidebar.open_door()
		"money":
			_sidebar.open_money()


func _on_empty() -> void:
	if _widget:
		_begin_drag()
	elif _sidebar.is_open() and not _decorate.active:
		_sidebar.back()


func _open_settings() -> bool:
	return _show(func() -> void: _sidebar.open_settings())


func _open_chat() -> bool:
	return _show(func() -> void: _sidebar.focus_chat())


func _open_closet() -> bool:
	return _show(func() -> void: _sidebar.open_closet())


func _open_add() -> bool:
	return _show(func() -> void: _sidebar.open_add())


# the home view of the sidebar is where every view opens, from the room only
func _show(open: Callable) -> bool:
	_set_widget(false)
	open.call()
	return true


# mode "new" (a preset for the form) or "edit" ({row, due})
func _open_form(mode: String, spec: Dictionary) -> bool:
	_set_widget(false)
	_sidebar.open_form(mode, spec)
	_room.home.form_open = true
	return true


func _add_thing() -> void:
	_open_add()


# H: the Now line on the home view, asked again from the top
func _what_now() -> void:
	_skip = []
	if _sidebar.view != "home":
		_sidebar.back()
	_ask_now(true)


func _ask_now(quiet: bool = false) -> void:
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
			elif not quiet:
				_trouble(_why(reached, code, parsed)),
		8.0
	)


func _show_pick(pick: Variant, say: String) -> void:
	if pick == null:
		_skip = []
	_room.home.show_pick(pick if pick is Dictionary else {}, say)
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
	_sidebar.form.fill(fill)
	if kv.has("error"):
		_sidebar.form.fail(kv["error"])





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
	_sidebar.visible = not on
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
		"got":
			_write("/api/home/%d/done" % id, {}, _then(ok, func() -> void: _got(id)))
		"delete":
			_write("/api/home/%d/drop" % id, {}, _then(ok, func() -> void: _gone(id)))
		"revive":
			_write("/api/home/%d/revive" % id, {}, ok)
		"propose_take", "propose_no":
			var verb := "take" if what == "propose_take" else "dismiss"
			_write("/api/home/proposals/%d/%s" % [id, verb], {}, ok)
		"nottoday":
			var close := func() -> void: _ask_now(true)
			_write("/api/home/%d/answer" % id, {"choice": "nottoday"}, _then(ok, close))
		"else":
			_skip.append(id)
			_ask_now(true)
		"hour", "tomorrow":
			_later(id, what, ok)
		"now":
			for item in _data["open"]:
				if int(item["id"]) == id:
					_room.home.focus.set_now(id, str(item["text"]))
		"unnow":
			_room.home.focus.clear()
		"closet":
			_open_closet()
		"jot":
			_open_add()
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
			_sidebar.set_reachable(reached)
			if reached:
				_writes += 1
				_refresh()
			if reached and code == 200:
				if ok.is_valid():
					ok.call()
			else:
				_trouble(_why(reached, code, parsed))
	)


# a go, a no or an answer on an item of Your move; a go that opens a link opens it here. `finish`,
# when given, is told the answer, `{ok}` or `{error}`.
func _settle_move(key: String, choice: Variant, finish: Callable = Callable()) -> void:
	if _demo:
		if finish.is_valid():
			finish.call({"error": "not in the demo"})
		return
	if key in _settling:
		if finish.is_valid():
			finish.call({"error": "already settled"})
		return
	_settling.append(key)
	_post(
		"/api/home/moves/settle",
		{"key": key, "choice": choice},
		func(reached: bool, code: int, parsed: Variant) -> void:
			if not (reached and code == 200):
				_settling.erase(key)
			_sidebar.set_reachable(reached)
			if reached:
				_refresh()
			if reached and code == 200:
				if parsed is Dictionary and parsed.get("open") != null:
					OS.shell_open(str(parsed["open"]))
			else:
				_trouble(_why(reached, code, parsed))
			if finish.is_valid():
				finish.call(
					parsed if reached and code == 200 else {"error": _why(reached, code, parsed)}
				)
	)


func _form_saved() -> void:
	_room.home.sound.request("save")
	_sidebar.form_done()


static func _why(reached: bool, code: int, parsed: Variant) -> String:
	if not reached:
		return "couldn't reach tlon - nothing was changed"
	if code == 400 and parsed is Dictionary and parsed.get("error") is String:
		return parsed["error"]
	if code == 404:
		return "that one is not there any more"
	if code == 409:
		return "that one could not be added just now - it is still there"
	return "tlon answered %d" % code


# one line where he is looking: the form, else the open card, else a slip
func _trouble(line: String) -> void:
	_room.home.sound.request("error")
	if _sidebar.form.visible:
		_sidebar.form.fail(line)
	elif _sidebar.chat_view.acting >= 0:
		_sidebar.chat_view.flash(line)
	elif _room.home.card.is_open():
		_room.home.things.flash = line
	elif _sidebar.view in ["people", "door"]:
		_sidebar.people_ui.said(line)
	elif _sidebar.view == "money":
		_sidebar.money_ui.say = line
	else:
		_room.home.show_reply(line)


# read the room again now; one already on its way may have started before the change
func _refresh() -> void:
	if _demo:
		return
	if _busy:
		_again = true
	else:
		_poll()


func _got(id: int) -> void:
	_room.home.sound.request("delete")
	var at := Time.get_datetime_string_from_system(true) + "Z"
	for t in _data["waiting"]:
		if int(t["id"]) == id and _data.get("done") is Array:
			_data["done"] = [{"text": t["text"], "done_at": at}] + _data["done"]
	var before: int = _data["waiting"].size()
	_data["waiting"] = _data["waiting"].filter(func(t): return int(t["id"]) != id)
	if _data["waiting"].size() < before:
		_data["done_week"] = int(_data.get("done_week", 0)) + 1
	_apply(_data)


func _gone(id: int) -> void:
	_room.home.sound.request("delete")
	for key in ["open", "coming", "waiting", "someday", "projects"]:
		_data[key] = _data[key].filter(func(t): return int(t["id"]) != id)
	_data["note_rows"] = _data["note_rows"].filter(func(t): return int(t["id"]) != id)
	for p in _data["people"]:
		p["notes"] = p["notes"].filter(func(t): return int(t["id"]) != id)
	_data["door"]["notes"] = _data["door"]["notes"].filter(func(t): return int(t["id"]) != id)
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
	elif path == "/api/home/door/add":
		_demo_door(body)
	elif parts.size() == 5 and parts[4] == "drop":
		_gone(int(parts[3]))
	elif parts.size() == 6 and parts[3] == "proposals":
		_demo_proposal(int(parts[4]), parts[5])
	elif parts.size() >= 4 and parts[3] == "agendas":
		_demo_agenda(parts, body)


func _demo_proposal(id: int, verb: String) -> void:
	for p in _data["proposals"]:
		if int(p["id"]) != id:
			continue
		if verb == "take":
			_demo_ids += 1
			var row := {"id": _demo_ids, "kind": "todo", "text": p["text"], "due_at": null}
			_data["open"] = _data["open"] + [row]
		_data["proposals"] = _data["proposals"].filter(func(x): return int(x["id"]) != id)
		break
	_apply(_data)


# a staged agenda's `in_days` and `at` ("14:00") stand where its `next_at` would, so a demo never goes stale
func _demo_agendas(rows: Array) -> Array:
	var today := Time.get_unix_time_from_datetime_string(_room.home.today() + "T00:00:00")
	var bias := float(Time.get_time_zone_from_system()["bias"]) * 60.0
	return rows.map(
		func(row: Dictionary) -> Dictionary:
			if not row.has("in_days"):
				return row
			var at := str(row["at"]).split(":")
			var local := today + int(row["in_days"]) * 86400 + int(at[0]) * 3600 + int(at[1]) * 60
			return row.merged({"next_at": Time.get_datetime_string_from_unix_time(int(local - bias)) + "Z"})
	)


# a demo row's `in_days` and local `at` ("HH:MM") become its UTC `due_at`, so the demo never goes stale
func _demo_due(rows: Array) -> Array:
	var today := Time.get_unix_time_from_datetime_string(_room.home.today() + "T00:00:00")
	var bias: float = _room.home._bias()
	return rows.map(
		func(row: Dictionary) -> Dictionary:
			if not row.has("in_days"):
				return row
			var at := str(row["at"]).split(":")
			var local := today + int(row["in_days"]) * 86400 + int(at[0]) * 3600 + int(at[1]) * 60
			return row.merged({"due_at": Time.get_datetime_string_from_unix_time(int(local - bias)) + "Z"})
	)


func _demo_agenda(parts: PackedStringArray, body: Dictionary) -> void:
	var agendas: Array = _data["agendas"]
	var people: Array = _data["people"]
	if parts.size() == 4:
		_demo_ids += 1
		if body.get("kind") == "person":
			var birthday: Variant = body.get("birthday")
			people.append(_demo_person(_demo_ids, str(body["name"]), birthday))
		else:
			agendas.append(
				{"id": _demo_ids, "name": str(body["name"]), "every": null, "next_at": null, "notes": []}
			)
	else:
		for a in agendas + people:
			if int(a["id"]) != int(parts[4]):
				continue
			match parts[5]:
				"add":
					_demo_ids += 1
					var since := Time.get_datetime_string_from_system(true) + "Z"
					a["notes"].append({"id": _demo_ids, "text": str(body["text"]), "since": since})
				"clear":
					a["notes"] = []
				"edit":
					if body.has("name"):
						a["name"] = str(body["name"])
					if body.has("birthday") and a.has("birthday"):
						a.merge(_demo_birthday(body["birthday"]), true)
				"drop":
					agendas.erase(a)
					people.erase(a)
			break
	_apply(_data)


# a person made in the demo: the birthday as the server keeps it and the date it next falls
func _demo_person(id: int, name: String, birthday: Variant) -> Dictionary:
	var person := {"id": id, "name": name, "notes": [], "todos": []}
	return person.merged(_demo_birthday(birthday))


func _demo_birthday(birthday: Variant) -> Dictionary:
	var next := People.next_birthday(birthday, _room.home.today())
	return {"birthday": birthday, "next_birthday": next if next != "" else null}


func _demo_door(body: Dictionary) -> void:
	var door: Dictionary = _data["door"]
	if door["id"] == null:
		_demo_ids += 1
		door["id"] = _demo_ids
	_demo_ids += 1
	var since := Time.get_datetime_string_from_system(true) + "Z"
	door["notes"].append({"id": _demo_ids, "text": str(body["text"]), "since": since})
	_apply(_data)


# `--money quiet|short|none`: nothing due soon, a balance that will not cover it, no bank at all
func _stage_money(demo: Dictionary, mode: String) -> void:
	match mode:
		"none":
			demo.erase("money")
		"quiet":
			demo["money"]["due_this_week"] = []
		"short":
			demo["money"]["available"] = SHORT_CENTS
			_money_spec["start_cents"] = SHORT_CENTS


# a staged person's `birthday_in_days` stands where its birthday would, so a demo never goes stale
func _demo_people(rows: Array) -> Array:
	var today: String = _room.home.today()
	return rows.map(
		func(row: Dictionary) -> Dictionary:
			if not row.has("birthday_in_days"):
				return _demo_birthday(row.get("birthday")).merged(row, true).merged({"todos": []})
			var at := Time.get_unix_time_from_datetime_string(today + "T00:00:00")
			var date := Time.get_date_string_from_unix_time(
				int(at) + int(row["birthday_in_days"]) * 86400
			)
			var out := row.duplicate()
			out.erase("birthday_in_days")
			return out.merged({"birthday": date.substr(5), "next_birthday": date, "todos": []})
	)


# the demo's own to-dos that name a person, as the server finds them
func _demo_todos(data: Dictionary) -> void:
	for p in data["people"]:
		p["todos"] = (data["open"] + data["coming"]).filter(
			func(t: Dictionary) -> bool: return People.names(str(t["text"]), str(p["name"]))
		)


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
			_sidebar.set_reachable(code > 0)
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
	var jot = _sidebar.jot
	jot.sending(true)
	var done := func(ok: bool, _reply: String) -> void:
		if ok:
			_room.home.sound.request("save")
			_room.home.pets.nudge("desk", "jot")
		else:
			jot.fail("couldn't reach tlon — not kept")
			_room.home.sound.request("error")
	_tell(text, done, "", _sidebar.show_kept)


# A line to the home, from the notepad or the chat: both are kept in the chat's history. `done`
# gets (reached, the reply); the room is read again at once.
func _tell(text: String, done: Callable, via: String = "", kept: Callable = Callable()) -> void:
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
			if body is Dictionary and body.get("open") is String:
				OS.shell_open(body["open"])
			if kept.is_valid():
				kept.call(_made(body), reply)
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
		var sent := {"text": text}
		if chat.last_move() != "" and via == "":
			sent["last"] = chat.last_move()
		_post("/api/home", sent, finished, 60.0)


# the row the answer to a jot carries, {} when it made none; a note's row has no kind
static func _made(body: Variant) -> Dictionary:
	if not (body is Dictionary and body.get("row") is Dictionary):
		return {}
	var row: Dictionary = body["row"]
	return row if row.has("kind") else {"kind": "note"}.merged(row)


func _send_chat(text: String) -> void:
	_tell(text, func(ok: bool, _reply: String) -> void: _sidebar.chat_view.finish(ok, text))


# a button under a told reminder: the same routes the paper menu calls
func _chat_act(id: int, what: String) -> void:
	_act(
		id,
		what,
		func() -> void:
			_room.home.chat.resolve(id, what)
			_sidebar.chat_view.acting = -1
	)


func _check_server(url: String) -> void:
	if _demo:
		_sidebar.settings_view.url_result(true)
		return
	var probe := BackendHttp.new()
	add_child(probe)
	probe.check(
		url,
		func(ok: bool) -> void:
			probe.queue_free()
			_sidebar.settings_view.url_result(ok)
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
			_refresh()
		"cat", "dog", "pet1", "pet2", "pet1_personality", "pet2_personality":
			_pets_changed()
		"on_top":
			if _widget:
				get_window().always_on_top = _room.home.settings.value("on_top")
		"claude", "claude_command", "telegram", "telegram_list_at", "telegram_morning_at":
			_apply_talk()
		"background":
			_apply_background()


func _poll() -> void:
	if _busy or _probing:
		return
	_busy = true
	_poll_gen = _writes
	_backend.fetch("/api/home", _on_polled, 4.0)


func _on_polled(reached: bool, code: int, body: Variant) -> void:
	_busy = false
	if _again:
		_again = false
		_poll.call_deferred()
	var parsed: Variant = body if code == 200 else null
	var ok: bool = reached and parsed is Dictionary
	if ok:
		_data = _home_data(parsed)
		_room.home.sync_chat(_data)
		if _phone_on():
			_phone.sync(
				_data["open"]
				. filter(func(t): return t.get("told_at") != null)
				. map(func(t): return int(t["id"]))
			)
			_phone.on_moves(get_window().has_focus())
		_desktop_notices()
	_sidebar.set_reachable(ok)
	if ok:
		_apply(_data)
		_loaded_gen = maxi(_loaded_gen, _poll_gen)
		_room.home.chore_reload(_loaded_gen)



func _on_ticked(id: int) -> void:
	_act(id, "done")


func _slow_poll() -> void:
	if _slow_step != "" or _probing or _backend.local:
		return
	_slow_step = "settings"
	_backend.fetch("/api/settings", _on_slow, 8.0)


func _on_slow(reached: bool, code: int, body: Variant) -> void:
	_slow_step = ""
	var parsed: Variant = body if code == 200 else null
	if reached and parsed is Dictionary:
		for knob in parsed.get("knobs", []):
			_room.home.knobs[str(knob.get("key"))] = knob.get("value")
			if knob.get("key") == "home_list_at":
				_room.home.set_list_at(str(knob.get("value", "")))


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


func _watch_weather() -> void:
	if _watch_busy or _probing or _backend.local:
		return
	_watch_busy = true
	_backend.fetch("/api/office", _on_watch, 6.0)


func _on_watch(reached: bool, code: int, body: Variant) -> void:
	_watch_busy = false
	var parsed: Variant = body if code == 200 else null
	if reached and parsed is Dictionary:
		_room.home.set_weather(parsed.get("weather"))


func _remove(id: int) -> void:
	var chore: bool = _demo and _room.home.chore_thing_of(id) != ""
	var found := false
	for key in ["open", "coming"]:
		found = found or _data[key].any(func(t): return int(t["id"]) == id)
	_room.home.tick_off(id, -1 if _demo else _writes)
	var at := Time.get_datetime_string_from_system(true) + "Z"
	for t in _data["open"]:
		if int(t["id"]) == id and _data.get("done") is Array:
			_data["done"] = [{"text": t["text"], "done_at": at}] + _data["done"]
	if chore:
		_demo_repeat(id)
	var kept: Array = _data["open"].filter(func(t): return int(t["id"]) != id)
	if found:
		_data["done_week"] = int(_data.get("done_week", 0)) + 1
	_data["open"] = kept
	_apply(_data)
	_room.home.chore_reload(_loaded_gen)


# the demo has no server to move a repeating chore to its next time
func _demo_repeat(id: int) -> void:
	for key in ["open", "coming"]:
		for row in _data[key]:
			if int(row["id"]) != id:
				continue
			var gap: float = Chores.interval(str(row["every"]))
			if gap <= 0.0:
				return
			var due := Time.get_unix_time_from_datetime_string(str(row["due_at"]).trim_suffix("Z"))
			var now: float = _room.home._now_local() - _room.home._bias()
			due += gap
			while due <= now:
				due += gap
			row["due_at"] = Time.get_datetime_string_from_unix_time(int(due)) + "Z"
			row["told_at"] = null
			_data[key] = _data[key].filter(func(t): return int(t["id"]) != id)
			_data["coming"] = _data["coming"] + [row]
			return


# `--settings "key=value;scroll;armed=reset"` (keys name cat dog birthday widget), for a picture
func _put_staged(spec: String) -> void:
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


func _stage_settings(spec: String) -> void:
	_put_staged(spec)
	_open_settings()
	for p in spec.split(";", false):
		match p.get_slice("=", 0):
			"scroll":
				var to := p.substr(p.find("=") + 1) if "=" in p else ""
				_sidebar.scroll.scroll_vertical = int(to) if to != "" else 100000
			"armed":
				_sidebar.settings_view.sure.ask(p.get_slice("=", 1))


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
		_sidebar.chat_view.reading = true
	_open_chat()
	if "fail" in kinds:
		_sidebar.chat_view.finish(false, "buy stamps")
