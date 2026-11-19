extends RefCounted

# The soak's checks of the house's own list: `local_list.gd` and `reader_rules.gd` as tables over
# an injected clock, the list file, the re-ring schedule, and the backend's routes. Nothing here
# touches the user's files: the list is `user://soak_list*.json`.
const LocalList := preload("res://local_list.gd")
const Reader := preload("res://reader_rules.gd")
const BackendLocal := preload("res://backend_local.gd")
const FILE := "user://soak_list.json"

var s
var t := 0.0
var _told: Array = []


func _init(soak) -> void:
	s = soak


func _clock() -> float:
	return t


static func at(y: int, m: int, d: int, h: int = 0, mi: int = 0) -> float:
	return LocalList.wall(y, m, d, h, mi)


func _list(path: String = "", bias: float = 0.0) -> RefCounted:
	return LocalList.new(path, Callable(self, "_clock"), bias)


func _eq(got: Variant, want: Variant, what: String) -> void:
	s._check(got == want, "%s: got %s, want %s" % [what, str(got), str(want)])


func _line(r: Dictionary, code: int, line: String, what: String) -> void:
	_eq(
		[r["code"], r["body"].get("error") if r["body"] is Dictionary else null], [code, line], what
	)


func _wipe() -> void:
	for f in ["", ".tmp", ".bak", ".broken-1", ".broken-2"]:
		var p: String = (
			FILE.get_basename()
			+ f
			+ (".json" if f in ["", ".bak", ".broken-1", ".broken-2"] else ".json.tmp")
		)
		if f == ".bak":
			p = FILE.get_basename() + ".bak.json"
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


func run() -> void:
	t = at(2026, 11, 18, 14)
	_adds()
	_bounds()
	_refusals()
	_repeats()
	_done_and_projects()
	_edits()
	_later_revive_plan()
	_agendas()
	_pick()
	_rings()
	_files()
	_reader()
	_reader_acts()


func _adds() -> void:
	var l := _list()
	var r: Dictionary = l.add({"kind": "todo", "text": "  buy milk  "})
	_eq(
		[r["code"], r["body"]["id"], r["body"]["text"], r["body"]["kind"]],
		[200, 1, "buy milk", "todo"],
		"a to-do"
	)
	r = l.add({"kind": "reminder", "text": "bins", "at": "2026-11-21T09:00"})
	_eq(r["body"]["due_at"], "2026-11-21T09:00:00Z", "a reminder's time is kept as UTC")
	var st: Dictionary = l.status()
	_eq(st["open"].map(func(x): return x["text"]), ["buy milk"], "open")
	_eq(st["coming"].map(func(x): return x["text"]), ["bins"], "coming")
	_eq(st["open"][0].keys().size(), 8, "a row has id kind text due_at every since told_at project")
	l.add({"kind": "note", "text": "a"})
	l.add({"kind": "note", "text": "b"})
	l.add({"kind": "waiting", "text": "the lease", "who": " Dana "})
	st = l.status()
	_eq(
		[st["notes"], st["note_rows"].map(func(x): return x["id"])],
		[["b", "a"], [4, 3]],
		"notes, newest first"
	)
	var w: Dictionary = st["waiting"][0]
	_eq(
		[w["who"], w["kind"], w["due_at"]],
		["Dana", "waiting", "2026-11-21T14:00:00Z"],
		"a waiting-on, asked after three days"
	)
	_eq(l.doc["next_id"], 6, "ids are never reused")
	var z := _list("", -25200.0)
	r = z.add({"kind": "reminder", "text": "x", "at": "2026-11-21T09:00"})
	_eq(r["body"]["due_at"], "2026-11-21T16:00:00Z", "local time goes out as UTC")
	r = z.add({"kind": "reminder", "text": "y", "at": "2026-11-21T16:00:00Z"})
	_eq(r["body"]["due_at"], "2026-11-21T16:00:00Z", "a time with a zone is that instant")
	r = z.add({"kind": "reminder", "text": "y", "at": "2026-11-21T18:00+02:00"})
	_eq(r["body"]["due_at"], "2026-11-21T16:00:00Z", "an offset is applied")
	_eq(z.status()["coming"][0]["due_at"], "2026-11-21T16:00:00Z", "and read back")


func _bounds() -> void:
	var l := _list()
	for case in [
		["2025-11-18T14:00", 200],
		["2025-11-18T13:59", 400],
		["2046-11-18T14:00", 200],
		["2046-11-18T14:01", 400],
		["2024-02-29T09:00", 400],
		["2028-02-29T09:00", 200],
	]:
		var r: Dictionary = l.add({"kind": "reminder", "text": "x", "at": case[0]})
		_eq(r["code"], case[1], "at %s" % case[0])
	_line(
		l.add({"kind": "reminder", "text": "x", "at": "2024-01-01T09:00"}),
		400,
		LocalList.E_RANGE,
		"a year back"
	)
	for bad in [
		"tomorrow", "2026-02-30T09:00", "2026-11-21", "2026-11-21T25:00", "2026-13-01T09:00", 5
	]:
		_line(
			l.add({"kind": "reminder", "text": "x", "at": bad}),
			400,
			LocalList.E_AT,
			"at %s" % str(bad)
		)
	var past: Dictionary = l.add({"kind": "reminder", "text": "late", "at": "2026-11-18T09:00"})
	_eq(past["body"]["due_at"], "2026-11-18T09:00:00Z", "a one-off in the past stays as it was")


func _refusals() -> void:
	var l := _list()
	_line(l.add({"kind": "todo", "text": ""}), 400, "text is required", "empty text")
	_line(l.add({"kind": "todo", "text": "   "}), 400, "text is required", "blank text")
	_line(l.add({"kind": "todo"}), 400, "text is required", "no text")
	_line(
		l.add({"kind": "thing", "text": "x"}),
		400,
		"kind is todo, reminder, note, waiting or project",
		"a bad kind"
	)
	_line(l.add({"text": "x"}), 400, "kind is todo, reminder, note, waiting or project", "no kind")
	_line(
		l.add({"kind": "reminder", "text": "x"}), 400, "a reminder needs at", "a reminder needs at"
	)
	_line(
		l.add({"kind": "todo", "text": "x", "at": "2026-11-21T09:00"}),
		400,
		"at is for a reminder",
		"at on a to-do"
	)
	_line(
		l.add({"kind": "todo", "text": "x", "every": "day"}),
		400,
		"every is for a reminder",
		"every on a to-do"
	)
	for bad in ["fortnight", "100 day", "0 week", "2 years", "", 3]:
		_line(
			l.add({"kind": "reminder", "text": "x", "at": "2026-11-21T09:00", "every": bad}),
			400,
			LocalList.E_EVERY,
			"every %s" % str(bad)
		)
	_line(
		l.add({"kind": "waiting", "text": "x"}),
		400,
		"who is required for a waiting-on",
		"waiting needs who"
	)
	_line(
		l.add({"kind": "waiting", "text": "x", "who": " "}),
		400,
		"who is required for a waiting-on",
		"blank who"
	)
	for bad in [[], ["", "  "], "a", [1], null]:
		_line(
			l.add({"kind": "project", "text": "p", "steps": bad}),
			400,
			"steps is a list of texts, at least one",
			"steps %s" % str(bad)
		)
	_line(
		l.add({"kind": "project", "text": "p", "steps": range(51).map(func(i): return "s")}),
		400,
		"steps is a list of texts, at least one",
		"fifty-one steps"
	)
	_line(
		l.add({"kind": "todo", "text": "x", "project": "p"}),
		400,
		"project is a project's id",
		"a bad project"
	)
	_line(
		l.add({"kind": "note", "text": "x", "project": 3}),
		400,
		"project is for a to-do",
		"a note with a project"
	)
	_eq(l.add({"kind": "todo", "text": "x", "project": 99})["code"], 404, "a step of no project")
	_eq(
		l.add({"kind": "todo", "text": "x", "project": null})["code"], 200, "a null project is none"
	)
	var long := "x".repeat(600)
	_eq(l.add({"kind": "todo", "text": long})["body"]["text"].length(), 500, "text is cut at 500")
	_eq(
		(
			l
			. add({"kind": "reminder", "text": "x", "at": "2026-11-21T09:00", "every": "1 week"})["body"]["every"]
		),
		"week",
		"1 week is week"
	)
	_eq(
		(
			l
			. add({"kind": "reminder", "text": "x", "at": "2026-11-21T09:00", "every": "6 weeks"})["body"]["every"]
		),
		"6 week",
		"plurals are read"
	)
	for id in [77]:
		for route in ["edit", "plan", "revive", "done", "drop", "later", "answer"]:
			var r: Dictionary = (
				l.edit(id, {"text": "x"})
				if route == "edit"
				else (
					l.plan(id, {"plan": []})
					if route == "plan"
					else (
						l.revive(id)
						if route == "revive"
						else (
							l.done(id)
							if route == "done"
							else (
								l.drop(id)
								if route == "drop"
								else (
									l.later(id, {"until": "hour"})
									if route == "later"
									else l.answer(id, {"choice": "nottoday"})
								)
							)
						)
					)
				)
			)
			_eq(r["code"], 404, "%s of an id that is not live" % route)
	var made: int = l.add({"kind": "todo", "text": "y"})["body"]["id"]
	l.done(made)
	_eq(
		[
			l.done(made)["code"],
			l.drop(made)["code"],
			l.edit(made, {"text": "z"})["code"],
			l.later(made, {"until": "hour"})["code"]
		],
		[404, 404, 404, 404],
		"a done thing is not live"
	)
	var gone: int = l.add({"kind": "todo", "text": "y"})["body"]["id"]
	_eq([l.drop(gone)["code"], l.drop(gone)["code"]], [200, 404], "a deleted thing is deleted once")


func _repeats() -> void:
	var l := _list()
	t = at(2026, 11, 18, 14)
	var r: Dictionary = l.add(
		{"kind": "reminder", "text": "bins", "at": "2026-11-10T09:00", "every": "week"}
	)
	_eq(
		r["body"]["due_at"],
		"2026-11-24T09:00:00Z",
		"a weekly one set in the past starts from its next time"
	)
	r = l.add({"kind": "reminder", "text": "water", "at": "2026-11-20T09:00", "every": "2 week"})
	var id: int = r["body"]["id"]
	t = at(2026, 11, 20, 10)
	_eq(
		l.done(id)["body"]["due_at"],
		"2026-12-04T09:00:00Z",
		"done on every other week rolls two weeks on"
	)
	_eq(
		[l.status()["done_week"], l.status()["open"].is_empty(), l.status()["coming"].size()],
		[0, true, 2],
		"and stays open, not counted done"
	)
	t = at(2026, 12, 20, 10)
	_eq(
		l.done(id)["body"]["due_at"],
		"2027-01-01T09:00:00Z",
		"a long way behind it lands on the next after now"
	)
	t = at(2026, 11, 20, 8)
	r = l.add({"kind": "reminder", "text": "six", "at": "2026-11-20T09:00", "every": "6 day"})
	t = at(2026, 11, 20, 10)
	_eq(l.done(r["body"]["id"])["body"]["due_at"], "2026-11-26T09:00:00Z", "every 6 days")
	t = at(2027, 1, 1, 10)
	r = l.add({"kind": "reminder", "text": "rent", "at": "2027-01-31T09:00", "every": "month"})
	id = r["body"]["id"]
	for step in [
		[at(2027, 1, 31, 10), "2027-02-28T09:00:00Z"],
		[at(2027, 2, 28, 10), "2027-03-31T09:00:00Z"],
		[at(2027, 3, 31, 10), "2027-04-30T09:00:00Z"],
		[at(2027, 4, 30, 10), "2027-05-31T09:00:00Z"]
	]:
		t = step[0]
		_eq(l.done(id)["body"]["due_at"], step[1], "monthly keeps the 31st: %s" % step[1])
	t = at(2026, 11, 18, 10)
	r = l.add({"kind": "reminder", "text": "quarter", "at": "2026-11-30T09:00", "every": "3 month"})
	id = r["body"]["id"]
	t = at(2026, 11, 30, 10)
	_eq(l.done(id)["body"]["due_at"], "2027-02-28T09:00:00Z", "every 3 months clamps in February")
	t = at(2027, 2, 28, 10)
	_eq(l.done(id)["body"]["due_at"], "2027-05-30T09:00:00Z", "and returns to the 30th")
	t = at(2026, 11, 18, 10)
	r = l.add(
		{"kind": "reminder", "text": "past month", "at": "2026-08-31T09:00", "every": "month"}
	)
	_eq(
		r["body"]["due_at"],
		"2026-11-30T09:00:00Z",
		"a monthly one set in the past keeps its day: 31 Aug, 30 Sep, 31 Oct, 30 Nov"
	)
	r = l.edit(r["body"]["id"], {"at": "2026-12-31T09:00"})
	t = at(2026, 12, 31, 10)
	_eq(
		l.done(r["body"]["id"])["body"]["due_at"],
		"2027-01-31T09:00:00Z",
		"an edited time moves the anchor"
	)
	t = at(2026, 11, 18, 14)


func _done_and_projects() -> void:
	var l := _list()
	t = at(2026, 11, 18, 14)
	var todo: int = l.add({"kind": "todo", "text": "buy milk"})["body"]["id"]
	var r: Dictionary = l.done(todo)
	var st: Dictionary = l.status()
	_eq(
		[
			r["code"],
			st["open"].size(),
			st["done_week"],
			st["done"][0]["text"],
			st["done"][0]["done_at"]
		],
		[200, 0, 1, "buy milk", "2026-11-18T14:00:00Z"],
		"done leaves open and counts"
	)
	t = at(2026, 11, 26, 14)
	_eq(
		[l.status()["done_week"], l.status()["done"].size()],
		[0, 0],
		"and leaves the week eight days on"
	)
	t = at(2026, 11, 18, 14)
	var p: Dictionary = (
		l.add({"kind": "project", "text": "Move", "steps": ["a", "b", " ", "c"]})["body"]
	)
	_eq(
		[p["kind"], p["next"]["text"], p["plan"], p["steps_done"], p["done"]],
		["project", "a", ["b", "c"], [], 0],
		"a project: the first step open, the rest planned"
	)
	var open: Array = l.status()["open"]
	_eq(
		[open.size(), open[0]["project"]["text"]],
		[1, "Move"],
		"its open step is on the board under its name"
	)
	l.done(p["next"]["id"])
	p = l.status()["projects"][0]
	_eq(
		[p["next"]["text"], p["plan"], p["steps_done"], p["done"]],
		["b", ["c"], ["a"], 1],
		"done promotes the next planned step"
	)
	l.done(p["next"]["id"])
	p = l.status()["projects"][0]
	_eq([p["next"]["text"], p["plan"]], ["c", []], "and again")
	l.done(p["next"]["id"])
	p = l.status()["projects"][0]
	_eq(
		[p["next"], p["plan"], p["steps_done"]],
		[null, [], ["a", "b", "c"]],
		"the last step leaves the project with none open"
	)
	var step: Dictionary = l.add({"kind": "todo", "text": "d", "project": p["id"]})["body"]
	_eq(
		[step["kind"], step["project"]["text"]],
		["todo", "Move"],
		"a step for a project with none open is its open step"
	)
	var again: Dictionary = l.add({"kind": "todo", "text": "e", "project": p["id"]})["body"]
	_eq([again["kind"], again["plan"]], ["project", ["e"]], "the next goes to the end of its plan")
	l.plan(p["id"], {"plan": ["e", "f"]})
	l.done(step["id"])
	_eq(l.status()["projects"][0]["next"]["text"], "e", "the plan is promoted from the front")
	_eq(l.done(p["id"])["code"], 200, "a project is finished")
	st = l.status()
	_eq([st["projects"].size(), st["open"].size()], [0, 0], "and takes its open steps with it")
	var q: Dictionary = (
		l.add({"kind": "project", "text": "Knit", "steps": ["needles", "cast on"]})["body"]
	)
	l.done(q["next"]["id"])
	var dropped: Dictionary = l.drop(q["id"])
	st = l.status()
	_eq(
		[dropped["code"], dropped["body"]["text"], st["projects"].size(), st["open"].size()],
		[200, "Knit", 0, 0],
		"deleting a project takes its steps and plan"
	)
	_eq(
		st["done"].filter(func(x): return x["text"] == "needles").size(),
		1,
		"its finished steps stay done"
	)
	var w: Dictionary = (
		l.add({"kind": "project", "text": "Paint", "steps": ["tape", "roll"]})["body"]
	)
	_eq(l.drop(w["next"]["id"])["code"], 200, "deleting the only open step")
	_eq(
		[l.status()["projects"][0]["next"]["text"], l.status()["projects"][0]["plan"]],
		["roll", []],
		"proposes the next from the plan"
	)
	var many := _list()
	for i in 205:
		many.done(many.add({"kind": "todo", "text": "t%d" % i})["body"]["id"])
		t += 1.0
	_eq(
		[many.things().size(), many.status()["done_week"]], [200, 200], "the last 200 done are kept"
	)
	_eq(many.things()[0]["text"], "t5", "the oldest go first")
	t = at(2026, 11, 18, 14)


func _edits() -> void:
	var l := _list()
	var todo: int = l.add({"kind": "todo", "text": "buy milk"})["body"]["id"]
	var rem: Dictionary = (
		l
		. add({"kind": "reminder", "text": "bins", "at": "2026-11-24T09:00", "every": "week"})["body"]
	)
	var note: int = l.add({"kind": "note", "text": "n"})["body"]["id"]
	var proj: int = l.add({"kind": "project", "text": "p", "steps": ["s"]})["body"]["id"]
	_eq(l.edit(todo, {"text": "buy oat milk"})["body"]["text"], "buy oat milk", "a to-do's text")
	_line(l.edit(todo, {"text": ""}), 400, "text is required", "an edit to nothing")
	_line(
		l.edit(todo, {"at": "2026-11-24T09:00"}),
		400,
		"a to-do has no time: send kind reminder with at",
		"a time on a to-do"
	)
	_line(
		l.edit(todo, {"every": "week"}),
		400,
		"a to-do has no time: send kind reminder with at",
		"a repeat on a to-do"
	)
	_line(l.edit(todo, {"kind": "reminder"}), 400, "a reminder needs at", "to a reminder needs at")
	_line(l.edit(todo, {"kind": "note"}), 400, "kind is only todo or reminder", "kind note")
	_line(
		l.edit(note, {"kind": "todo"}),
		400,
		"kind is only todo or reminder",
		"a note cannot become a to-do"
	)
	_line(l.edit(note, {"at": "2026-11-24T09:00"}), 400, "at is for a reminder", "a time on a note")
	_line(l.edit(proj, {"every": "week"}), 400, "at is for a reminder", "a repeat on a project")
	_line(
		l.edit(rem["id"], {"kind": "todo", "at": "2026-11-24T09:00"}),
		400,
		"a to-do has no time and no repeat",
		"to a to-do with a time"
	)
	_line(l.edit(rem["id"], {"every": "soon"}), 400, LocalList.E_EVERY, "a bad repeat")
	_line(l.edit(rem["id"], {"at": "nonsense"}), 400, LocalList.E_AT, "a bad time")
	_eq(l.edit(note, {"text": "m"})["body"]["text"], "m", "a note takes text only")
	var r: Dictionary = l.edit(
		todo, {"text": "buy milk", "kind": "reminder", "at": "2026-12-02T10:00", "every": null}
	)
	_eq(
		[r["body"]["kind"], r["body"]["due_at"], r["body"]["every"]],
		["reminder", "2026-12-02T10:00:00Z", null],
		"a to-do becomes a reminder"
	)
	r = l.edit(todo, {"kind": "todo"})
	_eq(
		[r["body"]["kind"], r["body"]["due_at"], r["body"]["every"]],
		["todo", null, null],
		"a reminder becomes a to-do with no time and no repeat"
	)
	r = l.edit(rem["id"], {"text": "bins", "at": "2026-11-24T09:00", "every": null})
	_eq([r["body"]["every"], r["body"]["due_at"]], [null, "2026-11-24T09:00:00Z"], "stop repeating")
	r = l.edit(rem["id"], {"text": "bins out", "at": "2026-11-24T18:30", "every": "2 week"})
	_eq(
		[r["body"]["every"], r["body"]["text"], r["body"]["due_at"]],
		["2 week", "bins out", "2026-11-24T18:30:00Z"],
		"a changed text, time and repeat"
	)
	l.things().filter(func(x): return x["id"] == rem["id"])[0]["told_at"] = "2026-11-18T10:00:00Z"
	r = l.edit(rem["id"], {"at": "2026-11-25T18:30"})
	_eq(r["body"]["told_at"], null, "a moved reminder is told afresh")
	r = l.edit(rem["id"], {"text": "bins again"})
	_eq(r["body"]["due_at"], "2026-11-25T18:30:00Z", "text alone moves nothing")
	r = l.edit(rem["id"], {"at": "2026-11-01T09:00", "every": "week"})
	_eq(
		r["body"]["due_at"],
		"2026-11-22T09:00:00Z",
		"a repeat moved into the past starts from its next time"
	)
	l.things().filter(func(x): return x["id"] == rem["id"])[0]["state"] = "someday"
	r = l.edit(rem["id"], {"every": "week"})
	_eq(
		[r["code"], l.status()["someday"].size()],
		[200, 0],
		"a repeat set on a put-off thing brings it back"
	)


func _later_revive_plan() -> void:
	var l := _list()
	t = at(2026, 11, 18, 14, 20)
	var todo: int = l.add({"kind": "todo", "text": "x"})["body"]["id"]
	var r: Dictionary = l.later(todo, {"until": "hour"})
	_eq(
		[r["body"]["kind"], r["body"]["due_at"], r["body"]["told_at"]],
		["reminder", "2026-11-18T15:20:00Z", null],
		"later an hour"
	)
	_eq(l.status()["coming"].size(), 1, "it is coming")
	r = l.later(todo, {"until": "tomorrow"})
	_eq(r["body"]["due_at"], "2026-11-19T09:00:00Z", "later till tomorrow is 09:00")
	t = at(2026, 11, 18, 23, 50)
	_eq(
		l.later(todo, {"until": "tomorrow"})["body"]["due_at"],
		"2026-11-19T09:00:00Z",
		"tomorrow is the next day, near midnight"
	)
	_line(l.later(todo, {"until": "never"}), 400, "until is hour or tomorrow", "a bad until")
	var note: int = l.add({"kind": "note", "text": "n"})["body"]["id"]
	_line(
		l.later(note, {"until": "hour"}),
		400,
		"only a to-do or a reminder can be put off",
		"a note is not put off"
	)
	var someday: Dictionary = l.add({"kind": "todo", "text": "maybe"})["body"]
	l.things().filter(func(x): return x["id"] == someday["id"])[0]["state"] = "someday"
	var rep: Dictionary = (
		l
		. add({"kind": "reminder", "text": "weekly", "at": "2026-11-20T09:00", "every": "week"})["body"]
	)
	var plain: Dictionary = (
		l.add({"kind": "reminder", "text": "once", "at": "2026-11-20T09:00"})["body"]
	)
	for x in [rep, plain]:
		l.things().filter(func(y): return y["id"] == x["id"])[0]["state"] = "someday"
	t = at(2026, 12, 10, 10)
	_eq(l.status()["someday"].size(), 3, "put-off things are on someday")
	_eq(
		[
			l.revive(someday["id"])["body"]["kind"],
			l.revive(rep["id"])["body"]["due_at"],
			l.revive(plain["id"])["body"]["due_at"]
		],
		["todo", "2026-12-11T09:00:00Z", "2026-11-20T09:00:00Z"],
		"revive: a to-do, a repeat at its next time, a one-off as it was"
	)
	_eq(l.revive(someday["id"])["code"], 404, "only a put-off thing is revived")
	t = at(2026, 11, 18, 14)
	var p: Dictionary = l.add({"kind": "project", "text": "P", "steps": ["a"]})["body"]
	_eq(
		l.plan(p["id"], {"plan": ["x", " y ", ""]})["body"]["plan"], ["x", "y"], "a plan is trimmed"
	)
	_line(
		l.plan(p["id"], {"plan": "x"}), 400, "plan is a list of texts", "a plan that is not a list"
	)
	_line(l.plan(p["id"], {"plan": [1]}), 400, "plan is a list of texts", "a plan of numbers")
	_eq(l.plan(todo, {"plan": []})["code"], 404, "a to-do has no plan")
	_eq(l.plan(p["id"], {"plan": []})["body"]["plan"], [], "an empty plan")
	_eq(l.answer(todo, {"choice": "nottoday"})["code"], 200, "not today")
	_line(l.answer(todo, {"choice": "later"}), 400, "choice is nottoday", "another choice")


func _agendas() -> void:
	t = at(2026, 11, 18, 12)
	var l := _list()
	var said: Array = []
	l.told_agenda.connect(func(text: String) -> void: said.append(text))
	_line(l.agenda_add({"every": "week"}), 400, "name is required", "an agenda needs a name")
	_line(l.agenda_add({"name": "retro", "every": "often"}), 400, LocalList.E_EVERY, "a bad every")
	var r: Dictionary = l.agenda_add({"name": " retro ", "every": "2 week", "at": "2026-11-19T14:00"})
	var id := int(r["body"]["id"])
	_eq(
		[r["code"], r["body"]["name"], r["body"]["every"], r["body"]["next_at"], r["body"]["notes"]],
		[200, "retro", "2 week", "2026-11-19T14:00:00Z", []],
		"an agenda with a rhythm"
	)
	_line(l.agenda_add({"name": "RETRO"}), 400, "there is already an agenda called RETRO", "a name is taken in any case")
	_eq(l.agenda_note(id, {"text": " flaky gate "})["body"]["text"], "flaky gate", "a note on the pile")
	l.agenda_note(id, {"text": "deploy took three tries"})
	_line(l.agenda_note(id, {"text": " "}), 400, "text is required", "a note needs text")
	_eq(l.agenda_note(99, {"text": "x"})["code"], 404, "no such agenda")
	var st: Dictionary = l.status()
	_eq(
		[st["notes"], st["note_rows"], st["agendas"][0]["notes"].map(func(x): return x["text"])],
		[[], [], ["flaky gate", "deploy took three tries"]],
		"a pile's notes are in no plain list"
	)
	t = at(2026, 11, 19, 13, 40)
	l.tick()
	_eq(said.size(), 0, "not told before the lead")
	t = at(2026, 11, 19, 13, 46)
	_eq(l.tick(), true, "told within the lead")
	_eq(said, ["Retro in 15 — 2 things: flaky gate; deploy took three tries"], "the pile is told once")
	t = at(2026, 11, 19, 13, 59)
	l.tick()
	_eq(said.size(), 1, "and not again")
	t = at(2026, 11, 19, 14, 30)
	l.tick()
	_eq(l.status()["agendas"][0]["next_at"], "2026-11-19T14:00:00Z", "the time stands while it is on")
	t = at(2026, 11, 19, 15, 1)
	l.tick()
	_eq(l.status()["agendas"][0]["next_at"], "2026-12-03T14:00:00Z", "an hour after, the time moves on by the rhythm")
	_eq(l.agenda_clear(id)["body"]["notes"], [], "clearing empties the pile")
	st = l.status()
	_eq([st["done"], st["done_week"], st["agendas"].size()], [[], 0, 1], "cleared notes are kept, not counted as done")
	var e: Dictionary = l.agenda_edit(id, {"name": "weekly retro", "every": null, "at": null})
	_eq([e["body"]["name"], e["body"]["every"], e["body"]["next_at"]], ["weekly retro", null, null], "an agenda is edited, a rhythm cleared")
	l.agenda_note(id, {"text": "a"})
	_eq(l.agenda_drop(id)["code"], 200, "an agenda is deleted")
	_eq([l.status()["agendas"], l.things().size()], [[], 0], "with its notes")
	_eq(l.agenda_drop(id)["code"], 404, "once")
	_wipe()
	var kept := _list(FILE)
	kept.agenda_add({"name": "offsite"})
	kept.agenda_note(int(kept.status()["agendas"][0]["id"]), {"text": "venue"})
	var again := _list(FILE)
	again.load_file()
	_eq(again.status()["agendas"].map(func(a): return [a["name"], a["notes"].size()]), [["offsite", 1]], "agendas are kept in the list file")
	_wipe()


func _pick() -> void:
	var l := _list()
	t = at(2026, 11, 15, 10)
	var old: int = l.add({"kind": "todo", "text": "oldest"})["body"]["id"]
	t = at(2026, 11, 17, 10)
	var newer: int = l.add({"kind": "todo", "text": "newer"})["body"]["id"]
	var proj: Dictionary = (
		l.add({"kind": "project", "text": "Move", "steps": ["book the van"]})["body"]
	)
	t = at(2026, 11, 18, 8)
	var due: int = (
		l.add({"kind": "reminder", "text": "pills", "at": "2026-11-18T07:30"})["body"]["id"]
	)
	l.add({"kind": "reminder", "text": "later", "at": "2026-11-19T09:00"})
	t = at(2026, 11, 18, 14)
	var r: Dictionary = l.pick()
	_eq(
		[r["body"]["pick"]["id"], r["body"]["pick"]["why"]],
		[due, "it was due this morning"],
		"an overdue reminder first"
	)
	r = l.pick([due])
	_eq(
		[r["body"]["pick"]["id"], r["body"]["pick"]["why"], r["body"]["say"]],
		[old, "it has sat the longest", "oldest - it has sat the longest"],
		"then the to-do that has sat longest"
	)
	r = l.pick([due, old])
	_eq(r["body"]["pick"]["id"], newer, "skip is honoured")
	r = l.pick([due, old, newer])
	_eq(
		[r["body"]["pick"]["id"], r["body"]["pick"]["why"]],
		[proj["next"]["id"], "it is the next step of Move"],
		"then a project's open step"
	)
	r = l.pick([due, old, newer, proj["next"]["id"]])
	_eq(
		[r["body"]["pick"], r["body"]["say"]],
		[null, "Nothing open right now. That's a good place to be."],
		"nothing left"
	)
	_eq(l.answer(due, {"choice": "nottoday"})["body"]["reply"], "Not today: pills.", "not today")
	_eq(l.pick()["body"]["pick"]["id"], old, "a thing put off for today is not picked")
	_eq(l.status()["open"].size(), 4, "but is still open")
	t = at(2026, 11, 19, 5, 59)
	_eq(
		l.pick([old, newer])["body"]["pick"]["id"],
		proj["next"]["id"],
		"hidden until tomorrow 06:00"
	)
	t = at(2026, 11, 19, 6, 0)
	_eq(l.pick()["body"]["pick"]["id"], due, "and back at 06:00")
	t = at(2026, 11, 18, 14)


func _rings() -> void:
	var l := _list()
	l.told.connect(
		func(row: Dictionary) -> void: _told.append([l.iso(t), row["id"], row["told_at"]])
	)
	t = at(2026, 11, 18, 14)
	var id: int = (
		l.add({"kind": "reminder", "text": "stretch", "at": "2026-11-18T15:00"})["body"]["id"]
	)
	var todo: int = l.add({"kind": "todo", "text": "x"})["body"]["id"]
	_told = []
	t = at(2026, 11, 18, 14, 59)
	_eq([l.tick(), _told.size()], [false, 0], "nothing is told before its time")
	var times: Array = []
	for minute in range(15 * 60, 15 * 60 + 30 * 60 + 1):
		t = at(2026, 11, 18) + minute * 60.0
		if l.tick():
			times.append(Time.get_datetime_string_from_unix_time(int(t)).substr(5, 11))
	_eq(
		times,
		["11-18T15:00", "11-18T15:30", "11-18T16:30", "11-18T18:30", "11-19T08:00", "11-19T12:00"],
		"told, then 30 min, 1 h, 2 h, then 4 h that waits for 08:00, then 4 h: six times, none in the night"
	)
	_eq(_told.size(), 6, "the tell is announced each time")
	_eq(
		l.status()["open"].filter(func(x): return x["id"] == id)[0]["told_at"],
		"2026-11-19T12:00:00Z",
		"told_at is the last time"
	)
	t = at(2026, 11, 20, 12)
	_eq([l.tick(), _told.size()], [false, 6], "and never a seventh")
	l.done(id)
	_eq(l.status()["done_week"], 1, "done")
	t = at(2026, 11, 20, 8)
	var daily: int = (
		l
		. add({"kind": "reminder", "text": "water", "at": "2026-11-20T09:00", "every": "day"})["body"]["id"]
	)
	_told = []
	t = at(2026, 11, 20, 9)
	l.tick()
	t = at(2026, 11, 20, 9, 30)
	l.tick()
	_eq(_told.size(), 2, "a repeating one is told too")
	l.done(daily)
	_eq(
		l.status()["coming"].filter(func(x): return x["id"] == daily)[0]["told_at"],
		null,
		"done on it clears the nudges and rolls it on"
	)
	t = at(2026, 11, 20, 11)
	_told = []
	_eq([l.tick(), _told.size()], [false, 0], "and it is quiet until its next time")
	# told while closed
	var path := FILE
	_wipe()
	var a := _list(path)
	t = at(2026, 11, 20, 12)
	var once: int = (
		a.add({"kind": "reminder", "text": "dentist", "at": "2026-11-20T18:00"})["body"]["id"]
	)
	var daily2: int = (
		a
		. add({"kind": "reminder", "text": "vitamins", "at": "2026-11-20T09:00", "every": "day"})["body"]["id"]
	)
	t = at(2026, 11, 24, 10)
	var b := _list(path)
	_told = []
	b.told.connect(func(row: Dictionary) -> void: _told.append(row["id"]))
	b.load_file()
	_eq(_told, [], "loading tells nothing by itself")
	b.tick()
	_told.sort()
	_eq(
		_told,
		[once, daily2],
		"a reminder that came due while the house was closed is told at the next start, once"
	)
	var rows: Array = b.status()["open"]
	_eq(
		rows.filter(func(x): return x["id"] == daily2)[0]["due_at"],
		"2026-11-24T09:00:00Z",
		"a repeating one missed for days stands at its newest time"
	)
	_wipe()
	t = at(2026, 11, 18, 14)


func _files() -> void:
	_wipe()
	var l := _list(FILE)
	l.load_file()
	_eq(l.fresh, true, "no file yet")
	l.add({"kind": "todo", "text": "one"})
	_eq(
		[
			FileAccess.file_exists(FILE),
			FileAccess.file_exists(FILE.get_basename() + ".bak.json"),
			FileAccess.file_exists(FILE + ".tmp")
		],
		[true, false, false],
		"the first save: a file, no .bak, no temp"
	)
	var first := FileAccess.get_file_as_string(FILE)
	l.add({"kind": "todo", "text": "two"})
	_eq(
		FileAccess.get_file_as_string(FILE.get_basename() + ".bak.json"),
		first,
		"the previous file is kept as .bak"
	)
	_eq(FileAccess.file_exists(FILE + ".tmp"), false, "the temp is renamed away")
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FILE))
	_eq([int(doc["v"]), int(doc["next_id"]), doc["things"].size()], [1, 3, 2], "the shape on disk")
	var f := FileAccess.open(FILE + ".tmp", FileAccess.WRITE)
	f.store_string('{"things": [half a wr')
	f.close()
	var back := _list(FILE)
	back.load_file()
	_eq([back.things().size(), back.notice], [2, ""], "a crash mid-write leaves the list whole")
	back.add({"kind": "todo", "text": "three"})
	_eq(
		JSON.parse_string(FileAccess.get_file_as_string(FILE))["things"].size(),
		3,
		"and the next save goes through"
	)
	f = FileAccess.open(FILE, FileAccess.WRITE)
	(
		f
		. store_string(
			'{"v":1,"next_id":9,"mood":{"a":[1]},"things":[{"id":4,"kind":"todo","text":"x","colour":"blue"}]}'
		)
	)
	f.close()
	var kept := _list(FILE)
	kept.load_file()
	kept.add({"kind": "todo", "text": "y"})
	var disk: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FILE))
	_eq(
		[disk["mood"], disk["things"][0]["colour"], int(disk["next_id"])],
		[{"a": [1.0]}, "blue", 10],
		"keys the house does not know are kept, ids go on from next_id"
	)
	_eq(kept.status()["open"].size(), 2, "a thing missing most fields is still read")
	for bad in ['{"nope', "[1,2]", '{"things": 3}', '{"things": [1]}']:
		f = FileAccess.open(FILE, FileAccess.WRITE)
		f.store_string(bad)
		f.close()
		var broke := _list(FILE)
		broke.load_file()
		var n := 1 if bad == '{"nope' else 2
		_eq(
			[broke.things().size(), broke.notice != "", FileAccess.file_exists(FILE)],
			[0, true, false],
			"a list that cannot be read is moved aside: %s" % bad
		)
		_eq(
			FileAccess.file_exists(FILE.get_basename() + ".broken-%d.json" % n),
			true,
			"as house_list.broken-%d.json" % n
		)
		if n == 2:
			DirAccess.remove_absolute(FILE.get_basename() + ".broken-2.json")
	broken_cleanup()
	_wipe()


func broken_cleanup() -> void:
	for n in 4:
		var p := FILE.get_basename() + ".broken-%d.json" % (n + 1)
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


# a line read at a moment, against a list with a few things open
func _read(now: float, line: String, status: Dictionary = {}) -> Dictionary:
	var st := {"open": [], "coming": [], "waiting": [], "projects": [], "note_rows": []}
	st.merge(status, true)
	return Reader.new().read(line, {"now": now, "bias": 0.0, "status": st})


func _things() -> Dictionary:
	return {
		"open":
		[
			{"id": 1, "kind": "todo", "text": "buy milk", "every": null},
			{"id": 2, "kind": "todo", "text": "send photos", "every": null},
			{"id": 3, "kind": "todo", "text": "buy bread", "every": null},
		],
		"coming":
		[
			{
				"id": 4,
				"kind": "reminder",
				"text": "stretch",
				"every": null,
				"due_at": "2026-11-18T15:00:00Z"
			},
			{
				"id": 5,
				"kind": "reminder",
				"text": "bins",
				"every": "week",
				"due_at": "2026-11-24T09:00:00Z"
			},
		],
		"waiting":
		[{"id": 6, "kind": "waiting", "text": "the lease", "who": "Dana", "every": null}],
		"projects": [{"id": 7, "kind": "project", "text": "Move", "every": null}],
		"note_rows": [{"id": 8, "text": "wifi is on the fridge"}],
	}


func _reader() -> void:
	var wed := at(2026, 11, 18, 14)
	var mon_late := at(2026, 11, 30, 23, 30)
	var new_year := at(2026, 12, 31, 23, 30)
	var at_close := at(2027, 1, 31, 23, 30)
	var cases: Array = [
		[wed, "buy milk", "todo", "buy milk", "", "", "To do: buy milk."],
		[
			wed,
			"Remind me to call the plumber tomorrow",
			"reminder",
			"call the plumber",
			"2026-11-19T09:00",
			"",
			"Reminder set: call the plumber, tomorrow 09:00 (no hour given: 09:00)."
		],
		[
			wed,
			"call the plumber tomorrow at 9",
			"reminder",
			"call the plumber",
			"2026-11-19T09:00",
			"",
			"Reminder set: call the plumber, tomorrow 09:00."
		],
		[
			wed,
			"remind me to stretch at 3pm",
			"reminder",
			"stretch",
			"2026-11-18T15:00",
			"",
			"Reminder set: stretch, today 15:00."
		],
		[
			wed,
			"remind me to stretch at 1pm",
			"reminder",
			"stretch",
			"2026-11-19T13:00",
			"",
			"Reminder set: stretch, tomorrow 13:00."
		],
		[
			wed,
			"pay rent at 15:00",
			"reminder",
			"pay rent",
			"2026-11-18T15:00",
			"",
			"Reminder set: pay rent, today 15:00."
		],
		[
			wed,
			"pay rent at 3:30pm",
			"reminder",
			"pay rent",
			"2026-11-18T15:30",
			"",
			"Reminder set: pay rent, today 15:30."
		],
		[
			wed,
			"Call mom at 3 PM tomorrow",
			"reminder",
			"Call mom",
			"2026-11-19T15:00",
			"",
			"Reminder set: Call mom, tomorrow 15:00."
		],
		[
			wed,
			"TOMORROW call mom",
			"reminder",
			"call mom",
			"2026-11-19T09:00",
			"",
			"Reminder set: call mom, tomorrow 09:00 (no hour given: 09:00)."
		],
		[
			wed,
			"dentist thursday",
			"reminder",
			"dentist",
			"2026-11-19T09:00",
			"",
			"Reminder set: dentist, tomorrow 09:00 (no hour given: 09:00)."
		],
		[
			wed,
			"dentist on friday 3pm",
			"reminder",
			"dentist",
			"2026-11-20T15:00",
			"",
			"Reminder set: dentist, Fri 20 Nov 15:00."
		],
		[
			wed,
			"thursday 3pm dentist",
			"reminder",
			"dentist",
			"2026-11-19T15:00",
			"",
			"Reminder set: dentist, tomorrow 15:00."
		],
		[
			wed,
			"dentist next monday",
			"reminder",
			"dentist",
			"2026-11-23T09:00",
			"",
			"Reminder set: dentist, Mon 23 Nov 09:00 (no hour given: 09:00)."
		],
		[
			wed,
			"dentist wednesday",
			"reminder",
			"dentist",
			"2026-11-25T09:00",
			"",
			"Reminder set: dentist, Wed 25 Nov 09:00 (no hour given: 09:00)."
		],
		[
			wed,
			"in 10 minutes call mom",
			"reminder",
			"call mom",
			"2026-11-18T14:10",
			"",
			"Reminder set: call mom, today 14:10."
		],
		[
			wed,
			"remind me to check the oven in 2 hours",
			"reminder",
			"check the oven",
			"2026-11-18T16:00",
			"",
			"Reminder set: check the oven, today 16:00."
		],
		[
			wed,
			"stir in an hour",
			"reminder",
			"stir",
			"2026-11-18T15:00",
			"",
			"Reminder set: stir, today 15:00."
		],
		[
			wed,
			"call dad in 3 days",
			"reminder",
			"call dad",
			"2026-11-21T09:00",
			"",
			"Reminder set: call dad, Sat 21 Nov 09:00 (no hour given: 09:00)."
		],
		[
			wed,
			"renew passport in 2 weeks",
			"reminder",
			"renew passport",
			"2026-12-02T09:00",
			"",
			"Reminder set: renew passport, Wed 2 Dec 09:00 (no hour given: 09:00)."
		],
		[
			wed,
			"party on 21 nov",
			"reminder",
			"party",
			"2026-11-21T09:00",
			"",
			"Reminder set: party, Sat 21 Nov 09:00 (no hour given: 09:00)."
		],
		[
			wed,
			"party nov 21 at 8pm",
			"reminder",
			"party",
			"2026-11-21T20:00",
			"",
			"Reminder set: party, Sat 21 Nov 20:00."
		],
		[
			wed,
			"party 11/21",
			"reminder",
			"party",
			"2026-11-21T09:00",
			"",
			"Reminder set: party, Sat 21 Nov 09:00 (no hour given: 09:00)."
		],
		[
			wed,
			"party on 5 jan",
			"reminder",
			"party",
			"2027-01-05T09:00",
			"",
			"Reminder set: party, Tue 5 Jan 09:00 (no hour given: 09:00)."
		],
		[
			wed,
			"dinner 29 feb at 7pm",
			"reminder",
			"dinner 29 feb",
			"2026-11-18T19:00",
			"",
			"Reminder set: dinner 29 feb, today 19:00."
		],
		[
			wed,
			"tonight call mom",
			"reminder",
			"call mom",
			"2026-11-18T19:00",
			"",
			"Reminder set: call mom, today 19:00 (no hour given: 19:00)."
		],
		[
			wed,
			"today pick up the parcel",
			"reminder",
			"pick up the parcel",
			"2026-11-19T09:00",
			"",
			"Reminder set: pick up the parcel, tomorrow 09:00 (no hour given: 09:00)."
		],
		[
			wed,
			"water the plants every day",
			"reminder",
			"water the plants",
			"2026-11-19T09:00",
			"day",
			"Reminder set: water the plants, tomorrow 09:00, then every day (no hour given: 09:00)."
		],
		[
			wed,
			"bins every week at 7pm",
			"reminder",
			"bins",
			"2026-11-18T19:00",
			"week",
			"Reminder set: bins, today 19:00, then every week."
		],
		[
			wed,
			"rent every 2 months on 1 dec",
			"reminder",
			"rent",
			"2026-12-01T09:00",
			"2 month",
			"Reminder set: rent, Tue 1 Dec 09:00, then every 2 months (no hour given: 09:00)."
		],
		[
			wed,
			"vitamins every other week",
			"reminder",
			"vitamins",
			"2026-11-19T09:00",
			"2 week",
			"Reminder set: vitamins, tomorrow 09:00, then every 2 weeks (no hour given: 09:00)."
		],
		[
			wed,
			"gym every monday at 6pm",
			"reminder",
			"gym",
			"2026-11-23T18:00",
			"week",
			"Reminder set: gym, Mon 23 Nov 18:00, then every week."
		],
		[
			wed,
			"call mom every 3 days",
			"reminder",
			"call mom",
			"2026-11-19T09:00",
			"3 day",
			"Reminder set: call mom, tomorrow 09:00, then every 3 days (no hour given: 09:00)."
		],
		[
			wed,
			"stretch every month",
			"reminder",
			"stretch",
			"2026-11-19T09:00",
			"month",
			"Reminder set: stretch, tomorrow 09:00, then every month (no hour given: 09:00)."
		],
		[
			wed,
			"note: wifi is on the fridge",
			"note",
			"wifi is on the fridge",
			"",
			"",
			"Noted: wifi is on the fridge."
		],
		[
			wed,
			"Note the code is 1234",
			"note",
			"the code is 1234",
			"",
			"",
			"Noted: the code is 1234."
		],
		[
			wed,
			"waiting on Dana for the lease",
			"waiting",
			"the lease",
			"",
			"",
			"Waiting on Dana for the lease. I'll ask in 3 days."
		],
		[
			wed,
			"Dana owes me the lease",
			"waiting",
			"the lease",
			"",
			"",
			"Waiting on Dana for the lease. I'll ask in 3 days."
		],
		[
			wed,
			"remind me to call mom",
			"todo",
			"remind me to call mom",
			"",
			"",
			"To do: remind me to call mom."
		],
		[
			wed,
			"remind me tomorrow",
			"todo",
			"remind me tomorrow",
			"",
			"",
			"To do: remind me tomorrow."
		],
		[wed, "buy 2 apples", "todo", "buy 2 apples", "", "", "To do: buy 2 apples."],
		[
			mon_late,
			"remind me to lock up at 11pm",
			"reminder",
			"lock up",
			"2026-12-01T23:00",
			"",
			"Reminder set: lock up, tomorrow 23:00."
		],
		[
			mon_late,
			"pay the bill tomorrow",
			"reminder",
			"pay the bill",
			"2026-12-01T09:00",
			"",
			"Reminder set: pay the bill, tomorrow 09:00 (no hour given: 09:00)."
		],
		[
			mon_late,
			"call mom tonight",
			"reminder",
			"call mom",
			"2026-12-01T19:00",
			"",
			"Reminder set: call mom, tomorrow 19:00 (no hour given: 19:00)."
		],
		[
			mon_late,
			"in 45 minutes check the oven",
			"reminder",
			"check the oven",
			"2026-12-01T00:15",
			"",
			"Reminder set: check the oven, tomorrow 00:15."
		],
		[
			mon_late,
			"call mom in 1 day",
			"reminder",
			"call mom",
			"2026-12-01T09:00",
			"",
			"Reminder set: call mom, tomorrow 09:00 (no hour given: 09:00)."
		],
		[
			new_year,
			"tomorrow at 8 buy a calendar",
			"reminder",
			"buy a calendar",
			"2027-01-01T08:00",
			"",
			"Reminder set: buy a calendar, tomorrow 08:00."
		],
		[
			new_year,
			"party on 31 dec",
			"reminder",
			"party",
			"2027-01-01T09:00",
			"",
			"Reminder set: party, tomorrow 09:00 (no hour given: 09:00)."
		],
		[
			new_year,
			"resolutions on 1 jan",
			"reminder",
			"resolutions",
			"2027-01-01T09:00",
			"",
			"Reminder set: resolutions, tomorrow 09:00 (no hour given: 09:00)."
		],
		[
			at_close,
			"pay rent tomorrow",
			"reminder",
			"pay rent",
			"2027-02-01T09:00",
			"",
			"Reminder set: pay rent, tomorrow 09:00 (no hour given: 09:00)."
		],
		[
			at_close,
			"rent every month",
			"reminder",
			"rent",
			"2027-02-01T09:00",
			"month",
			"Reminder set: rent, tomorrow 09:00, then every month (no hour given: 09:00)."
		],
		[
			at_close,
			"taxes in 1 week",
			"reminder",
			"taxes",
			"2027-02-07T09:00",
			"",
			"Reminder set: taxes, Sun 7 Feb 09:00 (no hour given: 09:00)."
		],
	]
	var count := 0
	for c in cases:
		var r: Dictionary = _read(c[0], c[1])
		var got := [
			r["action"],
			r["body"]["kind"],
			r["body"]["text"],
			r["body"].get("at", ""),
			r["body"].get("every", ""),
			r["say"]
		]
		_eq(
			got,
			["add", c[2], c[3], c[4], c[5], c[6]],
			"reads '%s' at %s" % [c[1], Time.get_datetime_string_from_unix_time(int(c[0]))]
		)
		count += 1
	_eq(_read(wed, "waiting on Dana for the lease")["body"]["who"], "Dana", "who is waited on")
	_eq(_read(wed, "Dana owes me the lease")["body"]["who"], "Dana", "who owes")
	_eq(count >= 40, true, "at least forty lines in the table")


func _reader_acts() -> void:
	var wed := at(2026, 11, 18, 14)
	var st := _things()
	for case in [
		["done buy milk", "done", 1, "Done: buy milk."],
		["Did send photos", "done", 2, "Done: send photos."],
		["finished photos", "done", 2, "Done: send photos."],
		["done: the lease", "done", 6, "Done: the lease."],
		["done stretch", "done", 4, "Done: stretch."],
		["forget send photos", "delete", 2, "Deleted: send photos."],
		["Delete the wifi", "delete", 8, "Deleted: wifi is on the fridge."],
		["delete buy bread", "delete", 3, "Deleted: buy bread."],
	]:
		var r: Dictionary = _read(wed, case[0], st)
		_eq([r["action"], r.get("id"), r["say"]], [case[1], case[2], case[3]], "'%s'" % case[0])
	var tie: Dictionary = _read(wed, "done buy", st)
	_eq(
		[tie["action"], tie["say"]],
		["say", "Which one? buy milk, buy bread. Nothing changed."],
		"two equal matches are listed and nothing changes"
	)
	_eq(
		_read(wed, "done unicorns", st)["say"],
		"I couldn't find anything open like that. Nothing changed.",
		"no match"
	)
	_eq(
		_read(wed, "delete the bins", st)["say"],
		"bins repeats: delete it from its card. Nothing changed.",
		"a repeating reminder is deleted from its card"
	)
	_eq(
		_read(wed, "delete move", st)["say"],
		"Move is a project: do that from its card. Nothing changed.",
		"a project is deleted from its card"
	)
	_eq(_read(wed, "done move", st)["action"], "say", "and finished from its card")
	var exact := {
		"open":
		[
			{"id": 1, "kind": "todo", "text": "buy milk", "every": null},
			{"id": 2, "kind": "todo", "text": "buy milk and eggs", "every": null}
		]
	}
	_eq(_read(wed, "done buy milk", exact)["id"], 1, "the exact text wins a tie")
	var listing := "Still open: buy milk, send photos, buy bread.\nToday: stretch at 15:00."
	for line in ["what's left", "What is left", "what's left today?", "list", "Today", "LIST?"]:
		_eq(_read(wed, line, st)["say"], listing, "'%s' lists" % line)
	_eq(_read(wed, "list")["say"], "Nothing open right now.", "nothing to list")
	_eq(
		_read(
			wed,
			"today",
			{
				"coming":
				[{"id": 9, "kind": "reminder", "text": "later", "due_at": "2026-11-19T09:00:00Z"}]
			}
		)["say"],
		"Nothing open right now.",
		"a reminder for tomorrow is not today's"
	)
	_eq(
		_read(wed, "to do list for the weekend")["action"],
		"add",
		"a line that only begins like a command is a to-do"
	)


# The routes with the local list behind them, as the soak's stub is behind the server's: it logs
# every request as the stub does and answers an error when the soak asks for one. With `frozen` it
# applies each request to the list for its answer, then puts the list back as it was seeded, so a
# section written against a server that holds still reads the same here.
class Frozen:
	extends "res://backend_local.gd"
	var soak
	var log: Array = []
	var baseline := ""
	var frozen := true

	# no clock of its own: a section written against a server that holds still sees none move
	func _ready() -> void:
		pass

	func freeze() -> void:
		baseline = JSON.stringify(list.doc)

	func fetch(path: String, cb: Callable, timeout: float = 8.0) -> void:
		log.append(["GET", path, ""])
		super(path, cb, timeout)

	func send(path: String, body: Dictionary, cb: Callable, timeout: float = 6.0) -> void:
		log.append(["POST", path, JSON.stringify(body)])
		var edits: bool = path == "/api/home/add" or path.get_slice("/", 4) in ["edit", "plan", "revive", "answer"]
		if edits and soak._mode == "400":
			_deliver.call_deferred(cb, {"code": 400, "body": {"error": "at is more than a year back"}})
		elif (edits and soak._mode == "404") or (path == "/api/home" and soak._fail_jot):
			_deliver.call_deferred(cb, {"code": 404, "body": null})
		else:
			super(path, body, cb, timeout)
			if frozen:
				list.adopt(JSON.parse_string(baseline))


# the soak's status-shaped state as the things of a list
func doc_of(state: Dictionary, bias: float) -> Dictionary:
	var things: Array = []
	var since := "2026-11-18T14:00:00Z"
	var top := 1000
	for key in ["open", "coming", "someday"]:
		for row in state.get(key, []):
			var project: Variant = row.get("project")
			things.append(
				{
					"id": row["id"], "kind": row["kind"], "text": row["text"],
					"state": "someday" if key == "someday" else "open",
					"since": row.get("since", since) if row.get("since") != null else since,
					"due_at": row.get("due_at"), "every": row.get("every"), "every_day": null,
					"told_at": row.get("told_at"), "nudges": 0 if row.get("told_at") == null else 1,
					"project_id": project["id"] if project is Dictionary else null,
					"who": null, "plan": [], "done_at": null, "hidden_until": null,
				}
			)
	for row in state.get("waiting", []):
		things.append(
			{
				"id": row["id"], "kind": "waiting", "text": row["text"], "state": "open",
				"since": since, "who": row.get("who"), "due_at": null, "every": null,
				"told_at": null, "nudges": 0, "project_id": null, "plan": [],
			}
		)
	for row in state.get("projects", []):
		things.append(
			{
				"id": row["id"], "kind": "project", "text": row["text"], "state": "open",
				"since": since, "plan": row.get("plan", []), "due_at": null, "every": null,
				"told_at": null, "nudges": 0, "project_id": null, "who": null,
			}
		)
		if row.get("next") != null:
			things.append(
				{
					"id": row["next"]["id"], "kind": "todo", "text": row["next"]["text"],
					"state": "open", "since": since, "due_at": null, "every": null,
					"told_at": null, "nudges": 0, "project_id": row["id"], "who": null, "plan": [],
				}
			)
		for text in row.get("steps_done", []):
			top += 1
			things.append(
				{
					"id": top, "kind": "todo", "text": text, "state": "done", "since": since,
					"done_at": since, "due_at": null, "every": null, "told_at": null,
					"nudges": 0, "project_id": row["id"], "who": null, "plan": [],
				}
			)
	for text in state.get("notes", []):
		top += 1
		things.append(
			{
				"id": top, "kind": "note", "text": text, "state": "open", "since": since,
				"due_at": null, "every": null, "told_at": null, "nudges": 0, "project_id": null,
				"who": null, "plan": [],
			}
		)
	return {"v": 1, "next_id": 2000, "things": things}


var _frozen: Frozen
var _main


func push_state() -> void:
	_frozen.list.adopt(doc_of(s._state, _main._room.home._bias()))
	_frozen.freeze()


# the forms and the chat, run again with the local list behind the room instead of the server
func over(main) -> void:
	await _frozen_pass(main)
	await _real_pass(main)


func _frozen_pass(main) -> void:
	var FormSoak := preload("res://soak_forms.gd")
	var ChatSoak := preload("res://soak_chat.gd")
	_main = main
	var server_log: Array = s._log
	var server_state: Dictionary = s._state
	t = at(2026, 12, 1, 10)
	_frozen = Frozen.new()
	_frozen.soak = s
	_frozen.setup("", Callable(self, "_clock"), main._room.home._bias(), false)
	main._install(_frozen)
	s.served = false
	s._local = self
	s._log = _frozen.log
	s._state = {
		"open": [
			{"id": 1, "kind": "todo", "text": "buy milk", "due_at": null, "every": null},
			{"id": 2, "kind": "todo", "text": "send photos", "due_at": null, "every": null},
		],
		"coming": [], "notes": ["a note"], "done_week": 0,
		"projects": [
			{"id": 61, "kind": "project", "text": "Move", "plan": ["a", "b"], "steps_done": [],
			"next": {"id": 62, "text": "book the van"}}
		],
	}
	push_state()
	main._poll()
	await s.create_timer(0.5).timeout
	_eq(main._data["open"].size(), 3, "the local list fills the room: two to-dos and a project's step")
	await FormSoak.new(s, main).run()
	await ChatSoak.new(s, main).run()
	await preload("res://soak_sidebar.gd").new(s, main).shelf_local()
	s.served = true
	s._local = null
	s._log = server_log
	s._state = server_state


func _wait(secs: float = 0.4) -> void:
	await s.create_timer(secs).timeout


func _texts(rows: Array) -> Array:
	return rows.map(func(r): return r["text"] if r is Dictionary else r)


# the room over the local list for real: requests change the list, answers come a frame later,
# a reminder coming due rings, the office is not there, and the choice of where applies at once
func _real_pass(main) -> void:
	var h = main._room.home
	t = at(2026, 11, 18, 14)
	var plain := BackendLocal.new()
	plain.setup("", Callable(self, "_clock"), h._bias(), false)
	main._install(plain)
	var said: Array = []
	plain.replied.connect(func(line: String, reply: String) -> void: said.append([line, reply]))
	var told: Array = []
	plain.told.connect(func(row: Dictionary) -> void: told.append(row["id"]))
	var got: Array = []
	plain.send(
		"/api/home/add",
		{"kind": "todo", "text": "buy milk"},
		func(reached: bool, code: int, body: Variant) -> void: got.append([reached, code, body["text"]])
	)
	_eq(got, [], "an answer comes on a later frame, never inside the call")
	await s.process_frame
	await s.process_frame
	_eq(got, [[true, 200, "buy milk"]], "and is the route's answer, reached")
	got = []
	plain.fetch("/api/nowhere", func(reached: bool, code: int, _b: Variant) -> void: got.append([reached, code]))
	plain.send("/api/home/abc/done", {}, func(reached: bool, code: int, _b: Variant) -> void: got.append([reached, code]))
	plain.send("/api/home", {"text": " "}, func(_r: bool, code: int, b: Variant) -> void: got.append([code, b["error"]]))
	await s.process_frame
	await s.process_frame
	_eq(got, [[true, 404], [true, 404], [400, "text is required"]], "unknown routes are 404, a blank line 400")
	var pets: Array = []
	plain.fetch("/api/home/pets", func(_r: bool, code: int, b: Variant) -> void: pets.append([code, b]))
	await s.process_frame
	await s.process_frame
	_eq(pets, [[200, {}]], "the pets' lines: an empty batch, so the house's own are used")
	main._poll()
	await _wait()
	h.reply_text = ""
	main._send_jot("remind me to stretch at 3pm")
	await _wait()
	_eq(h.reply_text, "Reminder set: stretch, today 15:00.", "the notepad's reply is the reader's")
	_eq(said.back(), ["remind me to stretch at 3pm", "Reminder set: stretch, today 15:00."], "the reply is announced for a bot to send")
	var tail: Array = h.chat.messages.slice(-2).map(func(m): return [m["who"], m["text"]])
	_eq(tail, [["me", "remind me to stretch at 3pm"], ["home", "Reminder set: stretch, today 15:00."]], "the chat keeps both")
	_eq(_texts(main._data["coming"]), ["stretch"], "the reminder is coming")
	main._send_jot("what's left")
	await _wait()
	_eq(h.reply_text, "Still open: buy milk.\nToday: stretch at 15:00.", "what's left")
	main._send_jot("done buy milk")
	await _wait()
	_eq([h.reply_text, main._data["open"].size(), main._data["done_week"]], ["Done: buy milk.", 0, 1], "done by a loose line")
	main._write("/api/home/add", {"kind": "todo", "text": "send photos"})
	await _wait()
	var photos: int = main._data["open"][0]["id"]
	main._on_act(photos, "hour")
	await _wait()
	_eq([main._data["open"].size(), _texts(main._data["coming"])], [0, ["stretch", "send photos"]], "in an hour moves it to coming")
	main._on_act(photos, "done")
	await _wait()
	_eq(main._data["coming"].size(), 1, "done on a thing in coming")
	main._write("/api/home/add", {"kind": "todo", "text": "water"})
	main._write("/api/home/add", {"kind": "todo", "text": "mail"})
	await _wait()
	main._what_now()
	await _wait()
	_eq([h.things.pick["text"], h.things.pick["why"]], ["water", "it has sat the longest"], "what now")
	h.things.act("pk_else")
	await _wait()
	_eq(h.things.pick["text"], "mail", "something else skips the first")
	h.things.act("pk_not")
	await _wait()
	main._what_now()
	await _wait()
	_eq(h.things.pick["text"], "water", "not today hides the thing")
	h.card.close()
	# the room says nothing is wrong
	var door: Button = main._sidebar._door
	_eq([main._sidebar._status.visible, h.reply_text.contains("reach")], [false, false], "no word of a server that is not there")
	_eq([door.visible, h.room.office_door], [false, false], "the office door is not offered")
	var at_before: String = main._at
	main._toggle()
	main._enter("office")
	h.acted.emit(0, "office")
	_eq([main._at, at_before], ["home", "home"], "and does not open")
	main._pets_ask()
	main._slow_poll()
	main._watch_door()
	await _wait()
	_eq([main._slow_step, main._watch_busy, h.has_voices()], ["", false, false], "no server asks are made, and the pets use their own lines")
	# a reminder comes due, and again
	h.chat.messages = []
	var tea: int = plain.list.add({"kind": "reminder", "text": "tea", "at": "2026-11-18T15:00"})["body"]["id"]
	t = at(2026, 11, 18, 15)
	told.clear()
	_eq(plain.list.tick(), true, "a reminder due is told")
	plain.changed.emit()
	await _wait()
	var first: Variant = h._rang.get(tea)
	_eq([told.filter(func(i): return i == tea), h.ring_ids.has(tea), h.chat.messages.filter(func(m): return m.get("id") == tea).size()], [[tea], true, 1], "the house rings and the chat tells it")
	t = at(2026, 11, 18, 15, 29)
	plain.list.tick()
	t = at(2026, 11, 18, 15, 30)
	h._rang_new = false
	plain.list.tick()
	plain.changed.emit()
	await _wait()
	_eq([told.filter(func(i): return i == tea).size(), h.chat.messages.filter(func(m): return m.get("id") == tea).size()], [2, 2], "told again after half an hour: a new nudge in the chat")
	_eq([h._rang.get(tea) != first, h._rang.get(tea) == _row_of(main, tea)["told_at"]], [true, true], "and the house rings again: once per told_at")
	main._on_act(tea, "done")
	await _wait()
	_eq(h.ring_ids.has(tea), false, "done stops it")
	await preload("res://soak_sidebar.gd").new(s, main).local_agendas()
	t = at(2026, 11, 18, 14)
	await _where(main)
	await _first_start(main)


func _where(main) -> void:
	var h = main._room.home
	var settings = h.settings
	var f := FileAccess.open(FILE, FileAccess.WRITE)
	var doc := {"v": 1, "next_id": 4, "things": [
		{"id": 1, "kind": "todo", "text": "one", "state": "open", "since": "2026-11-17T10:00:00Z"},
		{"id": 2, "kind": "todo", "text": "two", "state": "open", "since": "2026-11-17T11:00:00Z"},
		{"id": 3, "kind": "note", "text": "a note", "state": "open", "since": "2026-11-17T11:00:00Z"},
	]}
	f.store_string(JSON.stringify(doc))
	f.close()
	var before := FileAccess.get_file_as_string(FILE)
	main._fixture = FILE
	settings.put("where", "local")
	_eq([main._backend.local, h.room.office_door, main._sidebar._door.visible], [true, false, false], "choosing this computer applies at once")
	main._poll()
	await _wait()
	_eq([_texts(main._data["open"]), main._data["notes"]], [["one", "two"], ["a note"]], "the room reads the list file")
	settings.put("where", "server")
	_eq([main._backend.local, main._backend.base, h.room.office_door, main._sidebar._door.visible], [false, settings.server_url(), true, true], "choosing a server applies at once and brings the door back")
	main._poll()
	await _wait()
	_eq(_texts(main._data["open"]).has("one"), false, "and the room reads the server")
	_eq(FileAccess.get_file_as_string(FILE), before, "the list file is not touched by the switch")
	settings.put("where", "local")
	main._poll()
	await _wait()
	_eq(_texts(main._data["open"]), ["one", "two"], "and is there when the house comes back")
	var v = main._sidebar.settings_view
	v.open()
	_eq([v._server_box.visible, v._local_say.visible, v._where_local.button_pressed], [false, true, true], "the settings show this computer")
	_eq(v._local_say.text, "kept in " + ProjectSettings.globalize_path(LocalList.STORE), "and where the file is kept")
	v._where_server.pressed.emit()
	v._refresh()
	_eq([settings.value("where"), v._server_box.visible, v._local_say.visible, v._where_server.button_pressed], ["server", true, false, true], "the choice of a server in the settings")
	v._where_local.pressed.emit()
	v._refresh()
	_eq(settings.value("where"), "local", "and back to this computer")
	v.close()
	# a list that cannot be read: said once, the house starts empty
	f = FileAccess.open(FILE, FileAccess.WRITE)
	f.store_string("{nope")
	f.close()
	h.reply_text = ""
	settings.put("where", "server")
	settings.put("where", "local")
	_eq(h.reply_text, "the list could not be read, so the house starts empty", "an unreadable list is said")
	main._poll()
	await _wait()
	_eq([main._data["open"].size(), FileAccess.file_exists(FILE)], [0, true], "and the house starts empty, the staged run having moved nothing")
	h.reply_text = ""
	main._poll()
	await _wait()
	_eq(h.reply_text, "", "only once")
	_wipe()
	main._fixture = ""
	settings.put("where", "server")


func _first_start(main) -> void:
	var h = main._room.home
	var settings = h.settings
	main._backend.base = "http://127.0.0.1:1"
	main._probing = true
	main._first_start()
	await _wait(0.8)
	_eq([main._backend.local, settings.value("where"), main._probing], [true, "local", false], "no server at the default address: the house keeps its own list")
	main._poll()
	await _wait()
	_eq(_texts(main._data["open"]), ["say hello to the cat"], "a few gentle things to start: a to-do")
	_eq(_texts(main._data["coming"]), ["water the plant"], "a weekly reminder")
	_eq([main._data["coming"][0]["every"], main._data["notes"]], ["week", ["press I to add something, K to chat"]], "and a note")
	settings.put("where", "server")
	main._backend.base = "http://127.0.0.1:%d" % s._srv.get_local_port()
	main._probing = true
	main._first_start()
	await _wait(0.8)
	_eq([main._backend.local, settings.value("where")], [false, "server"], "a server at the default address: the house stays with it")
	settings.put("where", "server")


func _row_of(main, id: int) -> Dictionary:
	for row in main._data["open"]:
		if int(row["id"]) == id:
			return row
	return {}
