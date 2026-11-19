extends RefCounted

# The day's two beats, each once a day: he comes home at the server's daily-list time and a slip of
# what is still open shows in the sidebar's banner; in the morning he stretches and a slip shows
# what is coming today.
const STORE := "user://house_rhythm.json"
const HOME_WINDOW := 3.0
const MORNING_FROM := 5.5
const MORNING_LATE := 8.0
const MORNING_UNTIL := 12.0
const SLIP_SECONDS := 14.0
const SHOWN := 6

var list_at := 17.5
var persist := true
var days := {"home": "", "morning": ""}
var first_hour := -1.0
var kind := ""
var title := ""
var rows: Array = []
var more := 0
var left := 0.0
var age := 0.0
# the pointer is on the banner: the slip waits
var held := false


static func parse_time(text: String) -> float:
	var parts := text.strip_edges().split(":")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return -1.0
	return float(int(parts[0])) + float(int(parts[1])) / 60.0


static func home_due(hour: float, at: float, done_day: String, today: String) -> bool:
	return at >= 0.0 and done_day != today and hour >= at and hour < minf(at + HOME_WINDOW, 23.0)


static func morning_due(hour: float, first: float, done_day: String, today: String) -> bool:
	if done_day == today or hour >= MORNING_UNTIL or hour < MORNING_FROM:
		return false
	return first >= MORNING_FROM or hour >= MORNING_LATE


func load_days() -> void:
	if not persist or not FileAccess.file_exists(STORE):
		return
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(STORE))
	if d is Dictionary:
		for k in days:
			days[k] = str(d.get(k, ""))


func _save() -> void:
	if not persist:
		return
	var f := FileAccess.open(STORE, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(days))


func due(hour: float, today: String) -> String:
	if first_hour < 0.0:
		first_hour = hour
	if morning_due(hour, first_hour, days["morning"], today):
		days["morning"] = today
		_save()
		return "morning"
	if home_due(hour, list_at, days["home"], today):
		days["home"] = today
		_save()
		return "home"
	return ""


func show_slip(which: String, heading: String, items: Array, extra: int = 0) -> void:
	kind = which
	title = heading
	rows = items.slice(0, SHOWN)
	more = extra + maxi(0, items.size() - SHOWN)
	left = SLIP_SECONDS
	age = 0.0


func dismiss() -> void:
	kind = ""
	rows = []
	more = 0


func active() -> bool:
	return kind != ""


func process(dt: float) -> void:
	if kind == "":
		return
	age += dt
	if not held:
		left -= dt
	if left <= 0.0:
		dismiss()

