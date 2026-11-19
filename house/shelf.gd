extends RefCounted

# The bookshelf's view: what is kept but not due (notes, someday, projects), then every Borges
# title, a click on one showing the pet's remark under it. The filter and the opened sections live
# here so a rebuild of the pane keeps them.
const Paper := preload("res://paper.gd")
const Blocks := preload("res://blocks.gd")
const SHOWN := 8
const FILTER_AT := 8

var home
var sb
var filter := ""
var expanded := {}
var _data := {}
var _list: VBoxContainer


func _init(the_sidebar, the_home) -> void:
	sb = the_sidebar
	home = the_home


func reset() -> void:
	filter = ""
	expanded = {}


# `data` is the shelf block `home.card_blocks` gives: rows of "notes", "someday" and "projects"
func build(box: VBoxContainer, data: Dictionary) -> void:
	_data = data
	var count := 0
	for key in ["notes", "someday", "projects"]:
		count += (data[key] as Array).size()
	if count > FILTER_AT:
		var edit := Paper.edit("filter the shelf", box)
		edit.text = filter
		edit.text_changed.connect(
			func(t: String) -> void:
				filter = t
				_fill()
		)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 2)
	box.add_child(_list)
	_fill()


func _fill() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var q := filter.to_lower()
	var kept := _section("notes", "Notes", q, func(_r: Dictionary) -> void: _open_notes())
	for key in ["someday", "projects"]:
		kept += _section(
			key, key.capitalize(), q, func(r: Dictionary) -> void: home.open_item(int(r["id"]))
		)
	if kept == 0 and filter == "":
		_list.add_child(Blocks.wrapped("Nothing is kept here yet.", 15, Paper.QUIET))
	_books(q)


func _open_notes() -> void:
	home.things.tab = "notes"
	sb.open_card("board")


# returns how many rows the section holds before the filter, so an empty shelf can say so
func _section(key: String, name: String, q: String, open: Callable) -> int:
	var held: Array = _data[key]
	var rows: Array = held.filter(
		func(r: Dictionary) -> bool: return q == "" or _hay(r).contains(q)
	)
	if rows.is_empty():
		return held.size()
	_list.add_child(Paper.heading("%s (%d)" % [name, rows.size()], 14, Paper.INK))
	var all: bool = expanded.get(key, false)
	for r in rows if all else rows.slice(0, SHOWN):
		var row := Blocks.Row.new(str(r["text"]), str(r.get("sub", "")))
		row.pressed.connect(func() -> void: open.call(r))
		_list.add_child(row)
	if rows.size() > SHOWN:
		var label := "less" if all else "%d more..." % (rows.size() - SHOWN)
		var more := Blocks.Row.new(label, "", false, true)
		more.pressed.connect(
			func() -> void:
				expanded[key] = not all
				_fill()
		)
		_list.add_child(more)
	return held.size()


static func _hay(r: Dictionary) -> String:
	return (str(r["text"]) + " " + str(r.get("sub", ""))).to_lower()


func _books(q: String) -> void:
	var finds = home.finds
	var shown := 0
	for i in finds.TITLES.size():
		var t: Array = finds.TITLES[i]
		if q != "" and not (t[0] + " " + t[1]).to_lower().contains(q):
			continue
		if shown == 0:
			_list.add_child(Paper.heading("Books", 14, Paper.INK))
		shown += 1
		var opened: bool = finds.book.get("title", "") == t[0]
		var row := Blocks.Row.new(t[0], t[1])
		row.pressed.connect(
			func() -> void:
				if opened:
					finds.book = {}
				else:
					finds.read(i)
				_fill()
		)
		_list.add_child(row)
		if opened:
			var pad := MarginContainer.new()
			pad.add_theme_constant_override("margin_left", 10)
			pad.add_child(Blocks.wrapped(finds.remark(), 14, Paper.INK))
			_list.add_child(pad)
