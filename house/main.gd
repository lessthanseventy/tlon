extends Control

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

var pets_retry := 20.0
var pets_every := 300.0
var pets_nudge := 60.0
var pets_window := 180.0

var _demo := false
var _shot := ""
var _base := "http://127.0.0.1:4040"

var _data := {"open": [], "coming": [], "notes": [], "done_week": 0, "done": null}
var _form: PanelContainer
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
var _slow: HTTPRequest
var _slow_step := ""
var _pets_req: HTTPRequest
var _pets_timer: Timer
var _pets_nudged: Timer
var _pets_since := 0.0
var _ids: Array = []
var _ids_known := false
var _watch: HTTPRequest
var _away_at := 0.0

var _room: Control
var _panel: PanelContainer
var _http: HTTPRequest


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
	_base = OS.get_environment("TLON_URL") if OS.has_environment("TLON_URL") else _base

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
		func(req: Dictionary) -> void: _write(req["path"], req["body"], _form.finish)
	)
	_form.acted.connect(func(id: int, what: String) -> void: _act(id, what, _form.finish))
	add_child(_form)
	_room.home.things.form_wanted.connect(_open_form)
	_room.home.things.post.connect(func(path: String, body: Dictionary) -> void: _write(path, body))

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
		_apply(demo)
		if "--tick-demo" in args:
			get_tree().create_timer(0.75).timeout.connect(func(): _on_ticked(1))
			if "--tick-all" in args:
				get_tree().create_timer(1.1).timeout.connect(func(): _on_ticked(2))
				get_tree().create_timer(1.4).timeout.connect(func(): _on_ticked(3))
	else:
		_slow = HTTPRequest.new()
		_slow.timeout = 8.0
		_slow.request_completed.connect(_on_slow)
		add_child(_slow)
		var slow_timer := Timer.new()
		slow_timer.wait_time = SLOW_SECONDS
		slow_timer.timeout.connect(_slow_poll)
		add_child(slow_timer)
		slow_timer.start()
		_slow_poll()
		_pets_req = HTTPRequest.new()
		_pets_req.timeout = 8.0
		_pets_req.request_completed.connect(_on_pets)
		add_child(_pets_req)
		_pets_timer = Timer.new()
		_pets_timer.one_shot = true
		_pets_timer.timeout.connect(_pets_ask)
		add_child(_pets_timer)
		_pets_nudged = Timer.new()
		_pets_nudged.one_shot = true
		_pets_nudged.timeout.connect(_pets_ask)
		add_child(_pets_nudged)
		_pets_ask()
		_watch = HTTPRequest.new()
		_watch.timeout = 6.0
		_watch.request_completed.connect(_on_watch)
		add_child(_watch)
		var watch_timer := Timer.new()
		watch_timer.wait_time = WATCH_SECONDS
		watch_timer.timeout.connect(_watch_door)
		add_child(watch_timer)
		watch_timer.start()
		_watch_door()
		_http = HTTPRequest.new()
		_http.timeout = 4.0
		_http.request_completed.connect(_on_polled)
		add_child(_http)
		_poll()
		var timer := Timer.new()
		timer.wait_time = POLL_SECONDS
		timer.timeout.connect(_poll)
		add_child(timer)
		timer.start()
	_enter(_at)
	if "--widget" in args:
		_set_widget(true)
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


func _art_dir() -> String:
	if OS.has_environment("TLON_ART_DIR"):
		return OS.get_environment("TLON_ART_DIR")
	return OS.get_environment("HOME").path_join("projects/thatch/packs/x")


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
	}


func _apply(data: Dictionary) -> void:
	_data = _home_data(data)
	_room.home.set_data(_data)
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
	_enter("office" if _at == "home" else "home")


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if _closet.visible or _jot.visible or _form.visible or event.ctrl_pressed or event.alt_pressed:
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
	if _form.visible and _form_blocked():
		_form.close()
	_room.home.form_open = _form.visible
	if _form.visible:
		var room_w := size.x - (0 if _widget else PANEL_WIDTH)
		_form.size = _form.get_combined_minimum_size()
		_form.position = ((Vector2(room_w, size.y) - _form.size) / 2.0).round()
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


# mode "new" (a preset for the form) or "edit" ({row, due}); false when something else is up
func _open_form(mode: String, spec: Dictionary) -> bool:
	if _at != "home" or _widget or _form_blocked():
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
	var req := HTTPRequest.new()
	req.timeout = 8.0
	add_child(req)
	var query := "" if _skip.is_empty() else "?skip=" + ",".join(_skip.map(str))
	req.request_completed.connect(
		func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
			req.queue_free()
			var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
			if result == HTTPRequest.RESULT_SUCCESS and code == 200 and parsed is Dictionary:
				_show_pick(parsed.get("pick"), str(parsed.get("say", "")))
			else:
				_trouble(_why(result == HTTPRequest.RESULT_SUCCESS, code, parsed))
	)
	if req.request(_base + "/api/home/now" + query) != OK:
		req.queue_free()
		_trouble(_why(false, 0, null))


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
	w.always_on_top = on
	w.size = WIDGET_SIZE if on else _prev_size
	if on and FileAccess.file_exists(WIDGET_STORE):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(WIDGET_STORE))
		if d is Dictionary:
			w.position = Vector2i(int(d.get("x", 0)), int(d.get("y", 0)))


func _on_act(id: int, what: String) -> void:
	_act(id, what)


# `ok` runs once the server has said yes
func _act(id: int, what: String, ok: Callable = Callable()) -> void:
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
			_later(id, what)
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
	if _form.visible:
		_form.fail(line)
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
	var req := HTTPRequest.new()
	req.timeout = timeout
	add_child(req)
	req.request_completed.connect(
		func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
			req.queue_free()
			done.call(
				result == HTTPRequest.RESULT_SUCCESS,
				code,
				JSON.parse_string(body.get_string_from_utf8())
			)
	)
	if (
		req.request(
			_base + path,
			["Content-Type: application/json"],
			HTTPClient.METHOD_POST,
			JSON.stringify(payload)
		)
		!= OK
	):
		req.queue_free()
		done.call(false, 0, null)


func _later(id: int, until: String) -> void:
	var hours := 1.0 if until == "hour" else 24.0
	var moved := func(_ok: bool, code: int, body: Variant) -> void:
		if code == 200:
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
	var finished := func(ok: bool, code: int, body: Variant) -> void:
		if seq != _jot_seq:
			return
		if ok and code == 200:
			_jot.finish()
			_room.home.sound.request("save")
			var reply := "kept"
			if body is Dictionary and body.get("reply") is String:
				reply = body["reply"]
			_room.home.show_reply(reply)
			if _demo:
				var id: int = 100 + _data["open"].size()
				_data["open"] = _data["open"] + [
					{"id": id, "kind": "todo", "text": text, "due_at": null, "every": null}
				]
				_apply(_data)
			else:
				_poll()
		else:
			_jot.fail("couldn't reach tlon — not kept")
			_room.home.sound.request("error")
	if _demo:
		get_tree().create_timer(1.4).timeout.connect(
			func() -> void: finished.call(true, 200, {"reply": "to do: " + text})
		)
	else:
		_post("/api/home", {"text": text}, finished, 40.0)


func _enter(where: String) -> void:
	_room.home.close_card()
	if where == "home" and _at == "office" and _away_at > 0.0:
		if Time.get_ticks_msec() / 1000.0 - _away_at >= AWAY_FOR_GREETING:
			_room.home.came_back()
	if where == "office":
		_away_at = Time.get_ticks_msec() / 1000.0
	if where == "home" and _watch != null:
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
	if _busy:
		return
	_busy = true
	_inflight = _at
	if _http.request(_base + ("/api/home" if _at == "home" else "/api/office")) != OK:
		_busy = false
		_reach[_inflight] = false
		_panel.set_reachable(false)


func _on_polled(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_busy = false
	if _again:
		_again = false
		_poll.call_deferred()
	var polled := _inflight
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8()) if code == 200 else null
	var ok: bool = result == HTTPRequest.RESULT_SUCCESS and parsed is Dictionary
	_reach[polled] = ok
	if ok:
		if polled == "home":
			_data = _home_data(parsed)
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
	if _slow_step != "":
		return
	_slow_step = "settings"
	if _slow.request(_base + "/api/settings") != OK:
		_slow_step = ""


func _slow_office() -> void:
	_slow_step = "office"
	if _slow.request(_base + "/api/office") != OK:
		_slow_step = ""


func _on_slow(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var step := _slow_step
	_slow_step = ""
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8()) if code == 200 else null
	if step == "settings":
		if result == HTTPRequest.RESULT_SUCCESS and parsed is Dictionary:
			for knob in parsed.get("knobs", []):
				if knob.get("key") == "home_list_at":
					_room.home.set_list_at(str(knob.get("value", "")))
		_slow_office()
		return
	if result != HTTPRequest.RESULT_SUCCESS or not parsed is Dictionary:
		return
	if step == "office":
		_room.home.set_weather(parsed.get("weather"))


func _pets_ask() -> void:
	if _pets_req.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	if not _room.home.has_voices() and _pets_since == 0.0:
		_pets_since = Time.get_ticks_msec() / 1000.0
	if _pets_req.request(_base + "/api/home/pets") != OK:
		_pets_later()


func _on_pets(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8()) if code == 200 else null
	if result == HTTPRequest.RESULT_SUCCESS and parsed is Dictionary and not parsed.is_empty():
		_room.home.set_voices(parsed)
	_pets_later()


func _pets_later() -> void:
	var wait := pets_every
	if _room.home.has_voices():
		_pets_since = 0.0
	elif Time.get_ticks_msec() / 1000.0 - _pets_since < pets_window:
		wait = pets_retry
	_pets_timer.start(wait)


func _watch_door() -> void:
	if _at != "home" or _watch.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	_watch.request(_base + "/api/office")


func _on_watch(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8()) if code == 200 else null
	if result == HTTPRequest.RESULT_SUCCESS and parsed is Dictionary:
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
