extends "res://backend.gd"

# The routes answered by the house's own list (`local_list.gd`), with the loose line read by
# `reader` (`reader_rules.gd`; anything with `read(text, context) -> reading` can stand in front).
const LocalList := preload("res://local_list.gd")
const Moves := preload("res://moves.gd")
const MovesList := preload("res://moves_list.gd")
const MOVES_STORE := "user://house_moves.json"
const ReaderRules := preload("res://reader_rules.gd")
const CalendarFeed := preload("res://calendar_feed.gd")
const Bank := preload("res://bank.gd")
const Ask := preload("res://ask.gd")
const ChatRoute := preload("res://chat_route.gd")
const ChatList := preload("res://chat_list.gd")
const AskModel := preload("res://ask_model.gd")
const BankUtil := preload("res://bank_util.gd")

const E_NOW := "skip is ids joined by commas, minutes a number"
const E_UNTIL := "until is a date as YYYY-MM-DD"
const E_KEY := "key is a bank:new: or bank:price: notice key"
const FORECAST_DAYS := 45
# the server's defaults of the knobs the settings screen reads
const KNOBS := [["home_morning_at", "08:30"], ["home_list_at", "17:30"], ["home_review_on", "sun"]]

var list: RefCounted
# the calendar feed (`calendar_feed.gd`); null answers no meetings
var calendar: Node
var reader: RefCounted = ReaderRules.new()
# when set (`reader_claude.gd`), a loose line is asked of it first; `reader` reads what it cannot
var claude: RefCounted
# the reminders that came due while the house was closed: the first tick tells them before anyone listens
var started: Array = []
# the operator's bank, read-only (`bank.gd`), and the questions asked about it (`ask.gd`)
var bank := Bank.new()
var money_ask := Ask.new()
var _money_thread := ""


func _init() -> void:
	local = true
	money_ask.bank = bank


# the list is read from `path` and, with `keep`, written back there; `clock` is the house's
# local-time clock
func setup(path: String, clock: Callable, bias: float, keep: bool = true) -> void:
	list = LocalList.new(path, clock, bias)
	list.keep = keep
	list.load_file()
	list.moves = Moves.new(MOVES_STORE if keep else "", clock, list)
	list.moves.load_file()
	if not keep:
		list.path = ""
	var first := func(row: Dictionary) -> void: started.append(row)
	list.told.connect(first)
	list.tick()
	list.told.disconnect(first)
	list.told.connect(func(row: Dictionary) -> void: told.emit(row))
	list.told_agenda.connect(func(text: String) -> void: told_agenda.emit(text))
	bank.clock = clock
	bank.bias = bias
	bank.persist = keep
	bank.load_file()


func _ready() -> void:
	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.timeout.connect(
		func() -> void:
			if list.tick():
				changed.emit()
	)
	add_child(bank)
	bank.refreshed.connect(func() -> void: changed.emit())
	add_child(timer)
	timer.start()


func fetch(path: String, cb: Callable, _timeout: float = 8.0) -> void:
	_deliver.call_deferred(cb, _route("GET", path, {}))


func send(path: String, body: Dictionary, cb: Callable, _timeout: float = 6.0) -> void:
	var text := str(body.get("text", ""))
	if path == "/api/home/money/ask" and text.strip_edges() != "":
		money_ask.ask(
			text,
			body.get("thread"),
			func(answer: Dictionary) -> void: _deliver(cb, {"code": 200, "body": answer}),
			_model()
		)
		return
	if path == "/api/home" and text.strip_edges() != "" and _chat(text, body, cb):
		return
	if claude != null and path == "/api/home" and text.strip_edges() != "":
		claude.ask(
			text, _context(), func(reading: Dictionary) -> void: _deliver(cb, _tell(text, reading))
		)
		return
	_deliver.call_deferred(cb, _route("POST", path, body))


# A line the chat answers from the house's own state, true when it did: an item of Your move settled
# in words (`last` is the key of the one said last), a question about the money or about the list.
# Any other line is a tell, as before.
func _chat(text: String, body: Dictionary, cb: Callable) -> bool:
	var open: Array = list.moves.open_items()
	var shown := {}
	for m in open:
		if m["key"] == str(body.get("last", "")):
			shown = m
	var settle := ChatRoute.settle(text, shown, open)
	if not settle.is_empty():
		var said: Dictionary = list.moves.settle(settle["key"], settle["choice"])
		var out := {"reply": str(said.get("ok", said.get("error", "")))}
		if said.has("open"):
			out["open"] = said["open"]
		_answered(cb, text, out)
		return true
	match ChatRoute.asks(text):
		"money":
			money_ask.ask(
				text,
				_money_thread,
				func(answer: Dictionary) -> void:
					_money_thread = str(answer["thread"])
					_answered(cb, text, {"reply": answer["reply"]}),
				_model()
			)
			return true
		"list":
			_list_answer(text, cb)
			return true
	return false


func _answered(cb: Callable, text: String, body: Dictionary) -> void:
	replied.emit(text, body["reply"])
	_deliver(cb, {"code": 200, "body": body})


func _list_answer(text: String, cb: Callable) -> void:
	var facts := ChatList.facts(list)
	var plain := ChatList.plain(facts)
	var model := _model()
	if not model.is_valid():
		_answered.call_deferred(cb, text, {"reply": plain})
		return
	model.call(
		ChatList.prompt(text, facts),
		func(ok: bool, said: String) -> void:
			_answered(
				cb,
				text,
				{"reply": said.strip_edges() if ok and said.strip_edges() != "" else plain}
			)
	)


func check(_url: String, cb: Callable) -> void:
	cb.call_deferred(true)


func _deliver(cb: Callable, answer: Dictionary) -> void:
	cb.call(true, answer["code"], answer["body"])


func _route(method: String, path: String, body: Dictionary) -> Dictionary:
	var query := path.get_slice("?", 1) if "?" in path else ""
	var p := path.get_slice("?", 0).split("/", false)
	if p.size() < 2 or p[0] != "api":
		return _nowhere()
	if method == "GET":
		return _read_route(p, query)
	if p.size() == 2 and p[1] == "home":
		return _tell(str(body.get("text", "")))
	if p.size() >= 4 and p[2] == "money":
		return _money_post(p, body)
	if p.size() == 4 and p[2] == "moves" and p[3] == "settle":
		return _settle_move(body)
	if p.size() == 3 and p[2] == "add":
		return list.add(body)
	if p.size() == 4 and p[2] == "door" and p[3] == "add":
		return list.door_add(body)
	if p.size() == 3 and p[2] == "agendas":
		return list.agenda_add(body)
	if p.size() == 5 and p[2] == "agendas" and p[3].is_valid_int():
		return _agenda_route(int(p[3]), p[4], body)
	if p.size() != 4 or not p[2].is_valid_int():
		return _nowhere()
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
	return _nowhere()


func _agenda_route(id: int, action: String, body: Dictionary) -> Dictionary:
	match action:
		"edit":
			return list.agenda_edit(id, body)
		"add":
			return list.agenda_note(id, body)
		"clear":
			return list.agenda_clear(id)
		"drop":
			return list.agenda_drop(id)
	return _nowhere()


func _read_route(p: PackedStringArray, query: String) -> Dictionary:
	if p.size() == 2 and p[1] == "home":
		var status: Dictionary = list.status()
		var now: float = list.now()
		var stale: float = now - MovesList.STALE_DAYS * 86400.0
		list.moves.sweep(MovesList.sources(status, list.iso(now), list.iso(stale)))
		status["moves"] = list.moves.open_items()
		status["meetings"] = [] if calendar == null else calendar.meetings()
		status["money"] = bank.summary()
		return {"code": 200, "body": status}
	if p.size() == 4 and p[1] == "home" and p[2] == "money" and p[3] == "forecast":
		return _money_forecast(query)
	if p.size() == 3 and p[1] == "home" and p[2] == "pets":
		return {"code": 200, "body": {}}
	if p.size() == 3 and p[1] == "home" and p[2] == "meetings":
		return _meetings_between(query)
	if p.size() == 3 and p[1] == "home" and p[2] == "now":
		var skip: Variant = _skip_of(query)
		if skip == null:
			return {"code": 400, "body": {"error": E_NOW}}
		return list.pick(skip)
	if p.size() == 2 and p[1] == "settings":
		return {"code": 200, "body": {"knobs": _knobs(), "restart_pending": false}}
	return _nowhere()


func _meetings_between(query: String) -> Dictionary:
	var q := {}
	for pair in query.split("&", false):
		q[pair.get_slice("=", 0)] = pair.get_slice("=", 1)
	var from := str(q.get("from", ""))
	var to := str(q.get("to", ""))
	if not CalendarFeed.range_ok(from, to):
		return {"code": 400, "body": {"error": CalendarFeed.E_RANGE}}
	return {"code": 200, "body": [] if calendar == null else calendar.between(from, to)}


func _nowhere() -> Dictionary:
	return {"code": 404, "body": {"error": "no such route"}}


# the ids of `skip`; null when skip or minutes is not what the server accepts
func _skip_of(query: String) -> Variant:
	var skip := []
	for pair in query.split("&", false):
		var value := pair.get_slice("=", 1)
		match pair.get_slice("=", 0):
			"skip":
				for s in value.split(",", false):
					if not s.is_valid_int():
						return null
					skip.append(int(s))
			"minutes":
				if not value.is_valid_float():
					return null
	return skip


func _knobs() -> Array:
	return KNOBS.map(func(k): return {"key": k[0], "value": k[1], "boot": k[1]})


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
				made = list.add({"kind": "todo", "text": text})
				said = "To do: %s." % text.strip_edges()
		"done":
			made = list.done(int(reading["id"]))
		"delete":
			made = list.drop(int(reading["id"]))
	if made["code"] == 404:
		said = "That one is not there any more. Nothing changed."
	replied.emit(text, said)
	var body := {"reply": said}
	if reading["action"] == "add" and made["code"] == 200 and made["body"] is Dictionary:
		body["row"] = made["body"]
	return {"code": 200, "body": body}


# the money chat's model: the `claude` program when the house may use it, else none
func _model() -> Callable:
	if claude == null:
		return Callable()
	var command: String = claude.command
	return func(prompt: String, cb: Callable) -> void:
		var model := AskModel.new()
		model.command = command
		model.ask(prompt, cb)


func _money_forecast(query: String) -> Dictionary:
	var until := BankUtil.add(bank.today(), FORECAST_DAYS)
	for pair in query.split("&", false):
		if pair.get_slice("=", 0) == "until":
			until = pair.get_slice("=", 1)
			if not BankUtil.valid(until):
				return {"code": 400, "body": {"error": E_UNTIL}}
	var forecast: Dictionary = bank.forecast(until)
	var subs: Dictionary = bank.subscriptions()
	if forecast.has("error") or subs.has("error"):
		return {"code": 200, "body": null}
	var out: Dictionary = forecast["ok"]
	out["subscriptions"] = subs["ok"]
	out["notices"] = bank.notices()
	var budget: Dictionary = bank.budget()
	if budget.has("ok"):
		out["budget"] = budget["ok"]
	return {"code": 200, "body": out}


func _money_seen(body: Dictionary) -> Dictionary:
	if bank.see(body.get("key")):
		return {"code": 200, "body": {"ok": true}}
	return {"code": 422, "body": {"error": E_KEY}}


# the money's posts that need no model: a notice seen, a question with none to read it (`send`
# gives the model a question when the house may use one)
func _money_post(p: PackedStringArray, body: Dictionary) -> Dictionary:
	if p.size() == 5 and p[3] == "notices" and p[4] == "seen":
		return _money_seen(body)
	if p.size() != 4 or p[3] != "ask":
		return _nowhere()
	var text: Variant = body.get("text")
	if not (text is String and text.strip_edges() != ""):
		return {"code": 400, "body": {"error": "text is required"}}
	var box := {}
	money_ask.ask(text, body.get("thread"), func(answer: Dictionary) -> void: box.merge(answer))
	return {"code": 200, "body": box}


# `{key, choice}`: go or no, or an ask's option number or words (`Moves.settle`)
func _settle_move(body: Dictionary) -> Dictionary:
	var choice: Variant = body.get("choice")
	if choice is float and choice == floorf(choice):
		choice = int(choice)
	var said: Dictionary = list.moves.settle(str(body.get("key", "")), choice)
	return {"code": 400 if said.has("error") else 200, "body": said}
