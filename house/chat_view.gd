extends PanelContainer

# The paper panel of the phone's chat. It shows `chat`'s messages (his on the right, the home's on the
# left, newest at the bottom) and hands up what he sends and what he does to a reminder; main.gd
# sends and answers.
signal sent(text: String)
signal acted(id: int, what: String)
signal closed

const Paper := preload("res://paper.gd")
const Settings := preload("res://settings.gd")
const Sure := preload("res://sure.gd")
const SIZE := 15
const SMALL := 11
const PAD := Vector2(9.0, 6.0)
const GAP := 8.0
const WHEEL := 48.0
const BUTTONS := [
	["Done", "done"], ["In an hour", "hour"], ["Tomorrow", "tomorrow"], ["Delete", "delete"]
]
const DID := {
	"done": "done",
	"hour": "moved an hour on",
	"tomorrow": "moved to tomorrow",
	"delete": "deleted",
	"gone": "dealt with",
}

var chat
var home
var sure := Sure.new()
var acting := -1
var reading := false

var _log: Log
var _edit: LineEdit
var _note: Label
var _items: Array = []
var _hits: Array = []
var _total := 0.0
var _width := -1.0
var _dirty := true
var _off := 0.0
var _hover := -1


class Log:
	extends Control
	var view

	func _init(owner) -> void:
		view = owner
		mouse_filter = Control.MOUSE_FILTER_STOP
		clip_contents = true
		custom_minimum_size = Vector2(400, 300)
		size_flags_vertical = Control.SIZE_EXPAND_FILL

	func _draw() -> void:
		view.paint(self)

	func _gui_input(event: InputEvent) -> void:
		view.pointer(event)


func setup(the_chat, the_home) -> void:
	chat = the_chat
	home = the_home
	chat.changed.connect(
		func() -> void:
			_dirty = true
			if _log != null:
				_log.queue_redraw()
	)


func _ready() -> void:
	visible = false
	add_theme_stylebox_override("panel", Paper.panel(12))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	col.add_child(Paper.label("The phone", 18, Paper.INK))
	_log = Log.new(self)
	col.add_child(_log)
	_note = Paper.label("", 13, Paper.QUIET)
	col.add_child(_note)
	_edit = Paper.edit("say something to the house", col)
	_edit.text_submitted.connect(_submit)
	_edit.gui_input.connect(_edit_key)
	col.add_child(Paper.label("Enter sends  -  Esc puts it down", 12, Paper.QUIET))


func open() -> void:
	visible = true
	chat.open = true
	chat.unread = false
	_off = 0.0
	_dirty = true
	_note.text = ""
	_edit.grab_focus()
	_log.queue_redraw()


func close() -> void:
	if not visible:
		return
	visible = false
	chat.open = false
	_edit.release_focus()
	closed.emit()


func _process(dt: float) -> void:
	sure.tick(dt)


# the reply came, or it did not and his words go back in the field
func finish(ok: bool, text: String) -> void:
	reading = false
	_edit.editable = true
	_dirty = true
	if not ok:
		_note.text = "couldn't reach tlon - not sent"
		_note.add_theme_color_override("font_color", Paper.WARM)
		_edit.text = text
		_edit.caret_column = text.length()
	_edit.grab_focus()
	_log.queue_redraw()


# a refused change or a failed send, said under the log
func flash(line: String) -> void:
	acting = -1
	_note.text = line
	_note.add_theme_color_override("font_color", Paper.WARM)
	_dirty = true
	_log.queue_redraw()


func scroll(by: float) -> void:
	_off = maxf(0.0, _off + by)
	_log.queue_redraw()


func _submit(text: String) -> void:
	var line := text.strip_edges()
	if reading or line == "":
		return
	reading = true
	_dirty = true
	_note.text = ""
	_edit.text = ""
	_edit.editable = false
	_log.queue_redraw()
	sent.emit(line)


func _edit_key(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_UP:
		_edit.accept_event()
		_edit.text = chat.last_mine()
		_edit.caret_column = _edit.text.length()


func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey and event.pressed):
		return
	match event.keycode:
		KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			close()
		KEY_PAGEUP, KEY_PAGEDOWN:
			get_viewport().set_input_as_handled()
			scroll(_log.size.y * 0.8 * (1.0 if event.keycode == KEY_PAGEUP else -1.0))


func pointer(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var at := _hit_at(event.position)
		if at != _hover:
			_hover = at
			_log.queue_redraw()
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				scroll(WHEEL)
			MOUSE_BUTTON_WHEEL_DOWN:
				scroll(-WHEEL)
			MOUSE_BUTTON_LEFT:
				var at := _hit_at(event.position)
				if at >= 0:
					press(int(_hits[at]["id"]), str(_hits[at]["what"]))


# a reminder's button: Delete of a repeating one asks twice, as the paper menu does
func press(id: int, what: String) -> void:
	if acting >= 0:
		return
	if what == "delete" and Sure.needs(home.things.find(id)) and not sure.ask("del:%d" % id):
		_log.queue_redraw()
		return
	acting = id
	_note.text = ""
	acted.emit(id, what)
	_log.queue_redraw()


func _hit_at(pos: Vector2) -> int:
	for i in _hits.size():
		if (_hits[i]["rect"] as Rect2).has_point(pos):
			return i
	return -1


func _font() -> Font:
	return ThemeDB.fallback_font


func _stamp(t: float) -> String:
	var bias := float(Time.get_time_zone_from_system()["bias"]) * 60.0
	var d := Time.get_datetime_dict_from_unix_time(int(t + bias))
	var n := Time.get_datetime_dict_from_unix_time(int(Time.get_unix_time_from_system() + bias))
	var hm := "%02d:%02d" % [d["hour"], d["minute"]]
	if d["year"] == n["year"] and d["month"] == n["month"] and d["day"] == n["day"]:
		return hm
	return "%02d-%02d %s" % [d["month"], d["day"], hm]


func _text_of(m: Dictionary) -> String:
	var text: String = str(m["text"]).trim_prefix(chat.BELL)
	return text if m["who"] == "me" else Settings.pets(text)


# positions in the log's own coordinates, from the oldest down
func _build(width: float) -> void:
	var font := _font()
	_items = []
	var y := 0.0
	var maxw := width * 0.8
	for m in chat.messages:
		var bell: bool = str(m["text"]).begins_with(chat.BELL)
		var inner := maxw - 2.0 * PAD.x - (18.0 if bell else 0.0)
		var text := _text_of(m)
		var box := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, inner, SIZE)
		var h := box.y + 2.0 * PAD.y
		var extra := 0.0
		if bell:
			extra = 18.0 if m.has("done") else 32.0
		var head := 14.0 if m["who"] in ["cat", "dog"] else 0.0
		var w := minf(maxw, box.x + 2.0 * PAD.x + (18.0 if bell else 0.0))
		if bell and not m.has("done"):
			w = maxw
		var x := width - w if m["who"] == "me" else 0.0
		_items.append(
			{"m": m, "y": y, "x": x, "w": w, "h": h + extra, "head": head, "text": text, "bell": bell, "inner": inner}
		)
		y += head + h + extra + 14.0 + GAP
	if reading:
		_items.append({"m": null, "y": y})
		y += 24.0
	_total = y
	_width = width
	_dirty = false


func paint(c: Control) -> void:
	var font := _font()
	if _dirty or c.size.x != _width:
		_build(c.size.x)
	_off = minf(_off, maxf(0.0, _total - c.size.y))
	_hits = []
	if chat.messages.is_empty() and not reading:
		var who := "" if Settings.person == "" else ", " + Settings.person
		c.draw_string(
			font,
			Vector2(0, c.size.y - 8.0),
			"Nothing yet%s. Say something to the house." % who,
			HORIZONTAL_ALIGNMENT_LEFT,
			c.size.x,
			SIZE,
			Paper.QUIET
		)
		return
	var top := c.size.y - _total + _off
	for it in _items:
		var sy: float = top + it["y"]
		if sy > c.size.y or sy + float(it.get("h", 24.0)) + 40.0 < 0.0:
			continue
		if it["m"] == null:
			c.draw_string(font, Vector2(2, sy + 16), "reading...", HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE, Paper.QUIET)
			continue
		_paint_message(c, it, sy)


func _paint_message(c: Control, it: Dictionary, sy: float) -> void:
	var font := _font()
	var m: Dictionary = it["m"]
	var mine: bool = m["who"] == "me"
	var left: float = it["x"]
	if it["head"] > 0.0:
		var name := Settings.cat if m["who"] == "cat" else Settings.dog
		c.draw_string(font, Vector2(left + 2, sy + 10), name, HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL, Paper.QUIET)
	var box := Rect2(left, sy + it["head"], it["w"], it["h"])
	var fill := Paper.GOLD if mine else Color("e4d8bd")
	if m["who"] in ["cat", "dog"]:
		fill = Color("efe6cf")
	c.draw_rect(box, fill)
	c.draw_rect(box, Paper.INK, false, 2.0)
	var tx := box.position.x + PAD.x + (18.0 if it["bell"] else 0.0)
	var ty := box.position.y + PAD.y + font.get_ascent(SIZE)
	if it["bell"]:
		_bell(c, Vector2(box.position.x + PAD.x + 6.0, box.position.y + PAD.y + 9.0))
	c.draw_multiline_string(font, Vector2(tx, ty), it["text"], HORIZONTAL_ALIGNMENT_LEFT, it["inner"], SIZE, -1, Paper.INK)
	if it["bell"]:
		_actions(c, m, box)
	var stamp := _stamp(float(m["t"])) + (" · from the phone" if m.get("via") == "phone" else "")
	var sw := font.get_string_size(stamp, HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL).x
	var sx := box.end.x - sw if mine else box.position.x
	c.draw_string(font, Vector2(sx, box.end.y + 12.0), stamp, HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL, Paper.QUIET)


func _bell(c: Control, at: Vector2) -> void:
	var gold := Color("c9962c")
	c.draw_colored_polygon(
		PackedVector2Array([at + Vector2(-2, -7), at + Vector2(2, -7), at + Vector2(6, 4), at + Vector2(-6, 4)]),
		gold
	)
	c.draw_circle(at + Vector2(0, -7), 2.5, gold)
	c.draw_circle(at + Vector2(0, 6), 2.0, Paper.INK)


func _actions(c: Control, m: Dictionary, box: Rect2) -> void:
	var font := _font()
	var y := box.end.y - 28.0
	if m.has("done"):
		c.draw_string(
			font,
			Vector2(box.position.x + PAD.x, box.end.y - 7.0),
			DID.get(str(m["done"]), "dealt with"),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			SMALL + 1,
			Paper.QUIET
		)
		return
	var x := box.position.x + PAD.x
	var id := int(m["id"])
	for b in BUTTONS:
		var label: String = b[0]
		if b[1] == "delete" and sure.armed("del:%d" % id):
			label = "Delete for good?"
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 14.0
		var r := Rect2(x, y, w, 22.0)
		_hits.append({"rect": r, "id": id, "what": b[1]})
		var lit: bool = _hover == _hits.size() - 1 and acting < 0
		c.draw_rect(r, Color("f8efb8") if lit else Color("f3ead6"))
		c.draw_rect(r, Paper.INK, false, 2.0)
		c.draw_string(font, r.position + Vector2(7, 16), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Paper.QUIET if acting >= 0 else Paper.INK)
		x += w + 5.0


func fit(room: Vector2) -> void:
	_log.custom_minimum_size.y = clampf(room.y - 150.0, 140.0, 420.0)
