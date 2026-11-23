extends RefCounted

# One calendar feed's meetings, as `Server.Calendar.Feed` reads them: an `.ics` body unfolded and
# parsed, each event's recurrences expanded (RRULE, EXDATE), a moved instance (an event carrying a
# RECURRENCE-ID) standing in for the occurrence it replaces, every time in UTC seconds. An all-day
# event runs from its date's midnight to its end date's, UTC. A meeting is `{uid, title, start,
# stop, link, cancelled, busy, all_day}`; `busy` is "free", "tentative", "busy" or "away", from
# Outlook's X-MICROSOFT-CDO-BUSYSTATUS, else TRANSP, else STATUS.
#
# Godot has no zone database, so a TZID is read from a table of the common zones (US and EU
# daylight rules, Australian eastern, fixed ones), else from the feed's own VTIMEZONE (its standard
# offset, with a US or EU rule when it carries one), else the `(UTC±hh:mm)` prefix of the name as a
# whole-hour offset, else UTC. A name that falls through to the last three is listed in `unknown`.
const DAY := 86400
const JOIN := (
	"https://(?:[\\w-]+\\.)*(?:meet\\.google\\.com|zoom\\.us|teams\\.microsoft\\.com"
	+ '|teams\\.live\\.com|webex\\.com|whereby\\.com)/[^\\s"<>\\\\]+'
)
const WEEKDAYS := ["SU", "MO", "TU", "WE", "TH", "FR", "SA"]
const EASTERN := {"std": -18000, "rule": "us"}
const CENTRAL := {"std": -21600, "rule": "us"}
const MOUNTAIN := {"std": -25200, "rule": "us"}
const PACIFIC := {"std": -28800, "rule": "us"}
const ALASKA := {"std": -32400, "rule": "us"}
const LONDON := {"std": 0, "rule": "eu"}
const CENTRAL_EU := {"std": 3600, "rule": "eu"}
const EASTERN_EU := {"std": 7200, "rule": "eu"}
const SYDNEY := {"std": 36000, "rule": "au"}
const ZONES := {
	"utc": {"std": 0, "rule": ""},
	"etc/utc": {"std": 0, "rule": ""},
	"gmt": {"std": 0, "rule": ""},
	"tzone://microsoft/utc": {"std": 0, "rule": ""},
	"america/new_york": EASTERN,
	"america/toronto": EASTERN,
	"america/detroit": EASTERN,
	"eastern standard time": EASTERN,
	"america/chicago": CENTRAL,
	"central standard time": CENTRAL,
	"america/denver": MOUNTAIN,
	"mountain standard time": MOUNTAIN,
	"america/phoenix": {"std": -25200, "rule": ""},
	"us mountain standard time": {"std": -25200, "rule": ""},
	"america/los_angeles": PACIFIC,
	"america/vancouver": PACIFIC,
	"pacific standard time": PACIFIC,
	"america/anchorage": ALASKA,
	"alaskan standard time": ALASKA,
	"pacific/honolulu": {"std": -36000, "rule": ""},
	"hawaiian standard time": {"std": -36000, "rule": ""},
	"europe/london": LONDON,
	"europe/dublin": LONDON,
	"gmt standard time": LONDON,
	"europe/berlin": CENTRAL_EU,
	"europe/paris": CENTRAL_EU,
	"europe/madrid": CENTRAL_EU,
	"europe/rome": CENTRAL_EU,
	"europe/amsterdam": CENTRAL_EU,
	"europe/brussels": CENTRAL_EU,
	"europe/vienna": CENTRAL_EU,
	"europe/zurich": CENTRAL_EU,
	"europe/stockholm": CENTRAL_EU,
	"europe/oslo": CENTRAL_EU,
	"europe/copenhagen": CENTRAL_EU,
	"europe/prague": CENTRAL_EU,
	"europe/warsaw": CENTRAL_EU,
	"w. europe standard time": CENTRAL_EU,
	"central europe standard time": CENTRAL_EU,
	"central european standard time": CENTRAL_EU,
	"romance standard time": CENTRAL_EU,
	"europe/helsinki": EASTERN_EU,
	"europe/kiev": EASTERN_EU,
	"europe/kyiv": EASTERN_EU,
	"europe/athens": EASTERN_EU,
	"europe/bucharest": EASTERN_EU,
	"fle standard time": EASTERN_EU,
	"e. europe standard time": EASTERN_EU,
	"australia/sydney": SYDNEY,
	"australia/melbourne": SYDNEY,
	"aus eastern standard time": SYDNEY,
	"asia/kolkata": {"std": 19800, "rule": ""},
	"india standard time": {"std": 19800, "rule": ""},
	"asia/dubai": {"std": 14400, "rule": ""},
	"asia/shanghai": {"std": 28800, "rule": ""},
	"china standard time": {"std": 28800, "rule": ""},
	"asia/singapore": {"std": 28800, "rule": ""},
	"asia/tokyo": {"std": 32400, "rule": ""},
	"tokyo standard time": {"std": 32400, "rule": ""},
}


# `{events, unknown}` of an `.ics` body; a body that is not a calendar is no events
static func read(text: String) -> Dictionary:
	var lines := _lines(text)
	var blocks := _vtimezones(lines)
	var unknown: Array = []
	var events: Array = []
	var depth := 0
	var props: Array = []
	var in_event := false
	for ln in lines:
		var p := _prop(ln)
		if p.is_empty():
			continue
		var name: String = p["name"]
		if name == "BEGIN":
			depth += 1
			if p["value"] == "VEVENT" and depth == 2:
				in_event = true
				props = []
		elif name == "END":
			if p["value"] == "VEVENT" and depth == 2 and in_event:
				var e := _event(props, blocks, unknown)
				if not e.is_empty():
					events.append(e)
				in_event = false
			depth -= 1
		elif in_event and depth == 2:
			props.append(p)
	return {"events": events, "unknown": unknown}


# the lines of a body, unfolded (a line break and a space or tab joins a line to the one before)
static func _lines(text: String) -> PackedStringArray:
	var flat := RegEx.create_from_string("\\r?\\n[ \\t]").sub(text, "", true)
	var out := PackedStringArray()
	for l in flat.split("\n"):
		var t := l.strip_edges(false, true)
		if t != "":
			out.append(t)
	return out


# `{name, params, value}` of a line, the colon and semicolons inside quotes left alone; {} for none
static func _prop(line: String) -> Dictionary:
	var quoted := false
	var colon := -1
	var cuts: Array = []
	for i in line.length():
		var c := line[i]
		if c == '"':
			quoted = not quoted
		elif not quoted and c == ";" and colon < 0:
			cuts.append(i)
		elif not quoted and c == ":":
			colon = i
			break
	if colon < 1:
		return {}
	var head := line.substr(0, colon)
	var parts: Array = []
	var from := 0
	for cut in cuts:
		parts.append(line.substr(from, cut - from))
		from = cut + 1
	parts.append(line.substr(from, colon - from))
	var params := {}
	for part in parts.slice(1):
		var eq: int = part.find("=")
		if eq > 0:
			params[part.substr(0, eq).to_upper()] = (
				part.substr(eq + 1).trim_prefix('"').trim_suffix('"')
			)
	return {"name": parts[0].to_upper(), "params": params, "value": line.substr(colon + 1)}


# each VTIMEZONE block of the feed by its TZID: {std, rule}, from its STANDARD offset and DAYLIGHT
# rule
static func _vtimezones(lines: PackedStringArray) -> Dictionary:
	var out := {}
	var id := ""
	var section := ""
	var std: Variant = null
	var rule := ""
	var in_zone := false
	for ln in lines:
		var p := _prop(ln)
		if p.is_empty():
			continue
		match [p["name"], p["value"]]:
			["BEGIN", "VTIMEZONE"]:
				in_zone = true
				id = ""
				std = null
				rule = ""
			["END", "VTIMEZONE"]:
				if in_zone and id != "" and std != null:
					out[id] = {"std": std, "rule": rule}
				in_zone = false
			["BEGIN", "STANDARD"], ["BEGIN", "DAYLIGHT"]:
				section = p["value"]
			["END", "STANDARD"], ["END", "DAYLIGHT"]:
				section = ""
			_:
				if not in_zone:
					continue
				if p["name"] == "TZID" and section == "":
					id = p["value"]
				elif p["name"] == "TZOFFSETTO" and section == "STANDARD" and std == null:
					std = _offset(p["value"])
				elif p["name"] == "RRULE" and section == "DAYLIGHT" and rule == "":
					var r: String = p["value"]
					rule = "eu" if r.contains("-1SU") else ("us" if r.contains("2SU") else "")
	return out


# "+0530" and "-0500" as seconds; null for anything else
static func _offset(text: String) -> Variant:
	var m := RegEx.create_from_string("^([+-])(\\d\\d):?(\\d\\d)").search(text)
	if m == null:
		return null
	return (
		(-1 if m.get_string(1) == "-" else 1)
		* (int(m.get_string(2)) * 3600 + int(m.get_string(3)) * 60)
	)


static func zone(name: String, blocks: Dictionary, unknown: Array) -> Dictionary:
	var known: Variant = ZONES.get(name.to_lower())
	if known != null:
		return known
	if blocks.has(name):
		return blocks[name]
	if not name in unknown:
		unknown.append(name)
	var m := RegEx.create_from_string("^\\(UTC([+-])(\\d\\d):(\\d\\d)\\)").search(name)
	if m != null:
		var secs := (int(m.get_string(2)) * 60 + int(m.get_string(3))) * 60
		if secs % 3600 == 0 and secs <= 14 * 3600:
			return {"std": (-1 if m.get_string(1) == "-" else 1) * secs, "rule": ""}
	return ZONES["utc"]


# the zone's offset from UTC at a UTC instant
static func offset_at(z: Dictionary, utc: float) -> int:
	return int(z["std"]) + (3600 if _dst(z, utc) else 0)


static func _dst(z: Dictionary, utc: float) -> bool:
	var rule: String = z["rule"]
	if rule == "":
		return false
	var std: int = z["std"]
	var year: int = Time.get_datetime_dict_from_unix_time(int(utc + std))["year"]
	match rule:
		"us":
			var on := _nth_sunday(year, 3, 2) * DAY + 7200 - std
			var off := _nth_sunday(year, 11, 1) * DAY + 7200 - std - 3600
			return utc >= on and utc < off
		"eu":
			var on := _nth_sunday(year, 3, -1) * DAY + 3600
			var off := _nth_sunday(year, 10, -1) * DAY + 3600
			return utc >= on and utc < off
		"au":
			var off := _nth_sunday(year, 4, 1) * DAY + 7200 - std
			var on := _nth_sunday(year, 10, 1) * DAY + 7200 - std
			return utc < off or utc >= on
	return false


# the day number (days since 1970-01-01) of the nth Sunday of a month; n -1 is the last
static func _nth_sunday(year: int, month: int, n: int) -> int:
	return _nth_weekday(year, month, 0, n)


static func _nth_weekday(year: int, month: int, wd: int, n: int) -> int:
	if n > 0:
		var first := day_of(year, month, 1)
		return first + posmod(wd - _weekday(first), 7) + (n - 1) * 7
	var last := day_of(year, month, month_days(year, month))
	return last - posmod(_weekday(last) - wd, 7) - (-n - 1) * 7


static func day_of(y: int, m: int, d: int) -> int:
	return (
		int(
			Time.get_unix_time_from_datetime_dict(
				{"year": y, "month": m, "day": d, "hour": 0, "minute": 0, "second": 0}
			)
		)
		/ DAY
	)


# 0 is Sunday
static func _weekday(day: int) -> int:
	return posmod(day + 4, 7)


static func month_days(y: int, m: int) -> int:
	if m == 2:
		return 29 if (y % 4 == 0 and y % 100 != 0) or y % 400 == 0 else 28
	return 30 if m in [4, 6, 9, 11] else 31


# a wall-clock reading in a zone as a UTC instant
static func to_utc(z: Dictionary, wall: float) -> float:
	var guess := wall - int(z["std"])
	var o := offset_at(z, guess)
	var utc := wall - o
	var again := offset_at(z, utc)
	return utc if again == o else wall - again


# `{wall, zone, date}` of a DTSTART-like property, null when it does not read; a date has `date`
# and a floating time (no zone) is read as UTC
static func _time(p: Dictionary, blocks: Dictionary, unknown: Array) -> Variant:
	var v: String = p["value"].strip_edges()
	var m := (
		RegEx
		. create_from_string("^(\\d{4})(\\d\\d)(\\d\\d)(?:T(\\d\\d)(\\d\\d)(\\d\\d)?)?(Z?)$")
		. search(v)
	)
	if m == null:
		return null
	var wall := (
		Time
		. get_unix_time_from_datetime_dict(
			{
				"year": int(m.get_string(1)),
				"month": int(m.get_string(2)),
				"day": int(m.get_string(3)),
				"hour": int(m.get_string(4)),
				"minute": int(m.get_string(5)),
				"second": int(m.get_string(6)),
			}
		)
	)
	var is_date: bool = m.get_string(4) == "" or p["params"].get("VALUE", "") == "DATE"
	var z: Dictionary = ZONES["utc"]
	if m.get_string(7) == "" and p["params"].has("TZID") and not is_date:
		z = zone(str(p["params"]["TZID"]), blocks, unknown)
	return {"wall": float(wall), "zone": z, "date": is_date}


static func _utc(t: Dictionary) -> float:
	return t["wall"] if t["date"] else to_utc(t["zone"], t["wall"])


static func _unescape(text: String) -> String:
	var out := ""
	var i := 0
	while i < text.length():
		var c := text[i]
		if c == "\\" and i + 1 < text.length():
			var n := text[i + 1]
			out += "\n" if n in ["n", "N"] else n
			i += 2
		else:
			out += c
			i += 1
	return out


static func _event(props: Array, blocks: Dictionary, unknown: Array) -> Dictionary:
	var e := {
		"uid": "",
		"summary": null,
		"description": null,
		"location": null,
		"url": null,
		"status": "",
		"transp": "",
		"ms": "",
		"rrule": null,
		"exdates": [],
		"recurrence_id": null,
		"start": null,
		"end": null,
		"duration": null,
	}
	for p in props:
		var v: String = p["value"]
		match p["name"]:
			"UID":
				e["uid"] = v
			"SUMMARY":
				e["summary"] = _unescape(v)
			"DESCRIPTION":
				e["description"] = _unescape(v)
			"LOCATION":
				e["location"] = _unescape(v)
			"URL":
				e["url"] = v
			"STATUS":
				e["status"] = v.to_lower()
			"TRANSP":
				e["transp"] = v.to_lower()
			"X-MICROSOFT-CDO-BUSYSTATUS":
				e["ms"] = v.to_upper()
			"DTSTART":
				e["start"] = _time(p, blocks, unknown)
			"DTEND":
				e["end"] = _time(p, blocks, unknown)
			"DURATION":
				e["duration"] = _duration(v)
			"RECURRENCE-ID":
				var t: Variant = _time(p, blocks, unknown)
				e["recurrence_id"] = null if t == null else _utc(t)
			"EXDATE":
				for one in v.split(",", false):
					var t: Variant = _time({"value": one, "params": p["params"]}, blocks, unknown)
					if t != null:
						e["exdates"].append(_utc(t))
			"RRULE":
				e["rrule"] = _rrule(v, blocks, unknown)
	if e["start"] == null:
		return {}
	return e


static func _duration(text: String) -> Variant:
	var m := (
		RegEx
		. create_from_string(
			"^P(?:(\\d+)W)?(?:(\\d+)D)?(?:T(?:(\\d+)H)?(?:(\\d+)M)?(?:(\\d+)S)?)?$"
		)
		. search(text.strip_edges())
	)
	if m == null:
		return null
	var n := func(i: int) -> int: return int(m.get_string(i)) if m.get_string(i) != "" else 0
	return ((n.call(1) * 7 + n.call(2)) * 24 + n.call(3)) * 3600 + n.call(4) * 60 + n.call(5)


static func _rrule(text: String, blocks: Dictionary, unknown: Array) -> Variant:
	var r := {
		"freq": "",
		"interval": 1,
		"count": 0,
		"until": null,
		"byday": [],
		"bymonthday": [],
		"bymonth": []
	}
	for part in text.split(";", false):
		var key := part.get_slice("=", 0).to_upper()
		var val := part.get_slice("=", 1)
		match key:
			"FREQ":
				r["freq"] = val.to_upper()
			"INTERVAL":
				r["interval"] = maxi(1, int(val))
			"COUNT":
				r["count"] = int(val)
			"UNTIL":
				var t: Variant = _time({"value": val, "params": {}}, blocks, unknown)
				if t != null:
					r["until"] = _utc(t) + (DAY - 1 if t["date"] else 0)
			"BYDAY":
				for d in val.split(",", false):
					var m := RegEx.create_from_string("^([+-]?\\d+)?([A-Za-z]{2})$").search(d)
					if m != null and m.get_string(2).to_upper() in WEEKDAYS:
						r["byday"].append(
							{
								"n": int(m.get_string(1)) if m.get_string(1) != "" else 0,
								"wd": WEEKDAYS.find(m.get_string(2).to_upper())
							}
						)
			"BYMONTHDAY":
				for d in val.split(",", false):
					r["bymonthday"].append(int(d))
			"BYMONTH":
				for d in val.split(",", false):
					r["bymonth"].append(int(d))
	return r if r["freq"] in ["DAILY", "WEEKLY", "MONTHLY", "YEARLY"] else null


# every start of an event up to `to`, in UTC seconds; a series without a rule is its one start
static func starts(e: Dictionary, to: float) -> Array:
	var s: Dictionary = e["start"]
	if e["rrule"] == null:
		return [_utc(s)]
	var r: Dictionary = e["rrule"]
	var tod: float = fposmod(s["wall"], DAY)
	var first := int(floor(s["wall"] / DAY))
	var out: Array = []
	var skipped: Array = e["exdates"]
	var limit: float = to if r["until"] == null else minf(to, r["until"] + 1.0)
	var period := 0
	var counted := 0
	while period < 20000:
		var days := _period_days(r, first, period)
		days.sort()
		var past := false
		for d in days:
			if d < first:
				continue
			var wall: float = d * DAY + tod
			var utc: float = wall if s["date"] else to_utc(s["zone"], wall)
			if r["until"] != null and utc > r["until"]:
				past = true
				break
			if utc >= to:
				past = true
				break
			counted += 1
			if not utc in skipped:
				out.append(utc)
			if r["count"] > 0 and counted >= r["count"]:
				past = true
				break
		if past or _period_start(r, first, period) * DAY > limit + 2 * DAY * 31:
			break
		period += 1
	return out


# the first day of the period `period` steps from the start's
static func _period_start(r: Dictionary, first: int, period: int) -> int:
	var step: int = r["interval"] * period
	match r["freq"]:
		"DAILY":
			return first + step
		"WEEKLY":
			return first + step * 7
		"MONTHLY":
			var d := Time.get_datetime_dict_from_unix_time(first * DAY)
			var idx: int = d["year"] * 12 + d["month"] - 1 + step
			return day_of(idx / 12, idx % 12 + 1, 1)
	var y: int = Time.get_datetime_dict_from_unix_time(first * DAY)["year"] + step
	return day_of(y, 1, 1)


# the day numbers the rule gives in one period (unsorted, some before the start)
static func _period_days(r: Dictionary, first: int, period: int) -> Array:
	var step: int = r["interval"] * period
	var d0 := Time.get_datetime_dict_from_unix_time(first * DAY)
	var out: Array = []
	match r["freq"]:
		"DAILY":
			var day := first + step
			if _matches(r, day):
				out.append(day)
		"WEEKLY":
			var monday := first - posmod(_weekday(first) - 1, 7) + step * 7
			var wds: Array = (
				r["byday"].map(func(b): return b["wd"])
				if not r["byday"].is_empty()
				else [_weekday(first)]
			)
			for wd in wds:
				var day: int = monday + posmod(wd - 1, 7)
				if (
					r["bymonth"].is_empty()
					or Time.get_datetime_dict_from_unix_time(day * DAY)["month"] in r["bymonth"]
				):
					out.append(day)
		"MONTHLY":
			var idx: int = d0["year"] * 12 + d0["month"] - 1 + step
			out = _month_days_of(r, idx / 12, idx % 12 + 1, d0["day"])
		"YEARLY":
			var y: int = d0["year"] + step
			for m in r["bymonth"] if not r["bymonth"].is_empty() else [d0["month"]]:
				out.append_array(_month_days_of(r, y, m, d0["day"]))
	return out


# a DAILY day passes the BYMONTH, BYDAY and BYMONTHDAY limits that are set
static func _matches(r: Dictionary, day: int) -> bool:
	var d := Time.get_datetime_dict_from_unix_time(day * DAY)
	if not r["bymonth"].is_empty() and not d["month"] in r["bymonth"]:
		return false
	if not r["byday"].is_empty() and not r["byday"].any(func(b): return b["wd"] == _weekday(day)):
		return false
	return (
		r["bymonthday"].is_empty()
		or _monthday_in(r["bymonthday"], d["day"], month_days(d["year"], d["month"]))
	)


static func _monthday_in(list: Array, day: int, length: int) -> bool:
	return list.any(func(n): return (n if n > 0 else length + 1 + n) == day)


# the days of one month the rule picks: BYDAY (every such weekday, or the nth), BYMONTHDAY, else
# the start's day
static func _month_days_of(r: Dictionary, y: int, m: int, start_day: int) -> Array:
	var length := month_days(y, m)
	var out: Array = []
	if not r["byday"].is_empty():
		for b in r["byday"]:
			if b["n"] != 0:
				var day := _nth_weekday(y, m, b["wd"], b["n"])
				if Time.get_datetime_dict_from_unix_time(day * DAY)["month"] == m:
					out.append(day)
			else:
				for dom in range(1, length + 1):
					var day := day_of(y, m, dom)
					if _weekday(day) == b["wd"]:
						out.append(day)
		if not r["bymonthday"].is_empty():
			out = out.filter(
				func(day):
					return _monthday_in(
						r["bymonthday"],
						Time.get_datetime_dict_from_unix_time(day * DAY)["day"],
						length
					)
			)
	elif not r["bymonthday"].is_empty():
		for n in r["bymonthday"]:
			var dom: int = n if n > 0 else length + 1 + n
			if dom >= 1 and dom <= length:
				out.append(day_of(y, m, dom))
	elif start_day <= length:
		out.append(day_of(y, m, start_day))
	return out


# the meetings of a parsed feed that overlap [from, to), by start
static func occurrences(feed: Dictionary, from: float, to: float) -> Array:
	var moved: Array = []
	var series: Array = []
	for e in feed["events"]:
		(moved if e["recurrence_id"] != null else series).append(e)
	var replaced := {}
	for e in moved:
		replaced["%s|%s" % [e["uid"], e["recurrence_id"]]] = true
	var found: Array = []
	for e in series:
		for st in starts(e, to):
			if not replaced.has("%s|%s" % [e["uid"], st]):
				found.append(_meeting(e, st))
	for e in moved:
		found.append(_meeting(e, _utc(e["start"])))
	found = found.filter(func(m): return m["stop"] > from and m["start"] < to)
	for i in found.size():
		found[i]["i"] = i
	found.sort_custom(
		func(a, b): return a["start"] < b["start"] or (a["start"] == b["start"] and a["i"] < b["i"])
	)
	for m in found:
		m.erase("i")
	return found


static func _meeting(e: Dictionary, start: float) -> Dictionary:
	var title: String = e["summary"] if e["summary"] != null else "(no title)"
	return {
		"uid": e["uid"],
		"title": title,
		"start": start,
		"stop": start + _length(e),
		"link": _link(e),
		"cancelled":
		(
			e["status"] == "cancelled"
			or (
				RegEx.create_from_string("(?i)^\\s*cancell?ed:").search(title) != null
				and e["summary"] != null
			)
		),
		"busy": _busy(e),
		"all_day": e["start"]["date"],
	}


static func _busy(e: Dictionary) -> String:
	match e["ms"]:
		"FREE":
			return "free"
		"TENTATIVE":
			return "tentative"
		"OOF":
			return "away"
	if e["transp"] == "transparent":
		return "free"
	return "tentative" if e["status"] == "tentative" else "busy"


static func _length(e: Dictionary) -> float:
	if e["end"] != null:
		return _utc(e["end"]) - _utc(e["start"])
	if e["duration"] != null:
		return float(e["duration"])
	return float(DAY) if e["start"]["date"] else 0.0


static func _link(e: Dictionary) -> Variant:
	var re := RegEx.create_from_string(JOIN)
	for text in [e["url"], e["location"], e["description"]]:
		if text is String:
			var m := re.search(text)
			if m != null:
				return m.get_string()
	return null


# `Server.Calendar.clean/1`: cancelled meetings and free all-day events gone, titles stripped, and
# exact doubles (the same title and start) kept once, the first
static func clean(meetings: Array) -> Array:
	var seen := {}
	var out: Array = []
	for m in meetings:
		if m["cancelled"] or (m["all_day"] and m["busy"] == "free"):
			continue
		var t := title(m["title"])
		var key := "%s|%s" % [t.to_lower(), m["start"]]
		if seen.has(key):
			continue
		seen[key] = true
		var c: Dictionary = m.duplicate()
		c["title"] = t
		out.append(c)
	return out


# a title without a leading "[EXT] " or "Synced invitation: " and without the trailing
# " @ Wed Nov 4 … (name@example.com)" an outside calendar puts on a recurring copy
static func title(text: String) -> String:
	var t := RegEx.create_from_string("(?i)^(?:\\[EXT\\]\\s*|Synced invitation:\\s*)+").sub(
		text.strip_edges(), ""
	)
	t = RegEx.create_from_string("\\s+@\\s.*\\([^()]*\\)\\s*$").sub(t, "")
	return t.strip_edges()
