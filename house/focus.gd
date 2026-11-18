extends RefCounted

const STORE := "user://house_now.json"
const LENGTHS := [10, 25, 45]

var id := -1
var text := ""
var minutes := 25
var started := 0.0
var persist := true


func active() -> bool:
	return id >= 0


func running() -> bool:
	return started > 0.0


func set_now(item_id: int, item_text: String) -> void:
	if item_id != id:
		started = 0.0
	id = item_id
	text = item_text
	save()


func clear() -> void:
	id = -1
	text = ""
	started = 0.0
	save()


func cycle() -> void:
	minutes = LENGTHS[(LENGTHS.find(minutes) + 1) % LENGTHS.size()]
	started = 0.0
	save()


func start() -> void:
	started = Time.get_unix_time_from_system()
	save()


func stop() -> void:
	started = 0.0
	save()


func elapsed() -> float:
	return Time.get_unix_time_from_system() - started if running() else 0.0


func progress() -> float:
	return clampf(elapsed() / (minutes * 60.0), 0.0, 1.0) if running() else 0.0


func left() -> int:
	return maxi(0, int(minutes * 60.0 - elapsed())) if running() else minutes * 60


func clock() -> String:
	var s := left()
	return "%d:%02d" % [s / 60, s % 60]


func finished() -> bool:
	if running() and elapsed() >= minutes * 60.0:
		started = 0.0
		save()
		return true
	return false


func save() -> void:
	if not persist:
		return
	var f := FileAccess.open(STORE, FileAccess.WRITE)
	if f != null:
		f.store_string(
			JSON.stringify({"id": id, "text": text, "minutes": minutes, "started": started})
		)


func load_saved() -> void:
	if not FileAccess.file_exists(STORE):
		return
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(STORE))
	if d is Dictionary:
		id = int(d.get("id", -1))
		text = str(d.get("text", ""))
		minutes = int(d.get("minutes", 25))
		started = float(d.get("started", 0.0))
