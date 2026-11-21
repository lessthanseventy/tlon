extends RefCounted

# The soak's checks of the Telegram bot (`telegram.gd`) against a stub of Telegram's API on the
# soak's local server, alone and in the room over the house's own list. The fake token never
# leaves this machine and no line of this file prints it.
const LocalList := preload("res://local_list.gd")
const Telegram := preload("res://telegram.gd")
const BackendLocal := preload("res://backend_local.gd")
const TOKEN := "123456:SOAK-not-a-real-token-ABCdef"
const STORE := "user://soak_telegram.json"

var s
var _made: Array = []
var t := 0.0


func _init(soak) -> void:
	s = soak


func _clock() -> float:
	return t


func _eq(got: Variant, want: Variant, what: String) -> void:
	s._check(got == want, "%s: got %s, want %s" % [what, str(got), str(want)])


func _until(done: Callable, secs: float = 4.0) -> void:
	var end := Time.get_ticks_msec() + int(secs * 1000.0)
	while not done.call() and Time.get_ticks_msec() < end:
		await s.create_timer(0.02).timeout


func _polls(bot) -> int:
	return bot.calls.filter(func(c): return c["method"] == "getUpdates").size()


# a moment, then until the bot has acknowledged every update and polled twice more, so what it
# answered has reached the stub (bounded). A bot that is not polling is not waited for.
func _settle(secs: float = 0.3) -> void:
	await s.create_timer(minf(secs, 0.1)).timeout
	if s.bot.is_null():
		return
	var bot = s.bot.get_object()
	var from := _polls(bot)
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 5000:
		var seen: int = _polls(bot) - from
		if seen >= 2 and bot.updates.is_empty():
			return
		if seen == 0 and Time.get_ticks_msec() - start > 700:
			return
		await s.create_timer(0.02).timeout


func _wipe() -> void:
	if FileAccess.file_exists(STORE):
		DirAccess.remove_absolute(STORE)


func run(main) -> void:
	t = LocalList.wall(2026, 11, 18, 14)
	await _telegram()
	await _in_the_house(main)
	_wipe()
	for n in _made:
		if is_instance_valid(n):
			n.queue_free()


# What Telegram's API does, as far as the bot uses it. `handle` answers the soak server's /bot... paths.
class Bot:
	var token := ""
	var updates: Array = []
	var calls: Array = []
	var sent: Array = []
	var attempts := 0
	var fail := 0
	var next_message := 100
	var next_update := 1

	func text(chat_id: int, body: String, kind: String = "private") -> int:
		return _push(
			{"message": {"message_id": 1, "chat": {"id": chat_id, "type": kind}, "text": body}}
		)

	func voice(chat_id: int) -> int:
		return _push(
			{"message": {"message_id": 1, "chat": {"id": chat_id, "type": "private"}, "voice": {}}}
		)

	func tap(chat_id: int, data: String, mid: int, body: String) -> int:
		return _push(
			{
				"callback_query":
				{
					"id": "cb%d" % next_update,
					"data": data,
					"message":
					{"message_id": mid, "text": body, "chat": {"id": chat_id, "type": "private"}}
				}
			}
		)

	func _push(u: Dictionary) -> int:
		u["update_id"] = next_update
		next_update += 1
		updates.append(u)
		return int(u["update_id"])

	func named(method: String) -> Array:
		return calls.filter(func(c): return c["method"] == method).map(func(c): return c["params"])

	func to(chat_id: int) -> Array:
		return sent.filter(func(m): return int(m["params"]["chat_id"]) == chat_id)

	func handle(path: String, params: Variant) -> Dictionary:
		attempts += 1
		if fail != 0:
			return {"code": fail, "body": {"ok": false, "description": "stub failure"}}
		var parts := path.trim_prefix("/").split("/", false)
		if parts[0] != "bot" + token:
			return {"code": 401, "body": {"ok": false, "description": "Unauthorized"}}
		var method := parts[1]
		calls.append({"method": method, "params": params})
		var result: Variant = true
		match method:
			"getMe":
				result = {"id": 1, "is_bot": true, "username": "house_stub_bot"}
			"getUpdates":
				var from := int(params.get("offset", 0))
				updates = updates.filter(func(u): return int(u["update_id"]) >= from)
				result = updates.duplicate()
			"sendMessage":
				result = {"message_id": next_message}
				sent.append({"mid": next_message, "params": params})
				next_message += 1
		return {"code": 200, "body": {"ok": true, "result": result}}


func _tg(base: String, heard: Array, taps: Array) -> Telegram:
	var tg := Telegram.new()
	tg.live = true
	tg.base = base
	tg.store = STORE
	tg.persist = true
	tg.poll_gap = 0.03
	tg.grace = 0.0
	tg.rng.seed = 5
	tg.clock = Callable(self, "_clock")
	tg.heard.connect(
		func(text: String, finish: Callable) -> void:
			heard.append(text)
			finish.call("re: " + text)
	)
	tg.tapped.connect(
		func(id: int, verb: String, finish: Callable) -> void:
			taps.append([id, verb])
			finish.call()
	)
	s.root.add_child(tg)
	_made.append(tg)
	return tg


func _keys(markup: Dictionary) -> Array:
	var out: Array = []
	for row in markup["inline_keyboard"]:
		for b in row:
			out.append(b["callback_data"])
	return out


func _telegram() -> void:
	_wipe()
	var bot := Bot.new()
	bot.token = TOKEN
	s.bot = Callable(bot, "handle")
	var base := "http://127.0.0.1:%d" % s._srv.get_local_port()
	var heard: Array = []
	var taps: Array = []
	var tg := _tg(base, heard, taps)
	var said: Array = []
	tg.connect_bot("", func(l: String) -> void: said.append(l))
	tg.connect_bot("999:wrong-WXYZ", func(l: String) -> void: said.append(l))
	await _until(func() -> bool: return said.size() == 2)
	_eq(
		said,
		["paste the token first", "Telegram says: Unauthorized"],
		"a missing and a bad token are said in one line"
	)
	await _settle(0.2)
	_eq([tg.token, bot.named("getUpdates").size()], ["", 0], "and nothing is kept or asked")
	tg.connect_bot(TOKEN, func(l: String) -> void: said.append(l))
	await _until(func() -> bool: return said.size() == 3)
	_eq(
		[said[2], tg.token == TOKEN, tg.masked()],
		["@house_stub_bot", true, "…" + TOKEN.right(4)],
		"a good token says the bot's name, and is shown masked"
	)
	await _until(func() -> bool: return bot.named("getUpdates").size() >= 2)
	var asked: Dictionary = bot.named("getUpdates").back()
	_eq(
		[int(asked["timeout"]), asked["allowed_updates"]],
		[25, ["message", "callback_query"]],
		"it long-polls for messages and button presses only"
	)
	_eq(
		[tg.code.length(), tg.code.is_valid_int(), tg.chat],
		[4, true, 0],
		"four digits wait to pair"
	)

	# pairing: only a private chat that sends exactly the code; everyone else is ignored, always
	var n := bot.sent.size()
	bot.text(555, "hello")
	bot.text(888, tg.code, "group")
	bot.text(556, "%04d" % ((int(tg.code) + 1) % 10000))
	await _settle()
	_eq(
		[tg.chat, heard, bot.sent.size() - n],
		[0, [], 0],
		"a wrong word, a group and a wrong code pair nothing and get no answer"
	)
	var first_code := tg.code
	for i in 3:
		bot.text(557, "x%d" % i)
	await _settle()
	_eq(tg.code != first_code, true, "five wrong tries and the code is changed")
	bot.text(777, tg.code)
	await _until(func() -> bool: return tg.chat == 777)
	_eq([tg.chat, tg.code], [777, ""], "the chat that sent the code is the chat")
	await _until(func() -> bool: return bot.to(777).size() == 1)
	_eq(bot.to(777)[0]["params"]["text"].begins_with("Paired."), true, "and is told so")
	n = bot.sent.size()
	bot.text(555, "hello again")
	bot.text(556, "buy milk")
	await _settle()
	_eq([heard, bot.sent.size() - n], [[], 0], "another chat is ignored after pairing too")

	# a line from the paired chat is the house's to read; the answer goes back
	var id := bot.text(777, "buy stamps")
	await _until(func() -> bool: return heard.size() == 1)
	await _until(func() -> bool: return bot.to(777).size() == 2)
	_eq(
		[heard, bot.to(777)[1]["params"]["text"]],
		[["buy stamps"], "re: buy stamps"],
		"a text from the chat is told, and the reply sent"
	)
	bot.text(777, "/start")
	await _until(func() -> bool: return bot.to(777).size() == 3)
	_eq(
		[heard.size(), bot.to(777)[2]["params"]["text"].begins_with("I'm here")],
		[1, true],
		"/start is greeted, not filed"
	)
	bot.voice(777)
	await _until(func() -> bool: return bot.to(777).size() == 4)
	await _settle()
	_eq(
		[heard.size(), bot.to(777).size(), bot.to(777)[3]["params"]["text"]],
		[1, 4, "I can only read text here."],
		"a voice note gets one answer and is not filed"
	)

	# what was read is not read again, here or after a restart
	_eq(tg.offset > id, true, "the offset moves past what was handled")
	var kept: Variant = JSON.parse_string(FileAccess.get_file_as_string(STORE))
	_eq(
		[
			kept.keys().size(),
			kept["token"] == TOKEN,
			int(kept["chat"]),
			int(kept["offset"]) == tg.offset
		],
		[4, true, 777, true],
		"and is kept with the token and chat in the bot's own file"
	)
	tg.stop()
	var again: Array = []
	var tg2 := _tg(base, again, [])
	tg2.load_state()
	_eq(
		[tg2.token == TOKEN, tg2.chat, tg2.offset == tg.offset],
		[true, 777, true],
		"a restart has them all"
	)
	bot.updates.append(
		{
			"update_id": id,
			"message":
			{"message_id": 1, "chat": {"id": 777, "type": "private"}, "text": "buy stamps"}
		}
	)
	tg2.start()
	await _until(func() -> bool: return bot.named("getUpdates").back()["offset"] == tg.offset)
	await _settle()
	_eq(
		[again, bot.named("getUpdates").back()["offset"] == tg.offset],
		[[], true],
		"and asks from the offset, so nothing is filed twice"
	)
	tg2.stop()
	# what came in while it was closed is read oldest first
	bot.text(777, "one")
	bot.text(777, "two")
	bot.text(777, "three")
	bot.updates.reverse()
	var backlog: Array = []
	var tg3 := _tg(base, backlog, taps)
	tg3.load_state()
	tg3.start()
	await _until(func() -> bool: return backlog.size() == 3)
	_eq(backlog, ["one", "two", "three"], "the backlog is read oldest first at start")

	# a reminder told: a message with buttons
	var tea: Dictionary = {"id": 7, "text": "tea", "every": null}
	n = bot.sent.size()
	tg3.on_told(tea)
	await _until(func() -> bool: return bot.sent.size() == n + 1)
	var msg: Dictionary = bot.sent.back()
	_eq(
		[msg["params"]["text"], _keys(msg["params"]["reply_markup"])],
		["⏰ tea", ["done:7", "hour:7", "tomorrow:7", "delete:7"]],
		"a told reminder is a message with Done, In an hour, Tomorrow, Delete"
	)
	_eq(
		_keys(msg["params"]["reply_markup"]).all(func(k): return k.to_utf8_buffer().size() < 64),
		true,
		"each button's data is under 64 bytes"
	)
	for pair in [
		["done", "✓ done"], ["hour", "in an hour"], ["tomorrow", "tomorrow"], ["delete", "deleted"]
	]:
		n = bot.sent.size()
		tg3.on_told({"id": 20, "text": "x", "every": null})
		await _until(func() -> bool: return bot.sent.size() == n + 1)
		var m: Dictionary = bot.sent.back()
		var answers := bot.named("answerCallbackQuery").size()
		var tap_id := bot.tap(777, "%s:20" % pair[0], m["mid"], "⏰ x")
		await _until(func() -> bool: return bot.named("answerCallbackQuery").size() == answers + 1)
		await _until(
			func() -> bool:
				return (
					bot.named("editMessageText").size() > 0
					and str(bot.named("editMessageText").back()["text"]).ends_with(pair[1])
				)
		)
		var edit: Dictionary = bot.named("editMessageText").back()
		_eq(
			[
				taps.back(),
				bot.named("answerCallbackQuery").back()["text"],
				bot.named("answerCallbackQuery").back()["callback_query_id"] == "cb%d" % tap_id
			],
			[[20, pair[0]], pair[1], true],
			"the %s button is the same route, and its press is answered" % pair[0]
		)
		_eq(
			[int(edit["message_id"]), edit["text"], edit["reply_markup"]["inline_keyboard"]],
			[m["mid"], "⏰ x\n" + pair[1], []],
			"and the message says what was done, with no buttons"
		)
	var presses := taps.size()
	bot.tap(555, "done:7", 1, "⏰ tea")
	await _settle()
	_eq(taps.size(), presses, "a press from another chat does nothing")

	# a repeating reminder's Delete asks again
	tg3.on_told({"id": 8, "text": "water", "every": "week"})
	await _until(func() -> bool: return bot.sent.back()["params"]["text"] == "⏰ water")
	var water: Dictionary = bot.sent.back()
	_eq(
		_keys(water["params"]["reply_markup"]).back(),
		"ask:8",
		"a repeating one's Delete is a question"
	)
	presses = taps.size()
	var edits := bot.named("editMessageText").size()
	bot.tap(777, "ask:8", water["mid"], "⏰ water")
	await _until(func() -> bool: return bot.named("editMessageText").size() == edits + 1)
	var ask: Dictionary = bot.named("editMessageText").back()
	_eq(
		[ask["text"], _keys(ask["reply_markup"]), taps.size()],
		["⏰ water\nDelete for good?", ["yes:8", "no:8"], presses],
		"the second keyboard says yes or no, and deletes nothing"
	)
	bot.tap(777, "no:8", water["mid"], ask["text"])
	await _until(func() -> bool: return bot.named("editMessageText").size() == edits + 2)
	var back: Dictionary = bot.named("editMessageText").back()
	_eq(
		[back["text"], _keys(back["reply_markup"]).size(), taps.size()],
		["⏰ water", 4, presses],
		"no puts the buttons back"
	)
	bot.tap(777, "yes:8", water["mid"], ask["text"])
	await _until(func() -> bool: return taps.size() == presses + 1)
	await _until(func() -> bool: return bot.named("editMessageText").size() == edits + 3)
	_eq(
		[taps.back(), bot.named("editMessageText").back()["text"]],
		[[8, "delete"], "⏰ water\ndeleted"],
		"yes deletes it for good"
	)

	# a re-ring: the new message, the old one loses its buttons
	tg3.on_told({"id": 9, "text": "gym", "every": null})
	await _until(func() -> bool: return bot.sent.back()["params"]["text"] == "⏰ gym")
	var old: Dictionary = bot.sent.back()
	n = bot.sent.size()
	tg3.on_told({"id": 9, "text": "gym", "every": null})
	await _until(func() -> bool: return bot.sent.size() == n + 1)
	await _until(func() -> bool: return bot.named("editMessageReplyMarkup").size() > 0)
	var cleared: Dictionary = bot.named("editMessageReplyMarkup").back()
	_eq(
		[int(cleared["message_id"]), cleared["reply_markup"]["inline_keyboard"]],
		[old["mid"], []],
		"a re-ring sends a new message and takes the buttons off the old"
	)

	# acted in the house: the message follows
	var fresh: Dictionary = bot.sent.back()
	edits = bot.named("editMessageText").size()
	tg3.handled(9, "done")
	await _until(func() -> bool: return bot.named("editMessageText").size() == edits + 1)
	var followed: Dictionary = bot.named("editMessageText").back()
	_eq(
		[
			int(followed["message_id"]),
			followed["text"],
			followed["reply_markup"]["inline_keyboard"]
		],
		[fresh["mid"], "⏰ gym\n✓ done", []],
		"done in the house takes the buttons off and says so"
	)
	tg3.handled(9, "done")
	await _settle(0.15)
	_eq(bot.named("editMessageText").size(), edits + 1, "and says it once")
	tg3.on_told({"id": 10, "text": "mail", "every": null})
	await _until(func() -> bool: return bot.sent.back()["params"]["text"] == "⏰ mail")
	edits = bot.named("editMessageText").size()
	tg3.sync([9, 7])
	await _until(func() -> bool: return bot.named("editMessageText").size() == edits + 1)
	_eq(
		bot.named("editMessageText").back()["text"],
		"⏰ mail\ndealt with in the house",
		"a reminder no longer ringing is closed"
	)
	# a press in flight is not said twice by the house's own report of it
	tg3.on_told({"id": 11, "text": "post", "every": null})
	await _until(func() -> bool: return bot.sent.back()["params"]["text"] == "⏰ post")
	var held: Array = []
	var tg4 := tg3
	tg4.tapped.disconnect(tg4.tapped.get_connections()[0]["callable"])
	tg4.tapped.connect(func(_i: int, _v: String, finish: Callable) -> void: held.append(finish))
	bot.tap(777, "done:11", bot.sent.back()["mid"], "⏰ post")
	await _until(func() -> bool: return held.size() == 1)
	edits = bot.named("editMessageText").size()
	tg4.handled(11, "done")
	await _settle(0.15)
	_eq(bot.named("editMessageText").size(), edits, "the house's report waits for the press's own")
	held[0].call()
	await _until(func() -> bool: return bot.named("editMessageText").size() == edits + 1)
	_eq(bot.named("editMessageText").back()["text"], "⏰ post\n✓ done", "which says it, once")
	# acted on before Telegram has even answered the send: said once the message exists
	tg3.on_told({"id": 13, "text": "quick", "every": null})
	tg3.handled(13, "done")
	await _until(
		func() -> bool:
			return (
				bot.named("editMessageText").size() > 0
				and bot.named("editMessageText").back()["text"] == "⏰ quick\n✓ done"
			)
	)
	_eq(bot.named("editMessageText").back()["text"], "⏰ quick\n✓ done", "a quick act is still said")
	# a list read before the tell does not close the new message
	tg3.grace = 5.0
	tg3.on_told({"id": 14, "text": "fresh", "every": null})
	await _until(func() -> bool: return bot.sent.back()["params"]["text"] == "⏰ fresh")
	var others: Array = tg3._msgs.keys().filter(func(k): return int(k) != 14)
	edits = bot.named("editMessageText").size()
	tg3.sync(others)
	await _settle(0.15)
	_eq(
		bot.named("editMessageText").size(), edits, "a message younger than the grace is left alone"
	)
	tg3.grace = 0.0
	tg3.sync(others)
	await _until(func() -> bool: return bot.named("editMessageText").size() == edits + 1)
	_eq(
		bot.named("editMessageText").back()["text"],
		"⏰ fresh\ndealt with in the house",
		"and closed after it"
	)
	tg3.stop()

	await _daily(base, bot)
	await _failures(base, bot, said)
	for l in said:
		_eq(str(l).contains(TOKEN), false, "no line the bot says holds the token")
	print(
		(
			"telegram: the stub answered %d requests and took %d messages"
			% [bot.calls.size(), bot.sent.size()]
		)
	)
	s.bot = Callable()
	_wipe()


func _daily(base: String, bot: Bot) -> void:
	var tg := _tg(base, [], [])
	tg.token = TOKEN
	tg.chat = 777
	tg.status = func() -> Dictionary:
		return {
			"open": [{"text": "buy milk"}, {"text": "send photos"}],
			"coming":
			[
				{"text": "dentist", "due_at": "2026-11-19T09:00:00Z"},
				{"text": "later", "due_at": "2026-11-25T09:00:00Z"},
			],
		}
	var n := bot.sent.size()
	t = LocalList.wall(2026, 11, 18, 17, 29)
	tg.daily()
	await _settle(0.15)
	_eq(bot.sent.size(), n, "no day's list before its time")
	t = LocalList.wall(2026, 11, 18, 17, 30)
	tg.daily()
	tg.daily()
	await _until(func() -> bool: return bot.sent.size() == n + 1)
	await _settle(0.15)
	_eq(
		[bot.sent.size() - n, bot.sent.back()["params"]["text"]],
		[1, "Still open: buy milk, send photos; tomorrow: dentist"],
		"at its time, once, the open things and tomorrow's"
	)
	t = LocalList.wall(2026, 11, 19, 17, 31)
	tg.daily()
	await _until(func() -> bool: return bot.sent.size() == n + 2)
	_eq(bot.sent.size() - n, 2, "and again the next day")
	var tg2 := _tg(base, [], [])
	tg2.token = TOKEN
	tg2.chat = 777
	tg2.status = tg.status
	tg2.listed = tg.listed
	tg2.daily()
	await _settle(0.15)
	_eq(bot.sent.size() - n, 2, "a restart the same day does not say it again")
	t = LocalList.wall(2026, 11, 20, 23, 30)
	tg2.list_at = "off"
	tg2.daily()
	await _settle(0.15)
	_eq(bot.sent.size() - n, 2, "off says nothing")
	tg2.list_at = "17:30"
	tg2.daily()
	await _until(func() -> bool: return bot.sent.size() == n + 3)
	_eq(bot.sent.size() - n, 3, "a house opened after the time says it that day")
	t = LocalList.wall(2026, 11, 21, 18)
	tg2.status = func() -> Dictionary: return {"open": [], "coming": []}
	tg2.daily()
	await _settle(0.15)
	_eq(
		[bot.sent.size() - n, tg2.listed],
		[3, "2026-11-21"],
		"with nothing to say it says nothing and counts the day"
	)
	tg.free()
	tg2.free()
	t = LocalList.wall(2026, 11, 18, 14)


func _failures(base: String, bot: Bot, said: Array) -> void:
	var seq: Array = []
	var b := 0.0
	for i in 9:
		b = Telegram.next_backoff(b)
		seq.append(b)
	_eq(
		seq,
		[5.0, 10.0, 20.0, 40.0, 80.0, 160.0, 300.0, 300.0, 300.0],
		"the back-off doubles from 5 s to 5 min"
	)
	var tg := _tg(base, [], [])
	tg.token = TOKEN
	tg.chat = 777
	bot.fail = 500
	var before := bot.attempts
	tg.me = "@x"
	tg.start()
	await _settle(0.5)
	_eq(
		[tg.backoff, tg.problem, bot.attempts - before],
		[5.0, "", 1],
		"a failing network backs off quietly and does not spin"
	)
	tg.stop()
	bot.fail = 0
	var dead := _tg("http://127.0.0.1:1", [], [])
	dead.token = TOKEN
	dead.chat = 777
	dead.me = "@x"
	dead.start()
	await _until(func() -> bool: return dead.backoff > 0.0)
	_eq(
		[dead.backoff, dead.problem],
		[5.0, ""],
		"a connection that is refused backs off quietly too"
	)
	dead.stop()
	dead.free()
	var gone := _tg(base, [], [])
	gone.token = TOKEN
	gone.chat = 777
	bot.token = "revoked"
	gone.start()
	await _until(func() -> bool: return gone.problem != "")
	before = bot.attempts
	await _settle(0.3)
	_eq(
		[gone.problem, bot.attempts - before],
		["Telegram says: Unauthorized", 0],
		"a refused token is said, and the polling stops"
	)
	bot.token = TOKEN
	said.append(gone.problem)
	gone.free()
	tg.free()


func _backend() -> BackendLocal:
	var b := BackendLocal.new()
	b.setup("", Callable(self, "_clock"), 0.0, false)
	b.list.add({"kind": "todo", "text": "buy milk"})
	return b


func _things(b: BackendLocal) -> Array:
	return b.list.things().map(func(x): return x["text"])


# the bot wired into the room over the house's own list, and the settings screen over it
func _in_the_house(main) -> void:
	var h = main._room.home
	var settings = h.settings
	var bot := Bot.new()
	bot.token = TOKEN
	s.bot = Callable(bot, "handle")
	var base := "http://127.0.0.1:%d" % s._srv.get_local_port()
	var ph = main._phone
	ph.base = base
	ph.poll_gap = 0.03
	ph.grace = 0.0
	ph.token = TOKEN
	ph.chat = 777
	ph.me = "@house_stub_bot"
	main.talk_live = true
	var b := _backend()
	main._install(b)
	_eq(main._phone_on(), false, "the bot is off until it is switched on")
	settings.forced["where"] = "local"
	settings.forced["telegram"] = true
	main._apply_talk()
	_eq(main._phone_on(), true, "switched on over the house's own list, it polls")

	# his words from the phone are read and answered like the chat's own, and marked
	bot.text(777, "remind me to call mum tomorrow at 5pm")
	await _until(func() -> bool: return bot.to(777).size() == 1)
	var made: Dictionary = b.list.things().back()
	_eq(
		[made["kind"], made["text"], made["due_at"]],
		["reminder", "call mum", "2026-11-19T17:00:00Z"],
		"a line from the phone is filed"
	)
	var tail: Array = h.chat.messages.slice(-2)
	_eq(
		tail.map(func(m): return [m["who"], m.get("via")]),
		[["me", "phone"], ["home", "phone"]],
		"the chat history marks both as from the phone"
	)
	_eq(bot.to(777)[0]["params"]["text"], tail[1]["text"], "and the reply goes back to Telegram")
	var before: int = b.list.things().size()
	bot.text(555, "buy cake")
	await _settle()
	_eq(b.list.things().size(), before, "another chat files nothing")

	# a reminder comes due: told, its buttons work, the house's own acts are followed
	var tea: int = (
		b.list.add({"kind": "reminder", "text": "tea", "at": "2026-11-18T15:00"})["body"]["id"]
	)
	var gym: int = (
		b.list.add({"kind": "reminder", "text": "gym", "at": "2026-11-18T16:00"})["body"]["id"]
	)
	var water: int = (
		b
		. list
		. add({"kind": "reminder", "text": "water", "at": "2026-11-18T16:00", "every": "week"})["body"]["id"]
	)
	t = LocalList.wall(2026, 11, 18, 15)
	b.list.tick()
	main._poll()
	await _until(func() -> bool: return bot.sent.back()["params"]["text"] == "⏰ tea")
	var tea_msg: Dictionary = bot.sent.back()
	_eq(
		h.chat.messages.filter(func(m): return m.get("id") == tea).size(),
		1,
		"the chat tells it too"
	)
	bot.tap(777, "hour:%d" % tea, tea_msg["mid"], "⏰ tea")
	await _until(func() -> bool: return bot.named("answerCallbackQuery").size() > 0)
	await _until(func() -> bool: return bot.named("editMessageText").size() > 0)
	var row: Dictionary = b.list.status()["coming"].filter(func(x): return x["id"] == tea)[0]
	_eq(
		[
			row["due_at"],
			bot.named("answerCallbackQuery").back()["text"],
			bot.named("editMessageText").back()["text"]
		],
		["2026-11-18T16:00:00Z", "in an hour", "⏰ tea\nin an hour"],
		"In an hour on the phone moves it in the list and says so"
	)
	await _until(
		func() -> bool:
			return (
				(
					h
					. chat
					. messages
					. filter(func(m): return m.get("id") == tea and m.get("done") == "hour")
					. size()
				)
				== 1
			)
	)
	t = LocalList.wall(2026, 11, 18, 16)
	b.list.tick()
	main._poll()
	await _until(
		func() -> bool:
			return (
				bot.to(777).filter(func(m): return m["params"]["text"] == "⏰ gym").size() == 1
				and bot.to(777).filter(func(m): return m["params"]["text"] == "⏰ water").size() == 1
			)
	)
	var gym_first: Dictionary = bot.to(777).filter(func(m): return m["params"]["text"] == "⏰ gym")[0]
	t = LocalList.wall(2026, 11, 18, 16, 30)
	b.list.tick()
	main._poll()
	await _until(
		func() -> bool:
			return bot.to(777).filter(func(m): return m["params"]["text"] == "⏰ gym").size() == 2
	)
	await _until(func() -> bool: return bot.named("editMessageReplyMarkup").size() > 0)
	var cleared := bot.named("editMessageReplyMarkup").filter(
		func(p): return int(p["message_id"]) == gym_first["mid"]
	)
	_eq(
		[cleared.size() >= 1, cleared[0]["reply_markup"]["inline_keyboard"]],
		[true, []],
		"a re-ring in the house sends a new message and clears the old one's buttons"
	)
	var edits := bot.named("editMessageText").size()
	main._on_act(gym, "done")
	await _until(func() -> bool: return bot.named("editMessageText").size() > edits)
	_eq(
		bot.named("editMessageText").back()["text"],
		"⏰ gym\n✓ done",
		"done in the house is said on the phone"
	)
	_eq(
		b.list.status()["open"].filter(func(x): return x["id"] == gym).size(),
		0,
		"and done in the list"
	)
	# a repeating reminder asks twice on the phone
	var water_msg: Dictionary = bot.to(777).filter(func(m): return m["params"]["text"] == "⏰ water")[0]
	_eq(
		_keys(water_msg["params"]["reply_markup"]).back(),
		"ask:%d" % water,
		"a repeating one's Delete asks first"
	)
	bot.tap(777, "ask:%d" % water, water_msg["mid"], "⏰ water")
	bot.tap(777, "yes:%d" % water, water_msg["mid"], "⏰ water\nDelete for good?")
	await _until(
		func() -> bool:
			return (
				b.list.status()["open"].filter(func(x): return x["id"] == water).size() == 0
				and b.list.status()["coming"].filter(func(x): return x["id"] == water).size() == 0
			)
	)
	_eq(_things(b).has("water"), false, "yes deletes it from the list")
	await _until(
		func() -> bool: return bot.named("editMessageText").back()["text"] == "⏰ water\ndeleted"
	)
	_eq(bot.named("editMessageText").back()["text"], "⏰ water\ndeleted", "and says so")
	# dealt with another way: the message loses its buttons
	var bins: int = (
		b.list.add({"kind": "reminder", "text": "bins", "at": "2026-11-18T16:00"})["body"]["id"]
	)
	b.list.tick()
	main._poll()
	await _until(func() -> bool: return bot.sent.back()["params"]["text"] == "⏰ bins")
	edits = bot.named("editMessageText").size()
	b.list.drop(bins)
	main._poll()
	await _until(func() -> bool: return bot.named("editMessageText").size() > edits)
	_eq(
		bot.named("editMessageText").back()["text"],
		"⏰ bins\ndealt with in the house",
		"a reminder that is gone loses its buttons"
	)

	# a reminder that came due while the house was closed is sent when it opens
	var away := "user://soak_telegram_list.json"
	var doc := {
		"v": 1,
		"next_id": 2,
		"things":
		[
			{
				"id": 1,
				"kind": "reminder",
				"text": "closed while away",
				"state": "open",
				"since": "2026-11-17T10:00:00Z",
				"due_at": "2026-11-18T09:00:00Z",
				"every": null
			}
		]
	}
	var af := FileAccess.open(away, FileAccess.WRITE)
	af.store_string(JSON.stringify(doc))
	af.close()
	var opened := BackendLocal.new()
	opened.setup(away, Callable(self, "_clock"), 0.0, false)
	var n := bot.sent.size()
	main._install(opened)
	await _until(func() -> bool: return bot.sent.size() == n + 1)
	_eq(
		[bot.sent.back()["params"]["text"], opened.started.size()],
		["⏰ closed while away", 1],
		"and the bot says it too"
	)
	DirAccess.remove_absolute(away)
	main._install(_backend())

	# the settings screen: masked token, pairing code, last reached, the second click
	var v = main._sidebar.settings_view
	ph.chat = 0
	ph.code = "4821"
	v.open()
	_eq(
		[v._talk_box.visible, v._tg_on.button_pressed, v._tg_box.visible, v._tg_token.secret],
		[true, true, true, true],
		"the settings offer the bot over the house's own list, the token field masked"
	)
	_eq(
		v._tg_state.text,
		"token saved (…%s). Send 4821 to @house_stub_bot in Telegram to pair." % TOKEN.right(4),
		"the saved token is shown by its last four, and the code to send"
	)
	_eq(v._tg_state.text.contains(TOKEN) or v._tg_say.text.contains(TOKEN), false, "never whole")
	ph.chat = 777
	await _until(func() -> bool: return ph.reached_at > 0.0)
	v._refresh()
	_eq(
		[
			v._tg_state.text.begins_with("paired with @house_stub_bot"),
			v._tg_reached.text.begins_with("last reached: ")
		],
		[true, true],
		"paired, and when Telegram was last reached"
	)
	v._tg_at.text = "25:99"
	v._tg_list_at()
	_eq(
		[settings.value("telegram_list_at"), v._tg_at.text],
		["17:30", "17:30"],
		"a time that is not one is put back"
	)
	v._tg_at.text = "18:15"
	v._tg_list_at()
	_eq(
		[settings.value("telegram_list_at"), ph.list_at],
		["18:15", "18:15"],
		"the day's list time is kept and applied"
	)
	v._tg_at.text = "off"
	v._tg_list_at()
	_eq(ph.list_at, "off", "off is allowed")
	settings.put("telegram_list_at", "17:30")
	v._tg_off.pressed.emit()
	v._refresh()
	_eq([v._tg_off.text, ph.token == TOKEN], ["sure?", true], "disconnect asks for a second click")
	v._tg_off.pressed.emit()
	v._refresh()
	_eq(
		[ph.token, ph.chat, ph.offset, v._tg_state.text],
		["", 0, 0, "no bot connected"],
		"and then forgets the token, the chat and the offset"
	)
	v._tg_token.text = "999:wrong-WXYZ"
	v._tg_connect()
	await _until(func() -> bool: return v._tg_say.text != "connecting...")
	_eq(v._tg_say.text, "Telegram says: Unauthorized", "connect says why in one line")
	v._tg_token.text = TOKEN
	v._tg_connect()
	await _until(func() -> bool: return v._tg_say.text == "@house_stub_bot")
	_eq(
		[v._tg_say.text, v._tg_token.text, ph.token == TOKEN],
		["@house_stub_bot", "", true],
		"and the bot's name when it works; the field is emptied"
	)
	v._refresh()
	_eq(
		v._tg_state.text.begins_with("token saved (…%s). Send " % TOKEN.right(4)),
		true,
		"a new bot waits for its code"
	)
	v.close()

	# server mode: neither is offered, and the bot is not polled
	settings.forced["where"] = "server"
	main._make_backend()
	v.open()
	await _settle()
	_eq(
		[v._talk_box.visible, main._phone_on()],
		[false, false],
		"in server mode the bot is not offered"
	)
	var seen_after: int = bot.named("getUpdates").size()
	await _settle()
	_eq(bot.named("getUpdates").size(), seen_after, "and is not polled")
	v.close()
	ph.stop()
	ph.disconnect_bot()
	settings.forced.erase("where")
	settings.forced.erase("telegram")
	main.talk_live = false
	print(
		(
			"telegram in the house: the stub answered %d requests and took %d messages"
			% [bot.calls.size(), bot.sent.size()]
		)
	)
	s.bot = Callable()
	main._make_backend()
