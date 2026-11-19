extends VBoxContainer

# The closet in the sidebar: who the person is, a row per choice with arrows, a small preview at
# the top, and the person in the room wearing the choice as it is made. Keep saves it; leaving any
# other way puts the old look back.
signal applied
signal closed
signal tabbed

const Paper := preload("res://paper.gd")

var look

var _work := {}
var _works := {}
var _backup := {}
var _kept := false
var _tab := "everyday"
var _tabs: Array = []
var _rows: Array = []
var _preset := 0
var _preview: Texture2D
var _preview_key := ""
var _t := 0.0
var _values: Array = []
var _pad: Control


# the person, idling, in a small frame
class Pad:
	extends Control
	var closet

	func _init(owner) -> void:
		closet = owner
		custom_minimum_size = Vector2(0, 150)
		clip_contents = true
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("d9cdb4"))
		draw_rect(Rect2(Vector2.ZERO, size), Color(Paper.INK, 0.4), false, 2.0)
		closet.paint(self)


func open(l) -> void:
	look = l
	_backup = {"cfg": look.cfg.duplicate(), "hero": look.hero_cfg.duplicate(), "wear": look.wear}
	_kept = false
	_works = {"everyday": look.cfg.duplicate()}
	_tabs = ["everyday"]
	if look.hero_ready:
		_works["hero"] = look.hero_cfg.duplicate()
		_tabs.append("hero")
	_tab = look.wear if _works.has(look.wear) else "everyday"
	_show_tab()
	visible = true


# the old look back unless it was kept
func leave() -> void:
	if look != null and not _kept:
		look.cfg = _backup["cfg"]
		look.hero_cfg = _backup["hero"]
		look.wear = _backup["wear"]
	visible = false


func _live() -> void:
	look.cfg = _works["everyday"].duplicate()
	if _works.has("hero"):
		look.hero_cfg = _works["hero"].duplicate()
	look.wear = _tab


func _show_tab() -> void:
	_work = _works[_tab]
	_rows = []
	if _tab == "hero":
		var names: Array = []
		for r in look.hero_recipes:
			names.append(r["name"])
		_rows.append({"key": "preset", "label": "Ready-made", "opts": names})
		_rows.append({"key": "build", "label": "Build", "opts": look.hero_opts["build"]})
		_rows.append({"key": "skin", "label": "Skin", "opts": look.hero_opts["skin"]})
		for r in look.HERO_ROWS:
			_rows.append({"key": r[0], "label": r[1], "opts": look.hero_opts[r[0]]})
			_rows.append({"key": r[0] + "_c", "label": r[1] + " colour", "dep": r[0], "opts": []})
	elif look.layered:
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
	_preset = -1
	_preview_key = ""
	_build()


func pick_tab(name: String) -> void:
	if _tabs.has(name):
		_tab = name
		_show_tab()


func _switch_tab() -> void:
	if _tabs.size() > 1:
		_tab = _tabs[(_tabs.find(_tab) + 1) % _tabs.size()]
		_show_tab()
		tabbed.emit()


func _options(row: Dictionary) -> Array:
	if row.has("dep"):
		return look.hero_colours(row["dep"], _work[row["dep"]])
	return row["opts"]


func _set_work(c: Dictionary) -> void:
	_work = c
	_works[_tab] = c




func _value(row: Dictionary) -> String:
	var key: String = row["key"]
	if key == "preset":
		return str(row["opts"][_preset]) if _preset >= 0 else "pick one"
	var v: Variant = _work[key]
	if row.has("dep") and _work[row["dep"]] == "":
		return "-"
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
	var list: Array = _options(row)
	var key: String = row["key"]
	if list.is_empty():
		return
	if key == "preset":
		_preset = (
			(0 if dir > 0 else list.size() - 1)
			if _preset < 0
			else (_preset + dir + list.size()) % list.size()
		)
		var made: Array = look.hero_recipes if _tab == "hero" else look.recipes
		_set_work(made[_preset]["cfg"].duplicate())
	else:
		var at := list.find(_work[key])
		_work[key] = list[(at + dir + list.size()) % list.size()]
		if _tab == "hero":
			look.sane_hero(_work)
	_refresh_values()


func _random() -> void:
	_set_work(look.random_hero() if _tab == "hero" else look.random_cfg())
	_refresh_values()




func _apply() -> void:
	look.cfg = _works["everyday"].duplicate()
	if _works.has("hero"):
		look.hero_cfg = _works["hero"].duplicate()
	look.wear = _tab
	look.save()
	_kept = true
	applied.emit()
	closed.emit()


func _build() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	add_theme_constant_override("separation", 6)
	_pad = Pad.new(self)
	add_child(_pad)
	if _tabs.size() > 1:
		var row := Paper.row(self)
		for t in _tabs:
			var chip := Paper.chip(t, row, func() -> void: _pick(t), true)
			chip.set_pressed_no_signal(t == _tab)
	var buttons := Paper.row(self)
	Paper.chip("Random", buttons, _random, false)
	Paper.chip("Keep", buttons, _apply, false)
	_values = []
	for i in _rows.size():
		var row := Paper.row(self)
		var name := Paper.label(str(_rows[i]["label"]), 14, Paper.INK)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name)
		Paper.chip("<", row, func() -> void: _step(i, -1), false)
		var value := Paper.label("", 14, Paper.INK)
		value.custom_minimum_size.x = 84
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		value.clip_text = true
		row.add_child(value)
		_values.append(value)
		Paper.chip(">", row, func() -> void: _step(i, 1), false)
	_refresh_values()


func _pick(t: String) -> void:
	if t != _tab:
		_switch_tab()


func _refresh_values() -> void:
	for i in _values.size():
		(_values[i] as Label).text = _value(_rows[i])
	_live()
	if _pad != null:
		_pad.queue_redraw()


func _process(delta: float) -> void:
	if visible and _pad != null:
		_t += delta
		_pad.queue_redraw()


func paint(c: Control) -> void:
	var pv := Rect2(Vector2.ZERO, c.size)
	if look.layered or _tab == "hero":
		var key := JSON.stringify(_work)
		if key != _preview_key:
			_preview_key = key
			_preview = look.preview(_work, 2)
		var frame := int(_t * 6.0) % 4
		var cell := 128.0
		c.draw_texture_rect_region(
			_preview,
			Rect2(pv.position + Vector2((pv.size.x - cell) / 2.0, 10), Vector2(cell, cell)),
			Rect2(frame * cell, 0, cell, cell)
		)
	else:
		look.draw_flat(c, pv.position + Vector2(pv.size.x / 2.0, 130), 3.0, false, _t, _work)
