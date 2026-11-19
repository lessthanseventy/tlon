extends RefCounted

# The soak's checks of the sidebar as a whole: every thing in the room opens a view or toggles, the
# views never lie outside the window at the smallest and the largest sizes, and a banner never takes
# a view away. Nothing here reaches a server.
const Sidebar := preload("res://sidebar.gd")
const SIZES :=[Vector2(900, 600), Vector2(1100, 700), Vector2(1920, 1080)]
const VIEWS := ["home", "item", "open", "add", "pet", "closet", "settings", "decorate", "card"]
const Blocks := preload("res://blocks.gd")

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
	await _things()
	await _shelf()
	await _agendas()
	await _proposals()
	await _fit()
	await _pet()
	await _banner()
	await _decorate_tabs()
	_meetings()


func _meeting(title: String, from: String, to: String, tentative: bool, day: String) -> Dictionary:
	return {"title": title, "starts_at": from, "ends_at": to, "tentative": tentative, "day": day}


func _meetings() -> void:
	var was: Array = h.meetings
	var now: float = h._now_local() - h._bias()
	var iso := func(at: float) -> String:
		return Time.get_datetime_string_from_unix_time(int(at)) + "Z"
	h.meetings = [
		_meeting("Over", iso.call(now - 7200), iso.call(now - 3600), false, "today"),
		_meeting("Standup", iso.call(now + 600), iso.call(now + 1500), false, "today"),
		_meeting("Review", iso.call(now + 90000), iso.call(now + 92000), true, "tomorrow"),
	]
	var meet := func(b: Dictionary) -> bool: return b["t"] == "meet"
	s._check(h.next_meeting().get("title") == "Standup", "Next up shows today's next meeting")
	var blocks: Array = h.meeting_blocks().filter(meet)
	s._check(blocks.size() == 3 and blocks[2]["dim"], "the calendar lists them, tentative dimmed")
	s._check(h.things.calendar_blocks().any(meet), "the calendar card has them")
	h.meetings = []
	s._check(h.next_meeting().is_empty() and h.meeting_blocks().is_empty(), "none shows nothing")
	h.meetings = was


func _texts(node: Node, out: Array = []) -> Array:
	for c in node.get_children():
		if c is Label:
			out.append(c.text)
		_texts(c, out)
	return out


func _row(node: Node, text: String) -> Variant:
	for c in node.get_children():
		if c is Blocks.Row and _texts(c)[0] == text:
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
	await _frames()


func _open_shelf() -> void:
	main._at = "home"
	sb.back()
	h.decorating = false
	await _frames()
	var c: Variant = _centre("furn:bookshelf")
	s._check(c != null, "the room has a bookshelf to click")
	if c != null:
		h.click(c)
	await _frames()


func _filter(text: String) -> void:
	for c in sb._dyn.find_children("*", "LineEdit", true, false):
		c.text = text
		c.text_changed.emit(text)
	await _frames()


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
	for i in 30:
		if s._count("/api/home") > before:
			break
		await s.create_timer(0.1).timeout
	await s.create_timer(0.45).timeout
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
	await s.create_timer(1.0).timeout
	await _open_shelf()
	texts = _texts(sb._dyn)
	s._check(sb.view == "card" and "Notes (9)" in texts and "note 3" not in texts, "deleting a note takes it off the shelf")
	s._check("2 more..." in texts or "1 more..." in texts, "the shelf opens collapsed again")
	sb.back()
	await _frames()
	h.things.open_note({"id": 0, "text": "plain"})
	await _frames()
	s._check(h.card.kind == "board" and h.things.tab == "notes", "a note with no id opens the board's notes")
	sb.back()
	await _open_shelf()
	await _press("learn sourdough")
	s._check(sb.view == "item" and int(sb.arg) == 51, "a someday row opens that item")
	sb.back()
	s._state = keep
	main._poll()
	await s.create_timer(0.45).timeout


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
# one due today under Next up
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
	for i in 30:
		if s._count("/api/home") > before:
			break
		await s.create_timer(0.1).timeout
	await s.create_timer(0.45).timeout
	sb.back()
	await _frames()
	var texts: Array = _texts(sb._dyn)
	s._check("Next up" in texts and "Retro at 14:00 - 2 things" in texts, "Home has a quiet row for an agenda due today: %s" % str(texts))
	await _press("Retro at 14:00 - 2 things")
	s._check(sb.view == "agenda" and int(sb.arg) == 71, "the row opens the agenda")
	texts = _texts(sb._dyn)
	var rhythm: String = h.things.agenda_rhythm(retro)
	s._check("retro" in texts and rhythm in texts and rhythm.begins_with("every other week, next "), "the agenda shows its name and its rhythm as text: %s" % rhythm)
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
	await _frames()
	var posts := _posted("/api/home/agendas/71/add")
	s._check(posts.size() == 1 and JSON.parse_string(posts[0][2]) == {"text": "nobody owned the rollback"}, "Enter adds the note to this agenda: %s" % str(posts))
	var clear: Variant = _button("Clear")
	s._check(clear != null, "a pile with notes has Clear")
	if clear != null:
		clear.pressed.emit()
	await _frames()
	s._check(_posted("/api/home/agendas/71/clear").size() == 1, "Clear asks the home to archive the pile")
	sb.back()
	await _frames()
	s._check(sb.view == "card" and h.card.kind == "book", "back from an agenda opened on the shelf is the shelf")
	await _press("new agenda")
	var name_edit: Variant = _edit("name the agenda")
	s._check(name_edit != null, "new agenda opens a line for the name")
	if name_edit != null:
		name_edit.text_submitted.emit("offsite")
	await _frames()
	s._check(_posted("/api/home/agendas").size() == 1, "a name makes a new agenda")
	sb.back()
	s._state = keep
	main._poll()
	await s.create_timer(0.45).timeout


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
	await _frames()
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
	for i in 30:
		if not _posted("/api/home/proposals/80/take").is_empty():
			break
		await s.create_timer(0.1).timeout
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
	for i in 30:
		if not _posted("/api/home/proposals/81/dismiss").is_empty():
			break
		await s.create_timer(0.1).timeout
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
	for i in 30:
		if s._count("/api/home") > before:
			break
		await s.create_timer(0.1).timeout
	await s.create_timer(0.45).timeout


func _settle_home() -> void:
	await _poll_home()
	sb.back()
	await _frames()


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
	await s.create_timer(1.2).timeout
	texts = _texts(sb._dyn)
	s._check("Agendas (1)" in texts and "retro" in texts, "the local list makes the agenda: %s" % str(texts.slice(0, 5)))
	await _press("retro")
	s._check(sb.view == "agenda", "the local agenda opens")
	var edit: Variant = _edit("add a note")
	if edit != null:
		edit.text_submitted.emit("flaky gate")
	await s.create_timer(1.2).timeout
	s._check("flaky gate" in _texts(sb._dyn), "the local list puts the note on the pile")
	var clear: Variant = _button("Clear")
	if clear != null:
		clear.pressed.emit()
	await s.create_timer(1.2).timeout
	s._check("Nothing on this pile yet." in _texts(sb._dyn), "Clear leaves the local agenda empty")
	s._check("flaky gate" not in h.notes and h.things.note_list().all(func(n): return n["text"] != "flaky gate"), "a pile's notes are not in the plain notes")
	sb.back()
	await _frames()
	sb.back()
	await _frames()


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
		await _frames()
		s._check(sb.view == "item" and str(kept[0]["text"]) in _texts(sb._dyn), "a local note opens its item view")
	sb.back()
	await _frames()


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
	main._at = "home"
	sb.back()
	h.decorating = false
	await _frames()
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
		await _frames()
		var was := [sb.view, h.card.kind, h.tv.on, sb._effective()]
		h.click(c)
		await _frames()
		var now := [sb.view, h.card.kind, h.tv.on, sb._effective()]
		s._check(now != was, "a click on %s opens a view or toggles (%s)" % [key, str(now)])
		if key != "tv" and key != "phone":
			s._check(sb.selected_key() == h.selected, "%s stays highlighted" % key)
		sb.back()
		await _frames()
	s._check(seen >= 8, "the room has things to click: %d" % seen)
	sb.back()
	var a: Variant = _centre("cal")
	var b: Variant = _centre("jar")
	if a != null and b != null:
		h.click(a)
		await _frames()
		h.click(b)
		await _frames()
		s._check(sb.view == "card" and h.card.kind == "jar", "thing B replaces thing A's view")
		sb.back()
		await _frames()
		s._check(sb.view == "home" and h.selected == "", "back brings the home view, nothing selected")


# every control of every view sits inside the window, at the smallest and the largest size
func _fit() -> void:
	var was: Vector2 = main.size
	for size in SIZES:
		main.size = size
		var win := Rect2(Vector2.ZERO, size)
		for name in ["home", "add", "pet", "pet_edit", "closet", "settings", "card"]:
			sb.back()
			await _frames()
			match name:
				"add":
					sb.open_add(true)
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
			await _frames(4)
			var out := _outside(win)
			s._check(out == "", "no %s control lies outside a %s window: %s" % [name, size, out])
			s._check(sb.get_global_rect().end.x <= size.x + 0.5, "the sidebar fits a %s window" % size)
		sb.back()
	main.size = was
	await _frames()


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
	main._at = "home"
	sb.back()
	await _frames()
	var cat = h.pets.critter("nina")
	var c: Vector2 = h.pets.hit_rect(cat, h._o, h._k).get_center()
	if h.pet_at(c) == "nina":
		h.click(c)
	else:
		main._on_viewed("pet", "nina")
	await _frames()
	var v = sb.pet_view
	s._check(sb.view == "pet" and v.visible, "a click on a pet opens its view")
	s._check(v._page.visible and not v._tiles["cat_black"].is_visible_in_tree(), "not the kind grid")
	s._check(not sb.takes_text(), "the pets go on with their day while it is open")
	v._open_edit()
	await _frames()
	s._check(sb.takes_text() and v._tiles["cat_black"].is_visible_in_tree(), "change who this is")
	s._check(is_equal_approx(sb.size.x, Sidebar.WIDTH), "the pane stays %d wide" % Sidebar.WIDTH)
	sb.back()
	await _frames()
	s._check(sb.view == "pet" and v._page.visible and not v.editing, "Esc goes back to the pet")
	sb.back()
	await _frames()
	s._check(sb.view == "home", "and again goes home")


# a slip or a ring over an open view takes nothing from it
func _banner() -> void:
	sb.back()
	main._open_add(false)
	await _frames()
	var form_was: bool = sb.form.visible
	h.rhythm.show_slip("home", "Still open", [])
	await _frames()
	s._check(sb.view == "add" and sb.form.visible == form_was, "a slip leaves the add view be")
	h.rhythm.dismiss()
	main._open_settings()
	h.show_reply("noted")
	await _frames()
	s._check(sb.view == "settings", "a reply leaves the settings be")
	sb.back()
	await _frames()
	s._check(sb.view == "home", "and back still goes home")


# the pane is no wider than its 360 px with the decorate view up, whichever tab, and every tab shows
func _decorate_tabs() -> void:
	if not h.layout.art:
		return
	main._set_decorate(true)
	await _frames(3)
	var d = main._decorate
	for t in h.layout.tabs:
		d.tab = t
		d.queue_redraw()
		await _frames(2)
		s._check(sb.get_global_rect().size.x <= sb.WIDTH + 0.5, "the sidebar stays %d wide on %s" % [sb.WIDTH, t])
	for hit in d._hits:
		if str(hit["act"]).begins_with("tab:"):
			s._check(hit["rect"].end.x <= d.size.x - 4.0, "the %s tab fits the pane" % hit["act"])
	main._set_decorate(false)
	await _frames()
