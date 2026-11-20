extends RefCounted

# The soak's checks of the settings and the phone's chat: the file, the names on display, the two
# second clicks, the address check, and the conversation against the soak's local stub. Nothing
# here reaches a real server, and the files are the soak's own.
const Settings := preload("res://settings.gd")
const Chat := preload("res://chat.gd")
const SettingsView := preload("res://settings_view.gd")
const USER_FILES := [
	"house_settings.json", "house_chat.json", "house_person.json", "house_rhythm.json",
	"house_layout.json", "house_found.json", "house_sound.json", "house_widget.json",
]
const TMP := "user://soak_settings2.json"
const TMP_CHAT := "user://soak_chat.json"

var s
var main
var h
var _before := {}


func _init(soak, the_main) -> void:
	s = soak
	main = the_main
	h = main._room.home


func _stamp() -> Dictionary:
	var out := {}
	for f in USER_FILES:
		var p: String = "user://" + f
		out[f] = (
			[FileAccess.get_modified_time(p), FileAccess.get_file_as_string(p).length()]
			if FileAccess.file_exists(p)
			else null
		)
	return out


# a moment, then until no request is in flight (bounded): a slow machine is slower, not wrong
func _wait(_secs: float = 0.0) -> void:
	await s.create_timer(0.15).timeout
	var quiet := 0
	var end := Time.get_ticks_msec() + 8000
	while quiet < 3 and Time.get_ticks_msec() < end:
		quiet = quiet + 1 if main._backend.get_child_count() == 0 else 0
		await s.process_frame


# until `done` holds, at most `secs`; a failure to hold is the caller's check
func _until(done: Callable, secs: float = 8.0) -> void:
	var end := Time.get_ticks_msec() + int(secs * 1000.0)
	while not done.call() and Time.get_ticks_msec() < end:
		await s.create_timer(0.02).timeout


func _key(code: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	return e


func _read(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func run() -> void:
	_before = _stamp()
	_settings_file()
	_names()
	_chat_file()
	await _settings_view()
	if s.served:
		await _address()
	await _conversation()
	await _blockers()
	s._check(_stamp() == _before, "the user's own files were not touched")
	for p in [TMP, TMP_CHAT]:
		DirAccess.remove_absolute(p)
	Settings.new().setup(false)


func _settings_file() -> void:
	DirAccess.remove_absolute(TMP)
	var a := Settings.new()
	a.store = TMP
	a.setup(true)
	s._check(a.value("cat") == "Nina" and a.value("dog") == "Argos", "the pets' default names")
	s._check(a.value("name") == "" and a.value("widget") == false, "no name, the full window")
	s._check(not FileAccess.file_exists(TMP), "nothing is written until something changes")
	a.put("cat", "Nina")
	s._check(not FileAccess.file_exists(TMP), "a value equal to its default is no change")
	var want := {
		"name": "Sam", "birthday": "03-15", "cat": "Mimi", "dog": "Rex", "widget": true,
		"on_top": false, "url": "http://127.0.0.1:4999",
	}
	for k in want:
		a.put(k, want[k])
	var b := Settings.new()
	b.store = TMP
	b.setup(true)
	for k in want:
		s._check(b.value(k) == want[k], "%s is kept and read back: %s" % [k, str(b.value(k))])
	s._check(Settings.cat == "Mimi" and Settings.dog == "Rex" and Settings.person == "Sam", "the names apply at once")
	s._check(b.server_url() == "http://127.0.0.1:4999", "the address in the file is the server's")
	var f := FileAccess.open(TMP, FileAccess.WRITE)
	f.store_string('{"birthday":"06-08","muted_for":{"a":[1,2]},"widget":true}')
	f.close()
	var c := Settings.new()
	c.store = TMP
	c.setup(true)
	s._check(c.value("birthday") == "06-08", "the old file's birthday is read")
	c.put("name", "Pat")
	var disk := _read(TMP)
	s._check(
		disk.get("birthday") == "06-08" and disk.get("name") == "Pat" and str(disk.get("muted_for")) == str({"a": [1.0, 2.0]}),
		"a key this build does not know is kept: %s" % str(disk)
	)
	c.forced["widget"] = false
	s._check(c.value("widget") == false, "an arg beats the file")
	c.forced = {}
	s._check(c.value("widget") == true, "the file beats the default")
	c.data = {}
	s._check(c.value("widget") == false and c.server_url() == Settings.default_url(), "and the default last")
	var quiet := Settings.new()
	quiet.store = TMP
	DirAccess.remove_absolute(TMP)
	quiet.setup(false)
	quiet.put("name", "Nobody")
	s._check(not FileAccess.file_exists(TMP), "a scripted or staged run writes nothing")
	s._check(not h.settings.persist and not h.chat.persist, "the soak's home keeps nothing in user://")
	Settings.new().setup(false)


func _names() -> void:
	var a := Settings.new()
	a.setup(false)
	a.put("cat", "Mimi")
	a.put("dog", "Rex")
	s._check(Settings.pets("Nina: hi. Argos and Nina's toy, Ninas") == "Mimi: hi. Rex and Mimi's toy, Ninas", "names are whole words")
	a.put("cat", "Argos")
	a.put("dog", "Nina")
	s._check(Settings.pets("Nina and Argos") == "Argos and Nina", "a swap is not undone by a second pass")
	a.put("cat", "Mimi")
	a.put("dog", "Rex")
	h.pets.set_voices({"Nina": {"pet": ["Nina is best, says Argos."]}, "duo": [["Nina: ask Argos", "Argos: Nina!"]]})
	var nina = h.pets.critter("nina")
	nina.say_left = 0.0
	h.pets.speak(nina, "pet")
	s._check(nina.say_text == "Mimi is best, says Rex.", "a server line shows the names he gave: %s" % nina.say_text)
	h.pets.play_duo(h.pets.voices.duo())
	s._check(nina.say_text == "ask Rex", "a duo turn too: %s" % nina.say_text)
	h.finds.book = {"title": "T", "about": "a", "who": "Argos", "blurb": "Nina approves"}
	var block: String = h.finds.remark()
	s._check(block == "Rex: Mimi approves", "the book card: %s" % block)
	var texts: Array = h.finds.found_blocks().map(func(b): return str(b.get("text", "")))
	s._check(not "\n".join(texts).contains("Nina"), "the found card uses the names")
	h.settings.put("name", "Sam")
	h.pets.set_voices({"Nina": {"muse": ["Hello {name}", "plain"]}})
	var seen := {}
	for i in 12:
		seen[h.pets.line("Nina", "muse")] = true
	s._check(seen.has("Hello Sam") and seen.has("plain"), "{name} is filled in: %s" % str(seen.keys()))
	h.settings.put("name", "")
	seen = {}
	for i in 12:
		seen[h.pets.line("Nina", "muse")] = true
	s._check(seen.keys() == ["plain"], "{name} with no name is skipped")
	h.settings.put("birthday", "03-15")
	h.fake_day = "03-15"
	s._check(h.finds.is_birthday() and not h.finds.table().is_empty(), "the birthday in settings puts the cake out")
	h.fake_day = "03-16"
	s._check(not h.finds.is_birthday(), "and only on its day")
	h.settings.put("birthday", "")
	h.settings.put("cat", "Nina")
	h.settings.put("dog", "Argos")
	h.fake_day = ""
	h.pets.set_voices({})


func _chat_file() -> void:
	DirAccess.remove_absolute(TMP_CHAT)
	var c := Chat.new()
	c.store = TMP_CHAT
	c.setup(true)
	for i in 305:
		c.add("me" if i % 2 == 0 else "home", "m%d" % i)
	s._check(c.messages.size() == 300 and c.messages[0]["text"] == "m5", "the last 300 are kept")
	var back := Chat.new()
	back.store = TMP_CHAT
	back.setup(true)
	s._check(back.messages.size() == c.messages.size() and back.messages[-1]["text"] == "m304" and back.messages[0]["t"] == c.messages[0]["t"], "history round-trips")
	var f := FileAccess.open(TMP_CHAT, FileAccess.WRITE)
	f.store_string('{"messages":[{"t":1,"who":"me","text":"a"},{"nope":1},"x",{"t":2,"who":"home","text":"b"}]}')
	f.close()
	back.setup(true)
	s._check(back.messages.size() == 2, "a malformed message is skipped on load")
	c.clear()
	s._check(c.messages.is_empty() and Chat.new().messages.is_empty(), "clear empties it")
	c.open = false
	c.add("me", "mine")
	s._check(not c.unread, "his own line is not unread")
	c.add("home", "x")
	s._check(c.unread, "a message while closed is unread")
	c.told(5, "t1", "stretch")
	c.told(5, "t1", "stretch")
	s._check(c.messages.filter(func(m): return m.get("id") == 5).size() == 1, "a reminder is told once")
	c.told(5, "t2", "stretch")
	s._check(c.messages.filter(func(m): return m.get("id") == 5).size() == 2, "a new nudge is a new message")
	c.resolve(5, "done")
	s._check(c.messages[-1]["done"] == "done" and c.messages[-2]["done"] == "done", "resolving replaces the buttons")
	c.told(6, "t1", "water")
	c.sync([])
	s._check(c.messages[-1]["done"] == "gone", "one no longer ringing was dealt with elsewhere")
	c.pet_said("cat", "first", 1000.0)
	c.pet_said("dog", "soon after", 1100.0)
	c.pet_said("dog", "later", 1700.0)
	var pets: Array = c.messages.filter(func(m): return m["who"] in ["cat", "dog"])
	s._check(pets.size() == 2 and pets[1]["text"] == "later", "a pet speaks in the chat now and then")
	s._check(c.last_mine() == "mine", "the last line of his")
	var n := c.messages.size()
	c.add("me", "oops")
	c.retract("oops")
	s._check(c.messages.size() == n, "a line that was not sent is taken back")


func _settings_view() -> void:
	var room: Control = s._room(31)
	var home = room.home
	home.settings.store = TMP
	home.settings.persist = false
	home.chat.persist = false
	var v = SettingsView.new()
	v.setup(home.settings, home)
	s.root.add_child(v)
	await s.process_frame
	v.open()
	s._check(v.visible, "the settings open")
	v._name.text = "Sam"
	v._name.text_submitted.emit("Sam")
	var typed := func(text: String) -> void:
		v._birth.text = text
		v._birth.text_submitted.emit(text)
	typed.call("15 March")
	s._check(home.settings.value("birthday") == "03-15" and Settings.person == "Sam", "name and birthday apply at once")
	s._check(v._birth.text == "15 March" and v._birth_say.text == "Kept as 15 March.", "the field says what was understood: %s" % v._birth_say.text)
	for pair in [["June 8", "06-08"], ["8 jun", "06-08"], ["06-08", "06-08"], ["12/25", "12-25"], ["29 February", "02-29"]]:
		typed.call(pair[0])
		s._check(home.settings.value("birthday") == pair[1], "'%s' is read as %s" % [pair[0], pair[1]])
	typed.call("31 February")
	s._check(home.settings.value("birthday") == "02-29" and "not a day" in v._birth_say.text, "a day the month lacks is refused and the kept one stays")
	typed.call("soon")
	s._check(home.settings.value("birthday") == "02-29", "words that are no date change nothing")
	typed.call("none")
	s._check(home.settings.value("birthday") == "" and v._birth_say.text == "No birthday set.", "none clears the birthday and says so")
	typed.call("")
	s._check(home.settings.value("birthday") == "", "an empty field is none")
	v.open()
	s._check(v._birth.text == "", "no birthday: an empty field")
	typed.call("8 June")
	v.open()
	s._check(v._birth.text == "8 June", "a kept birthday shows as written out")
	v._tab_chips["pets"].pressed.emit()
	s._check(v.page == "pets" and v._pages["pets"].visible and not v._pages["you"].visible, "a chip opens its group alone")
	for p in v.PAGES:
		v.show_page(p)
		var open: Array = v._pages.keys().filter(func(k: String) -> bool: return v._pages[k].visible)
		s._check(open == [p], "only %s is open" % p)
	v._menus["degrees"][0].item_selected.emit(1)
	s._check(home.settings.value("degrees") == "c", "You: the temperature unit saves")
	v._menus["pet1_personality"][0].item_selected.emit(2)
	s._check(home.settings.value("pet1_personality") == "lazy", "Pets: a personality saves")
	v._looks["glow"].set_pressed_no_signal(false)
	v._looks["glow"].pressed.emit()
	s._check(home.settings.value("glow") == false, "Look: a switch saves")
	v._town.text = "Oslo"
	v._town.text_submitted.emit("Oslo")
	s._check(home.settings.value("weather_town") == "Oslo", "Connections: the weather town saves")
	v._menus["degrees"][0].item_selected.emit(0)
	v._looks["glow"].set_pressed_no_signal(true)
	v._looks["glow"].pressed.emit()
	v.show_page("you")
	v._cat.text = "Mimi"
	v._cat.text_submitted.emit("Mimi")
	v._dog.text = "Rex"
	v._dog.focus_exited.emit()
	s._check(Settings.cat == "Mimi" and Settings.dog == "Rex", "the pets' names apply at once")
	var was: bool = home.sound.muted
	v._sound.set_pressed_no_signal(was)
	v._sound.pressed.emit()
	s._check(home.sound.muted != was, "the sound switch drives sound.gd")
	v._widget.set_pressed_no_signal(true)
	v._widget.pressed.emit()
	s._check(home.settings.value("widget") == true, "the widget default is set")
	s._check((v._volume != null) == ("volume" in home.sound), "the volume slider shows only if sound has a volume")
	home.eggs.found = {"book": true}
	home.eggs.persist = false
	v.open()
	s._check(v._found.text == "1 of %d found" % home.eggs.CATALOGUE.size(), "N of M found: %s" % v._found.text)
	v._forget.pressed.emit()
	s._check(home.eggs.found.size() == 1, "forgetting needs a second click")
	v._forget.pressed.emit()
	s._check(home.eggs.found.is_empty(), "the second click forgets them")
	home.layout.pieces.append({"p": "crate", "f": "", "c": 6, "r": 4})
	var n: int = home.layout.pieces.size()
	v._reset.pressed.emit()
	s._check(home.layout.pieces.size() == n, "resetting the room needs a second click")
	v.sure.tick(5.0)
	v._reset.pressed.emit()
	s._check(home.layout.pieces.size() == n, "and the first click lapses after a few seconds")
	v._reset.pressed.emit()
	s._check(home.layout.pieces.size() != n or not home.layout.art, "the second click resets the room")
	home.chat.add("me", "x")
	v._clear.pressed.emit()
	s._check(not home.chat.messages.is_empty(), "clearing the chat needs a second click")
	v._clear.pressed.emit()
	s._check(home.chat.messages.is_empty(), "the second click clears it")
	home.knobs = {"home_list_at": "17:30"}
	v.open()
	s._check(v._plan.get_child_count() == 1, "only the server's times it already tells are shown")
	v.close()
	s._check(not v.visible, "Esc closes")
	v.queue_free()
	room.queue_free()
	Settings.new().setup(false)


func _address() -> void:
	var v = main._sidebar.settings_view
	v.open()
	main._check_server("http://127.0.0.1:%d" % s._srv.get_local_port())
	await _until(func() -> bool: return v._url_say.text == "reachable")
	s._check(v._url_say.text == "reachable", "the check says reachable against the stub: %s" % v._url_say.text)
	main._check_server("http://127.0.0.1:1")
	await _until(func() -> bool: return v._url_say.text == "not reachable")
	s._check(v._url_say.text == "not reachable", "and not reachable on a dead port: %s" % v._url_say.text)
	v._url.text = "ftp://x"
	v._check()
	s._check("http" in v._url_say.text, "an address must start with http")
	v._url.text = "http://127.0.0.1:4998/"
	v._check()
	s._check(main._backend.base == "http://127.0.0.1:4998", "the address applies at once: %s" % main._backend.base)
	await _wait()
	v._url.text = ""
	v._check()
	s._check(main._backend.base == Settings.default_url(), "empty is the default again: %s" % main._backend.base)
	await _wait()
	v.close()


func _conversation() -> void:
	var chat = h.chat
	chat.messages = []
	s._fail_jot = false
	main._sidebar.jot.finish()
	s._check(main._open_chat(), "the chat opens")
	var v = main._sidebar.chat_view
	var before: int = s._count("/api/home")
	v._submit("hello house")
	s._check(v.reading and chat.messages[-1]["who"] == "me", "sending shows his line and a reading state")
	await _wait(1.0)
	s._check(not v.reading and chat.messages[-1]["text"] == s.reply_for("hello house") and chat.messages[-1]["who"] == "home", "the reply replaces reading")
	s._check(s._seen("POST", "/api/home", "hello house"), "the line is posted to /api/home")
	s._check(s._count("/api/home") > before, "the status is read again at once")
	s._fail_jot = true
	var n: int = chat.messages.size()
	v._submit("keep me")
	await _wait(1.0)
	s._check(chat.messages.size() == n and v._edit.text == "keep me" and "not sent" in v._note.text, "a failure takes the line back and keeps the text")
	s._fail_jot = false
	v._edit.text = ""
	s._check(v._edit.text == "", "ready again")
	chat.add("me", "older")
	v._edit_key(_key(KEY_UP))
	s._check(v._edit.text == "older", "Up recalls his last message")
	v._edit.text = ""
	main._open_add()
	main._sidebar.jot.open("from the pad")
	main._send_jot("from the pad")
	await _wait(1.0)
	var texts: Array = chat.messages.map(func(m): return m["text"])
	s._check(texts.has("from the pad") and texts.has(s.reply_for("from the pad")), "a notepad line and its reply are in the history")
	var pad = main._sidebar.jot
	s._check(pad._kept.visible and not pad._ask.visible, "the pad shows what the house made of the line")
	s._check(
		pad._change.visible == (not s.served) and pad._said.text == ("from the pad" if not s.served else s.reply_for("from the pad")),
		"over the local list it hands the row back, from a server it is the reply alone: %s" % pad._said.text
	)
	main._sidebar.jot.finish()
	for row in [
		{"id": 7, "kind": "reminder", "text": "stretch", "due_at": null, "every": null, "told_at": "2026-11-18T10:00:00Z"},
		{"id": 8, "kind": "reminder", "text": "water", "due_at": null, "every": null, "told_at": "2026-11-18T10:00:00Z"},
		{"id": 9, "kind": "reminder", "text": "mail", "due_at": null, "every": null, "told_at": "2026-11-18T10:00:00Z"},
		{"id": 10, "kind": "reminder", "text": "bins", "due_at": null, "every": "week", "told_at": "2026-11-18T10:00:00Z"},
	]:
		s.add_open(row)
	main._sidebar.chat_mode = "line"
	main._sidebar._apply()
	await s.process_frame
	await s.process_frame
	chat.unread = false
	main._poll()
	await _wait()
	var told: Array = chat.messages.filter(func(m): return m.has("id"))
	s._check(told.size() == 4 and told[0]["text"] == chat.BELL + "stretch", "each told reminder appears once: %d" % told.size())
	s._check(chat.unread, "a message while the chat is closed sets the unread mark")
	main._poll()
	await _wait()
	s._check(chat.messages.filter(func(m): return m.has("id")).size() == 4, "a second read tells nothing again")
	main._open_chat()
	await s.process_frame
	await s.process_frame
	s._check(not chat.unread, "opening clears the unread mark")
	await s.process_frame
	await s.process_frame
	s._check(v._hits.size() >= 4 and v._hits.size() % 4 == 0, "four buttons under each shown: %d" % v._hits.size())
	v.press(7, "done")
	await _wait()
	s._check(s._seen("POST", "/api/home/7/done"), "Done calls the done route")
	v.press(8, "hour")
	await _wait()
	s._check(s._seen("POST", "/api/home/8/later", "hour"), "In an hour calls later with hour")
	v.press(9, "tomorrow")
	await _wait()
	s._check(s._seen("POST", "/api/home/9/later", "tomorrow"), "Tomorrow calls later with tomorrow")
	var by := {}
	for m in chat.messages:
		if m.has("id"):
			by[int(m["id"])] = m.get("done", "")
	s._check(by[7] == "done" and by[8] == "hour" and by[9] == "tomorrow", "acted on, the buttons are replaced: %s" % str(by))
	var posts: int = s._log.filter(func(l): return l[1] == "/api/home/10/drop").size()
	v.press(10, "delete")
	await _wait()
	s._check(s._log.filter(func(l): return l[1] == "/api/home/10/drop").size() == posts, "deleting a repeating one asks twice")
	v.press(10, "delete")
	await _wait()
	s._check(s._seen("POST", "/api/home/10/drop"), "the second click deletes")
	await s.process_frame
	s._check(v._hits.is_empty() and v.acting == -1, "nothing is left to press")
	h._show_slip("home")
	s._check(str(chat.messages[-1]["text"]).begins_with("Still open"), "a slip is a message: %s" % chat.messages[-1]["text"])
	var nina = h.pets.critter("nina")
	chat.messages = chat.messages.filter(func(m): return not m["who"] in ["cat", "dog"])
	var pet_n: int = chat.messages.filter(func(m): return m["who"] == "cat").size()
	h.pets.say(nina, "Nina: not now")
	s._check(chat.messages.filter(func(m): return m["who"] == "cat").size() == pet_n + 1, "a pet's bubble is a message")
	h.settings.put("cat", "Mimi")
	s._check(v._text_of(chat.messages[-1]).begins_with("Mimi:"), "and shows the name he gave her")
	h.settings.put("cat", "Nina")
	v.set_mode("line")
	s._check(not chat.open, "closing marks the chat closed")


func _blockers() -> void:
	var sb = main._sidebar
	main._open_add()
	await s.process_frame
	s._check(sb.view == "add" and sb.takes_text(), "the add view takes text")
	main._input(_key(KEY_K))
	main._input(_key(KEY_D))
	main._input(_key(KEY_C))
	main._input(_key(KEY_COMMA))
	s._check(
		sb.view == "add" and not main._decorate.active and not sb.chat_popped,
		"letter hotkeys do not fire while a field has focus"
	)
	main._input(_key(KEY_ESCAPE))
	s._check(sb.view == "home", "Esc goes back to the home view")
	s._check(main._open_settings() and sb.view == "settings", "the settings open as a view")
	h.rhythm.show_slip("home", "Still open", [])
	await s.process_frame
	await s.process_frame
	s._check(sb.view == "settings", "a slip arriving does not close the view")
	h.rhythm.dismiss()
	main._input(_key(KEY_ESCAPE))
	s._check(sb.view == "home", "Esc leaves the settings")
	get_viewport_release()
	main._input(_key(KEY_K))
	s._check(sb._effective() in ["dock", "full"], "K brings the chat up")
	main._input(_key(KEY_ESCAPE))
	main._open_closet()
	s._check(sb.view == "closet", "the closet is a view")
	main._input(_key(KEY_ESCAPE))
	s._check(sb.view == "home", "Esc leaves the closet")
	main._open_chat()
	s._check(sb._effective() in ["dock", "full"], "the chat is up at home")
	h.acted.emit(0, "chat")
	s._check(sb._effective() in ["dock", "full"], "a click on the phone brings up the chat")
	main._sidebar.chat_view.set_mode("line")
	s._check(not h.chat.open, "the collapsed chat is marked closed")


func get_viewport_release() -> void:
	var f = main.get_viewport().gui_get_focus_owner()
	if f != null:
		f.release_focus()
