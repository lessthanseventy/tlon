extends "res://logic_local.gd"

# The logic checks of the people and the door: when a birthday is near, which day of a month it
# marks, the door's mark, the words, the view's reading of a birthday, and the house's own list
# keeping people and the pile by the door.
const People := preload("res://people.gd")
const When := preload("res://when.gd")
const PeopleView := preload("res://people_view.gd")

const TODAY := "2026-11-18"


func run() -> void:
	t = at(2026, 11, 18, 14)
	_valid()
	_next()
	_soon()
	_calendar()
	_door_mark()
	_names()
	_words()
	_people()
	_door()
	_old_files()


func _valid() -> void:
	for ok in ["03-15", "2000-03-15", "02-29", "1999-12-31"]:
		_eq(People.valid(ok), true, "'%s' is a birthday" % ok)
	for bad in [
		"", "3-15", "13-01", "00-10", "02-30", "04-31", "03/15", "99-03-15", "x", "2000-02", "03-1x"
	]:
		_eq(People.valid(bad), false, "'%s' is not" % bad)
	_eq(People.valid(null), false, "null is not")
	_eq(People.valid(315), false, "nor a number")


func _next() -> void:
	var cases := [
		["11-18", TODAY, "2026-11-18"],
		["11-19", TODAY, "2026-11-19"],
		["11-17", TODAY, "2027-11-17"],
		["2001-03-02", TODAY, "2027-03-02"],
		["02-29", TODAY, "2027-02-28"],
		["02-29", "2027-12-01", "2028-02-29"],
		["01-01", "2026-12-31", "2027-01-01"],
		["12-31", "2026-12-31", "2026-12-31"],
		["", TODAY, ""],
		["13-40", TODAY, ""],
	]
	for c in cases:
		_eq(People.next_birthday(c[0], c[1]), c[2], "'%s' from %s" % [c[0], c[1]])
	_eq(People.next_birthday(null, TODAY), "", "none has no next one")


func _person(name: String, next: Variant, birthday: Variant = null) -> Dictionary:
	return {"id": name.length(), "name": name, "birthday": birthday, "next_birthday": next}


func _soon() -> void:
	var people := [
		_person("Far", "2026-12-25", "12-25"),
		_person("Week", "2026-11-25", "11-25"),
		_person("Eight", "2026-11-26", "11-26"),
		_person("Today", TODAY, "11-18"),
		_person("None", null),
		_person("Soon", "2026-11-20", "11-20"),
	]
	_eq(People.days_to(people[3], TODAY), 0, "today is 0 days")
	_eq(People.days_to(people[1], TODAY), 7, "a week is 7")
	_eq(People.days_to(people[4], TODAY), -1, "none is -1")
	_eq(People.days_to(_person("Y", "2027-01-02"), "2026-12-30"), 3, "across the year's end")
	var names: Array = People.soon(people, TODAY).map(
		func(p: Dictionary) -> String: return p["name"]
	)
	_eq(names, ["Today", "Soon", "Week"], "within 7 days, today counted, the nearest first")
	_eq(People.soon(people, TODAY, 0).size(), 1, "within 0 days is today alone")
	_eq(People.soon([], TODAY).size(), 0, "nobody is none")
	_eq(People.soon([_person("None", null)], TODAY).size(), 0, "a person with no birthday never is")


func _calendar() -> void:
	var sam := _person("Sam", "2026-11-23", "11-23")
	var lee := _person("Lee", "2027-02-28", "2000-02-29")
	var none := _person("None", null)
	var people := [sam, lee, none]
	_eq(People.marks(people, 2026, 11), {23: true}, "November has Sam's day")
	_eq(People.marks(people, 2026, 12), {}, "December has none")
	_eq(People.marks(people, 2027, 2), {28: true}, "29 Feb is the 28th in a year with no 29th")
	_eq(People.marks(people, 2028, 2), {29: true}, "and the 29th in a leap year")
	_eq(People.marks(people, 2025, 11), {23: true}, "a past year marks its day too")
	_eq(
		People.on_day(people, 2026, 11, 23).map(func(p: Dictionary) -> String: return p["name"]),
		["Sam"],
		"who is on a day"
	)
	_eq(People.on_day(people, 2026, 11, 22).size(), 0, "nobody on another")
	var twins := [sam, _person("Pam", "2026-11-23", "11-23")]
	_eq(People.on_day(twins, 2026, 11, 23).size(), 2, "two on one day")
	_eq(People.day_in("11-23", 2026, 10), 0, "another month has no day for it")


func _door_mark() -> void:
	_eq(People.door_state({"id": null, "notes": []}), "none", "no pile: no tote")
	_eq(People.door_state({"id": 3, "notes": []}), "none", "an emptied pile: no tote")
	_eq(
		People.door_state({"id": 3, "notes": [{"id": 1, "text": "umbrella"}]}),
		"some",
		"a note: the tote is out"
	)
	_eq(People.door_state({}), "none", "an older server's status has none")


func _names() -> void:
	var cases := [
		["send Sam the photos", "Sam", true],
		["send SAM the photos", "sam", true],
		["ring Sam's mum", "Sam", true],
		["Sam", "Sam", true],
		["samurai sword", "Sam", false],
		["Samantha called", "Sam", false],
		["Sam-Jo called", "Sam", true],
		["call A.J. back", "A.J.", true],
		["call AxJx back", "A.J.", false],
		["buy milk", "Sam", false],
		["anything", "", false],
		["anything", "  ", false],
	]
	for c in cases:
		_eq(People.names(c[0], c[1]), c[2], "'%s' names '%s'" % [c[0], c[1]])


func _words() -> void:
	_eq(When.birthday(0, TODAY), "today", "today")
	_eq(When.birthday(1, "2026-11-19"), "tomorrow · Thu 19 Nov", "tomorrow with its day")
	_eq(When.birthday(3, "2026-11-21"), "in 3 days · Sat 21 Nov", "in days with its day")
	_eq(When.birthday(41, "2026-12-29"), "in 41 days · Tue 29 Dec", "a far one the same way")
	_eq(PeopleView.reading_of("")[0], "No birthday set.", "an empty field")
	_eq(PeopleView.reading_of("8 June"), ["Kept as 8 June.", true], "words read")
	_eq(PeopleView.reading_of("06-08")[0], "Kept as 8 June.", "digits read")
	_eq(PeopleView.reading_of("none")[0], "No birthday set.", "none clears")
	_eq(
		PeopleView.reading_of("31 June"),
		["That is not a day. Try 8 June or 06-08.", false],
		"not a day"
	)


func _person_row(l: RefCounted, id: int) -> Dictionary:
	for p in l.status()["people"]:
		if int(p["id"]) == id:
			return p
	return {}


func _people() -> void:
	var l := _list()
	var st: Dictionary = l.status()
	_eq(
		[st["people"], st["door"]],
		[[], {"id": null, "notes": []}],
		"a fresh list has no people and nothing by the door"
	)
	_line(
		l.agenda_add({"name": "Sam", "kind": "door"}),
		400,
		"kind is agenda or person",
		"a kind that is neither"
	)
	_line(l.agenda_add({"kind": "person"}), 400, "name is required", "a person needs a name")
	_line(
		l.agenda_add({"name": "Sam", "kind": "person", "birthday": "soon"}),
		400,
		LocalList.E_BIRTHDAY,
		"a bad birthday"
	)
	_line(
		l.agenda_add({"name": "Sam", "kind": "person", "birthday": "02-30"}),
		400,
		LocalList.E_BIRTHDAY,
		"a day that is not"
	)
	_line(
		l.agenda_add({"name": "Sam", "kind": "person", "every": "week"}),
		400,
		LocalList.E_PERSON_RHYTHM,
		"a person has no every"
	)
	_line(
		l.agenda_add({"name": "Sam", "kind": "person", "at": "2026-11-20T10:00"}),
		400,
		LocalList.E_PERSON_RHYTHM,
		"nor at"
	)
	_eq(l.status()["people"].size(), 0, "none of those made one")
	var r: Dictionary = l.agenda_add({"name": " Sam ", "kind": "person", "birthday": "2000-11-23"})
	_eq(r["code"], 200, "a person is made")
	var id := int(r["body"]["id"])
	_eq(
		r["body"],
		{
			"id": id,
			"name": "Sam",
			"birthday": "2000-11-23",
			"next_birthday": "2026-11-23",
			"notes": [],
			"todos": []
		},
		"as the server shows one"
	)
	_line(
		l.agenda_add({"name": "sam", "kind": "person"}),
		400,
		"there is already a person called sam",
		"a name is taken in any case"
	)
	var retro: Dictionary = l.agenda_add({"name": "Sam"})
	_eq(retro["code"], 200, "an agenda may share a person's name")
	var st2: Dictionary = l.status()
	_eq([st2["agendas"].size(), st2["people"].size()], [1, 1], "each in its own list")
	_eq(l.agenda_drop(int(retro["body"]["id"]))["code"], 200, "the agenda goes")
	var bare: Dictionary = l.agenda_add({"name": "Robyn", "kind": "person"})
	_eq(
		[bare["body"]["birthday"], bare["body"]["next_birthday"]],
		[null, null],
		"a person without a birthday has none"
	)
	var jude: Dictionary = l.agenda_add({"name": "Jude", "kind": "person", "birthday": "11-19"})
	var names: Array = l.status()["people"].map(func(p: Dictionary) -> String: return p["name"])
	_eq(names, ["Jude", "Sam", "Robyn"], "the soonest birthday first, none last")
	_eq(l.agenda_note(id, {"text": " a kettle "})["body"]["text"], "a kettle", "a note on a person")
	_line(l.agenda_note(id, {"text": " "}), 400, "text is required", "a note needs text")
	l.agenda_note(id, {"text": "said she wants a scarf"})
	var row := _person_row(l, id)
	_eq(
		row["notes"].map(func(n: Dictionary) -> String: return n["text"]),
		["a kettle", "said she wants a scarf"],
		"its notes in order"
	)
	_eq(l.status()["note_rows"].size(), 0, "a person's notes are in no other list")
	_todos(l, id)
	var e: Dictionary = l.agenda_edit(id, {"name": "Samuel", "birthday": "11-24"})
	_eq(
		[e["body"]["name"], e["body"]["birthday"], e["body"]["next_birthday"]],
		["Samuel", "11-24", "2026-11-24"],
		"a person is renamed and moved"
	)
	_line(
		l.agenda_edit(id, {"name": "jude"}),
		400,
		"there is already a person called jude",
		"a rename onto another"
	)
	_line(l.agenda_edit(id, {"name": " "}), 400, "name is required", "an empty name")
	_line(
		l.agenda_edit(id, {"birthday": "2026"}),
		400,
		LocalList.E_BIRTHDAY,
		"a bad birthday on an edit"
	)
	_line(
		l.agenda_edit(id, {"every": "week"}), 400, LocalList.E_PERSON_RHYTHM, "no every on an edit"
	)
	_eq(_person_row(l, id)["name"], "Samuel", "a refused edit changes nothing")
	_eq(
		l.agenda_edit(id, {"birthday": null})["body"]["next_birthday"],
		null,
		"a birthday is cleared with null"
	)
	_eq(l.agenda_edit(id, {"name": "Samuel"})["code"], 200, "the same name is no clash with itself")
	_eq(l.agenda_edit(99, {"name": "x"})["code"], 404, "no such person")
	var cleared: Dictionary = l.agenda_clear(id)
	_eq(
		[cleared["code"], cleared["body"]["notes"], cleared["body"].has("todos")],
		[200, [], true],
		"clearing empties a person's notes"
	)
	_eq(
		l.agenda_note(int(bare["body"]["id"]), {"text": "x"})["code"],
		200,
		"a note on another person"
	)
	var gone: Dictionary = l.agenda_drop(int(bare["body"]["id"]))
	_eq(gone["body"], {"id": int(bare["body"]["id"]), "name": "Robyn"}, "a person is dropped")
	var st3: Dictionary = l.status()
	_eq(
		st3["people"].map(func(p: Dictionary) -> String: return p["name"]),
		["Jude", "Samuel"],
		"and is gone from the list"
	)
	_eq(l.agenda_drop(int(bare["body"]["id"]))["code"], 404, "dropping twice is 404")
	_eq(jude["code"], 200, "(Jude stayed)")


# the open things that name a person: a to-do or a reminder by its text, a waiting-on by its who
func _todos(l: RefCounted, id: int) -> void:
	l.add({"kind": "todo", "text": "send Sam the photos"})
	l.add({"kind": "reminder", "text": "call SAM", "at": "2026-11-20T09:00"})
	l.add({"kind": "waiting", "text": "the lease", "who": "Sam"})
	l.add({"kind": "todo", "text": "buy a samovar"})
	l.add({"kind": "note", "text": "Sam likes tea"})
	var done: int = int(l.add({"kind": "todo", "text": "Sam's card"})["body"]["id"])
	l.done(done)
	var texts: Array = _person_row(l, id)["todos"].map(
		func(x: Dictionary) -> String: return x["text"]
	)
	texts.sort()
	_eq(
		texts,
		["call SAM", "send Sam the photos", "the lease"],
		"the to-dos that name Sam, a note and a done one not"
	)
	_eq(_person_row(l, id)["todos"][0].has("id"), true, "each is a row as Home's")


func _door() -> void:
	var l := _list()
	_line(l.door_add({"text": " "}), 400, "text is required", "an empty note by the door")
	_eq(l.status()["door"], {"id": null, "notes": []}, "which makes no pile")
	var r: Dictionary = l.door_add({"text": " umbrella "})
	_eq(
		[r["code"], r["body"]["text"], r["body"]["kind"]],
		[200, "umbrella", "note"],
		"the first note by the door"
	)
	l.door_add({"text": "return the library books"})
	var door: Dictionary = l.status()["door"]
	_eq(
		door["notes"].map(func(n: Dictionary) -> String: return n["text"]),
		["umbrella", "return the library books"],
		"both, in order"
	)
	_eq(l.status()["agendas"].size(), 0, "the door is no agenda")
	_eq(l.status()["note_rows"].size(), 0, "nor are its notes Home's notes")
	var door_id := int(door["id"])
	_line(
		l.agenda_edit(door_id, {"name": "front"}),
		400,
		LocalList.E_DOOR,
		"the door pile is never renamed"
	)
	_line(l.agenda_drop(door_id), 400, LocalList.E_DOOR, "nor dropped")
	_eq(l.agenda_note(door_id, {"text": "keys"})["code"], 200, "a note goes on it by its id too")
	_eq(l.drop(int(r["body"]["id"]))["code"], 200, "a note comes off with drop")
	var after: Dictionary = l.status()["door"]
	_eq(
		after["notes"].map(func(n: Dictionary) -> String: return n["text"]),
		["return the library books", "keys"],
		"and the rest stay"
	)
	_eq(after["id"], door_id, "the pile is the same")
	_eq(l.agenda_clear(door_id)["body"]["notes"], [], "clearing empties it")
	_eq(l.status()["door"], {"id": door_id, "notes": []}, "the pile stays, empty")
	l.door_add({"text": "again"})
	_eq(l.status()["door"]["id"], door_id, "a later note goes on the same pile")
	_eq(_list().status()["door"]["id"], null, "(another list has none)")


# a list file written before people and the door loads as it was; what it keeps survives a save
func _old_files() -> void:
	var path := FILE
	var old := {
		"v": 1,
		"next_id": 9,
		"things":
		[
			{
				"id": 1,
				"kind": "todo",
				"text": "send Sam the photos",
				"state": "open",
				"since": "2026-11-17T10:00:00Z",
				"novel": 7
			},
			{
				"id": 2,
				"kind": "note",
				"text": "a gift",
				"state": "open",
				"since": "2026-11-17T10:00:00Z",
				"agenda_id": 5
			},
		],
		"agendas":
		[
			{
				"id": 5,
				"name": "retro",
				"every": null,
				"next_at": null,
				"told_for": null,
				"extra": "kept"
			}
		],
		"future": {"a": 1},
	}
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(old))
	f.close()
	var l := _list(path)
	l.load_file()
	var st: Dictionary = l.status()
	_eq(
		[st["agendas"].size(), st["people"], st["door"]],
		[1, [], {"id": null, "notes": []}],
		"an old file has its agendas, no people, nothing by the door"
	)
	_eq(st["agendas"][0]["notes"].size(), 1, "and its agenda's notes")
	var made: Dictionary = l.agenda_add({"name": "Sam", "kind": "person", "birthday": "11-23"})
	l.door_add({"text": "umbrella"})
	var back := _list(path)
	back.load_file()
	var st2: Dictionary = back.status()
	_eq(
		[st2["agendas"].size(), st2["people"].size(), st2["door"]["notes"].size()],
		[1, 1, 1],
		"saved and read again: each in its own list"
	)
	_eq(st2["people"][0]["id"], made["body"]["id"], "the person is the same one")
	_eq(
		st2["people"][0]["todos"].map(func(x: Dictionary) -> String: return x["text"]),
		["send Sam the photos"],
		"and finds the old to-do"
	)
	_eq(
		[
			int(back.doc.get("future")["a"]),
			back.doc["agendas"][0].get("extra"),
			int(back.doc["things"][0].get("novel"))
		],
		[1, "kept", 7],
		"unknown keys are kept"
	)
	_wipe()
