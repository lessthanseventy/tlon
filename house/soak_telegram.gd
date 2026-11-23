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
var phone: Node
var t := 0.0


func _init(soak) -> void:
	s = soak


func _clock() -> float:
	return t


func _eq(got: Variant, want: Variant, what: String) -> void:
	s._check(got == want, "%s: got %s, want %s" % [what, str(got), str(want)])


func _bots() -> Array:
	var out: Array = _made.filter(func(n): return is_instance_valid(n))
	if is_instance_valid(phone):
		out.append(phone)
	return out


func _in_flight(tg: Node) -> int:
	return s._requests(tg)


func _polls(bot) -> int:
	return bot.calls.filter(func(c): return c["method"] == "getUpdates").size()


# until no bot has a request in flight or a line waiting for its reply and, while one polls,
# the stub has seen two more polls and handed out every update: what the bot answered has then
# reached the stub
func _settle() -> void:
	var bot = null if s.bot.is_null() else s.bot.get_object()
	var from: int = 0 if bot == null else _polls(bot)
	await s._until(
		func() -> bool:
			var polling := false
			for tg in _bots():
				polling = polling or tg._running
				if _in_flight(tg) > 0 or tg._busy:
					return false
			return (
				bot == null or not polling or (_polls(bot) - from >= 2 and bot.updates.is_empty())
			),
		"the bot's requests answered and the stub's updates taken"
	)


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
	var gone := 0
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
			"editMessageText":
				if int(params.get("message_id", 0)) == gone:
					return {
						"code": 400,
						"body":
						{"ok": false, "description": "Bad Request: message to edit not found"}
					}
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
	await s._until(func() -> bool: return said.size() == 2)
	_eq(
		said,
		["paste the token first", "Telegram says: Unauthorized"],
		"a missing and a bad token are said in one line"
	)
	await _settle()
	_eq([tg.token, bot.named("getUpdates").size()], ["", 0], "and nothing is kept or asked")
	tg.connect_bot(TOKEN, func(l: String) -> void: said.append(l))
	await s._until(func() -> bool: return said.size() == 3)
	_eq(
		[said[2], tg.token == TOKEN, tg.masked()],
		["@house_stub_bot", true, "…" + TOKEN.right(4)],
		"a good token says the bot's name, and is shown masked"
	)
	await s._until(func() -> bool: return bot.named("getUpdates").size() >= 2)
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
	await s._until(func() -> bool: return tg.chat == 777)
	_eq([tg.chat, tg.code], [777, ""], "the chat that sent the code is the chat")
	await s._until(func() -> bool: return bot.to(777).size() == 1)
	_eq(bot.to(777)[0]["params"]["text"].begins_with("Paired."), true, "and is told so")
	n = bot.sent.size()
	bot.text(555, "hello again")
	bot.text(556, "buy milk")
	await _settle()
	_eq([heard, bot.sent.size() - n], [[], 0], "another chat is ignored after pairing too")

	# a line from the paired chat is the house's to read; the answer goes back
	var id := bot.text(777, "buy stamps")
	await s._until(func() -> bool: return heard.size() == 1)
	await s._until(func() -> bool: return bot.to(777).size() == 2)
	_eq(
		[heard, bot.to(777)[1]["params"]["text"]],
		[["buy stamps"], "re: buy stamps"],
		"a text from the chat is told, and the reply sent"
	)
	bot.text(777, "/start")
	await s._until(func() -> bool: return bot.to(777).size() == 3)
	_eq(
		[heard.size(), bot.to(777)[2]["params"]["text"].begins_with("I'm here")],
		[1, true],
		"/start is greeted, not filed"
	)
	bot.voice(777)
	await s._until(func() -> bool: return bot.to(777).size() == 4)
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
		[7, true, 777, true],
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
	await s._until(func() -> bool: return bot.named("getUpdates").back()["offset"] == tg.offset)
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
	await s._until(func() -> bool: return backlog.size() == 3)
	_eq(backlog, ["one", "two", "three"], "the backlog is read oldest first at start")
	await _settle()

	# a reminder told: a message with buttons
	var tea: Dictionary = {"id": 7, "text": "tea", "every": null}
	n = bot.sent.size()
	tg3.on_told(tea)
	await s._until(func() -> bool: return bot.sent.size() == n + 1)
	var msg: Dictionary = bot.sent.back()
	_eq(
		[msg["params"]["text"], _keys(msg["params"]["reply_markup"])],
		["⏰ tea", ["done:7", "hour:7", "tomorrow:7"]],
		"a told reminder is a message with Done, Later and Skip, which is tomorrow for a one-off"
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
		await s._until(func() -> bool: return bot.sent.size() == n + 1)
		var m: Dictionary = bot.sent.back()
		var answers := bot.named("answerCallbackQuery").size()
		var tap_id := bot.tap(777, "%s:20" % pair[0], m["mid"], "⏰ x")
		await s._until(
			func() -> bool: return bot.named("answerCallbackQuery").size() == answers + 1
		)
		await s._until(
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

	# a repeating one's Skip is its next time, which the list's done is for a repeating reminder
	tg3.on_told({"id": 8, "text": "water", "every": "week"})
	await s._until(func() -> bool: return bot.sent.back()["params"]["text"] == "⏰ water")
	var water: Dictionary = bot.sent.back()
	_eq(
		_keys(water["params"]["reply_markup"]),
		["done:8", "hour:8", "skip:8"],
		"a repeating one's Skip is a button of its own"
	)
	tg3.on_told({"id": 12, "text": "stretch", "every": "day"})
	await s._until(func() -> bool: return bot.sent.back()["params"]["text"] == "⏰ stretch")
	var skipped: Dictionary = bot.sent.back()
	var before_skip := bot.named("editMessageText").size()
	tg3.card = {"items": [{"id": 12}], "ticked": []}
	bot.tap(777, "skip:12", skipped["mid"], "⏰ stretch")
	await s._until(func() -> bool: return bot.named("editMessageText").size() == before_skip + 1)
	_eq(tg3.card["ticked"], [], "a skipped repeating reminder is not ticked on the day's card")
	tg3.card = {}
	_eq(
		[taps.back(), bot.named("editMessageText").back()["text"]],
		[[12, "done"], "⏰ stretch\nskipped to its next time"],
		"Skip moves it on through the list's done, and says it was skipped"
	)
	# a message from before carries the old Delete: it still asks again
	presses = taps.size()
	var edits := bot.named("editMessageText").size()
	bot.tap(777, "ask:8", water["mid"], "⏰ water")
	await s._until(func() -> bool: return bot.named("editMessageText").size() == edits + 1)
	var ask: Dictionary = bot.named("editMessageText").back()
	_eq(
		[ask["text"], _keys(ask["reply_markup"]), taps.size()],
		["⏰ water\nDelete for good?", ["yes:8", "no:8"], presses],
		"the second keyboard says yes or no, and deletes nothing"
	)
	bot.tap(777, "no:8", water["mid"], ask["text"])
	await s._until(func() -> bool: return bot.named("editMessageText").size() == edits + 2)
	var back: Dictionary = bot.named("editMessageText").back()
	_eq(
		[back["text"], _keys(back["reply_markup"]).size(), taps.size()],
		["⏰ water", 3, presses],
		"no puts the buttons back"
	)
	bot.tap(777, "yes:8", water["mid"], ask["text"])
	await s._until(func() -> bool: return taps.size() == presses + 1)
	await s._until(func() -> bool: return bot.named("editMessageText").size() == edits + 3)
	_eq(
		[taps.back(), bot.named("editMessageText").back()["text"]],
		[[8, "delete"], "⏰ water\ndeleted"],
		"yes deletes it for good"
	)

	# a re-ring: the old message is deleted and the new one, at the bottom, says since when
	tg3.on_told({"id": 9, "text": "gym", "every": null})
	await s._until(func() -> bool: return bot.sent.back()["params"]["text"] == "⏰ gym")
	var old: Dictionary = bot.sent.back()
	n = bot.sent.size()
	t += 1800.0
	tg3.on_told({"id": 9, "text": "gym", "every": null})
	await s._until(func() -> bool: return bot.sent.size() == n + 1)
	await s._until(func() -> bool: return bot.named("deleteMessage").size() > 0)
	_eq(
		[
			bot.sent.back()["params"]["text"],
			_keys(bot.sent.back()["params"]["reply_markup"]).size(),
			int(bot.named("deleteMessage").back()["message_id"])
		],
		["⏰ gym · still waiting since 14:00", 3, old["mid"]],
		"a re-ring sends it again, still waiting since its first tell, and deletes the old"
	)
	t -= 1800.0

	# acted in the house: the message follows
	var fresh: Dictionary = bot.sent.back()
	edits = bot.named("editMessageText").size()
	tg3.handled(9, "done")
	await s._until(func() -> bool: return bot.named("editMessageText").size() == edits + 1)
	var followed: Dictionary = bot.named("editMessageText").back()
	_eq(
		[
			int(followed["message_id"]),
			followed["text"],
			followed["reply_markup"]["inline_keyboard"]
		],
		[fresh["mid"], "⏰ gym · still waiting since 14:00\n✓ done", []],
		"done in the house takes the buttons off and says so"
	)
	tg3.handled(9, "done")
	await _settle()
	_eq(bot.named("editMessageText").size(), edits + 1, "and says it once")
	tg3.on_told({"id": 10, "text": "mail", "every": null})
	await s._until(func() -> bool: return bot.sent.back()["params"]["text"] == "⏰ mail")
	edits = bot.named("editMessageText").size()
	tg3.sync([9, 7])
	await s._until(func() -> bool: return bot.named("editMessageText").size() == edits + 1)
	_eq(
		bot.named("editMessageText").back()["text"],
		"⏰ mail\ndealt with in the house",
		"a reminder no longer ringing is closed"
	)
	# a press in flight is not said twice by the house's own report of it
	tg3.on_told({"id": 11, "text": "post", "every": null})
	await s._until(func() -> bool: return bot.sent.back()["params"]["text"] == "⏰ post")
	var held: Array = []
	var tg4 := tg3
	tg4.tapped.disconnect(tg4.tapped.get_connections()[0]["callable"])
	tg4.tapped.connect(func(_i: int, _v: String, finish: Callable) -> void: held.append(finish))
	bot.tap(777, "done:11", bot.sent.back()["mid"], "⏰ post")
	await s._until(func() -> bool: return held.size() == 1)
	edits = bot.named("editMessageText").size()
	tg4.handled(11, "done")
	await _settle()
	_eq(bot.named("editMessageText").size(), edits, "the house's report waits for the press's own")
	held[0].call()
	await s._until(func() -> bool: return bot.named("editMessageText").size() == edits + 1)
	_eq(bot.named("editMessageText").back()["text"], "⏰ post\n✓ done", "which says it, once")
	# acted on before Telegram has even answered the send: said once the message exists
	tg3.on_told({"id": 13, "text": "quick", "every": null})
	tg3.handled(13, "done")
	await s._until(
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
	await s._until(func() -> bool: return bot.sent.back()["params"]["text"] == "⏰ fresh")
	var others: Array = tg3._msgs.keys().filter(func(k): return int(k) != 14)
	edits = bot.named("editMessageText").size()
	tg3.sync(others)
	await _settle()
	_eq(
		bot.named("editMessageText").size(), edits, "a message younger than the grace is left alone"
	)
	tg3.grace = 0.0
	tg3.sync(others)
	await s._until(func() -> bool: return bot.named("editMessageText").size() == edits + 1)
	_eq(
		bot.named("editMessageText").back()["text"],
		"⏰ fresh\ndealt with in the house",
		"and closed after it"
	)
	tg3.stop()

	await _daily(base, bot)
	await _moves(base, bot)
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


func _row(id: int, text: String, due: Variant = null) -> Dictionary:
	return {"id": id, "kind": "todo" if due == null else "reminder", "text": text, "due_at": due}


func _cards(bot: Bot, n: int) -> Array:
	return bot.sent.slice(n).filter(
		func(m):
			return (
				str(m["params"]["text"]).begins_with("Today · ")
				or str(m["params"]["text"]).begins_with("This evening · ")
			)
	)


# A day of the card against the stub: one message in the morning, edited by every tick and
# change, never posted again; in the evening one in its place at the bottom; a weekend evening
# with nothing moved says nothing.
func _daily(base: String, bot: Bot) -> void:
	var st := {
		"open": [_row(1, "buy milk"), _row(2, "send photos")],
		"coming": [_row(3, "dentist", "2026-11-18T15:00:00Z")],
		"done": [],
	}
	var taps: Array = []
	var tg := _tg(base, [], taps)
	tg.token = TOKEN
	tg.chat = 777
	tg.status = func() -> Dictionary: return st
	var n := bot.sent.size()
	t = LocalList.wall(2026, 11, 18, 8, 29)
	tg.daily()
	await _settle()
	_eq(bot.sent.size(), n, "no card before its time")
	t = LocalList.wall(2026, 11, 18, 8, 30)
	tg.daily()
	tg.daily()
	await s._until(func() -> bool: return int(tg.card.get("mid", 0)) != 0)
	await _settle()
	var morning: Dictionary = bot.sent.back()
	_eq(
		[bot.sent.size() - n, morning["params"]["text"], _keys(morning["params"]["reply_markup"])],
		[
			1,
			"Today · Wed 18 Nov\n\nTo do\n1. buy milk\n2. send photos\n3. 15:00 dentist",
			["card:tick"]
		],
		"at its time, once, the day's card"
	)
	var mid: int = morning["mid"]

	# a reply by number ticks through the house, says so, and edits the card
	var edits := bot.named("editMessageText").size()
	bot.text(777, "2")
	tg.start()
	await s._until(func() -> bool: return bot.named("editMessageText").size() == edits + 1)
	await _settle()
	var edit: Dictionary = bot.named("editMessageText").back()
	_eq(
		[taps, bot.sent.back()["params"]["text"], int(edit["message_id"]), edit["text"]],
		[
			[[2, "done"]],
			"✓ send photos",
			mid,
			"Today · Wed 18 Nov\n\nTo do\n1. buy milk\n2. ✓ send photos\n3. 15:00 dentist"
		],
		'"2" ticks the second, says it, and edits the card in place'
	)
	bot.text(777, "2 9")
	await s._until(func() -> bool: return bot.sent.back()["params"]["text"].begins_with("Nothing"))
	_eq(
		[taps.size(), bot.sent.back()["params"]["text"]],
		[1, "Nothing to tick at 2, 9."],
		"a number already ticked or not on the card ticks nothing"
	)

	# the ✓ button opens the numbers; a number ticks it and closes them
	edits = bot.named("editMessageText").size()
	bot.tap(777, "card:tick", mid, "")
	await s._until(func() -> bool: return bot.named("editMessageText").size() == edits + 1)
	_eq(
		_keys(bot.named("editMessageText").back()["reply_markup"]),
		["card:1", "card:3", "card:back"],
		"✓ Tick… shows the numbers still to tick, and Back"
	)
	var answers := bot.named("answerCallbackQuery").size()
	bot.tap(777, "card:3", mid, "")
	await s._until(func() -> bool: return bot.named("answerCallbackQuery").size() == answers + 1)
	await s._until(func() -> bool: return bot.named("editMessageText").size() == edits + 2)
	_eq(
		[
			taps.back(),
			bot.named("answerCallbackQuery").back()["text"],
			_keys(bot.named("editMessageText").back()["reply_markup"])
		],
		[[3, "done"], "✓ 15:00 dentist", ["card:tick"]],
		"a number ticks it, says so on the button, and the keyboard is back"
	)
	answers = bot.named("answerCallbackQuery").size()
	bot.tap(777, "card:1", 4242, "")
	await s._until(func() -> bool: return bot.named("answerCallbackQuery").size() == answers + 1)
	_eq(
		[taps.size(), bot.named("answerCallbackQuery").back()["text"]],
		[2, "that card is from another day"],
		"a press on an older card ticks nothing"
	)

	# the list moves: the card follows, once, and keeps its numbers
	st["open"] = [_row(1, "buy milk"), _row(4, "pay rent")]
	st["coming"] = []
	st["done"] = [{"text": "send photos", "done_at": "2026-11-18T10:00:00Z"}]
	edits = bot.named("editMessageText").size()
	tg.sync([])
	tg.sync([])
	await _settle()
	_eq(
		[bot.named("editMessageText").size() - edits, bot.named("editMessageText").back()["text"]],
		[
			1,
			"Today · Wed 18 Nov\n\nTo do\n1. buy milk\n2. ✓ send photos\n3. ✓ 15:00 dentist\n4. pay rent"
		],
		"a new thing is numbered on the card, edited once"
	)
	st["open"] = [_row(1, "buy milk"), _row(4, "pay rent"), _row(5, "call mum")]
	edits = bot.named("editMessageText").size()
	bot.fail = 500
	var tries := bot.attempts
	tg.sync([])
	await s._until(func() -> bool: return bot.attempts > tries)
	await s._until(func() -> bool: return str(tg.card["sent"]) == "")
	bot.fail = 0
	tg.sync([])
	await s._until(func() -> bool: return bot.named("editMessageText").size() == edits + 1)
	_eq(
		"call mum" in str(bot.named("editMessageText").back()["text"]),
		true,
		"a refused edit is tried again on the next change"
	)
	edits = bot.named("editMessageText").size()
	n = bot.sent.size()
	bot.gone = int(tg.card["mid"])
	st["open"] = [_row(1, "buy milk"), _row(4, "pay rent"), _row(6, "water plants")]
	tg.sync([])
	await s._until(func() -> bool: return bot.sent.size() == n + 1)
	await s._until(func() -> bool: return int(tg.card["mid"]) == int(bot.sent.back()["mid"]))
	var resent: String = bot.sent.back()["params"]["text"]
	_eq(
		[bot.named("editMessageText").size() - edits, "water plants" in resent],
		[1, true],
		"a card whose message is gone is sent anew, not edited again"
	)
	tg.sync([])
	await _settle()
	_eq(bot.named("editMessageText").size() - edits, 1, "and the new message is not retried")
	bot.gone = 0
	tg.card["mid"] = mid
	tg._save()
	st["open"] = [_row(1, "buy milk"), _row(4, "pay rent")]
	tg.stop()
	var tg2 := _tg(base, [], taps)
	tg2.load_state()
	tg2.status = tg.status
	_eq([int(tg2.card["mid"]), tg2.card["ticked"]], [mid, [2, 3]], "a restart keeps the card")

	# the evening: one new card in place of the morning's, which is deleted
	n = bot.sent.size()
	t = LocalList.wall(2026, 11, 18, 17, 30)
	tg2.daily()
	tg2.daily()
	await s._until(
		func() -> bool:
			return bot.named("deleteMessage").any(func(p): return int(p["message_id"]) == mid)
	)
	await _settle()
	_eq(
		[_cards(bot, n).size(), bot.sent.back()["params"]["text"]],
		[
			1,
			"This evening · Wed 18 Nov\n\nDone today: send photos\n\nStill to do\n1. buy milk\n4. pay rent"
		],
		"at the evening's time the card is sent again at the bottom, and the morning's deleted"
	)
	_eq(bot.sent.back()["params"]["text"].contains("clock out"), false, "and never says clock out")

	# a weekend: the evening only when the day moved
	n = bot.sent.size()
	st["done"] = []
	t = LocalList.wall(2026, 11, 21, 8, 30)
	tg2.daily()
	await s._until(func() -> bool: return _cards(bot, n).size() == 1)
	var saturday := int(tg2.card["mid"])
	t = LocalList.wall(2026, 11, 21, 17, 30)
	tg2.daily()
	tg2.sync([])
	await _settle()
	_eq(
		bot.named("editMessageText").filter(func(p): return int(p["message_id"]) == saturday),
		[],
		"and leaves the morning's card as it is"
	)
	_eq(
		[_cards(bot, n).size(), tg2.listed],
		[1, "2026-11-21"],
		"a Saturday evening with nothing moved says nothing"
	)
	t = LocalList.wall(2026, 11, 22, 8, 30)
	tg2.daily()
	await s._until(func() -> bool: return _cards(bot, n).size() == 2)
	st["done"] = [{"text": "pay rent", "done_at": "2026-11-22T12:00:00Z"}]
	t = LocalList.wall(2026, 11, 22, 17, 30)
	tg2.daily()
	await s._until(func() -> bool: return _cards(bot, n).size() == 3)
	_eq(
		bot.sent.back()["params"]["text"].begins_with(
			"This evening · Sun 22 Nov\n\nDone today: pay rent"
		),
		true,
		"a Sunday that moved gets its evening"
	)

	# off, nothing to say, a house opened late
	n = bot.sent.size()
	tg2.morning_at = "off"
	t = LocalList.wall(2026, 11, 23, 9)
	tg2.daily()
	await _settle()
	_eq(bot.sent.size() - n, 0, "a morning that is off says nothing")
	t = LocalList.wall(2026, 11, 23, 23)
	tg2.daily()
	await s._until(func() -> bool: return _cards(bot, n).size() == 1)
	_eq(
		bot.sent.back()["params"]["text"].begins_with("This evening · Mon 23 Nov"),
		true,
		"a house opened after the evening's time says it that day, once"
	)
	var before := bot.sent.size()
	t = LocalList.wall(2026, 11, 28, 23)
	tg2.daily()
	await _settle()
	_eq(bot.sent.size() - before, 0, "a weekend evening with no morning card, nothing done: nothing")
	tg2.morning_at = "08:30"
	st["open"] = []
	t = LocalList.wall(2026, 11, 24, 9)
	tg2.daily()
	await _settle()
	_eq(
		[bot.sent.size() - n, tg2.card["day"]],
		[1, "2026-11-24"],
		"with nothing to say no card, and the day counts"
	)
	tg.free()
	tg2.free()
	t = LocalList.wall(2026, 11, 18, 14)


func _move(key: String, text: String, date: String = "") -> Dictionary:
	return {"key": key, "kind": "proposal", "text": text, "why": "because", "date": date}


func _rung(bot: Bot, n: int) -> Array:
	return bot.sent.slice(n).filter(func(m): return m["params"]["text"].begins_with("Your move\n"))


# Your move on the day's card: lettered, settled by a button or typed, then "Done: A · Dropped: B";
# and an urgent one as its own message, rung once, never in quiet hours or with the window in front,
# edited when it is settled on the card, on its own button or anywhere.
func _moves(base: String, bot: Bot) -> void:
	var st := {
		"open": [],
		"coming": [],
		"done": [],
		"moves": [_move("a", "Move $120", "2026-12-30"), _move("b", "Nudge Sam", "2026-12-30")],
		"moves_settled": {}
	}
	var tg := _tg(base, [], [])
	tg.token = TOKEN
	tg.chat = 777
	tg.status = func() -> Dictionary: return st
	tg.moved.connect(
		func(key: String, choice: String, finish: Callable) -> void:
			st["moves"] = st["moves"].filter(func(m): return m["key"] != key)
			st["moves_settled"][key] = choice
			finish.call({"ok": "%s %s" % [choice, key]})
	)
	var n := bot.sent.size()
	t = LocalList.wall(2026, 11, 23, 8, 30)
	tg.daily()
	await s._until(func() -> bool: return int(tg.card.get("mid", 0)) != 0)
	await _settle()
	var card: Dictionary = bot.sent.back()
	_eq(
		[card["params"]["text"], _keys(card["params"]["reply_markup"])],
		[
			"Today · Mon 23 Nov\n\nYour move\nA. Move $120\nB. Nudge Sam",
			["card:go:A", "card:go:B", "card:pick"]
		],
		"the day's card letters Your move, with Go for each and Pick…"
	)
	var notes := {"open": [], "coming": [], "done": [], "moves": st["moves"], "notices": [{}, {}]}
	_eq(
		Telegram.card_text(tg.card, notes, t, 0).ends_with("\n\n2 money"),
		true,
		"the card ends in one Notices line, a count, never a row to tick"
	)
	notes["notices"] = []
	_eq(
		Telegram.card_text(tg.card, notes, t, 0).contains("money"),
		false,
		"no notices, no line"
	)
	var edits := bot.named("editMessageText").size()
	bot.text(777, "go A")
	tg.start()
	await s._until(func() -> bool: return bot.named("editMessageText").size() == edits + 1)
	await _settle()
	_eq(
		[
			bot.sent.back()["params"]["text"],
			bot.named("editMessageText").back()["text"],
			bot.named("editMessageText").back()["message_id"] == card["mid"]
		],
		[
			"A: go a",
			"Today · Mon 23 Nov\n\nYour move\nB. Nudge Sam\nDone: A",
			true
		],
		'"go A" settles it through the house, says so, and edits the card'
	)
	edits = bot.named("editMessageText").size()
	bot.tap(777, "card:pick", card["mid"], "")
	await s._until(func() -> bool: return bot.named("editMessageText").size() == edits + 1)
	_eq(
		_keys(bot.named("editMessageText").back()["reply_markup"]),
		["card:go:B", "card:no:B", "card:back"],
		"Pick… opens Go and No for what waits"
	)
	edits = bot.named("editMessageText").size()
	bot.tap(777, "card:no:B", card["mid"], "")
	await s._until(func() -> bool: return bot.named("editMessageText").size() == edits + 1)
	await _settle()
	_eq(
		[bot.named("editMessageText").back()["text"], bot.named("editMessageText").back()["reply_markup"]],
		["Today · Mon 23 Nov\n\nYour move\nDone: A · Dropped: B", {"inline_keyboard": []}],
		"a press settles the last one, and the card reads Done and Dropped"
	)

	n = bot.sent.size()
	tg.card = {}
	tg.noticed = null
	t = LocalList.wall(2026, 11, 23, 12)
	st["moves"] = []
	tg.on_moves(false)
	st["moves"] = [_move("u1", "Pay Sam", "2026-11-24"), _move("n1", "Later", "2026-12-30")]
	tg.on_moves(true)
	st["moves"].append(_move("u2", "Book it", "2026-11-24"))
	t = LocalList.wall(2026, 11, 23, 18)
	tg.on_moves(false)
	await _settle()
	_eq(_rung(bot, n).size(), 0, "nothing is rung for the first look, with the window in front, or in quiet hours")
	t = LocalList.wall(2026, 11, 23, 12)
	st["moves"].append(_move("u3", "Call the vet", "2026-11-25"))
	tg.on_moves(false)
	tg.on_moves(false)
	await s._until(func() -> bool: return _rung(bot, n).size() == 1)
	await _settle()
	var urgent: Dictionary = _rung(bot, n)[0]
	_eq(
		[urgent["params"]["text"], _keys(urgent["params"]["reply_markup"])],
		["Your move\nCall the vet\nbecause", ["move:go:u3", "move:no:u3"]],
		"a new urgent one is its own message, once, with Go and No"
	)
	edits = bot.named("editMessageText").size()
	bot.tap(777, "move:go:u3", urgent["mid"], "")
	await s._until(func() -> bool: return bot.named("editMessageText").size() == edits + 1)
	await _settle()
	_eq(
		[bot.named("editMessageText").back()["text"], bot.named("editMessageText").back()["message_id"] == urgent["mid"]],
		["Your move\nCall the vet\nbecause\nDone", true],
		"its Go settles it through the house and edits it"
	)
	st["moves"].append(_move("u4", "Renew", "2026-11-24"))
	tg.on_moves(false)
	tg.on_moves(false)
	await s._until(func() -> bool: return _rung(bot, n).size() == 2)
	await _settle()
	edits = bot.named("editMessageText").size()
	st["moves"] = st["moves"].filter(func(m): return m["key"] != "u4")
	st["moves_settled"]["u4"] = "no"
	tg.on_moves(false)
	await s._until(func() -> bool: return bot.named("editMessageText").size() == edits + 1)
	_eq(
		bot.named("editMessageText").back()["text"],
		"Your move\nRenew\nbecause\nDropped",
		"one settled anywhere else is edited too"
	)
	tg.stop()
	await _settle()
	tg.free()
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
	await s._until(func() -> bool: return tg.backoff > 0.0, "the failing poll backs off")
	await s._quiet(0.3)
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
	await s._until(func() -> bool: return dead.backoff > 0.0)
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
	await s._until(func() -> bool: return gone.problem != "")
	before = bot.attempts
	await s._quiet(0.2)
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
	phone = ph
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
	await s._until(func() -> bool: return bot.to(777).size() == 1)
	var made: Dictionary = b.list.things().back()
	_eq(
		[made["kind"], made["text"], made["due_at"]],
		["reminder", "call mum", "2026-11-19T17:00:00Z"],
		"a line from the phone is filed"
	)
	var tail: Array = h.chat.messages.filter(func(m): return m.get("via") == "phone").slice(-2)
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
	await s._until(func() -> bool: return bot.sent.back()["params"]["text"] == "⏰ tea")
	var tea_msg: Dictionary = bot.sent.back()
	_eq(
		h.chat.messages.filter(func(m): return m.get("id") == tea).size(),
		1,
		"the chat tells it too"
	)
	bot.tap(777, "hour:%d" % tea, tea_msg["mid"], "⏰ tea")
	await s._until(func() -> bool: return bot.named("answerCallbackQuery").size() > 0)
	await s._until(func() -> bool: return bot.named("editMessageText").size() > 0)
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
	await s._until(
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
	var gyms := func() -> Array:
		return bot.to(777).filter(func(m): return m["params"]["text"].begins_with("⏰ gym"))
	await s._until(
		func() -> bool:
			return (
				gyms.call().size() == 1
				and bot.to(777).filter(func(m): return m["params"]["text"] == "⏰ water").size() == 1
			)
	)
	var gym_first: Dictionary = gyms.call()[0]
	t = LocalList.wall(2026, 11, 18, 16, 30)
	b.list.tick()
	main._poll()
	await s._until(func() -> bool: return gyms.call().size() == 2)
	await s._until(
		func() -> bool:
			return bot.named("deleteMessage").any(
				func(p): return int(p["message_id"]) == gym_first["mid"]
			),
		"the old message deleted"
	)
	_eq(
		gyms.call()[1]["params"]["text"].begins_with("⏰ gym · still waiting since "),
		true,
		"a re-ring in the house sends it again, still waiting, and deletes the old one"
	)
	var edits := bot.named("editMessageText").size()
	main._on_act(gym, "done")
	await s._until(func() -> bool: return bot.named("editMessageText").size() > edits)
	_eq(
		bot.named("editMessageText").back()["text"],
		gyms.call()[1]["params"]["text"] + "\n✓ done",
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
		"skip:%d" % water,
		"a repeating one has Skip"
	)
	bot.tap(777, "ask:%d" % water, water_msg["mid"], "⏰ water")
	bot.tap(777, "yes:%d" % water, water_msg["mid"], "⏰ water\nDelete for good?")
	await s._until(
		func() -> bool:
			return (
				b.list.status()["open"].filter(func(x): return x["id"] == water).size() == 0
				and b.list.status()["coming"].filter(func(x): return x["id"] == water).size() == 0
			)
	)
	_eq(_things(b).has("water"), false, "yes deletes it from the list")
	await s._until(
		func() -> bool: return bot.named("editMessageText").back()["text"] == "⏰ water\ndeleted"
	)
	_eq(bot.named("editMessageText").back()["text"], "⏰ water\ndeleted", "and says so")
	# dealt with another way: the message loses its buttons
	var bins: int = (
		b.list.add({"kind": "reminder", "text": "bins", "at": "2026-11-18T16:00"})["body"]["id"]
	)
	b.list.tick()
	main._poll()
	await s._until(func() -> bool: return bot.sent.back()["params"]["text"] == "⏰ bins")
	edits = bot.named("editMessageText").size()
	b.list.drop(bins)
	main._poll()
	await s._until(func() -> bool: return bot.named("editMessageText").size() > edits)
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
	await s._until(func() -> bool: return bot.sent.size() == n + 1)
	_eq(
		[bot.sent.back()["params"]["text"], opened.started.size()],
		["⏰ closed while away", 1],
		"and the bot says it too"
	)
	DirAccess.remove_absolute(away)
	var fresh := _backend()
	main._install(fresh)

	# the day's card over the house's own list: a number replied is done in the list
	var real_clock: Callable = ph.clock
	ph.clock = Callable(self, "_clock")
	ph.card = {}
	ph.listed = ""
	t = LocalList.wall(2026, 11, 19, 8, 30)
	var milk: int = fresh.list.status()["open"][0]["id"]
	ph.daily()
	await s._until(func() -> bool: return int(ph.card.get("mid", 0)) != 0, "the house's card sent")
	_eq(
		bot.sent.back()["params"]["text"],
		"Today · Thu 19 Nov\n\nTo do\n1. buy milk",
		"the house's card numbers its own list"
	)
	var card_mid := int(ph.card["mid"])
	var card_edits := func() -> Array:
		return bot.named("editMessageText").filter(
			func(p): return int(p["message_id"]) == card_mid
		)
	bot.text(777, "1")
	await s._until(func() -> bool: return not card_edits.call().is_empty(), "the card edited")
	_eq(
		[
			fresh.list.status()["open"].any(func(x): return x["id"] == milk),
			card_edits.call().back()["text"]
		],
		[false, "Today · Thu 19 Nov\n\nTo do\n1. ✓ buy milk"],
		"\"1\" from the phone is done in the list, and the card is edited"
	)
	ph.clock = real_clock
	ph.card = {}
	t = LocalList.wall(2026, 11, 18, 14)

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
	await s._until(func() -> bool: return ph.reached_at > 0.0)
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
	v._tg_time("telegram_list_at")
	_eq(
		[settings.value("telegram_list_at"), v._tg_at.text],
		["17:30", "17:30"],
		"a time that is not one is put back"
	)
	v._tg_at.text = "18:15"
	v._tg_time("telegram_list_at")
	_eq(
		[settings.value("telegram_list_at"), ph.list_at],
		["18:15", "18:15"],
		"the evening card's time is kept and applied"
	)
	v._tg_at.text = "off"
	v._tg_time("telegram_list_at")
	_eq(ph.list_at, "off", "off is allowed")
	settings.put("telegram_list_at", "17:30")
	_eq(
		[settings.value("telegram_morning_at"), v._tg_morning.text, ph.morning_at],
		["08:30", "08:30", "08:30"],
		"the morning card is at 08:30 until changed"
	)
	v._tg_morning.text = "7:45"
	v._tg_time("telegram_morning_at")
	_eq(
		[settings.value("telegram_morning_at"), ph.morning_at],
		["7:45", "7:45"],
		"and its time is kept and applied"
	)
	v._tg_morning.text = "noon"
	v._tg_time("telegram_morning_at")
	_eq(v._tg_morning.text, "7:45", "a time that is not one is put back")
	settings.put("telegram_morning_at", "08:30")
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
	await s._until(func() -> bool: return v._tg_say.text != "connecting...")
	_eq(v._tg_say.text, "Telegram says: Unauthorized", "connect says why in one line")
	v._tg_token.text = TOKEN
	v._tg_connect()
	await s._until(func() -> bool: return v._tg_say.text == "@house_stub_bot")
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
	await s._quiet(0.3)
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
