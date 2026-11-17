extends Control

const POLL_SECONDS := 5.0
const PANEL_WIDTH := 300
const BACKDROP := Color("1f1b24")

var _demo := false
var _shot := ""
var _base := "http://127.0.0.1:4040"

var _data := {"open": [], "coming": [], "notes": []}
var _busy := false

var _room: Control
var _panel: PanelContainer
var _http: HTTPRequest


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_demo = "--demo" in args
	if "--shot" in args:
		_shot = args[args.find("--shot") + 1]
	_base = OS.get_environment("TLON_URL") if OS.has_environment("TLON_URL") else _base

	var bg := ColorRect.new()
	bg.color = BACKDROP
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_room = preload("res://room.gd").new()
	_room.set_anchors_preset(Control.PRESET_FULL_RECT)
	_room.offset_right = -PANEL_WIDTH
	_room.art_dir = _art_dir()
	add_child(_room)

	_panel = preload("res://panel.gd").new()
	_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_panel.offset_left = -PANEL_WIDTH
	_panel.offset_right = 0
	_panel.ticked.connect(_on_ticked)
	add_child(_panel)

	_add_note(Control.PRESET_BOTTOM_LEFT, "Art by Gridwright")
	if not _room.art_found:
		_add_note(Control.PRESET_TOP_LEFT, "art not found")

	if _demo:
		_apply(JSON.parse_string(FileAccess.get_file_as_string("res://demo.json")))
	else:
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

	if _shot != "":
		await get_tree().create_timer(1.5).timeout
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
	_room.open_count = _data["open"].size()
	_room.queue_redraw()
	_panel.show_data(_data)


func _poll() -> void:
	if _busy:
		return
	_busy = true
	if _http.request(_base + "/api/home") != OK:
		_busy = false
		_panel.set_reachable(false)


func _on_polled(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_busy = false
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8()) if code == 200 else null
	if result == HTTPRequest.RESULT_SUCCESS and parsed is Dictionary:
		_panel.set_reachable(true)
		_apply(parsed)
	else:
		_panel.set_reachable(false)


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


func _remove(id: int) -> void:
	var kept: Array = _data["open"].filter(func(t): return int(t["id"]) != id)
	_data["open"] = kept
	_apply(_data)
