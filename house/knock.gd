extends RefCounted

# Nina's one nag: the oldest sticky that has sat too long gets knocked off the desk, now and then.
const AGE := 3.0 * 86400.0
const GAP := 4.0 * 3600.0
const FIRST_CHECK := Vector2(60.0, 180.0)
const NEXT_CHECK := Vector2(180.0, 600.0)
const DAY_FROM := 8.0
const DAY_TO := 21.0
const STORE := "user://house_knock.json"
const LANDS_AT := Vector2(6.5, 1.5)

var id := -1
var last := 0.0
var persist := true
var next_check := 0.0
var flying := {}
var pending := -1

var _rng := RandomNumberGenerator.new()


func setup(seed_value: int) -> void:
	_rng.seed = seed_value if seed_value >= 0 else randi()
	next_check = _rng.randf_range(FIRST_CHECK.x, FIRST_CHECK.y)
	if persist and FileAccess.file_exists(STORE):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(STORE))
		if d is Dictionary:
			last = float(d.get("last", 0.0))


func save() -> void:
	if not persist:
		return
	var f := FileAccess.open(STORE, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"last": last}))


static func _unix(iso: Variant) -> float:
	return Time.get_unix_time_from_datetime_string(str(iso).trim_suffix("Z"))


static func oldest(open: Array, now: float) -> int:
	var best := -1
	var best_at := INF
	for item in open:
		if item.get("since") == null:
			continue
		if item.get("due_at") != null and _unix(item["due_at"]) > now:
			continue
		var at := _unix(item["since"])
		if at < best_at:
			best_at = at
			best = int(item["id"])
	if best >= 0 and now - best_at > AGE:
		return best
	return -1


func candidate(open: Array, now: float, hour: float, night: bool) -> int:
	if id >= 0 or pending >= 0 or not flying.is_empty():
		return -1
	if night or hour < DAY_FROM or hour >= DAY_TO:
		return -1
	if now - last < GAP:
		return -1
	return oldest(open, now)


func due(dt: float, open: Array, now: float, hour: float, night: bool) -> int:
	next_check -= dt
	if next_check > 0.0:
		return -1
	next_check = _rng.randf_range(NEXT_CHECK.x, NEXT_CHECK.y)
	return candidate(open, now, hour, night)


func fell(item_id: int, now: float) -> void:
	pending = -1
	last = now
	flying = {"id": item_id, "t": 0.0}
	save()


func clear() -> void:
	id = -1
	flying = {}
