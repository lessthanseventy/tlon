extends RefCounted

# The soak's checks of reading with the claude program (`reader_claude.gd`) against a fake program
# in a temp dir: the readings it can give, every way it can fail, and the settings screen over it.
# The real program is never run.
const LocalList := preload("res://local_list.gd")
const Claude := preload("res://reader_claude.gd")
const BackendLocal := preload("res://backend_local.gd")
const DIR := "user://soak_talk"
const FAKE := """#!/bin/sh
d=$(dirname "$0")
printf '%s' "$2" > "$d/prompt.txt"
printf '%s|%s|%s|%s|%s|%s' "$#" "$1" "$3" "$4" "$5" "$6" > "$d/args.txt"
cat > /dev/null
if [ -f "$d/sleep" ]; then sleep "$(cat "$d/sleep")"; fi
cat "$d/out.json"
if [ -f "$d/exit" ]; then exit "$(cat "$d/exit")"; fi
"""

var s
var t := 0.0
var _dir := ""
var _runs := 0


func _init(soak) -> void:
	s = soak
	_dir = ProjectSettings.globalize_path(DIR)


func _clock() -> float:
	return t


func _eq(got: Variant, want: Variant, what: String) -> void:
	s._check(got == want, "%s: got %s, want %s" % [what, str(got), str(want)])


func _wipe() -> void:
	if DirAccess.dir_exists_absolute(_dir):
		for f in DirAccess.get_files_at(_dir):
			DirAccess.remove_absolute(_dir.path_join(f))


func run(main) -> void:
	t = LocalList.wall(2026, 11, 18, 14)
	DirAccess.make_dir_recursive_absolute(_dir)
	var fake := _dir.path_join("claude")
	var f := FileAccess.open(fake, FileAccess.WRITE)
	f.store_string(FAKE)
	f.close()
	FileAccess.set_unix_permissions(fake, 0x1ED)
	await _claude()
	await _claude_in_the_house(main)
	_wipe()
	DirAccess.remove_absolute(_dir)
	print("claude: the fake program was run %d times" % _runs)


func _envelope(result: Variant, is_error: bool = false) -> void:
	_out(
		JSON.stringify(
			{"type": "result", "subtype": "success", "is_error": is_error, "result": result}
		)
	)


func _out(text: String) -> void:
	var f := FileAccess.open(_dir.path_join("out.json"), FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _knob(name: String, value: String) -> void:
	var p := _dir.path_join(name)
	if value == "":
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
		return
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(value)
	f.close()


func _read(name: String) -> String:
	var p := _dir.path_join(name)
	return FileAccess.get_file_as_string(p) if FileAccess.file_exists(p) else ""


# a backend over a list with four things, reading through the fake program
func _backend(limit: float = 5.0) -> BackendLocal:
	var b := BackendLocal.new()
	b.setup("", Callable(self, "_clock"), 0.0, false)
	b.list.add({"kind": "todo", "text": "buy milk"})
	b.list.add({"kind": "reminder", "text": "call the plumber", "at": "2026-11-20T09:00"})
	b.list.add({"kind": "note", "text": "wifi is on the fridge"})
	var reader := Claude.new()
	reader.command = _dir.path_join("claude")
	reader.limit = limit
	b.claude = reader
	return b


# one loose line through the backend; the reply, whether the call returned before it, and the frames that ran
func _tell(b: BackendLocal, line: String) -> Dictionary:
	_runs += 1
	var got := {}
	b.send(
		"/api/home",
		{"text": line},
		func(_r: bool, code: int, body: Variant) -> void:
			got.merge({"code": code, "reply": body["reply"]})
	)
	got["early"] = got.is_empty()
	var frames := 0
	var end := Time.get_ticks_msec() + 12000
	while got.size() < 3 and Time.get_ticks_msec() < end:
		await s.process_frame
		frames += 1
	s._check(got.size() >= 3, "the call answered within 12 s: %s" % str(got))
	got["frames"] = frames
	return got


func _texts(b: BackendLocal) -> Array:
	return b.list.things().map(func(x): return x["text"])


func _added(reading: Dictionary, line: String = "buy milk") -> Dictionary:
	var b := _backend()
	_envelope(JSON.stringify(reading))
	var before: int = b.list.things().size()
	var got: Dictionary = await _tell(b, line)
	got["b"] = b
	got["new"] = b.list.things().slice(before)
	return got


func _claude() -> void:
	var good := {
		"action": "add", "kind": "todo", "text": "water the ferns", "at": null, "say": "Noted."
	}
	var r: Dictionary = await _added(good)
	_eq(
		[r["reply"], r["new"].map(func(x): return [x["kind"], x["text"]]), r["b"].claude.last],
		["Noted.", [["todo", "water the ferns"]], "ok"],
		"a good reading is applied, once"
	)
	_eq(_read("args.txt"), "6|-p|--model|haiku|--output-format|json", "the exact command line")
	var cases := [
		[
			"a reminder that repeats",
			{
				"action": "add",
				"kind": "reminder",
				"text": "bins",
				"at": "2026-11-21T09:00",
				"every": "week",
				"say": "Bins."
			},
			[["reminder", "bins"]]
		],
		[
			"a note",
			{"action": "add", "kind": "note", "text": "the code is 4411", "say": "ok"},
			[["note", "the code is 4411"]]
		],
		[
			"a waiting-on",
			{"action": "add", "kind": "waiting", "text": "the lease", "who": "Dana", "say": "ok"},
			[["waiting", "the lease"]]
		],
		[
			"a project",
			{
				"action": "add",
				"kind": "project",
				"text": "move house",
				"steps": ["book the van", "pack", "change address"],
				"say": "ok",
				"assumed": "this month"
			},
			[["project", "move house"], ["todo", "book the van"]]
		],
	]
	for c in cases:
		r = await _added(c[1])
		_eq(r["new"].map(func(x): return [x["kind"], x["text"]]), c[2], "reading applied: " + c[0])
	r = await _added(cases[0][1])
	_eq(
		[r["new"][0]["due_at"], r["new"][0]["every"]],
		["2026-11-21T09:00:00Z", "week"],
		"a reminder's time and repeat"
	)
	r = await _added(cases[3][1])
	_eq(
		[r["new"][0]["plan"], r["reply"]],
		[["pack", "change address"], "ok (assumed: this month)"],
		"a project's plan, and what was assumed is said"
	)
	r = await _added({"action": "done", "id": 1, "say": "Done."})
	_eq(
		[r["reply"], r["b"].list.status()["open"].size(), r["b"].list.status()["done"].size()],
		["Done.", 0, 1],
		"done by id"
	)
	r = await _added({"action": "delete", "id": 3, "say": "Gone."})
	_eq([r["reply"], r["b"].list.status()["note_rows"].size()], ["Gone.", 0], "delete by id")
	r = await _added({"action": "list", "say": "x"})
	_eq(
		[r["reply"].begins_with("Still open: buy milk"), r["new"].size()],
		[true, 0],
		"list says what is open, files nothing"
	)
	r = await _added({"action": "answer", "say": "The plumber is Friday."})
	_eq([r["reply"], r["new"].size()], ["The plumber is Friday.", 0], "an answer files nothing")
	_envelope("```json\n" + JSON.stringify(good) + "\n```")
	var b := _backend()
	r = await _tell(b, "x")
	_eq([r["reply"], _texts(b).back()], ["Noted.", "water the ferns"], "a fenced reply")
	_envelope("Sure, here you go:\n" + JSON.stringify(good))
	b = _backend()
	r = await _tell(b, "x")
	_eq(_texts(b).back(), "water the ferns", "a reply after a line of talk")

	# every failure reads the same line with the rules, and files it once
	var bad := [
		[
			"Claude reports an error",
			func() -> void: _envelope("{}", true),
			"Claude reported an error"
		],
		["garbage", func() -> void: _out("not json at all"), "no reply"],
		["an envelope with no result", func() -> void: _out('{"is_error": false}'), "no reply"],
		[
			"a result that is not an object",
			func() -> void: _envelope("I could not tell."),
			"reply was not JSON"
		],
		[
			"an exit of 1",
			func() -> void:
				_envelope(JSON.stringify(good))
				_knob("exit", "1"),
			"exit 1"
		],
		[
			"an unknown action",
			func() -> void: _envelope(JSON.stringify({"action": "frobnicate", "say": "x"})),
			"unknown action"
		],
		[
			"an unknown kind",
			func() -> void:
				_envelope(
					JSON.stringify({"action": "add", "kind": "event", "text": "x", "say": "x"})
				),
			"unknown kind"
		],
		[
			"no text",
			func() -> void:
				_envelope(
					JSON.stringify({"action": "add", "kind": "todo", "text": "  ", "say": "x"})
				),
			"no text"
		],
		[
			"a reminder with no time",
			func() -> void:
				_envelope(
					JSON.stringify({"action": "add", "kind": "reminder", "text": "x", "say": "x"})
				),
			"a reminder needs a time and nothing else has one"
		],
		[
			"a to-do with a time",
			func() -> void:
				_envelope(
					JSON.stringify(
						{
							"action": "add",
							"kind": "todo",
							"text": "x",
							"at": "2026-11-21T09:00",
							"say": "x"
						}
					)
				),
			"a reminder needs a time and nothing else has one"
		],
		[
			"a time that is not a time",
			func() -> void:
				_envelope(
					JSON.stringify(
						{
							"action": "add",
							"kind": "reminder",
							"text": "x",
							"at": "tomorrow",
							"say": "x"
						}
					)
				),
			"the time is not usable"
		],
		[
			"a time out of bounds",
			func() -> void:
				_envelope(
					JSON.stringify(
						{
							"action": "add",
							"kind": "reminder",
							"text": "x",
							"at": "2090-01-01T09:00",
							"say": "x"
						}
					)
				),
			"the time is not usable"
		],
		[
			"a repeat that is not one",
			func() -> void:
				_envelope(
					JSON.stringify(
						{
							"action": "add",
							"kind": "reminder",
							"text": "x",
							"at": "2026-11-21T09:00",
							"every": "sometimes",
							"say": "x"
						}
					)
				),
			"the repeat is not usable"
		],
		[
			"a waiting-on with no one",
			func() -> void:
				_envelope(
					JSON.stringify({"action": "add", "kind": "waiting", "text": "x", "say": "x"})
				),
			"no one waited on"
		],
		[
			"a project with no steps",
			func() -> void:
				_envelope(
					JSON.stringify(
						{"action": "add", "kind": "project", "text": "x", "steps": [], "say": "x"}
					)
				),
			"no steps"
		],
		[
			"an id that is not live",
			func() -> void: _envelope(JSON.stringify({"action": "done", "id": 999, "say": "x"})),
			"not an open thing"
		],
		[
			"an id that is not a number",
			func() -> void: _envelope(JSON.stringify({"action": "delete", "id": "1", "say": "x"})),
			"not an open thing"
		],
		[
			"an answer with nothing said",
			func() -> void: _envelope(JSON.stringify({"action": "answer"})),
			"no answer"
		],
	]
	for c in bad:
		_knob("exit", "")
		c[1].call()
		b = _backend()
		var before: int = b.list.things().size()
		r = await _tell(b, "buy milk")
		var made: Array = b.list.things().slice(before)
		_eq(
			[r["reply"], made.map(func(x): return x["text"]), b.claude.last],
			["To do: buy milk.", ["buy milk"], "failed (%s), used the simple reader" % c[2]],
			"falls back to the rules, once: " + c[0]
		)
	_knob("exit", "")

	# too slow: killed at the limit, the line read by the rules
	_envelope(JSON.stringify(good))
	_knob("sleep", "5")
	b = _backend(0.4)
	var before: int = b.list.things().size()
	r = await _tell(b, "buy milk")
	_eq(
		[r["reply"], b.list.things().size() - before, b.claude.last],
		["To do: buy milk.", 1, "failed (timed out), used the simple reader"],
		"a program past the limit is stopped and the rules read the line"
	)
	# slow but in time: the frames keep running and the call itself returns at once
	_knob("sleep", "1")
	b = _backend()
	r = await _tell(b, "x")
	_eq(
		[r["reply"], r["early"], r["frames"] > 10],
		["Noted.", true, true],
		"a slow read blocks no frame (returned before the reply: %s, %d frames)" % [r["early"], r["frames"]]
	)
	_knob("sleep", "")
	# the program is not there
	b = _backend()
	b.claude.command = "/nonexistent/claude-x"
	before = b.list.things().size()
	r = await _tell(b, "buy milk")
	_eq(
		[r["reply"], b.list.things().size() - before, b.claude.last],
		["To do: buy milk.", 1, "failed (command not found), used the simple reader"],
		"a missing program falls back"
	)

	# a message cannot become a command: it is one argument, as typed
	var evil := (
		"x \"q\" 'q'; $(touch %s/PWNED1) `touch %s/PWNED2` && touch %s/PWNED3\nline two \\ %%PATH%% | > out"
		% [_dir, _dir, _dir]
	)
	_envelope(JSON.stringify(good))
	b = _backend()
	var expected: String = b.claude.prompt(evil, b._context())
	r = await _tell(b, evil)
	_eq(
		[_read("prompt.txt") == expected, _read("args.txt").begins_with("6|")],
		[true, true],
		"an injection attempt reaches the program as one argument, unchanged"
	)
	_eq(
		[
			FileAccess.file_exists(_dir.path_join("PWNED1")),
			FileAccess.file_exists(_dir.path_join("PWNED2")),
			FileAccess.file_exists(_dir.path_join("PWNED3"))
		],
		[false, false, false],
		"and nothing in it was run"
	)
	_eq(
		expected.contains("buy milk") and expected.contains("1: buy milk"),
		true,
		"the prompt lists the open things as id: text"
	)
	_eq(
		[
			expected.contains("Wednesday 2026-11-18 14:00"),
			expected.contains('"action": "add"|"done"')
		],
		[true, true],
		"and the date, the weekday and the shape asked for"
	)
	for i in 50:
		b.list.add({"kind": "todo", "text": "thing %d" % i})
	_eq(
		(
			b.claude.prompt("x", b._context()).count("\n") < 80
			and not b.claude.prompt("x", b._context()).contains("thing 49")
		),
		true,
		"no more than 40 open things are sent"
	)
	_eq(
		(
			Claude._batch_safe('a"b%c^d&e|f<g>h!i\nj').count('"')
			+ Claude._batch_safe('a"b%c^d&e|f<g>h!i\nj').count("%")
			+ Claude._batch_safe("a&b|c\nd").count("&")
		),
		0,
		"a .cmd file gets a prompt with nothing cmd.exe reads"
	)

	# the program's name is looked for on PATH; the test button runs one tiny reading
	var path_was := OS.get_environment("PATH")
	OS.set_environment("PATH", _dir + ":" + path_was)
	_eq(
		[Claude.which("claude"), Claude.which("claude-nowhere-x"), Claude.which("")],
		[_dir.path_join("claude"), "", ""],
		"which finds the program on PATH"
	)
	OS.set_environment("PATH", path_was)
	_eq(Claude.which(_dir.path_join("claude")), _dir.path_join("claude"), "or by a path")
	var line := []
	var reader := Claude.new()
	reader.command = _dir.path_join("claude")
	_envelope(JSON.stringify({"action": "answer", "say": "ok"}))
	reader.test({"now": t, "bias": 0.0, "status": {}}, func(l: String) -> void: line.append(l))
	await s._until(func() -> bool: return line.size() == 1)
	_eq(line, ["works"], "the test says works")
	_out("nope")
	reader.test({"now": t, "bias": 0.0, "status": {}}, func(l: String) -> void: line.append(l))
	await s._until(func() -> bool: return line.size() == 2)
	_eq(line[1], "no reply", "and the reason when it does not")


# the settings and the notepad over the house's own list, Claude switched on
func _claude_in_the_house(main) -> void:
	var h = main._room.home
	var settings = h.settings
	main.talk_live = true
	var b := _backend()
	b.claude = null
	main._install(b)
	var v = main._sidebar.settings_view
	settings.forced["where"] = "local"
	settings.forced["claude"] = false
	_eq(b.claude, null, "Claude is off until it is switched on")
	settings.forced["claude"] = true
	settings.forced["claude_command"] = _dir.path_join("claude")
	main._apply_talk()
	_eq(b.claude == main._claude, true, "switched on, the loose lines go to it")
	_envelope(
		JSON.stringify(
			{
				"action": "add",
				"kind": "reminder",
				"text": "stretch",
				"at": "2026-11-18T15:00",
				"say": "Stretch at three."
			}
		)
	)
	main._open_add()
	main._send_jot("stretch later")
	await s._until(func() -> bool: return main._sidebar.jot._kept.visible)
	_eq([main._sidebar.jot._summary.text.begins_with("Reminder"), main._sidebar.jot._said.text, h.chat.messages.back()["text"]], [true, "stretch", "Stretch at three."], "the pad reads back the thing; the reading's own line is in the chat")
	_eq(
		h.chat.messages.slice(-2).map(func(m): return m["who"]),
		["me", "home"],
		"and the chat keeps both"
	)
	main._sidebar.chat_view.sent.emit("again")
	await s._until(
		func() -> bool:
			return (
				h.chat.messages.back()["who"] == "home" and h.chat.messages[-2]["text"] == "again"
			)
	)
	_eq(
		h.chat.messages.back()["text"], "Stretch at three.", "the chat's own line goes the same way"
	)
	main._sidebar.chat_view.finish(true, "again")
	v.open()
	_eq(
		[v._talk_box.visible, v._claude_on.button_pressed, v._claude_box.visible],
		[true, true, true],
		"the settings offer it over the house's own list"
	)
	_eq(v._claude_found.text, "found: " + _dir.path_join("claude"), "and say the program was found")
	_eq(v._claude_last.text, "last Claude reading: ok", "and how the last reading went")
	_out("junk")
	v._claude_test()
	await s._until(func() -> bool: return v._claude_say.text != "testing...")
	_eq(v._claude_say.text, "no reply", "the test button says why when it fails")
	_envelope(JSON.stringify({"action": "answer", "say": "ok"}))
	v._claude_test()
	await s._until(
		func() -> bool:
			return v._claude_say.text != "testing..." and v._claude_say.text != "no reply"
	)
	_eq(v._claude_say.text, "works", "and works when it does")
	settings.forced["claude_command"] = "claude-nowhere-x"
	v._cmd_seen = "\n"
	v._refresh()
	_eq(v._claude_found.text, "not found on PATH", "a program that is not there is said so")
	settings.forced["claude_command"] = _dir.path_join("claude")
	main._apply_talk()
	v.close()
	# the server's house is not offered it, and does not use it
	settings.forced["where"] = "server"
	main._make_backend()
	v.open()
	_eq(
		[v._talk_box.visible, main._backend.local],
		[false, false],
		"in server mode neither helper is offered"
	)
	v.close()
	settings.forced.erase("where")
	settings.forced.erase("claude")
	settings.forced.erase("claude_command")
	main.talk_live = false
	main._make_backend()
