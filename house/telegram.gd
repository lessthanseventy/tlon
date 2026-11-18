extends Node

# The house's own Telegram bot, over the house's own list only. It long-polls `getUpdates`, speaks
# only to the one chat that paired with it (sent the code the settings screen shows), and tells
# main.gd what that chat says (`heard`) and which button it pressed (`tapped`); main.gd carries both
# out through the routes the chat and the paper menu use. `on_told`, `handled` and `sync` keep the
# messages of told reminders in step with the house. The token lives in `user://house_telegram.json`
# {"token", "chat", "offset", "listed"} and nowhere else, and no line printed, logged or returned
# holds it: Telegram's API puts it in the URL, which `_call` alone builds.
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
	"delete": "deleted",
	"gone": "dealt with in the house",
}
const ASK := "Delete for good?"

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
var list_at := "17:30"
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


func _save() -> void:
	if not persist:
		return
	var f := FileAccess.open(store, FileAccess.WRITE)
	if f != null:
		f.store_string(
			JSON.stringify({"token": token, "chat": chat, "offset": offset, "listed": listed})
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


static func keyboard(id: int, repeating: bool) -> Dictionary:
	var del := ("ask:%d" if repeating else "delete:%d") % id
	return {
		"inline_keyboard":
		[
			[_button("Done", "done:%d" % id), _button("In an hour", "hour:%d" % id)],
			[_button("Tomorrow", "tomorrow:%d" % id), _button("Delete", del)],
		]
	}


static func confirm(id: int) -> Dictionary:
	return {
		"inline_keyboard": [[_button("Yes, delete", "yes:%d" % id), _button("No", "no:%d" % id)]]
	}


static func _button(label: String, data: String) -> Dictionary:
	return {"text": label, "callback_data": data}


# a reminder the house has just told: a message with its buttons; one told before loses its buttons
func on_told(row: Dictionary) -> void:
	if chat == 0:
		return
	var id := int(row["id"])
	if _msgs.has(id):
		_edit_markup(int(_msgs[id]["mid"]), {"inline_keyboard": []})
	var text := BELL + str(row["text"])
	_call(
		"sendMessage",
		{
			"chat_id": chat,
			"text": text.left(4000),
			"reply_markup": keyboard(id, row.get("every") != null)
		},
		func(ok: bool, result: Variant, _why: String, _http: int) -> void:
			if ok and result is Dictionary:
				_msgs[id] = {"mid": int(result["message_id"]), "text": text}
	)


# the reminder was dealt with in the house (`what`: done hour tomorrow delete, or gone)
func handled(id: int, what: String) -> void:
	if chat == 0 or _tapping.has(id) or not _msgs.has(id):
		return
	var m: Dictionary = _msgs[id]
	_msgs.erase(id)
	_edit(
		int(m["mid"]),
		str(m["text"]) + "\n" + OUTCOME.get(what, OUTCOME["gone"]),
		{"inline_keyboard": []}
	)


# what the house still rings: a message whose reminder is no longer among them was dealt with
func sync(ringing: Array) -> void:
	for id in _msgs.keys():
		if not ringing.has(int(id)):
			handled(int(id), "gone")


func _edit(mid: int, text: String, markup: Dictionary) -> void:
	_call(
		"editMessageText",
		{"chat_id": chat, "message_id": mid, "text": text.left(4000), "reply_markup": markup},
		Callable(self, "_ignored")
	)


func _edit_markup(mid: int, markup: Dictionary) -> void:
	_call(
		"editMessageReplyMarkup",
		{"chat_id": chat, "message_id": mid, "reply_markup": markup},
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
	if (
		not id_text.is_valid_int()
		or verb not in ["done", "hour", "tomorrow", "delete", "ask", "yes", "no"]
	):
		_answer(qid, "")
		return
	var id := int(id_text)
	var mid := int(message.get("message_id", 0))
	var text := str(message.get("text", ""))
	match verb:
		"ask":
			_answer(qid, "")
			_edit(mid, text + "\n" + ASK, confirm(id))
		"no":
			_answer(qid, "")
			_edit(mid, text.trim_suffix("\n" + ASK), keyboard(id, true))
		_:
			var what := "delete" if verb == "yes" else verb
			_tapping[id] = true
			tapped.emit(
				id,
				what,
				func() -> void:
					_tapping.erase(id)
					_msgs.erase(id)
					_answer(qid, OUTCOME[what])
					_edit(
						mid,
						text.trim_suffix("\n" + ASK) + "\n" + OUTCOME[what],
						{"inline_keyboard": []}
					)
			)


func _answer(qid: String, text: String) -> void:
	_call(
		"answerCallbackQuery", {"callback_query_id": qid, "text": text}, Callable(self, "_ignored")
	)


# once a day at `list_at` by the house clock (and, if the house was shut then, when it next starts
# that day): the open things and tomorrow's, in one message
func daily() -> void:
	if chat == 0 or list_at == "off" or not clock.is_valid() or not status.is_valid():
		return
	var now: float = clock.call()
	var d := LocalList.parts(now)
	var today := "%04d-%02d-%02d" % [d["year"], d["month"], d["day"]]
	var at := list_at.split(":")
	if (
		listed == today
		or at.size() != 2
		or int(d["hour"]) * 60 + int(d["minute"]) < int(at[0]) * 60 + int(at[1])
	):
		return
	listed = today
	_save()
	var text := list_text(status.call(), now)
	if text != "":
		_say(text)


func list_text(st: Dictionary, now: float) -> String:
	var open: Array = st.get("open", []).map(func(r): return str(r["text"]))
	var tomorrow: Array = []
	var from := LocalList.midnight(now) + LocalList.DAY
	for r in st.get("coming", []):
		var due := Time.get_unix_time_from_datetime_string(str(r["due_at"]).trim_suffix("Z")) + bias
		if due >= from and due < from + LocalList.DAY:
			tomorrow.append(str(r["text"]))
	var parts: Array = []
	if not open.is_empty():
		parts.append("Still open: " + _some(open))
	if not tomorrow.is_empty():
		parts.append("tomorrow: " + _some(tomorrow))
	return "; ".join(parts)


static func _some(items: Array) -> String:
	var shown := ", ".join(items.slice(0, 10))
	return shown if items.size() <= 10 else "%s and %d more" % [shown, items.size() - 10]
