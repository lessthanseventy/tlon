extends RefCounted

# Which thing's blocks the sidebar shows (`kind`, from the thing `key`, `page` of a long list), and
# the calendar's date and repeat arithmetic. `blocks.gd` turns the blocks into the view.
const MONTHS := [
	"January",
	"February",
	"March",
	"April",
	"May",
	"June",
	"July",
	"August",
	"September",
	"October",
	"November",
	"December",
]
const WEEK := ["S", "M", "T", "W", "T", "F", "S"]

var kind := ""
var key := ""
var page := 0


static func unix(year: int, month: int, day: int, hour: int = 0, minute: int = 0) -> float:
	return Time.get_unix_time_from_datetime_dict(
		{"year": year, "month": month, "day": day, "hour": hour, "minute": minute, "second": 0}
	)


static func days_in(year: int, month: int) -> int:
	var next := unix(year + month / 12, month % 12 + 1, 1)
	return int((next - unix(year, month, 1)) / 86400.0)


# {first: weekday of the 1st (0 = Sunday), days}
static func month_info(year: int, month: int) -> Dictionary:
	var wd: int = Time.get_datetime_dict_from_unix_time(int(unix(year, month, 1)))["weekday"]
	return {"first": wd, "days": days_in(year, month)}


# {"n", "unit"} of an `every` the server sends ("week", "6 week"), {} for anything else
static func parse_every(every: String) -> Dictionary:
	var parts := every.strip_edges().split(" ", false)
	if parts.is_empty() or parts.size() > 2 or parts[-1] not in ["day", "week", "month"]:
		return {}
	var n := 1 if parts.size() == 1 else (int(parts[0]) if parts[0].is_valid_int() else 0)
	return {} if n < 1 else {"n": n, "unit": parts[-1]}


# "every week", "every other week", "every 6 weeks", "every 3 months"
static func every_words(every: String) -> String:
	var e := parse_every(every)
	if e.is_empty():
		return "every " + every
	if e["n"] == 1:
		return "every " + e["unit"]
	return "every other " + e["unit"] if e["n"] == 2 else "every %d %ss" % [e["n"], e["unit"]]


# the times (unix, local) a reminder falls on in [from, to): its due time, and for a repeating one
# every N days, weeks or months after it (a monthly one on its day, clamped in short months)
static func occurrences(due: float, every: String, from: float, to: float) -> Array:
	var out: Array = []
	var e := parse_every(every)
	if e.is_empty():
		if due >= from and due < to:
			out.append(due)
		return out
	var n: int = e["n"]
	if e["unit"] == "month":
		var d := Time.get_datetime_dict_from_unix_time(int(due))
		var base: int = int(d["year"]) * 12 + int(d["month"]) - 1
		for k in 1200:
			var y: int = (base + k * n) / 12
			var m: int = (base + k * n) % 12 + 1
			var at := unix(y, m, mini(int(d["day"]), days_in(y, m)), d["hour"], d["minute"])
			if at >= to:
				break
			if at >= from:
				out.append(at)
		return out
	var step := 86400.0 * n * (7 if e["unit"] == "week" else 1)
	var at := due
	if at < from:
		at += ceilf((from - at) / step) * step
	while at < to:
		out.append(at)
		at += step
	return out


# "in 2 h 10 min", "in 25 min", "in 1 day 3 h"
static func until_text(secs: float) -> String:
	var mins := roundi(secs / 60.0)
	if mins <= 0:
		return "now"
	if mins < 60:
		return "in %d min" % mins
	if mins < 1440:
		var h := mins / 60
		return "in %d h" % h if mins % 60 == 0 else "in %d h %d min" % [h, mins % 60]
	var days := mins / 1440
	var h := (mins % 1440) / 60
	var text := "in %d day%s" % [days, "" if days == 1 else "s"]
	return text if h == 0 else text + " %d h" % h


func is_open() -> bool:
	return kind != ""


func open(what: String, from: String) -> void:
	kind = what
	key = from
	page = 0


func close() -> void:
	kind = ""
	key = ""

