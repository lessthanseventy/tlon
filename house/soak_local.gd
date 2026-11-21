extends "res://logic_local.gd"

const BackendLocal := preload("res://backend_local.gd")

# The routes with the local list behind them, as the soak's stub is behind the server's: it logs
# every request as the stub does and answers an error when the soak asks for one. With `frozen` it
# applies each request to the list for its answer, then puts the list back as it was seeded, so a
# section written against a server that holds still reads the same here.
class Frozen:
	extends "res://backend_local.gd"
	var soak
	var log: Array = []
	var baseline := ""
	var frozen := true

	# no clock of its own: a section written against a server that holds still sees none move
	func _ready() -> void:
		pass

	func freeze() -> void:
		baseline = JSON.stringify(list.doc)

	func fetch(path: String, cb: Callable, timeout: float = 8.0) -> void:
		log.append(["GET", path, ""])
		super(path, cb, timeout)

	func send(path: String, body: Dictionary, cb: Callable, timeout: float = 6.0) -> void:
		log.append(["POST", path, JSON.stringify(body)])
		var edits: bool = path == "/api/home/add" or path.get_slice("/", 4) in ["edit", "plan", "revive", "answer"]
		if edits and soak._mode == "400":
			_deliver.call_deferred(cb, {"code": 400, "body": {"error": "at is more than a year back"}})
		elif (edits and soak._mode == "404") or (path == "/api/home" and soak._fail_jot):
			_deliver.call_deferred(cb, {"code": 404, "body": null})
		else:
			super(path, body, cb, timeout)
			if frozen:
				list.adopt(JSON.parse_string(baseline))


# the soak's status-shaped state as the things of a list
func doc_of(state: Dictionary, bias: float) -> Dictionary:
	var things: Array = []
	var since := "2026-11-18T14:00:00Z"
	var top := 1000
	for key in ["open", "coming", "someday"]:
		for row in state.get(key, []):
			var project: Variant = row.get("project")
			things.append(
				{
					"id": row["id"], "kind": row["kind"], "text": row["text"],
					"state": "someday" if key == "someday" else "open",
					"since": row.get("since", since) if row.get("since") != null else since,
					"due_at": row.get("due_at"), "every": row.get("every"), "every_day": null,
					"told_at": row.get("told_at"), "nudges": 0 if row.get("told_at") == null else 1,
					"project_id": project["id"] if project is Dictionary else null,
					"who": null, "plan": [], "done_at": null, "hidden_until": null,
				}
			)
	for row in state.get("waiting", []):
		things.append(
			{
				"id": row["id"], "kind": "waiting", "text": row["text"], "state": "open",
				"since": since, "who": row.get("who"), "due_at": null, "every": null,
				"told_at": null, "nudges": 0, "project_id": null, "plan": [],
			}
		)
	for row in state.get("projects", []):
		things.append(
			{
				"id": row["id"], "kind": "project", "text": row["text"], "state": "open",
				"since": since, "plan": row.get("plan", []), "due_at": null, "every": null,
				"told_at": null, "nudges": 0, "project_id": null, "who": null,
			}
		)
		if row.get("next") != null:
			things.append(
				{
					"id": row["next"]["id"], "kind": "todo", "text": row["next"]["text"],
					"state": "open", "since": since, "due_at": null, "every": null,
					"told_at": null, "nudges": 0, "project_id": row["id"], "who": null, "plan": [],
				}
			)
		for text in row.get("steps_done", []):
			top += 1
			things.append(
				{
					"id": top, "kind": "todo", "text": text, "state": "done", "since": since,
					"done_at": since, "due_at": null, "every": null, "told_at": null,
					"nudges": 0, "project_id": row["id"], "who": null, "plan": [],
				}
			)
	for text in state.get("notes", []):
		top += 1
		things.append(
			{
				"id": top, "kind": "note", "text": text, "state": "open", "since": since,
				"due_at": null, "every": null, "told_at": null, "nudges": 0, "project_id": null,
				"who": null, "plan": [],
			}
		)
	return {"v": 1, "next_id": 2000, "things": things}


var _frozen: Frozen
var _main


func push_state() -> void:
	_frozen.list.adopt(doc_of(s._state, _main._room.home._bias()))
	_frozen.freeze()


# the forms and the chat, run again with the local list behind the room instead of the server
func over(main) -> void:
	await _frozen_pass(main)
	await _real_pass(main)


func _frozen_pass(main) -> void:
	var FormSoak := preload("res://soak_forms.gd")
	var ChatSoak := preload("res://soak_chat.gd")
	_main = main
	var server_log: Array = s._log
	var server_state: Dictionary = s._state
	t = at(2026, 12, 1, 10)
	_frozen = Frozen.new()
	_frozen.soak = s
	_frozen.setup("", Callable(self, "_clock"), main._room.home._bias(), false)
	main._install(_frozen)
	s.served = false
	s._local = self
	s._log = _frozen.log
	s._state = {
		"open": [
			{"id": 1, "kind": "todo", "text": "buy milk", "due_at": null, "every": null},
			{"id": 2, "kind": "todo", "text": "send photos", "due_at": null, "every": null},
		],
		"coming": [], "notes": ["a note"], "done_week": 0,
		"projects": [
			{"id": 61, "kind": "project", "text": "Move", "plan": ["a", "b"], "steps_done": [],
			"next": {"id": 62, "text": "book the van"}}
		],
	}
	push_state()
	main._poll()
	await s._until(func(): return main._data["open"].size() == 3, "the local list fills the room")
	_eq(main._data["open"].size(), 3, "the local list fills the room: two to-dos and a project's step")
	await FormSoak.new(s, main).run()
	await ChatSoak.new(s, main).run()
	await preload("res://soak_sidebar.gd").new(s, main).shelf_local()
	s.served = true
	s._local = null
	s._log = server_log
	s._state = server_state


func _wait() -> void:
	await s._answered(_main)


func _texts(rows: Array) -> Array:
	return rows.map(func(r): return r["text"] if r is Dictionary else r)


# the room over the local list for real: requests change the list, answers come a frame later,
# a reminder coming due rings, and the choice of where applies at once
func _real_pass(main) -> void:
	var h = main._room.home
	t = at(2026, 11, 18, 14)
	var plain := BackendLocal.new()
	plain.setup("", Callable(self, "_clock"), h._bias(), false)
	main._install(plain)
	var said: Array = []
	plain.replied.connect(func(line: String, reply: String) -> void: said.append([line, reply]))
	var told: Array = []
	plain.told.connect(func(row: Dictionary) -> void: told.append(row["id"]))
	var got: Array = []
	plain.send(
		"/api/home/add",
		{"kind": "todo", "text": "buy milk"},
		func(reached: bool, code: int, body: Variant) -> void: got.append([reached, code, body["text"]])
	)
	_eq(got, [], "an answer comes on a later frame, never inside the call")
	await s._until(func(): return not got.is_empty(), "the add's answer arrives")
	_eq(got, [[true, 200, "buy milk"]], "and is the route's answer, reached")
	got = []
	plain.fetch("/api/nowhere", func(reached: bool, code: int, _b: Variant) -> void: got.append([reached, code]))
	plain.send("/api/home/abc/done", {}, func(reached: bool, code: int, _b: Variant) -> void: got.append([reached, code]))
	plain.send("/api/home", {"text": " "}, func(_r: bool, code: int, b: Variant) -> void: got.append([code, b["error"]]))
	await s._until(func(): return got.size() == 3, "the three answers arrive")
	_eq(got, [[true, 404], [true, 404], [400, "text is required"]], "unknown routes are 404, a blank line 400")
	var pets: Array = []
	plain.fetch("/api/home/pets", func(_r: bool, code: int, b: Variant) -> void: pets.append([code, b]))
	await s._until(func(): return not pets.is_empty(), "the pets' answer arrives")
	_eq(pets, [[200, {}]], "the pets' lines: an empty batch, so the house's own are used")
	main._poll()
	await _wait()
	main._open_add()
	main._send_jot("remind me to stretch at 3pm")
	await _wait()
	_eq([main._sidebar.jot._summary.text.begins_with("Reminder"), main._sidebar.jot._said.text], [true, "stretch"], "the pad reads back what the reader made")
	_eq(said.back(), ["remind me to stretch at 3pm", "Reminder set: stretch, today 15:00."], "the reply is announced for a bot to send")
	var talk: Array = h.chat.messages.filter(func(m): return m["who"] in ["me", "home"])
	var tail: Array = talk.slice(-2).map(func(m): return [m["who"], m["text"]])
	_eq(tail, [["me", "remind me to stretch at 3pm"], ["home", "Reminder set: stretch, today 15:00."]], "the chat keeps both")
	_eq(_texts(main._data["coming"]), ["stretch"], "the reminder is coming")
	main._send_jot("what's left")
	await _wait()
	_eq(main._sidebar.jot._said.text, "Still open: buy milk.\nToday: stretch at 15:00.", "what's left is read back as the reply")
	main._send_jot("done buy milk")
	await _wait()
	_eq([main._sidebar.jot._said.text, main._data["open"].size(), main._data["done_week"]], ["Done: buy milk.", 0, 1], "done by a loose line")
	main._write("/api/home/add", {"kind": "todo", "text": "send photos"})
	await _wait()
	var photos: int = main._data["open"][0]["id"]
	main._on_act(photos, "hour")
	await _wait()
	_eq([main._data["open"].size(), _texts(main._data["coming"])], [0, ["stretch", "send photos"]], "in an hour moves it to coming")
	main._on_act(photos, "done")
	await _wait()
	_eq(main._data["coming"].size(), 1, "done on a thing in coming")
	main._write("/api/home/add", {"kind": "todo", "text": "water"})
	main._write("/api/home/add", {"kind": "todo", "text": "mail"})
	await _wait()
	main._what_now()
	await _wait()
	_eq([h.things.pick["text"], h.things.pick["why"]], ["water", "it has sat the longest"], "what now")
	h.things.act("pk_else")
	await _wait()
	_eq(h.things.pick["text"], "mail", "something else skips the first")
	h.things.act("pk_not")
	await _wait()
	main._what_now()
	await _wait()
	_eq(h.things.pick["text"], "water", "not today hides the thing")
	h.card.close()
	# the room says nothing is wrong
	_eq([main._sidebar._status.visible, h.reply_text.contains("reach")], [false, false], "no word of a server that is not there")
	main._pets_ask()
	main._slow_poll()
	main._watch_weather()
	await _wait()
	_eq([main._slow_step, main._watch_busy, h.has_voices()], ["", false, false], "no server asks are made, and the pets use their own lines")
	# a reminder comes due, and again
	h.chat.messages = []
	var tea: int = plain.list.add({"kind": "reminder", "text": "tea", "at": "2026-11-18T15:00"})["body"]["id"]
	t = at(2026, 11, 18, 15)
	told.clear()
	_eq(plain.list.tick(), true, "a reminder due is told")
	plain.changed.emit()
	await _wait()
	var first: Variant = h._rang.get(tea)
	_eq([told.filter(func(i): return i == tea), h.ring_ids.has(tea), h.chat.messages.filter(func(m): return m.get("id") == tea).size()], [[tea], true, 1], "the house rings and the chat tells it")
	t = at(2026, 11, 18, 15, 29)
	plain.list.tick()
	t = at(2026, 11, 18, 15, 30)
	h._rang_new = false
	plain.list.tick()
	plain.changed.emit()
	await _wait()
	_eq([told.filter(func(i): return i == tea).size(), h.chat.messages.filter(func(m): return m.get("id") == tea).size()], [2, 2], "told again after half an hour: a new nudge in the chat")
	_eq([h._rang.get(tea) != first, h._rang.get(tea) == _row_of(main, tea)["told_at"]], [true, true], "and the house rings again: once per told_at")
	main._on_act(tea, "done")
	await _wait()
	_eq(h.ring_ids.has(tea), false, "done stops it")
	await preload("res://soak_sidebar.gd").new(s, main).local_agendas()
	t = at(2026, 11, 18, 14)
	await _where(main)
	await _first_start(main)


func _where(main) -> void:
	var h = main._room.home
	var settings = h.settings
	var f := FileAccess.open(FILE, FileAccess.WRITE)
	var doc := {"v": 1, "next_id": 4, "things": [
		{"id": 1, "kind": "todo", "text": "one", "state": "open", "since": "2026-11-17T10:00:00Z"},
		{"id": 2, "kind": "todo", "text": "two", "state": "open", "since": "2026-11-17T11:00:00Z"},
		{"id": 3, "kind": "note", "text": "a note", "state": "open", "since": "2026-11-17T11:00:00Z"},
	]}
	f.store_string(JSON.stringify(doc))
	f.close()
	var before := FileAccess.get_file_as_string(FILE)
	main._fixture = FILE
	settings.put("where", "local")
	_eq(main._backend.local, true, "choosing this computer applies at once")
	main._poll()
	await _wait()
	_eq([_texts(main._data["open"]), main._data["notes"]], [["one", "two"], ["a note"]], "the room reads the list file")
	settings.put("where", "server")
	_eq([main._backend.local, main._backend.base], [false, settings.server_url()], "choosing a server applies at once")
	main._poll()
	await _wait()
	_eq(_texts(main._data["open"]).has("one"), false, "and the room reads the server")
	_eq(FileAccess.get_file_as_string(FILE), before, "the list file is not touched by the switch")
	settings.put("where", "local")
	main._poll()
	await _wait()
	_eq(_texts(main._data["open"]), ["one", "two"], "and is there when the house comes back")
	var v = main._sidebar.settings_view
	v.open()
	_eq([v._server_box.visible, v._local_say.visible, v._where_local.button_pressed], [false, true, true], "the settings show this computer")
	_eq(v._local_say.text, "kept in " + ProjectSettings.globalize_path(LocalList.STORE), "and where the file is kept")
	v._where_server.pressed.emit()
	v._refresh()
	_eq([settings.value("where"), v._server_box.visible, v._local_say.visible, v._where_server.button_pressed], ["server", true, false, true], "the choice of a server in the settings")
	v._where_local.pressed.emit()
	v._refresh()
	_eq(settings.value("where"), "local", "and back to this computer")
	v.close()
	# a list that cannot be read: said once, the house starts empty
	f = FileAccess.open(FILE, FileAccess.WRITE)
	f.store_string("{nope")
	f.close()
	h.reply_text = ""
	settings.put("where", "server")
	settings.put("where", "local")
	_eq(h.reply_text, "the list could not be read, so the house starts empty", "an unreadable list is said")
	main._poll()
	await _wait()
	_eq([main._data["open"].size(), FileAccess.file_exists(FILE)], [0, true], "and the house starts empty, the staged run having moved nothing")
	h.reply_text = ""
	main._poll()
	await _wait()
	_eq(h.reply_text, "", "only once")
	_wipe()
	main._fixture = ""
	settings.put("where", "server")


func _first_start(main) -> void:
	var h = main._room.home
	var settings = h.settings
	main._backend.base = "http://127.0.0.1:1"
	main._probing = true
	main._first_start()
	await s._until(func(): return not main._probing, "the first-start probe ends")
	_eq([main._backend.local, settings.value("where"), main._probing], [true, "local", false], "no server at the default address: the house keeps its own list")
	main._poll()
	await _wait()
	_eq(_texts(main._data["open"]), ["say hello to the cat"], "a few gentle things to start: a to-do")
	_eq(_texts(main._data["coming"]), ["water the plant"], "a weekly reminder")
	_eq([main._data["coming"][0]["every"], main._data["notes"]], ["week", ["press I to add something, K to chat"]], "and a note")
	settings.put("where", "server")
	main._backend.base = "http://127.0.0.1:%d" % s._srv.get_local_port()
	main._probing = true
	main._first_start()
	await s._until(func(): return not main._probing, "the first-start probe ends")
	_eq([main._backend.local, settings.value("where")], [false, "server"], "a server at the default address: the house stays with it")
	settings.put("where", "server")


func _row_of(main, id: int) -> Dictionary:
	for row in main._data["open"]:
		if int(row["id"]) == id:
			return row
	return {}
