extends RefCounted

# The soak's checks of the piggy bank and the Money view over a stub that answers the forecast
# as the server does: the three states of the envelope, the click, the view, a short balance
# said calmly, the bank's proposals, the asking sent to the chat, Home's
# Today row, and the room without money (the server says null, the house's own list). The rules
# without a scene are `logic_money.gd`.
const Money := preload("res://money.gd")
# the pig's feet, left and right of its middle, in its own art pixels
const FEET := [-11.0, 11.5]
const MoneyView := preload("res://money_view.gd")
const BackendLocal := preload("res://backend_local.gd")
const Blocks := preload("res://blocks.gd")
const When := preload("res://when.gd")
const Decorate := preload("res://decorate.gd")
const LocalSoak := preload("res://soak_local.gd")

const QUIET := {
	"balance": 181500,
	"available": 181500,
	"as_of": "2026-11-20T12:00:00Z",
	"due_this_week": [{"name": "Rent", "amount": 120000, "in_days": 6}],
	"next_deposit": {"name": "Paycheck", "amount": 240000, "in_days": 6},
	"accounts": [],
}
const DUE := {
	"balance": 400000,
	"available": 400000,
	"as_of": "2026-11-20T12:00:00Z",
	"due_this_week":
	[
		{"name": "Streaming", "amount": 1599, "in_days": 2},
		{"name": "Rent", "amount": 120000, "in_days": 4}
	],
	"next_deposit": {"name": "Paycheck", "amount": 240000, "in_days": 6},
	"accounts": [],
}
const FORECAST := {
	"start_cents": 400000,
	"everyday_cents": 4200,
	"ahead": 20,
	"other_available_cents": 410000,
	"other_accounts": ["Rainy day"],
	"events":
	[
		{"in_days": 2, "kind": "charge", "name": "Streaming", "amount_cents": -1599},
		{"in_days": 4, "kind": "charge", "name": "Rent", "amount_cents": -120000},
		{"in_days": 6, "kind": "deposit", "name": "Paycheck", "amount_cents": 240000},
	],
	"subscriptions":
	[
		{
			"name": "Streaming",
			"amount_cents": -1599,
			"rhythm": "monthly",
			"in_days": 2,
			"was_cents": -1299
		},
		{"name": "Rent", "amount_cents": -120000, "rhythm": "monthly", "in_days": 4},
		{"name": "Cloud storage", "amount_cents": -2999, "rhythm": "yearly", "in_days": 160},
	],
	"budget":
	{
		"in_days": 6,
		"safe_daily_cents": 4500,
		"short_cents": 0,
		"spent_today_cents": 6000,
		"weeks":
		[
			{"top": [{"name": "Corner Market", "amount_cents": 14000}]},
			{"top": []},
		],
	},
}

var s
var main
var h
var sb
var mv
var _fspec: Variant = FORECAST


func _init(soak, the_main) -> void:
	s = soak
	main = the_main
	h = main._room.home
	sb = main._sidebar
	mv = sb.money_ui


func run() -> void:
	_start()
	await _states()
	await _click()
	await _view()
	await _short()
	await _no_forecast()
	await _proposals()
	await _notices()
	await _ask()
	await _today()
	await _row_fits()
	await _cell()
	await _tops()
	await _without()
	await _local()


func _start() -> void:
	for t in main.get_children().filter(
		func(n: Node) -> bool: return n is Timer and n.wait_time == main.POLL_SECONDS
	):
		t.stop()
	sb.back()
	s.stub = Callable(self, "answer")


func answer(method: String, path: String, _body: Variant) -> Variant:
	if method == "GET" and path == "/api/home/money/forecast":
		var out: Variant = null
		if _fspec != null:
			out = Money.staged_forecast(_fspec, h.today())
		return {"code": 200, "body": out}
	if method == "POST" and path == "/api/home/money/notices/seen":
		return {"code": 200, "body": {"ok": true}}
	return null


func _stage(summary: Variant) -> void:
	if summary == null:
		s._state.erase("money")
	else:
		s._state["money"] = Money.staged_summary(summary, h.today())
	await _poll()


func _poll() -> void:
	var before: int = s._count("/api/home")
	main._poll()
	await s._until(func(): return s._count("/api/home") > before, "the house is read again")
	await s._answered(main)
	await _sync()


func _sync() -> void:
	await s.process_frame
	await s.process_frame


func _texts(node: Node, out: Array = []) -> Array:
	for c in node.get_children():
		if c is Label:
			out.append(c.text)
		_texts(c, out)
	return out


func _has(prefix: String) -> bool:
	return _texts(sb._dyn).any(func(t: String) -> bool: return t.begins_with(prefix))


func _strips() -> Array:
	return sb._dyn.find_children("*", "Control", true, false).filter(
		func(c: Control) -> bool: return c is MoneyView.DayStrip
	)


func _buttons(text: String) -> Array:
	return sb._dyn.find_children("*", "Button", true, false).filter(
		func(b: Button) -> bool: return b.text == text
	)



func _posted(path: String) -> Array:
	return s._log.filter(func(l: Array) -> bool: return l[0] == "POST" and l[1] == path)


func _centre(key: String) -> Variant:
	for hit in h._hits:
		if hit["key"] != key:
			continue
		var sum := Vector2.ZERO
		for p: Vector2 in hit["poly"]:
			sum += p
		var c: Vector2 = sum / maxf(1.0, hit["poly"].size())
		if h._topmost(c) == key:
			return c
	return null


func _hits(key: String) -> int:
	return h._hits.filter(func(hit: Dictionary) -> bool: return hit["key"] == key).size()


func _states() -> void:
	await _stage(QUIET)
	var piece: Dictionary = h.layout.piggy()
	s._check(
		not piece.is_empty() and h.layout.kind(piece) == "floor",
		"the default layout has a piggy bank"
	)
	s._check(
		h.layout.rows()["furniture"].all(func(f: Array) -> bool: return f[0] != Money.PIECE),
		"the room draws it in code, not as a sprite row"
	)
	var table: Dictionary = h.layout.table_under(piece)
	s._check(
		not table.is_empty() and table["p"] == "dining_table",
		"by default it stands on the dining table"
	)
	s._check(
		h.layout.lift(piece) == h.layout.TABLE_TOPS["dining_table"] and h.layout.lift(piece) > 0,
		"at the table top's height"
	)
	var drawn_at: Array = h.items().filter(
		func(it: Dictionary) -> bool: return it["fn"] == Callable(h, "_draw_piggy")
	)
	s._check(
		drawn_at.size() == 1 and drawn_at[0]["key"] == float(h.layout.draw_key(table)) + 0.5,
		"and is drawn just after the table, so it is not behind it"
	)
	var summary: Dictionary
	for want in [["none", QUIET], ["due", DUE], ["short", _short_of(DUE)]]:
		summary = want[1]
		await _stage(summary)
		s._check(
			Money.envelope(h.things.money, h.today()) == want[0],
			"%s: the envelope is %s" % [want[0], Money.envelope(h.things.money, h.today())]
		)
		await s._until(func() -> bool: return _centre("piggy") != null, "the piggy bank has a hit")
		var drawn: Array = h.items().filter(
			func(it: Dictionary) -> bool: return it["fn"] == Callable(h, "_draw_piggy")
		)
		s._check(drawn.size() == 1, "%s: the piggy bank is drawn once" % want[0])


func _short_of(summary: Dictionary) -> Dictionary:
	var out := summary.duplicate(true)
	out["available"] = 60000
	out["balance"] = 60000
	return out


func _click() -> void:
	await _stage(DUE)
	var at: Variant = _centre("piggy")
	if at == null:
		s._check(false, "the piggy bank has a hit to click")
		return
	h.hover(at)
	s._check(
		h._hover == "piggy" and h._name_of("piggy") == "the piggy bank",
		"the pointer is on the piggy bank"
	)
	h.click(at)
	await s._until(
		func() -> bool: return sb.view == "money", "a click on the piggy bank opens Money"
	)
	s._check(
		h.selected == "piggy" and sb.selected_key() == "piggy",
		"the piggy bank is outlined while the view is open"
	)
	sb.back()
	h.selected = ""
	s._check(sb.view == "home", "back leaves the view")


func _open() -> void:
	sb.open_money()
	await s._until(func() -> bool: return mv.fstate != "loading", "the forecast comes")
	await _sync()


func _view() -> void:
	await _stage(DUE)
	await _open()
	s._check(mv.fstate == "ok", "the forecast is read: %s" % mv.fstate)
	var texts := _texts(sb._dyn)
	s._check(Money.fmt(400000) in texts, "Available shows %s: %s" % [Money.fmt(400000), str(texts)])
	s._check(
		Money.fmt(410000) in texts and "Rainy day" in texts,
		"savings sit beside it, named: %s" % str(texts)
	)
	s._check(
		not texts.any(func(t: String) -> bool: return t.contains(Money.fmt(810000))),
		"and are never added in"
	)
	s._check(_has("Lowest point before"), "the lowest-point sentence is there: %s" % str(texts))
	s._check(_has("Safe to spend: about $45 a day"), "the day's figure is there: %s" % str(texts))
	s._check(
		"Spent $60 of $45 today, over by $15." in texts,
		"today against it, over: %s" % str(texts)
	)
	s._check(
		"Where it went" in texts and "This week: Corner Market $140" in texts,
		"where it went this week: %s" % str(texts)
	)
	s._check("Last week: nothing yet" in texts, "and an empty last week")
	var strips := _strips()
	s._check(
		strips.size() == 1 and strips[0].days.size() == 7,
		"the days ahead are one strip of a week (%d)" % strips.size()
	)
	for want in ["Streaming", "Rent", "Paycheck", "Cloud storage", "was $12.99", Money.fmt(1599)]:
		s._check(want in texts, "%s is in the view: %s" % [want, str(texts)])
	s._check(not _has("Worth a look"), "no proposals, no Worth a look")
	sb.back()


func _short() -> void:
	var low: Dictionary = FORECAST.duplicate(true)
	low["start_cents"] = 60000
	_fspec = low
	await _stage(_short_of(DUE))
	await _open()
	var line := ""
	for t in _texts(sb._dyn):
		if t.begins_with("Lowest point before"):
			line = t
	s._check(
		line.contains("below zero") and line.contains("Rainy day holds"),
		"below zero is said plainly with what savings hold: %s" % line
	)
	s._check(not line.contains("!"), "and calmly")
	sb.back()
	_fspec = FORECAST


func _no_forecast() -> void:
	_fspec = null
	await _stage(DUE)
	await _open()
	s._check(mv.fstate == "none", "a server with nothing stored: %s" % mv.fstate)
	s._check("No forecast yet." in _texts(sb._dyn), "says so")
	s._check(Money.fmt(400000) in _texts(sb._dyn), "and still shows what is available")
	sb.back()
	_fspec = FORECAST


func _proposals() -> void:
	await _stage(DUE)
	s._state["proposals"] = [
		{
			"id": 71,
			"source": "bank",
			"text": "Cancel the gym",
			"why": "unused for 3 months",
			"url": null
		},
		{"id": 72, "source": "bank", "text": "Move $200 to savings", "why": null, "url": null},
		{"id": 73, "source": "mail", "text": "Package arriving Tuesday", "why": null, "url": null},
	]
	await _poll()
	await _open()
	var texts := _texts(sb._dyn)
	s._check(
		"Worth a look" in texts, "the bank's proposals sit under Worth a look: %s" % str(texts)
	)
	s._check(
		(
			"Cancel the gym" in texts
			and "Move $200 to savings" in texts
			and "Package arriving Tuesday" not in texts
		),
		"only the bank's: %s" % str(texts)
	)
	var add: Array = _buttons("add")
	s._check(add.size() == 2, "each has add (%d)" % add.size())
	add[0].pressed.emit()
	await s._until(
		func() -> bool: return not _posted("/api/home/proposals/71/take").is_empty(), "add is taken"
	)
	await s._answered(main)
	await _sync()
	s._check("Cancel the gym" not in _texts(sb._dyn), "a taken proposal leaves the view")
	var no: Array = _buttons("no")
	s._check(no.size() == 1, "the other has no (%d)" % no.size())
	no[0].pressed.emit()
	await s._until(
		func() -> bool: return not _posted("/api/home/proposals/72/dismiss").is_empty(),
		"no is dismissed"
	)
	await s._answered(main)
	await _sync()
	s._check("Worth a look" not in _texts(sb._dyn), "with none left the heading goes")
	sb.back()
	s._state.erase("proposals")


func _notices() -> void:
	var noted: Dictionary = FORECAST.duplicate(true)
	noted["notices"] = [
		{
			"key": "bank:new:a1",
			"kind": "new",
			"text": "Streamly looks like a new subscription: $9.99 monthly",
			"why": "seen on 3 months running",
		},
		{
			"key": "bank:price:b2:1999",
			"kind": "price",
			"text": "Cloudbox went up from $14.99 to $19.99",
			"why": "",
		},
	]
	_fspec = noted
	await _stage(DUE)
	await _open()
	var texts := _texts(sb._dyn)
	s._check("Noticed" in texts, "the notices sit under Noticed: %s" % str(texts))
	s._check(
		"Streamly looks like a new subscription: $9.99 monthly" in texts,
		"a notice is drawn with its text: %s" % str(texts)
	)
	s._check("Cloudbox went up from $14.99 to $19.99" in texts, "and the other")
	s._check("seen on 3 months running" in texts, "its why under it")
	var seen: Array = _buttons("seen")
	s._check(seen.size() == 2, "each has seen (%d)" % seen.size())
	seen[0].pressed.emit()
	await s._until(
		func() -> bool: return not _posted("/api/home/money/notices/seen").is_empty(),
		"seen is posted"
	)
	await s._answered(main)
	await _sync()
	var body: Dictionary = JSON.parse_string(_posted("/api/home/money/notices/seen")[0][2])
	s._check(body == {"key": "bank:new:a1"}, "seen posts the key: %s" % str(body))
	texts = _texts(sb._dyn)
	s._check(
		not texts.any(func(t: String) -> bool: return t.begins_with("Streamly")),
		"the cleared row goes at once"
	)
	s._check("Cloudbox went up from $14.99 to $19.99" in texts, "the other stays")
	sb.back()
	for none in [[], null]:
		var bare: Dictionary = FORECAST.duplicate(true)
		if none != null:
			bare["notices"] = none
		_fspec = bare
		await _open()
		texts = _texts(sb._dyn)
		s._check("Noticed" not in texts, "no notices, no heading (%s)" % str(none))
		s._check(_buttons("seen").is_empty(), "and no seen (%s)" % str(none))
		sb.back()
	_fspec = FORECAST


func _ask() -> void:
	await _stage(DUE)
	await _open()
	s._check("ask in the chat" in _texts(sb._dyn), "the view sends the asking to the chat")
	s._check(
		sb._dyn.find_children("*", "LineEdit", true, false).is_empty(), "and has no ask line"
	)
	sb.back()


func _today() -> void:
	await _stage(QUIET)
	s._check(
		not _has("Streaming") and not _has("Rent $"), "nothing due soon: Today has no money row"
	)
	await _stage(DUE)
	var row := ""
	for t in _texts(sb._dyn):
		if t.begins_with("Streaming $15.99 due"):
			row = t
	s._check(row != "", "a charge due soon has a row in Today: %s" % str(_texts(sb._dyn)))
	s._check("and 1 more" in _texts(sb._dyn), "and the others are counted on a line under it")
	var found: Variant = null
	for c in sb._dyn.find_children("*", "Control", true, false):
		if c is Blocks.Row and row in _texts(c):
			found = c
	s._check(found != null, "the row is there to press")
	if found != null:
		found.pressed.emit()
		await s._until(func() -> bool: return sb.view == "money", "the row opens Money")
		sb.back()


func _without() -> void:
	await _stage(DUE)
	await _stage(null)
	s._check(h.things.money == null, "money null from the server")
	s._check(_hits("piggy") == 0, "no hit without money")
	s._check(not _has("Streaming"), "no row in Today")
	var deco: Control = Decorate.new()
	deco.room = main._room
	deco.home = h
	deco.size = Vector2(300, 4000)
	main.add_child(deco)
	deco.enter()
	await _sync()
	s._check(
		not deco._hits.any(func(x: Dictionary) -> bool: return x["act"] == "pick:piggy_bank"),
		"decorate does not list it"
	)
	await _stage(DUE)
	deco.queue_redraw()
	await _sync()
	s._check(
		deco._hits.any(func(x: Dictionary) -> bool: return x["act"] == "pick:piggy_bank"),
		"decorate lists it while the server sends money"
	)
	deco.leave()
	deco.queue_free()
	await _sync()


func _local() -> void:
	await _stage(DUE)
	var clock := LocalSoak.new(s)
	clock.t = clock.at(2026, 11, 18, 14)
	var plain := BackendLocal.new()
	plain.setup("", Callable(clock, "_clock"), h._bias(), false)
	main._install(plain)
	main._poll()
	await s._until(
		func() -> bool: return h.things.money == null, "the house's own list has no money"
	)
	await _sync()
	s._check(_hits("piggy") == 0, "local mode: no piggy bank hit")
	s._check(h.layout.piggy().is_empty() and _held() != {}, "and the piece takes no cell")


# on every table it may stand on, each way round, the line its feet stand along lies inside the
# table top's outline
func _tops() -> void:
	await _stage(DUE)
	var saved: Array = h.layout.pieces.duplicate(true)
	for spec in [
		["dining_table", "nwse"],
		["dining_table", "nesw"],
		["round_table", ""],
		["tavern_table", "sw"],
		["tavern_table", "se"],
	]:
		h.layout.pieces = saved.duplicate(true)
		for p in h.layout.pieces:
			if p["p"] == "dining_table":
				p["p"] = spec[0]
				p["f"] = spec[1]
		var table: Dictionary = h.layout.pieces.filter(func(p): return p["p"] == spec[0])[0]
		var pig := _held()
		pig["c"] = table["c"]
		pig["r"] = table["r"]
		var name := "%s %s" % spec
		s._check(h.layout.table_under(pig) == table, "%s: the piggy bank stands on it" % name)
		var seat: Vector2 = h.layout.seat(pig)
		var mid: Vector2 = h._p(seat.x + 0.5, seat.y + 0.5, float(h.layout.lift(pig)))
		var sprite: Dictionary = h.room._sprite(h.room._furn_id([h.layout.sprite_id(table)]))
		var corner: Vector2 = h.room._p(h.room._origin, table["c"], table["r"]) - sprite["anchor"]
		var tex: Texture2D = sprite["tex"]
		for x in FEET:
			var foot := mid + Vector2(x * Money.SCALE * h._k, 0.0)
			var local := (foot - corner.round()).floor()
			s._check(
				tex.get_image().get_pixelv(Vector2i(local)).a > 0.1,
				"%s: its foot at %s is on the table's top" % [name, x]
			)
			var behind := 0
			var image := tex.get_image()
			while local.y - behind - 1 >= 0 and image.get_pixelv(Vector2i(local.x, local.y - behind - 1)).a > 0.1:
				behind += 1
			var want: int = 4 if spec[0] == "tavern_table" else 6
			s._check(
				behind >= want,
				"%s: its foot at %s stands %s px in from the top's back edge, at least %s" % [name, x, behind, want]
			)
	h.layout.pieces = saved


func _held() -> Dictionary:
	for p in h.layout.pieces:
		if Money.is_piggy(p):
			return p
	return {}


func _cell() -> void:
	await _stage(DUE)
	var floor_cell := {"p": Money.PIECE, "f": "", "c": 6, "r": 4}
	s._check(
		h.layout.place(floor_cell, _held(), []) == "" and h.layout.table_under(_held()).is_empty(),
		"the piggy bank can stand on open floor"
	)
	var at := Vector2i(_held()["c"], _held()["r"])
	s._check(h.layout.blocked().has(at), "with money the piggy bank's cell is blocked")
	await _stage(null)
	s._check(h.layout.piggy().is_empty(), "without money the room has no piggy bank")
	s._check(not h.layout.blocked().has(at), "and its cell is free to walk on")
	var plant: Dictionary = h.layout._piece(["plant_small", "", at.x, at.y])
	s._check(h.layout.place(plant, null, []) == "", "and another piece may stand there")
	await _stage(DUE)
	var pig: Dictionary = h.layout.piggy()
	s._check(not pig.is_empty(), "money again brings the piggy bank back")
	if not pig.is_empty():
		s._check(
			Vector2i(pig["c"], pig["r"]) != at and h.layout.check(pig, pig, []) == "",
			"to a cell it may stand on, not the one taken"
		)
	h.layout.remove(plant)
	h.layout.place({"p": Money.PIECE, "f": "", "c": 5, "r": 8}, h.layout.piggy(), [])


# the row's lines whole: every line of a label shown, none cut to an ellipsis, none past the pane
func _whole(text: String) -> bool:
	for l in sb._dyn.find_children("*", "Label", true, false):
		if l.text == text:
			var cut: bool = l.clip_text or l.get_visible_line_count() < l.get_line_count()
			return not cut and l.get_global_rect().end.x <= sb.get_global_rect().end.x + 0.5
	return false


func _row_fits() -> void:
	var rows := [
		[[["Streaming", 1599, 2]], ["Streaming $15.99 due Mon"]],
		[
			[["Streaming", 1599, 2], ["Rent", 120000, 4]],
			["Streaming $15.99 due Mon", "and 1 more"],
		],
		[
			[["Streaming", 1599, 2], ["Rent", 120000, 4], ["Quarterly water and sewer assessment", 48250, 5]],
			["Streaming $15.99 due Mon", "and 2 more"],
		],
		[[["Quarterly water and sewer assessment", 48250, 1]], ["Quarterly water and sewer assessment $482.50 due tomorrow"]],
	]
	for want in rows:
		var due: Array = want[0].map(
			func(d: Array) -> Dictionary: return {"name": d[0], "amount": d[1], "in_days": d[2]}
		)
		var spec := DUE.duplicate(true)
		spec["due_this_week"] = due
		await _stage(spec)
		var texts := _texts(sb._dyn)
		var lines: Array = want[1].map(
			func(t: String) -> String: return t.replace("Mon", When.day_word(When.add_days(h.today(), int(due[0]["in_days"])), h.today()))
		)
		for line in lines:
			s._check(line in texts, "%d due: %s is a line of Today: %s" % [due.size(), line, str(texts)])
			s._check(_whole(line), "%d due: %s is shown whole" % [due.size(), line])
