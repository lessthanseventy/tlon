extends RefCounted

# Your move: what waits on the person's decision, kept in `path` (`user://house_moves.json`, 0600).
# Pure logic over an injected clock and the house's list, which is the only thing a go may change.
# An item is `{key, kind: ask|proposal|look_at, source, text, why, options | action, date}`; a
# source hands `sweep` the whole of what is true now, and code does the rest: the limits, the
# order, and taking back an item whose cause is gone. Settling runs one of the closed `action`s, or
# keeps an answer as a fact; a settled key is never offered again.
const KINDS := ["ask", "proposal", "look_at"]
const DAILY := 5
const ASKS := 2
const DAY := 86400.0
const LISTED := ["todo", "reminder", "waiting"]
const OPENED := ["http://", "https://", "mailto:"]

var path := ""
var clock := Callable()
var list: RefCounted = null
var doc := {"v": 1, "open": [], "settled": {}, "facts": {}, "day": "", "shown": 0}


func _init(
	the_path: String = "", the_clock: Callable = Callable(), the_list: RefCounted = null
) -> void:
	path = the_path
	clock = the_clock
	list = the_list


func now() -> float:
	return float(int(clock.call()))


func _iso(at: float) -> String:
	return Time.get_datetime_string_from_unix_time(int(at))


func load_file() -> void:
	if path == "" or not FileAccess.file_exists(path):
		return
	var parser := JSON.new()
	var d: Variant = (
		parser.data if parser.parse(FileAccess.get_file_as_string(path)) == OK else null
	)
	if not (d is Dictionary and d.get("open") is Array and d.get("settled") is Dictionary):
		return
	doc.merge(d, true)
	if not doc["facts"] is Dictionary:
		doc["facts"] = {}


func save() -> void:
	if path == "":
		return
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	FileAccess.set_unix_permissions(tmp, FileAccess.UNIX_READ_OWNER | FileAccess.UNIX_WRITE_OWNER)
	f.store_string(JSON.stringify(doc))
	f.close()
	DirAccess.rename_absolute(tmp, path)


func facts() -> Dictionary:
	return doc["facts"]


func settled(key: String) -> Dictionary:
	return doc["settled"].get(key, {})


func _find(key: String) -> Dictionary:
	for m in doc["open"]:
		if m["key"] == key:
			return m
	return {}


func _asks() -> int:
	return doc["open"].filter(func(m): return m["kind"] == "ask").size()


static func _whole(c: Variant) -> bool:
	if not (c is Dictionary and c.get("kind") in KINDS):
		return false
	for k in ["key", "source", "text"]:
		if not (c.get(k) is String and c[k] != ""):
			return false
	if c["kind"] == "ask":
		return c.get("options") is Array and not c["options"].is_empty()
	return c.get("action") is Dictionary


static func _date(m: Dictionary) -> String:
	return str(m.get("date", "")) if str(m.get("date", "")) != "" else "9999"


# asks first, then the soonest date, the oldest within a date
static func _before(a: Dictionary, b: Dictionary) -> bool:
	var ka := [0 if a["kind"] == "ask" else 1, _date(a), str(a.get("at", "")), a["key"]]
	var kb := [0 if b["kind"] == "ask" else 1, _date(b), str(b.get("at", "")), b["key"]]
	return ka < kb


# The open items, in the order they are shown.
func open_items() -> Array:
	var out: Array = doc["open"].duplicate()
	out.sort_custom(_before)
	return out


# `candidates` is everything the sources say is the person's move right now. What is open and no
# longer there is taken back; what is new and not settled is shown, ranked, while the day's five and
# the two open asks last (the rest wait for a later sweep). True when anything changed.
func sweep(candidates: Array) -> bool:
	var live := {}
	var fresh: Array = []
	for c in candidates:
		if not _whole(c):
			continue
		live[c["key"]] = true
		if _find(c["key"]).is_empty() and settled(c["key"]).is_empty():
			fresh.append(c)
	var before: int = doc["open"].size()
	doc["open"] = doc["open"].filter(func(m): return live.has(m["key"]))
	var changed: bool = doc["open"].size() != before
	var today := _iso(now()).substr(0, 10)
	if doc["day"] != today:
		doc["day"] = today
		doc["shown"] = 0
	fresh.sort_custom(_before)
	for c in fresh:
		if int(doc["shown"]) >= DAILY or (c["kind"] == "ask" and _asks() >= ASKS):
			continue
		var m: Dictionary = c.duplicate(true)
		m["at"] = _iso(now())
		doc["open"].append(m)
		doc["shown"] = int(doc["shown"]) + 1
		changed = true
	if changed:
		save()
	return changed


# Settle the open item `key`: "go" runs its action, "no" drops it for good, and for an ask `choice`
# is the number of an option (1-based) or the answer in words, kept as a fact. The answer is
# `{"ok": line}` (with `"open": url` when a link is to be opened) or `{"error": line}`.
func settle(key: String, choice: Variant) -> Dictionary:
	var m := _find(key)
	if m.is_empty():
		return {"error": "that is not waiting on you"}
	if m["kind"] == "ask":
		return _answer(m, choice)
	if choice == "no":
		return _close(m, "no", {"ok": "Dropped: %s." % m["text"]})
	if choice != "go":
		return {"error": "choice is go or no"}
	var done := _run(m["action"])
	if done.has("error"):
		return done
	return _close(m, "go", done)


func _answer(m: Dictionary, choice: Variant) -> Dictionary:
	var said := ""
	if choice is int and choice >= 1 and choice <= m["options"].size():
		said = str(m["options"][choice - 1])
	elif choice is String and choice.strip_edges() != "":
		said = choice.strip_edges()
	else:
		return {"error": "choice is an option's number or an answer"}
	doc["facts"][m["key"]] = said
	return _close(m, "answer", {"ok": "Noted: %s." % said})


func _close(m: Dictionary, how: String, out: Dictionary) -> Dictionary:
	doc["open"] = doc["open"].filter(func(x): return x != m)
	doc["settled"][m["key"]] = {"how": how, "at": _iso(now())}
	save()
	return out


# the closed set of things a go may do
func _run(a: Dictionary) -> Dictionary:
	match a.get("do"):
		"add":
			return _add(a)
		"someday":
			return _listed(list.put_off(int(a.get("id", 0))), "Moved to someday.")
		"day":
			var at := {"kind": "reminder", "at": a.get("at")}
			return _listed(list.edit(int(a.get("id", 0)), at), "Moved.")
		"open":
			return _open(str(a.get("url", "")))
	return {"error": "that is not something a go does"}


func _add(a: Dictionary) -> Dictionary:
	if not a.get("kind") in LISTED:
		return {"error": "a go adds a to-do, a reminder or a waiting-on"}
	var body := {"kind": a["kind"], "text": a.get("text")}
	for k in ["at", "who"]:
		if a.has(k):
			body[k] = a[k]
	return _listed(list.add(body), "Added: %s." % a.get("text", ""))


func _open(url: String) -> Dictionary:
	if not OPENED.any(func(p): return url.begins_with(p)):
		return {"error": "a link opens as http, https or mailto"}
	return {"ok": "Opening it.", "open": url}


func _listed(r: Dictionary, said: String) -> Dictionary:
	if r["code"] != 200:
		return {"error": "the list would not take it"}
	return {"ok": said}
