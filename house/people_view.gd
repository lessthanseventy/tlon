extends RefCounted

# The People view (a card each: next birthday, notes with an add line, the to-dos that name
# them, a form to add or change one) and the Door view (the pile by the door). `sidebar.gd` owns
# when each is built; every change goes out as a write through `home.things` and the view is
# built again from the data that comes back, so a draft is kept here, not in the controls.
const Paper := preload("res://paper.gd")
const Fonts := preload("res://fonts.gd")
const Blocks := preload("res://blocks.gd")
const Views := preload("res://views.gd")
const People := preload("res://people.gd")
const When := preload("res://when.gd")
const SettingsView := preload("res://settings_view.gd")
const DRAFT := {"name": "", "birthday": "", "was": ""}

# "": no form; "new", or "edit:ID"
var form := ""
var draft := DRAFT.duplicate()
# one line over the view: a refusal or a name left out
var say := ""
# the field that had the cursor, which takes it back when the view is built again
var focus := ""

var sb
var home


func _init(the_sidebar, the_home) -> void:
	sb = the_sidebar
	home = the_home


func reset() -> void:
	form = ""
	draft = DRAFT.duplicate()
	say = ""
	focus = ""


func said(line: String) -> void:
	say = line


# what the view shows, so it is built again only when that changes
func signature(view: String) -> String:
	if view == "door":
		return JSON.stringify([home.things.door, say])
	var armed: bool = form.begins_with("edit:") and home.sure.armed("rm:" + form.substr(5))
	return JSON.stringify([home.things.people, form, say, armed, home.today()])


# "new", or "edit" with the person's row
func open_form(mode: String, person: Dictionary = {}) -> void:
	say = ""
	focus = "name"
	if mode == "edit":
		var was := SettingsView.birthday_text(str(person.get("birthday", "")).right(5))
		draft = {"name": str(person["name"]), "birthday": was, "was": was}
		form = "edit:%d" % int(person["id"])
	else:
		draft = DRAFT.duplicate()
		form = "new"


func _close() -> void:
	form = ""
	draft = DRAFT.duplicate()
	say = ""
	focus = ""


func _write(path: String, body: Dictionary, ok: Callable = Callable()) -> void:
	say = ""
	if ok.is_valid():
		home.things.post_kept.emit(path, body, ok)
	else:
		home.things.post.emit(path, body)


func people_view(box: VBoxContainer) -> void:
	_say(box)
	var people: Array = home.things.people
	if people.is_empty():
		box.add_child(
			Views.quiet("No one yet. Add a name, and a birthday if you know it.", Fonts.BODY)
		)
	for p in people:
		if form == "edit:%d" % int(p["id"]):
			_form(box, p)
		else:
			_card(box, p)
	if people.is_empty() or form == "new":
		_form(box, null)
	else:
		Paper.chip("Add a person", Paper.row(box), func() -> void: open_form("new"))


func door_view(box: VBoxContainer) -> void:
	_say(box)
	var notes: Array = home.things.door["notes"]
	if notes.is_empty():
		box.add_child(Views.quiet("Nothing by the door.", Fonts.BODY))
	for n in notes:
		var id := int(n["id"])
		var pad := MarginContainer.new()
		pad.add_theme_constant_override("margin_left", 5)
		pad.add_theme_constant_override("margin_top", 3)
		pad.add_theme_constant_override("margin_bottom", 3)
		box.add_child(pad)
		var line := Paper.row(pad)
		var tick := Blocks.Tick.new()
		tick.tooltip_text = "take it off"
		tick.pressed.connect(func() -> void: home.acted.emit(id, "delete"))
		line.add_child(tick)
		var text := Blocks.wrapped(str(n["text"]), Fonts.BODY, Paper.INK)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(text)
	_add_line(box, "door", "something to take with you", "/api/home/door/add")


func _say(box: VBoxContainer) -> void:
	if say != "":
		box.add_child(Blocks.wrapped(say, Fonts.SMALL, Paper.WARM))


# a line that puts what is typed on a pile when Enter is pressed and keeps the cursor
func _add_line(box: Control, tag: String, hint: String, path: String) -> void:
	var edit := Paper.edit(hint, box)
	edit.focus_entered.connect(func() -> void: focus = tag)
	edit.text_submitted.connect(
		func(text: String) -> void:
			if text.strip_edges() == "":
				return
			edit.clear()
			focus = tag
			_write(path, {"text": text})
	)
	if focus == tag:
		edit.grab_focus.call_deferred()


func _card(box: VBoxContainer, p: Dictionary) -> void:
	var id := int(p["id"])
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.set_border_width_all(1)
	style.border_color = Color(Paper.INK, 0.2)
	style.set_corner_radius_all(2)
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", style)
	box.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	panel.add_child(col)
	var head := Paper.row(col)
	var name := Paper.label(str(p["name"]), Fonts.BODY, Paper.INK)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.clip_text = true
	head.add_child(name)
	Paper.chip("edit", head, func() -> void: open_form("edit", p), false, "quiet")
	var days := People.days_to(p, home.today())
	if days >= 0:
		col.add_child(Views.quiet(When.birthday(days, str(p["next_birthday"]))))
	for n in p.get("notes", []):
		var nid := int(n["id"])
		var line := Paper.row(col)
		var text := Blocks.wrapped(str(n["text"]), Fonts.BODY, Paper.INK)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(text)
		Paper.chip("drop", line, func() -> void: home.acted.emit(nid, "delete"), false, "quiet")
	_add_line(col, "note:%d" % id, "add a note", "/api/home/agendas/%d/add" % id)
	var todos: Array = p.get("todos", [])
	if not todos.is_empty():
		col.add_child(Paper.section("To do"))
	for t in todos:
		var tid := int(t["id"])
		var sub: String = home._clock(home._due(t)) if t.get("due_at") != null else ""
		var row := Blocks.Row.new(str(t["text"]), sub, true, false, true)
		row.pressed.connect(func() -> void: home.open_item(tid))
		row.ticked.connect(func() -> void: home.acted.emit(tid, "done"))
		col.add_child(row)


# a name and a birthday that says what it was read as; `person` is {} for a new one
func _form(box: VBoxContainer, person: Variant) -> void:
	var editing: bool = person != null
	box.add_child(Paper.section("Change" if editing else "Add a person"))
	var name := Paper.edit("name", box)
	name.text = draft["name"]
	var birth := Paper.edit("birthday, if you know it: 8 June or 06-08", box)
	birth.text = draft["birthday"]
	var reading := Views.quiet("")
	box.add_child(reading)
	_read(reading, birth.text)
	name.text_changed.connect(func(t: String) -> void: draft["name"] = t)
	name.focus_entered.connect(func() -> void: focus = "name")
	birth.text_changed.connect(
		func(t: String) -> void:
			draft["birthday"] = t
			_read(reading, t)
	)
	birth.focus_entered.connect(func() -> void: focus = "birthday")
	var go := func(_t: String = "") -> void: _submit(person)
	name.text_submitted.connect(go)
	birth.text_submitted.connect(go)
	match focus:
		"name":
			name.grab_focus.call_deferred()
		"birthday":
			birth.grab_focus.call_deferred()
	var row := Paper.row(box)
	Paper.chip("Save" if editing else "Add", row, go, false, "primary")
	if form != "":
		Paper.chip("Cancel", row, _close, false, "quiet")
	if editing:
		var key := "rm:%d" % int(person["id"])
		var label := "Remove for good?" if home.sure.armed(key) else "Remove"
		Paper.chip(
			label,
			row,
			func() -> void:
				if home.sure.ask(key):
					_write("/api/home/agendas/%d/drop" % int(person["id"]), {}, _close),
			false,
			"quiet"
		)


static func reading_of(text: String) -> Array:
	var parsed: Variant = SettingsView.parse_birthday(text)
	if parsed == null:
		return ["That is not a day. Try 8 June or 06-08.", false]
	if parsed == "":
		return ["No birthday set.", true]
	return ["Kept as %s." % SettingsView.birthday_text(parsed), true]


func _read(label: Label, text: String) -> void:
	var read := reading_of(text)
	label.text = read[0]
	label.add_theme_color_override("font_color", Paper.QUIET if read[1] else Paper.WARM)


func _submit(person: Variant) -> void:
	var name := str(draft["name"]).strip_edges()
	if name == "":
		say = "A name, please."
		return
	var parsed: Variant = SettingsView.parse_birthday(str(draft["birthday"]))
	if parsed == null:
		return
	var body := {"name": name}
	if person == null:
		body["kind"] = "person"
		if parsed != "":
			body["birthday"] = parsed
		_write("/api/home/agendas", body, _close)
		return
	if draft["birthday"] != draft["was"]:
		body["birthday"] = null if parsed == "" else parsed
	_write("/api/home/agendas/%d/edit" % int(person["id"]), body, _close)
