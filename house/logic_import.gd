extends "res://logic_local.gd"

# The logic checks of the one-shot import of the server's home (`import_list.gd`): a dry run
# changes nothing, a write keeps every row and every link, a second run adds nothing, and a read
# that is empty, miscounted or dangling stops before anything is written.
const Import := preload("res://import_list.gd")


func run() -> void:
	t = at(2026, 11, 18, 14)
	_refused()
	_dry_then_write()
	_twice()
	_hand_made_door()
	_same_named_piles()


func _thing(id: int, kind: String, text: String, extra: Dictionary = {}) -> Dictionary:
	var out := {
		"id": id,
		"kind": kind,
		"text": text,
		"state": "open",
		"since": "2026-11-01T09:00:00Z",
		"due_at": null,
		"every": null,
		"every_day": null,
		"told_at": null,
		"nudges": 0,
		"project_id": null,
		"who": null,
		"plan": [],
		"done_at": null,
		"dropped_at": null,
		"hidden_until": null,
		"agenda_id": null,
	}
	out.merge(extra, true)
	return out


func _pile(id: int, kind: String, name: String, extra: Dictionary = {}) -> Dictionary:
	var out := {
		"id": id,
		"kind": kind,
		"name": name,
		"birthday": null,
		"every": null,
		"every_day": null,
		"next_at": null,
		"told_for": null,
	}
	out.merge(extra, true)
	return out


# what the server's route answers, after the JSON trip that makes every number a float
func _export() -> Dictionary:
	var things := [
		_thing(10, "project", "paint the hall", {"plan": ["buy paint"]}),
		_thing(11, "todo", "tape the edges", {"project_id": 10}),
		_thing(12, "todo", "call the bank", {"state": "done", "done_at": "2026-11-15T10:00:00Z"}),
		_thing(13, "note", "gone", {"state": "dropped", "dropped_at": "2026-11-11T10:00:00Z"}),
		_thing(14, "todo", "learn Greek", {"state": "someday"}),
		_thing(15, "reminder", "water", {"due_at": "2026-11-20T09:00:00Z", "every": "week"}),
		_thing(16, "note", "ask about the roof", {"agenda_id": 20}),
		_thing(17, "note", "umbrella", {"agenda_id": 22}),
		_thing(18, "waiting", "the plumber", {"who": "Sam"}),
	]
	var agendas := [
		_pile(20, "agenda", "retro", {"every": "week", "next_at": "2026-11-25T14:00:00Z"}),
		_pile(21, "person", "Sam", {"birthday": "03-15"}),
		_pile(22, "door", "by the door"),
	]
	var d := {
		"v": 1,
		"things": things,
		"agendas": agendas,
		"proposals": [{"id": 1, "text": "x"}],
		"settings": {"telegram_list_at": "18:00", "telegram_morning_at": "07:45"},
	}
	d["counts"] = Import.counts(things, agendas)
	d["counts"]["proposals"] = 1
	return JSON.parse_string(JSON.stringify(d))


func _refused() -> void:
	var list := _list()
	var before := JSON.stringify(list.doc)
	var empty := {"v": 1, "things": [], "agendas": [], "counts": {}, "proposals": []}
	_eq(Import.run(list, empty, true).get("error") != null, true, "an empty read is refused")
	var counted := _export()
	counted["counts"]["todo"] = 99
	_eq(Import.run(list, counted, true).get("error") != null, true, "a miscounted read is refused")
	var dangling := _export()
	dangling["things"][1]["project_id"] = 777
	_eq(Import.run(list, dangling, true).get("error") != null, true, "a dangling project stops")
	var thin := _export()
	thin["things"][0].erase("kind")
	_eq(Import.run(list, thin, true).get("error") != null, true, "a thing without a kind stops")
	_eq(JSON.stringify(list.doc), before, "nothing was written by any of them")


func _dry_then_write() -> void:
	_wipe()
	var list := _list(FILE)
	list.starters()
	var before := JSON.stringify(list.doc)
	var dry := Import.run(list, _export(), false)
	_eq(JSON.stringify(list.doc), before, "a dry run changes nothing")
	_eq(FileAccess.get_file_as_string(FILE) == JSON.stringify(list.doc), true, "nor the file")
	var report := Import.run(list, _export(), true)
	_eq(report, dry, "the write answers what the dry run said")
	_eq(report["server"], report["local"], "every kind: server count equals local count")
	_eq(report["server"]["todo"], 3, "three to-dos, done and someday among them")
	_eq(report["proposals"], 1, "the proposal is told, not carried")
	_eq(report["settings"]["telegram_morning_at"], "07:45", "the times are read")
	var s2: Dictionary = list.status()
	_eq(s2["open"].size(), 1 + 1, "the starter to-do and the step are open")
	_eq(s2["someday"].size(), 1, "someday stays someday")
	_eq(s2["done"].size(), 1, "the done one is in the week's done")
	_eq(s2["agendas"].size(), 1, "the agenda")
	_eq(s2["agendas"][0]["notes"].size(), 1, "its note is on its pile")
	_eq(s2["people"].size(), 1, "the person")
	_eq(s2["door"]["notes"].size(), 1, "the door's note")
	_eq(s2["projects"].size(), 1, "the project")
	_eq(s2["projects"][0]["steps"].size() if s2["projects"][0].has("steps") else 1, 1, "its step")
	var step: Dictionary = list.things().filter(func(x): return x["text"] == "tape the edges")[0]
	var project: Dictionary = list.things().filter(func(x): return x["text"] == "paint the hall")[0]
	_eq(int(step["project_id"]), int(project["id"]), "the step's project is mapped to the new id")
	var ids: Array = list.things().map(func(x): return int(x["id"]))
	ids.append_array(list.doc["agendas"].map(func(x): return int(x["id"])))
	var seen := {}
	for i in ids:
		seen[i] = true
	_eq(seen.size(), ids.size(), "no id is used twice")
	var back := _list(FILE)
	back.load_file()
	_eq(back.things().size(), list.things().size(), "the file holds it")
	_wipe()


func _twice() -> void:
	var list := _list()
	Import.run(list, _export(), true)
	var once := JSON.stringify(list.doc)
	var again := Import.run(list, _export(), true)
	_eq(again["added"], {}, "a second run adds nothing")
	_eq(JSON.stringify(list.doc), once, "and the list is as it was")


func _same_named_piles() -> void:
	var list := _list()
	var agendas := [_pile(30, "person", "Sam"), _pile(31, "person", "sam")]
	var d := {"v": 1, "things": [], "agendas": agendas}
	d["counts"] = Import.counts([], agendas)
	var report := Import.run(list, JSON.parse_string(JSON.stringify(d)), true)
	_eq(report["local"], report["server"], "two same-named server piles stay two")
	_eq(report["added"], {"person": 2}, "both added")


func _hand_made_door() -> void:
	var list := _list()
	list.door_add({"text": "keys"})
	Import.run(list, _export(), true)
	_eq(list.doc["agendas"].filter(func(a): return a.get("kind") == "door").size(), 1, "one door")
	_eq(list.status()["door"]["notes"].size(), 2, "the hand-made note and the server's")
