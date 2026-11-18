extends RefCounted

# What is his to choose, in one flat object kept in user://house_settings.json. A command-line arg
# beats the file, the file beats the default. A key this build does not know is kept when the file
# is written. A scripted or staged run reads and writes nothing.
signal changed(key: String)

const STORE := "user://house_settings.json"
const CAT := "Nina"
const DOG := "Argos"
const DEFAULTS := {
	"name": "",
	"birthday": "",
	"cat": CAT,
	"dog": DOG,
	"pet1": "cat_black",
	"pet2": "dog_golden",
	"widget": false,
	"on_top": true,
	"url": "",
	"where": "server",
	"telegram": false,
	"telegram_list_at": "17:30",
	"claude": false,
	"claude_command": "claude",
	"glow": true,
	"weather_art": false,
	"spells": true,
}

# the names on display; Pets, Finds and the chat read these
static var cat := CAT
static var dog := DOG
static var person := ""

var store := STORE
var persist := false
var data := {}
var forced := {}
# no settings file existed at start: the house has not been set up yet
var fresh := false


static func default_url() -> String:
	if OS.has_environment("TLON_URL"):
		return OS.get_environment("TLON_URL")
	return "http://127.0.0.1:4040"


# the server's own pet lines name Nina and Argos; show the names he gave them
static func pets(text: String) -> String:
	if cat == CAT and dog == DOG:
		return text
	var out := ""
	var at := 0
	for m in RegEx.create_from_string("\\b(Nina|Argos)\\b").search_all(text):
		out += text.substr(at, m.get_start() - at) + (cat if m.get_string() == CAT else dog)
		at = m.get_end()
	return out + text.substr(at)


func setup(persist_it: bool) -> void:
	persist = persist_it
	fresh = persist and not FileAccess.file_exists(store)
	data = _read() if persist else {}
	_sync()


func value(key: String) -> Variant:
	if forced.has(key):
		return forced[key]
	return data.get(key, DEFAULTS[key])


func is_local() -> bool:
	return value("where") == "local"


func server_url() -> String:
	var u := str(value("url")).strip_edges().trim_suffix("/")
	return u if u != "" else default_url()


# a changed key is kept at once and the others in the file are left as they are
func put(key: String, v: Variant) -> void:
	if data.get(key, DEFAULTS.get(key)) == v:
		return
	data[key] = v
	if persist:
		var on_disk := _read()
		on_disk[key] = v
		var f := FileAccess.open(store, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(on_disk))
	_sync()
	changed.emit(key)


func _read() -> Dictionary:
	if not FileAccess.file_exists(store):
		return {}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(store))
	return d if d is Dictionary else {}


func _sync() -> void:
	cat = str(value("cat")).strip_edges()
	cat = cat if cat != "" else CAT
	dog = str(value("dog")).strip_edges()
	dog = dog if dog != "" else DOG
	person = str(value("name")).strip_edges()
