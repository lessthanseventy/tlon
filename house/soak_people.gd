extends RefCounted

# The soak's checks of the people and the door: the frame and the tote in the room (their hits,
# marks and place, the layout's offer of the frame), the People and Door views over a stub that
# answers the routes as the server does, the calendar and Home's Today, and the house's own list
# behind the same views. The rules without a scene are `logic_people.gd`.
const Chores := preload("res://chores.gd")
const Money := preload("res://money.gd")
const People := preload("res://people.gd")
const PetThings := preload("res://pet_things.gd")
const BackendLocal := preload("res://backend_local.gd")
const Blocks := preload("res://blocks.gd")
const When := preload("res://when.gd")
const SAM := "11-23"

var s
var main
var h
var sb
var _next := 700


func _init(soak, the_main) -> void:
	s = soak
	main = the_main
	h = main._room.home
	sb = main._sidebar


func people() -> void:
	_start()
	await _frame()
	await _view()
	await _notes()
	await _form()
	await _calendar()
	await _today()
	await _offered()
	_old_cell()
	await _moved()
	await _local()


func door() -> void:
	_start()
	await _tote()
	await _pile()
	await _local_door()


func _start() -> void:
	for t in main.get_children().filter(
		func(n: Node) -> bool: return n is Timer and n.wait_time == main.POLL_SECONDS
	):
		t.stop()
	h.fake_day = "11-18"
	sb.back()
	s.stub = Callable(self, "answer")
	s._state["people"] = [
		_person(
			61, "Sam", SAM, ["a green kettle", "wants a scarf"], [_todo(31, "send Sam the photos")]
		),
		_person(62, "Jude", "2000-12-30"),
		_person(63, "Robyn", null),
	]
	s._state["door"] = {"id": null, "notes": []}


func _id() -> int:
	_next += 1
	return _next


func _todo(id: int, text: String) -> Dictionary:
	return {"id": id, "kind": "todo", "text": text, "due_at": null, "every": null}


func _person(
	id: int, name: String, birthday: Variant, notes: Array = [], todos: Array = []
) -> Dictionary:
	var rows: Array = []
	for n in notes:
		rows.append({"id": id * 10 + rows.size() + 1, "text": n, "since": "2026-11-17T10:00:00Z"})
	return {
		"id": id,
		"name": name,
		"birthday": birthday,
		"next_birthday": People.next_birthday(birthday, h.today()) if birthday != null else null,
		"notes": rows,
		"todos": todos,
	}


func _bad(line: String) -> Dictionary:
	return {"code": 400, "body": {"error": line}}


func _sorted() -> void:
	var people: Array = s._state["people"]
	var key := func(p: Dictionary) -> String:
		return str(p["next_birthday"]) if p["next_birthday"] != null else "9999"
	people.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return (
				key.call(a) < key.call(b) or (key.call(a) == key.call(b) and a["name"] < b["name"])
			)
	)


func _named(name: String, but: int = 0) -> bool:
	for p in s._state["people"]:
		if str(p["name"]).to_lower() == name.to_lower() and int(p["id"]) != but:
			return true
	return false


func _by_id(id: int) -> Dictionary:
	for p in s._state["people"]:
		if int(p["id"]) == id:
			return p
	return {}


func _by_name(name: String) -> Dictionary:
	for p in s._state["people"]:
		if p["name"] == name:
			return p
	return {}


# the routes as the server answers them: a person made, changed, given a note, dropped; a note put
# by the door; the to-dos that name a person go when one is done
func answer(method: String, path: String, body: Variant) -> Variant:
	if method != "POST":
		return null
	var b: Dictionary = body if body is Dictionary else {}
	var parts := path.split("/")
	if path == "/api/home/door/add":
		var text := str(b.get("text", "")).strip_edges()
		if text == "":
			return _bad("text is required")
		var pile: Dictionary = s._state["door"]
		if pile["id"] == null:
			pile["id"] = _id()
		var note := {"id": _id(), "text": text, "since": "2026-11-18T10:00:00Z"}
		pile["notes"].append(note)
		return {"code": 200, "body": {"id": note["id"], "text": text, "kind": "note"}}
	if path == "/api/home/agendas" and b.get("kind") == "person":
		var name := str(b.get("name", "")).strip_edges()
		if name == "":
			return _bad("name is required")
		if b.has("birthday") and not People.valid(b["birthday"]):
			return _bad("birthday must be MM-DD or YYYY-MM-DD")
		if b.has("every") or b.has("at"):
			return _bad("a person has no every or at")
		if _named(name):
			return _bad("there is already a person called " + name)
		var made := _person(_id(), name, b.get("birthday"))
		s._state["people"].append(made)
		_sorted()
		return {"code": 200, "body": made}
	if parts.size() == 6 and parts[3] == "agendas" and not _by_id(int(parts[4])).is_empty():
		var p := _by_id(int(parts[4]))
		match parts[5]:
			"edit":
				if b.has("name"):
					var name := str(b["name"]).strip_edges()
					if name == "":
						return _bad("name is required")
					if _named(name, int(p["id"])):
						return _bad("there is already a person called " + name)
					p["name"] = name
				if b.has("birthday"):
					if b["birthday"] != null and not People.valid(b["birthday"]):
						return _bad("birthday must be MM-DD or YYYY-MM-DD")
					p["birthday"] = b["birthday"]
					p["next_birthday"] = (
						People.next_birthday(b["birthday"], h.today())
						if b["birthday"] != null
						else null
					)
				_sorted()
				return {"code": 200, "body": p}
			"add":
				var text := str(b.get("text", "")).strip_edges()
				if text == "":
					return _bad("text is required")
				var note := {"id": _id(), "text": text, "since": "2026-11-18T10:00:00Z"}
				p["notes"].append(note)
				return {"code": 200, "body": note}
			"drop":
				s._state["people"].erase(p)
				return {"code": 200, "body": {"id": p["id"], "name": p["name"]}}
	if parts.size() == 5 and parts[4] == "done":
		for p in s._state["people"]:
			p["todos"] = p["todos"].filter(
				func(t: Dictionary) -> bool: return t["id"] != int(parts[3])
			)
	return null


func _sync() -> void:
	await s.process_frame
	await s.process_frame


func _poll() -> void:
	var before: int = s._count("/api/home")
	main._poll()
	await s._until(func(): return s._count("/api/home") > before, "the house is read again")
	await s._answered(main)
	await _sync()


func _texts(node: Node, out: Array = []) -> Array:
	for c in node.get_children():
		if c is Label:
			out.append(c.text)
		_texts(c, out)
	return out


func _row(node: Node, text: String) -> Variant:
	for c in node.get_children():
		if c is Blocks.Row and text in _texts(c):
			return c
		var r: Variant = _row(c, text)
		if r != null:
			return r
	return null


func _edit(placeholder: String) -> Variant:
	for e in sb._dyn.find_children("*", "LineEdit", true, false):
		if e.placeholder_text.begins_with(placeholder):
			return e
	return null


func _buttons(text: String) -> Array:
	return sb._dyn.find_children("*", "Button", true, false).filter(
		func(b: Button) -> bool: return b.text == text
	)


func _posted(path: String) -> Array:
	return s._log.filter(func(l: Array) -> bool: return l[0] == "POST" and l[1] == path)


func _centre(key: String) -> Variant:
	for hit in h._hits:
		if hit["key"] != key:
			continue
		var sum := Vector2.ZERO
		for p: Vector2 in hit["poly"]:
			sum += p
		var c: Vector2 = sum / maxf(1.0, hit["poly"].size())
		if h._topmost(c) == key:
			return c
	return null


func _hits(key: String) -> int:
	return h._hits.filter(func(hit: Dictionary) -> bool: return hit["key"] == key).size()


func _says(line: String) -> bool:
	return line in _texts(sb._dyn)


func _frame() -> void:
	await _poll()
	var piece: Dictionary = h.layout.frame()
	s._check(
		not piece.is_empty() and h.layout.kind(piece) == "wall", "the default layout has a frame"
	)
	s._check(
		piece["f"] == "ne" and Vector2i(piece["c"], piece["r"]) == Vector2i(10, 0),
		"hung on the north-east wall beside the bookshelf"
	)
	s._check(
		h.layout.footprint(piece) == Vector2i(1, 1) and h.layout.height(piece) < h.layout.TALL,
		"a one-cell piece shorter than the tall ones"
	)
	s._check(
		h.layout.rows()["furniture"].all(func(f: Array) -> bool: return f[0] != People.PIECE),
		"the room draws it in code, not as a sprite row"
	)
	s._check(not h.layout.entry(People.PIECE).is_empty(), "decorating lists it")
	var items: Array = h.items().filter(
		func(it: Dictionary) -> bool: return it["fn"] == Callable(h, "_draw_frame")
	)
	s._check(
		items.size() == 1 and items[0]["key"] == float(h.layout.draw_key(piece)),
		"it is drawn at its own depth"
	)
	for day in ["11-16", "11-17", "11-18"]:
		h.fake_day = day
		s._check(h.frame_marked(), "a birthday on 23 Nov marks the frame on %s" % day)
	for day in ["11-14", "11-15"]:
		h.fake_day = day
		s._check(not h.frame_marked(), "and not on %s, over a week off" % day)
	h.fake_day = "11-23"
	s._check(h.frame_marked(), "the day itself marks it")
	h.fake_day = "11-24"
	s._check(not h.frame_marked(), "the day after it does not")
	h.fake_day = "11-18"
	await s._until(func() -> bool: return _centre("frame") != null, "the frame has a hit")
	var at: Variant = _centre("frame")
	if at == null:
		return
	h.hover(at)
	s._check(
		h._hover == "frame" and h._name_of("frame") == "the people", "the pointer is on the people"
	)
	h.click(at)
	await s._until(func() -> bool: return sb.view == "people", "a click on the frame opens People")
	s._check(
		h.selected == "frame" and sb.selected_key() == "frame",
		"the frame is outlined while it is open"
	)
	s._check(h.card.kind == "", "and no card")
	sb.back()
	h.selected = ""


func _view() -> void:
	sb.open_people()
	await _sync()
	var texts := _texts(sb._dyn)
	var next := People.next_birthday(SAM, h.today())
	for want in ["Sam", "Jude", "Robyn", "a green kettle", "wants a scarf", "send Sam the photos"]:
		s._check(want in texts, "People shows %s: %s" % [want, str(texts)])
	s._check(When.birthday(5, next) in texts, "Sam's birthday is in words: %s" % str(texts))
	s._check(
		texts.find("Sam") < texts.find("Jude") and texts.find("Jude") < texts.find("Robyn"),
		"the soonest first, none last"
	)
	s._check(
		_buttons("edit").size() == 3 and _buttons("drop").size() == 2,
		"an edit each, a drop for each note"
	)
	s._check(
		_edit("add a note") != null and _buttons("Add a person").size() == 1,
		"an add line and Add a person"
	)
	s._check(
		sb.get_global_rect().size.x <= sb.WIDTH + 0.5, "the view keeps the pane %d wide" % sb.WIDTH
	)
	sb.back()


func _notes() -> void:
	sb.open_people()
	await _sync()
	_edit("add a note").text_submitted.emit("likes tea")
	await s._until(
		func() -> bool: return _posted("/api/home/agendas/61/add").size() == 1, "the note is posted"
	)
	s._check(
		JSON.parse_string(_posted("/api/home/agendas/61/add")[0][2]) == {"text": "likes tea"},
		"as a text"
	)
	await s._until(func() -> bool: return _says("likes tea"), "the note is on the card")
	_edit("add a note").text_submitted.emit("   ")
	await _sync()
	s._check(_posted("/api/home/agendas/61/add").size() == 1, "a blank line posts nothing")
	_buttons("drop")[0].pressed.emit()
	await s._until(
		func() -> bool: return _posted("/api/home/611/drop").size() == 1,
		"the note's drop is posted"
	)
	await s._until(func() -> bool: return not _says("a green kettle"), "and it leaves the card")
	s._check(_posted("/api/home/611/done").is_empty(), "a note comes off with drop, never done")
	var todo: Variant = _row(sb._dyn, "send Sam the photos")
	s._check(todo != null, "Sam's to-do is a row")
	if todo != null:
		todo.ticked.emit()
		await s._until(
			func() -> bool: return _posted("/api/home/31/done").size() == 1,
			"its tick is posted as done"
		)
		await s._until(
			func() -> bool: return not _says("send Sam the photos"), "and it leaves the card"
		)
	sb.back()


func _form() -> void:
	sb.open_people()
	await _sync()
	_buttons("Add a person")[0].pressed.emit()
	await _sync()
	var name: Variant = _edit("name")
	var birth: Variant = _edit("birthday")
	s._check(name != null and birth != null, "the form has a name and a birthday")
	s._check(_says("No birthday set."), "and says there is none yet")
	name.text_changed.emit("")
	_buttons("Add")[0].pressed.emit()
	await _sync()
	s._check(
		_says("A name, please.") and _posted("/api/home/agendas").is_empty(),
		"no name: said, nothing posted"
	)
	name = _edit("name")
	name.text = "Pam"
	name.text_changed.emit("Pam")
	birth = _edit("birthday")
	birth.text = "31 June"
	birth.text_changed.emit("31 June")
	s._check(
		_says("That is not a day. Try 8 June or 06-08."), "a birthday that is not a day says so"
	)
	_buttons("Add")[0].pressed.emit()
	await _sync()
	s._check(_posted("/api/home/agendas").is_empty(), "and is not posted")
	birth.text = "8 June"
	birth.text_changed.emit("8 June")
	s._check(_says("Kept as 8 June."), "a day says what it was read as")
	_buttons("Add")[0].pressed.emit()
	await s._until(
		func() -> bool: return _posted("/api/home/agendas").size() == 1, "the person is posted"
	)
	s._check(
		(
			JSON.parse_string(_posted("/api/home/agendas")[0][2])
			== {"name": "Pam", "kind": "person", "birthday": "06-08"}
		),
		"as a person with a birthday"
	)
	await s._until(
		func() -> bool: return _says("Pam") and _edit("name") == null,
		"Pam is on a card and the form is closed"
	)
	_buttons("Add a person")[0].pressed.emit()
	await _sync()
	name = _edit("name")
	name.text = "pam"
	name.text_changed.emit("pam")
	_buttons("Add")[0].pressed.emit()
	await s._until(
		func() -> bool: return _says("there is already a person called pam"),
		"a name taken is said as the server says it"
	)
	s._check(
		_edit("name") != null and s._state["people"].size() == 4,
		"the form stays and nobody is added"
	)
	_buttons("Cancel")[0].pressed.emit()
	await _sync()
	s._check(
		_edit("name") == null and not _says("there is already a person called pam"),
		"Cancel closes it"
	)
	var pam: int = int(_by_name("Pam")["id"])
	_buttons("edit")[2].pressed.emit()
	await _sync()
	s._check(
		(
			(_edit("name") as LineEdit).text == "Pam"
			and (_edit("birthday") as LineEdit).text == "8 June"
		),
		"edit has the name and the birthday as they are"
	)
	name = _edit("name")
	name.text = "Pamela"
	name.text_changed.emit("Pamela")
	_buttons("Save")[0].pressed.emit()
	await s._until(
		func() -> bool: return _posted("/api/home/agendas/%d/edit" % pam).size() == 1,
		"the edit is posted"
	)
	s._check(
		JSON.parse_string(_posted("/api/home/agendas/%d/edit" % pam)[0][2]) == {"name": "Pamela"},
		"only the name, the birthday untouched"
	)
	await s._until(func() -> bool: return _says("Pamela"), "the card says Pamela")
	_buttons("edit")[2].pressed.emit()
	await _sync()
	birth = _edit("birthday")
	birth.text = ""
	birth.text_changed.emit("")
	_buttons("Save")[0].pressed.emit()
	await s._until(
		func() -> bool: return _posted("/api/home/agendas/%d/edit" % pam).size() == 2,
		"the second edit is posted"
	)
	s._check(
		(
			JSON.parse_string(_posted("/api/home/agendas/%d/edit" % pam)[1][2])
			== {"name": "Pamela", "birthday": null}
		),
		"an emptied birthday is null"
	)
	await s._until(
		func() -> bool: return _by_id(pam)["birthday"] == null and _edit("name") == null,
		"it is cleared and the form closed"
	)
	_buttons("edit")[2].pressed.emit()
	await _sync()
	s._check(_buttons("Remove").size() == 1, "an edit has Remove")
	_buttons("Remove")[0].pressed.emit()
	await _sync()
	s._check(
		(
			_posted("/api/home/agendas/%d/drop" % pam).is_empty()
			and _buttons("Remove for good?").size() == 1
		),
		"the first press asks again"
	)
	_buttons("Remove for good?")[0].pressed.emit()
	await s._until(
		func() -> bool: return _posted("/api/home/agendas/%d/drop" % pam).size() == 1,
		"the second press drops"
	)
	await s._until(func() -> bool: return not _says("Pamela"), "and the card is gone")
	s._check(_by_id(pam).is_empty(), "the server has dropped them")
	sb.back()
	s._state["people"] = []
	await _poll()
	sb.open_people()
	await _sync()
	s._check(
		_says("No one yet. Add a name, and a birthday if you know it.") and _edit("name") != null,
		"with no one there is a line and the form"
	)
	sb.back()
	s._state["people"] = [
		_person(61, "Sam", SAM, ["a green kettle"]), _person(62, "Jude", "2000-12-30")
	]
	await _poll()


func _calendar() -> void:
	h.card.open("calendar", "cal")
	h.things.reset()
	var blocks: Array = h.things.calendar_blocks()
	var month: Dictionary = blocks.filter(func(b: Dictionary) -> bool: return b["t"] == "month")[0]
	var day := int(SAM.substr(3))
	s._check(
		month["birthday_marks"] == {day: true},
		"the month marks Sam's day: %s" % str(month["birthday_marks"])
	)
	h.things.day = day
	var line := "Sam's birthday"
	s._check(_listed(line), "the day's list says it")
	h.things.day = day - 1
	s._check(not _listed(line), "and another day does not")
	h.things.day = 0
	h.close_card()


func _today() -> void:
	var box := VBoxContainer.new()
	var texts: Array = []
	for day in ["11-22", "11-23", "11-24"]:
		h.fake_day = day
		for p in s._state["people"]:
			p["next_birthday"] = People.next_birthday(p["birthday"], h.today())
		await _poll()
		box = VBoxContainer.new()
		sb._views.home_view(box)
		texts = _texts(box)
		box.free()
		s._check(
			("Sam's birthday" in texts) == (day == "11-23"),
			"Today has Sam's birthday on the day only (%s): %s" % [day, str(texts)]
		)
	h.fake_day = "11-23"
	for p in s._state["people"]:
		p["next_birthday"] = People.next_birthday(p["birthday"], h.today())
	await _poll()
	sb.back()
	await _sync()
	var row: Variant = _row(sb._dyn, "Sam's birthday")
	s._check(row != null, "the row is on Home")
	if row != null:
		row.pressed.emit()
		await _sync()
		s._check(sb.view == "people", "and opens People")
	sb.back()
	h.fake_day = "11-18"
	for p in s._state["people"]:
		p["next_birthday"] = People.next_birthday(p["birthday"], h.today())
	await _poll()


# a saved layout from before the frame is offered it once: at its cell, else the nearest free one
func _offered() -> void:
	var path := "user://soak_people_layout.json"
	var rows: Array = (
		s
		. Layout
		. DEFAULTS
		. filter(func(r: Array) -> bool: return r[0] != People.PIECE)
		. map(func(r: Array) -> Dictionary: return {"p": r[0], "f": r[1], "c": r[2], "r": r[3]})
	)
	var home: Array = s.Layout.DEFAULTS.filter(func(r: Array) -> bool: return r[0] == People.PIECE)[0]
	s._write_layout(path, {"v": 2, "wall": "wallpaper", "floor": "oak", "pieces": rows})
	var l: RefCounted = s._layout()
	l.path = path
	l.persist = true
	s._check(l.load_file(), "the old layout loads")
	var frame: Dictionary = l.frame()
	s._check(
		not frame.is_empty() and frame["c"] == home[2] and frame["r"] == home[3],
		"it gains the frame at its cell: %s" % frame
	)
	s._check(
		l.pieces.size() == rows.size() + 1 and People.PIECE in s._read_layout(path)["offered"],
		"and the file says it was offered"
	)
	l.remove(frame)
	l.save()
	var back: RefCounted = s._layout()
	back.path = path
	back.persist = true
	s._check(back.load_file() and back.frame().is_empty(), "taken out, it stays out")
	s._check(People.PIECE in s._read_layout(path)["offered"], "and is still on record")
	var blocked: Array = rows.duplicate()
	blocked.append({"p": "painting", "f": "ne", "c": home[2], "r": home[3]})
	s._write_layout(path, {"v": 2, "wall": "wallpaper", "floor": "oak", "pieces": blocked})
	var near: RefCounted = s._layout()
	near.path = path
	near.persist = true
	s._check(near.load_file(), "a layout with the cell taken loads")
	s._check(near.frame().is_empty(), "no other wall cell is free, so there is no frame")
	DirAccess.remove_absolute(path)


# a layout saved before the frame, the basket and the piggy bank moved to their current default
# places: one on an old default cell goes to the current one once when that is free, one the owner
# put anywhere else stays, and a layout saved now is not moved again
func _old_cell() -> void:
	var path := "user://soak_people_old_cell.json"
	var keys: Array = s.Layout.NEWER
	var base: Array = []
	for row in s.Layout.DEFAULTS:
		if row[0] not in keys:
			base.append({"p": row[0], "f": row[1], "c": row[2], "r": row[3]})
	var plant := {"p": "plant_small", "f": "", "c": 0, "r": 10}
	var cases := {
		People.PIECE:
		{
			"old": [Vector2i(3, 7), Vector2i(5, 3)],
			"hand": [Vector2i(0, 0), "ne"],
			"taken": {"p": "painting", "f": "ne", "c": 10, "r": 0},
		},
		Chores.PIECE:
		{
			"old": [Vector2i(1, 1)],
			"hand": [Vector2i(6, 9), ""],
			"taken": plant,
		},
		Money.PIECE:
		{
			"old": [Vector2i(6, 4)],
			"hand": [Vector2i(6, 9), ""],
			"taken": {"p": "plant_small", "f": "", "c": 5, "r": 8},
		},
	}
	for key in cases:
		var want: Dictionary = cases[key]
		var row: Array = s.Layout.DEFAULTS.filter(func(r: Array) -> bool: return r[0] == key)[0]
		var home := Vector2i(row[2], row[3])
		for old: Vector2i in want["old"]:
			s._check(old != home, "%s: the default is no longer %s" % [key, old])
			var l := _old_layout(path, 3, base, {"p": key, "f": "", "c": old.x, "r": old.y})
			s._check(_cell_of(l, key) == home, "%s on %s goes to %s" % [key, old, home])
		var by_hand: Array = want["hand"]
		var clear: Array = base.filter(
			func(r: Dictionary) -> bool: return r["p"] != "painting" or key != People.PIECE
		)
		var l := _old_layout(
			path, 3, clear, {"p": key, "f": by_hand[1], "c": by_hand[0].x, "r": by_hand[0].y}
		)
		s._check(_cell_of(l, key) == by_hand[0], "%s put at %s by hand stays" % [key, by_hand[0]])
		var old: Vector2i = want["old"][0]
		var at := {"p": key, "f": "", "c": old.x, "r": old.y}
		l = _old_layout(path, 3, [want["taken"]] + base, at)
		var landed := _cell_of(l, key)
		if key == People.PIECE:
			s._check(
				l.frame().is_empty(),
				"%s with its new cell taken and no wall cell free is out" % key
			)
		else:
			s._check(
				landed == old, "%s on %s with the new cell taken stays: %s" % [key, old, landed]
			)
		l = _old_layout(path, s.Layout.SAVED, base, at)
		if key == People.PIECE:
			s._check(l.frame().is_empty(), "%s: a current layout is not given one again" % key)
		else:
			s._check(_cell_of(l, key) == old, "%s: a current layout is not moved again" % key)
	var saved := _old_layout(path, 3, base, {"p": Chores.PIECE, "f": "", "c": 1, "r": 1})
	saved.save()
	s._check(
		s._read_layout(path)["v"] == s.Layout.SAVED, "the layout is saved as the current version"
	)
	DirAccess.remove_absolute(path)


func _old_layout(path: String, v: int, rows: Array, piece: Dictionary) -> RefCounted:
	(
		s
		. _write_layout(
			path,
			{
				"v": v,
				"wall": "wallpaper",
				"floor": "oak",
				"offered": s.Layout.NEWER,
				"pieces": rows + [piece],
			}
		)
	)
	var l: RefCounted = s._layout()
	l.path = path
	l.persist = true
	s._check(l.load_file(), "a version %d layout with %s loads" % [v, piece["p"]])
	return l


func _cell_of(l: RefCounted, key: String) -> Vector2i:
	for p in l.pieces:
		if p["p"] == key:
			return Vector2i(p["c"], p["r"])
	return Vector2i(-1, -1)


# the frame is movable: it draws and clicks by where it stands, not where it began
func _moved() -> void:
	var piece: Dictionary = h.layout.frame()
	var home := [piece["c"], piece["r"]]
	var last: Variant = _centre("frame")
	var painting: Dictionary = {}
	for p in h.layout.pieces:
		if p["p"] == "painting" and p["f"] == "ne" and p["c"] == 0:
			painting = p
	var hung := painting.duplicate()
	h.layout.remove(painting)
	for cell in [Vector2i(0, 0)]:
		var why: String = h.layout.place(
			{"p": People.PIECE, "f": "ne", "c": cell.x, "r": cell.y}, piece, []
		)
		s._check(why == "", "the frame can stand at %s: %s" % [cell, why])
		var entry: Dictionary = {}
		for it in h.items():
			if it["fn"] == Callable(h, "_draw_frame"):
				entry = it
		s._check(
			not entry.is_empty() and entry["key"] == float(h.layout.draw_key(piece)),
			"at %s it is drawn at its own depth (%s)" % [cell, entry.get("key")]
		)
		var from: Variant = last
		await s._until(
			func() -> bool:
				var at: Variant = _centre("frame")
				return at != null and at != from,
			"at %s its hit moves there and is on top" % cell
		)
		last = _centre("frame")
		sb.back()
		h.click(last)
		await s._until(
			func() -> bool: return sb.view == "people", "a click at %s opens People" % cell
		)
		sb.back()
	h.layout.place({"p": People.PIECE, "f": "ne", "c": home[0], "r": home[1]}, piece, [])
	h.layout.place(hung, null, [])


# the house's own list keeps people the same way: a person, a note, a to-do that names them
func _local() -> void:
	s.stub = Callable()
	var plain := BackendLocal.new()
	plain.setup("", Callable(h, "_now_local"), h._bias(), false)
	main._install(plain)
	main._write("/api/home/agendas", {"name": "Sam", "kind": "person", "birthday": SAM})
	main._write("/api/home/add", {"kind": "todo", "text": "send Sam the photos"})
	await s._answered(main)
	main._poll()
	await s._answered(main)
	await _sync()
	s._check(
		h.things.people.size() == 1 and h.frame_marked(),
		"the local list has a person and the frame is marked"
	)
	var sam: Dictionary = h.things.people[0]
	s._check(sam["next_birthday"] == People.next_birthday(SAM, h.today()), "with the next birthday")
	s._check(
		(
			sam["todos"].map(func(t: Dictionary) -> String: return t["text"])
			== ["send Sam the photos"]
		),
		"and the to-do that names them"
	)
	main._write("/api/home/agendas/%d/add" % int(sam["id"]), {"text": "likes tea"})
	await s._answered(main)
	main._poll()
	await s._answered(main)
	sb.open_people()
	await _sync()
	s._check(
		_says("Sam") and _says("likes tea") and _says("send Sam the photos"), "People shows them"
	)
	_buttons("drop")[0].pressed.emit()
	await s._answered(main)
	main._poll()
	await s._answered(main)
	await _sync()
	s._check(not _says("likes tea"), "a note is dropped there too")
	_buttons("edit")[0].pressed.emit()
	await _sync()
	_buttons("Remove")[0].pressed.emit()
	await _sync()
	_buttons("Remove for good?")[0].pressed.emit()
	await s._answered(main)
	main._poll()
	await s._answered(main)
	await _sync()
	s._check(h.things.people.is_empty() and not h.frame_marked(), "a person removed leaves no mark")
	sb.back()


func _tote() -> void:
	await _poll()
	s._check(People.door_state(h.things.door) == "none", "the pile starts empty")
	s._check(_hits("door") == 1, "the door is a hit and no tote stands by it")
	await s._until(func() -> bool: return _centre("door") != null, "the door has a hit")
	var at: Variant = _centre("door")
	if at == null:
		return
	h.hover(at)
	s._check(h._hover == "door" and h._name_of("door") == "the door", "the pointer is on the door")
	h.click(at)
	await s._until(
		func() -> bool: return sb.view == "door", "a click on the door opens the door view"
	)
	await _sync()
	s._check(
		h.selected == "door" and sb.selected_key() == "door",
		"the door is outlined while it is open"
	)
	s._check(_says("Nothing by the door."), "an empty pile says so")
	s._check(h.card.kind == "", "and no card")
	sb.back()
	h.selected = ""
	s._state["door"] = {
		"id": 90, "notes": [{"id": 901, "text": "umbrella", "since": "2026-11-18T10:00:00Z"}]
	}
	await _poll()
	s._check(
		People.door_state(h.things.door) == "some" and _hits("door") == 2,
		"a note puts the tote out, a hit of its own"
	)
	var items: Array = h.items().filter(
		func(it: Dictionary) -> bool: return it["fn"] == Callable(h, "_draw_tote")
	)
	s._check(items.size() == 1, "and it is drawn")
	var tote: Variant = _centre_of_tote()
	s._check(tote != null, "the tote can be clicked")
	if tote != null:
		h.click(tote)
		await s._until(
			func() -> bool: return sb.view == "door", "a click on the tote opens the door view"
		)
		sb.back()
	s._state["door"] = {"id": 90, "notes": []}
	await _poll()
	s._check(_hits("door") == 1, "an emptied pile takes the tote in")


# the hit that is not the wall's: the one over the cell the tote stands in
func _centre_of_tote() -> Variant:
	for hit in h._hits:
		if hit["key"] != "door":
			continue
		var sum := Vector2.ZERO
		for p: Vector2 in hit["poly"]:
			sum += p
		var c: Vector2 = sum / maxf(1.0, hit["poly"].size())
		if hit["poly"].size() != 4 and h._topmost(c) == "door" and c.y > h._p(0, 7).y - 30.0 * h._k:
			return c
	return null


func _pile() -> void:
	s._state["door"] = {"id": null, "notes": []}
	await _poll()
	sb.open_door()
	await _sync()
	var edit: Variant = _edit("something to take")
	s._check(edit != null, "the view has an add line")
	edit.text_submitted.emit("umbrella")
	await s._until(
		func() -> bool: return _posted("/api/home/door/add").size() == 1, "the note is posted"
	)
	s._check(
		JSON.parse_string(_posted("/api/home/door/add")[0][2]) == {"text": "umbrella"}, "as a text"
	)
	await s._until(func() -> bool: return _says("umbrella"), "it is on the pile")
	s._check(_hits("door") == 2, "and the tote stands by the door")
	_edit("something to take").text_submitted.emit("  ")
	await _sync()
	s._check(_posted("/api/home/door/add").size() == 1, "a blank line posts nothing")
	_edit("something to take").text_submitted.emit("return the library books")
	await s._until(
		func() -> bool: return _says("return the library books"), "a second note is there"
	)
	var ticks: Array = sb._dyn.find_children("*", "Control", true, false).filter(
		func(c: Control) -> bool: return c is Blocks.Tick
	)
	s._check(ticks.size() == 2, "each note has a tick")
	var first: int = int(s._state["door"]["notes"][0]["id"])
	ticks[0].pressed.emit()
	await s._until(
		func() -> bool: return _posted("/api/home/%d/drop" % first).size() == 1,
		"a tick drops the note"
	)
	await s._until(func() -> bool: return not _says("umbrella"), "and it leaves the pile")
	s._check(_posted("/api/home/%d/done" % first).is_empty(), "a note is dropped, never done")
	s._check(_hits("door") == 2, "the tote stays while one is left")
	ticks = sb._dyn.find_children("*", "Control", true, false).filter(
		func(c: Control) -> bool: return c is Blocks.Tick
	)
	ticks[0].pressed.emit()
	await s._until(func() -> bool: return _says("Nothing by the door."), "the last tick empties it")
	await s._until(func() -> bool: return _hits("door") == 1, "and the tote goes in")
	main._write("/api/home/door/add", {"text": " "})
	await s._until(
		func() -> bool: return _says("text is required"), "a refusal is said in the view"
	)
	sb.back()


# the house's own list keeps the pile: a note, its drop, and the tote's mark
func _local_door() -> void:
	s.stub = Callable()
	var plain := BackendLocal.new()
	plain.setup("", Callable(h, "_now_local"), h._bias(), false)
	main._install(plain)
	main._poll()
	await s._answered(main)
	s._check(
		People.door_state(h.things.door) == "none", "the local list starts with nothing by the door"
	)
	main._write("/api/home/door/add", {"text": "umbrella"})
	await s._answered(main)
	main._poll()
	await s._answered(main)
	await _sync()
	s._check(
		(
			(
				h.things.door["notes"].map(func(n: Dictionary) -> String: return n["text"])
				== ["umbrella"]
			)
			and _hits("door") == 2
		),
		"a note is kept and the tote is out"
	)
	sb.open_door()
	await _sync()
	s._check(_says("umbrella"), "the view shows it")
	var ticks: Array = sb._dyn.find_children("*", "Control", true, false).filter(
		func(c: Control) -> bool: return c is Blocks.Tick
	)
	ticks[0].pressed.emit()
	await s._answered(main)
	main._poll()
	await s._answered(main)
	await _sync()
	s._check(_says("Nothing by the door.") and _hits("door") == 1, "a tick drops it there too")
	main._write("/api/home/door/add", {"text": " "})
	await s._answered(main)
	await s._until(
		func() -> bool: return _says("text is required"),
		"the list refuses a blank one as the server does"
	)
	sb.back()


func _listed(line: String) -> bool:
	return h.things.calendar_blocks().any(func(b: Dictionary) -> bool: return b.get("text") == line)
