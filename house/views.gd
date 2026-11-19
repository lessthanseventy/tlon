extends RefCounted

# What the sidebar's context pane shows for the things that are lists or blocks: the home view
# (now, next up, open, weather, notes), the office, one item with its actions, the whole desk and
# the blocks of a thing the room's click opened. `sidebar.gd` owns when each is built.
const Paper := preload("res://paper.gd")
const Blocks := preload("res://blocks.gd")
const Card := preload("res://card.gd")
const Forecast := preload("res://forecast.gd")
const Sure := preload("res://sure.gd")
const Settings := preload("res://settings.gd")
const Shelf := preload("res://shelf.gd")
const OPEN_SHOWN := 6
const NEXT_SHOWN := 3
const SHORT := ["jar", "plant", "clock", "found", "globe", "piano", "weather"]
const GOOD := Color("3f7a47")
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
	var l := Paper.heading(text, 14, Paper.INK)
	box.add_child(l)


static func quiet(text: String, size: int = 13) -> Label:
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


func home_view(box: VBoxContainer) -> void:
	_now(box)
	var next: Array = home._upcoming(
		home.coming.filter(func(i: Dictionary) -> bool: return i.get("due_at") != null), NEXT_SHOWN
	)
	var due: Array = home.things.agendas_today()
	var meeting: Dictionary = home.next_meeting()
	if not next.is_empty() or not due.is_empty() or not meeting.is_empty():
		heading(box, "Next up")
		if not meeting.is_empty():
			box.add_child(quiet("%s  ·  %s" % [meeting["title"], home.meeting_time(meeting)], 14))
		for item in next:
			_row(box, item, false, _when(item))
		for a in due:
			var row := Blocks.Row.new(home.things.agenda_line(a), "", false, true)
			row.pressed.connect(func() -> void: home.open_agenda(int(a["id"])))
			box.add_child(row)
	if not home.open.is_empty():
		heading(box, "Open")
		var shown: Array = home.open if sb.open_expanded else home.open.slice(0, OPEN_SHOWN)
		for item in shown:
			_row(box, item, true, _when(item))
		var more: int = home.open.size() - OPEN_SHOWN
		if more > 0:
			var label := "less" if sb.open_expanded else "%d more..." % more
			var row := Blocks.Row.new(label, "", false, true)
			row.pressed.connect(func() -> void: sb.open_expanded = not sb.open_expanded)
			box.add_child(row)
	_weather(box)
	var notes: Array = home.things.note_list()
	if not notes.is_empty():
		var label := "Notes (%d)" % notes.size()
		var row := Blocks.Row.new(("v " if sb.notes_expanded else "> ") + label, "", false)
		row.pressed.connect(func() -> void: sb.notes_expanded = not sb.notes_expanded)
		box.add_child(row)
		if sb.notes_expanded:
			for n in notes:
				var note := Blocks.Row.new("- " + str(n["text"]), "", false)
				note.pressed.connect(func() -> void: home.things.open_note(n))
				box.add_child(note)
	if box.get_child_count() == 0:
		box.add_child(quiet("Nothing waiting. Enjoy it.", 15))


func _now(box: VBoxContainer) -> void:
	if home.focus.active() and home.focus.text != "":
		box.add_child(PinCard.new(home.focus))
	var pick: Dictionary = home.things.pick
	if pick.is_empty():
		return
	var id := int(pick["id"])
	var row := Blocks.Row.new(str(pick["text"]), str(pick.get("why", "")))
	row.pressed.connect(func() -> void: home.open_item(id))
	box.add_child(row)
	_chips(
		box,
		[
			{"label": "Done", "act": "pk_done", "s": 13},
			{"label": "Something else", "act": "pk_else", "s": 13},
			{"label": "Not today", "act": "pk_not", "s": 13},
		],
		func(a: String) -> void: home.card_act(a)
	)


func _weather(box: VBoxContainer) -> void:
	var today: String = home.today()
	var days := Forecast.upcoming(home.forecast, today)
	if home.weather_desc == "" and home.temp_c == null and days.is_empty():
		return
	var strip := Strip.new(home, days, today)
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
		box.add_child(quiet("Nothing waiting. Enjoy it.", 15))
	for item in home.open:
		_row(box, item, true, _when(item))


func item_view(box: VBoxContainer, id: int) -> void:
	var item: Dictionary = home.things.find(id)
	if item.is_empty():
		return
	var kind := str(item.get("kind", "todo"))
	var l := Paper.heading(str(item["text"]), 18, Paper.INK)
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
	box.add_child(quiet("  -  ".join(facts), 14))
	_chips(box, _actions(item, kind), func(a: String) -> void: sb.item_act(id, a))
	var plan: Array = item.get("plan", [])
	for step in plan.slice(0, 3):
		box.add_child(quiet("then " + str(step), 13))
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
	var title := Paper.heading(str(a["name"]), 18, Paper.INK)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size.x = 40
	box.add_child(title)
	box.add_child(quiet(home.things.agenda_rhythm(a), 14))
	var notes: Array = a["notes"]
	if notes.is_empty():
		box.add_child(quiet("Nothing on this pile yet.", 14))
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
		out.append({"label": "Plan", "act": "plan"})
	elif kind in ["todo", "reminder"]:
		out.append({"label": "Done", "act": "done"})
		if home.hearth.lit:
			out.append({"label": "Into the fire", "act": "fire"})
		out.append({"label": "In an hour", "act": "hour"})
		out.append({"label": "Tomorrow", "act": "tomorrow"})
		var pinned: bool = home.focus.id == id
		out.append({"label": "Not now" if pinned else "Now", "act": "unnow" if pinned else "now"})
	elif kind == "waiting":
		out.append({"label": "Got it", "act": "done"})
	out.append({"label": "Edit", "act": "edit"})
	var sure: bool = Sure.needs(item) and home.sure.armed("del:%d" % id)
	out.append({"label": "Delete for good?" if sure else "Delete", "act": "delete"})
	return out


func office_view(box: VBoxContainer, view: Dictionary) -> void:
	if view.is_empty():
		return
	if view["paused"] != "":
		box.add_child(Blocks.wrapped(view["paused"], 15, Paper.WARM))
	heading(box, "Waiting on you")
	if view["waiting"].is_empty() and view["waiting_count"] == 0:
		box.add_child(quiet("Nothing needs you.", 15))
	for w in view["waiting"]:
		box.add_child(Blocks.wrapped(str(w["title"]), 15, Paper.INK))
		box.add_child(Blocks.wrapped(str(w["why"]), 13, Paper.WARM))
	if view["waiting_count"] > view["waiting"].size():
		box.add_child(quiet("%d in all" % view["waiting_count"]))
	heading(box, "The crew")
	if view["crew"].is_empty():
		box.add_child(quiet("Nobody on the bench.", 15))
	for c in view["crew"]:
		var who := str(c["name"])
		if c["role"] != "":
			who += "  -  " + str(c["role"])
		box.add_child(Blocks.wrapped(who, 15, _status_color(c["status"])))
		box.add_child(quiet(str(c["doing"])))
	if view["more"] > 0:
		box.add_child(quiet("+%d more" % view["more"], 15))


static func _status_color(status: String) -> Color:
	match status:
		"working":
			return GOOD
		"waiting":
			return Paper.WARM
		"idle":
			return Paper.INK
	return Paper.QUIET


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
		style.set_border_width_all(2)
		style.border_color = Paper.INK
		style.set_content_margin_all(8)
		add_theme_stylebox_override("panel", style)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 4)
		add_child(col)
		var top := HBoxContainer.new()
		col.add_child(top)
		var tag := Paper.label("NOW", 12, Paper.QUIET)
		tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(tag)
		Paper.chip("x", top, func() -> void: focus.clear(), false).tooltip_text = "not now"
		_text = Blocks.wrapped(focus.text, 16, Paper.INK)
		col.add_child(_text)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		col.add_child(row)
		_ring = Ring.new(focus)
		row.add_child(_ring)
		_len = Paper.chip("", row, func() -> void: focus.cycle(), false)
		_len.tooltip_text = "click to change: 10 / 25 / 45"
		_go = Paper.chip("", row, _toggle, false)

	func _toggle() -> void:
		if focus.running():
			focus.stop()
		else:
			focus.start()

	func _process(_dt: float) -> void:
		_len.text = focus.clock() if focus.running() else "%d min" % focus.minutes
		_len.disabled = focus.running()
		_go.text = "stop" if focus.running() else "start"


# the weather in one line and the next days as small chips; a click opens the window's view
class Strip:
	extends Control
	signal pressed
	var home
	var days: Array
	var today: String
	var _lit := false

	func _init(the_home, rows: Array, day: String) -> void:
		home = the_home
		days = rows
		today = day
		custom_minimum_size = Vector2(0, 28.0 + (52.0 if not rows.is_empty() else 0.0))
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
		var font := ThemeDB.fallback_font
		if _lit:
			draw_rect(Rect2(Vector2.ZERO, size), Color("f8efb8"))
		var sky: String = (
			home.weather_desc if home.weather_desc != "" else home.weather.capitalize()
		)
		if home.temp_c != null:
			sky += ", " + Settings.temp(home.temp_c, home.settings.degrees())
		draw_string(font, Vector2(4, 19), sky, HORIZONTAL_ALIGNMENT_LEFT, size.x - 8, 15, Paper.INK)
		var unit: String = home.settings.degrees()
		var w := (size.x - 8.0) / 3.0
		for i in days.size():
			var d: Dictionary = days[i]
			var at := Vector2(4.0 + i * w, 28.0)
			draw_rect(Rect2(at, Vector2(w - 6.0, 46.0)), Color("e4d8bd"))
			draw_rect(Rect2(at, Vector2(w - 6.0, 46.0)), Paper.INK, false, 1.0)
			var name: String = Forecast.name_of(d["date"], today)
			name = {"Today": "Today", "Tomorrow": "Tmrw"}.get(name, name.substr(0, 3))
			draw_string(
				font, at + Vector2(6, 15), name, HORIZONTAL_ALIGNMENT_LEFT, w - 14, 12, Paper.INK
			)
			Forecast.draw_icon(self, d["kind"], at + Vector2(14, 31), 18.0)
			draw_string(
				font,
				at + Vector2(28, 38),
				Settings.temp(d["high_c"], unit),
				HORIZONTAL_ALIGNMENT_LEFT,
				w - 34,
				13,
				Paper.INK
			)
