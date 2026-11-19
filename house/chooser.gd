extends VBoxContainer

# Picks one of a few values in place: chips for up to six, "< value >" arrows for more, so a
# choice never opens a floating menu. Answers like an OptionButton: add_item, select, selected,
# disabled, item_selected.
signal item_selected(index: int)

const Paper := preload("res://paper.gd")
const CHIPS := 6

var selected := 0
var disabled := false:
	set(value):
		disabled = value
		_refresh()

var _items: Array[String] = []
var _chips: Array[Button] = []
var _value: Label
var _body: Container
var _prev: Button
var _next: Button


func add_item(text: String) -> void:
	_items.append(text)
	_build()


func get_item_count() -> int:
	return _items.size()


func select(index: int) -> void:
	selected = clampi(index, 0, maxi(0, _items.size() - 1))
	_refresh()


func _pick(index: int) -> void:
	if disabled or index == selected:
		_refresh()
		return
	selected = index
	_refresh()
	item_selected.emit(index)


func _init() -> void:
	add_theme_constant_override("separation", 0)


func _build() -> void:
	if _body != null:
		remove_child(_body)
		_body.queue_free()
	_chips = []
	if _items.size() <= CHIPS:
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 4)
		flow.add_theme_constant_override("v_separation", 4)
		_body = flow
		add_child(_body)
		for i in _items.size():
			_chips.append(Paper.chip(_items[i], _body, func() -> void: _pick(i), true))
		_refresh()
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	_body = row
	add_child(_body)
	_prev = Paper.chip("<", _body, func() -> void: _step(-1), false)
	_value = Paper.label("", 14, Paper.INK)
	_value.custom_minimum_size.x = 96
	_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_value.clip_text = true
	_body.add_child(_value)
	_next = Paper.chip(">", _body, func() -> void: _step(1), false)
	_refresh()


func _step(dir: int) -> void:
	_pick((selected + dir + _items.size()) % _items.size())


func _refresh() -> void:
	for i in _chips.size():
		_chips[i].set_pressed_no_signal(i == selected)
		_chips[i].disabled = disabled
	if _value != null and not _items.is_empty():
		_value.text = _items[clampi(selected, 0, _items.size() - 1)]
		_prev.disabled = disabled
		_next.disabled = disabled
