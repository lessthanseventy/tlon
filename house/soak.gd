extends SceneTree

const Pets := preload("res://pets.gd")
const Look := preload("res://look.gd")
const Person := preload("res://person.gd")

var _srv := TCPServer.new()
var _conns: Array = []
var _log: Array = []
var _fail_jot := false
var _failures: Array = []
var _state := {
	"open":
	[
		{"id": 1, "kind": "todo", "text": "buy milk", "due_at": null, "every": null},
		{"id": 2, "kind": "todo", "text": "send photos", "due_at": null, "every": null},
	],
	"coming": [],
	"notes": ["a note"],
	"done_week": 0,
}


func _initialize() -> void:
	_run.call_deferred()


func _process(_dt: float) -> bool:
	_serve()
	return false


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures.append(what)
		print("FAIL: ", what)


func _run() -> void:
	await _routes()
	_soak()
	_looks()
	print("SOAK %s (%d failures)" % ["OK" if _failures.is_empty() else "FAILED", _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _soak() -> void:
	var pets := Pets.new()
	var look := Look.new()
	var person := Person.new()
	pets.setup("", 11)
	person.setup(pets, look, 5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var last := {}
	var still := {}
	var busy := 0.0
	var steps := 0
	var chair_cells := 0
	var dt := 0.1
	var settle := 0.0
	person.snap()
	while steps < 360000:
		steps += 1
		if steps % 600 == 1:
			person.open_n = rng.randi_range(0, 4)
			person.tv = ["", "playing", "paused"][rng.randi_range(0, 2)]
			person.ring = rng.randf() < 0.2
			person.hour = rng.randf_range(0.0, 24.0)
			person.calm = rng.randf() < 0.7
			person.has_notes = rng.randf() < 0.6
			pets.tv_on = person.tv == "playing"
			if rng.randf() < 0.1:
				person.stretch()
			settle = 0.0
		settle += dt
		pets.freeze = false
		pets.process(dt)
		person.process(dt, false)
		for c in pets.critters:
			var cell := Vector2i(int(floor(c.pos.x)), int(floor(c.pos.y)))
			var on_floor: bool = c.z <= 0.0 and c.jump.is_empty()
			var seat_ok: bool = (
				c.id == "person" and (person.seated or person.phase in ["leaving", "entering"])
			)
			if on_floor and not seat_ok:
				if cell == Pets.CHAIR:
					chair_cells += 1
				if cell.x < 1 or cell.y < 1 or cell.x >= Pets.COLS or cell.y >= Pets.ROWS:
					_check(false, "%s on a blocked cell %s at step %d" % [c.id, cell, steps])
					return
			var p: Vector2 = c.pos
			if c.mode == "walk" and last.get(c.id) == p:
				still[c.id] = still.get(c.id, 0.0) + dt
				if still[c.id] > 3.0:
					_check(false, "%s walking but not moving at step %d" % [c.id, steps])
					return
			else:
				still[c.id] = 0.0
			last[c.id] = p
		if person.phase == "idle":
			busy = 0.0
			if settle > 20.0:
				_check(
					person.act == person.base(),
					"person act %s != base %s (step %d)" % [person.act, person.base(), steps]
				)
		else:
			busy += dt
			if busy > 40.0:
				_check(
					false,
					(
						"person stuck in phase %s going to %s at step %d"
						% [person.phase, person.next, steps]
					)
				)
				return
	_check(chair_cells == 0, "someone stood in the chair cell %d times" % chair_cells)
	print(
		(
			"soak: %d steps (%.1f simulated hours), person act %s"
			% [steps, steps * dt / 3600.0, person.act]
		)
	)


func _looks() -> void:
	var art := OS.get_environment("TLON_ART_DIR")
	if art == "":
		art = OS.get_environment("HOME").path_join("projects/thatch/packs/x")
	var look := Look.new()
	look.setup(art)
	if not look.layered:
		print("looks: creator pack not found, composition not tested")
		return
	print("looks: %d recipes, slots %s" % [look.recipes.size(), look.opts.keys()])
	for r in look.recipes:
		var img := look._compose(r["cfg"], "")
		var seen := false
		for x in range(0, 256, 4):
			for y in range(0, 64, 2):
				if img.get_pixel(x, y).a > 0.5:
					seen = true
		_check(seen, "recipe %s composes to an empty sheet" % r["name"])
	var closet: Control = load("res://closet.gd").new()
	root.add_child(closet)
	closet.open(look)
	for i in closet._rows.size():
		for d in [1, 1, -1]:
			closet._step(i, d)
			_check(look.preview(closet._work, 4) != null, "preview after row %d" % i)
	closet._random()
	_check(look.preview(closet._work, 2) != null, "preview after random")
	closet.queue_free()


func _routes() -> void:
	await process_frame
	_srv.listen(4999, "127.0.0.1")
	OS.set_environment("TLON_URL", "http://127.0.0.1:4999")
	var main: Control = load("res://main.gd").new()
	root.add_child(main)
	await create_timer(1.5).timeout
	_check(
		main._data["open"].size() == 2,
		"GET /api/home filled the room (%d open)" % main._data["open"].size()
	)
	main._on_act(1, "done")
	await create_timer(1.0).timeout
	_check(_seen("POST", "/api/home/1/done"), "done posted")
	_check(main._data["open"].size() == 1, "done removed the thing")
	main._on_act(2, "hour")
	await create_timer(1.0).timeout
	_check(_seen("POST", "/api/home/2/later", "hour"), "later posted with until=hour")
	_check(
		main._data["open"].is_empty() and main._data["coming"].size() == 1,
		"later moved the thing to coming"
	)
	main._jot.open("buy stamps")
	main._send_jot("buy stamps")
	await create_timer(1.0).timeout
	_check(_seen("POST", "/api/home", "buy stamps"), "jot posted")
	_check(
		main._room.home.reply_text == "to do: buy stamps",
		"reply shown: '%s'" % main._room.home.reply_text
	)
	_check(not main._jot.visible, "jot hid after a reply")
	_fail_jot = true
	main._jot.open("keep me")
	main._send_jot("keep me")
	await create_timer(1.0).timeout
	_check(
		main._jot.visible and main._jot._edit.text == "keep me",
		"failed jot keeps its text in the field"
	)
	_check("not kept" in main._jot._hint.text, "failed jot says so: '%s'" % main._jot._hint.text)
	var tv = main._room.home.tv
	tv.poll()
	await create_timer(1.0).timeout
	tv.collect()
	print(
		(
			"tv: state='%s' player='%s' caption='%s' raw=%s"
			% [tv.state, tv.player, tv.caption, JSON.stringify(tv.last_raw)]
		)
	)
	main._room.home.exit()
	_srv.stop()


func _seen(method: String, path: String, body_has: String = "") -> bool:
	for l in _log:
		if l[0] == method and l[1] == path and (body_has == "" or body_has in str(l[2])):
			return true
	return false


func _serve() -> void:
	if _srv.is_listening() and _srv.is_connection_available():
		_conns.append({"p": _srv.take_connection(), "buf": PackedByteArray()})
	for c in _conns.duplicate():
		var p: StreamPeerTCP = c["p"]
		p.poll()
		if p.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_conns.erase(c)
			continue
		var n := p.get_available_bytes()
		var buf: PackedByteArray = c["buf"]
		if n > 0:
			buf.append_array(p.get_data(n)[1])
			c["buf"] = buf
		var text := buf.get_string_from_utf8()
		var split := text.find("\r\n\r\n")
		if split < 0:
			continue
		var head := text.substr(0, split)
		var body := text.substr(split + 4)
		var length := 0
		for line in head.split("\r\n"):
			if line.to_lower().begins_with("content-length:"):
				length = int(line.get_slice(":", 1))
		if body.to_utf8_buffer().size() < length:
			continue
		_respond(p, head.get_slice(" ", 0), head.get_slice(" ", 1), body)
		_conns.erase(c)


func _respond(p: StreamPeerTCP, method: String, path: String, body: String) -> void:
	_log.append([method, path, body])
	var code := 200
	var out: Variant = {}
	var parsed: Variant = JSON.parse_string(body) if body != "" else {}
	if method == "GET" and path == "/api/home":
		out = _state
	elif method == "GET" and path == "/api/office":
		out = {"weather": {"kind": "rain", "desc": "Light rain", "temp_c": 9}}
	elif method == "POST" and path.ends_with("/done"):
		var id := int(path.get_slice("/", 3))
		_state["open"] = _state["open"].filter(func(t): return int(t["id"]) != id)
	elif method == "POST" and path.ends_with("/later"):
		var id := int(path.get_slice("/", 3))
		out = {"id": id, "text": "send photos", "due_at": "2026-11-17T20:00:00Z"}
		_state["open"] = _state["open"].filter(func(t): return int(t["id"]) != id)
		_state["coming"] = [
			{"id": id, "kind": "reminder", "text": "send photos", "due_at": out["due_at"]}
		]
	elif method == "POST" and path == "/api/home":
		if _fail_jot:
			code = 404
		else:
			out = {"reply": "to do: " + str(parsed.get("text", ""))}
	else:
		code = 404
	var payload := JSON.stringify(out).to_utf8_buffer()
	var head := (
		"HTTP/1.1 %d X\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n"
		% [code, payload.size()]
	)
	p.put_data(head.to_utf8_buffer() + payload)
	p.disconnect_from_host()
