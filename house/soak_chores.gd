extends RefCounted

# The soak's checks of the chores: which text names which thing, the three states from a pretended
# clock, the room's hits (hover, click, outline), Done, what leaves Home's lists, the layout's basket
# and the same over the house's own list.
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


func _frames(n: int = 3) -> void:
	for _i in n:
		await s.process_frame


func run() -> void:
	var keep := [h.open, h.coming, h.fake_day, h.fake_hour, h.things.pick, h.meetings]
	var was_busy: bool = main._busy
	var was_bowls: Variant = h.settings.value("bowls")
	var was_things: Variant = h.settings.value("pet_things")
	var was_away: Array = h.pets.critters.map(func(c): return c.away)
	main._busy = true
	h.settings.put("bowls", true)
	h.settings.put("pet_things", true)
	for c in h.pets.critters:
		c.away = false
	h.layout.reset(h.busy_cells())
	h.apply_layout()
	h.petlife.sync()
	_table()
	_states()
	await _room()
	await _lists()
	await _layout()
	await _done()
	h.open = keep[0]
	h.coming = keep[1]
	h.fake_day = keep[2]
	h.fake_hour = keep[3]
	h.things.pick = keep[4]
	h.meetings = keep[5]
	main._busy = was_busy
	h.settings.put("bowls", was_bowls)
	h.settings.put("pet_things", was_things)
	for i in h.pets.critters.size():
		h.pets.critters[i].away = was_away[i]
	h.selected = ""
	sb.back()
	await _frames()


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


func _table() -> void:
	var cases := {
		"do the laundry": "laundry",
		"Washing": "laundry",
		"wash the dishes": "",
		"take the bins out": "bins",
		"bin night": "bins",
		"binder": "",
		"Take out the TRASH": "bins",
		"recycling, then garbage": "bins",
		"rubbish": "bins",
		"feed the cat": "bowls",
		"Feed the dogs": "",
		"feed the pets": "bowls",
		"feed Mimi": "",
		"feed": "",
		"feed the baby": "",
		"take your meds": "pills",
		"vitamins": "pills",
		"medication at 9": "pills",
		"pills": "pills",
		"water the plants": "plant",
		"water the plant": "plant",
		"water": "",
		"plant a tree": "",
		"laundry bins": "laundry",
		"": "",
	}
	for text in cases:
		s._check(
			Chores.thing_of(text) == cases[text],
			"'%s' names '%s', not '%s'" % [text, cases[text], Chores.thing_of(text)]
		)
	s._check(
		Chores.thing_of("feed Mimi", ["Mimi", "Argos"]) == "bowls", "a pet's own name is a word"
	)
	s._check(Chores.thing_of("feed Mimic", ["Mimi", "Argos"]) == "", "and only as a whole word")
	s._check(Chores.thing_of("feed Mimi", ["", "Argos"]) == "", "an empty name matches nothing")


func _states() -> void:
	var now := _clock()
	var day := floorf(now / 86400.0) * 86400.0
	var cases := [
		["week", now + 6 * 86400.0, "fine"],
		["week", now + 3.6 * 86400.0, "fine"],
		["week", now + 3.4 * 86400.0, "soon"],
		["week", day + 86400.0 + 3600.0, "soon"],
		["week", day + 18 * 3600.0, "due"],
		["week", day + 3600.0, "due"],
		["week", now - 3 * 86400.0, "due"],
		["day", day + 86400.0 + 8 * 3600.0, "fine"],
		["day", day + 86400.0 + 5 * 3600.0, "fine"],
		["2 week", now + 8 * 86400.0, "fine"],
		["2 week", now + 6 * 86400.0, "soon"],
		["month", now + 14 * 86400.0, "soon"],
		["month", now + 16 * 86400.0, "fine"],
		["month", now + 12 * 86400.0, "soon"],
	]
	for c in cases:
		var got := Chores.state(c[1], c[0], now)
		s._check(
			got == c[2],
			"every %s, due in %.1f days is %s, not %s" % [c[0], (c[1] - now) / 86400.0, c[2], got]
		)
	s._check(
		Chores.interval("2 week") == 14 * 86400.0 and Chores.interval("soon") == 0.0,
		"the rhythm in seconds"
	)
	var phrases := [
		["due", day + 18 * 3600.0, "due today"],
		["due", now - 86400.0, "due since Tue"],
		["due", now - 9 * 86400.0, "due since 9 Nov"],
		["soon", day + 86400.0 + 3600.0, "tomorrow"],
		["fine", now + 2 * 86400.0, "Friday"],
		["fine", now + 12 * 86400.0, "30 Nov"],
	]
	for c in phrases:
		var got := Chores.phrase(c[0], c[1], now)
		s._check(got == c[2], "%s reads '%s', not '%s'" % [c[0], c[2], got])
	s._check(
		Chores.hover("bins", "fine", now + 2 * 86400.0, now) == "bins · Friday",
		"a thing's hover words"
	)


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
		s._check(
			h.chore_present(thing),
			(
				"%s is in the default room (bowls %s, here %s)"
				% [thing, h.settings.value("bowls"), h.pets.species_here()]
			)
		)
		s._check(h.chore_state(thing) == "", "%s shows nothing with no chore" % thing)
		for state in Chores.STATES:
			id += 1
			h.open = []
			h.coming = [_row(id, THINGS[thing], dues[state])]
			await _frames()
			s._check(
				h.chore_state(thing) == state,
				"%s: %s from the clock, not '%s'" % [thing, state, h.chore_state(thing)]
			)
			var key: String = h.chore_hit(thing)
			var at: Variant = _centre(key)
			s._check(at != null, "%s has a hit to point at (%s)" % [thing, state])
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
			await _frames()
			s._check(
				sb.view == "item" and int(sb.arg) == id and h.card.kind == "",
				(
					"a click on %s opens that chore's item view (%s %s, %s at %s)"
					% [thing, sb.view, sb.arg, state, at]
				)
			)
			s._check(
				h.selected == key and sb.selected_key() == key,
				"%s is outlined while its view is open" % thing
			)
			sb.back()
	h.open = []
	h.coming = []
	await _frames()
	for thing in THINGS:
		s._check(h.chore_state(thing) == "", "%s shows nothing again with no chore" % thing)
	for c in h.pets.critters:
		c.away = false
	h.selected = ""


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
	await _frames()
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
	# the click opens the more urgent one
	var at: Variant = _centre("chore:laundry")
	if at != null:
		for c in h.pets.critters:
			if c.id != "person":
				c.away = true
		h.click(at)
		await _frames()
		s._check(
			sb.view == "item" and int(sb.arg) == 20,
			"a click on the thing opens the more urgent chore"
		)
		for c in h.pets.critters:
			c.away = false
		sb.back()
	# the calendar card and the item view still have it
	h.card.open("calendar", "cal")
	h.things.reset()
	var blocks := str(h.things.calendar_blocks())
	h.close_card()
	s._check(
		blocks.contains("do the laundry") or blocks.contains("laundry"),
		"the calendar card still shows the chore"
	)
	var box := VBoxContainer.new()
	sb._views.item_view(box, 20)
	var item := _texts(box)
	box.free()
	s._check("do the laundry" in item, "and so does its item view")
	# taken out of the room, the thing's rows are list rows again
	var piece: Dictionary = h.layout.basket()
	h.layout.remove(piece)
	h.apply_layout()
	await _frames()
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
	await _frames()
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
	var wall: Dictionary = {"p": Chores.PIECE, "f": "", "c": 6, "r": 0}
	s._check(h.layout.check(wall, piece, []) != "", "it does not go on the bin")
	var again := {"p": Chores.PIECE, "f": "", "c": 8, "r": 9}
	s._check(h.layout.check(again, piece, []) == "", "it can be moved to free floor")


# Done through the same path a ticked item takes: the thing moves to fine with a moment of its own
func _done() -> void:
	var now := _clock()
	var day := floorf(now / 86400.0) * 86400.0
	var keep: Dictionary = main._data.duplicate(true)
	var was_demo: bool = main._demo
	main._demo = true
	var data: Dictionary = main._data.duplicate(true)
	data["open"] = [
		_row(31, "take the bins out", now - 86400.0), _row(32, "water the plants", day + 3600.0)
	]
	data["coming"] = [
		_row(33, "do the laundry", now + 3 * 86400.0), _row(34, "take your meds", now + 6 * 86400.0)
	]
	main._apply(data)
	await _frames()
	var week: int = int(main._data["done_week"])
	for thing in ["bins", "plant", "laundry", "pills"]:
		var before: String = h.chore_state(thing)
		s._check(
			before != "" and (before != "fine" or thing == "pills"),
			"%s starts %s" % [thing, before]
		)
	main._act(31, "done")
	main._act(32, "done")
	main._act(33, "done")
	main._act(34, "done")
	await _frames()
	s._check(h.chore_moment("bins") < 0.0, "the moment holds the old look at first")
	s._check(h.chore_state("bins") == "due", "the bin is as it was for the first beat")
	await s.create_timer(Chores.PAUSE + 0.2).timeout
	for thing in ["bins", "plant", "laundry", "pills"]:
		s._check(
			h.chore_state(thing) == "fine",
			"%s is fine after Done: '%s'" % [thing, h.chore_state(thing)]
		)
	s._check(h.chore_moment("bins") >= 0.0, "and the bag goes in a moment of its own")
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
	await s.create_timer(Chores.MOMENT).timeout
	s._check(
		h.chore_moment("bins") < 0.0 and h.chore_state("bins") == "fine",
		"the moment ends with the thing fine"
	)
	main._demo = was_demo
	main._apply(keep)
	h.open = []
	h.coming = []


# the same over the house's own list: Done moves a repeating reminder on and the thing is fine
func local() -> void:
	var was := [h.fake_day, h.fake_hour]
	var now := _clock()
	var plain := BackendLocal.new()
	plain.setup("", Callable(h, "_now_local"), h._bias(), false)
	main._install(plain)
	var at: String = h.today() + "T18:00"
	var got: Array = []
	plain.send(
		"/api/home/add",
		{"kind": "reminder", "text": "do the laundry", "at": at, "every": "week"},
		func(_r: bool, code: int, body: Variant) -> void: got.append([code, body])
	)
	await s.create_timer(0.5).timeout
	main._poll()
	await s.create_timer(0.5).timeout
	s._check(got.size() == 1 and got[0][0] == 200, "the local list takes a repeating reminder")
	var id: int = int(got[0][1]["id"]) if got.size() == 1 and got[0][1] is Dictionary else -1
	s._check(
		h.chore_thing_of(id) == "laundry",
		"a repeating reminder in the local list stands for its thing"
	)
	s._check(h.chore_state("laundry") == "due", "due today: %s" % h.chore_state("laundry"))
	main._act(id, "done")
	await s.create_timer(Chores.PAUSE + 0.8).timeout
	main._poll()
	await s.create_timer(0.5).timeout
	s._check(
		h.chores().has("laundry") and h.chore_state("laundry") == "fine",
		"Done over the local list: fine, the row kept for next week"
	)
	var row: Dictionary = h.chores()["laundry"]["item"] if h.chores().has("laundry") else {}
	s._check(not row.is_empty() and h._due(row) > now + 5 * 86400.0, "its next time is a week on")
	h.open = []
	h.coming = []
	h.fake_day = was[0]
	h.fake_hour = was[1]
	main._make_backend()
