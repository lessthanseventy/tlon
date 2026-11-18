extends Node

# The weather of a house with no server: wttr.in's `format=j1` report, read into the kinds the room
# draws exactly as the server's `weather.ex` reads it. The one outward call of the local list: the
# URL only (no name, no text, the default user agent), at start and then every `EVERY` seconds,
# never oftener; a failure keeps the last report and waits for the next turn. Nothing is asked
# unless `live` (never in a staged run) and `on`.
signal reported

const BASE := "https://wttr.in"
const EVERY := 1800.0
const TIMEOUT := 15.0
const DEBOUNCE := 2.0
const TOWN_MAX := 60
const SEVERITY := ["storm", "snow", "rain", "fog", "cloudy", "partly", "clear"]
const DAYTIME := [900, 1200, 1500, 1800]
const CLEAR := [113]
const PARTLY := [116]
const CLOUDY := [119, 122]
const FOG := [143, 248, 260]
const STORM := [200, 386, 389, 392, 395]
const SNOW := [
	179,
	182,
	185,
	227,
	230,
	317,
	320,
	323,
	326,
	329,
	332,
	335,
	338,
	350,
	362,
	365,
	368,
	371,
	374,
	377,
]
const RAIN := [176, 263, 266, 281, 284, 293, 296, 299, 302, 305, 308, 311, 314, 353, 356, 359]

var base := BASE
var live := false
var on := false
var town := ""
var report: Variant = null
var days: Array = []
var clock := Callable()

var _last := -1.0e9
var _due := -1.0
var _busy := false


# a town as it may go into the address: letters, digits, spaces, commas, periods, ' and -, at most
# 60 characters; anything else is no town at all
static func town_of(raw: String) -> String:
	var t := raw.strip_edges()
	if t.length() > TOWN_MAX or t == "":
		return ""
	var ok := RegEx.create_from_string("^[\\p{L}\\p{N} ,.'\\-]+$")
	return t if ok.search(t) != null else ""


static func url(root: String, place: String) -> String:
	var path := "/" + place.uri_encode() if place != "" else "/"
	return root + path + "?format=j1"


static func kind_of(code: int) -> String:
	if code in CLEAR:
		return "clear"
	if code in PARTLY:
		return "partly"
	if code in CLOUDY:
		return "cloudy"
	if code in FOG:
		return "fog"
	if code in STORM:
		return "storm"
	if code in SNOW:
		return "snow"
	if code in RAIN:
		return "rain"
	return ""


# `{"report": {kind, temp_c, desc}, "days": [{date, high_c, low_c, kind, wet}]}`, or `{}` for a body
# that is not a report; a day that does not read is left out
static func parse(body: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(body) != OK or not json.data is Dictionary:
		return {}
	var doc: Dictionary = json.data
	var now: Variant = doc.get("current_condition")
	if not now is Array or now.is_empty() or not now[0] is Dictionary:
		return {}
	var c: Dictionary = now[0]
	var code: Variant = _int(c.get("weatherCode"))
	if code == null or kind_of(code) == "":
		return {}
	var kind := kind_of(code)
	var desc := ""
	var descs: Variant = c.get("weatherDesc")
	if descs is Array and not descs.is_empty() and descs[0] is Dictionary:
		desc = (
			str(descs[0].get("value", "")).strip_edges() if descs[0].get("value") is String else ""
		)
	return {
		"report":
		{"kind": kind, "temp_c": _int(c.get("temp_C")), "desc": desc if desc != "" else kind},
		"days": _days(doc.get("weather")),
	}


static func _days(list: Variant) -> Array:
	var out: Array = []
	if not list is Array:
		return out
	for d in list.slice(0, 3):
		var day := _day(d)
		if not day.is_empty():
			out.append(day)
	return out


static func _day(d: Variant) -> Dictionary:
	if not d is Dictionary or not d.get("hourly") is Array:
		return {}
	var date := str(d.get("date", ""))
	var shape := "^\\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\\d|3[0-1])$"
	var high: Variant = _int(d.get("maxtempC"))
	var low: Variant = _int(d.get("mintempC"))
	if RegEx.create_from_string(shape).search(date) == null or high == null or low == null:
		return {}
	var kinds: Array = []
	var wet := -1
	for h in d["hourly"]:
		var hour := _hour(h)
		if hour.is_empty():
			continue
		wet = maxi(wet, hour["wet"])
		if hour["kind"] != "":
			kinds.append(hour["kind"])
	if kinds.is_empty():
		return {}
	var worst := ""
	for k in SEVERITY:
		if k in kinds:
			worst = k
			break
	return {"date": date, "high_c": high, "low_c": low, "kind": worst, "wet": wet}


static func _hour(h: Variant) -> Dictionary:
	if not h is Dictionary:
		return {}
	var time: Variant = _int(h.get("time"))
	var code: Variant = _int(h.get("weatherCode"))
	var rain: Variant = _int(h.get("chanceofrain"))
	var snow: Variant = _int(h.get("chanceofsnow"))
	if time == null or time not in DAYTIME or code == null or rain == null or snow == null:
		return {}
	return {"kind": kind_of(code), "wet": clampi(maxi(rain, snow), 0, 100)}


# a whole number from a string or a JSON number, else null
static func _int(v: Variant) -> Variant:
	if v is String and v.is_valid_int():
		return v.to_int()
	if v is float and v == floorf(v):
		return int(v)
	return null


func _now() -> float:
	return clock.call() if clock.is_valid() else Time.get_ticks_msec() / 1000.0


# the place or the switch changed: one fetch, once things have been quiet for `DEBOUNCE`
func poke() -> void:
	_due = _now() + DEBOUNCE


func clear() -> void:
	report = null
	days = []
	_due = -1.0


func _process(_dt: float) -> void:
	step()


func step() -> void:
	if not live or not on or _busy:
		return
	var now := _now()
	if _due >= 0.0:
		if now >= _due:
			_fetch(now)
	elif now - _last >= EVERY:
		_fetch(now)


func _fetch(now: float) -> void:
	_last = now
	_due = -1.0
	_busy = true
	var req := HTTPRequest.new()
	req.timeout = TIMEOUT
	add_child(req)
	req.request_completed.connect(
		func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
			req.queue_free()
			_busy = false
			_took(result == HTTPRequest.RESULT_SUCCESS and code == 200, body)
	)
	if req.request(url(base, town)) != OK:
		req.queue_free()
		_busy = false


func _took(ok: bool, body: PackedByteArray) -> void:
	if not ok or not on:
		return
	var got := parse(body.get_string_from_utf8())
	if got.is_empty():
		return
	report = got["report"]
	days = got["days"]
	reported.emit()
