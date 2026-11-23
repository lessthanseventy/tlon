extends RefCounted

# The soak's check of the headless loop: with the room and sidebar hidden and stopped, a due
# reminder is told to the paired chat by the backend's own timer (the test only moves the fake
# clock) and a line from it is answered, against the Telegram stub.
const LocalList := preload("res://local_list.gd")
const BackendLocal := preload("res://backend_local.gd")
const TelegramSoak := preload("res://soak_telegram.gd")

var s
var t := 0.0


func _init(soak) -> void:
	s = soak


func _clock() -> float:
	return t


func _eq(got: Variant, want: Variant, what: String) -> void:
	s._check(got == want, "%s: got %s, want %s" % [what, str(got), str(want)])


func run(main) -> void:
	t = LocalList.wall(2026, 11, 18, 14)
	var settings = main._room.home.settings
	var bot := TelegramSoak.Bot.new()
	bot.token = TelegramSoak.TOKEN
	s.bot = Callable(bot, "handle")
	var ph = main._phone
	ph.base = "http://127.0.0.1:%d" % s._srv.get_local_port()
	ph.poll_gap = 0.03
	ph.token = TelegramSoak.TOKEN
	ph.chat = 777
	ph.me = "@house_stub_bot"
	main.talk_live = true
	var b := BackendLocal.new()
	b.setup("", Callable(self, "_clock"), 0.0, false)
	main._install(b)
	settings.forced["where"] = "local"
	settings.forced["telegram"] = true
	main._apply_talk()

	main.go_headless()
	_eq(
		[main.headless, main._room.visible, main._sidebar.visible],
		[true, false, false],
		"headless hides the room and the sidebar"
	)
	_eq(
		[main._room.process_mode, main._sidebar.process_mode],
		[Node.PROCESS_MODE_DISABLED, Node.PROCESS_MODE_DISABLED],
		"and stops them"
	)

	var tea: int = (
		b.list.add({"kind": "reminder", "text": "tea", "at": "2026-11-18T15:00"})["body"]["id"]
	)
	t = LocalList.wall(2026, 11, 18, 15)
	await s._until(
		func() -> bool: return bot.to(777).any(func(m): return m["params"]["text"] == "⏰ tea"),
		"the backend's own timer told the due reminder to the chat with the window shut"
	)
	bot.text(777, "buy cake")
	await s._until(
		func() -> bool: return b.list.things().any(func(x): return x["text"] == "buy cake"),
		"a line from the chat filed with the window shut"
	)
	await s._until(func() -> bool: return bot.to(777).size() == 2, "and answered")
	_eq(b.list.things().any(func(x): return x["id"] == tea), true, "the reminder is still kept")

	ph.stop()
	settings.forced.erase("where")
	settings.forced.erase("telegram")
	main.talk_live = false
	s.bot = Callable()
