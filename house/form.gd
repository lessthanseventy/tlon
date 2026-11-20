extends PanelContainer

# The paper form: put a thing in, or change one. It builds the request and hands it up (main.gd
# sends it); a line the server answers with is shown here and what was typed stays.
signal submitted(req: Dictionary)
signal acted(id: int, what: String)
signal cancelled

const Card := preload("res://card.gd")
const Paper := preload("res://paper.gd")
const Fonts := preload("res://fonts.gd")
const Icons := preload("res://icons.gd")
const Sure := preload("res://sure.gd")


const INK := Color("2a2530")
const PAPER := Color("f3ead6")
const QUIET := Color(0.165, 0.145, 0.188, 0.6)
const WARM := Color("a8453c")
const GOLD := Color("e8c77a")
const KINDS := {
	"todo": "To-do",
	"reminder": "Reminder",
	"note": "Note",
	"waiting": "Waiting on someone",
	"project": "Project (several steps)",
}
const PLACEHOLDERS := {
	"todo": "What needs doing?",
	"reminder": "What should the house remind you of?",
	"note": "What is the note?",
	"waiting": "What are you waiting for?",
	"project": "Name the project",
}
const EVERY := {"once": "once", "day": "every day", "week": "every week", "month": "every month"}
const UNITS := ["day", "week", "month"]
const TIMES := {"morning": "09:00", "noon": "12:00", "evening": "19:00"}

var kind := "reminder"
var id := 0
var project := 0
var sure := Sure.new()

var _was := ""
var _was_every := ""
var _busy := false
var _today := {}
var _mode := "once"
var _unit := "week"
var _kind_chips := {}
var _every_chips := {}
var _unit_chips := {}
var _title: Label
var _kind_row: Container
var _who_row: Container
var _who: LineEdit
var _text: LineEdit
var _steps: TextEdit
var _when: VBoxContainer
var _month: MiniMonth
var _time: LineEdit
var _n: LineEdit
var _err: Label
var _save: Button
var _done: Button
var _stop: Button
var _del: Button


class MiniMonth:
	extends Control
	signal changed
	const CELL := Vector2(34.0, 22.0)
	var year := 2026
	var month := 1
	var sel := {}
	var today := {}
	var _prev := Rect2()
	var _next := Rect2()
	var _name := Rect2()

	func _init() -> void:
		custom_minimum_size = Vector2(7.0 * CELL.x, 24.0 + 18.0 + 6.0 * CELL.y)
		mouse_filter = Control.MOUSE_FILTER_STOP

	func show_month(y: int, m: int) -> void:
		year = y
		month = m
		queue_redraw()

	func step(by: int) -> void:
		var idx := year * 12 + month - 1 + by
		show_month(idx / 12, idx % 12 + 1)

	func _gui_input(event: InputEvent) -> void:
		if not (event is InputEventMouseButton and event.pressed and event.button_index == 1):
			return
		var pos: Vector2 = event.position
		if _prev.has_point(pos):
			step(-1)
		elif _next.has_point(pos):
			step(1)
		elif _name.has_point(pos) and not today.is_empty():
			show_month(today["y"], today["m"])
		else:
			var info := Card.month_info(year, month)
			var at := pos - Vector2(0, 42)
			var col := int(at.x / CELL.x)
			var idx := int(at.y / CELL.y) * 7 + col - int(info["first"])
			if at.y >= 0 and col < 7 and idx >= 0 and idx < int(info["days"]):
				sel = {"y": year, "m": month, "d": idx + 1}
				changed.emit()
		queue_redraw()

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var title := "%s %d" % [Card.MONTHS[month - 1], year]
		draw_string(font, Vector2(0, 16), title, HORIZONTAL_ALIGNMENT_LEFT, -1, Fonts.BODY, INK)
		_name = Rect2(Vector2.ZERO, Vector2(font.get_string_size(title, 0, -1, Fonts.BODY).x, 22))
		_prev = Rect2(size.x - 60, 0, 28, 22)
		_next = Rect2(size.x - 30, 0, 28, 22)
		Icons.draw(self, "left", _prev.get_center(), Color(INK, 0.75))
		Icons.draw(self, "right", _next.get_center(), Color(INK, 0.75))
		for i in 7:
			draw_string(font, Vector2(i * CELL.x + 12, 38), Card.WEEK[i], 0, -1, Fonts.LABEL, QUIET)
		var info := Card.month_info(year, month)
		for d in range(1, int(info["days"]) + 1):
			var idx: int = int(info["first"]) + d - 1
			var cell := Vector2((idx % 7) * CELL.x, 42.0 + (idx / 7) * CELL.y)
			var mid := cell + CELL / 2.0
			if today.get("y") == year and today.get("m") == month and today.get("d") == d:
				draw_circle(mid, 10.0, Color("e8b86d"))
			if sel.get("y") == year and sel.get("m") == month and sel.get("d") == d:
				draw_arc(mid, 11.0, 0.0, TAU, 24, INK, 2.0)
			var w := font.get_string_size(str(d), 0, -1, Fonts.BODY).x
			draw_string(font, cell + Vector2((CELL.x - w) / 2.0, 16), str(d), 0, -1, Fonts.BODY, INK)


func _ready() -> void:
	visible = false
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	_title = _label("", Fonts.BODY, INK)
	col.add_child(_title)
	_kind_row = _row(col)
	for k in KINDS:
		_kind_chips[k] = _chip(KINDS[k], _kind_row, func() -> void: _set_kind(k))
	_who_row = HBoxContainer.new()
	_who_row.add_theme_constant_override("separation", 6)
	col.add_child(_who_row)
	_who_row.add_child(_label("who", Fonts.SMALL, QUIET))
	_who = _edit("a name", _who_row)
	_text = _edit("", col)
	_steps = TextEdit.new()
	_steps.placeholder_text = "the first step, then one more per line"
	_steps.custom_minimum_size = Vector2(0, 90)
	_steps.add_theme_color_override("font_color", INK)
	_steps.add_theme_color_override("caret_color", INK)
	_steps.add_theme_color_override("font_placeholder_color", Color(INK, 0.4))
	_steps.add_theme_font_size_override("font_size", Fonts.BODY)
	var flat := _flat()
	for s in ["normal", "focus", "read_only"]:
		_steps.add_theme_stylebox_override(s, flat)
	_steps.gui_input.connect(_steps_key)
	col.add_child(_steps)
	_when = VBoxContainer.new()
	_when.add_theme_constant_override("separation", 6)
	col.add_child(_when)
	_month = MiniMonth.new()
	_when.add_child(_month)
	var time_row := _row(_when)
	time_row.add_child(_label("time", Fonts.SMALL, QUIET))
	_time = _edit("09:00", time_row)
	_time.custom_minimum_size.x = 70
	_time.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_time.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for t in TIMES:
		_chip(
			"%s %s" % [t, TIMES[t]] if t != "noon" else "noon",
			time_row,
			func() -> void: _time.text = TIMES[t]
		)
	var every_row := _row(_when)
	for m in EVERY:
		_every_chips[m] = _chip(EVERY[m], every_row, func() -> void: _set_mode(m))
	var custom_row := _row(_when)
	_every_chips["custom"] = _chip("every", custom_row, func() -> void: _set_mode("custom"))
	_n = _edit("2", custom_row)
	_n.custom_minimum_size.x = 44
	_n.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_n.max_length = 2
	_n.text_changed.connect(func(_t: String) -> void: _set_mode("custom"))
	for u in UNITS:
		_unit_chips[u] = _chip(u, custom_row, func() -> void: _set_unit(u))
	_err = _label("", Fonts.SMALL, WARM)
	_err.visible = false
	col.add_child(_err)
	var btns := _row(col)
	_save = _chip("Save", btns, submit, false, "primary")
	_chip("Cancel", btns, cancel, false, "quiet")
	_done = _chip("Done", btns, func() -> void: _acted("done"), false)
	_stop = _chip("Stop repeating", btns, _stop_repeating, false)
	_del = _chip("Delete", btns, _delete, false, "quiet")
	_set_mode("once")
	_set_unit("week")


func _process(dt: float) -> void:
	sure.tick(dt)
	if id > 0:
		_del.text = "Delete for good?" if sure.armed("del:%d" % id) else "Delete"


func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode in [KEY_ENTER, KEY_KP_ENTER] and _steps.has_focus() and event.ctrl_pressed:
		get_viewport().set_input_as_handled()
		submit()


func _steps_key(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		_steps.accept_event()
		var next := _steps.find_valid_focus_neighbor(
			SIDE_TOP if event.shift_pressed else SIDE_BOTTOM
		)
		if next != null:
			next.grab_focus()


func _flat() -> StyleBoxFlat:
	var flat := StyleBoxFlat.new()
	flat.bg_color = Color(1, 1, 1, 0.35)
	flat.set_content_margin_all(5)
	return flat


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if size > 14 else TextServer.AUTOWRAP_OFF
	return l


func _row(parent: Control) -> Container:
	var r := HFlowContainer.new()
	r.add_theme_constant_override("separation", 6)
	parent.add_child(r)
	return r


func _edit(placeholder: String, parent: Control) -> LineEdit:
	var e := LineEdit.new()
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.placeholder_text = placeholder
	e.add_theme_color_override("font_color", INK)
	e.add_theme_color_override("font_placeholder_color", Color(INK, 0.4))
	e.add_theme_color_override("caret_color", INK)
	e.add_theme_font_size_override("font_size", Fonts.BODY)
	var flat := _flat()
	for s in ["normal", "focus", "read_only"]:
		e.add_theme_stylebox_override(s, flat)
	e.text_submitted.connect(func(_t: String) -> void: submit())
	parent.add_child(e)
	return e


func _chip(
	text: String, parent: Control, cb: Callable, toggle: bool = true, kind: String = "secondary"
) -> Button:
	return Paper.chip(text, parent, cb, toggle, kind)


func _set_kind(k: String) -> void:
	kind = k
	for key in _kind_chips:
		(_kind_chips[key] as Button).set_pressed_no_signal(key == k)
	_who_row.visible = k == "waiting" and id == 0
	_steps.visible = k == "project" and id == 0
	_when.visible = k == "reminder"
	_text.placeholder_text = PLACEHOLDERS[k]
	_err.visible = false


func _set_mode(m: String) -> void:
	_mode = m
	for key in _every_chips:
		(_every_chips[key] as Button).set_pressed_no_signal(key == m)
	for key in _unit_chips:
		(_unit_chips[key] as Button).set_pressed_no_signal(m == "custom" and key == _unit)


func _set_unit(u: String) -> void:
	_unit = u
	for key in _unit_chips:
		(_unit_chips[key] as Button).set_pressed_no_signal(key == u)
	_set_mode("custom")


func _show(title: String, kinds: Array, today: Dictionary) -> void:
	_today = today
	_title.text = title
	_title.visible = title != ""
	_kind_row.visible = kinds.size() > 1
	for key in _kind_chips:
		(_kind_chips[key] as Button).visible = key in kinds
	_err.visible = false
	_busy = false
	_save.disabled = false
	sure.key = ""
	_month.today = today
	visible = true


# What to start with: `kinds` the kinds on offer (the first is the start), and any of `text`,
# `who`, `steps`, `date` ({y, m, d}), `time`, `every`, `project`.
func open_new(preset: Dictionary, today: Dictionary) -> void:
	id = 0
	_was = ""
	_was_every = ""
	project = int(preset.get("project", 0))
	var kinds: Array = preset.get("kinds", ["reminder"])
	_show("A step" if project > 0 else (KINDS[kinds[0]] if kinds.size() == 1 else ""), kinds, today)
	_done.visible = false
	_stop.visible = false
	_del.visible = false
	_text.text = ""
	_who.text = ""
	_steps.text = ""
	_time.text = "09:00"
	_n.text = ""
	_set_kind("todo" if project > 0 else kinds[0])
	var start := {"date": preset.get("date", today), "every": ""}
	start.merge(_only(preset, ["text", "who", "steps", "time", "every"]), true)
	fill(start)
	_text.grab_focus()
	_text.caret_column = _text.text.length()


# `row` is the thing as the server sent it; `due` its due time as local unix, or -1
func open_edit(row: Dictionary, due: float, today: Dictionary) -> void:
	id = int(row["id"])
	project = 0
	_was = str(row["kind"])
	_was_every = "" if row.get("every") == null else str(row["every"])
	var kinds: Array = ["todo", "reminder"] if _was in ["todo", "reminder"] else [_was]
	_show("Change this", kinds, today)
	_text.text = str(row["text"])
	_set_kind(_was)
	var stamp := {"date": today, "time": "09:00", "every": _was_every}
	if due >= 0.0:
		var d := Time.get_datetime_dict_from_unix_time(int(due))
		stamp["date"] = {"y": d["year"], "m": d["month"], "d": d["day"]}
		stamp["time"] = "%02d:%02d" % [d["hour"], d["minute"]]
	fill(stamp)
	_done.visible = true
	_done.text = "Got it" if _was == "waiting" else "Done"
	_stop.visible = _was_every != ""
	_del.visible = true
	_text.grab_focus()
	_text.caret_column = _text.text.length()


static func _only(d: Dictionary, keys: Array) -> Dictionary:
	var out := {}
	for k in keys:
		if d.has(k):
			out[k] = d[k]
	return out


# set the fields: `kind`, `text`, `who`, `steps`, `date` ({y, m, d}), `time`, `every` ("" once,
# "week", "6 week")
func fill(d: Dictionary) -> void:
	if d.has("kind"):
		_set_kind(d["kind"])
	if d.has("text"):
		_text.text = str(d["text"])
	if d.has("who"):
		_who.text = str(d["who"])
	if d.has("steps"):
		_steps.text = str(d["steps"])
	if d.has("time"):
		_time.text = str(d["time"])
	if d.has("date"):
		var dt: Dictionary = d["date"]
		_month.sel = {"y": dt["y"], "m": dt["m"], "d": dt["d"]}
		_month.show_month(dt["y"], dt["m"])
	if d.has("every"):
		var e := Card.parse_every(str(d["every"]))
		if e.is_empty():
			_set_mode("once")
		elif e["n"] == 1:
			_set_mode(e["unit"])
		else:
			_n.text = str(e["n"])
			_set_unit(e["unit"])


static func parse_time(text: String) -> Variant:
	var s := text.strip_edges()
	if s == "":
		return Vector2i(9, 0)
	var p := s.split(":")
	if p.size() > 2 or not p[0].is_valid_int():
		return null
	var m := 0
	if p.size() == 2:
		if p[1].length() != 2 or not p[1].is_valid_int():
			return null
		m = int(p[1])
	var h := int(p[0])
	return Vector2i(h, m) if h >= 0 and h < 24 and m >= 0 and m < 60 else null


# {"at", "every"} (every null for once) or {"error"}
func when() -> Dictionary:
	var t: Variant = parse_time(_time.text)
	if t == null:
		return {"error": "the time looks like 09:30"}
	var every: Variant = null
	match _mode:
		"once":
			pass
		"custom":
			if not _n.text.is_valid_int() or int(_n.text) < 1 or int(_n.text) > 99:
				return {"error": "every how many? a number from 1 to 99"}
			var n := int(_n.text)
			every = _unit if n == 1 else "%d %s" % [n, _unit]
		_:
			every = _mode
	var day: Dictionary = _month.sel if not _month.sel.is_empty() else _today
	var at := "%04d-%02d-%02dT%02d:%02d" % [day["y"], day["m"], day["d"], t.x, t.y]
	return {"at": at, "every": every}


# {"path", "body"} for what is typed, or {"error"}
func request() -> Dictionary:
	var text := _text.text.strip_edges()
	if text == "":
		return {"error": "name it first" if kind == "project" else "say what it is"}
	var body := {"text": text}
	var w := {}
	if kind == "reminder":
		w = when()
		if w.has("error"):
			return w
	if id > 0:
		if kind in ["todo", "reminder"] and kind != _was:
			body["kind"] = kind
		if kind == "reminder":
			body["at"] = w["at"]
			body["every"] = w["every"]
		return {"path": "/api/home/%d/edit" % id, "body": body}
	body["kind"] = kind if project == 0 else "todo"
	match kind:
		"reminder":
			body["at"] = w["at"]
			if w["every"] != null:
				body["every"] = w["every"]
		"waiting":
			if _who.text.strip_edges() == "":
				return {"error": "who is it waiting on?"}
			body["who"] = _who.text.strip_edges()
		"project":
			var steps: Array = []
			for line in _steps.text.split("\n"):
				if line.strip_edges() != "":
					steps.append(line.strip_edges())
			if steps.is_empty():
				return {"error": "a project needs a first step"}
			body["steps"] = steps
	if project > 0:
		body["project"] = project
	return {"path": "/api/home/add", "body": body}


func submit() -> void:
	if _busy or not visible:
		return
	var req := request()
	if req.has("error"):
		_say(req["error"])
		return
	_busy = true
	_save.disabled = true
	_err.visible = false
	submitted.emit(req)


func _say(line: String) -> void:
	_err.text = line
	_err.visible = true


# the server said no (or nothing): the form stays as it was typed
func fail(line: String) -> void:
	_busy = false
	_save.disabled = false
	_say(line)


func finish() -> void:
	close()


func close() -> void:
	visible = false
	_busy = false
	for e in [_text, _who, _time, _n]:
		(e as LineEdit).release_focus()
	_steps.release_focus()


func cancel() -> void:
	close()
	cancelled.emit()


func _acted(what: String) -> void:
	if not _busy:
		_busy = true
		acted.emit(id, what)


func _stop_repeating() -> void:
	_set_mode("once")
	submit()


func _delete() -> void:
	var row := {"kind": _was, "every": null if _was_every == "" else _was_every}
	if Sure.needs(row) and not sure.ask("del:%d" % id):
		_del.text = "Delete for good?"
		return
	_acted("delete")
