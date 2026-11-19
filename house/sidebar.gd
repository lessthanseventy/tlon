extends PanelContainer

# The one sidebar: a banner strip on top (a ringing reminder, the day's slip, a short line from the
# house), the context pane (what is clicked, else the home) with its header, and the chat at the
# bottom. Views are `home`, `office`, `item` (an id), `open` (the desk), `card` (a thing's blocks,
# from `home.card`), `add` and `edit` (the form, with the jot field on a plain add), `pet`,
# `closet`, `settings` and `decorate`. One is up at a time; `back` goes to the home, or from a form
# to the card or item it came from.
signal form_submitted(req: Dictionary)
signal form_acted(id: int, what: String)
signal jot_submitted(text: String)
signal chat_sent(text: String)
signal chat_acted(id: int, what: String)
signal check_requested(url: String)
signal door_pressed
signal kept_closet

const Paper := preload("res://paper.gd")
const Fonts := preload("res://fonts.gd")
const Blocks := preload("res://blocks.gd")
const Views := preload("res://views.gd")
const Form := preload("res://form.gd")
const Jot := preload("res://jot.gd")
const ChatView := preload("res://chat_view.gd")
const SettingsView := preload("res://settings_view.gd")
const PetView := preload("res://pet_view.gd")
const Closet := preload("res://closet.gd")
const Pets := preload("res://pets.gd")
const Settings := preload("res://settings.gd")
const WIDTH := 360
const FRAME := Color("2a2530")
const LIGHT := Color("f1e9dc")
const ACCENT := Color("e8b86d")
const SLIP := Color("f8efb8")
const TITLES := {
	"calendar": "Calendar",
	"jar": "The jar",
	"weather": "The window",
	"clock": "The clock",
	"board": "The board",
	"plant": "The plant",
	"book": "The bookshelf",
	"found": "The mouse hole",
	"fireplace": "The fireplace",
	"piano": "The piano",
	"globe": "The snow globe",
}
const FORM_TITLES := {"add": "Add", "edit": "Change"}
const VIEW_TITLES := {
	"open": "On the desk",
	"closet": "The closet",
	"settings": "Settings",
	"decorate": "Decorate",
}

var home
var view := "home"
var arg: Variant = null
var open_expanded := false
var notes_expanded := false
var chat_mode := "dock"
var chat_popped := false
var form: Control
var jot: Control
var settings_view: Control
var pet_view: Control
var closet: Control
var chat_view: PanelContainer
var decorate: Control
var scroll: ScrollContainer
var office := {}

var _views: RefCounted
var _dyn: VBoxContainer
var _add_root: VBoxContainer
var _banner: VBoxContainer
var _banner_sig := ""
var _header: HBoxContainer
var _back: Button
var _title: Label
var _door: Button
var _add: Button
var _cog: Control
var _status: Label
var _sheet: PanelContainer
var _pane: VBoxContainer
var _sig := ""
var _seen_card := ""
var _reach := true
var _eff := ""
var _door_on := true


func setup(the_home, claude: RefCounted, phone: Node) -> void:
	home = the_home
	_views = Views.new(self, home)
	var style := StyleBoxFlat.new()
	style.bg_color = FRAME
	style.set_content_margin_all(8)
	add_theme_stylebox_override("panel", style)
	custom_minimum_size.x = WIDTH
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	add_child(outer)

	_banner = VBoxContainer.new()
	_banner.custom_minimum_size.y = 38
	_banner.alignment = BoxContainer.ALIGNMENT_CENTER
	outer.add_child(_banner)
	_build_header(outer)
	_status = Paper.label("can't reach tlon", 13, Color("a89fb0"))
	_status.visible = false
	outer.add_child(_status)

	_pane = VBoxContainer.new()
	_pane.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_pane.add_theme_constant_override("separation", 0)
	outer.add_child(_pane)
	_sheet = PanelContainer.new()
	_sheet.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sheet.add_theme_stylebox_override("panel", Paper.panel(9))
	_pane.add_child(_sheet)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 0)
	_sheet.add_child(inner)
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inner.add_child(scroll)
	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 8)
	scroll.add_child(stack)
	_dyn = VBoxContainer.new()
	_dyn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dyn.add_theme_constant_override("separation", 2)
	stack.add_child(_dyn)
	_build_persistent(stack, claude, phone)
	decorate = null

	chat_view = ChatView.new()
	chat_view.setup(home.chat, home)
	chat_view.sent.connect(func(text: String) -> void: chat_sent.emit(text))
	chat_view.acted.connect(func(id: int, what: String) -> void: chat_acted.emit(id, what))
	chat_view.mode_wanted.connect(_chat_mode_wanted)
	outer.add_child(chat_view)
	_apply()


func _build_header(outer: VBoxContainer) -> void:
	_header = HBoxContainer.new()
	_header.add_theme_constant_override("separation", 6)
	outer.add_child(_header)
	_back = _head_button("< home", back)
	_title = Paper.heading("the home", 22, ACCENT)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.clip_text = true
	_header.add_child(_title)
	_door = _head_button("", func() -> void: door_pressed.emit())
	_add = _head_button("add  (I)", func() -> void: open_add(false))
	_cog = SettingsView.Cog.new()
	_cog.pressed.connect(toggle_settings)
	_cog.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_header.add_child(_cog)


func _head_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", 13)
	b.pressed.connect(cb)
	_header.add_child(b)
	return b


func _build_persistent(stack: VBoxContainer, claude: RefCounted, phone: Node) -> void:
	_add_root = VBoxContainer.new()
	_add_root.add_theme_constant_override("separation", 10)
	stack.add_child(_add_root)
	jot = Jot.new()
	jot.submitted.connect(func(text: String) -> void: jot_submitted.emit(text))
	_add_root.add_child(jot)
	form = Form.new()
	form.submitted.connect(func(req: Dictionary) -> void: form_submitted.emit(req))
	form.acted.connect(func(id: int, what: String) -> void: form_acted.emit(id, what))
	form.cancelled.connect(back)
	_add_root.add_child(form)
	settings_view = SettingsView.new()
	settings_view.setup(home.settings, home)
	settings_view.claude = claude
	settings_view.phone = phone
	settings_view.check_requested.connect(func(url: String) -> void: check_requested.emit(url))
	stack.add_child(settings_view)
	pet_view = PetView.new()
	pet_view.setup(home.settings, home)
	stack.add_child(pet_view)
	closet = Closet.new()
	closet.closed.connect(back)
	stack.add_child(closet)


func attach_decorate(node: Control) -> void:
	decorate = node
	decorate.size_flags_vertical = Control.SIZE_EXPAND_FILL
	decorate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	decorate.custom_minimum_size = Vector2(0, 240)
	_sheet.get_child(0).add_child(decorate)
	_apply()


func set_reachable(ok: bool) -> void:
	_reach = ok
	_status.visible = not ok


func set_room(room: String, door_text: String, served: bool) -> void:
	_door.text = door_text
	_door_on = served
	if room == "office" and view != "office":
		_switch("office", null)
	elif room == "home" and view == "office":
		_switch("home", null)
	_apply()


func set_door(served: bool) -> void:
	_door_on = served
	_apply()


func show_office(data: Dictionary) -> void:
	office = data
	_sig = ""


func is_open() -> bool:
	return view not in ["home", "office"]


func takes_text() -> bool:
	return view in ["add", "edit", "settings", "pet"]


func view_title() -> String:
	match view:
		"home":
			return "the home"
		"office":
			return "the office"
		"item":
			var row: Dictionary = home.things.find(int(arg))
			return str(row.get("text", "")) if not row.is_empty() else "a thing"
		"card":
			return TITLES.get(home.card.kind, "")
		"add", "edit":
			return FORM_TITLES[view]
		"pet":
			return Settings.cat if arg == "nina" else Settings.dog
	return VIEW_TITLES.get(view, "")


func selected_key() -> String:
	match view:
		"item":
			return "item:%d" % int(arg)
		"card":
			return home.card.key
		"pet":
			return "pet:" + str(arg)
		"closet":
			return "wardrobe"
		"open":
			return "stack"
		"add":
			return "pad" if jot.visible else ""
	return ""


func open_card(kind: String) -> void:
	home.open_card(kind)


func item_act(id: int, what: String) -> void:
	match what:
		"edit":
			var row: Dictionary = home.things.find(id)
			if not row.is_empty():
				var due: float = home._due(row) if row.get("due_at") != null else -1.0
				open_form("edit", {"row": row, "due": due})
		"plan":
			home.things.reset()
			home.things.tab = "projects"
			home.things.proj = id
			home.card.open("board", "board")
		"delete":
			if Views.Sure.needs(home.things.find(id)) and not home.sure.ask("del:%d" % id):
				return
			home.acted.emit(id, "delete")
		"fire":
			home.eggs.toss_ids.append(id)
			home.acted.emit(id, "done")
		_:
			home.acted.emit(id, what)


func _switch(name: String, the_arg: Variant) -> void:
	_leave(name)
	view = name
	arg = the_arg
	if name not in ["card", "add", "edit"] and home.card.is_open():
		home.close_card()
	_seen_card = home.card.kind + "|" + home.card.key
	chat_popped = false
	_sig = ""
	scroll.scroll_vertical = 0
	home.selected = selected_key()
	_apply()


func _leave(to: String) -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null:
		focused.release_focus()
	match view:
		"add", "edit":
			if to not in ["add", "edit"]:
				form.close()
				jot.finish()
		"settings":
			settings_view.close()
		"pet":
			pet_view.close()
		"closet":
			closet.leave()
		"decorate":
			if decorate != null and decorate.active:
				decorate.leave()


func back() -> void:
	match view:
		"home", "office":
			return
		"edit":
			var id := int(arg)
			if not home.things.find(id).is_empty():
				_switch("item", id)
				return
		"add":
			if home.card.is_open():
				var kind: String = home.card.kind
				_switch("card", kind)
				return
	if view == "card":
		home.close_card()
	_switch("home", null)


func open_item(id: int) -> void:
	_switch("item", id)


func open_pet(who: String) -> void:
	_switch("pet", who)
	pet_view.open(who)


func open_closet() -> void:
	_switch("closet", null)
	closet.open(home.look)


func open_settings() -> void:
	_switch("settings", null)
	settings_view.open()


func toggle_settings() -> void:
	if view == "settings":
		back()
	else:
		open_settings()


func open_desk() -> void:
	_switch("open", null)


func open_decorate() -> void:
	_switch("decorate", null)
	decorate.enter()


# the plain add: the jot field over the typed form; `jot_first` puts the cursor in the jot field
func open_add(jot_first: bool) -> void:
	_switch("add", null)
	jot.visible = true
	form.open_new(
		{"kinds": ["todo", "reminder", "note", "waiting", "project"]}, home.things.today()
	)
	if jot_first:
		jot.open()
	else:
		jot.show_quiet()


# mode "new" (a preset) or "edit" ({row, due}): the form alone
func open_form(mode: String, spec: Dictionary) -> void:
	_switch("edit" if mode == "edit" else "add", int(spec["row"]["id"]) if mode == "edit" else null)
	jot.visible = false
	if mode == "edit":
		form.open_edit(spec["row"], spec["due"], home.things.today())
	else:
		form.open_new(spec, home.things.today())


func form_done() -> void:
	form.finish()
	jot.finish()
	back()


func jot_done() -> void:
	jot.finish()
	if view == "add":
		back()


func focus_chat() -> void:
	if view == "office":
		return
	if _effective() == "line":
		if view == "home":
			chat_mode = "dock"
		else:
			chat_popped = true
	chat_view.focus_input()


func _chat_mode_wanted(mode: String) -> void:
	if view == "home":
		chat_mode = mode
	else:
		chat_popped = mode != "line"
		if mode == "full":
			chat_mode = "full"
		elif chat_mode == "full":
			chat_mode = "dock"


func _effective() -> String:
	if view == "office":
		return "hidden"
	if chat_mode == "full":
		return "full"
	if view == "home":
		return chat_mode
	return "dock" if chat_popped else "line"


func _apply() -> void:
	if _header == null:
		return
	var home_like: bool = view in ["home", "office"]
	_back.visible = not home_like
	_title.text = view_title()
	_door.visible = _door_on and home_like
	_add.visible = view == "home"
	_cog.visible = view != "settings"
	if decorate != null:
		decorate.visible = view == "decorate"
	scroll.visible = view != "decorate"
	_dyn.visible = view in ["home", "office", "item", "open", "card"]
	_add_root.visible = view in ["add", "edit"]
	settings_view.visible = view == "settings"
	pet_view.visible = view == "pet"
	closet.visible = view == "closet"


func _process(_dt: float) -> void:
	if home == null:
		return
	var cs: String = home.card.kind + "|" + home.card.key
	if cs != _seen_card:
		_seen_card = cs
		if home.card.is_open():
			_switch("card", home.card.kind)
		elif view == "card":
			_switch("home", null)
	if view == "item" and home.things.find(int(arg)).is_empty():
		_switch("home", null)
	var sig := _signature()
	if sig != _sig:
		_sig = sig
		_rebuild()
	_title.text = view_title()
	_banner_update()
	_layout()


func _signature() -> String:
	match view:
		"home":
			return (
				JSON
				. stringify(
					[
						home.open,
						home.coming,
						home.notes,
						home.things.pick,
						home.weather,
						home.weather_desc,
						home.temp_c,
						home.forecast,
						home.focus.id,
						home.focus.text,
						open_expanded,
						notes_expanded,
						home.today(),
					]
				)
			)
		"office":
			return JSON.stringify(office)
		"item":
			var row: Dictionary = home.things.find(int(arg))
			var armed: bool = home.sure.armed("del:%d" % int(arg))
			return JSON.stringify([row, armed, home.hearth.lit, home.focus.id])
		"card":
			return JSON.stringify([home.card.kind, home.card_blocks()])
		"open":
			return JSON.stringify(home.open)
	return ""


func _rebuild() -> void:
	var keep := scroll.scroll_vertical
	for c in _dyn.get_children():
		_dyn.remove_child(c)
		c.queue_free()
	match view:
		"home":
			_views.home_view(_dyn)
		"office":
			_views.office_view(_dyn, office)
		"item":
			_views.item_view(_dyn, int(arg))
		"card":
			_views.card_view(_dyn)
		"open":
			_views.open_view(_dyn)
	_restore_scroll.call_deferred(keep)


func _restore_scroll(v: int) -> void:
	await get_tree().process_frame
	scroll.scroll_vertical = v


func _layout() -> void:
	var eff := _effective()
	chat_view.visible = eff != "hidden"
	if eff == "hidden":
		return
	var full := eff == "full"
	_header.visible = not full
	_pane.visible = not full
	if eff != _eff:
		_eff = eff
		chat_view.set_mode(eff)
	chat_view.size_flags_vertical = Control.SIZE_EXPAND_FILL if full else Control.SIZE_SHRINK_END
	chat_view.custom_minimum_size.y = 0.0
	if eff == "dock":
		chat_view.custom_minimum_size.y = maxf(176.0, size.y * 0.3)


func _banner_update() -> void:
	var pad := get_global_rect().has_point(get_global_mouse_position())
	home.rhythm.held = pad and _banner.get_global_rect().has_point(get_global_mouse_position())
	var queue: Array = []
	for item in home.open:
		if home.ring_ids.has(int(item["id"])):
			queue.append({"k": "ring", "item": item})
			break
	if home.reply_left > 0.0 and home.reply_text != "":
		queue.append({"k": "reply", "text": home.reply_text})
	if home.rhythm.kind != "":
		queue.append({"k": "slip"})
	var first: Dictionary = queue[0] if not queue.is_empty() else {}
	var sig := JSON.stringify(
		[
			first,
			queue.size(),
			home.rhythm.kind,
			home.rhythm.rows.size() + home.rhythm.more,
		]
	)
	if sig == _banner_sig:
		return
	_banner_sig = sig
	for c in _banner.get_children():
		_banner.remove_child(c)
		c.queue_free()
	if queue.is_empty():
		return
	var strip := _strip()
	var text := ""
	var acts: Array = []
	var cb: Callable
	match first["k"]:
		"ring":
			var id := int(first["item"]["id"])
			text = "ringing: " + str(first["item"]["text"])
			acts = [
				{"label": "Done", "act": "done"},
				{"label": "In 1 h", "act": "hour"},
				{"label": "Tomorrow", "act": "tomorrow"},
			]
			cb = func(a: String) -> void: item_act(id, a)
		"reply":
			text = str(first["text"])
			acts = [{"label": "ok", "act": "ok"}]
			cb = func(_a: String) -> void: home.reply_left = 0.0
		_:
			var n: int = home.rhythm.rows.size() + home.rhythm.more
			text = (
				"%d still open" % n
				if home.rhythm.kind == "home"
				else "%s (%d)" % [home.rhythm.title, n]
			)
			if home.rhythm.kind == "home":
				acts.append({"label": "Look", "act": "look"})
			acts.append({"label": "Put away", "act": "away"})
			cb = func(a: String) -> void: _slip_act(a)
	var l := Paper.label(text, 14, Paper.INK)
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size.x = 30
	strip.add_child(l)
	if queue.size() > 1:
		strip.add_child(Paper.label("+%d" % (queue.size() - 1), 12, Paper.QUIET))
	for a in acts:
		var b := Paper.chip(str(a["label"]), strip, func() -> void: cb.call(str(a["act"])), false)
		b.add_theme_font_size_override("font_size", 12)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER


func _slip_act(a: String) -> void:
	home.rhythm.dismiss()
	if a == "look":
		open_expanded = true
		_switch("home", null)


# one compact row: the slip's paper with its text and buttons side by side
func _strip() -> HBoxContainer:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var s := StyleBoxFlat.new()
	s.bg_color = SLIP
	s.set_border_width_all(2)
	s.border_color = Paper.INK
	s.content_margin_left = 8
	s.content_margin_right = 4
	s.content_margin_top = 3
	s.content_margin_bottom = 3
	p.add_theme_stylebox_override("panel", s)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	p.add_child(row)
	_banner.add_child(p)
	return row
