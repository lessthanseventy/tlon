extends RefCounted

# The conversation on the phone: what he said, what the home said, the reminders it was told of
# and now and then a pet. Each message is {t (unix), who ("me"|"home"|"cat"|"dog"), text, done?};
# a reminder also carries its `id` and `told_at`. The last 300 are kept in user://house_chat.json.
signal changed

const STORE := "user://house_chat.json"
const CAP := 300
const PET_GAP := 600.0
const BELL := "⏰ "

var store := STORE
var persist := false
var messages: Array = []
var unread := false
var open := false


func setup(persist_it: bool) -> void:
	persist = persist_it
	messages = []
	if persist and FileAccess.file_exists(store):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(store))
		if d is Dictionary and d.get("messages") is Array:
			for m in d["messages"]:
				if m is Dictionary and m.get("text") is String and m.get("who") is String:
					messages.append(m)
			messages = messages.slice(-CAP)


func add(who: String, text: String, extra: Dictionary = {}) -> Dictionary:
	var m := {"t": int(Time.get_unix_time_from_system()), "who": who, "text": text}
	m.merge(extra, true)
	messages.append(m)
	if messages.size() > CAP:
		messages = messages.slice(-CAP)
	if who != "me" and not open:
		unread = true
	_save()
	return m


# the house was told of this reminder: one message with its buttons, once per nudge
func told(id: int, told_at: String, text: String) -> void:
	for m in messages:
		if m.get("id") == id and m.get("told_at") == told_at:
			return
	add("home", BELL + text, {"id": id, "told_at": told_at})


# the buttons of a reminder message are replaced by what was done: "done", "hour", "tomorrow",
# "delete", or "gone" when it was dealt with another way
func resolve(id: int, what: String) -> void:
	for m in messages:
		if m.get("id") == id and not m.has("done"):
			m["done"] = what
	_save()


# a reminder no longer ringing was dealt with elsewhere
func sync(ringing: Array) -> void:
	var any := false
	for m in messages:
		if m.has("id") and not m.has("done") and not ringing.has(int(m["id"])):
			m["done"] = "gone"
			any = true
	if any:
		_save()


# a pet's bubble, now and then: not twice within ten minutes
func pet_said(who: String, text: String, now: float = Time.get_unix_time_from_system()) -> void:
	for i in range(messages.size() - 1, -1, -1):
		if messages[i]["who"] in ["cat", "dog"]:
			if now - float(messages[i]["t"]) < PET_GAP:
				return
			break
	add(who, text, {"t": now})


func slip(title: String, labels: Array) -> void:
	add("home", "%s: %s" % [title, ", ".join(labels)] if not labels.is_empty() else title)


# a sent line that never got there
func retract(text: String) -> void:
	if not messages.is_empty() and messages[-1]["who"] == "me" and messages[-1]["text"] == text:
		messages.pop_back()
		_save()


func last_mine() -> String:
	for i in range(messages.size() - 1, -1, -1):
		if messages[i]["who"] == "me":
			return str(messages[i]["text"])
	return ""


func clear() -> void:
	messages = []
	unread = false
	_save()


func _save() -> void:
	if persist:
		var f := FileAccess.open(store, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify({"messages": messages}))
	changed.emit()
