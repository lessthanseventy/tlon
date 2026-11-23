extends Node

# The house's own Telegram bot, over the house's own list only. It long-polls `getUpdates`, speaks
# only to the one chat that paired with it (sent the code the settings screen shows), and tells
# main.gd what that chat says (`heard`) and which button it pressed (`tapped`); main.gd carries both
# out through the routes the chat and the paper menu use. `on_told`, `handled` and `sync` keep the
# messages of told reminders, and the day's card, in step with the house. The token lives in
# `user://house_telegram.json` {"token", "chat", "offset", "listed", "card"} and nowhere else, and
# no line printed, logged or returned holds it: Telegram's API puts it in the URL, which `_call`
# alone builds.
signal heard(text: String, finish: Callable)
signal tapped(id: int, verb: String, finish: Callable)

const LocalList := preload("res://local_list.gd")
const STORE := "user://house_telegram.json"
const BELL := "⏰ "
const POLL_SECONDS := 25
const BACKOFF_FIRST := 5.0
const BACKOFF_MAX := 300.0
const WRONG_TRIES := 5
const OUTCOME := {
	"done": "✓ done",
	"hour": "in an hour",
	"tomorrow": "tomorrow",
	"skip": "skipped to its next time",
	"delete": "deleted",
	"gone": "dealt with in the house",
}
const ASK := "Delete for good?"
const WEEKDAYS := ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
const PICK_ROW := 5

var base := "https://api.telegram.org"
var store := STORE
var persist := false
# false: no request is ever made (a staged run shows the state and nothing more)
var live := false
var token := ""
var chat := 0
var offset := 0
var listed := ""
var me := ""
var code := ""
var problem := ""
var reached_at := 0.0
var backoff := 0.0
var poll_gap := 1.0
var grace := 3.0
var list_at := "17:30"
var morning_at := "08:30"
# the day's card: {day, phase "morning"|"evening", mid, items [{id, text}] numbered in order,
# ticked [ids], first (how many items the morning had), keys "main"|"tick", sent}
var card := {}
var clock := Callable()
var status := Callable()
var bias := 0.0
var rng := RandomNumberGenerator.new()

var _gen := 0
var _running := false
var _msgs := {}
var _tapping := {}
var _queue: Array = []
var _busy := false
var _wrong := 0
var _daily: Timer


static func next_backoff(prev: float) -> float:
	return BACKOFF_FIRST if prev <= 0.0 else minf(prev * 2.0, BACKOFF_MAX)


# the last four characters, for the settings screen
func masked() -> String:
	return "" if token == "" else "…" + token.right(4)


func is_paired() -> bool:
	return chat != 0


func load_state() -> void:
	if not (persist and FileAccess.file_exists(store)):
		return
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(store))
	if d is Dictionary:
		token = str(d.get("token", ""))
		chat = int(d.get("chat", 0))
		offset = int(d.get("offset", 0))
		listed = str(d.get("listed", ""))
		card = _card_of(d.get("card"))


# JSON reads every number back as a float, and an id must stay an int to be found
static func _card_of(c: Variant) -> Dictionary:
	if not (c is Dictionary and c.get("items") is Array and c.get("ticked") is Array):
		return {}
	c["mid"] = int(c.get("mid", 0))
	c["first"] = int(c.get("first", 0))
	c["ticked"] = c["ticked"].map(func(id): return int(id))
	for item in c["items"]:
		item["id"] = int(item["id"])
	return c


func _save() -> void:
	if not persist:
		return
	var f := FileAccess.open(store, FileAccess.WRITE)
	if f != null:
		f.store_string(
			JSON.stringify(
				{"token": token, "chat": chat, "offset": offset, "listed": listed, "card": card}
			)
		)


# ask Telegram who `candidate` is; on success it becomes the token (a different one than before
# forgets the old chat) and `cb(line)` says the bot's @name, else why not
func connect_bot(candidate: String, cb: Callable) -> void:
	candidate = candidate.strip_edges()
	if candidate == "":
		cb.call("paste the token first")
		return
	_call(
		"getMe",
		{},
		func(ok: bool, result: Variant, why: String, _http: int) -> void:
			if not (ok and result is Dictionary):
				cb.call(why)
				return
			if candidate != token:
				stop()
				chat = 0
				offset = 0
				_msgs = {}
			token = candidate
			me = "@" + str(result.get("username", "bot"))
			problem = ""
			_save()
			start()
			cb.call(me),
		candidate
	)


# the second click's work: token, chat and offset are forgotten
func disconnect_bot() -> void:
	stop()
	token = ""
	chat = 0
	offset = 0
	listed = ""
	card = {}
	me = ""
	code = ""
	problem = ""
	_msgs = {}
	if persist and FileAccess.file_exists(store):
		DirAccess.remove_absolute(store)


# begin polling; a bot not yet paired waits for its code
func start() -> void:
	if _running or token == "":
		return
	_running = true
	if chat == 0 and code == "":
		_new_code()
	_gen += 1
	_poll(_gen)
	if me == "":
		_call(
			"getMe",
			{},
			func(ok: bool, result: Variant, _why: String, _http: int) -> void:
				if ok and result is Dictionary:
					me = "@" + str(result.get("username", "bot"))
		)
	if _daily == null:
		_daily = Timer.new()
		_daily.wait_time = 20.0
		_daily.timeout.connect(daily)
		add_child(_daily)
	_daily.start()


func stop() -> void:
	_running = false
	_gen += 1
	if _daily != null:
		_daily.stop()


func _new_code() -> void:
	code = "%04d" % rng.randi_range(0, 9999)
	_wrong = 0


# a Telegram method; `cb(ok, result, why)`. The URL holds the token, so it is built here and
# nowhere else, and what is passed on is only Telegram's own description or a fixed phrase.
func _call(
	method: String, params: Dictionary, cb: Callable, tok: String = "", timeout: float = 15.0
) -> void:
	if not live:
		cb.call_deferred(false, null, "not available in this run", 0)
		return
	var req := HTTPRequest.new()
	req.timeout = timeout
	add_child(req)
	req.request_completed.connect(
		func(result: int, http: int, _h: PackedStringArray, body: PackedByteArray) -> void:
			req.queue_free()
			var json := JSON.new()
			var parsed: Variant = (
				json.data if json.parse(body.get_string_from_utf8()) == OK else null
			)
			var ok: bool = (
				result == HTTPRequest.RESULT_SUCCESS
				and http == 200
				and parsed is Dictionary
				and parsed.get("ok") == true
			)
			var why := "Telegram could not be reached"
			if result == HTTPRequest.RESULT_SUCCESS:
				why = "Telegram answered %d" % http
				if parsed is Dictionary and parsed.get("description") is String:
					why = "Telegram says: " + parsed["description"]
			cb.call(ok, parsed["result"] if ok else null, why, http)
	)
	var url := "%s/bot%s/%s" % [base, tok if tok != "" else token, method]
	if (
		req.request(
			url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(params)
		)
		!= OK
	):
		req.queue_free()
		cb.call_deferred(false, null, "Telegram could not be reached", 0)


func _poll(gen: int) -> void:
	if gen != _gen:
		return
	_call(
		"getUpdates",
		{
			"offset": offset,
			"timeout": POLL_SECONDS,
			"allowed_updates": ["message", "callback_query"]
		},
		func(ok: bool, result: Variant, why: String, http: int) -> void:
			_polled(gen, ok, result, why, http),
		"",
		POLL_SECONDS + 10.0
	)


func _polled(gen: int, ok: bool, result: Variant, why: String, http: int) -> void:
	if gen != _gen:
		return
	if http == 401:
		problem = why
		_running = false
		return
	if not ok:
		backoff = next_backoff(backoff)
		_after(backoff, gen)
		return
	backoff = 0.0
	problem = ""
	reached_at = clock.call() if clock.is_valid() else Time.get_unix_time_from_system()
	_batch(result)
	_after(poll_gap, gen)


func _after(seconds: float, gen: int) -> void:
	get_tree().create_timer(seconds).timeout.connect(func() -> void: _poll(gen))


func _batch(updates: Array) -> void:
	if updates.is_empty():
		return
	updates.sort_custom(func(a, b) -> bool: return int(a["update_id"]) < int(b["update_id"]))
	offset = int(updates[-1]["update_id"]) + 1
	_save()
	for u in updates:
		if u.get("message") is Dictionary:
			_message(u["message"])
		elif u.get("callback_query") is Dictionary:
			_callback(u["callback_query"])


func _chat_of(message: Variant) -> Dictionary:
	if message is Dictionary and message.get("chat") is Dictionary:
		return message["chat"]
	return {}


func _message(m: Dictionary) -> void:
	var from := _chat_of(m)
	var id := int(from.get("id", 0))
	var text: Variant = m.get("text")
	if chat == 0:
		_pair(id, from, text)
	elif id != chat:
		return
	elif not text is String:
		_say("I can only read text here.")
	elif text.strip_edges().begins_with("/start"):
		_say("I'm here. Send me a line and I'll keep it.")
	elif not numbers(text).is_empty() and _card_today():
		_tick_numbers(numbers(text))
	elif text.strip_edges() != "":
		_queue.append(text)
		_pump()


# the first private chat that sends exactly the code is the chat; every other message, before and
# after, is ignored and never answered
func _pair(id: int, from: Dictionary, text: Variant) -> void:
	if id == 0 or from.get("type") != "private":
		return
	if text is String and code != "" and text.strip_edges() == code:
		chat = id
		code = ""
		_save()
		_say("Paired. Send me a line and I'll keep it; reminders come here too.")
		return
	_wrong += 1
	if _wrong >= WRONG_TRIES:
		_new_code()


func _pump() -> void:
	if _busy or _queue.is_empty():
		return
	_busy = true
	heard.emit(
		_queue.pop_front(),
		func(reply: String) -> void:
			_say(reply)
			_busy = false
			_pump()
	)


func _say(text: String) -> void:
	_call("sendMessage", {"chat_id": chat, "text": text.left(4000)}, Callable(self, "_ignored"))


func _ignored(_ok: bool, _result: Variant, _why: String, _http: int = 0) -> void:
	pass


# Skip is the next time for a repeating one (the list's done moves it on and records nothing), and
# tomorrow morning for a one-off
static func keyboard(id: int, repeating: bool) -> Dictionary:
	var skip := ("skip:%d" if repeating else "tomorrow:%d") % id
	return {
		"inline_keyboard":
		[[_button("Done", "done:%d" % id), _button("Later", "hour:%d" % id), _button("Skip", skip)]]
	}


static func confirm(id: int) -> Dictionary:
	return {
		"inline_keyboard": [[_button("Yes, delete", "yes:%d" % id), _button("No", "no:%d" % id)]]
	}


static func _button(label: String, data: String) -> Dictionary:
	return {"text": label, "callback_data": data}


# an agenda's pile, told once ahead of its time: a plain message, nothing to press
func on_agenda(text: String) -> void:
	if chat != 0:
		_say(text)


# a reminder the house has just told: a message with its buttons. Told again, the old message is
# deleted and the new one, at the bottom of the chat where it rings, says since when it waits.
func on_told(row: Dictionary) -> void:
	if chat == 0:
		return
	var id := int(row["id"])
	var since := _hhmm(clock.call()) if clock.is_valid() else ""
	var text := BELL + str(row["text"])
	if _msgs.has(id):
		since = str(_msgs[id].get("since", since))
		_after_sent(_msgs[id], func(mid: int) -> void: _delete(mid))
		if since != "":
			text += " · still waiting since " + since
	var entry := {
		"mid": 0, "text": text, "at": Time.get_ticks_msec(), "then": Callable(), "since": since
	}
	_msgs[id] = entry
	_call(
		"sendMessage",
		{
			"chat_id": chat,
			"text": text.left(4000),
			"reply_markup": keyboard(id, row.get("every") != null)
		},
		func(ok: bool, result: Variant, _why: String, _http: int) -> void:
			if not (ok and result is Dictionary):
				if is_same(_msgs.get(id), entry):
					_msgs.erase(id)
				return
			entry["mid"] = int(result["message_id"])
			if entry["then"].is_valid():
				entry["then"].call(entry["mid"])
	)


# `fn(message id)` once the message exists: now, or when Telegram has answered the send
func _after_sent(entry: Dictionary, fn: Callable) -> void:
	if int(entry["mid"]) != 0:
		fn.call(int(entry["mid"]))
	else:
		entry["then"] = fn


# the reminder was dealt with in the house (`what`: done hour tomorrow delete, or gone)
func handled(id: int, what: String) -> void:
	if what == "done":
		_ticked(id)
	if chat == 0 or _tapping.has(id) or not _msgs.has(id):
		return
	var m: Dictionary = _msgs[id]
	_msgs.erase(id)
	var said: String = str(m["text"]) + "\n" + OUTCOME.get(what, OUTCOME["gone"])
	_after_sent(m, func(mid: int) -> void: _edit(mid, said, {"inline_keyboard": []}))


# What the house still rings: a message whose reminder is no longer among them was dealt with. A
# message younger than `grace` is left alone: the list that said so may have been read before the tell.
# The day's card follows the list too: edited in place, which never rings the phone.
func sync(ringing: Array) -> void:
	for id in _msgs.keys():
		var age: float = (Time.get_ticks_msec() - int(_msgs[id]["at"])) / 1000.0
		if not ringing.has(int(id)) and age >= grace:
			handled(int(id), "gone")
	_card_refresh()


func _delete(mid: int) -> void:
	_call("deleteMessage", {"chat_id": chat, "message_id": mid}, Callable(self, "_ignored"))


func _edit(mid: int, text: String, markup: Dictionary) -> void:
	_call(
		"editMessageText",
		{"chat_id": chat, "message_id": mid, "text": text.left(4000), "reply_markup": markup},
		Callable(self, "_ignored")
	)


func _callback(q: Dictionary) -> void:
	var message: Variant = q.get("message")
	if chat == 0 or int(_chat_of(message).get("id", 0)) != chat:
		return
	var data := str(q.get("data", ""))
	var verb := data.get_slice(":", 0)
	var id_text := data.get_slice(":", 1)
	var qid := str(q.get("id", ""))
	var mid := int(message.get("message_id", 0))
	if verb == "card":
		_card_tap(id_text, mid, qid)
		return
	if (
		not id_text.is_valid_int()
		or verb not in ["done", "hour", "tomorrow", "skip", "delete", "ask", "yes", "no"]
	):
		_answer(qid, "")
		return
	var id := int(id_text)
	var text := str(message.get("text", ""))
	match verb:
		"ask":
			_answer(qid, "")
			_edit(mid, text + "\n" + ASK, confirm(id))
		"no":
			_answer(qid, "")
			_edit(mid, text.trim_suffix("\n" + ASK), keyboard(id, true))
		_:
			var said := "delete" if verb == "yes" else verb
			var what := "done" if verb == "skip" else said
			_tapping[id] = true
			tapped.emit(
				id,
				what,
				func() -> void:
					_tapping.erase(id)
					_msgs.erase(id)
					if verb == "done":
						_ticked(id)
					_answer(qid, OUTCOME[said])
					_edit(
						mid,
						text.trim_suffix("\n" + ASK) + "\n" + OUTCOME[said],
						{"inline_keyboard": []}
					)
					_card_refresh()
			)


func _answer(qid: String, text: String) -> void:
	_call(
		"answerCallbackQuery", {"callback_query_id": qid, "text": text}, Callable(self, "_ignored")
	)


# The day's card, by the house clock (and, if the house was shut then, when it next starts that
# day): a new message at `morning_at`, and at `list_at` the evening's in its place at the bottom of
# the chat, so both ring; on Saturday and Sunday the evening's only when the day moved. In between
# it is edited as the list changes, which rings nothing.
func daily() -> void:
	if chat == 0 or not clock.is_valid() or not status.is_valid():
		return
	var now: float = clock.call()
	var today := day_of(now)
	if listed != today and reached(list_at, now):
		listed = today
		_save()
		_card_evening(today, now)
	elif listed != today and str(card.get("day", "")) != today and reached(morning_at, now):
		_card_morning(today, now)


static func day_of(now: float) -> String:
	var d := LocalList.parts(now)
	return "%04d-%02d-%02d" % [d["year"], d["month"], d["day"]]


# whether the local time `now` is at or past `at` ("HH:MM"; "off" or anything else never is)
static func reached(at: String, now: float) -> bool:
	var m := RegEx.create_from_string("^([01]?\\d|2[0-3]):([0-5]\\d)$").search(at)
	if m == null:
		return false
	var d := LocalList.parts(now)
	return (
		int(d["hour"]) * 60 + int(d["minute"]) >= int(m.get_string(1)) * 60 + int(m.get_string(2))
	)


static func _hhmm(at: float) -> String:
	var d := LocalList.parts(at)
	return "%02d:%02d" % [d["hour"], d["minute"]]


# "2", "2 4 5", "2, 4": the numbers of a reply that is nothing else; [] for any other text
static func numbers(text: String) -> Array:
	if RegEx.create_from_string("^\\s*\\d{1,3}(\\s*[ ,]\\s*\\d{1,3})*\\s*$").search(text) == null:
		return []
	var out: Array = []
	for part in RegEx.create_from_string("\\d+").search_all(text):
		if not out.has(int(part.get_string())):
			out.append(int(part.get_string()))
	return out


static func new_card(day: String, phase: String) -> Dictionary:
	return {
		"day": day,
		"phase": phase,
		"mid": 0,
		"items": [],
		"ticked": [],
		"first": 0,
		"keys": "main",
		"sent": ""
	}


# what the card numbers: the open things, then the reminders still to come today, each kept under
# the number it first got for the whole day; a new one takes the next number
static func number(c: Dictionary, st: Dictionary, now: float, offset_s: float) -> void:
	var seen: Array = c["items"].map(func(i): return int(i["id"]))
	var end := LocalList.midnight(now) + LocalList.DAY
	var rows: Array = st.get("open", []).map(func(r): return [r, ""])
	for r in st.get("coming", []):
		if _at(r["due_at"], offset_s) < end:
			rows.append([r, _hhmm(_at(r["due_at"], offset_s)) + " "])
	for pair in rows:
		var r: Dictionary = pair[0]
		if seen.has(int(r["id"])):
			continue
		var text := str(r["text"])
		if r.get("project") is Dictionary:
			text = "%s: %s" % [r["project"]["text"], text]
		var item := {"id": int(r["id"]), "text": pair[1] + text}
		if r.get("list") != null:
			item["list"] = str(r["list"])
		c["items"].append(item)
		seen.append(int(r["id"]))


# a UTC "…Z" time of a row, on the house clock
static func _at(utc: Variant, offset_s: float) -> float:
	return Time.get_unix_time_from_datetime_string(str(utc).trim_suffix("Z")) + offset_s


static func done_today(st: Dictionary, now: float, offset_s: float) -> Array:
	var start := LocalList.midnight(now)
	return (
		st
		. get("done", [])
		. filter(func(r): return _at(r["done_at"], offset_s) >= start)
		. map(func(r): return str(r["text"]))
	)


static func _live(st: Dictionary) -> Array:
	return (st.get("open", []) + st.get("coming", [])).map(func(r): return int(r["id"]))


# the numbers still to tick: open, and not ticked
static func tickable(c: Dictionary, st: Dictionary) -> Array:
	var live := _live(st)
	var out: Array = []
	for i in c["items"].size():
		var id := int(c["items"][i]["id"])
		if live.has(id) and not c["ticked"].has(id):
			out.append(i + 1)
	return out


# The card's text. Morning: the date, then To do, numbered, a ticked line kept with a ✓ so no number
# moves; a thing put off or deleted leaves its line. Evening: what was done today, then what is
# still to do under the same numbers. "" when it has nothing to say.
static func card_text(c: Dictionary, st: Dictionary, now: float, offset_s: float) -> String:
	var d := LocalList.parts(now)
	var date := "%s %d %s" % [WEEKDAYS[d["weekday"]], d["day"], MONTHS[d["month"] - 1]]
	var evening: bool = c["phase"] == "evening"
	var live := _live(st)
	var groups := {"": []}
	for i in c["items"].size():
		var item: Dictionary = c["items"][i]
		var id := int(item["id"])
		var line := ""
		if c["ticked"].has(id):
			if not evening:
				line = "%d. ✓ %s" % [i + 1, item["text"]]
		elif live.has(id):
			line = "%d. %s" % [i + 1, item["text"]]
		if line != "":
			var list := str(item.get("list", ""))
			if not groups.has(list):
				groups[list] = []
			groups[list].append(line)
	var lines: Array = groups[""]
	for list in groups:
		if list != "":
			lines.append(
				("\n" if not lines.is_empty() else "") + list + "\n" + "\n".join(groups[list])
			)
	var parts: Array = []
	if evening:
		var done := done_today(st, now, offset_s)
		if not done.is_empty():
			parts.append("Done today: " + ", ".join(done))
		if not lines.is_empty():
			parts.append("Still to do\n" + "\n".join(lines))
	elif not lines.is_empty():
		parts.append("To do\n" + "\n".join(lines))
	if parts.is_empty():
		return ""
	return "\n\n".join([("This evening · " if evening else "Today · ") + date] + parts)


# one ✓ button that opens the numbers; the numbers, five a row, and Back
static func card_keys(c: Dictionary, st: Dictionary) -> Dictionary:
	var open := tickable(c, st)
	if open.is_empty():
		return {"inline_keyboard": []}
	if c["keys"] != "tick":
		return {"inline_keyboard": [[_button("✓ Tick…", "card:tick")]]}
	var rows: Array = []
	for i in range(0, open.size(), PICK_ROW):
		rows.append(open.slice(i, i + PICK_ROW).map(func(n): return _button(str(n), "card:%d" % n)))
	rows.append([_button("‹ Back", "card:back")])
	return {"inline_keyboard": rows}


func _card_today() -> bool:
	return clock.is_valid() and str(card.get("day", "")) == day_of(clock.call())


func _card_morning(today: String, now: float) -> void:
	var st: Dictionary = status.call()
	card = new_card(today, "morning")
	number(card, st, now, bias)
	card["first"] = card["items"].size()
	_save()
	_send_card(st, now, 0)


func _card_evening(today: String, now: float) -> void:
	var st: Dictionary = status.call()
	var old := 0
	if str(card.get("day", "")) == today:
		old = int(card["mid"])
	else:
		card = new_card(today, "evening")
		number(card, st, now, bias)
		card["first"] = card["items"].size()
	number(card, st, now, bias)
	var weekday: int = LocalList.parts(now)["weekday"]
	if weekday in [0, 6] and not _moved(st, now):
		_save()
		return
	card["phase"] = "evening"
	card["keys"] = "main"
	_send_card(st, now, old)


# the day moved: something was done, ticked or added since the morning
func _moved(st: Dictionary, now: float) -> bool:
	return not (
		done_today(st, now, bias).is_empty()
		and card["ticked"].is_empty()
		and card["items"].size() <= int(card["first"])
	)


# a new message for the card; `old`, the one it takes the place of, is deleted once it is sent
func _send_card(st: Dictionary, now: float, old: int) -> void:
	var text := card_text(card, st, now, bias)
	if text == "":
		_save()
		return
	var keys := card_keys(card, st)
	var sent := text + JSON.stringify(keys)
	var day := str(card["day"])
	_call(
		"sendMessage",
		{"chat_id": chat, "text": text.left(4000), "reply_markup": keys},
		func(ok: bool, result: Variant, _why: String, _http: int) -> void:
			if not (ok and result is Dictionary) or str(card.get("day", "")) != day:
				return
			card["mid"] = int(result["message_id"])
			card["sent"] = sent
			_save()
			if old != 0:
				_delete(old)
	)


# the card as the list has it now, edited only when that differs from what it shows
func _card_refresh() -> void:
	if chat == 0 or not _card_today() or int(card.get("mid", 0)) == 0 or not status.is_valid():
		return
	var now: float = clock.call()
	var st: Dictionary = status.call()
	number(card, st, now, bias)
	var text := card_text(card, st, now, bias)
	var keys := card_keys(card, st)
	var sent := text + JSON.stringify(keys)
	if text == "" or sent == str(card["sent"]):
		return
	card["sent"] = sent
	_save()
	_call(
		"editMessageText",
		{
			"chat_id": chat,
			"message_id": int(card["mid"]),
			"text": text.left(4000),
			"reply_markup": keys
		},
		func(ok: bool, _result: Variant, why: String, _http: int) -> void:
			if not (ok or "not modified" in why) and str(card.get("sent", "")) == sent:
				card["sent"] = ""
				_save()
	)


func _ticked(id: int) -> void:
	if not card.is_empty() and not card["ticked"].has(id):
		for item in card["items"]:
			if int(item["id"]) == id:
				card["ticked"].append(id)
				_save()


func _card_tap(arg: String, mid: int, qid: String) -> void:
	if not _card_today() or mid != int(card.get("mid", 0)):
		_answer(qid, "that card is from another day")
		return
	if arg in ["tick", "back"]:
		_answer(qid, "")
		card["keys"] = "tick" if arg == "tick" else "main"
		_card_refresh()
	elif arg.is_valid_int():
		card["keys"] = "main"
		_tick_numbers([int(arg)], qid)
	else:
		_answer(qid, "")


# tick the card's numbers `ns` one after the other through the house, then say what was ticked:
# in the chat for a typed reply, on the button for a press (`qid`)
func _tick_numbers(ns: Array, qid: String = "") -> void:
	var st: Dictionary = status.call() if status.is_valid() else {}
	var open := tickable(card, st)
	var ids: Array = []
	var names: Array = []
	var missing: Array = []
	for n in ns:
		if open.has(n):
			ids.append(int(card["items"][n - 1]["id"]))
			names.append(str(card["items"][n - 1]["text"]))
		else:
			missing.append(str(n))
	var said := "✓ " + ", ".join(names) if not names.is_empty() else ""
	if not missing.is_empty():
		said += ("\n" if said != "" else "") + "Nothing to tick at %s." % ", ".join(missing)
	_tick_each(
		ids,
		func() -> void:
			if qid != "":
				_answer(qid, said.left(190))
			else:
				_say(said)
			_card_refresh()
	)


func _tick_each(ids: Array, then: Callable) -> void:
	if ids.is_empty():
		then.call()
		return
	var id: int = ids.pop_front()
	_tapping[id] = true
	tapped.emit(
		id,
		"done",
		func() -> void:
			_tapping.erase(id)
			_ticked(id)
			if _msgs.has(id):
				handled(id, "done")
			_tick_each(ids, then)
	)
