extends Node

# The house's own calendar, over the local list: one optional feed address (an `.ics` link) the
# person pastes in settings, fetched on a timer, and answered as `Server.Home.Day` answers the
# server's: today's remaining and tomorrow's (`meetings`), and any run of dates (`between`). The
# address is a secret: it lives in `user://house_calendar.json` {"url"} at mode 0600 and nowhere
# else, and no line printed, logged or returned holds it; `problem` is a fixed phrase. With no feed
# set every answer is []. Nothing is fetched unless `live` (never in a staged run).
signal fetched

const Ics := preload("res://ics.gd")
const STORE := "user://house_calendar.json"
const EVERY := 900.0
const TIMEOUT := 20.0
const BODY_MAX := 20000000
const DAY := 86400
const E_RANGE := "from and to are dates as YYYY-MM-DD, from not after to, at most 62 days"

static var _said := {}

var store := STORE
var persist := false
var live := false
var url := ""
var problem := ""
var found := {"events": [], "unknown": []}
# the house's local wall clock (seconds) and its zone's offset from UTC, as the list has them
var clock := Callable()
var bias := 0.0

var _timer: Timer
var _busy := false


# the address as it will be fetched: webcal:// is https://, and only http(s) with a host is one
static func address(raw: String) -> String:
	var t := raw.strip_edges()
	if t.to_lower().begins_with("webcal://"):
		t = "https://" + t.substr(9)
	var ok := RegEx.create_from_string("^(?i)https?://[^/\\s?#]+").search(t) != null
	return t if ok and not t.contains(" ") else ""


# both are real dates as YYYY-MM-DD, from not after to, no more than 62 days
static func range_ok(from: String, to: String) -> bool:
	var a: Variant = _day(from)
	var b: Variant = _day(to)
	return a != null and b != null and b - a >= 0 and b - a <= 61


# the day number of a date, null when it is not one
static func _day(text: String) -> Variant:
	var m := RegEx.create_from_string("^(\\d{4})-(\\d\\d)-(\\d\\d)$").search(text)
	if m == null:
		return null
	var y := int(m.get_string(1))
	var mo := int(m.get_string(2))
	var d := int(m.get_string(3))
	if mo < 1 or mo > 12 or d < 1 or d > Ics.month_days(y, mo):
		return null
	return Ics.day_of(y, mo, d)


func has_url() -> bool:
	return url != ""


func load_state() -> void:
	if not (persist and FileAccess.file_exists(store)):
		return
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(store))
	if d is Dictionary:
		url = address(str(d.get("url", "")))


func _save() -> void:
	if not persist:
		return
	var f := FileAccess.open(store, FileAccess.WRITE)
	if f == null:
		return
	f.close()
	FileAccess.set_unix_permissions(store, FileAccess.UNIX_READ_OWNER | FileAccess.UNIX_WRITE_OWNER)
	f = FileAccess.open(store, FileAccess.WRITE)
	f.store_string(JSON.stringify({"url": url}))


# `cb(line)` says "ok" when the address read as a calendar, else why not; kept only then
func connect_feed(candidate: String, cb: Callable) -> void:
	var addr := address(candidate)
	if addr == "":
		cb.call("paste the calendar's link (https://...)")
		return
	_fetch(
		addr,
		func(ok: bool, why: String) -> void:
			if ok:
				url = addr
				problem = ""
				_save()
				_arm()
			cb.call("ok" if ok else why)
	)


func disconnect_feed() -> void:
	stop()
	url = ""
	problem = ""
	found = {"events": [], "unknown": []}
	if persist and FileAccess.file_exists(store):
		DirAccess.remove_absolute(store)


# fetch now and then every `EVERY` seconds, never oftener; a failure keeps the last good copy
func start() -> void:
	if _arm():
		refresh()


# the timer alone, for a feed just fetched; false when there is nothing to fetch
func _arm() -> bool:
	if not live or url == "":
		return false
	if _timer == null:
		_timer = Timer.new()
		_timer.wait_time = EVERY
		_timer.timeout.connect(refresh)
		add_child(_timer)
	_timer.start()
	return true


func stop() -> void:
	if _timer != null:
		_timer.stop()


func refresh() -> void:
	if url == "" or _busy:
		return
	_fetch(
		url,
		func(ok: bool, why: String) -> void:
			problem = "" if ok else why
			if ok:
				fetched.emit()
	)


# `done(ok, why)`; on success `found` is the new copy. The address is the request's own and no
# message made here holds it.
func _fetch(addr: String, done: Callable) -> void:
	if not live:
		done.call_deferred(false, "not available in this run")
		return
	_busy = true
	var req := HTTPRequest.new()
	req.timeout = TIMEOUT
	req.body_size_limit = BODY_MAX
	add_child(req)
	req.request_completed.connect(
		func(result: int, http: int, _h: PackedStringArray, body: PackedByteArray) -> void:
			req.queue_free()
			_busy = false
			if result != HTTPRequest.RESULT_SUCCESS:
				done.call(false, "the calendar could not be reached")
			elif http != 200:
				done.call(false, "the calendar answered %d" % http)
			else:
				_read(body.get_string_from_utf8(), done)
	)
	if req.request(addr, ["Accept: text/calendar, */*"]) != OK:
		req.queue_free()
		_busy = false
		done.call_deferred(false, "the calendar could not be reached")


func _read(text: String, done: Callable) -> void:
	if not text.contains("BEGIN:VCALENDAR"):
		done.call(false, "that link did not answer a calendar")
		return
	found = Ics.read(text)
	for name in found["unknown"]:
		if not _said.has(name):
			_said[name] = true
			print('calendar: unknown time zone "%s", read at the feed\'s own offset or UTC' % name)
	done.call(true, "")


func _now_utc() -> float:
	return float(clock.call()) - bias


func _midnight(day: int) -> float:
	return day * DAY - bias


func _iso(utc: float) -> String:
	return Time.get_datetime_string_from_unix_time(int(utc)) + "Z"


# today's remaining and tomorrow's, as `Server.Home.Day.meetings/1`: {title, starts_at, ends_at,
# tentative, all_day, day}
func meetings() -> Array:
	if found["events"].is_empty():
		return []
	var today := int(floor(float(clock.call()) / DAY))
	var rows: Array = []
	var cleaned := _cleaned(today, today + 1)
	for pair in [["today", today], ["tomorrow", today + 1]]:
		for p in _placed(cleaned, pair[1]):
			if pair[0] == "tomorrow" or p[2] >= _now_utc():
				var row := _row(p)
				row["day"] = pair[0]
				rows.append(row)
	rows.sort_custom(func(a, b): return a["starts_at"] < b["starts_at"])
	return rows


# the meetings on each local date from `from` to `to` (both valid, see `range_ok`), past dates too:
# {title, starts_at, ends_at, tentative, all_day, date}, by date, all-day first, then soonest
func between(from: String, to: String) -> Array:
	if found["events"].is_empty():
		return []
	var first: int = _day(from)
	var last: int = _day(to)
	var cleaned := _cleaned(first, last)
	var rows: Array = []
	for day in range(first, last + 1):
		for p in _placed(cleaned, day):
			var row := _row(p)
			row["date"] = Time.get_date_string_from_unix_time(day * DAY)
			rows.append(row)
	rows.sort_custom(
		func(a, b):
			if a["date"] != b["date"]:
				return a["date"] < b["date"]
			if a["all_day"] != b["all_day"]:
				return a["all_day"]
			return a["starts_at"] < b["starts_at"]
	)
	return rows


# the cleaned meetings that touch the local days `first` to `last`, fetched a day wider each way
# since an all-day event is held at UTC midnights
func _cleaned(first: int, last: int) -> Array:
	return Ics.clean(Ics.occurrences(found, _midnight(first) - DAY, _midnight(last + 1) + DAY))


# `[meeting, starts, ends]` for each way the meeting falls on the local day `day`
func _placed(cleaned: Array, day: int) -> Array:
	var out: Array = []
	for m in cleaned:
		if m["all_day"]:
			var first := int(floor(m["start"] / DAY))
			var last := int(floor(m["stop"] / DAY)) - 1
			if day >= first and day <= last:
				out.append([m, _midnight(day), _midnight(day + 1)])
		elif m["start"] < _midnight(day + 1) and m["stop"] > _midnight(day):
			out.append([m, m["start"], m["stop"]])
	return out


func _row(p: Array) -> Dictionary:
	return {
		"title": p[0]["title"],
		"starts_at": _iso(p[1]),
		"ends_at": _iso(p[2]),
		"tentative": p[0]["busy"] == "tentative",
		"all_day": p[0]["all_day"],
	}
