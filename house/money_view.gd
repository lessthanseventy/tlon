extends RefCounted

# The Money view: what is available and what savings hold beside it, the days to the next deposit
# with each expected charge and deposit on its date and one sentence of the lowest point, the
# subscriptions, what the bank thinks is worth a look, and a line to ask about the money. It reads
# `home.things.money` and the forecast `main.gd` fetches when the view opens; a question goes out
# through `ask_wanted` and its answer comes back through `got_reply`. A draft and the last answer
# are kept here, not in the controls, so the view can be built again.
signal forecast_wanted(gen: int)
signal ask_wanted(text: String, thread: String, gen: int)
signal seen_wanted(key: String)

# notices drawn before "and N more"
const NOTICES_SHOWN := 3

const Paper := preload("res://paper.gd")
const Fonts := preload("res://fonts.gd")
const Blocks := preload("res://blocks.gd")
const Views := preload("res://views.gd")
const Money := preload("res://money.gd")
const When := preload("res://when.gd")
const Icons := preload("res://icons.gd")
const CHARGE := Color("5a6f8a")
const DEPOSIT := Color("5f8a4f")
const RISE := Color("b07d2a")

# "idle", "loading", "ok", "none" (the server has nothing stored) or "error"
var fstate := "idle"
var forecast := {}
# the last question and its answer: {q, reply?, figures?}
var asked := {}
var waiting := false
var thread := ""
# one line over the asking when it did not go
var say := ""
var draft := ""
var focus := false
# a call that comes back after the view was reset is not for this one
var gen := 0

var sb
var home


func _init(the_sidebar, the_home) -> void:
	sb = the_sidebar
	home = the_home


func reset() -> void:
	gen += 1
	fstate = "idle"
	forecast = {}
	asked = {}
	waiting = false
	thread = ""
	say = ""
	draft = ""
	focus = false


# the view was just opened: ask for the forecast
func open() -> void:
	fstate = "loading"
	forecast_wanted.emit(gen)


func got_forecast(for_gen: int, reached: bool, code: int, body: Variant) -> void:
	if for_gen != gen:
		return
	if reached and code == 200 and body is Dictionary:
		forecast = body
		fstate = "ok"
	elif reached and code == 200:
		fstate = "none"
	else:
		fstate = "error"


func _notices_of() -> Array:
	return forecast.get("notices", []) if fstate == "ok" else []


# a notice clears at once; one the server did not take comes back with the next forecast
func seen(key: String) -> void:
	forecast["notices"] = _notices_of().filter(
		func(n: Dictionary) -> bool: return str(n["key"]) != key
	)
	seen_wanted.emit(key)


func got_reply(for_gen: int, reached: bool, code: int, body: Variant) -> void:
	if for_gen != gen:
		return
	waiting = false
	if reached and code == 200 and body is Dictionary and body.get("reply") is String:
		asked["reply"] = body["reply"]
		asked["figures"] = body.get("figures")
		thread = str(body.get("thread", thread))
		return
	asked = {}
	if not reached:
		say = "Couldn't reach tlon, so nothing was asked."
	elif code == 400 and body is Dictionary and body.get("error") is String:
		say = "Couldn't ask: %s." % body["error"]
	else:
		say = "tlon answered %d, so nothing came back." % code


# what the view shows, so it is built again only when that changes
func signature() -> String:
	return JSON.stringify(
		[home.things.money, fstate, forecast, asked, waiting, say, _bank_proposals(), home.today()]
	)


func _bank_proposals() -> Array:
	return home.things.proposals.filter(
		func(p: Dictionary) -> bool: return str(p.get("source", "")) == "bank"
	)


func build(box: VBoxContainer) -> void:
	var money: Variant = home.things.money
	if money == null:
		box.add_child(Views.quiet("The bank is not connected.", Fonts.BODY))
		return
	_now(box, money)
	_noticed(box)
	_ahead(box)
	_subscriptions(box)
	_look(box)
	_ask(box)


# `child` under the left margin the rows' text has
func _indented(box: Control, child: Control) -> void:
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 5)
	pad.add_child(child)
	box.add_child(pad)


func _tile(parent: Control, caption: String, cents: Variant, sub: String = "") -> void:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 0)
	parent.add_child(col)
	col.add_child(Paper.label(caption, Fonts.SMALL, Paper.QUIET))
	col.add_child(Paper.label(Money.fmt(cents), Fonts.BODY, Paper.INK))
	if sub != "":
		col.add_child(Paper.label(sub, Fonts.SMALL, Paper.QUIET))


func _now(box: VBoxContainer, money: Dictionary) -> void:
	Views.heading(box, "Now")
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 5)
	box.add_child(pad)
	var row := Paper.row(pad)
	var have: Variant = money.get("available")
	if have == null:
		have = money.get("balance")
	if have != null:
		_tile(row, "Available", have)
	var held := roundi(float(forecast.get("other_available_cents", 0)))
	var names: Array = forecast.get("other_accounts", []) if fstate == "ok" else []
	if fstate == "ok" and (held != 0 or not names.is_empty()):
		_tile(row, "Savings", held, ", ".join(names))


func _noticed(box: VBoxContainer) -> void:
	var rows := _notices_of()
	if rows.is_empty():
		return
	Views.heading(box, "Noticed")
	for n in rows.slice(0, NOTICES_SHOWN):
		var key := str(n["key"])
		var why: Variant = n.get("why")
		var row := Blocks.Row.new(str(n["text"]), "" if why == null else str(why))
		row.marks(
			[{"label": "seen", "act": "seen", "k": "quiet"}], func(_a: String) -> void: seen(key)
		)
		box.add_child(row)
	if rows.size() > NOTICES_SHOWN:
		_indented(box, Views.quiet("and %d more" % (rows.size() - NOTICES_SHOWN), Fonts.SMALL))


func _ahead(box: VBoxContainer) -> void:
	Views.heading(box, "Until the next deposit")
	match fstate:
		"loading", "idle":
			_indented(box, Views.quiet("Looking ahead...", Fonts.BODY))
		"error":
			_indented(
				box, Views.quiet("Couldn't read the forecast: tlon didn't answer.", Fonts.BODY)
			)
		"none":
			_indented(box, Views.quiet("No forecast yet.", Fonts.BODY))
		_:
			var line := Money.lowest_line(forecast, home.today())
			if line != "":
				_indented(box, Blocks.wrapped(line, Fonts.BODY, Paper.INK))
			_days(box, forecast)


# the day strip and the day's events under it, for a forecast of the server's shape
func _days(box: Control, from: Dictionary) -> void:
	var strip := Money.strip(from, home.today())
	var draw := DayStrip.new()
	draw.days = strip
	draw.custom_minimum_size = Vector2(0, 50)
	draw.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_indented(box, draw)
	for d in strip:
		for e in d["events"]:
			_event(box, d["date"], e)


func _event(box: Control, date: String, e: Dictionary) -> void:
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 5)
	box.add_child(pad)
	var row := Paper.row(pad)
	var day := Paper.label(When.day_word(date, home.today()), Fonts.SMALL, Paper.QUIET)
	day.custom_minimum_size.x = 64
	row.add_child(day)
	var name := Paper.label(str(e["name"]), Fonts.BODY, Paper.INK)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.clip_text = true
	row.add_child(name)
	row.add_child(Paper.label(Money.signed(e["cents"]), Fonts.BODY, Paper.INK))


func _subscriptions(box: VBoxContainer) -> void:
	var subs: Array = forecast.get("subscriptions", []) if fstate == "ok" else []
	if subs.is_empty():
		return
	Views.heading(box, "Subscriptions")
	for s in subs:
		var pad := MarginContainer.new()
		pad.add_theme_constant_override("margin_left", 5)
		pad.add_theme_constant_override("margin_top", 2)
		pad.add_theme_constant_override("margin_bottom", 2)
		box.add_child(pad)
		var row := Paper.row(pad)
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 0)
		row.add_child(col)
		var name := Paper.label(str(s["name"]), Fonts.BODY, Paper.INK)
		name.clip_text = true
		col.add_child(name)
		var next := ""
		if s.get("next") != null:
			next = " · next " + When.day_word(str(s["next"]), home.today())
		col.add_child(
			Paper.label(Money.rhythm_word(str(s["rhythm"])) + next, Fonts.SMALL, Paper.QUIET)
		)
		var was := Money.was_line(s)
		if was != "":
			var rise := Rise.new()
			rise.tooltip_text = was
			row.add_child(rise)
		var cents := absi(roundi(float(s["amount_cents"])))
		var amount := Paper.label(Money.fmt(cents), Fonts.BODY, Paper.INK)
		amount.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(amount)
		if was != "":
			col.add_child(Paper.label(was, Fonts.SMALL, Paper.QUIET))


func _look(box: VBoxContainer) -> void:
	var rows := _bank_proposals()
	if rows.is_empty():
		return
	Views.heading(box, "Worth a look")
	for p in rows:
		var id := int(p["id"])
		var why: Variant = p.get("why")
		var row := Blocks.Row.new(str(p["text"]), "" if why == null else str(why))
		row.marks(
			[{"label": "add", "act": "take"}, {"label": "no", "act": "no", "k": "quiet"}],
			func(a: String) -> void: home.acted.emit(id, "propose_" + a)
		)
		box.add_child(row)


func _ask(box: VBoxContainer) -> void:
	Views.heading(box, "Ask")
	if not asked.is_empty():
		_indented(box, Views.quiet(str(asked["q"]), Fonts.SMALL))
	if waiting:
		_indented(box, Views.quiet("Asking...", Fonts.BODY))
	elif asked.has("reply"):
		_indented(box, Blocks.wrapped(str(asked["reply"]), Fonts.BODY, Paper.INK))
		var shown := Money.forecast_of(asked.get("figures"))
		if not shown.is_empty():
			_days(box, shown)
	if say != "":
		_indented(box, Blocks.wrapped(say, Fonts.SMALL, Paper.WARM))
	var edit := Paper.edit("ask about your money", box)
	edit.text = draft
	edit.text_changed.connect(func(t: String) -> void: draft = t)
	edit.focus_entered.connect(func() -> void: focus = true)
	edit.text_submitted.connect(
		func(text: String) -> void:
			var q := text.strip_edges()
			if q == "" or waiting:
				return
			asked = {"q": q}
			say = ""
			draft = ""
			waiting = true
			focus = true
			edit.clear()
			ask_wanted.emit(q, thread, gen)
	)
	if focus:
		edit.grab_focus.call_deferred()


# the days ahead as a row of cells: weekday, date, and a bar for each charge and deposit
class DayStrip:
	extends Control
	var days: Array = []

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if days.is_empty():
			return
		var font := get_theme_default_font()
		var w := size.x / days.size()
		for i in days.size():
			var d: Dictionary = days[i]
			var x := i * w
			var at := Time.get_unix_time_from_datetime_string(str(d["date"]) + "T00:00:00")
			var weekday: int = Time.get_datetime_dict_from_unix_time(int(at))["weekday"]
			draw_rect(Rect2(x + 1, 0, w - 2, size.y), Color(Paper.INK, 0.05))
			draw_string(
				font,
				Vector2(x, 12),
				When.DAYS[weekday].substr(0, 2),
				HORIZONTAL_ALIGNMENT_CENTER,
				w,
				Fonts.SMALL - 2,
				Paper.QUIET
			)
			draw_string(
				font,
				Vector2(x, 25),
				str(int(str(d["date"]).substr(8, 2))),
				HORIZONTAL_ALIGNMENT_CENTER,
				w,
				Fonts.SMALL,
				Paper.INK
			)
			var y := 31.0
			for e in (d["events"] as Array).slice(0, 3):
				var up: bool = e["kind"] == "deposit"
				draw_rect(Rect2(x + 4, y, w - 8, 4), DEPOSIT if up else CHARGE)
				y += 6.0


# a small up arrow beside a price that went up
class Rise:
	extends Control

	func _init() -> void:
		custom_minimum_size = Vector2(14, 14)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_PASS

	func _draw() -> void:
		Icons.draw(self, "up", Vector2(7, 7), RISE, 4.0)
