extends Control

signal applied
signal closed

const INK := Color("2a2530")
const PAPER := Color("f3ead6")
const ACCENT := Color("e8b86d")
const PANEL := Vector2(700, 440)
const ROW_H := 25.0

var look

var _work := {}
var _rows: Array = []
var _sel := 0
var _preset := 0
var _hover := -1
var _preview: Texture2D
var _preview_key := ""
var _t := 0.0
var _rects: Array = []
var _buttons: Array = []
var _panel := Rect2()


func _ready() -> void:
	visible = false
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func open(l) -> void:
	look = l
	_work = look.cfg.duplicate()
	_rows = []
	if look.layered:
		var names: Array = []
		for r in look.recipes:
			names.append(r["name"])
		_rows.append({"key": "preset", "label": "Ready-made", "opts": names})
		for r in look.LAYER_ROWS:
			_rows.append({"key": r[0], "label": r[1], "opts": look.opts[r[0]]})
	else:
		_rows = [
			{"key": "flat_skin", "label": "Skin", "opts": range(look.FLAT_SKIN.size())},
			{"key": "flat_shirt", "label": "Shirt", "opts": range(look.FLAT_SHIRT.size())},
			{"key": "flat_hat", "label": "Hat", "opts": range(look.FLAT_HATS.size())},
			{"key": "flat_glasses", "label": "Glasses", "opts": [0, 1]},
			{"key": "flat_scarf", "label": "Scarf", "opts": range(look.FLAT_SCARF.size())},
		]
	_sel = 0
	_preset = -1
	_preview_key = ""
	visible = true
	grab_focus()
	queue_redraw()


func close() -> void:
	visible = false
	closed.emit()


func _value(row: Dictionary) -> String:
	var key: String = row["key"]
	if key == "preset":
		return str(row["opts"][_preset]) if _preset >= 0 else "pick one"
	var v: Variant = _work[key]
	if key.begins_with("flat_"):
		match key:
			"flat_hat":
				return look.FLAT_HATS[int(v)]
			"flat_glasses":
				return "on" if int(v) == 1 else "off"
			"flat_scarf":
				return "none" if int(v) == 0 else ["", "red", "blue", "green"][int(v)]
		return "#%d" % (int(v) + 1)
	return "none" if str(v) == "" else str(v).replace("_", " ")


func _step(i: int, dir: int) -> void:
	var row: Dictionary = _rows[i]
	var list: Array = row["opts"]
	var key: String = row["key"]
	if key == "preset":
		_preset = (
			(0 if dir > 0 else list.size() - 1)
			if _preset < 0
			else (_preset + dir + list.size()) % list.size()
		)
		_work = look.recipes[_preset]["cfg"].duplicate()
	else:
		var at := list.find(_work[key])
		_work[key] = list[(at + dir + list.size()) % list.size()]
	_sel = i
	queue_redraw()


func _random() -> void:
	_work = look.random_cfg()
	queue_redraw()


func _apply() -> void:
	look.cfg = _work.duplicate()
	look.save()
	applied.emit()
	close()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_UP:
				_sel = (_sel - 1 + _rows.size()) % _rows.size()
			KEY_DOWN:
				_sel = (_sel + 1) % _rows.size()
			KEY_LEFT:
				_step(_sel, -1)
			KEY_RIGHT:
				_step(_sel, 1)
			KEY_R:
				_random()
			KEY_ENTER, KEY_KP_ENTER:
				_apply()
			KEY_ESCAPE:
				close()
		accept_event()
		queue_redraw()
	elif event is InputEventMouseMotion:
		_hover = -1
		for i in _rects.size():
			if (_rects[i] as Rect2).has_point(event.position):
				_hover = i
		queue_redraw()
	elif (
		event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	):
		for i in _rects.size():
			var r: Rect2 = _rects[i]
			if r.has_point(event.position):
				var mid := r.position.x + r.size.x * 0.62
				if event.position.x > mid + 40:
					_step(i, 1)
				elif event.position.x < mid - 40:
					_step(i, -1)
				_sel = i
		for b in _buttons:
			if (b["rect"] as Rect2).has_point(event.position):
				match b["act"]:
					"random":
						_random()
					"done":
						_apply()
					"cancel":
						close()
		accept_event()
		queue_redraw()


func _process(delta: float) -> void:
	if visible:
		_t += delta
		queue_redraw()


func _draw() -> void:
	if not visible:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.04, 0.08, 0.62))
	var font := ThemeDB.fallback_font
	_panel = Rect2(((size - PANEL) / 2.0).round(), PANEL)
	draw_rect(Rect2(_panel.position + Vector2(4, 6), PANEL), Color(0, 0, 0, 0.35))
	draw_rect(_panel, INK)
	draw_rect(_panel.grow(-3), PAPER)
	draw_string(
		font,
		_panel.position + Vector2(24, 36),
		"the closet",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		24,
		INK
	)
	draw_string(
		font,
		_panel.position + Vector2(24, 58),
		"up/down: pick   left/right: change   R: random   Enter: keep   Esc: leave",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		12,
		Color(INK, 0.6)
	)
	var pv := Rect2(_panel.position + Vector2(24, 76), Vector2(280, 300))
	draw_rect(pv, Color("d9cdb4"))
	draw_rect(pv, Color(INK, 0.4), false, 2.0)
	_draw_preview(pv)
	_rects = []
	var x0 := _panel.position.x + 330.0
	for i in _rows.size():
		var r := Rect2(
			Vector2(x0, _panel.position.y + 74 + i * ROW_H), Vector2(PANEL.x - 354, ROW_H - 2)
		)
		_rects.append(r)
		if i == _sel:
			draw_rect(r, Color("f8efb8"))
		elif i == _hover:
			draw_rect(r, Color("ebe2c8"))
		draw_string(
			font,
			r.position + Vector2(6, 17),
			_rows[i]["label"],
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			14,
			INK
		)
		var mid := r.position.x + r.size.x * 0.62
		var text := _value(_rows[i])
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		draw_string(
			font,
			Vector2(mid - w / 2.0, r.position.y + 17),
			text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			14,
			INK
		)
		for s in [-1, 1]:
			var ax: float = mid + s * 62.0
			draw_colored_polygon(
				PackedVector2Array(
					[
						Vector2(ax - s * 4, r.position.y + 6),
						Vector2(ax - s * 4, r.position.y + 18),
						Vector2(ax + s * 4, r.position.y + 12)
					]
				),
				ACCENT.darkened(0.3) if i == _sel else Color(INK, 0.5)
			)
	_buttons = []
	var by := _panel.end.y - 50
	for j in 3:
		var label: String = ["Random", "Keep", "Leave"][j]
		var act: String = ["random", "done", "cancel"][j]
		var br := Rect2(Vector2(_panel.position.x + 24 + j * 100, by), Vector2(90, 30))
		_buttons.append({"rect": br, "act": act})
		draw_rect(br, INK)
		draw_rect(br.grow(-2), ACCENT if act == "done" else Color("e4d8bd"))
		var bw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		draw_string(
			font,
			br.position + Vector2((90 - bw) / 2.0, 20),
			label,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			15,
			INK
		)


func _draw_preview(pv: Rect2) -> void:
	if look.layered:
		var key := JSON.stringify(_work)
		if key != _preview_key:
			_preview_key = key
			_preview = look.preview(_work, 4)
		var frame := int(_t * 6.0) % 4
		var cell := 256.0
		draw_texture_rect_region(
			_preview,
			Rect2(pv.position + Vector2((pv.size.x - cell) / 2.0, 14), Vector2(cell, cell)),
			Rect2(frame * cell, 0, cell, cell)
		)
		draw_circle(pv.position + Vector2(pv.size.x / 2.0, 14 + 46 * 4), 2, Color(0, 0, 0, 0))
	else:
		look.draw_flat(self, pv.position + Vector2(pv.size.x / 2.0, 260), 6.0, false, _t, _work)
