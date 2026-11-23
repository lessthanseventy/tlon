extends RefCounted

# Reads a loose line with rules, no model: the seam `read(text, context) -> reading` that a later
# reader (a model) can stand in front of, keeping this as the fallback. Pure: the clock is in the
# context.
#
# context: {now: local wall-clock seconds, bias: seconds east of UTC (for rows' Z times),
#           status: the list's status()}
# reading: {action: "add"|"done"|"delete"|"say", say: the reply, and by action
#           body (add: what POST /api/home/add takes) | id (done, delete)}
const LocalList := preload("res://local_list.gd")
const DAYS := ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
const DAY_ABBR := ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
const MONTHS := ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
const MONTH_ABBR := [
	"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
]
const STOP := ["a", "an", "the", "to", "my", "of", "and", "me"]
const RESERVED := [
	"note", "done", "did", "finished", "delete", "forget", "remind me", "waiting on", "list", "today",
]
const MORNING := 9
const TONIGHT := 19
const DAY_RX := "(sunday|monday|tuesday|wednesday|thursday|friday|saturday)"
const MON_RX := "(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*"


func read(text: String, context: Dictionary) -> Dictionary:
	var line := text.strip_edges()
	if _m("^(?:what(?:'s|s| is) left(?: today)?|list|today)\\s*[?.!]*$", line) != null:
		return _say(_list(context))
	var m := _m("^note(?:\\s*:\\s*|\\s+)(.+)$", line)
	if m != null:
		return _add(
			"note", m.get_string(1).strip_edges(), {}, "Noted: %s." % m.get_string(1).strip_edges()
		)
	m = _m("^waiting on (.+?) for (.+)$", line)
	if m == null:
		m = _m("^(.+?) owes me (.+)$", line)
	if m != null:
		var who := m.get_string(1).strip_edges()
		var what := m.get_string(2).strip_edges()
		return _add(
			"waiting",
			what,
			{"who": who},
			"Waiting on %s for %s. I'll ask in %d days." % [who, what, LocalList.WAIT_DAYS]
		)
	m = _m("^(?:done|did|finished)(?:\\s*:\\s*|\\s+)(.+)$", line)
	if m != null:
		return _find(m.get_string(1), context, "done")
	m = _m("^(?:delete|forget)(?:\\s*:\\s*|\\s+)(.+)$", line)
	if m != null:
		return _find(m.get_string(1), context, "delete")
	m = _m("^for\\s+([^:]{1,40}?)\\s*(?:(?<!\\d):|:(?!\\d))\\s*(.+)$", line)
	if m == null:
		m = _m("^([\\p{L}\\p{N}']+(?:\\s[\\p{L}\\p{N}']+)?)\\s*:\\s+(.+)$", line)
		if m != null and RESERVED.has(m.get_string(1).to_lower()):
			m = null
	if m != null:
		return _listed(m.get_string(1).strip_edges(), m.get_string(2), context)
	return _timed(line, context)


static func _m(pattern: String, line: String) -> RegExMatch:
	return RegEx.create_from_string("(?i)" + pattern).search(line)


static func _say(line: String) -> Dictionary:
	return {"action": "say", "say": line}


static func _add(kind: String, text: String, extra: Dictionary, say: String) -> Dictionary:
	var body := {"kind": kind, "text": text}
	body.merge(extra, true)
	return {"action": "add", "body": body, "say": say}


# cut the first match of `pattern` out of `box.s`; the match, or null
static func _cut(box: Dictionary, pattern: String) -> RegExMatch:
	var m := _m(pattern, box["s"])
	if m != null:
		_excise(box, m)
	return m


static func _excise(box: Dictionary, m: RegExMatch) -> void:
	box["s"] = box["s"].substr(0, m.get_start()) + " " + box["s"].substr(m.get_end())


# "for school: read chapter 4", "school: read chapter 4": the rest read as any line, in that list
func _listed(name: String, rest: String, context: Dictionary) -> Dictionary:
	var reading := read(rest, context)
	if reading["action"] != "add" or reading["body"]["kind"] not in ["todo", "reminder"]:
		return reading
	var body: Dictionary = reading["body"]
	if body.has("list"):
		return reading
	body["list"] = name
	reading["say"] = "%s (list: %s)" % [str(reading["say"]).trim_suffix("."), name]
	return reading


func _timed(line: String, context: Dictionary) -> Dictionary:
	var now: float = context["now"]
	var box := {"s": line}
	var lead := _m("^remind me(?:\\s+(?:to|about|that))?\\s*,?\\s*", line)
	if lead != null:
		box["s"] = line.substr(lead.get_end())
	var every := ""
	var weekday := -1
	var date := -1.0
	var tonight := false
	var exact := -1.0
	var hour := -1
	var minute := 0
	var found := false
	var m := _cut(box, "\\bevery\\s+(\\d+)\\s+(day|week|month)s?\\b")
	if m != null and int(m.get_string(1)) in range(1, 100):
		every = LocalList.every_of("%s %s" % [m.get_string(1), m.get_string(2).to_lower()])
	elif m == null:
		m = _cut(box, "\\bevery\\s+other\\s+(day|week|month)\\b")
		if m != null:
			every = "2 " + m.get_string(1).to_lower()
		else:
			m = _cut(box, "\\bevery\\s+(day|week|month)\\b")
			if m != null:
				every = m.get_string(1).to_lower()
			else:
				m = _cut(box, "\\bevery\\s+" + DAY_RX + "\\b")
				if m != null:
					every = "week"
					weekday = DAYS.find(m.get_string(1).to_lower())
	found = m != null
	m = _cut(box, "\\bin\\s+(\\d+|an?)\\s+(minutes?|mins?|hours?|hrs?|days?|weeks?)\\b")
	if m != null:
		found = true
		var n := 1 if m.get_string(1).to_lower() in ["a", "an"] else int(m.get_string(1))
		var unit := m.get_string(2).to_lower()
		if unit.begins_with("min"):
			exact = floorf(now / 60.0) * 60.0 + n * 60.0
		elif unit.begins_with("h"):
			exact = floorf(now / 60.0) * 60.0 + n * 3600.0
		else:
			date = LocalList.midnight(now) + n * (7 if unit.begins_with("w") else 1) * LocalList.DAY
	if exact < 0.0 and date < 0.0:
		date = _named_date(box, now)
		found = found or date >= 0.0
		if date < 0.0:
			m = _cut(box, "\\b(tomorrow|tonight|today)\\b")
			if m != null:
				found = true
				var word := m.get_string(1).to_lower()
				tonight = word == "tonight"
				date = LocalList.midnight(now) + (LocalList.DAY if word == "tomorrow" else 0.0)
			else:
				m = _cut(box, "\\b(?:on\\s+|next\\s+)?" + DAY_RX + "\\b")
				if m != null:
					found = true
					weekday = DAYS.find(m.get_string(1).to_lower())
	if weekday >= 0 and date < 0.0:
		var ahead := (weekday - int(LocalList.parts(now)["weekday"]) + 7) % 7
		date = LocalList.midnight(now) + (ahead if ahead > 0 else 7) * LocalList.DAY
	var clock := _time(box)
	if clock.size() > 0:
		hour = clock[0]
		minute = clock[1]
		found = true
	var text := _tidy(box["s"])
	if not found or text == "":
		return _add("todo", line, {}, "To do: %s." % line)
	var guessed := hour < 0 and exact < 0.0
	if hour < 0:
		hour = TONIGHT if tonight else MORNING
	var at := exact
	if exact < 0.0:
		var implicit := date < 0.0 or tonight or date == LocalList.midnight(now)
		if date < 0.0:
			date = LocalList.midnight(now)
		at = date + hour * 3600.0 + minute * 60.0
		if implicit and at <= now:
			at += LocalList.DAY
	var stamp := _stamp(at)
	var body := {"kind": "reminder", "text": text, "at": stamp}
	var say := "Reminder set: %s, %s" % [text, _when(at, now)]
	if every != "":
		body["every"] = every
		say += ", then every " + LocalList.say_every(every)
	if guessed:
		say += " (no hour given: %02d:00)" % hour
	return {"action": "add", "body": body, "say": say + "."}


# "21 nov", "nov 21", "11/21": midnight of that day this year, or next year's when it has gone
func _named_date(box: Dictionary, now: float) -> float:
	var y := int(LocalList.parts(now)["year"])
	for form in [
		["\\b(?:on\\s+)?(\\d{1,2})(?:st|nd|rd|th)?\\s+" + MON_RX + "\\b", 1, 2],
		["\\b(?:on\\s+)?" + MON_RX + "\\.?\\s+(\\d{1,2})(?:st|nd|rd|th)?\\b", 2, 1],
		["\\b(?:on\\s+)?(\\d{1,2})/(\\d{1,2})\\b", 2, 1],
	]:
		var m := _m(form[0], box["s"])
		if m == null:
			continue
		var day := int(m.get_string(form[1]))
		var mon_text: String = m.get_string(form[2])
		var mon := int(mon_text) if mon_text.is_valid_int() else MONTHS.find(mon_text.to_lower()) + 1
		if mon > 12 and day <= 12 and mon_text.is_valid_int():
			var swap := mon
			mon = day
			day = swap
		if mon < 1 or mon > 12 or day < 1 or day > LocalList.days_in(y, mon):
			continue
		_excise(box, m)
		var out := LocalList.wall(y, mon, day)
		if out < LocalList.midnight(now):
			out = LocalList.wall(y + 1, mon, mini(day, LocalList.days_in(y + 1, mon)))
		return out
	return -1.0


# [hour, minute] from "at 3pm", "15:00", "3:30pm", "at 9"; [] when there is none
static func _time(box: Dictionary) -> Array:
	for form in [
		"\\b(?:at\\s+)?(\\d{1,2})(?::(\\d{2}))?\\s*(am|pm)\\b",
		"\\b(?:at\\s+)?(\\d{1,2}):(\\d{2})\\b",
		"\\bat\\s+(\\d{1,2})\\b",
	]:
		var m := _m(form, box["s"])
		if m == null:
			continue
		var h := int(m.get_string(1))
		var mi := int(m.get_string(2)) if m.get_group_count() >= 2 and m.get_string(2) != "" else 0
		if m.get_group_count() >= 3 and m.get_string(3) != "":
			if h < 1 or h > 12:
				continue
			h = h % 12 + (12 if m.get_string(3).to_lower() == "pm" else 0)
		if h > 23 or mi > 59:
			continue
		_excise(box, m)
		return [h, mi]
	return []


static func _tidy(s: String) -> String:
	var out := RegEx.create_from_string("\\s+").sub(s, " ", true).strip_edges()
	out = RegEx.create_from_string("(?i)^(?:to\\s+)").sub(out, "")
	out = RegEx.create_from_string("(?i)(?:\\s+(?:on|at|by|next|this|for|in))+$").sub(out, "")
	out = RegEx.create_from_string("^[\\s,.;:!-]+|[\\s,;:-]+$").sub(out, "", true)
	return out.strip_edges()


static func _stamp(at: float) -> String:
	var d := LocalList.parts(at)
	return "%04d-%02d-%02dT%02d:%02d" % [d["year"], d["month"], d["day"], d["hour"], d["minute"]]


static func _when(at: float, now: float) -> String:
	var d := LocalList.parts(at)
	var days := int((LocalList.midnight(at) - LocalList.midnight(now)) / LocalList.DAY)
	var clock := "%02d:%02d" % [d["hour"], d["minute"]]
	if days == 0:
		return "today " + clock
	if days == 1:
		return "tomorrow " + clock
	return (
		"%s %d %s %s" % [DAY_ABBR[d["weekday"]], d["day"], MONTH_ABBR[int(d["month"]) - 1], clock]
	)


static func _words(s: String) -> Array:
	var out := []
	for m in RegEx.create_from_string("[\\p{L}\\p{N}]+").search_all(s.to_lower()):
		out.append(m.get_string())
	return out


# the open thing whose words overlap the query's the most; a tie is told and nothing changes
func _find(query: String, context: Dictionary, action: String) -> Dictionary:
	var status: Dictionary = context["status"]
	var pool: Array = status["open"] + status["coming"] + status["waiting"] + status["projects"]
	if action == "delete":
		pool = pool + status["note_rows"]
	var wanted := _words(query).filter(func(w): return not STOP.has(w))
	if wanted.is_empty():
		wanted = _words(query)
	var best := 0
	var top: Array = []
	for row in pool:
		var have := _words(str(row["text"]))
		var score := wanted.filter(func(w): return have.has(w)).size()
		if score > best:
			best = score
			top = [row]
		elif score == best and score > 0:
			top.append(row)
	if top.is_empty():
		return _say("I couldn't find anything open like that. Nothing changed.")
	if top.size() > 1:
		var exact := top.filter(
			func(r): return str(r["text"]).to_lower() == query.strip_edges().to_lower()
		)
		if exact.size() == 1:
			top = exact
		else:
			var names := top.slice(0, 5).map(func(r): return str(r["text"]))
			return _say("Which one? %s. Nothing changed." % ", ".join(names))
	var row: Dictionary = top[0]
	var text := str(row["text"])
	if row.get("kind") == "project":
		return _say("%s is a project: do that from its card. Nothing changed." % text)
	if action == "delete" and row.get("every") != null:
		return _say("%s repeats: delete it from its card. Nothing changed." % text)
	return {
		"action": action,
		"id": int(row["id"]),
		"say": ("Done: %s." if action == "done" else "Deleted: %s.") % text,
	}


func _list(context: Dictionary) -> String:
	var status: Dictionary = context["status"]
	var now: float = context["now"]
	var bias: float = context.get("bias", 0.0)
	var open: Array = status["open"].map(func(r): return str(r["text"]))
	var today := []
	for r in status["coming"]:
		var at: float = (
			Time.get_unix_time_from_datetime_string(str(r["due_at"]).trim_suffix("Z")) + bias
		)
		if LocalList.midnight(at) == LocalList.midnight(now):
			today.append("%s at %s" % [r["text"], _when(at, now).get_slice(" ", 1)])
	var lines := []
	if not open.is_empty():
		lines.append("Still open: %s." % ", ".join(open))
	if not today.is_empty():
		lines.append("Today: %s." % ", ".join(today))
	return "\n".join(lines) if not lines.is_empty() else "Nothing open right now."
