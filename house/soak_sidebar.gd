extends RefCounted

# The soak's checks of the sidebar as a whole: every thing in the room opens a view or toggles, the
# views never lie outside the window at the smallest and the largest sizes, and a banner never takes
# a view away. Nothing here reaches a server.
const Sidebar := preload("res://sidebar.gd")
const SIZES :=[Vector2(900, 600), Vector2(1100, 700), Vector2(1920, 1080)]
const VIEWS := ["home", "item", "open", "add", "pet", "closet", "settings", "decorate", "card"]
const Blocks := preload("res://blocks.gd")
const When := preload("res://when.gd")

var s
var main
var h
var sb


func _init(soak, the_main) -> void:
	s = soak
	main = the_main
	h = main._room.home
	sb = main._sidebar


# the sidebar's own frame, which draws its state; the deferred calls an action queued have run by
# the time it ends
func _sync() -> void:
	await s.process_frame


# the engine's own container pass lays a resize or a rebuild out at the end of a frame; a layout
# is read after the sidebar has drawn and that pass has run
func _laid_out() -> void:
	await _sync()
	await _sync()


func run() -> void:
	await _things()
	await _shelf()
	await _agendas()
	await _proposals()
	await _fit()
	await _pet()
	await _banner()
	await _decorate_tabs()
	_day_meetings()
	_wall_click()
	await _home_sections()
	_times()
	await _home_fits()


func _meeting(title: String, from: String, to: String, tentative: bool, day: String) -> Dictionary:
	return {"title": title, "starts_at": from, "ends_at": to, "tentative": tentative, "day": day}


# a click on the wall calendar opens the card, and the sidebar's own frame (not a call to the code
# under test) draws it: the month must have been asked for by then, and today's meeting shows
func _wall_click() -> void:
	var date: String = h.today()
	var wanted: Array = []
	var serve := func(key: String, _from: String, _to: String) -> void:
		wanted.append(key)
		h.things.set_meetings(
			key,
			[
				{
					"title": "Clicked in",
					"starts_at": date + "T23:00:00Z",
					"ends_at": date + "T23:30:00Z",
					"tentative": false,
					"all_day": false,
					"date": date,
				}
			]
		)
	h.things.meetings_wanted.connect(serve)
	h.close_card()
	var wall: Variant = _centre("cal")
	s._check(wall != null, "the room has a calendar to click")
	if wall == null:
		h.things.meetings_wanted.disconnect(serve)
		return
	h.decorating = false
	h.click(wall)
	s._check(h.card.kind == "calendar" and wanted.is_empty(), "opening the card asks nothing yet")
	sb._process(0.0)
	s._check(not wanted.is_empty(), "the card's first frame asks for the month")
	s._check(
		h.card_blocks().any(func(b: Dictionary) -> bool: return b["t"] == "meet"),
		"and today shows its meeting"
	)
	h.things.meetings_wanted.disconnect(serve)
	h.things.month_meetings.clear()
	h.close_card()
	h.things.reset()


# the wall calendar: Today and Tomorrow headed when nothing is picked, a clicked date its own block
# (named when it is today or tomorrow) and back, a mark for a day with meetings, a meeting that is
# over dimmer, and each month fetched once while the view is open and again when it is reopened;
# on an ordinary day, the last of a month and the last of a year
func _day_meetings() -> void:
	var was: String = h.fake_day
	for pin: String in ["03-14", "11-30", "12-31"]:
		h.fake_day = pin
		_day_view(pin)
	h.fake_day = was


func _day_view(pin: String) -> void:
	var things = h.things
	var at := "(%s) " % pin
	var asked: Array = []
	var ask := func(key: String, _from: String, _to: String) -> void: asked.append(key)
	things.meetings_wanted.connect(ask)
	things.reset()
	things.calendar_blocks()
	var first := asked.size()
	things.calendar_blocks()
	s._check(first >= 1 and asked.size() == first, at + "a month in view is asked for once")
	var t: Dictionary = things.today()
	var tomorrow: Dictionary = things._plus_day(t)
	var other := {"y": t["y"], "m": t["m"], "d": (int(t["d"]) + 9) % 28 + 1}
	var now: float = h._now_local() - h._bias()
	var iso := func(secs: float) -> String:
		return Time.get_datetime_string_from_unix_time(int(now + secs)) + "Z"
	var row := func(
		title: String, d: Dictionary, from: String, to: String, tentative: bool
	) -> Dictionary:
		return {
			"title": title,
			"starts_at": from,
			"ends_at": to,
			"tentative": tentative,
			"all_day": false,
			"date": "%04d-%02d-%02d" % [int(d["y"]), int(d["m"]), int(d["d"])],
		}
	var rows := {}
	for r: Dictionary in [
		row.call("Over", t, iso.call(-7200.0), iso.call(-3600.0), false),
		row.call("Soon", t, iso.call(3600.0), iso.call(5400.0), false),
		row.call("Review", tomorrow, iso.call(90000.0), iso.call(92000.0), true),
		row.call("Dentist", other, iso.call(900000.0), iso.call(901800.0), false)
	]:
		var key: String = str(r["date"]).substr(0, 7)
		rows[key] = rows.get(key, []) + [r]
	for key: String in rows:
		things.set_meetings(key, rows[key])
	var titles := func() -> Array:
		return (
			things
			. calendar_blocks()
			. filter(func(b: Dictionary) -> bool: return b["t"] == "title")
			. map(func(b: Dictionary) -> String: return b["text"])
		)
	var meet := func() -> Array:
		return things.calendar_blocks().filter(func(b: Dictionary) -> bool: return b["t"] == "meet")
	var grid := func() -> Dictionary:
		return things.calendar_blocks().filter(func(b: Dictionary) -> bool: return b["t"] == "month")[0]
	var heads: Array = titles.call()
	s._check(
		str(heads[0]).begins_with("Today · ") and str(heads[1]).begins_with("Tomorrow · "),
		at + "nothing picked: Today and Tomorrow, headed"
	)
	var shown: Array = meet.call()
	s._check(
		shown.size() == 3 and shown[1]["text"].ends_with("Soon") and shown[2]["dim"],
		at + "each has its meetings, a tentative one dimmed"
	)
	s._check(shown[0]["past"] and not shown[1]["past"], at + "one that is over is dimmer")
	things.act("day:%d" % int(other["d"]))
	s._check(
		(
			not str(titles.call()[0]).begins_with("Today")
			and not str(titles.call()[0]).begins_with("Tomorrow")
			and meet.call().size() == 1
			and meet.call()[0]["text"].ends_with("Dentist")
		),
		at + "a clicked date shows its own meetings"
	)
	things.act("day:%d" % int(other["d"]))
	s._check(
		str(titles.call()[0]).begins_with("Today · "),
		at + "clicking it again is back to Today and Tomorrow"
	)
	things.act("day:%d" % int(t["d"]))
	var named: Array = titles.call()
	s._check(
		named.size() == 1 and str(named[0]).begins_with("Today · "),
		at + "a clicked today is one block, named"
	)
	things.act("day:%d" % int(t["d"]))
	var g: Dictionary = grid.call()
	s._check(
		g["meet_marks"].has(int(t["d"])) and g["meet_marks"].has(int(other["d"])),
		at + "a day with a meeting has its mark"
	)
	s._check(
		not g["meet_marks"].has(int(other["d"]) % 28 + 1) and int(g["today"]) == int(t["d"]),
		at + "another day has none; today is marked"
	)
	var same_month: bool = tomorrow["m"] == t["m"]
	s._check(
		int(g["tomorrow"]) == (int(tomorrow["d"]) if same_month else 0),
		at + "tomorrow is marked in its own month"
	)
	var before := asked.size()
	things.act("mnext")
	things.calendar_blocks()
	s._check(asked.has(things._month_key()), at + "a month change asks for that month")
	var after := asked.size()
	things.act("mprev")
	things.calendar_blocks()
	s._check(asked.size() == after and after >= before, at + "a month already asked for is kept")
	if not same_month:
		things.act("mnext")
		var g2: Dictionary = grid.call()
		s._check(
			int(g2["tomorrow"]) == int(tomorrow["d"]) and g2["meet_marks"].has(int(tomorrow["d"])),
			at + "paged to tomorrow's month, tomorrow is marked"
		)
		things.act("day:%d" % int(tomorrow["d"]))
		s._check(
			str(titles.call()[0]).begins_with("Tomorrow · ") and meet.call().size() == 1,
			at + "its first is tomorrow, named, with its meeting"
		)
	else:
		things.act("day:%d" % int(tomorrow["d"]))
		s._check(
			str(titles.call()[0]).begins_with("Tomorrow · "), at + "a clicked tomorrow is named"
		)
	things.reset()
	things.calendar_blocks()
	s._check(asked.size() > after, at + "reopening the view asks again")
	for key: String in rows:
		things.month_meetings.erase(key)
	things.meetings_wanted.disconnect(ask)
	things.reset()


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


func _press(text: String) -> void:
	var r: Variant = _row(sb._dyn, text)
	s._check(r != null, "the shelf has a row: %s" % text)
	if r != null:
		r.pressed.emit()
	await _sync()


func _open_shelf() -> void:
	sb.back()
	h.decorating = false
	await _sync()
	var c: Variant = _centre("furn:bookshelf")
	s._check(c != null, "the room has a bookshelf to click")
	if c != null:
		h.click(c)
	await _sync()


func _filter(text: String) -> void:
	for c in sb._dyn.find_children("*", "LineEdit", true, false):
		c.text = text
		c.text_changed.emit(text)
	await _sync()


# one click on the bookshelf shows the notes, what is put off, the projects and every title
func _shelf() -> void:
	var keep: Dictionary = s._state.duplicate(true)
	var notes: Array = []
	var rows: Array = []
	for i in range(1, 11):
		notes.append("note %d" % i)
		rows.append({"id": 200 + i, "text": "note %d" % i})
	var project := {"id": 61, "kind": "project", "text": "Move", "next": {"id": 62, "text": "book the van"}}
	var put_off := {"id": 51, "kind": "todo", "text": "learn sourdough", "due_at": null, "every": null}
	var extra := {"notes": notes, "note_rows": rows, "someday": [put_off], "projects": [project]}
	var before: int = s._count("/api/home")
	s.seed(keep["open"], keep["coming"], extra)
	main._poll()
	await s._until(func(): return s._count("/api/home") > before, "the house is read again")
	await s._answered(main)
	await _open_shelf()
	s._check(sb.view == "card" and h.card.kind == "book", "the bookshelf opens the shelf")
	var texts: Array = _texts(sb._dyn)
	for t in ["Notes (10)", "note 1", "note 8", "Someday (1)", "learn sourdough", "Projects (1)"]:
		s._check(t in texts, "the shelf lists %s" % t)
	for t in ["Move", "Books", "Ficciones", "Seven Nights"]:
		s._check(t in texts, "the shelf lists %s" % t)
	s._check("2 more..." in texts and "note 9" not in texts, "a long list shows eight and a more row")
	await _press("2 more...")
	s._check("note 10" in _texts(sb._dyn), "more opens the rest in place")
	await _filter("sourdough")
	texts = _texts(sb._dyn)
	s._check("learn sourdough" in texts and not "note 1" in texts and not "Books" in texts, "the filter narrows every section")
	await _filter("")
	h.eggs.found.erase("book")
	await _press("Ficciones")
	s._check(h.eggs.found.has("book"), "opening a title grants the book find")
	s._check(h.finds.remark() in _texts(sb._dyn), "a title shows its remark under it")
	await _press("The Aleph")
	s._check(_texts(sb._dyn).count(h.finds.remark()) == 1 and h.finds.book["title"] == "The Aleph", "one title is open at a time")
	s._check(sb.view == "card" and h.card.kind == "book", "a title does not leave the shelf")
	s._check(sb.get_global_rect().size.x <= sb.WIDTH + 0.5, "the shelf keeps the pane %d wide" % sb.WIDTH)
	await _press("note 3")
	s._check(sb.view == "item" and int(sb.arg) == 203, "a note opens its item view")
	s._check("note 3" in _texts(sb._dyn) and sb.get_global_rect().size.x <= sb.WIDTH + 0.5, "the note view shows its text")
	sb.item_act(203, "delete")
	await s._answered(main)
	await _open_shelf()
	texts = _texts(sb._dyn)
	s._check(sb.view == "card" and "Notes (9)" in texts and "note 3" not in texts, "deleting a note takes it off the shelf")
	s._check("2 more..." in texts or "1 more..." in texts, "the shelf opens collapsed again")
	sb.back()
	await _sync()
	h.things.open_note({"id": 0, "text": "plain"})
	await _sync()
	s._check(h.card.kind == "board" and h.things.tab == "notes", "a note with no id opens the board's notes")
	sb.back()
	await _open_shelf()
	await _press("learn sourdough")
	s._check(sb.view == "item" and int(sb.arg) == 51, "a someday row opens that item")
	sb.back()
	s._state = keep
	main._poll()
	await s._answered(main)


func _edit(placeholder: String) -> Variant:
	for e in sb._dyn.find_children("*", "LineEdit", true, false):
		if e.placeholder_text == placeholder:
			return e
	return null


func _button(text: String) -> Variant:
	for b in sb._dyn.find_children("*", "Button", true, false):
		if b.text == text:
			return b
	return null


func _posted(path: String) -> Array:
	return s._log.filter(func(l: Array) -> bool: return l[0] == "POST" and l[1] == path)


# the agendas: on the shelf above the notes, an agenda's pile with its add line and Clear, and the
# one due today under Today
func _agendas() -> void:
	var keep: Dictionary = s._state.duplicate(true)
	var today := Time.get_unix_time_from_datetime_string(h.today() + "T14:00:00")
	var due_at := Time.get_datetime_string_from_unix_time(int(today - h._bias())) + "Z"
	var retro := {
		"id": 71, "name": "retro", "every": "2 week", "next_at": due_at,
		"notes": [
			{"id": 711, "text": "the deploy took three tries", "since": "2026-11-16T10:00:00Z"},
			{"id": 712, "text": "flaky gate again", "since": "2026-11-17T15:30:00Z"},
		],
	}
	var sam := {"id": 72, "name": "1:1 with Sam", "every": null, "next_at": null, "notes": []}
	var before: int = s._count("/api/home")
	s.seed(keep["open"], keep["coming"], {"agendas": [retro, sam]})
	main._poll()
	await s._until(func(): return s._count("/api/home") > before, "the house is read again")
	await s._answered(main)
	sb.back()
	await _sync()
	var texts: Array = _texts(sb._dyn)
	s._check("Today" in texts and "14:00" in texts and "Retro · 2 things" in texts, "Home has a time-first row for an agenda due today: %s" % str(texts))
	await _press("Retro · 2 things")
	s._check(sb.view == "agenda" and int(sb.arg) == 71, "the row opens the agenda")
	texts = _texts(sb._dyn)
	var rhythm: String = h.things.agenda_rhythm(retro)
	s._check("retro" in texts and rhythm in texts and rhythm.begins_with("every other week, "), "the agenda shows its name and its rhythm as text: %s" % rhythm)
	s._check("the deploy took three tries" in texts and "flaky gate again" in texts, "the agenda lists its notes")
	s._check(sb.get_global_rect().size.x <= sb.WIDTH + 0.5, "the agenda keeps the pane %d wide" % sb.WIDTH)
	await _press("flaky gate again")
	s._check(sb.view == "item" and int(sb.arg) == 712, "a note on a pile opens as a note")
	sb.back()
	await _open_shelf()
	texts = _texts(sb._dyn)
	var at := func(t: String) -> int: return texts.find(t)
	s._check("Agendas (2)" in texts and "retro" in texts and "1:1 with Sam" in texts and "new agenda" in texts, "the shelf lists the agendas")
	s._check("2 - " + h.things.agenda_when(retro) in texts and "0" in texts, "each agenda shows its count and when it is next")
	s._check(at.call("Agendas (2)") == 0, "the agendas come first on the shelf")
	await _press("retro")
	s._check(sb.view == "agenda", "an agenda row opens the agenda")
	var edit: Variant = _edit("add a note")
	s._check(edit != null, "the agenda has an add line")
	if edit != null:
		edit.text_submitted.emit("nobody owned the rollback")
	await s._until(func(): return _posted("/api/home/agendas/71/add").size() >= 1, "the note is posted")
	var posts := _posted("/api/home/agendas/71/add")
	s._check(posts.size() == 1 and JSON.parse_string(posts[0][2]) == {"text": "nobody owned the rollback"}, "Enter adds the note to this agenda: %s" % str(posts))
	var clear: Variant = _button("Clear")
	s._check(clear != null, "a pile with notes has Clear")
	if clear != null:
		clear.pressed.emit()
	await s._until(func(): return _posted("/api/home/agendas/71/clear").size() >= 1, "Clear is posted")
	s._check(_posted("/api/home/agendas/71/clear").size() == 1, "Clear asks the home to archive the pile")
	sb.back()
	await s._until(func(): return sb.view == "card" and h.card.kind == "book", "back from the agenda reaches the shelf")
	s._check(sb.view == "card" and h.card.kind == "book", "back from an agenda opened on the shelf is the shelf")
	await _press("new agenda")
	var name_edit: Variant = _edit("name the agenda")
	s._check(name_edit != null, "new agenda opens a line for the name")
	if name_edit != null:
		name_edit.text_submitted.emit("offsite")
	await s._until(func(): return _posted("/api/home/agendas").size() >= 1, "the new agenda is posted")
	s._check(_posted("/api/home/agendas").size() == 1, "a name makes a new agenda")
	sb.back()
	s._state = keep
	main._poll()
	await s._answered(main)


# proposals: a section under Open with the why line, add and no, three shown, no banner
func _proposals() -> void:
	var keep: Dictionary = s._state.duplicate(true)
	var rows: Array = []
	for i in 5:
		var why := "acme/app#%d" % i
		var shown = null if i == 1 else why
		rows.append({"id": 80 + i, "source": "github", "text": "Review: PR %d" % i, "why": shown})
	s.seed(keep["open"], keep["coming"], {"proposals": rows})
	await _poll_home()
	sb.back()
	await _sync()
	var texts: Array = _texts(sb._dyn)
	s._check("Proposed (5)" in texts, "Home has a Proposed (5) section: %s" % str(texts))
	s._check(texts.find("Proposed (5)") > texts.find("Open"), "Proposed comes under Open")
	var shows: bool = "Review: PR 0" in texts and "acme/app#0" in texts and "Review: PR 2" in texts
	s._check(shows, "a row shows the text and the why line")
	var bare: bool = "Review: PR 1" in texts and not ("<null>" in texts or "null" in texts)
	s._check(bare, "a proposal with no why has no line")
	var three: bool = not ("Review: PR 3" in texts) and "2 more..." in texts
	s._check(three, "three are shown, then 2 more...")
	s._check(sb.get_global_rect().size.x <= sb.WIDTH + 0.5, "the pane stays %d wide" % sb.WIDTH)
	var banner := " ".join(_texts(sb._banner))
	s._check(not ("Review: PR" in banner or "Proposed" in banner), "a proposal raises no banner")
	await _press("2 more...")
	s._check("Review: PR 4" in _texts(sb._dyn), "2 more... shows the rest in place")
	await _press("less")
	var add: Variant = _mark("Review: PR 0", "add")
	s._check(add != null, "a row has an add button")
	if add != null:
		add.pressed.emit()
	await s._until(
		func(): return not _posted("/api/home/proposals/80/take").is_empty(), "add posts the take"
	)
	s._check(_posted("/api/home/proposals/80/take").size() == 1, "add takes the proposal")
	await _settle_home()
	texts = _texts(sb._dyn)
	var at: int = texts.find("Review: PR 0")
	var moved: bool = "Proposed (4)" in texts and at < texts.find("Proposed (4)")
	s._check(moved and texts.find("Review: PR 0") > texts.find("Open"), "added: in Open, section 4")
	var no: Variant = _mark("Review: PR 1", "no")
	s._check(no != null, "a row has a no button")
	if no != null:
		no.pressed.emit()
	await s._until(
		func(): return not _posted("/api/home/proposals/81/dismiss").is_empty(), "no posts the dismissal"
	)
	s._check(_posted("/api/home/proposals/81/dismiss").size() == 1, "no dismisses the proposal")
	await _settle_home()
	texts = _texts(sb._dyn)
	s._check("Proposed (3)" in texts and not ("Review: PR 1" in texts), "the dismissed one is gone")
	s._check(sb.get_global_rect().size.x <= sb.WIDTH + 0.5, "the pane still stays %d wide" % sb.WIDTH)
	s._state = keep
	await _poll_home()
	await _settle_home()
	s._check(not ("Proposed (" in " ".join(_texts(sb._dyn))), "with none there is no section")


# read the home again and wait for the stub to have answered it
func _poll_home() -> void:
	var before: int = s._count("/api/home")
	main._poll()
	await s._until(func(): return s._count("/api/home") > before, "the house is read again")
	await s._answered(main)


func _settle_home() -> void:
	await _poll_home()
	sb.back()
	await _sync()


# the small button `label` on the row whose text is `text`
func _mark(text: String, label: String) -> Variant:
	var row: Variant = _row(sb._dyn, text)
	if row == null:
		return null
	return _find_button(row, label)


func _find_button(node: Node, label: String) -> Variant:
	for c in node.get_children():
		if c is Button and c.text == label:
			return c
		var b: Variant = _find_button(c, label)
		if b != null:
			return b
	return null


# the local list keeps agendas the same way: new agenda, a note, Clear
func local_agendas() -> void:
	await _open_shelf()
	var texts: Array = _texts(sb._dyn)
	s._check("Agendas (0)" in texts and "new agenda" in texts, "the local shelf has Agendas and a new agenda row")
	await _press("new agenda")
	var name_edit: Variant = _edit("name the agenda")
	if name_edit != null:
		name_edit.text_submitted.emit("retro")
	await s._answered(main)
	texts = _texts(sb._dyn)
	s._check("Agendas (1)" in texts and "retro" in texts, "the local list makes the agenda: %s" % str(texts.slice(0, 5)))
	await _press("retro")
	s._check(sb.view == "agenda", "the local agenda opens")
	var edit: Variant = _edit("add a note")
	if edit != null:
		edit.text_submitted.emit("flaky gate")
	await s._answered(main)
	s._check("flaky gate" in _texts(sb._dyn), "the local list puts the note on the pile")
	var clear: Variant = _button("Clear")
	if clear != null:
		clear.pressed.emit()
	await s._answered(main)
	s._check("Nothing on this pile yet." in _texts(sb._dyn), "Clear leaves the local agenda empty")
	s._check("flaky gate" not in h.notes and h.things.note_list().all(func(n): return n["text"] != "flaky gate"), "a pile's notes are not in the plain notes")
	sb.back()
	await _sync()
	sb.back()
	await _sync()


# the local list's own data builds the same view
func shelf_local() -> void:
	await _open_shelf()
	s._check(sb.view == "card" and h.card.kind == "book", "the local list's shelf opens")
	var texts: Array = _texts(sb._dyn)
	s._check("Books" in texts and "Move" in texts, "the local list's shelf lists its projects and the books: %s" % str(texts.slice(0, 6)))
	s._check(sb.get_global_rect().size.x <= sb.WIDTH + 0.5, "the local shelf keeps the pane %d wide" % sb.WIDTH)
	var kept: Array = h.things.note_rows
	s._check(not kept.is_empty(), "the local list gives notes with ids")
	if not kept.is_empty():
		h.things.open_note(kept[0])
		await _sync()
		s._check(sb.view == "item" and str(kept[0]["text"]) in _texts(sb._dyn), "a local note opens its item view")
	sb.back()
	await _sync()


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


# a click on each thing leaves the home view, or turns something on or off
func _things() -> void:
	sb.back()
	h.decorating = false
	await _sync()
	var seen := 0
	for key in [
		"cal", "jar", "window", "clock", "plant", "board", "mousehole", "furn:fireplace",
		"furn:bookshelf", "furn:piano", "globe", "wardrobe", "pad", "stack", "phone", "tv"
	]:
		var c: Variant = _centre(key)
		if c == null:
			continue
		seen += 1
		sb.back()
		await _sync()
		if key == "phone":
			sb.chat_mode = "line"
		var was := [sb.view, h.card.kind, h.tv.on, sb._effective()]
		h.click(c)
		await _sync()
		var now := [sb.view, h.card.kind, h.tv.on, sb._effective()]
		s._check(now != was, "a click on %s opens a view or toggles (%s)" % [key, str(now)])
		if key != "tv" and key != "phone":
			s._check(sb.selected_key() == h.selected, "%s stays highlighted" % key)
		sb.back()
		await _sync()
	s._check(seen >= 8, "the room has things to click: %d" % seen)
	sb.back()
	var a: Variant = _centre("cal")
	var b: Variant = _centre("jar")
	if a != null and b != null:
		h.click(a)
		await _sync()
		h.click(b)
		await _sync()
		s._check(sb.view == "card" and h.card.kind == "jar", "thing B replaces thing A's view")
		sb.back()
		await _sync()
		s._check(sb.view == "home" and h.selected == "", "back brings the home view, nothing selected")


# every control of every view sits inside the window, at the smallest and the largest size
func _fit() -> void:
	var was: Vector2 = main.size
	for size in SIZES:
		main.size = size
		var win := Rect2(Vector2.ZERO, size)
		for name in ["home", "add", "pet", "pet_edit", "closet", "settings", "card"]:
			sb.back()
			await _sync()
			match name:
				"add":
					sb.open_add()
				"pet":
					sb.open_pet("nina")
				"pet_edit":
					sb.open_pet("nina")
					sb.pet_view._open_edit()
				"closet":
					sb.open_closet()
				"settings":
					sb.open_settings()
				"card":
					h.card.open("calendar", "cal")
			await _laid_out()
			await s._until(
				func(): return _outside(win) == "" and sb.get_global_rect().end.x <= size.x + 0.5,
				"the %s view laid out inside a %s window" % [name, size]
			)
			var out := _outside(win)
			s._check(out == "", "no %s control lies outside a %s window: %s" % [name, size, out])
			s._check(sb.get_global_rect().end.x <= size.x + 0.5, "the sidebar fits a %s window" % size)
		sb.back()
	main.size = was
	await _sync()
	await _laid_out()


func _outside(win: Rect2) -> String:
	var bad: Array = []
	for c in sb.find_children("*", "Control", true, false):
		if not c.is_visible_in_tree():
			continue
		var r: Rect2 = c.get_global_rect()
		if r.size.x <= 0.0 or r.size.y <= 0.0:
			continue
		if r.position.x < win.position.x - 0.5 or r.end.x > win.end.x + 0.5:
			bad.append("%s %s" % [c.name, r])
	return ", ".join(bad.slice(0, 3))


# a click on a pet opens its view, not the controls; Esc goes back one level at a time
func _pet() -> void:
	sb.back()
	await _sync()
	var cat = h.pets.critter("nina")
	var c: Vector2 = h.pets.hit_rect(cat, h._o, h._k).get_center()
	if h.pet_at(c) == "nina":
		h.click(c)
	else:
		main._on_viewed("pet", "nina")
	await _sync()
	var v = sb.pet_view
	s._check(sb.view == "pet" and v.visible, "a click on a pet opens its view")
	s._check(v._page.visible and not v._tiles["cat_black"].is_visible_in_tree(), "not the kind grid")
	s._check(not sb.takes_text(), "the pets go on with their day while it is open")
	v._open_edit()
	await _sync()
	s._check(sb.takes_text() and v._tiles["cat_black"].is_visible_in_tree(), "change who this is")
	s._check(is_equal_approx(sb.size.x, Sidebar.WIDTH), "the pane stays %d wide" % Sidebar.WIDTH)
	sb.back()
	await _sync()
	s._check(sb.view == "pet" and v._page.visible and not v.editing, "Esc goes back to the pet")
	sb.back()
	await _sync()
	s._check(sb.view == "home", "and again goes home")


# a slip or a ring over an open view takes nothing from it
func _banner() -> void:
	sb.back()
	main._open_add()
	await _sync()
	var form_was: bool = sb.form.visible
	h.rhythm.show_slip("home", "Still open", [])
	await _sync()
	s._check(sb.view == "add" and sb.form.visible == form_was, "a slip leaves the add view be")
	h.rhythm.dismiss()
	main._open_settings()
	h.show_reply("noted")
	await _sync()
	s._check(sb.view == "settings", "a reply leaves the settings be")
	sb.back()
	await _sync()
	s._check(sb.view == "home", "and back still goes home")


# the pane is no wider than its 360 px with the decorate view up, whichever tab, and every tab shows
func _decorate_tabs() -> void:
	if not h.layout.art:
		return
	main._set_decorate(true)
	await _sync()
	var d = main._decorate
	for t in h.layout.tabs:
		d.tab = t
		d.queue_redraw()
		await _sync()
		s._check(sb.get_global_rect().size.x <= sb.WIDTH + 0.5, "the sidebar stays %d wide on %s" % [sb.WIDTH, t])
	for hit in d._hits:
		if str(hit["act"]).begins_with("tab:"):
			s._check(hit["rect"].end.x <= d.size.x - 4.0, "the %s tab fits the pane" % hit["act"])
	main._set_decorate(false)
	await _sync()


func _iso(at: float) -> String:
	return Time.get_datetime_string_from_unix_time(int(at - h._bias())) + "Z"


func _home_box() -> VBoxContainer:
	var box := VBoxContainer.new()
	sb._views.home_view(box)
	return box


# Home's sections in order, an empty one with no header, the pick only once, Later closed until
# opened; the header the same in every view; the dock the input line alone until there is a message
func _home_sections() -> void:
	var keep := [h.open, h.coming, h.meetings, h.things.pick, h.things.proposals, h.chat.messages]
	var was_hour: float = h.fake_hour
	h.fake_hour = 10.0
	var day := Time.get_unix_time_from_datetime_string(h.today() + "T23:30:00")
	var pick := {"id": 1, "kind": "todo", "text": "pick me", "why": "it has sat the longest"}
	h.things.pick = pick
	h.open = [pick, {"id": 2, "kind": "todo", "text": "second to-do", "due_at": null}]
	h.coming = [
		{"id": 3, "kind": "reminder", "text": "water the plant", "due_at": _iso(day)},
		{"id": 4, "kind": "reminder", "text": "dentist next week", "due_at": _iso(day + 7 * 86400.0)},
	]
	var soon: float = h._now_local() + 600.0
	h.meetings = [_meeting("Standup", _iso(soon), _iso(soon + 900.0), false, "today")]
	h.things.proposals = []
	var box := _home_box()
	var texts := _texts(box)
	box.free()
	var at := func(t: String) -> int: return texts.find(t)
	var order := ["Now", "Today", "Open", "Later (1)"]
	var found: Array = order.map(at)
	var sorted := found.duplicate()
	sorted.sort()
	s._check(not (-1 in found) and found == sorted, "Home's sections in order: %s" % str(texts))
	s._check(texts.count("pick me") == 1, "the pick is not repeated in Open")
	s._check("second to-do" in texts and "water the plant" in texts, "Open has the to-dos, Today the reminder")
	s._check(at.call("water the plant") > at.call("Today") and at.call("water the plant") < at.call("Open"), "a reminder due today sits under Today")
	s._check("Standup" in texts, "Today has the meeting")
	var meeting_time: String = h.meeting_time(h.meetings[0])
	s._check(at.call(meeting_time) == at.call("Standup") - 1, "a meeting's time comes first: %s" % str(texts))
	s._check(at.call("23:30") == at.call("water the plant") - 1, "so does a reminder's")
	s._check(not ("dentist next week" in texts), "Later is one closed line")
	sb.later_expanded = true
	box = _home_box()
	var opened := _texts(box)
	box.free()
	sb.later_expanded = false
	s._check("dentist next week" in opened, "Later opens in place")
	h.open = []
	h.coming = []
	h.meetings = []
	h.things.pick = {}
	box = _home_box()
	texts = _texts(box)
	box.free()
	for header in ["Now", "Today", "Open", "Later (1)"]:
		s._check(not (header in texts), "an empty section draws no %s header" % header)
	h.open = keep[0]
	h.coming = keep[1]
	h.meetings = keep[2]
	h.things.pick = keep[3]
	h.things.proposals = keep[4]
	h.fake_hour = was_hour
	s._check(not h.open.is_empty(), "there is a to-do to open")
	var opens: Array[Callable] = [
		sb.back,
		func() -> void: sb.open_item(int(h.open[0]["id"])),
		func() -> void: sb.open_add(),
		sb.open_settings,
	]
	for open in opens:
		open.call()
		await _sync()
		s._check(sb._add.visible and sb._cog.visible, "the header keeps add and settings in %s" % sb.view)
		s._check(sb._back.visible == (sb.view != "home"), "the back chevron is only off Home (%s)" % sb.view)
	sb.back()
	await _sync()
	h.chat.messages = []
	sb.chat_view.set_mode("dock")
	s._check(not sb.chat_view.has_log(), "the dock with no messages is the input line alone")
	h.chat.messages = [{"who": "cat", "text": "meow", "t": Time.get_unix_time_from_system()}]
	s._check(not sb.chat_view.has_log(), "a pet's remark leaves the dock compact")
	h.chat.messages = [
		{"who": "cat", "text": "meow", "t": Time.get_unix_time_from_system()},
		{"who": "me", "text": "hello", "t": Time.get_unix_time_from_system()},
	]
	s._check(sb.chat_view.has_log(), "his line grows it")
	h.chat.messages = [{"who": "home", "text": "done", "t": Time.get_unix_time_from_system()}]
	s._check(sb.chat_view.has_log(), "so does the house's word to him")
	h.chat.messages = [{"who": "me", "text": "hello", "t": Time.get_unix_time_from_system()}]
	s._check(sb.chat_view.has_log(), "a message grows the dock")
	h.chat.messages = keep[5]
	sb.chat_view.set_mode(sb._effective())


# every row that prints a due time words it by the one rule (`logic.gd` holds the rule)
func _times() -> void:
	var was_pick: Dictionary = h.things.pick
	h.things.pick = {}
	var was_hour: float = h.fake_hour
	var was_day: String = h.fake_day
	h.fake_day = "11-18"
	h.fake_hour = 12.0
	var clock: float = h._now_local()
	var local := func(gap: int, hm: String) -> float:
		var p := hm.split(":")
		return floorf(clock / 86400.0) * 86400.0 + gap * 86400.0 + int(p[0]) * 3600.0 + int(p[1]) * 60.0
	var keep := [h.open, h.coming]
	h.open = [{"id": 1, "kind": "reminder", "text": "gone", "due_at": _iso(local.call(-2, "09:00")), "every": null}]
	h.coming = [
		{"id": 2, "kind": "reminder", "text": "swim class", "due_at": _iso(local.call(1, "18:00")), "every": "week"},
		{"id": 3, "kind": "reminder", "text": "rent", "due_at": _iso(local.call(10, "09:00")), "every": "month"},
	]
	var texts := _texts(_home_box())
	var gone: String = When.text(local.call(-2, "09:00"), clock)
	s._check(gone.begins_with("since ") and gone in texts, "Home's open row words a past due time: %s" % str(texts))
	sb.later_expanded = true
	texts = _texts(_home_box())
	sb.later_expanded = false
	var rent: String = When.text(local.call(10, "09:00"), clock)
	s._check(texts.any(func(t: String) -> bool: return t.begins_with("tomorrow 18:00") and t.ends_with("every week")) and texts.any(func(t: String) -> bool: return t.begins_with(rent)), "Later's rows: %s" % str(texts))
	var rows: Array = h.things.calendar_blocks().filter(func(b: Dictionary) -> bool: return b["t"] == "row")
	var bins: Array = rows.filter(func(b: Dictionary) -> bool: return str(b["text"]).ends_with("rent"))
	s._check(
		not bins.is_empty() and bins[0]["text"] == rent + "  rent" and bins[0]["sub"] == "every month",
		"Coming up: the time and the text, the rhythm apart: %s" % str(bins)
	)
	s._check(rows.all(func(b: Dictionary) -> bool: return not "(" in str(b["text"])), "no rhythm is parenthesised into a title")
	s._check(rows.all(func(b: Dictionary) -> bool: return b.get("line", false)), "a Coming up row is one line")
	h.open = keep[0]
	h.coming = keep[1]
	h.fake_day = was_day
	h.fake_hour = was_hour
	h.things.pick = was_pick


# at 1100x700 with the demo list and the dock compact, Home's content fits its pane: no scrolling
func _home_fits() -> void:
	var demo: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://demo.json"))
	var keep := [
		h.open, h.coming, h.notes, h.meetings, h.things.note_rows, h.things.agendas,
		h.things.proposals, h.things.pick, h.weather_desc, h.temp_c, h.chat.messages,
	]
	var size_was: Vector2 = main.size
	h.open = main._demo_due(demo["open"])
	h.coming = main._demo_due(demo["coming"])
	h.notes = demo["notes"]
	h.things.note_rows = []
	h.things.agendas = main._demo_agendas(demo["agendas"])
	h.things.proposals = demo["proposals"]
	h.things.pick = h.open[0]
	h.meetings = main._demo_meetings(demo["meetings"]).filter(func(m: Dictionary) -> bool: return m["day"] != "")
	h.weather_desc = "Sunny"
	h.temp_c = 13
	h.chat.messages = []
	main.size = Vector2(1100, 700)
	sb.back()
	sb.chat_mode = "dock"
	await _laid_out()
	var content: Control = sb.scroll.get_child(0)
	await s._until(
		func(): return content.get_combined_minimum_size().y <= sb.scroll.size.y + 0.5,
		"Home laid out to fit its pane"
	)
	s._check(sb.view == "home" and not sb.chat_view.has_log(), "Home with the dock compact")
	s._check(
		content.get_combined_minimum_size().y <= sb.scroll.size.y + 0.5,
		"Home does not scroll at 1100x700 with the demo list: content %s in a pane of %s" % [content.get_combined_minimum_size().y, sb.scroll.size.y]
	)
	h.coming += main._demo_due(
		[{"id": 90, "kind": "reminder", "text": "swim class", "in_days": 1, "at": "12:00", "every": null}]
	)
	h.things.reset()
	h.card.open("calendar", "cal")
	await _laid_out()
	await s._until(
		func(): return content.get_combined_minimum_size().y <= sb.scroll.size.y + 0.5,
		"the calendar card laid out to fit its pane"
	)
	var blocks: Array = h.things.calendar_blocks()
	var split: int = blocks.find_custom(func(b: Dictionary) -> bool: return b.get("text") == "Coming up")
	var ids := func(part: Array) -> Array:
		return part.filter(func(b: Dictionary) -> bool: return b["t"] == "row").map(func(b: Dictionary) -> String: return str(b["act"]))
	var before: Array = ids.call(blocks.slice(0, split))
	var after: Array = ids.call(blocks.slice(split))
	s._check(split > 0 and not before.is_empty(), "the card lists today's and tomorrow's things before Coming up: split %s, before %s, blocks %s" % [split, before, blocks.map(func(b: Dictionary) -> String: return str(b.get("text", b["t"])))])
	s._check(after.all(func(a: String) -> bool: return a not in before), "Coming up lists only what is after tomorrow: %s against %s" % [after, before])
	s._check(
		content.get_combined_minimum_size().y <= sb.scroll.size.y + 0.5,
		"The calendar card does not scroll at 1100x700 with the demo list: content %s in a pane of %s" % [content.get_combined_minimum_size().y, sb.scroll.size.y]
	)
	h.close_card()
	h.open = keep[0]
	h.coming = keep[1]
	h.notes = keep[2]
	h.meetings = keep[3]
	h.things.note_rows = keep[4]
	h.things.agendas = keep[5]
	h.things.proposals = keep[6]
	h.things.pick = keep[7]
	h.weather_desc = keep[8]
	h.temp_c = keep[9]
	h.chat.messages = keep[10]
	main.size = size_was
	await _sync()
