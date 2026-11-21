extends RefCounted

# The soak's checks of the chores in the room: the room's hits (hover, click, outline), what leaves
# Home's lists, the basket's place and the layout's record of it, and Done over the demo, the
# server and the house's own list. The rules without a scene are `logic_chores.gd`.
const Chores := preload("res://chores.gd")
const PetThings := preload("res://pet_things.gd")
const BackendLocal := preload("res://backend_local.gd")
const THINGS := {
	"laundry": "do the laundry",
	"bins": "take the bins out",
	"bowls": "feed the cat",
	"pills": "take your meds",
	"plant": "water the plants",
}
const DAYS := ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

var s
var main
var h
var sb


func _init(soak, the_main) -> void:
	s = soak
	main = the_main
	h = main._room.home
	sb = main._sidebar


func run() -> void:
	main._busy = true
	h.settings.put("bowls", true)
	h.settings.put("pet_things", true)
	for c in h.pets.critters:
		c.away = false
	h.layout.reset(h.busy_cells())
	h.apply_layout()
	h.petlife.sync()
	await _room()
	_lists()
	_layout()
	await _moved()
	await _offered()
	await _done()
	await _wire()
	await _local()


func _iso(at: float) -> String:
	return Time.get_datetime_string_from_unix_time(int(at - h._bias())) + "Z"


func _row(id: int, text: String, due: float, every: Variant = "week") -> Dictionary:
	return {
		"id": id,
		"kind": "reminder",
		"text": text,
		"due_at": _iso(due),
		"every": every,
		"since": "2026-11-01T10:00:00Z",
		"told_at": null,
	}


# the day is Wednesday 18 Nov at 10:00 whatever the year
func _clock() -> float:
	h.fake_day = "11-18"
	h.fake_hour = 10.0
	return h._now_local()


func _centre(key: String) -> Variant:
	for hit in h._hits:
		if hit["key"] != key:
			continue
		var sum := Vector2.ZERO
		for p: Vector2 in hit["poly"]:
			sum += p
		for t in [0.0, 0.25, 0.5, 0.75]:
			var at: Vector2 = sum / maxf(1.0, hit["poly"].size())
			for p: Vector2 in hit["poly"]:
				var q := at.lerp(p, t)
				if h._topmost(q) == key:
					return q
	return null


func _texts(node: Node, out: Array = []) -> Array:
	for c in node.get_children():
		if c is Label:
			out.append(c.text)
		_texts(c, out)
	return out


func _home_texts() -> Array:
	var box := VBoxContainer.new()
	sb._views.home_view(box)
	var out := _texts(box)
	box.free()
	return out


# each thing in each state from the clock, and its hit, its name and the click
func _room() -> void:
	var now := _clock()
	var day := floorf(now / 86400.0) * 86400.0
	sb.back()
	h.petlife.sync()
	for p in h.layout.pet_pieces():
		if PetThings.key_of(p) == "bowls":
			p["own"] = true
	for c in h.pets.critters:
		if c.id != "person":
			c.away = true
	var dues := {"fine": now + 6 * 86400.0, "soon": now + 3 * 86400.0, "due": day + 18 * 3600.0}
	h.open = []
	h.coming = []
	var id := 100
	for thing in THINGS:
		s._check(h.chore_present(thing), "%s is in the default room" % thing)
		s._check(h.chore_state(thing) == "", "%s shows nothing with no chore" % thing)
		for state in Chores.STATES:
			id += 1
			h.open = []
			h.coming = [_row(id, THINGS[thing], dues[state])]
			s._check(
				h.chore_state(thing) == state,
				"%s: %s from the clock, not '%s'" % [thing, state, h.chore_state(thing)]
			)
			var key: String = h.chore_hit(thing)
			await s._until(
				func() -> bool: return _centre(key) != null, "%s has a hit (%s)" % [thing, state]
			)
			var at: Variant = _centre(key)
			if at == null:
				continue
			h.hover(at)
			s._check(h._hover == key, "the pointer is on %s" % key)
			var words: String = h._name_of(key)
			s._check(
				words == Chores.hover(thing, state, dues[state], now) and words.contains(" · "),
				"%s says %s: '%s'" % [thing, state, words]
			)
			if state == "due":
				s._check(
					words.ends_with("due today"), "%s due today says so: '%s'" % [thing, words]
				)
			if state == "fine":
				var due_day: String = DAYS[
					Time.get_datetime_dict_from_unix_time(int(dues[state]))["weekday"]
				]
				s._check(
					words.ends_with(due_day), "%s far off says the weekday: '%s'" % [thing, words]
				)
			sb.back()
			h.click(at)
			var opened := id
			await s._until(
				func() -> bool: return sb.view == "item" and int(sb.arg) == opened,
				"a click on %s opens that chore's item view (%s)" % [thing, state]
			)
			s._check(h.card.kind == "", "and no card")
			s._check(
				h.selected == key and sb.selected_key() == key,
				"%s is outlined while its view is open" % thing
			)
			sb.back()
	h.open = []
	h.coming = []
	for thing in THINGS:
		s._check(h.chore_state(thing) == "", "%s shows nothing again with no chore" % thing)
	for c in h.pets.critters:
		c.away = false
	h.selected = ""


# a chore is in the room or in the lists, never both; two for one thing: the more urgent is the thing
func _lists() -> void:
	var now := _clock()
	var day := floorf(now / 86400.0) * 86400.0
	sb.back()
	h.things.pick = {}
	h.meetings = []
	h.open = [
		_row(20, "do the laundry", now - 2 * 86400.0),
		_row(21, "take the bins out", now - 86400.0),
		{"id": 22, "kind": "todo", "text": "buy milk", "due_at": null, "every": null},
	]
	h.coming = [
		_row(23, "laundry: sheets", day + 20 * 3600.0, "2 week"),
		_row(24, "wash the laundry on Sunday", now + 4 * 86400.0),
		_row(25, "put the bins out", now + 5 * 86400.0),
		_row(26, "dentist next week", now + 7 * 86400.0, null),
		_row(27, "stretch", day + 19 * 3600.0, null),
	]
	var texts := _home_texts()
	s._check("buy milk" in texts, "a to-do stays in Open")
	s._check(
		not ("do the laundry" in texts) and not ("take the bins out" in texts),
		"a chore in the room is not in Open: %s" % str(texts)
	)
	s._check(
		"laundry: sheets" in texts and "Today" in texts,
		"the second laundry chore stays in Today: %s" % str(texts)
	)
	s._check("stretch" in texts, "a reminder that does not repeat stays in Today")
	s._check(
		h.chore_thing_of(20) == "laundry" and h.chore_thing_of(23) == "",
		"the more urgent is the thing"
	)
	s._check(
		h.chore_thing_of(21) == "bins" and h.chore_thing_of(25) == "",
		"and the one due later is not"
	)
	sb.later_expanded = true
	texts = _home_texts()
	sb.later_expanded = false
	s._check(
		"wash the laundry on Sunday" in texts and "dentist next week" in texts,
		"the others are in Later: %s" % str(texts)
	)
	s._check("put the bins out" in texts, "the second bins row is a list row")
	h.card.open("calendar", "cal")
	h.things.reset()
	var blocks := str(h.things.calendar_blocks())
	h.close_card()
	s._check(blocks.contains("laundry"), "the calendar card still shows the chore")
	var box := VBoxContainer.new()
	sb._views.item_view(box, 20)
	var item := _texts(box)
	box.free()
	s._check("do the laundry" in item, "and so does its item view")
	var piece: Dictionary = h.layout.basket()
	h.layout.remove(piece)
	h.apply_layout()
	texts = _home_texts()
	s._check(
		not h.chore_present("laundry") and h.chore_thing_of(20) == "",
		"no basket: the laundry is not in the room"
	)
	s._check(
		"do the laundry" in texts and "laundry: sheets" in texts,
		"and its rows are in the lists again: %s" % str(texts)
	)
	s._check(not ("take the bins out" in texts), "the bins are still in the room")
	var put: String = h.layout.place(
		{"p": Chores.PIECE, "f": "", "c": piece["c"], "r": piece["r"]}, null, []
	)
	h.apply_layout()
	s._check(
		put == "" and h.chore_present("laundry"), "the basket put back is in the room: '%s'" % put
	)
	texts = _home_texts()
	s._check(not ("do the laundry" in texts), "and the row leaves the lists")
	h.open = []
	h.coming = []


func _layout() -> void:
	var piece: Dictionary = h.layout.basket()
	s._check(
		not piece.is_empty() and h.layout.kind(piece) == "floor", "the default layout has a basket"
	)
	s._check(
		h.layout.footprint(piece) == Vector2i(1, 1) and h.layout.height(piece) <= h.layout.LOW,
		"a small piece"
	)
	s._check(
		h.layout.rows()["furniture"].all(func(f: Array) -> bool: return f[0] != Chores.PIECE),
		"the room draws it in code, not as a sprite row"
	)
	s._check(not h.layout.entry(Chores.PIECE).is_empty(), "decorating lists it")
	s._check(
		Vector2i(piece["c"], piece["r"]) == Vector2i(0, 10), "by default it is in the piano's corner"
	)
	s._check(
		not h.layout.in_front().has(Vector2i(piece["c"], piece["r"])),
		"on no piece's approach cell"
	)
	var wall: Dictionary = {"p": Chores.PIECE, "f": "", "c": 6, "r": 0}
	s._check(h.layout.check(wall, piece, []) != "", "it does not go on the bin")
	var again := {"p": Chores.PIECE, "f": "", "c": 8, "r": 9}
	s._check(h.layout.check(again, piece, []) == "", "it can be moved to free floor")


# the basket is movable: it draws and clicks by where it stands, not where it began
func _moved() -> void:
	var piece: Dictionary = h.layout.basket()
	var home := [piece["c"], piece["r"]]
	h.open = []
	h.coming = [_row(201, THINGS["laundry"], _clock() + 3 * 86400.0)]
	var chair: Dictionary = {}
	for p in h.layout.pieces:
		if p["p"] == "dining_chair" and p["c"] == 5:
			chair = p
	var last: Variant = null
	for cell in [Vector2i(6, 9), Vector2i(3, 9)]:
		var why: String = h.layout.place(
			{"p": Chores.PIECE, "f": "", "c": cell.x, "r": cell.y}, piece, []
		)
		s._check(why == "", "the basket can stand at %s: %s" % [cell, why])
		var entry: Dictionary = {}
		for it in h.items():
			if it["fn"] == Callable(h, "_draw_chore_basket"):
				entry = it
		s._check(
			not entry.is_empty() and entry["key"] == float(h.layout.draw_key(piece)),
			"at %s it is drawn at its own depth (%s)" % [cell, entry.get("key")]
		)
		s._check(
			(entry["key"] > float(h.layout.draw_key(chair))) == (cell.x > chair["c"]),
			"and in order with the chair beside it"
		)
		var from: Variant = last
		await s._until(
			func() -> bool:
				var at: Variant = _centre("chore:laundry")
				return at != null and at != from,
			"at %s its hit moves there and is on top" % cell
		)
		last = _centre("chore:laundry")
		sb.back()
		h.click(last)
		await s._until(
			func() -> bool: return sb.view == "item" and int(sb.arg) == 201,
			"a click at %s opens its chore" % cell
		)
		sb.back()
	h.layout.place({"p": Chores.PIECE, "f": "", "c": home[0], "r": home[1]}, piece, [])
	h.open = []
	h.coming = []


# a saved layout from before the basket is offered it once: at its cell, else the nearest free one
func _offered() -> void:
	var path := "user://soak_chores_layout.json"
	var rows: Array = (
		s
		. Layout
		. DEFAULTS
		. filter(func(r: Array) -> bool: return r[0] != Chores.PIECE)
		. map(func(r: Array) -> Dictionary: return {"p": r[0], "f": r[1], "c": r[2], "r": r[3]})
	)
	s._write_layout(path, {"v": 2, "wall": "wallpaper", "floor": "oak", "pieces": rows})
	var l: RefCounted = s._layout()
	l.path = path
	l.persist = true
	s._check(l.load_file(), "the old layout loads")
	var basket: Dictionary = l.basket()
	s._check(
		not basket.is_empty() and basket["c"] == 0 and basket["r"] == 10,
		"it gains the basket at its cell"
	)
	s._check(
		l.pieces.size() == rows.size() + 1 and Chores.PIECE in s._read_layout(path)["offered"],
		"and the file says it was offered"
	)
	l.remove(basket)
	l.save()
	var back: RefCounted = s._layout()
	back.path = path
	back.persist = true
	s._check(back.load_file() and back.basket().is_empty(), "taken out, it stays out")
	s._check(Chores.PIECE in s._read_layout(path)["offered"], "and is still on record")
	var blocked: Array = rows.duplicate()
	blocked.append({"p": "plant_small", "f": "", "c": 0, "r": 10})
	s._write_layout(path, {"v": 2, "wall": "wallpaper", "floor": "oak", "pieces": blocked})
	var near: RefCounted = s._layout()
	near.path = path
	near.persist = true
	s._check(near.load_file(), "a layout with the cell taken loads")
	var spot: Dictionary = near.basket()
	var apart: int = absi(spot.get("c", 99) - 0) + absi(spot.get("r", 99) - 10)
	s._check(
		not spot.is_empty() and apart == 1, "the basket goes to the nearest free cell: %s" % spot
	)
	DirAccess.remove_absolute(path)


# an unreadable or zero rhythm is no chore: its row stays in the lists, and Done in the demo
# neither moves it on nor loops
func _no_rhythm() -> void:
	var now := _clock()
	h.open = []
	h.coming = [_row(301, "do the laundry", floorf(now / 86400.0) * 86400.0 + 18 * 3600.0, "0 week")]
	s._check(h.chore_state("laundry") == "", "a zero rhythm is no chore")
	s._check("do the laundry" in _home_texts(), "and its row stays in the lists")
	h.coming = [_row(302, "do the laundry", now + 86400.0, "whenever")]
	s._check(h.chore_state("laundry") == "", "nor one that does not read")
	main._demo = true
	var data: Dictionary = main._data.duplicate(true)
	data["open"] = [_row(303, "do the laundry", now - 86400.0, "0 day")]
	data["coming"] = []
	main._apply(data)
	main._act(303, "done")
	s._check(
		main._data["coming"].all(func(t: Dictionary) -> bool: return int(t["id"]) != 303),
		"Done in the demo on a zero rhythm just ticks it off"
	)
	main._demo = false
	h.open = []
	h.coming = []


# Done through the same path a ticked item takes: the thing moves to fine with a moment of its own
func _done() -> void:
	await _no_rhythm()
	var now := _clock()
	var day := floorf(now / 86400.0) * 86400.0
	main._demo = true
	var data: Dictionary = main._data.duplicate(true)
	data["open"] = [
		_row(31, "take the bins out", now - 86400.0), _row(32, "water the plants", day + 3600.0)
	]
	data["coming"] = [
		_row(33, "do the laundry", now + 3 * 86400.0), _row(34, "take your meds", now + 6 * 86400.0)
	]
	main._apply(data)
	var week: int = int(main._data["done_week"])
	for thing in ["bins", "plant", "laundry", "pills"]:
		var before: String = h.chore_state(thing)
		s._check(
			before != "" and (before != "fine" or thing == "pills"),
			"%s starts %s" % [thing, before]
		)
	for id in [31, 32, 33, 34]:
		main._act(id, "done")
	s._check(h.chore_moment("bins") < 0.0, "the moment holds the old look at first")
	s._check(h.chore_state("bins") == "due", "the bin is as it was for the first beat")
	await s._until(
		func() -> bool: return h.chore_moment("bins") >= 0.0, "the bin's moment plays"
	)
	for thing in ["bins", "plant", "laundry", "pills"]:
		s._check(
			h.chore_state(thing) == "fine",
			"%s is fine after Done: '%s'" % [thing, h.chore_state(thing)]
		)
	s._check(int(main._data["done_week"]) == week + 4, "each Done drops a marble in the jar")
	var gone: Array = main._data["open"].filter(
		func(t: Dictionary) -> bool: return t["kind"] == "reminder"
	)
	s._check(gone.is_empty(), "a done chore left Open for its next time")
	var next: Array = main._data["coming"].filter(
		func(t: Dictionary) -> bool: return int(t["id"]) in [31, 32, 33, 34]
	)
	s._check(
		next.size() == 4 and next.all(func(t: Dictionary) -> bool: return h._due(t) > now),
		"each came back for its next time"
	)
	await s._until(
		func() -> bool: return h.chore_moment("bins") < 0.0, "the bin's moment ends"
	)
	s._check(h.chore_state("bins") == "fine", "the moment ends with the thing fine")
	main._demo = false
	h.open = []
	h.coming = []


# Done over a server: the thing keeps its look until the read after the write has come, whatever
# a read already on its way says, then plays its moment
func _wire() -> void:
	var now := _clock()
	for t in main.get_children().filter(
		func(n: Node) -> bool: return n is Timer and n.wait_time == main.POLL_SECONDS
	):
		t.stop()
	main._busy = false
	var before := _row(41, "take the bins out", now - 86400.0)
	var pills := _row(42, "take your meds", now + 6 * 86400.0)
	var after := _row(41, "take the bins out", now + 7 * 86400.0)
	var pills_after := _row(42, "take your meds", now + 13 * 86400.0)
	s.seed([before], [pills])
	main._poll()
	await s._until(func() -> bool: return h.chore_state("bins") == "due", "the bin starts due")

	s.hold_reads = true
	main._act(41, "done")
	s.seed([], [after, pills_after])
	await s._until(
		func() -> bool: return s._seen("POST", "/api/home/41/done") and s._held.size() == 1,
		"the write is answered and the read after it is asked"
	)
	s._check(h.chore_state("bins") == "due", "the thing waits for the read")
	await s._quiet(Chores.PAUSE + Chores.MOMENT)
	s._check(
		h.chore_state("bins") == "due" and h.chore_moment("bins") < 0.0,
		"a slow read leaves the bin as it was: '%s'" % h.chore_state("bins")
	)
	s._check(h.chore_thing_of(41) == "bins", "and the row stays out of the lists")
	s.release_reads()
	await s._until(
		func() -> bool: return h.chore_moment("bins") >= 0.0, "the read that has come starts it"
	)
	s._check(h.chore_state("bins") == "fine", "and the bin turns fine")
	await s._until(func() -> bool: return h.chore_moment("bins") < 0.0, "the moment ends")
	await s._quiet(Chores.MOMENT)
	s._check(h.chore_state("bins") == "fine", "and stays fine after it")

	s.hold_reads = false
	s.seed([before], [pills])
	main._poll()
	await s._until(
		func() -> bool: return h.chore_state("bins") == "due" and not main._busy,
		"the bin is due again"
	)
	s.hold_reads = true
	main._poll()
	await s._until(func() -> bool: return s._held.size() == 1, "a read is on its way")
	var writes: int = main._writes
	main._act(41, "done")
	s.seed([], [after, pills_after])
	await s._until(func() -> bool: return main._writes == writes + 1, "the write is answered")
	s.release_reads()
	await s._until(
		func() -> bool: return s._held.size() == 1, "the read after the write is asked for"
	)
	s._check(
		h.chore_state("bins") == "due" and h.chore_moment("bins") < 0.0,
		"a read from before the write does not end the wait: '%s'" % h.chore_state("bins")
	)
	s._check(h.chore_thing_of(41) == "bins", "nor puts the row back in the lists")
	await s._quiet(Chores.PAUSE + Chores.MOMENT)
	s._check(h.chore_state("bins") == "due", "and the bin keeps its look meanwhile")
	s.release_reads()
	await s._until(func() -> bool: return h.chore_moment("bins") >= 0.0, "then it plays")
	s._check(h.chore_state("bins") == "fine", "and turns fine for good")
	await s._until(func() -> bool: return h.chore_moment("bins") < 0.0, "the moment ends")
	await s._quiet(Chores.MOMENT)
	s._check(h.chore_state("bins") == "fine", "and never as due again")
	s.hold_reads = false


# the same over the house's own list: Done moves a repeating reminder on and the thing is fine
func _local() -> void:
	var now := _clock()
	var plain := BackendLocal.new()
	plain.setup("", Callable(h, "_now_local"), h._bias(), false)
	main._install(plain)
	var got: Array = []
	plain.send(
		"/api/home/add",
		{"kind": "reminder", "text": "do the laundry", "at": h.today() + "T18:00", "every": "week"},
		func(_r: bool, code: int, body: Variant) -> void: got.append([code, body])
	)
	await s._until(func() -> bool: return got.size() == 1, "the list answers the add")
	s._check(got[0][0] == 200, "the local list takes a repeating reminder")
	var id: int = int(got[0][1]["id"])
	main._poll()
	await s._until(
		func() -> bool: return h.chore_thing_of(id) == "laundry",
		"a repeating reminder in the local list stands for its thing"
	)
	s._check(h.chore_state("laundry") == "due", "due today: %s" % h.chore_state("laundry"))
	main._act(id, "done")
	await s._until(
		func() -> bool: return h.chore_moment("laundry") >= 0.0, "Done plays the moment"
	)
	s._check(h.chore_state("laundry") == "fine", "Done over the local list: fine")
	await s._until(
		func() -> bool: return h.chore_moment("laundry") < 0.0 and s._requests(main._backend) == 0,
		"the moment ends"
	)
	var row: Dictionary = h.chores()["laundry"]["item"] if h.chores().has("laundry") else {}
	s._check(
		h.chore_state("laundry") == "fine" and not row.is_empty() and h._due(row) > now + 5 * 86400.0,
		"the row is kept for next week"
	)
