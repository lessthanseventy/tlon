extends RefCounted

# The soak's check of `drive.gd`: the listener inside the soak's own house, a real TCP client, and
# the work a person does through it (add a to-do, a key, a right click, a drag in decorate, a shot,
# a bad command, what is under a point).
const Drive := preload("res://drive.gd")

var s
var _peer := StreamPeerTCP.new()


func _init(soak) -> void:
	s = soak


func _eq(got: Variant, want: Variant, what: String) -> void:
	s._check(got == want, "drive: %s: got %s, want %s" % [what, str(got), str(want)])


func run() -> void:
	OS.set_environment("TLON_URL", "http://127.0.0.1:9")
	var was: Vector2i = s.root.size
	s.root.size = Vector2i(1100, 700)
	var main: Control = load("res://main.gd").new()
	s.root.add_child(main)
	main.size = Vector2(s.root.size)
	var h = main._room.home
	h.fake_hour = 15.0
	h.settings.forced["where"] = "local"
	main._fixture = "starters"
	main._make_backend()
	var drive := Drive.new()
	main.add_child(drive)
	var port: int = drive.start(main, 0)
	_eq(port > 0, true, "listens on a free port")
	_peer.connect_to_host("127.0.0.1", port)
	for _i in 600:
		await s.process_frame
		_peer.poll()
		if _peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			break
	await _add_a_todo(h)
	await _keys()
	await _pet_card()
	await _decorate(h)
	await _shot()
	await _bad()
	await _at()
	_peer.disconnect_from_host()
	main.queue_free()
	OS.unset_environment("TLON_URL")
	s.root.size = was


func _send(cmd: Variant) -> Dictionary:
	var line: String = cmd if cmd is String else JSON.stringify(cmd)
	_peer.put_data((line + "\n").to_utf8_buffer())
	var buf := ""
	var began := Time.get_ticks_msec()
	while Time.get_ticks_msec() - began < 15000:
		await s.process_frame
		_peer.poll()
		var n := _peer.get_available_bytes()
		if n > 0:
			buf += _peer.get_utf8_string(n)
		if "\n" in buf:
			var reply: Variant = JSON.parse_string(buf.get_slice("\n", 0))
			return reply if reply is Dictionary else {"ok": false, "error": "not JSON"}
	return {"ok": false, "error": "no reply"}


func _control(things: Dictionary, klass: String, key: String, text: String) -> Dictionary:
	for c in things["controls"]:
		if c["class"] == klass and str(c.get(key, "")).begins_with(text):
			return c
	return {}


func _click(at: Array, button: String = "left") -> void:
	await _send({"do": "click", "x": at[0], "y": at[1], "button": button})


func _add_a_todo(h) -> void:
	await _send({"do": "key", "key": "Escape"})
	var things := await _send({"do": "things"})
	_eq(things["ok"], true, "things answers")
	_eq(things["window"].size(), 2, "things names the window size")
	var add := _control(things, "Button", "text", "add")
	_eq(add.is_empty(), false, "things finds the add button")
	if add.is_empty():
		return
	await _click(add["center"])
	await _send({"do": "wait", "seconds": 0.3})
	things = await _send({"do": "things"})
	_eq(things["mode"]["form"], "todo", "the add button opens the to-do form")
	var field := _control(things, "LineEdit", "placeholder", "what is it")
	await _click(field.get("center", [0, 0]))
	await _send({"do": "type", "text": "buy milk"})
	await _send({"do": "key", "key": "Enter"})
	await _send({"do": "wait", "seconds": 0.3})
	var state := await _send({"do": "state"})
	var texts: Array = state["open"].map(func(t: Dictionary) -> String: return t["text"])
	_eq("buy milk" in texts, true, "the typed to-do is in the list (%s)" % str(texts))
	_eq(state["mode"]["form"], "", "and the form is closed")
	_eq(state["errors"], null, "the error count is said to be unknown")
	_eq(h.pets.critters.size() > 1, true, "the room is live")


func _keys() -> void:
	await _send({"do": "key", "key": ","})
	var state := await _send({"do": "state"})
	_eq(state["mode"]["settings"], true, "a key opens settings")
	await _send({"do": "key", "key": "Escape"})
	state = await _send({"do": "state"})
	_eq(state["mode"]["settings"], false, "Escape closes it")


func _pet_card() -> void:
	var things := await _send({"do": "things"})
	var pets: Array = things["registered"].filter(
		func(r: Dictionary) -> bool: return r["key"].begins_with("pet:") and r["reachable"]
	)
	_eq(pets.is_empty(), false, "a pet can be clicked")
	if pets.is_empty():
		return
	await _click(pets[0]["center"], "right")
	var state := await _send({"do": "state"})
	_eq(state["mode"]["pet_card"] != "", true, "a right click on a pet opens the picker")
	await _send({"do": "key", "key": "Escape"})
	state = await _send({"do": "state"})
	_eq(state["mode"]["pet_card"], "", "Escape closes it")


func _piano(state: Dictionary) -> Array:
	for p in state["layout"]:
		if p["p"] == "piano":
			return [p["c"], p["r"]]
	return []


func _decorate(h) -> void:
	await _send({"do": "key", "key": "D"})
	var state := await _send({"do": "state"})
	_eq(state["mode"]["decorate"], true, "D enters decorate mode")
	var before := _piano(state)
	var things := await _send({"do": "things"})
	var piano: Dictionary = {}
	for r in things["registered"]:
		if r["key"] == "furn:piano":
			piano = r
	_eq(before.is_empty() or piano.is_empty(), false, "the piano is in the room")
	if before.is_empty() or piano.is_empty():
		return
	var room = h.room
	var moved := false
	await _send({"do": "drag", "from": piano["center"], "to": [300, 300], "seconds": 0.1})
	for c in 10:
		for r in 10:
			var at: Vector2 = room._p(room._origin, c + 0.5, r + 0.5)
			await _click([at.x, at.y])
			if _piano(await _send({"do": "state"})) != before:
				moved = true
				break
		if moved:
			break
	_eq(moved, true, "a drag picks a piece up and a click puts it down elsewhere")
	await _send({"do": "key", "key": "D"})
	state = await _send({"do": "state"})
	_eq(state["mode"]["decorate"], false, "D leaves decorate mode")


func _shot() -> void:
	var path := ProjectSettings.globalize_path("user://soak_drive.png")
	var reply := await _send({"do": "shot", "path": path})
	if DisplayServer.get_name() == "headless":
		_eq(reply["ok"], false, "a headless run has no picture to save")
		return
	_eq(reply["ok"], true, "shot answers")
	_eq(FileAccess.get_file_as_bytes(path).size() > 0, true, "the PNG is not empty")
	DirAccess.remove_absolute(path)


func _bad() -> void:
	var reply := await _send({"do": "bogus"})
	_eq(reply["ok"], false, "an unknown command is refused")
	_eq(str(reply.get("error", "")).contains("bogus"), true, "and says which")
	reply = await _send("this is not json")
	_eq(reply["ok"], false, "a line that is not JSON is refused")
	reply = await _send({"do": "click", "x": "left"})
	_eq(reply["ok"], false, "a click with no point is refused")
	reply = await _send({"do": "state"})
	_eq(reply["ok"], true, "the house keeps running")


func _at() -> void:
	var things := await _send({"do": "things"})
	var known: Array = things["registered"].filter(
		func(r: Dictionary) -> bool: return r["reachable"] and not r["key"].begins_with("pet:")
	)
	_eq(known.is_empty(), false, "a thing is registered")
	if known.is_empty():
		return
	var reply := await _send({"do": "at", "x": known[0]["center"][0], "y": known[0]["center"][1]})
	_eq(reply["topmost"], known[0]["key"], "at names the thing under its centre")
