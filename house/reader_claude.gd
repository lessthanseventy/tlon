extends RefCounted

# Reads a loose line with the `claude` command-line program, in front of the rule reader. A run is
# `<command> -p <prompt> --model haiku --output-format json`: a process of its own, the prompt one
# argument, stdin closed, `limit` seconds. The answer is checked strictly and made into the rules'
# reading shape (`reader_rules.gd`); anything else answers {} and the caller reads the line with
# the rules, so a line is never lost.
const LocalList := preload("res://local_list.gd")
const Rules := preload("res://reader_rules.gd")
const ACTIONS := ["add", "done", "delete", "list", "answer"]
const MAX_OPEN := 40
const MAX_STEPS := 10
const SCHEMA := (
	'{"action": "add"|"done"|"delete"|"list"|"answer", '
	+ '"kind": "todo"|"reminder"|"note"|"waiting"|"project", "text": text, '
	+ '"at": "YYYY-MM-DDTHH:MM" or null, "every": "day"|"week"|"month"|"N unit" or null, '
	+ '"who": text or null, "steps": [text] or null, "id": number or null, '
	+ '"say": "one short line saying back what was understood", "assumed": text or null}'
)
const RULES := (
	"add makes a new thing: a reminder has at (local time) and may repeat with every, a to-do has "
	+ "no time, waiting has who, a project has steps. A vague thing with several steps is a project "
	+ "with 2 to 5 concrete steps. done and delete name one open thing above by its id. A line that "
	+ "only refers to an open thing (a question, a comment) is answer, never a new thing. list says "
	+ "what is open. Say in assumed what you had to guess."
)

var command := "claude"
var limit := 45.0
# "" before the first line; else the settings screen's line about the latest one
var last := ""

var _rules := Rules.new()


# the file `cmd` names, searching PATH (and the extensions Windows tries); "" when there is none
static func which(cmd: String) -> String:
	cmd = cmd.strip_edges()
	if cmd == "":
		return ""
	var windows := OS.get_name() == "Windows"
	var exts: Array = [""]
	if windows:
		for e in OS.get_environment("PATHEXT").split(";", false):
			exts.append(e.to_lower())
		if exts.size() == 1:
			exts.append_array([".exe", ".cmd", ".bat"])
	var dirs: Array = (
		[""]
		if (cmd.contains("/") or cmd.contains("\\"))
		else Array(OS.get_environment("PATH").split(";" if windows else ":", false))
	)
	for d in dirs:
		for e in exts:
			var p: String = cmd + e if d == "" else str(d).path_join(cmd + e)
			if FileAccess.file_exists(p):
				return p
	return ""


# the prompt for one line; the open things are the context's
func prompt(text: String, context: Dictionary) -> String:
	var d := LocalList.parts(float(context["now"]))
	var day: String = Rules.DAYS[int(d["weekday"])].capitalize()
	var now := (
		"Now: %s %04d-%02d-%02d %02d:%02d (local time)."
		% [day, d["year"], d["month"], d["day"], d["hour"], d["minute"]]
	)
	return (
		"\n"
		. join(
			[
				"You turn one line, typed to a person's own to-do list, into one action.",
				now,
				"Open things, one per line as id: text:\n" + _open_text(_open(context)),
				"The line:\n" + text,
				"Answer ONLY with one JSON object, nothing else: " + SCHEMA,
				RULES,
			]
		)
	)


# a reading for `text` and `context`, or {} on any failure; `cb(reading)` runs on a later frame
func ask(text: String, context: Dictionary, cb: Callable) -> void:
	_ask(
		text,
		context,
		func(reading: Dictionary, why: String) -> void:
			last = "ok" if why == "" else "failed (%s), used the simple reader" % why
			if cb.is_valid():
				cb.call(reading)
	)


# one tiny reading: cb("works") or cb(the reason)
func test(context: Dictionary, cb: Callable) -> void:
	_ask(
		"Answer with action answer and say ok.",
		context,
		func(_reading: Dictionary, why: String) -> void: cb.call("works" if why == "" else why)
	)


func _ask(text: String, context: Dictionary, cb: Callable) -> void:
	var path := which(command)
	if path == "":
		cb.call_deferred({}, "command not found")
		return
	var spawned := _spawn(path, prompt(text, context))
	if spawned.is_empty():
		cb.call_deferred({}, "could not start")
		return
	var pid: int = spawned["pid"]
	var box := {"over": false, "timed_out": false}
	Engine.get_main_loop().create_timer(limit).timeout.connect(
		func() -> void:
			if not box["over"] and OS.is_process_running(pid):
				box["timed_out"] = true
				OS.kill(pid)
	)
	var thread := Thread.new()
	thread.start(_collect.bind(spawned, thread, box, context, cb))


func _spawn(path: String, prompt_text: String) -> Dictionary:
	var args := ["-p", prompt_text, "--model", "haiku", "--output-format", "json"]
	if OS.get_name() == "Windows":
		if path.get_extension().to_lower() in ["cmd", "bat"]:
			args[1] = _batch_safe(prompt_text)
		return OS.execute_with_pipe(path, args)
	return OS.execute_with_pipe("/bin/sh", ["-c", 'exec "$0" "$@" </dev/null', path] + args)


# cmd.exe parses a .cmd's arguments and one can break out of them: the prompt stays plain
static func _batch_safe(text: String) -> String:
	var out := text.replace('"', "'")
	for c in ["%", "^", "&", "|", "<", ">", "!", "\r", "\n"]:
		out = out.replace(c, " ")
	return out


# on the thread: wait for the program's end and take its output
func _collect(
	spawned: Dictionary, thread: Thread, box: Dictionary, context: Dictionary, cb: Callable
) -> void:
	var out := PackedByteArray()
	var io: FileAccess = spawned["stdio"]
	while true:
		var part := io.get_buffer(4096)
		out.append_array(part)
		if part.size() < 4096:
			break
	var pid: int = spawned["pid"]
	var code := -1
	if not box["timed_out"]:
		for _i in 200:
			if not OS.is_process_running(pid):
				break
			OS.delay_msec(10)
		code = OS.get_process_exit_code(pid)
	_finish.call_deferred(thread, box, code, out.get_string_from_utf8(), context, cb)


func _finish(
	thread: Thread, box: Dictionary, code: int, out: String, context: Dictionary, cb: Callable
) -> void:
	thread.wait_to_finish()
	box["over"] = true
	if box["timed_out"]:
		cb.call({}, "timed out")
	elif code != 0:
		cb.call({}, "exit %d" % code)
	else:
		var reading := read_output(out, context)
		cb.call({} if reading.has("why") else reading, str(reading.get("why", "")))


# the program's JSON envelope -> a reading, or {"why": the reason}
func read_output(out: String, context: Dictionary) -> Dictionary:
	var envelope: Variant = _parse(out)
	if not envelope is Dictionary:
		return _no("no reply")
	if envelope.get("is_error") == true:
		return _no("Claude reported an error")
	if not envelope.get("result") is String:
		return _no("no reply")
	var answer: Variant = _json_of(envelope["result"])
	if not answer is Dictionary:
		return _no("reply was not JSON")
	return check(answer, context)


# the model's text as an object, whether bare, fenced or after a line of talk
static func _json_of(text: String) -> Variant:
	var s := text.strip_edges()
	var parsed: Variant = _parse(s)
	if parsed is Dictionary:
		return parsed
	var from := s.find("{")
	var to := s.rfind("}")
	return _parse(s.substr(from, to - from + 1)) if from >= 0 and to > from else null


# like JSON.parse_string, without the error line the engine prints for text that is not JSON
static func _parse(text: String) -> Variant:
	var json := JSON.new()
	return json.data if json.parse(text) == OK else null


static func _no(why: String) -> Dictionary:
	return {"why": why}


# the model's object, strictly -> a reading, or {"why": ...}
func check(o: Dictionary, context: Dictionary) -> Dictionary:
	var action: Variant = o.get("action")
	if not (action is String and action in ACTIONS):
		return _no("unknown action")
	var say: String = str(o["say"]).strip_edges() if o.get("say") is String else ""
	match action:
		"list":
			return {"action": "say", "say": _rules.read("list", context)["say"]}
		"answer":
			return _no("no answer") if say == "" else {"action": "say", "say": say}
		"done", "delete":
			var id: Variant = o.get("id")
			var open := _open(context)
			if not ((id is float or id is int) and id == floorf(id) and open.has(int(id))):
				return _no("not an open thing")
			var line := "%s: %s." % ["Done" if action == "done" else "Deleted", open[int(id)]]
			return {"action": action, "id": int(id), "say": say if say != "" else line}
	return _add(o, say, context)


func _add(o: Dictionary, say: String, context: Dictionary) -> Dictionary:
	var body := {}
	for field in [_kind_text, _time, _repeat, _who, _steps]:
		var why: String = field.call(o, body, context)
		if why != "":
			return _no(why)
	var assumed: Variant = _blank(o.get("assumed"))
	if say == "":
		say = "%s: %s." % [str(body["kind"]).capitalize(), body["text"]]
	if assumed is String:
		say += " (assumed: %s)" % assumed
	return {"action": "add", "body": body, "say": say}


# the checks of an add: each fills `body` from the model's object and answers "" or what is wrong
func _kind_text(o: Dictionary, body: Dictionary, _context: Dictionary) -> String:
	var text: Variant = o.get("text")
	if not (o.get("kind") is String and o["kind"] in LocalList.KINDS):
		return "unknown kind"
	if not (text is String and text.strip_edges() != "" and text.length() <= LocalList.MAX_TEXT):
		return "no text"
	body.merge({"kind": o["kind"], "text": text.strip_edges()})
	return ""


func _time(o: Dictionary, body: Dictionary, context: Dictionary) -> String:
	var at: Variant = _blank(o.get("at"))
	if (body["kind"] == "reminder") != (at != null):
		return "a reminder needs a time and nothing else has one"
	if at == null:
		return ""
	var now: float = context["now"]
	var probe := LocalList.new("", func() -> float: return now, float(context["bias"]))
	if not (at is String and probe._when(at) is float):
		return "the time is not usable"
	body["at"] = at
	return ""


func _repeat(o: Dictionary, body: Dictionary, _context: Dictionary) -> String:
	var every: Variant = _blank(o.get("every"))
	if every == null:
		return ""
	if body["kind"] != "reminder" or LocalList.every_of(every) == "":
		return "the repeat is not usable"
	body["every"] = every
	return ""


func _who(o: Dictionary, body: Dictionary, _context: Dictionary) -> String:
	var who: Variant = _blank(o.get("who"))
	if body["kind"] != "waiting":
		return ""
	if not who is String:
		return "no one waited on"
	body["who"] = who.strip_edges()
	return ""


func _steps(o: Dictionary, body: Dictionary, _context: Dictionary) -> String:
	if body["kind"] != "project":
		return ""
	var steps: Variant = o.get("steps")
	if not (steps is Array and steps.size() >= 1 and steps.size() <= MAX_STEPS):
		return "no steps"
	for s in steps:
		if not (s is String and s.strip_edges() != "" and s.length() <= LocalList.MAX_TEXT):
			return "no steps"
	body["steps"] = steps.map(func(s): return s.strip_edges())
	return ""


# "", an empty list and null are all "not given"
static func _blank(v: Variant) -> Variant:
	if v is String and v.strip_edges() == "":
		return null
	return v


# id -> text of what the line may refer to: open to-dos and reminders, waiting-ons, projects, notes
static func _open(context: Dictionary) -> Dictionary:
	var out := {}
	var st: Dictionary = context["status"]
	for key in ["open", "coming", "waiting", "projects", "note_rows"]:
		for row in st.get(key, []):
			out[int(row["id"])] = str(row["text"])
	return out


func _open_text(open: Dictionary) -> String:
	var lines: Array = []
	for id in open:
		lines.append("%d: %s" % [id, str(open[id]).replace("\n", " ")])
	return "(nothing)" if lines.is_empty() else "\n".join(lines.slice(0, MAX_OPEN))
