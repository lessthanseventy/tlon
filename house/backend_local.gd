extends "res://backend.gd"

# The routes answered by the house's own list (`local_list.gd`), with the loose line read by
# `reader` (`reader_rules.gd`; anything with `read(text, context) -> reading` can stand in front).
const LocalList := preload("res://local_list.gd")
const ReaderRules := preload("res://reader_rules.gd")

var list: RefCounted
var reader: RefCounted = ReaderRules.new()
# when set (`reader_claude.gd`), a loose line is asked of it first; `reader` reads what it cannot
var claude: RefCounted
# the reminders that came due while the house was closed: the first tick tells them before anyone listens
var started: Array = []


func _init() -> void:
	local = true


# the list is read from `path` and, with `keep`, written back there; `clock` is the house's
# local-time clock
func setup(path: String, clock: Callable, bias: float, keep: bool = true) -> void:
	list = LocalList.new(path, clock, bias)
	list.keep = keep
	list.load_file()
	if not keep:
		list.path = ""
	var first := func(row: Dictionary) -> void: started.append(row)
	list.told.connect(first)
	list.tick()
	list.told.disconnect(first)
	list.told.connect(func(row: Dictionary) -> void: told.emit(row))


func _ready() -> void:
	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.timeout.connect(
		func() -> void:
			if list.tick():
				changed.emit()
	)
	add_child(timer)
	timer.start()


func fetch(path: String, cb: Callable, _timeout: float = 8.0) -> void:
	_deliver.call_deferred(cb, _route("GET", path, {}))


func send(path: String, body: Dictionary, cb: Callable, _timeout: float = 6.0) -> void:
	var text := str(body.get("text", ""))
	if claude != null and path == "/api/home" and text.strip_edges() != "":
		claude.ask(
			text, _context(), func(reading: Dictionary) -> void: _deliver(cb, _tell(text, reading))
		)
		return
	_deliver.call_deferred(cb, _route("POST", path, body))


func check(_url: String, cb: Callable) -> void:
	cb.call_deferred(true)


func _deliver(cb: Callable, answer: Dictionary) -> void:
	cb.call(true, answer["code"], answer["body"])


func _route(method: String, path: String, body: Dictionary) -> Dictionary:
	var query := path.get_slice("?", 1) if "?" in path else ""
	var p := path.get_slice("?", 0).split("/", false)
	if p.size() < 2 or p[0] != "api":
		return {"code": 404, "body": null}
	if method == "GET":
		return _read_route(p, query)
	if p.size() == 2 and p[1] == "home":
		return _tell(str(body.get("text", "")))
	if p.size() == 3 and p[2] == "add":
		return list.add(body)
	if p.size() != 4 or not p[2].is_valid_int():
		return {"code": 404, "body": null}
	var id := int(p[2])
	match p[3]:
		"edit":
			return list.edit(id, body)
		"plan":
			return list.plan(id, body)
		"revive":
			return list.revive(id)
		"done":
			return list.done(id)
		"later":
			return list.later(id, body)
		"drop":
			return list.drop(id)
		"answer":
			return list.answer(id, body)
	return {"code": 404, "body": null}


func _read_route(p: PackedStringArray, query: String) -> Dictionary:
	if p.size() == 2 and p[1] == "home":
		return {"code": 200, "body": list.status()}
	if p.size() == 3 and p[1] == "home" and p[2] == "pets":
		return {"code": 200, "body": {}}
	if p.size() == 3 and p[1] == "home" and p[2] == "now":
		var skip := []
		if query.begins_with("skip="):
			for s in query.trim_prefix("skip=").split(",", false):
				skip.append(int(s))
		return list.pick(skip)
	if p.size() == 2 and p[1] == "settings":
		return {"code": 200, "body": {"knobs": []}}
	return {"code": 404, "body": null}


func _context() -> Dictionary:
	return {"now": list.now(), "bias": list.bias, "status": list.status()}


# a loose line: read (by `given`, else the rules), carried out, and answered in the reader's words
func _tell(text: String, given: Dictionary = {}) -> Dictionary:
	if text.strip_edges() == "":
		return {"code": 400, "body": {"error": "text is required"}}
	var reading: Dictionary = given if not given.is_empty() else reader.read(text, _context())
	var said: String = reading["say"]
	var made := {"code": 200}
	match reading["action"]:
		"add":
			made = list.add(reading["body"])
			if made["code"] != 200:
				list.add({"kind": "todo", "text": text})
				said = "To do: %s." % text.strip_edges()
		"done":
			made = list.done(int(reading["id"]))
		"delete":
			made = list.drop(int(reading["id"]))
	if made["code"] == 404:
		said = "That one is not there any more. Nothing changed."
	replied.emit(text, said)
	return {"code": 200, "body": {"reply": said}}
