extends Control

const POLL_SECONDS := 5.0
const SLOW_SECONDS := 300.0
const PANEL_WIDTH := 300
const BACKDROP := Color("1f1b24")
const RoomScript := preload("res://room.gd")
const ORDER := ["waiting", "working", "idle", "cold", "off"]
const LIVE := ["waiting", "working", "idle"]
const WAITING_SHOWN := 5

var _demo := false
var _shot := ""
var _base := "http://127.0.0.1:4040"

var _data := {"open": [], "coming": [], "notes": []}
var _office := {}
var _at := "home"
var _inflight := ""
var _reach := {}
var _busy := false
var _slow: HTTPRequest
var _slow_step := ""
var _pets_retried := false

var _room: Control
var _panel: PanelContainer
var _http: HTTPRequest


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
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
	add_child(_panel)

	_add_note(Control.PRESET_BOTTOM_LEFT, "Art by Gridwright")
	if not _room.art_found:
		_add_note(Control.PRESET_TOP_LEFT, "art not found")

	if _demo:
		var demo: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://demo.json"))
		_office = demo.get("office", {})
		if "--empty" in args:
			demo.merge({"open": [], "coming": [], "notes": []}, true)
		_room.home.set_weather(demo.get("weather"))
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


func _apply(data: Dictionary) -> void:
	_data = {
		"open": data.get("open", []),
		"coming": data.get("coming", []),
		"notes": data.get("notes", []),
	}
	_room.home.set_data(_data)
	if _at == "home":
		_room.show_home()
		_panel.show_data(_data)


func _toggle() -> void:
	_enter("office" if _at == "home" else "home")


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		get_viewport().set_input_as_handled()
		_toggle()


func _enter(where: String) -> void:
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
	var polled := _inflight
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8()) if code == 200 else null
	var ok: bool = result == HTTPRequest.RESULT_SUCCESS and parsed is Dictionary
	_reach[polled] = ok
	if ok:
		if polled == "home":
			_data = {
				"open": parsed.get("open", []),
				"coming": parsed.get("coming", []),
				"notes": parsed.get("notes", []),
			}
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
	if _demo:
		_remove(id)
		return
	var req := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(
		func(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
			req.queue_free()
			if result == HTTPRequest.RESULT_SUCCESS and code == 200:
				_remove(id)
			else:
				_panel.set_reachable(result == HTTPRequest.RESULT_SUCCESS)
				_apply(_data)
	)
	req.request(
		_base + "/api/home/%d/done" % id,
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		"{}"
	)


func _slow_poll() -> void:
	if _slow_step != "":
		return
	_slow_step = "office"
	if _slow.request(_base + "/api/office") != OK:
		_slow_step = ""


func _on_slow(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var step := _slow_step
	_slow_step = ""
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8()) if code == 200 else null
	if result != HTTPRequest.RESULT_SUCCESS or not parsed is Dictionary:
		return
	if step == "office":
		_room.home.set_weather(parsed.get("weather"))
		for w in parsed.get("workspaces", []):
			if w.get("name") == "Home":
				_slow_step = "pets"
				if _slow.request(_base + "/api/office/pets/%d" % int(w["id"])) != OK:
					_slow_step = ""
	elif step == "pets":
		_room.home.set_voices(parsed)
		if parsed.is_empty() and not _pets_retried:
			_pets_retried = true
			get_tree().create_timer(45.0).timeout.connect(_slow_poll)


func _remove(id: int) -> void:
	_room.home.tick_off(id)
	var kept: Array = _data["open"].filter(func(t): return int(t["id"]) != id)
	_data["open"] = kept
	_apply(_data)
