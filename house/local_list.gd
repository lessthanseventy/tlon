extends RefCounted

# The house's own list: what the tlon server's /api/home routes do, over one Dictionary kept in
# `path` (`{"v": 1, "next_id": N, "things": [...], "agendas": [...]}`). Pure logic: no nodes, and
# the clock is injected (`clock` returns local wall-clock seconds, as the house's `_now_local()`
# does; `bias` is the zone's offset from UTC, which the rows' `due_at` carry as `Z`). Every route
# answers `{"code": int, "body": Variant}`: 400 with `{"error": line}`, 404 with a null body.
signal told(row: Dictionary)
signal told_agenda(text: String)

const People := preload("res://people.gd")
const STORE := "user://house_list.json"
const KINDS := ["todo", "reminder", "note", "waiting", "project"]
const DONE_KEPT := 200
const NUDGES := 6
const QUESTION_CHOICES := [
	"add", "finish", "step", "keep", "later", "drop", "got", "chased", "tomorrow", "no"
]
const MAX_TEXT := 500
const MAX_LIST := 50
const DAY := 86400.0
const WAIT_DAYS := 3
const MAX_NAME := 80
const AGENDA_LEAD := 900.0
const AGENDA_LINGER := 3600.0
const E_AT := "at is ISO 8601: 2026-11-21T09:00 (local) or with a zone, 2026-11-21T09:00:00Z"
const E_RANGE := "at is no more than a year back or 20 years ahead"
const E_EVERY := "every is day, week or month, or a number then one of them: 6 week"
const E_BIRTHDAY := "birthday must be MM-DD or YYYY-MM-DD"
const E_PERSON_RHYTHM := "a person has no every or at"
const E_DOOR := "the door pile cannot be edited or dropped; clear it or drop its notes"

var path := ""
var clock := Callable()
var bias := 0.0
var doc := {"v": 1, "next_id": 1, "things": [], "agendas": []}
var notice := ""
# a list that cannot be read is moved aside only by a house that keeps its list
var keep := true
var fresh := false


func _init(the_path: String = "", the_clock: Callable = Callable(), the_bias: float = 0.0) -> void:
	path = the_path
	clock = the_clock
	bias = the_bias


static func wall(y: int, m: int, d: int, h: int = 0, mi: int = 0) -> float:
	return float(
		Time.get_unix_time_from_datetime_dict(
			{"year": y, "month": m, "day": d, "hour": h, "minute": mi, "second": 0}
		)
	)


static func days_in(y: int, m: int) -> int:
	return [
		31,
		29 if (y % 4 == 0 and y % 100 != 0) or y % 400 == 0 else 28,
		31,
		30,
		31,
		30,
		31,
		31,
		30,
		31,
		30,
		31
	][m - 1]


static func parts(at: float) -> Dictionary:
	return Time.get_datetime_dict_from_unix_time(int(at))


static func midnight(at: float) -> float:
	return floorf(at / DAY) * DAY


# "6 week" -> ["6", "week"]; a bare unit has n 1
static func every_of(value: Variant) -> String:
	if not value is String:
		return ""
	var m := RegEx.create_from_string("^(?:(\\d+)\\s+)?(day|week|month)s?$").search(
		value.strip_edges()
	)
	if m == null:
		return ""
	var n := 1 if m.get_string(1) == "" else int(m.get_string(1))
	if n < 1 or n > 99:
		return ""
	return m.get_string(2) if n == 1 else "%d %s" % [n, m.get_string(2)]


static func say_every(every: String) -> String:
	return every if " " not in every else every + "s"


static func step(at: float, every: String, anchor: int) -> float:
	var p := every.split(" ")
	var n := 1 if p.size() == 1 else int(p[0])
	match p[-1]:
		"day":
			return at + n * DAY
		"week":
			return at + n * 7 * DAY
	var d := parts(at)
	var total: int = int(d["year"]) * 12 + int(d["month"]) - 1 + n
	var y := total / 12
	var m := total % 12 + 1
	var day := mini(anchor if anchor > 0 else int(d["day"]), days_in(y, m))
	return wall(y, m, day) + fposmod(at, DAY)


static func next(at: float, every: String, now: float, anchor: int) -> float:
	var out := at
	for _i in 100000:
		out = step(out, every, anchor)
		if out > now:
			break
	return out


static func latest(at: float, every: String, now: float, anchor: int) -> float:
	var out := at
	for _i in 100000:
		var n := step(out, every, anchor)
		if n > now:
			break
		out = n
	return out


func now() -> float:
	return float(int(clock.call()))


func iso(at: float) -> String:
	return Time.get_datetime_string_from_unix_time(int(at - bias)) + "Z"


func at_of(stamp: Variant) -> float:
	return Time.get_unix_time_from_datetime_string(str(stamp).trim_suffix("Z")) + bias


func things() -> Array:
	return doc["things"]


func load_file() -> void:
	notice = ""
	fresh = false
	if path == "" or not FileAccess.file_exists(path):
		fresh = true
		return
	var parser := JSON.new()
	var d: Variant = parser.data if parser.parse(FileAccess.get_file_as_string(path)) == OK else null
	if not (d is Dictionary and d.get("things") is Array and d["things"].all(_whole)):
		notice = "the list could not be read, so the house starts empty"
		if keep:
			var n := 1
			while FileAccess.file_exists(path.get_basename() + ".broken-%d.json" % n):
				n += 1
			var aside := path.get_basename() + ".broken-%d.json" % n
			DirAccess.rename_absolute(path, aside)
			notice += " (the file was set aside as %s)" % aside.get_file()
		return
	adopt(d)


static func _whole(t: Variant) -> bool:
	return t is Dictionary and t.get("id") != null and t.get("kind") in KINDS and t.get("text") is String


# take a parsed list as it is, its numbers whole
func adopt(d: Dictionary) -> void:
	doc = d
	doc["v"] = 1
	if not doc.get("agendas") is Array:
		doc["agendas"] = []
	for a in doc["agendas"]:
		for k in ["id", "every_day"]:
			if a.get(k) is float:
				a[k] = int(a[k])
	for t in doc["things"]:
		if t.get("since") == null:
			t["since"] = iso(now())
		for k in ["id", "nudges", "every_day", "project_id", "agenda_id"]:
			if t.get(k) is float:
				t[k] = int(t[k])
	doc["next_id"] = maxi(int(doc.get("next_id", 1)), _top() + 1)


func _top() -> int:
	var top := 0
	for t in doc["things"]:
		top = maxi(top, int(t["id"]))
	return top


# the list is written whole beside itself, then renamed over the old one, which stays as .bak
func save() -> void:
	if path == "":
		return
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(doc))
	f.close()
	if FileAccess.file_exists(path):
		DirAccess.copy_absolute(path, path.get_basename() + ".bak.json")
	if DirAccess.rename_absolute(tmp, path) != OK:
		DirAccess.remove_absolute(path)
		DirAccess.rename_absolute(tmp, path)


func starters() -> void:
	var n := now()
	var morning := midnight(n) + DAY + 9 * 3600.0
	_new("todo", "say hello to the cat")
	_new("reminder", "water the plant", {"due_at": iso(morning), "every": "week"})
	_new("note", "press I to add something, K to chat")
	save()


func _new(kind: String, text: String, extra: Dictionary = {}) -> Dictionary:
	var t := {
		"id": int(doc["next_id"]),
		"kind": kind,
		"text": text,
		"state": "open",
		"since": iso(now()),
		"due_at": null,
		"every": null,
		"every_day": null,
		"told_at": null,
		"nudges": 0,
		"project_id": null,
		"who": null,
		"plan": [],
		"done_at": null,
		"hidden_until": null,
	}
	doc["next_id"] = int(doc["next_id"]) + 1
	t.merge(extra, true)
	doc["things"].append(t)
	return t


func _find(id: int, states: Array = ["open", "someday"]) -> Dictionary:
	for t in doc["things"]:
		if int(t["id"]) == id and t.get("state", "open") in states:
			return t
	return {}


func _state(t: Dictionary) -> String:
	return str(t.get("state", "open"))


func _ok(body: Variant) -> Dictionary:
	return {"code": 200, "body": body}


func _bad(line: String) -> Dictionary:
	return {"code": 400, "body": {"error": line}}


func _gone() -> Dictionary:
	return {"code": 404, "body": {"error": "no such route"}}


static func _err(v: Variant) -> bool:
	return v is Dictionary and v.has("error")


static func _line(line: String) -> Dictionary:
	return {"error": line}


func _row(t: Dictionary) -> Dictionary:
	match str(t["kind"]):
		"project":
			return _project_row(t)
		"waiting":
			var w := _plain_row(t)
			w["who"] = t.get("who")
			w["due_at"] = iso(at_of(t["since"]) + WAIT_DAYS * DAY)
			return w
	return _plain_row(t)


func _plain_row(t: Dictionary) -> Dictionary:
	var parent := {}
	if t.get("project_id") != null:
		parent = _find(int(t["project_id"]), ["open"])
	var row := {
		"id": int(t["id"]),
		"kind": t["kind"],
		"text": t["text"],
		"due_at": t.get("due_at"),
		"every": t.get("every"),
		"since": t.get("since"),
		"told_at": t.get("told_at"),
		"project": null if parent.is_empty() else {"id": int(parent["id"]), "text": parent["text"]},
	}
	if t.get("list") != null:
		row["list"] = t["list"]
	return row


func _steps(project_id: int, states: Array = ["open"]) -> Array:
	return things().filter(
		func(t):
			return (
				t.get("project_id") != null
				and int(t["project_id"]) == project_id
				and _state(t) in states
			)
	)


func _project_row(t: Dictionary) -> Dictionary:
	var open := _steps(int(t["id"]))
	var finished := _steps(int(t["id"]), ["done"])
	return {
		"id": int(t["id"]),
		"kind": "project",
		"text": t["text"],
		"since": t.get("since"),
		"next": null if open.is_empty() else {"id": int(open[0]["id"]), "text": open[0]["text"]},
		"done": finished.size(),
		"plan": t.get("plan", []),
		"steps_done": finished.map(func(s): return s["text"]),
	}


func status() -> Dictionary:
	var n := now()
	var out := {
		"open": [],
		"coming": [],
		"waiting": [],
		"someday": [],
		"projects": [],
		"notes": [],
		"note_rows": [],
		"done": [],
		"done_week": 0,
		"agendas": _piles("agenda").map(_agenda_row),
		"people": _people(),
		"door": _door_row(),
		"proposals": [],
	}
	for t in things():
		var s := _state(t)
		if s == "someday" and str(t["kind"]) in ["todo", "reminder"]:
			out["someday"].append(_row(t))
		elif s == "done" and t.get("agenda_id") == null and at_of(t["done_at"]) > n - 7 * DAY:
			out["done"].append({"text": t["text"], "done_at": t["done_at"]})
		elif s == "open":
			match str(t["kind"]):
				"todo":
					out["open"].append(_row(t))
				"reminder":
					(
						out[
							"coming"
							if t.get("due_at") != null and at_of(t["due_at"]) > n
							else "open"
						]
						. append(_row(t))
					)
				"waiting":
					out["waiting"].append(_row(t))
				"project":
					out["projects"].append(_row(t))
				"note" when t.get("agenda_id") == null:
					out["note_rows"].append({"id": int(t["id"]), "text": t["text"]})
	out["coming"].sort_custom(func(a, b): return [str(a["due_at"]), a["id"]] < [str(b["due_at"]), b["id"]])
	out["note_rows"].reverse()
	out["note_rows"] = out["note_rows"].slice(0, 20)
	out["notes"] = out["note_rows"].map(func(r): return r["text"])
	out["done"].sort_custom(func(a, b): return str(a["done_at"]) > str(b["done_at"]))
	out["done_week"] = out["done"].size()
	return out


func _text(v: Variant) -> Variant:
	if v is String and v.strip_edges() != "":
		return v.strip_edges().substr(0, MAX_TEXT)
	return _line("text is required")


func _texts(v: Variant) -> Variant:
	if v is Array and v.size() <= MAX_LIST and v.all(func(x): return x is String):
		return (
			v
			. map(func(x): return x.strip_edges().substr(0, MAX_TEXT))
			. filter(func(x): return x != "")
		)
	return null


func _shift_years(at: float, years: int) -> float:
	var d := parts(at)
	var y: int = int(d["year"]) + years
	return wall(
		y,
		int(d["month"]),
		mini(int(d["day"]), days_in(y, int(d["month"]))),
		int(d["hour"]),
		int(d["minute"])
	)


# `at`: local wall time without a zone, or with one; a wall-clock float, or an error
func _when(at: Variant) -> Variant:
	if not at is String:
		return _line(E_AT)
	var m := (
		RegEx
		. create_from_string(
			"^(\\d{4})-(\\d{2})-(\\d{2})T(\\d{2}):(\\d{2})(?::(\\d{2}))?(Z|[+-]\\d{2}:\\d{2})?$"
		)
		. search(at)
	)
	if m == null:
		return _line(E_AT)
	var y := int(m.get_string(1))
	var mo := int(m.get_string(2))
	var d := int(m.get_string(3))
	var h := int(m.get_string(4))
	var mi := int(m.get_string(5))
	if mo < 1 or mo > 12 or d < 1 or d > days_in(y, mo) or h > 23 or mi > 59:
		return _line(E_AT)
	var out := wall(y, mo, d, h, mi)
	var zone := m.get_string(7)
	if zone == "Z":
		out += bias
	elif zone != "":
		var off := (
			(int(zone.substr(1, 2)) * 3600 + int(zone.substr(4, 2)) * 60)
			* (1 if zone[0] == "+" else -1)
		)
		out += bias - off
	var n := now()
	if out < _shift_years(n, -1) or out > _shift_years(n, 20):
		return _line(E_RANGE)
	return out


func _anchor(every: Variant, due: Variant) -> Variant:
	if every is String and every.ends_with("month") and due != null:
		return int(parts(at_of(due))["day"])
	return null


func add(body: Dictionary) -> Dictionary:
	var kind: Variant = body.get("kind")
	if not (kind is String and kind in KINDS):
		return _bad("kind is todo, reminder, note, waiting or project")
	var text: Variant = _text(body.get("text"))
	var due: Variant = null
	var every := ""
	if not _err(text):
		if body.get("at") == null:
			if kind == "reminder":
				text = _line("a reminder needs at")
		elif kind != "reminder":
			text = _line("at is for a reminder")
		else:
			due = _when(body["at"])
			if _err(due):
				text = due
	if not _err(text) and body.get("every") != null:
		if kind != "reminder":
			text = _line("every is for a reminder")
		else:
			every = every_of(body["every"])
			if every == "":
				text = _line(E_EVERY)
	var listed: Variant = null
	if not _err(text) and body.get("list") != null:
		if kind not in ["todo", "reminder"] or body.get("project") != null:
			text = _line("list is for a to-do or reminder")
		else:
			listed = _list_name(body["list"])
			if _err(listed):
				text = listed
	if _err(text):
		return _bad(text["error"])
	match kind:
		"waiting":
			var who: Variant = body.get("who")
			if not (who is String and who.strip_edges() != ""):
				return _bad("who is required for a waiting-on")
			return _ok(_row(_new("waiting", text, {"who": who.strip_edges()})))
		"project":
			var steps: Variant = _texts(body.get("steps"))
			if steps == null or steps.is_empty():
				return _bad("steps is a list of texts, at least one")
			var project := _new("project", text, {"plan": steps.slice(1)})
			_new("todo", steps[0], {"project_id": int(project["id"])})
			save()
			return _ok(_row(project))
		"todo":
			var pid: Variant = body.get("project")
			if pid != null:
				if not ((pid is int) or (pid is float and pid == floorf(pid))):
					return _bad("project is a project's id")
				return _step(int(pid), text)
		"reminder":
			var out := _new("reminder", text, {"list": listed})
			var at := float(due)
			var anchor: Variant = _anchor(every, iso(at)) if every != "" else null
			if every != "" and at <= now():
				at = next(at, every, now(), int(anchor) if anchor != null else 0)
			out.merge(
				{"due_at": iso(at), "every": null if every == "" else every, "every_day": anchor},
				true
			)
			save()
			return _ok(_row(out))
	if body.get("project") != null:
		return _bad("project is for a to-do")
	var made := _new(kind, text, {"list": listed})
	save()
	return _ok(_row(made))


# the name a person gave a list: trimmed, null when empty, and spelled as the list already
# there is when one matches ignoring case
func _list_name(v: Variant) -> Variant:
	if not v is String:
		return _line("list is a name")
	var name: String = v.strip_edges().substr(0, MAX_NAME)
	if name == "":
		return null
	for t in doc["things"]:
		if t.get("list") != null and str(t["list"]).to_lower() == name.to_lower():
			return t["list"]
	return name


func _step(project_id: int, text: String) -> Dictionary:
	var project := _find(project_id, ["open"])
	if project.is_empty() or str(project["kind"]) != "project":
		return _gone()
	if _steps(project_id).is_empty():
		var s := _new("todo", text, {"project_id": project_id})
		save()
		return _ok(_row(s))
	project["plan"] = project.get("plan", []) + [text]
	save()
	return _ok(_row(project))


func edit(id: int, body: Dictionary) -> Dictionary:
	var t := _find(id)
	if t.is_empty():
		return _gone()
	var current := str(t["kind"])
	var kind := ""
	if body.has("kind"):
		if not (body["kind"] in ["todo", "reminder"] and current in ["todo", "reminder"]):
			return _bad("kind is only todo or reminder")
		kind = body["kind"]
	var text: Variant = null
	if body.has("text"):
		text = _text(body["text"])
		if _err(text):
			return _bad(text["error"])
	var at: Variant = null
	if body.get("at") != null:
		at = _when(body["at"])
		if _err(at):
			return _bad(at["error"])
	var every: Variant = null
	var stop := body.has("every") and body["every"] == null
	if body.get("every") != null:
		every = every_of(body["every"])
		if every == "":
			return _bad(E_EVERY)
	var final := current if kind == "" else kind
	if final != "reminder" and (at != null or every != null):
		if final == "todo":
			return _bad(
				(
					"a to-do has no time: send kind reminder with at"
					if current == "todo"
					else "a to-do has no time and no repeat"
				)
			)
		return _bad("at is for a reminder")
	if final == "reminder" and at == null:
		if current == "todo" or (t.get("due_at") == null and every != null):
			return _bad("a reminder needs at")
	var listed: Variant = null
	if body.has("list"):
		if current not in ["todo", "reminder"]:
			return _bad("list is for a to-do or reminder")
		listed = _list_name(body["list"])
		if _err(listed):
			return _bad(listed["error"])
	var to_todo := final == "todo" and current == "reminder"
	var changes := {}
	if body.has("list"):
		changes["list"] = listed
	if text != null:
		changes["text"] = text
	if final != current:
		changes["kind"] = final
	if to_todo:
		changes["due_at"] = null
		changes["every"] = null
	else:
		if at != null:
			changes["due_at"] = iso(float(at))
		if every != null:
			changes["every"] = every
		elif stop:
			changes["every"] = null
	var due: Variant = changes.get("due_at", t.get("due_at"))
	var rep: Variant = changes["every"] if changes.has("every") else t.get("every")
	var moved := changes.has("due_at") or changes.has("kind")
	var wanted := changes.has("due_at") or changes.has("every")
	var back := wanted and _state(t) == "someday"
	var anchor: Variant = _anchor(rep, due) if wanted else t.get("every_day")
	if (moved or back) and rep != null and due != null and at_of(due) <= now():
		changes["due_at"] = iso(next(at_of(due), rep, now(), int(anchor if anchor != null else 0)))
	for k in changes:
		t[k] = changes[k]
	t["every_day"] = anchor
	if to_todo:
		t["every_day"] = null
	if moved:
		t["told_at"] = null
		t["nudges"] = 0
	if back:
		t["state"] = "open"
	save()
	return _ok(_row(t))


func plan(id: int, body: Dictionary) -> Dictionary:
	var p := _find(id, ["open"])
	if p.is_empty() or str(p["kind"]) != "project":
		return _gone()
	var texts: Variant = _texts(body.get("plan"))
	if texts == null:
		return _bad("plan is a list of texts")
	p["plan"] = texts
	save()
	return _ok(_row(p))


func revive(id: int) -> Dictionary:
	var t := _find(id, ["someday"])
	if t.is_empty():
		return _gone()
	t["state"] = "open"
	t["told_at"] = null
	t["nudges"] = 0
	if t["kind"] == "reminder" and t.get("due_at") == null:
		t["kind"] = "todo"
		t["every"] = null
		t["every_day"] = null
	elif t.get("every") != null and t.get("due_at") != null and at_of(t["due_at"]) <= now():
		var anchor := int(t["every_day"]) if t.get("every_day") != null else 0
		t["due_at"] = iso(next(at_of(t["due_at"]), t["every"], now(), anchor))
	save()
	return _ok(_row(t))


func done(id: int) -> Dictionary:
	var t := _find(id, ["open"])
	if t.is_empty() or not str(t["kind"]) in ["todo", "reminder"]:
		return _gone()
	var n := now()
	if t.get("every") != null and t.get("due_at") != null:
		var anchor := int(t["every_day"]) if t.get("every_day") != null else 0
		t["due_at"] = iso(next(at_of(t["due_at"]), t["every"], n, anchor))
		t["told_at"] = null
		t["nudges"] = 0
		save()
		return _ok({"id": id, "text": t["text"], "done_at": iso(n), "due_at": t["due_at"]})
	t["state"] = "done"
	t["done_at"] = iso(n)
	t["told_at"] = null
	_advance(t)
	_forget_old_done()
	save()
	return _ok({"id": id, "text": t["text"], "done_at": t["done_at"], "due_at": t.get("due_at")})


func _close_project(id: int) -> void:
	doc["things"] = things().filter(
		func(t):
			return not (
				t.get("project_id") != null
				and int(t["project_id"]) == id
				and _state(t) in ["open", "someday"]
			)
	)


# a project left with no open step gets the next of its plan
func _advance(t: Dictionary) -> void:
	if t.get("project_id") == null:
		return
	var p := _find(int(t["project_id"]), ["open"])
	if p.is_empty() or not _steps(int(p["id"])).is_empty() or p.get("plan", []).is_empty():
		return
	var plan: Array = p["plan"]
	_new("todo", plan.pop_front(), {"project_id": int(p["id"])})
	p["plan"] = plan


func _forget_old_done() -> void:
	var finished := things().filter(func(t): return _state(t) == "done")
	if finished.size() <= DONE_KEPT:
		return
	finished.sort_custom(
		func(a, b): return [str(a["done_at"]), int(a["id"])] < [str(b["done_at"]), int(b["id"])]
	)
	var gone := finished.slice(0, finished.size() - DONE_KEPT)
	doc["things"] = things().filter(func(t): return not gone.has(t))


func drop(id: int) -> Dictionary:
	var t := _find(id)
	if t.is_empty():
		return _gone()
	if str(t["kind"]) == "project":
		_close_project(id)
	doc["things"] = things().filter(func(x): return x != t)
	_advance(t)
	save()
	return _ok({"id": id, "text": t["text"], "dropped_at": iso(now()), "due_at": t.get("due_at")})


func later(id: int, body: Dictionary) -> Dictionary:
	var until: Variant = body.get("until")
	var t := _find(id)
	if not until in ["hour", "tomorrow"] or t.is_empty() or not str(t["kind"]) in ["todo", "reminder"]:
		return _gone()
	var n := now()
	t["kind"] = "reminder"
	t["state"] = "open"
	t["due_at"] = iso(n + 3600.0 if until == "hour" else midnight(n) + DAY + 9 * 3600.0)
	t["told_at"] = null
	t["nudges"] = 0
	save()
	return _ok({"id": id, "text": t["text"], "due_at": t["due_at"]})


func answer(id: int, body: Dictionary) -> Dictionary:
	var t := _find(id, ["open"])
	if t.is_empty():
		return _gone()
	var choice := str(body.get("choice", ""))
	if choice == "":
		return _bad("choice is required")
	if choice in QUESTION_CHOICES:
		return _gone()
	if choice != "nottoday":
		return _bad("choice is nottoday")
	t["hidden_until"] = iso(midnight(now()) + DAY + 6 * 3600.0)
	save()
	return _ok({"reply": "Not today: %s." % t["text"]})


# the open to-do or reminder to do now: overdue reminders (the most overdue first), then the to-do
# that has sat longest, then a project's open step
func pick(skip: Array = []) -> Dictionary:
	var n := now()
	var live := things().filter(
		func(t):
			return (
				_state(t) == "open"
				and str(t["kind"]) in ["todo", "reminder"]
				and not skip.has(int(t["id"]))
				and (t.get("hidden_until") == null or at_of(t["hidden_until"]) <= n)
				and not (
					t["kind"] == "reminder" and t.get("due_at") != null and at_of(t["due_at"]) > n
				)
			)
	)
	var overdue := live.filter(func(t): return t["kind"] == "reminder" and t.get("due_at") != null)
	var plain := live.filter(func(t): return t.get("project_id") == null and not overdue.has(t))
	var steps := live.filter(func(t): return t.get("project_id") != null and not overdue.has(t))
	overdue.sort_custom(func(a, b): return [str(a["due_at"]), a["id"]] < [str(b["due_at"]), b["id"]])
	plain.sort_custom(func(a, b): return [str(a["since"]), a["id"]] < [str(b["since"]), b["id"]])
	var chosen: Dictionary = {}
	var why := ""
	if not overdue.is_empty():
		chosen = overdue[0]
		why = _why_due(at_of(chosen["due_at"]), n)
	elif not plain.is_empty():
		chosen = plain[0]
		why = "it has sat the longest"
	elif not steps.is_empty():
		chosen = steps[0]
		var parent := _find(int(chosen["project_id"]), ["open"])
		why = "it is the next step of %s" % parent.get("text", "a project")
	if chosen.is_empty():
		return _ok({"pick": null, "say": "Nothing open right now. That's a good place to be."})
	var row := _row(chosen)
	row["why"] = why
	var label := str(chosen["text"])
	if row["project"] != null:
		label = "%s: %s" % [row["project"]["text"], label]
	return _ok({"pick": row, "say": "%s — %s" % [label, why]})


func _why_due(due: float, n: float) -> String:
	var days := int((midnight(n) - midnight(due)) / DAY)
	if days <= 0:
		return (
			"it was due this morning"
			if fposmod(due, DAY) < 12 * 3600.0
			else "it was due earlier today"
		)
	return "it was due yesterday" if days == 1 else "it was due %d days ago" % days


# once a second: due reminders are told, and a told one not acted on is told again after 30 min,
# doubling to 4 h, six times in all, never between 22:00 and 08:00. Whether anything changed.
func tick() -> bool:
	var n := now()
	var changed := false
	for t in things():
		if _state(t) != "open" or str(t["kind"]) != "reminder" or t.get("due_at") == null:
			continue
		var due := at_of(t["due_at"])
		if due > n:
			continue
		if t.get("every") != null:
			var anchor := int(t["every_day"]) if t.get("every_day") != null else 0
			var latest_due := latest(due, t["every"], n, anchor)
			if latest_due != due:
				t["due_at"] = iso(latest_due)
				t["told_at"] = null
				t["nudges"] = 0
				changed = true
		var count := int(t.get("nudges", 0))
		var turn := t.get("told_at") == null
		if not turn and count < NUDGES:
			var waited := (n - at_of(t["told_at"])) / 60.0
			turn = (
				waited >= minf(30.0 * pow(2.0, count - 1), 240.0)
				and int(parts(n)["hour"]) in range(8, 22)
			)
		if turn:
			t["told_at"] = iso(n)
			t["nudges"] = count + 1
			changed = true
			told.emit(_row(t))
	changed = _tick_agendas(n) or changed
	if changed:
		save()
	return changed


# an agenda: a named standing pile of notes (things of kind note with its `agenda_id`) with an
# optional rhythm. Told once AGENDA_LEAD ahead of its time; the time moves on AGENDA_LINGER after it.
func _agenda(id: int) -> Dictionary:
	for a in doc["agendas"]:
		if int(a["id"]) == id:
			return a
	return {}


func _kind(a: Dictionary) -> String:
	return str(a.get("kind", "agenda"))


func _piles(kind: String) -> Array:
	return doc["agendas"].filter(func(a: Dictionary) -> bool: return _kind(a) == kind)


func _named(name: String, kind: String = "agenda") -> Dictionary:
	for a in _piles(kind):
		if str(a["name"]).to_lower() == name.to_lower():
			return a
	return {}


func _pile(a: Dictionary, states: Array = ["open"]) -> Array:
	return things().filter(
		func(t):
			return (
				t.get("agenda_id") != null
				and int(t["agenda_id"]) == int(a["id"])
				and _state(t) in states
			)
	)


func _agenda_row(a: Dictionary) -> Dictionary:
	return {
		"id": int(a["id"]),
		"name": a["name"],
		"every": a.get("every"),
		"next_at": a.get("next_at"),
		"notes":
		_pile(a).map(func(t): return {"id": int(t["id"]), "text": t["text"], "since": t.get("since")}),
	}


static func _agenda_name(v: Variant) -> String:
	return v.strip_edges().substr(0, MAX_NAME) if v is String else ""


# the rhythm `body` gives an agenda that has `a`'s: `every` and `at`, either null to clear it
func _timing(body: Dictionary, a: Dictionary) -> Dictionary:
	var every: Variant = a.get("every")
	var at: Variant = a.get("next_at")
	var given := false
	if body.has("every"):
		given = true
		every = null
		if body["every"] != null:
			every = every_of(body["every"])
			if every == "":
				return _line(E_EVERY)
	if body.has("at"):
		given = true
		at = null
		if body["at"] != null:
			var when: Variant = _when(body["at"])
			if _err(when):
				return when
			at = iso(float(when))
	var anchor: Variant = _anchor(every, at) if given else a.get("every_day")
	if every != null and at != null and at_of(at) <= now():
		at = iso(next(at_of(at), every, now(), int(anchor) if anchor != null else 0))
	return {"every": every, "every_day": anchor, "next_at": at}


# what a person's body changes: a birthday (null clears it); a rhythm means nothing to a person
func _person_fields(body: Dictionary) -> Dictionary:
	if body.has("every") or body.has("at"):
		return _line(E_PERSON_RHYTHM)
	if not body.has("birthday"):
		return {}
	var birthday: Variant = body["birthday"]
	if birthday == null:
		return {"birthday": null}
	if not (birthday is String and People.valid((birthday as String).strip_edges())):
		return _line(E_BIRTHDAY)
	return {"birthday": (birthday as String).strip_edges()}


func _person_row(a: Dictionary) -> Dictionary:
	var birthday: Variant = a.get("birthday")
	var next := People.next_birthday(birthday, Time.get_date_string_from_unix_time(int(now())))
	return {
		"id": int(a["id"]),
		"name": a["name"],
		"birthday": birthday,
		"next_birthday": next if next != "" else null,
		"notes": _agenda_row(a)["notes"],
		"todos": _todos(str(a["name"])),
	}


# the open to-dos, reminders and waiting-ons that name `name` as a whole word in the text or who
func _todos(name: String) -> Array:
	var out: Array = []
	for t in things():
		if _state(t) != "open" or str(t["kind"]) not in ["todo", "reminder", "waiting"]:
			continue
		if People.names(str(t["text"]), name) or People.names(str(t.get("who", "")), name):
			out.append(_row(t))
	return out


# the people, the soonest birthday first and those with none last, by name
func _people() -> Array:
	var rows := _piles("person").map(_person_row)
	rows.sort_custom(
		func(x: Dictionary, y: Dictionary) -> bool:
			return (
				[x["next_birthday"] == null, str(x["next_birthday"]), str(x["name"])]
				< [y["next_birthday"] == null, str(y["next_birthday"]), str(y["name"])]
			)
	)
	return rows


func _door_row() -> Dictionary:
	var door := _piles("door")
	if door.is_empty():
		return {"id": null, "notes": []}
	return {"id": int(door[0]["id"]), "notes": _agenda_row(door[0])["notes"]}


func agenda_add(body: Dictionary) -> Dictionary:
	var kind: Variant = body.get("kind", "agenda")
	if kind not in ["agenda", "person"]:
		return _bad("kind is agenda or person")
	var name := _agenda_name(body.get("name"))
	if name == "":
		return _bad("name is required")
	var timing := _person_fields(body) if kind == "person" else _timing(body, {})
	if _err(timing):
		return _bad(timing["error"])
	if not _named(name, kind).is_empty():
		return _bad(
			"there is already %s called %s" % ["a person" if kind == "person" else "an agenda", name]
		)
	var a := {"id": int(doc["next_id"]), "name": name, "told_for": null}
	if kind == "person":
		a["kind"] = "person"
	doc["next_id"] = int(doc["next_id"]) + 1
	a.merge(timing, true)
	doc["agendas"].append(a)
	save()
	return _ok(_person_row(a) if kind == "person" else _agenda_row(a))


# a person's name and birthday
func _person_edit(a: Dictionary, body: Dictionary) -> Dictionary:
	var fields := _person_fields(body)
	if _err(fields):
		return _bad(fields["error"])
	var name := str(a["name"])
	if body.has("name"):
		name = _agenda_name(body["name"])
		if name == "":
			return _bad("name is required")
		var other := _named(name, "person")
		if not other.is_empty() and int(other["id"]) != int(a["id"]):
			return _bad("there is already a person called %s" % name)
	a["name"] = name
	a.merge(fields, true)
	save()
	return _ok(_person_row(a))


func agenda_edit(id: int, body: Dictionary) -> Dictionary:
	var a := _agenda(id)
	if a.is_empty():
		return _gone()
	if _kind(a) == "door":
		return _bad(E_DOOR)
	if _kind(a) == "person":
		return _person_edit(a, body)
	var timing := _timing(body, a)
	if _err(timing):
		return _bad(timing["error"])
	if body.has("name"):
		var name := _agenda_name(body["name"])
		if name == "":
			return _bad("name is required")
		var other := _named(name)
		if not other.is_empty() and int(other["id"]) != id:
			return _bad("there is already an agenda called %s" % name)
		a["name"] = name
	a.merge(timing, true)
	save()
	return _ok(_agenda_row(a))


func agenda_note(id: int, body: Dictionary) -> Dictionary:
	var a := _agenda(id)
	if a.is_empty():
		return _gone()
	var text: Variant = _text(body.get("text"))
	if _err(text):
		return _bad(text["error"])
	var t := _new("note", text, {"agenda_id": id})
	save()
	return _ok(_plain_row(t))


# the note put by the door, which the first one makes the pile for
func door_add(body: Dictionary) -> Dictionary:
	var text: Variant = _text(body.get("text"))
	if _err(text):
		return _bad(text["error"])
	var door := _piles("door")
	if door.is_empty():
		door = [{"id": int(doc["next_id"]), "name": "by the door", "kind": "door", "told_for": null}]
		doc["next_id"] = int(doc["next_id"]) + 1
		doc["agendas"].append(door[0])
	return agenda_note(int(door[0]["id"]), body)


# the notes are kept, done, and the agenda stands empty
func agenda_clear(id: int) -> Dictionary:
	var a := _agenda(id)
	if a.is_empty():
		return _gone()
	for t in _pile(a):
		t["state"] = "done"
		t["done_at"] = iso(now())
	save()
	return _ok(_person_row(a) if _kind(a) == "person" else _agenda_row(a))


func agenda_drop(id: int) -> Dictionary:
	var a := _agenda(id)
	if a.is_empty():
		return _gone()
	if _kind(a) == "door":
		return _bad(E_DOOR)
	doc["things"] = things().filter(
		func(t): return not (t.get("agenda_id") != null and int(t["agenda_id"]) == id)
	)
	doc["agendas"] = doc["agendas"].filter(func(x): return x != a)
	save()
	return _ok({"id": id, "name": a["name"]})


func _agenda_told(a: Dictionary, pile: Array) -> String:
	var name := str(a["name"])
	return (
		"%s in 15 — %d thing%s: %s"
		% [
			name.substr(0, 1).to_upper() + name.substr(1),
			pile.size(),
			"" if pile.size() == 1 else "s",
			"; ".join(pile.map(func(t): return str(t["text"]))),
		]
	)


# once a second as well: an agenda's pile is told once as its time comes within the lead, and its
# time moves on by the rhythm (a one-off time is dropped) after the linger
func _tick_agendas(n: float) -> bool:
	var changed := false
	for a in doc["agendas"]:
		var upcoming: Variant = a.get("next_at")
		if upcoming == null:
			continue
		var due := at_of(upcoming)
		if due > n and due - n <= AGENDA_LEAD and a.get("told_for") != upcoming:
			a["told_for"] = upcoming
			changed = true
			var pile := _pile(a)
			if not pile.is_empty():
				told_agenda.emit(_agenda_told(a, pile))
		elif due <= n - AGENDA_LINGER:
			var anchor := int(a["every_day"]) if a.get("every_day") != null else 0
			a["next_at"] = iso(next(due, a["every"], n, anchor)) if a.get("every") != null else null
			changed = true
	return changed
