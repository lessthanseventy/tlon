extends SceneTree

const Pets := preload("res://pets.gd")
const Look := preload("res://look.gd")
const Person := preload("res://person.gd")
const Jar := preload("res://jar.gd")
const Knock := preload("res://knock.gd")
const Door := preload("res://door.gd")
const Rhythm := preload("res://rhythm.gd")
const Hacks := preload("res://hacks.gd")
const Tv := preload("res://tv.gd")

var _srv := TCPServer.new()
var _conns: Array = []
var _log: Array = []
var _fail_jot := false
var _office := {
	"weather": {"kind": "rain", "desc": "Light rain", "temp_c": 9},
	"pause": null,
	"awaiting": 1,
	"bench": [{"name": "lonnrot", "archetype": "reviewer"}],
	"roster": [{"agent": "lonnrot", "status": "waiting", "title": "Review: door", "thread_id": 7}],
	"threads": [{"id": 7, "title": "Review: door", "awaiting": "operator", "prompt": null}],
	"landings": [{"ref": "pr/1", "subject": "first", "landed_at": "2026-11-09T23:05:14Z"}],
}
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
	_logic()
	_soak()
	_looks()
	await _hacks_draw()
	await _routes()
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
			person.ring = rng.randf() < 0.2
			person.hour = rng.randf_range(0.0, 24.0)
			person.calm = rng.randf() < 0.7
			person.has_notes = rng.randf() < 0.6
			pets.tv_on = rng.randf() < 0.5
			if rng.randf() < 0.15:
				pets.cheer(pets.critter("argos"), "desk_stand", 3, "cheer")
			if rng.randf() < 0.1:
				pets.knock(pets.critter("nina"))
			if rng.randf() < 0.05:
				person.arrive(rng.randf() < 0.5)
				pets.cheer(pets.critter("argos"), "door", 3, "greet")
			pets.settle_near(rng.randf() < 0.15)
			if rng.randf() < 0.1:
				person.stretch()
			settle = 0.0
		settle += dt
		pets.freeze = false
		pets.process(dt)
		pets.events = []
		person.process(dt, false)
		for c in pets.critters:
			var cell := Vector2i(int(floor(c.pos.x)), int(floor(c.pos.y)))
			var on_floor: bool = c.z <= 0.0 and c.jump.is_empty()
			var seat_ok: bool = (
				c.id == "person"
				and (
					person.seated
					or person.phase in ["leaving", "entering"]
					or (person.arrive_left > 3.0 and cell == Vector2i(0, 7))
				)
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
	# The 30 s blocking soak leaves the engine catching up for a few frames; an HTTPRequest made
	# in them times out at once (measured: result TIMEOUT, no frame between request and failure).
	# Waiting 30 frames lets it settle, so the routes pass in any order.
	for _i in 30:
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
	var home = main._room.home
	_check(
		is_equal_approx(home.rhythm.list_at, 9.25),
		"home_list_at read from /api/settings (%s)" % home.rhythm.list_at
	)
	_check(
		not home.door.want.is_empty() and home.door.want["name"] == "lonnrot",
		"the waiting coworker comes from /api/office"
	)
	_check(home.door.plane.is_empty(), "the first landings only prime the door")
	_office["awaiting"] = 0
	_office["roster"] = []
	_office["threads"] = []
	_office["landings"] = [
		{"ref": "pr/2", "subject": "second", "landed_at": "2026-11-10T01:00:00Z"},
		{"ref": "pr/1", "subject": "first", "landed_at": "2026-11-09T23:05:14Z"},
	]
	main._watch_door()
	await create_timer(1.0).timeout
	_check(home.door.want.is_empty(), "nobody leans in once nothing awaits")
	_check(
		not home.door.plane.is_empty() and home.door.plane["title"] == "second",
		"a new landing sends a plane"
	)
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
		out = _office
	elif method == "GET" and path == "/api/settings":
		out = {"knobs": [{"key": "home_list_at", "value": "09:15"}]}
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


func _iso(days_ago: float) -> String:
	var at := Time.get_unix_time_from_system() - days_ago * 86400.0
	return Time.get_datetime_string_from_unix_time(int(at)) + "Z"


func _art() -> String:
	if OS.has_environment("TLON_ART_DIR"):
		return OS.get_environment("TLON_ART_DIR")
	return OS.get_environment("HOME").path_join("projects/thatch/packs/x")


func _unix(text: String) -> float:
	return Time.get_unix_time_from_datetime_string(text)


func _logic() -> void:
	_jar_logic()
	_knock_logic()
	_rhythm_logic()
	_door_logic()
	_tv_logic()
	_home_logic()
	_night_logic()


func _jar_logic() -> void:
	var monday := Jar.week_key(_unix("2026-11-16T09:00:00"))
	_check(Jar.week_key(_unix("2026-11-22T23:00:00")) == monday, "Sunday is in its Monday's week")
	_check(Jar.week_key(_unix("2026-11-23T00:30:00")) != monday, "Monday starts a new week")
	var jar := Jar.new()
	jar.set_count(4, monday)
	_check(jar.shown == 4 and jar.drops.is_empty(), "the first count shows at once")
	jar.set_count(5, monday)
	_check(jar.drops.size() == 1 and jar.shown == 4, "one more done queues one drop")
	for i in 20:
		jar.process(0.05)
	_check(jar.shown == 5 and jar.drops.is_empty(), "the drop lands and the jar holds it")
	jar.set_count(60, monday)
	_check(jar.shown == Jar.CAP, "the drawn marbles are capped")
	jar.set_count(2, monday + 7)
	_check(jar.shown == 2 and jar.drops.is_empty(), "a new week starts again, quietly")
	var a := Jar.new()
	var b := Jar.new()
	var c := Jar.new()
	a.set_count(1, monday)
	b.set_count(1, monday)
	c.set_count(1, monday + 7)
	var same := true
	var differs := false
	for i in Jar.CAP:
		same = same and a.colour(i) == b.colour(i)
		differs = differs or a.colour(i) != c.colour(i)
	_check(same, "a week's colours are the same every time")
	_check(differs, "another week has other colours")


func _knock_logic() -> void:
	var now := Time.get_unix_time_from_system()
	var old := {"id": 1, "since": _iso(5.0), "due_at": null}
	var older := {"id": 2, "since": _iso(9.0), "due_at": null}
	var fresh := {"id": 3, "since": _iso(1.0), "due_at": null}
	var future := {"id": 4, "since": _iso(20.0), "due_at": _iso(-1.0)}
	_check(Knock.oldest([old, older, fresh], now) == 2, "the oldest open thing is the one")
	_check(Knock.oldest([fresh], now) == -1, "nothing under three days is knocked")
	_check(Knock.oldest([future, fresh], now) == -1, "a thing with a future due is never knocked")
	_check(Knock.oldest([future, old], now) == 1, "a future due is passed over for the next oldest")
	var k := Knock.new()
	k.persist = false
	_check(k.candidate([old], now, 12.0, false) == 1, "by day the old sticky is a candidate")
	_check(k.candidate([old], now, 12.0, true) == -1, "never at night")
	_check(k.candidate([old], now, 7.0, false) == -1, "never before the morning")
	_check(k.candidate([old], now, 22.0, false) == -1, "never late in the evening")
	k.last = now - 3600.0
	_check(k.candidate([old], now, 12.0, false) == -1, "at most once every few hours")
	k.last = now - 5.0 * 3600.0
	_check(k.candidate([old], now, 12.0, false) == 1, "after the gap it can again")
	k.pending = 1
	_check(k.candidate([old], now, 12.0, false) == -1, "not while one is on its way")
	k.pending = -1
	k.id = 1
	_check(k.candidate([old], now, 12.0, false) == -1, "one knocked sticky at a time")
	k.clear()
	var pets := Pets.new()
	pets.setup("", 3)
	var nina := pets.critter("nina")
	pets.knock(nina)
	var swats := 0
	for i in 400:
		pets.process(0.1)
		for ev in pets.events:
			swats += 1 if ev == "swat" else 0
		pets.events = []
	_check(swats == 1, "Nina swats once (%d)" % swats)
	_check(nina.spot == "knocked", "Nina ends beside the sticky (%s)" % nina.spot)


func _rhythm_logic() -> void:
	_check(Rhythm.parse_time("17:30") == 17.5, "17:30 parses")
	_check(Rhythm.parse_time("") == -1.0 and Rhythm.parse_time("later") == -1.0, "no time, no beat")
	_check(Rhythm.home_due(17.6, 17.5, "", "d"), "home beat is due after the list time")
	_check(not Rhythm.home_due(17.4, 17.5, "", "d"), "not before it")
	_check(not Rhythm.home_due(17.6, 17.5, "d", "d"), "not twice a day")
	_check(not Rhythm.home_due(21.0, 17.5, "", "d"), "not hours after")
	_check(not Rhythm.home_due(17.6, -1.0, "", "d"), "not when the list is off")
	_check(Rhythm.morning_due(9.0, 9.0, "", "d"), "first run after 05:30 is a morning")
	_check(not Rhythm.morning_due(6.0, 4.0, "", "d"), "running since before 05:30 waits for 08:00")
	_check(Rhythm.morning_due(8.1, 4.0, "", "d"), "the clock passing 08:00 is a morning")
	_check(not Rhythm.morning_due(8.1, 4.0, "d", "d"), "once a day")
	_check(not Rhythm.morning_due(13.0, 13.0, "", "d"), "no morning in the afternoon")
	var r := Rhythm.new()
	r.persist = false
	_check(r.due(9.0, "d1") == "morning", "the morning comes")
	_check(r.due(9.1, "d1") == "", "and not again that day")
	_check(r.due(17.6, "d1") == "home", "then the homecoming")
	_check(r.due(17.7, "d1") == "", "and not again")
	_check(r.due(9.0, "d2") == "morning", "the next day it all comes back")


func _door_logic() -> void:
	var waiting := _office.duplicate(true)
	var v := Door.visitor(waiting)
	_check(v.get("name") == "lonnrot" and v.get("text") == "Review: door", "a waiting coworker leans in")
	var asked := {
		"threads":
		[{"id": 9, "title": "t", "awaiting": null, "prompt": {"summary": "run it?"}, "lead": "yu"}],
		"bench": [{"name": "yu"}],
		"roster": [],
	}
	_check(Door.visitor(asked).get("text") == "asks: run it?", "a prompt is the caption")
	waiting["pause"] = "pencils_down"
	_check(Door.visitor(waiting).is_empty(), "a paused office sends nobody")
	var quiet := {"awaiting": 0, "roster": [], "threads": [], "bench": []}
	_check(Door.visitor(quiet).is_empty(), "nothing waits, nobody comes")
	var d := Door.new()
	d.update_office(_office)
	for i in 30:
		d.process(0.1)
	_check(d.present(), "the coworker is at the door")
	d.update_office(quiet)
	for i in 30:
		d.process(0.1)
	_check(d.lean == 0.0 and d.shown.is_empty() and not d.present(), "and leaves when nothing waits")
	d = Door.new()
	d.update_office({"landings": [{"ref": "a", "subject": "s"}]})
	_check(d.plane.is_empty(), "landings seen at the start send nothing")
	var two := {"landings": [{"ref": "b", "subject": "t"}, {"ref": "a", "subject": "s"}]}
	d.update_office(two)
	_check(not d.plane.is_empty() and d.plane["title"] == "t", "a new landing flies in")
	d.dismiss_plane()
	d.update_office(two)
	_check(d.plane.is_empty(), "a dismissed plane does not come again")


func _tv_logic() -> void:
	var tv := Tv.new()
	tv.setup(5)
	tv.process(0.1, false, false)
	_check(not tv.on, "the TV is off when nobody watches")
	tv.process(0.1, true, false)
	_check(tv.on, "it is on while he watches")
	tv.process(0.1, true, true)
	_check(not tv.on, "it is off in the deep night")
	tv.process(0.1, false, false)
	tv.click()
	tv.process(0.1, false, false)
	_check(tv.on, "a click turns it on")
	var before: String = tv.hacks.current
	tv.click()
	_check(tv.hacks.current != before, "a click changes the channel")
	_check(Hacks.NAMES.size() >= 8, "at least eight hacks")
	var seen := {}
	var last: String = tv.hacks.current
	for i in 400:
		tv.hacks.advance()
		_check(tv.hacks.current != last, "never the same hack twice in a row")
		seen[tv.hacks.current] = true
		last = tv.hacks.current
	_check(seen.size() == Hacks.NAMES.size(), "every hack comes up")
	for n in Hacks.NAMES:
		_check(tv.hacks.has_method("_" + n), "hack %s has a drawer" % n)
	var h := Hacks.new()
	h.setup(9)
	var at := 0.0
	var changed: Array = []
	var cur: String = h.current
	for i in 36000:
		h.update(0.1, true)
		at += 0.1
		if h.current != cur:
			changed.append(at)
			cur = h.current
	var spaced := changed.size() > 8
	for i in range(1, changed.size()):
		var gap: float = changed[i] - changed[i - 1]
		spaced = spaced and gap >= 119.0 and gap <= 241.0
	_check(spaced, "a new hack every two to four minutes (%d changes in an hour)" % changed.size())
	var frozen := Hacks.new()
	frozen.setup(9)
	for i in 10:
		frozen.update(0.1, false)
	_check(frozen.t == 0.0, "an off TV runs no clock")


func _room() -> Control:
	var room: Control = load("res://room.gd").new()
	room.art_dir = _art()
	root.add_child(room)
	var h = room.home
	h.knock.persist = false
	h.knock.last = 0.0
	h.rhythm.persist = false
	h.rhythm.days = {"home": "", "morning": ""}
	h.pets.freeze = false
	return room


func _data(items: Array, week: int = 0) -> Dictionary:
	return {"open": items, "coming": [], "notes": [], "done_week": week}


func _thing(id: int, days: float, text: String = "old thing", due: Variant = null) -> Dictionary:
	return {
		"id": id,
		"kind": "todo",
		"text": text,
		"due_at": due,
		"every": null,
		"since": _iso(days),
		"told_at": null
	}


func _run_home(h, seconds: float, until: Callable = Callable()) -> void:
	var t := 0.0
	while t < seconds:
		h.process(0.1)
		t += 0.1
		if until.is_valid() and until.call():
			return


func _home_logic() -> void:
	var room := _room()
	var h = room.home
	h.fake_hour = 12.0
	h.set_data(_data([_thing(1, 8.0)], 3))
	_check(h.jar.total == 3 and h.jar.shown == 3, "the jar starts at the week's count")
	h.set_data(_data([_thing(1, 8.0)], 4))
	_check(h.jar.drops.size() == 1, "one more done drops one marble")
	h.knock.next_check = 0.0
	_run_home(h, 120.0, func(): return h.knock.id >= 0)
	_check(h.knock.id == 1, "Nina knocks the old sticky off (%s)" % h.knock.id)
	_check(not h._slots.has(1), "the knocked sticky leaves the desk")
	h.knock.next_check = 0.0
	_run_home(h, 1.0)
	_check(h.knock.id == 1 and h.knock.pending == -1, "one knocked sticky at a time")
	h.open_item_menu(1)
	_check(h.knock.id == -1 and h._slots.has(1) and h.menu.is_open, "a click gives the paper menu")
	h.menu.close()
	h.knock.last = Time.get_unix_time_from_system()
	h.knock.next_check = 0.0
	_run_home(h, 700.0)
	_check(h.knock.id == -1 and h.knock.pending == -1, "not again within the gap")
	h.knock.last = Time.get_unix_time_from_system() - 5.0 * 3600.0
	h.fake_hour = 2.0
	for i in 8:
		h.knock.next_check = 0.0
		_run_home(h, 60.0)
	_check(h.knock.id == -1 and h.knock.pending == -1, "never at night")
	h.fake_hour = 12.0
	var future := _iso(-2.0)
	h.set_data(_data([_thing(1, 9.0, "old thing", future)]))
	for i in 8:
		h.knock.next_check = 0.0
		_run_home(h, 60.0)
	_check(h.knock.id == -1 and h.knock.pending == -1, "never for a thing due in the future")
	h.set_data(_data([_thing(5, 2.0, "water the plant")]))
	h.tick_off(5)
	_check(h.perk_left > 0.0 and h.water_left > 0.0, "the plant is watered when its reminder is done")
	_check(h.pets.critter("argos").hops > 0, "Argos celebrates a done thing")
	h.knock.last = Time.get_unix_time_from_system()
	h.set_data(_data([]))
	h.rhythm.list_at = 17.5
	h.rhythm.days = {"home": "", "morning": "x"}
	h.fake_hour = 17.6
	h.set_data(_data([_thing(6, 0.2, "pay the thing")]))
	_run_home(h, 1.0)
	_check(h.person.bag == "carry" or h.person.act == "arrive", "he comes home at the list time")
	_run_home(h, 6.0)
	_check(h.rhythm.kind == "home" and h.rhythm.rows.size() == 1, "the slip of what is open unrolls")
	_check(h.rhythm.days["home"] == h._day_key(), "the homecoming is remembered for the day")
	h.dismiss_slip()
	_run_home(h, 2.0)
	_check(h.rhythm.kind == "", "a click or Esc puts the slip away")
	_run_home(h, 300.0)
	_check(h.rhythm.kind == "" and h.person.arrive_left == 0.0, "the homecoming is once a day")
	h.rhythm.days = {"home": h._day_key(), "morning": ""}
	h.rhythm.first_hour = 9.0
	h.fake_hour = 9.0
	_run_home(h, 3.0)
	_check(h.person.stretch_left > 0.0 or h.rhythm.kind == "morning", "he stretches in the morning")
	_check(h.rhythm.days["morning"] == h._day_key(), "the morning is remembered for the day")
	room.queue_free()


func _night_logic() -> void:
	var room := _room()
	var h = room.home
	h.fake_hour = 1.0
	h.set_data(_data([]))
	_run_home(h, 600.0)
	_check(h.person.act == "sleep", "he sleeps late at night (%s)" % h.person.act)
	_check(h.pets.critter("nina").spot == "sofa", "Nina settles on the sofa")
	_check(h.pets.critter("argos").spot == "rug", "Argos settles by him")
	_check(not h.tv.on and h._deep > 0.9, "the TV is off and the lights are low")
	h.person.forced = "tv"
	h.fake_hour = 14.0
	_run_home(h, 8.0)
	_check(h.tv.on, "he turns the TV on when he sits down to watch")
	room.queue_free()


func _hacks_draw() -> void:
	var canvas := Control.new()
	canvas.size = Vector2(200, 120)
	var h := Hacks.new()
	h.setup(1)
	var drawn := []
	canvas.draw.connect(
		func() -> void:
			var q := PackedVector2Array([Vector2(10, 10), Vector2(190, 10), Vector2(190, 110), Vector2(10, 110)])
			for n in Hacks.NAMES:
				h.force(n)
				h.update(1.5, true)
				h.draw(canvas, q)
				drawn.append(n)
	)
	root.add_child(canvas)
	await process_frame
	await process_frame
	_check(drawn.size() >= Hacks.NAMES.size(), "every hack draws (%d)" % drawn.size())
	canvas.queue_free()
