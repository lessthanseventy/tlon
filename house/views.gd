extends RefCounted

# What the sidebar's context pane shows for the things that are lists or blocks: the home view
# (now, today, open, proposed, later, weather, notes), one item with its actions, the whole desk
# and the blocks of a thing the room's click opened. `sidebar.gd` owns when each is built.
const Paper := preload("res://paper.gd")
const Fonts := preload("res://fonts.gd")
const Blocks := preload("res://blocks.gd")
const Card := preload("res://card.gd")
const Sure := preload("res://sure.gd")
const Settings := preload("res://settings.gd")
const Shelf := preload("res://shelf.gd")
const Money := preload("res://money.gd")
const OPEN_SHOWN := 6
const PROPOSED_SHOWN := 3
const SHORT := ["jar", "plant", "clock", "found", "globe", "piano", "weather"]
const KINDS := {
	"todo": "a to-do",
	"reminder": "a reminder",
	"note": "a note",
	"waiting": "waiting on someone",
	"project": "a project",
}

var home
var sb
var shelf


func _init(the_sidebar, the_home) -> void:
	sb = the_sidebar
	home = the_home
	shelf = Shelf.new(sb, home)


static func heading(box: Control, text: String) -> void:
	box.add_child(Paper.section(text, 5))


static func quiet(text: String, size: int = Fonts.SMALL) -> Label:
	return Blocks.wrapped(text, size, Paper.QUIET)


func _when(item: Dictionary) -> String:
	var parts: Array[String] = []
	if item.get("due_at") != null:
		parts.append(home._clock(home._due(item)))
	if item.get("every") != null:
		parts.append(Card.every_words(str(item["every"])))
	return "  -  ".join(parts)


func _row(box: Control, item: Dictionary, tick: bool, sub: String) -> void:
	var id := int(item["id"])
	var row := Blocks.Row.new(str(item["text"]), sub, tick, false, true)
	row.pressed.connect(func() -> void: home.open_item(id))
	row.ticked.connect(func() -> void: home.acted.emit(id, "done"))
	box.add_child(row)


func _chips(box: Control, items: Array, act: Callable) -> void:
	Blocks.build(box, [{"t": "buttons", "items": items}], act)


# the pinned thing and the pick, which Open leaves out
func _in_now() -> Array:
	var ids: Array = []
	if home.focus.active() and home.focus.text != "":
		ids.append(int(home.focus.id))
	if not home.things.pick.is_empty():
		ids.append(int(home.things.pick["id"]))
	return ids


func home_view(box: VBoxContainer) -> void:
	_now(box)
	_today(box)
	_open(box)
	_proposed(box)
	_later(box)
	_weather(box)
	_notes(box)
	if box.get_child_count() == 0:
		box.add_child(quiet("Nothing waiting. Enjoy it.", Fonts.BODY))


# what has a time today, in time order: meetings still on, reminders, an agenda that is due
func _today(box: VBoxContainer) -> void:
	var now: float = home._now_local()
	var today: String = home.today()
	var entries: Array = []
	for m in home.meetings:
		if m.get("day") != "today" or home._local(str(m["ends_at"])) <= now:
			continue
		var at: float = -1.0 if m.get("all_day", false) else home._local(str(m["starts_at"]))
		entries.append({"at": at, "meeting": m})
	for item in home.coming:
		if item.get("due_at") == null or home.chore_thing_of(int(item["id"])) != "":
			continue
		var at: float = home._due(item)
		if Time.get_date_string_from_unix_time(int(at)) == today:
			entries.append({"at": at, "item": item})
	for a in home.things.agendas_today():
		entries.append({"at": home.things._agenda_at(a), "agenda": a})
	for p in home.things.people:
		if str(p.get("next_birthday", "")) == today:
			entries.append({"at": -1.0, "birthday": p})
	var due := Money.today_row(home.things.money, today)
	if due != "":
		entries.append({"at": -1.0, "money": due})
	if entries.is_empty():
		return
	entries.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x["at"] < y["at"])
	heading(box, "Today")
	for e in entries:
		var at: float = e["at"]
		if e.has("meeting"):
			var m: Dictionary = e["meeting"]
			var line := HBoxContainer.new()
			line.add_theme_constant_override("separation", 8)
			var pad := MarginContainer.new()
			pad.add_theme_constant_override("margin_left", 5)
			pad.add_child(line)
			line.add_child(_time_col(home.meeting_time(m)))
			var title := quiet(str(m["title"]), Fonts.BODY)
			title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			line.add_child(title)
			box.add_child(pad)
		elif e.has("item"):
			var item: Dictionary = e["item"]
			var id := int(item["id"])
			var every := "" if item.get("every") == null else Card.every_words(str(item["every"]))
			var row := Blocks.Row.new(str(item["text"]), every, false, false, true)
			row.pressed.connect(func() -> void: home.open_item(id))
			_put_time(row, _hm(at))
			box.add_child(row)
		elif e.has("birthday"):
			var row := Blocks.Row.new("%s's birthday" % e["birthday"]["name"], "", false, false, true)
			row.pressed.connect(func() -> void: sb.open_people())
			_put_time(row, "")
			box.add_child(row)
		elif e.has("money"):
			var row := Blocks.Row.new(str(e["money"]), "", false, false, true)
			row.pressed.connect(func() -> void: sb.open_money())
			_put_time(row, "")
			box.add_child(row)
		else:
			var a: Dictionary = e["agenda"]
			var n: int = (a["notes"] as Array).size()
			var name := str(a["name"])
			var text := "%s · %d thing%s" % [name.substr(0, 1).to_upper() + name.substr(1), n, "" if n == 1 else "s"]
			var row := Blocks.Row.new(text, "", false, true, true)
			row.pressed.connect(func() -> void: home.open_agenda(int(a["id"])))
			_put_time(row, _hm(at))
			box.add_child(row)


static func _hm(at: float) -> String:
	var d := Time.get_datetime_dict_from_unix_time(int(at))
	return "%02d:%02d" % [d["hour"], d["minute"]]


# the one column the times of Today line up in
static func _time_col(text: String) -> Label:
	var l := Paper.label(text, Fonts.SMALL, Paper.QUIET)
	l.custom_minimum_size.x = 44
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func _put_time(row: Blocks.Row, text: String) -> void:
	var h: HBoxContainer = row.get_child(0)
	var col := _time_col(text)
	h.add_child(col)
	h.move_child(col, 0)


func _open(box: VBoxContainer) -> void:
	var skip := _in_now()
	var rows: Array = home.open.filter(
		func(i: Dictionary) -> bool:
			return int(i["id"]) not in skip and home.chore_thing_of(int(i["id"])) == ""
	)
	if rows.is_empty():
		return
	heading(box, "Open")
	for item in rows if sb.open_expanded else rows.slice(0, OPEN_SHOWN):
		_row(box, item, true, _when(item))
	var more := rows.size() - OPEN_SHOWN
	if more > 0:
		var label := "less" if sb.open_expanded else "%d more..." % more
		var row := Blocks.Row.new(label, "", false, true, true)
		row.pressed.connect(func() -> void: sb.open_expanded = not sb.open_expanded)
		box.add_child(row)


# the coming things after today, one line until opened
func _later(box: VBoxContainer) -> void:
	var today: String = home.today()
	var rows: Array = home.coming.filter(
		func(i: Dictionary) -> bool:
			return (
				home.chore_thing_of(int(i["id"])) == ""
				and (
					i.get("due_at") == null
					or Time.get_date_string_from_unix_time(int(home._due(i))) != today
				)
			)
	)
	if rows.is_empty():
		return
	rows.sort_custom(
		func(x: Dictionary, y: Dictionary) -> bool:
			if x.get("due_at") == null or y.get("due_at") == null:
				return x.get("due_at") != null and y.get("due_at") == null
			return home._due(x) < home._due(y)
	)
	var fold := Blocks.Fold.new("Later (%d)" % rows.size(), sb.later_expanded)
	fold.pressed.connect(func() -> void: sb.later_expanded = not sb.later_expanded)
	box.add_child(fold)
	if sb.later_expanded:
		for item in rows:
			_row(box, item, false, _when(item))


func _notes(box: VBoxContainer) -> void:
	var notes: Array = home.things.note_list()
	if notes.is_empty():
		return
	var fold := Blocks.Fold.new("Notes (%d)" % notes.size(), sb.notes_expanded)
	fold.pressed.connect(func() -> void: sb.notes_expanded = not sb.notes_expanded)
	box.add_child(fold)
	if sb.notes_expanded:
		for n in notes:
			var note := Blocks.Row.new(str(n["text"]), "", false)
			note.pressed.connect(func() -> void: home.things.open_note(n))
			box.add_child(note)


# what outside sources suggest: never a banner, a ring or a badge, only these rows
func _proposed(box: VBoxContainer) -> void:
	var rows: Array = home.things.proposals
	if rows.is_empty():
		return
	heading(box, "Proposed (%d)" % rows.size())
	var shown: Array = rows if sb.proposed_expanded else rows.slice(0, PROPOSED_SHOWN)
	for p in shown:
		var id := int(p["id"])
		var why = p.get("why")
		var row := Blocks.Row.new(str(p["text"]), "" if why == null else str(why))
		row.marks(
			[{"label": "add", "act": "take"}, {"label": "no", "act": "no", "k": "quiet"}],
			func(a: String) -> void: home.acted.emit(id, "propose_" + a)
		)
		box.add_child(row)
	var more: int = rows.size() - PROPOSED_SHOWN
	if more > 0:
		var label := "less" if sb.proposed_expanded else "%d more..." % more
		var row := Blocks.Row.new(label, "", false, true, true)
		row.pressed.connect(func() -> void: sb.proposed_expanded = not sb.proposed_expanded)
		box.add_child(row)


func _now(box: VBoxContainer) -> void:
	var pick: Dictionary = home.things.pick
	var pinned: bool = home.focus.active() and home.focus.text != ""
	if pick.is_empty() and not pinned:
		return
	heading(box, "Now")
	if pinned:
		box.add_child(PinCard.new(home.focus))
	if pick.is_empty():
		return
	var id := int(pick["id"])
	var row := Blocks.Row.new(str(pick["text"]), str(pick.get("why", "")))
	row.pressed.connect(func() -> void: home.open_item(id))
	box.add_child(row)
	_chips(
		box,
		[
			{"label": "Done", "act": "pk_done", "k": "primary"},
			{"label": "Something else", "act": "pk_else", "k": "quiet"},
			{"label": "Not today", "act": "pk_not", "k": "quiet"},
		],
		func(a: String) -> void: home.card_act(a)
	)


func _weather(box: VBoxContainer) -> void:
	if home.weather_desc == "" and home.temp_c == null:
		return
	var strip := Strip.new(home)
	strip.pressed.connect(func() -> void: sb.open_card("weather"))
	box.add_child(strip)


func card_view(box: VBoxContainer) -> void:
	if home.card.kind == "book":
		shelf.build(box, home.card_blocks()[0])
		return
	Blocks.build(box, home.card_blocks(), func(a: String) -> void: home.card_act(a))
	if home.card.kind in SHORT:
		_now(box)


func open_view(box: VBoxContainer) -> void:
	if home.open.is_empty():
		box.add_child(quiet("Nothing waiting. Enjoy it.", Fonts.BODY))
	for item in home.open:
		_row(box, item, true, _when(item))


func item_view(box: VBoxContainer, id: int) -> void:
	var item: Dictionary = home.things.find(id)
	if item.is_empty():
		return
	var kind := str(item.get("kind", "todo"))
	var l := Paper.label(str(item["text"]), Fonts.BODY, Paper.INK)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 40
	box.add_child(l)
	var facts: Array = [KINDS.get(kind, kind)]
	if item.get("who") != null:
		facts.append("from " + str(item["who"]))
	if item.get("due_at") != null:
		facts.append(home._clock(home._due(item)))
	if item.get("every") != null:
		facts.append(Card.every_words(str(item["every"])))
	if item.get("since") != null:
		facts.append("said " + home._ago(str(item["since"])))
	box.add_child(quiet("  -  ".join(facts)))
	_chips(box, _actions(item, kind), func(a: String) -> void: sb.item_act(id, a))
	var plan: Array = item.get("plan", [])
	for step in plan.slice(0, 3):
		box.add_child(quiet("then " + str(step)))
	var others: Array = home.open.filter(func(t: Dictionary) -> bool: return int(t["id"]) != id)
	if kind != "note" and not others.is_empty():
		heading(box, "Other open")
		for other in others.slice(0, 3):
			_row(box, other, true, _when(other))


# an agenda's pile: its rhythm as text, the notes (each opens as a note), a line to add one, Clear
func agenda_view(box: VBoxContainer, id: int) -> void:
	var a: Dictionary = home.things.agenda(id)
	if a.is_empty():
		return
	var title := Paper.label(str(a["name"]), Fonts.BODY, Paper.INK)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size.x = 40
	box.add_child(title)
	box.add_child(quiet(home.things.agenda_rhythm(a)))
	var notes: Array = a["notes"]
	if notes.is_empty():
		box.add_child(quiet("Nothing on this pile yet."))
	for n in notes:
		var said: String = "" if n.get("since") == null else "said " + home._ago(str(n["since"]))
		var row := Blocks.Row.new(str(n["text"]), said)
		row.pressed.connect(func() -> void: home.open_item(int(n["id"])))
		box.add_child(row)
	var edit := Paper.edit("add a note", box)
	edit.text_submitted.connect(
		func(text: String) -> void:
			if text.strip_edges() == "":
				return
			edit.clear()
			sb.agenda_typing = true
			home.things.post.emit("/api/home/agendas/%d/add" % id, {"text": text})
	)
	if sb.agenda_typing:
		edit.grab_focus.call_deferred()
	if not notes.is_empty():
		_chips(
			box,
			[{"label": "Clear", "act": "clear"}],
			func(_a: String) -> void:
				home.things.post.emit("/api/home/agendas/%d/clear" % id, {})
		)


func _actions(item: Dictionary, kind: String) -> Array:
	var id := int(item["id"])
	var out: Array = []
	if kind == "project":
		out.append({"label": "Plan", "act": "plan", "k": "primary"})
	elif kind in ["todo", "reminder"]:
		out.append({"label": "Done", "act": "done", "k": "primary"})
		if home.hearth.lit:
			out.append({"label": "Into the fire", "act": "fire"})
		out.append({"label": "In an hour", "act": "hour"})
		out.append({"label": "Tomorrow", "act": "tomorrow"})
		var pinned: bool = home.focus.id == id
		out.append({"label": "Not now" if pinned else "Now", "act": "unnow" if pinned else "now"})
	elif kind == "waiting":
		out.append({"label": "Got it", "act": "done", "k": "primary"})
	out.append({"label": "Edit", "act": "edit"})
	var sure: bool = Sure.needs(item) and home.sure.armed("del:%d" % id)
	out.append({"label": "Delete for good?" if sure else "Delete", "act": "delete", "k": "quiet"})
	return out


# the pinned thing with its timer
class PinCard:
	extends PanelContainer
	var focus
	var _text: Label
	var _len: Button
	var _go: Button
	var _ring: Ring

	class Ring:
		extends Control
		var focus

		func _init(f) -> void:
			focus = f
			custom_minimum_size = Vector2(34, 34)

		func _process(_dt: float) -> void:
			if focus.running():
				queue_redraw()

		func _draw() -> void:
			var mid := size / 2.0
			draw_arc(mid, 13, 0, TAU, 28, Color(0.1, 0.09, 0.12, 0.25), 4.0)
			if focus.running():
				draw_arc(
					mid, 13, -PI / 2, -PI / 2 + TAU * focus.progress(), 28, Color("5fa86a"), 5.0
				)

	func _init(f) -> void:
		focus = f
		var style := StyleBoxFlat.new()
		style.bg_color = Color("f8efb8")
		style.set_border_width_all(1)
		style.border_color = Color(Paper.INK, 0.4)
		style.set_content_margin_all(8)
		add_theme_stylebox_override("panel", style)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 4)
		add_child(col)
		var top := HBoxContainer.new()
		col.add_child(top)
		var tag := Paper.label("Pinned", Fonts.LABEL, Paper.QUIET)
		tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(tag)
		Paper.chip("Not now", top, func() -> void: focus.clear(), false, "quiet")
		_text = Blocks.wrapped(focus.text, Fonts.BODY, Paper.INK)
		col.add_child(_text)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		col.add_child(row)
		_ring = Ring.new(focus)
		row.add_child(_ring)
		_len = Paper.chip("", row, func() -> void: focus.cycle(), false)
		_len.tooltip_text = "Change: 10 / 25 / 45 min"
		_go = Paper.chip("", row, _toggle, false, "primary")

	func _toggle() -> void:
		if focus.running():
			focus.stop()
		else:
			focus.start()

	func _process(_dt: float) -> void:
		_len.text = focus.clock() if focus.running() else "%d min" % focus.minutes
		_len.disabled = focus.running()
		_go.text = "Stop" if focus.running() else "Start"


# the weather in one line; a click opens the window's view
class Strip:
	extends Control
	signal pressed
	var home
	var _lit := false

	func _init(the_home) -> void:
		home = the_home
		custom_minimum_size = Vector2(0, 26)
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func() -> void: _light(true))
		mouse_exited.connect(func() -> void: _light(false))

	func _light(on: bool) -> void:
		_lit = on
		queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if (
			event is InputEventMouseButton
			and event.pressed
			and event.button_index == MOUSE_BUTTON_LEFT
		):
			accept_event()
			pressed.emit()

	func _draw() -> void:
		if _lit:
			draw_rect(Rect2(Vector2.ZERO, size), Color("f8efb8"))
		var sky: String = (
			home.weather_desc if home.weather_desc != "" else home.weather.capitalize()
		)
		if home.temp_c != null:
			sky += ", " + Settings.temp(home.temp_c, home.settings.degrees())
		draw_string(
			ThemeDB.fallback_font,
			Vector2(5, 18),
			sky,
			HORIZONTAL_ALIGNMENT_LEFT,
			size.x - 8,
			Fonts.BODY,
			Paper.INK
		)


# what a kept thing was read as, for the jot's read-back
static func read_as(row: Dictionary) -> String:
	match str(row.get("kind", "todo")):
		"reminder":
			return "Reminder"
		"note":
			return "Note"
		"waiting":
			return "Waiting on " + str(row.get("who", "someone"))
		"project":
			return "Project"
	return "To-do"
