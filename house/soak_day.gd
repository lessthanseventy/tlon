extends RefCounted

# One day of the house over its own list, the clock driven, the phone a stub of Telegram, the
# `claude` program a fake: the morning card, a reminder told, a line from the phone, a to-do made
# and closed, a waiting-on closed by a reply, an edit made outside the house kept, a money question
# answered, the evening card. The data is a made-up list and bank; `TLON_DAY_FROM=DIR` copies
# `house_list.json` and `house_bank.json` from DIR (a data folder of a real house) in their place,
# into the soak's own throwaway `user://`; the live folder is never written and never driven.
const LocalList := preload("res://local_list.gd")
const BackendLocal := preload("res://backend_local.gd")
const TelegramSoak := preload("res://soak_telegram.gd")
const TalkSoak := preload("res://soak_talk.gd")
const Ask := preload("res://ask.gd")
const TOKEN := "123456:SOAK-not-a-real-token-ABCdef"
const CHAT := 777
const FROM := "TLON_DAY_FROM"
# the loose-line reader and the money chat both run `claude`: the prompt that asks for a plan of
# "asks" gets the plan, any other a sentence that is no reading and fails the engine's checks, so
# the answer is the engine's own wording of the bank
const FAKE := """#!/bin/sh
d=$(dirname "$0")
cat > /dev/null
case "$2" in *'{"asks"'*) cat "$d/plan.json" ;; *) cat "$d/sentence.json" ;; esac
"""

var s
var tg
var talk
var _runs := 0


func _init(soak) -> void:
	s = soak
	tg = TelegramSoak.new(soak)
	talk = TalkSoak.new(soak)


func _eq(got: Variant, want: Variant, what: String) -> void:
	s._check(got == want, "%s: got %s, want %s" % [what, str(got), str(want)])


func _copy(name: String, dir: String) -> bool:
	var from := dir.path_join(name)
	if not FileAccess.file_exists(from):
		return false
	var f := FileAccess.open("user://" + name, FileAccess.WRITE)
	f.store_buffer(FileAccess.get_file_as_bytes(from))
	f.close()
	FileAccess.set_unix_permissions(
		"user://" + name, FileAccess.UNIX_READ_OWNER | FileAccess.UNIX_WRITE_OWNER
	)
	return true


# the day's data: the real files when asked for, else a small list and bank made here
func _seed(list: BackendLocal) -> String:
	var dir := OS.get_environment(FROM)
	if dir != "":
		var got := [_copy("house_list.json", dir), _copy("house_bank.json", dir)]
		_eq(got, [true, true], "%s names a folder with house_list.json and house_bank.json" % FROM)
		return "copied from " + dir
	list.list.add({"kind": "todo", "text": "buy milk"})
	list.list.add({"kind": "todo", "text": "send photos"})
	return "made here"


func _bank_file() -> void:
	var f := FileAccess.open("user://house_bank.json", FileAccess.WRITE)
	(
		f
		. store_string(
			(
				JSON
				. stringify(
					{
						"format": 2,
						"as_of": "2026-11-25T06:00:00Z",
						"accounts":
						[
							{
								"id": "a1",
								"name": "Checking",
								"type": "depository",
								"subtype": "checking",
								"current": 123456,
								"available": 123456
							}
						],
						"transactions":
						[
							{
								"id": "t1",
								"account_id": "a1",
								"cents": 1234,
								"date": "2026-11-24",
								"name": "Cafe",
								"merchant": "Cafe",
								"category": null,
								"made": null,
								"pending": false
							}
						],
					}
				)
			)
		)
	)
	f.close()
	FileAccess.set_unix_permissions(
		"user://house_bank.json", FileAccess.UNIX_READ_OWNER | FileAccess.UNIX_WRITE_OWNER
	)


func _wipe() -> void:
	for f in [
		"house_list.json",
		"house_list.bak.json",
		"house_bank.json",
		"house_moves.json",
		"soak_telegram.json"
	]:
		if FileAccess.file_exists("user://" + f):
			DirAccess.remove_absolute("user://" + f)


func run(main) -> void:
	tg.t = LocalList.wall(2026, 11, 25, 7)
	var dir := OS.get_environment(FROM)
	_wipe()
	if dir == "":
		_bank_file()
	var plaid := {}
	for k in ["PLAID_CLIENT_ID", "PLAID_SECRET", "PLAID_ACCESS_TOKEN"]:
		plaid[k] = OS.get_environment(k)
		OS.set_environment(k, "soak")
	var path := OS.get_environment("PATH")
	var fake := ProjectSettings.globalize_path(TalkSoak.DIR)
	DirAccess.make_dir_recursive_absolute(fake)
	var f := FileAccess.open(fake.path_join("claude"), FileAccess.WRITE)
	f.store_string(FAKE)
	f.close()
	FileAccess.set_unix_permissions(fake.path_join("claude"), 0x1ED)
	talk._dir = fake
	OS.set_environment("PATH", fake + ":" + path)

	await _the_day(main, dir)

	OS.set_environment("PATH", path)
	for k in plaid:
		OS.set_environment(k, plaid[k])
	_wipe()
	for n in tg._made:
		if is_instance_valid(n):
			n.queue_free()
	for name in ["claude", "plan.json", "sentence.json"]:
		if FileAccess.file_exists(fake.path_join(name)):
			DirAccess.remove_absolute(fake.path_join(name))
	DirAccess.remove_absolute(fake)


func _the_day(main, dir: String) -> void:
	var h = main._room.home
	var bot := TelegramSoak.Bot.new()
	bot.token = TOKEN
	s.bot = Callable(bot, "handle")
	var ph = main._phone
	tg.phone = ph
	ph.base = "http://127.0.0.1:%d" % s._srv.get_local_port()
	ph.poll_gap = 0.03
	ph.grace = 0.0
	ph.token = TOKEN
	ph.chat = CHAT
	ph.me = "@house_stub_bot"
	ph.clock = Callable(tg, "_clock")
	ph.morning_at = "08:30"
	ph.list_at = "17:30"
	main.talk_live = true

	var b := BackendLocal.new()
	var made := ""
	if dir != "":
		made = _seed(b)
	b.setup("user://house_list.json", Callable(tg, "_clock"), 0.0, true)
	if dir == "":
		made = _seed(b)
	print("day: the data was %s; %d things open" % [made, b.list.status()["open"].size()])
	b.claude = load("res://reader_claude.gd").new()
	b.claude.command = "claude"
	main._install(b)
	h.settings.forced["where"] = "local"
	h.settings.forced["telegram"] = true
	h.settings.forced["claude"] = true
	main._apply_talk()
	_eq(main._phone_on(), true, "the bot polls over the house's own list")
	var open_at_start: int = b.list.status()["open"].size()

	# 08:30: the day's card, once
	var n := bot.sent.size()
	tg.t = LocalList.wall(2026, 11, 25, 8, 30)
	ph.daily()
	ph.daily()
	await s._until(
		func() -> bool: return int(ph.card.get("mid", 0)) != 0, "the morning card is sent"
	)
	await tg._settle()
	var morning: String = bot.sent.back()["params"]["text"]
	_eq(
		[bot.sent.size() - n, morning.begins_with("Today · Wed 25 Nov")],
		[1, true],
		"08:30: one card"
	)

	# a reminder, told at its time on the phone and in the chat
	var rid: int = (
		b
		. list
		. add({"kind": "reminder", "text": "check the cutover", "at": "2026-11-25T09:00"})["body"]["id"]
	)
	tg.t = LocalList.wall(2026, 11, 25, 9)
	b.list.tick()
	main._poll()
	await s._until(
		func() -> bool: return bot.sent.back()["params"]["text"] == "⏰ check the cutover",
		"the reminder is told on the phone"
	)
	_eq(
		h.chat.messages.filter(func(m): return m.get("id") == rid).size(),
		1,
		"and in the chat, once"
	)
	# done on the phone: an untouched reminder is told again later, which is its own case
	_eq(b.list.done(rid)["code"], 200, "the reminder is ticked")

	# a line from the phone becomes a to-do, then is closed by a line
	var todos := func() -> Array:
		return b.list.status()["open"].filter(func(r): return r["kind"] == "todo")
	var before: int = todos.call().size()
	bot.text(CHAT, "buy test milk")
	await s._until(func() -> bool: return todos.call().size() == before + 1, "the to-do is filed")
	await tg._settle()
	bot.text(CHAT, "done buy test milk")
	await s._until(func() -> bool: return todos.call().size() == before, "the to-do is closed")
	await tg._settle()

	# a waiting-on, nudged, closed by the reply that says it happened (#712)
	var w: int = (
		b.list.add({"kind": "waiting", "text": "the support review", "who": "Dana"})["body"]["id"]
	)
	var key := "waiting-%d" % w
	# the day's quota of nudges may be spent already over a real list: a nudge must still be shown
	b.list.moves.doc["shown"] = 0
	b.list.moves.sweep(
		[
			{
				"key": key,
				"kind": "proposal",
				"source": "list",
				"text": "Nudge Dana about the support review",
				"why": "w",
				"action": {"do": "add", "kind": "todo", "text": "Nudge Dana"},
				"date": "",
				"waiting_id": w,
				"about": "the support review"
			}
		]
	)
	var got: Array = []
	b.send(
		"/api/home",
		{"text": "the support review merged", "last": key},
		func(_r: bool, _code: int, body: Variant) -> void: got.append(body.get("reply"))
	)
	await s._until(func() -> bool: return got.size() == 1, "the reply to the nudge is answered")
	_eq(
		[got, b.list.status()["waiting"].filter(func(r): return r["id"] == w).size()],
		[["Done: the support review."], 0],
		"a reply that says it happened closes the waiting-on, no new to-do"
	)
	_eq(todos.call().size(), before, "and files nothing")

	# an edit made outside the house (a second writer on the same file) survives the house's next save
	var outside := LocalList.new("user://house_list.json", Callable(tg, "_clock"), 0.0)
	outside.load_file()
	var other: int = outside.add({"kind": "todo", "text": "made by another writer"})["body"]["id"]
	b.list.add({"kind": "todo", "text": "made in the house after"})
	var texts: Array = b.list.status()["open"].map(func(r): return r["text"])
	_eq(
		[texts.has("made by another writer"), texts.has("made in the house after")],
		[true, true],
		"the other writer's row and the house's own are both kept"
	)
	var on_disk := LocalList.new("user://house_list.json", Callable(tg, "_clock"), 0.0)
	on_disk.load_file()
	var kept: Array = on_disk.status()["open"].map(func(r): return r["text"])
	_eq(
		[kept.has("made by another writer"), kept.has("made in the house after"), other > 0],
		[true, true, true],
		"and both are in the file"
	)

	# a money question, read by the fake claude, answered from the bank
	for pair in [
		["plan.json", '{"asks": [{"ask": "summary"}]}'],
		["sentence.json", "You have $999,999.00 available."]
	]:
		var out := FileAccess.open(talk._dir.path_join(pair[0]), FileAccess.WRITE)
		out.store_string(
			JSON.stringify(
				{"type": "result", "subtype": "success", "is_error": false, "result": pair[1]}
			)
		)
		out.close()
	var ans: Array = []
	b.send(
		"/api/home",
		{"text": "how much have I spent this week?", "last": ""},
		func(_r: bool, _code: int, body: Variant) -> void: ans.append(body.get("reply"))
	)
	await s._until(func() -> bool: return ans.size() == 1, "the money question is answered", 12.0)
	var reply := str(ans[0])
	s._check(
		not reply.begins_with("Claude is off") and not reply.contains("timed out") and reply != "",
		"the money answer is an answer: %s" % reply
	)
	print("day: the money answer was: %s" % reply.left(300))
	if dir == "":
		s._check(
			reply.contains("$1,234.56") and not reply.contains("999,999"),
			"the answer is the bank's own figure: %s" % reply
		)
	else:
		s._check(
			reply.contains("$") and not reply.contains("999,999"),
			"the answer is the bank's own figures: %s" % reply
		)

	# 17:30: the evening card, once, with what was done today
	n = bot.sent.size()
	tg.t = LocalList.wall(2026, 11, 25, 17, 30)
	ph.daily()
	ph.daily()
	await s._until(func() -> bool: return bot.sent.size() > n, "the evening card is sent")
	await tg._settle()
	var evening: String = bot.sent.back()["params"]["text"]
	print(
		"day: after 17:30 the phone was sent: ",
		bot.sent.slice(n).map(func(m): return m["params"]["text"].left(60))
	)
	_eq(
		[bot.sent.size() - n, evening.begins_with("This evening")],
		[1, true],
		"17:30: one evening card"
	)
	_eq(
		b.list.status()["open"].size() >= open_at_start - 1,
		true,
		"nothing the day did not do is gone"
	)
