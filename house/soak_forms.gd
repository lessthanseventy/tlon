extends RefCounted

# The soak's checks of the forms and what the cards change: the request each one sends, against the
# soak's local stub of the server. Nothing here reaches a real server.
const Card := preload("res://card.gd")

var s
var main
var h


func _init(soak, the_main) -> void:
	s = soak
	main = the_main
	h = main._room.home


# the body of the last POST to `path` after log position `from`, or null
func _sent(path: String, from: int) -> Variant:
	for i in range(s._log.size() - 1, from - 1, -1):
		if s._log[i][0] == "POST" and s._log[i][1] == path:
			return _norm(JSON.parse_string(s._log[i][2]))
	return null


func _wait() -> void:
	await s._answered(main)


func _read_again(before: int) -> void:
	await s._until(func(): return s._count("/api/home") > before, "the room reads the list again")


func _iso_utc(y: int, m: int, d: int, hour: int, minute: int) -> String:
	return (
		Time.get_datetime_string_from_unix_time(int(Card.unix(y, m, d, hour, minute) - h._bias()))
		+ "Z"
	)


# open a new form and fill it, send it, and answer the body it posted
func _send(preset: Dictionary, fields: Dictionary, path: String = "/api/home/add") -> Variant:
	s._check(main._open_form("new", preset), "a form opens for %s (widget %s)" % [str(fields), main._widget])
	main._sidebar.form.fill(fields)
	var from: int = s._log.size()
	main._sidebar.form.submit()
	await _wait()
	return _sent(path, from)


func _date(y: int, m: int, d: int) -> Dictionary:
	return {"y": y, "m": m, "d": d}


func _refresh_state(open: Array, coming: Array = [], extra: Dictionary = {}) -> void:
	s.seed(open, coming, extra)
	var before: int = s._count("/api/home")
	main._poll()
	await _read_again(before)
	await _wait()


func run() -> void:
	main._sidebar.jot.finish()
	await _bodies()
	await _errors()
	await _edits()
	await _deletes()
	await _plan_and_now()
	await _blockers()
	_card_things()


func _bodies() -> void:
	var f = main._sidebar.form
	var before: int = s._count("/api/home")
	var body: Variant = await _send(
		{"kinds": ["reminder"], "date": _date(2026, 11, 30)}, {"text": "pay rent", "time": "09:00"}
	)
	s._check(
		body == {"kind": "reminder", "text": "pay rent", "at": "2026-11-30T09:00"},
		"a one-off reminder: %s" % str(body)
	)
	s._check(not f.visible, "a saved form closes")
	await _read_again(before)
	s._check(s._count("/api/home") > before, "the room is read again at once")
	body = await _send(
		{"kinds": ["reminder"]},
		{"text": "bins", "date": _date(2026, 12, 1), "time": "00:05", "every": "week"}
	)
	s._check(
		body == {"kind": "reminder", "text": "bins", "at": "2026-12-01T00:05", "every": "week"},
		"every week, local time with no zone: %s" % str(body)
	)
	body = await _send(
		{"kinds": ["reminder"]}, {"text": "late", "date": _date(2026, 11, 30), "time": "23:30"}
	)
	s._check(body["at"] == "2026-11-30T23:30", "23:30 stays on its day: %s" % str(body))
	body = await _send(
		{"kinds": ["reminder"]}, {"text": "leap", "date": _date(2028, 2, 29), "time": "7:05"}
	)
	s._check(body["at"] == "2028-02-29T07:05", "a leap day and a one-digit hour: %s" % str(body))
	body = await _send(
		{"kinds": ["reminder"]}, {"text": "blank time", "date": _date(2026, 3, 1), "time": ""}
	)
	s._check(body["at"] == "2026-03-01T09:00", "a blank time is 09:00")
	_opens({"kinds": ["reminder"], "date": _date(2026, 5, 4)})
	f.fill({"text": "plants", "time": "08:15"})
	f._every_chips["custom"].pressed.emit()
	f._n.text = "6"
	f._unit_chips["week"].pressed.emit()
	f._time.text = "08:15"
	var from: int = s._log.size()
	f._text.text_submitted.emit("plants")
	await _wait()
	body = _sent("/api/home/add", from)
	s._check(
		body == {"kind": "reminder", "text": "plants", "at": "2026-05-04T08:15", "every": "6 week"},
		"every 6 weeks from the chips, Enter saves: %s" % str(body)
	)
	body = await _send(
		{"kinds": ["reminder"]}, {"text": "a", "date": _date(2026, 5, 4), "every": "1 month"}
	)
	s._check(body["every"] == "month", "1 month is sent as month")
	body = await _send(
		{"kinds": ["reminder"]}, {"text": "a", "date": _date(2026, 5, 4), "every": "3 month"}
	)
	s._check(body["every"] == "3 month", "every 3 months is sent as 3 month")
	body = await _send({"kinds": ["todo", "reminder"]}, {"text": "call the vet"})
	s._check(body == {"kind": "todo", "text": "call the vet"}, "a to-do: %s" % str(body))
	body = await _send({"kinds": ["todo"]}, {"text": "read chapter 4", "list": " School "})
	s._check(
		body == {"kind": "todo", "text": "read chapter 4", "list": "School"},
		"a to-do with a list: %s" % str(body)
	)
	body = await _send({"kinds": ["note"]}, {"text": "wifi is on the fridge"})
	s._check(body == {"kind": "note", "text": "wifi is on the fridge"}, "a note: %s" % str(body))
	body = await _send(
		{"kinds": ["project"]},
		{"text": "Learn to knit", "steps": "buy needles\n\n  watch a tutorial \ncast on"}
	)
	s._check(
		(
			body
			== {
				"kind": "project",
				"text": "Learn to knit",
				"steps": ["buy needles", "watch a tutorial", "cast on"]
			}
		),
		"a project with steps: %s" % str(body)
	)
	body = await _send({"kinds": ["waiting"]}, {"text": "the lease", "who": "Dana"})
	s._check(
		body == {"kind": "waiting", "text": "the lease", "who": "Dana"},
		"a waiting-on: %s" % str(body)
	)
	body = await _send({"kinds": ["todo"], "project": 61}, {"text": "pack the books"})
	s._check(
		body == {"kind": "todo", "text": "pack the books", "project": 61}, "a step: %s" % str(body)
	)
	var day0: String = h.fake_day
	var hour0: float = h.fake_hour
	# the clock card's timers: now plus N minutes, local, across midnight
	h.fake_day = "12-31"
	h.fake_hour = 23.5
	var year: int = h.things.today()["y"]
	from = s._log.size()
	h.things.act("timer:10")
	await _wait()
	body = _sent("/api/home/add", from)
	s._check(
		body == {"kind": "reminder", "text": "timer", "at": "%d-12-31T23:40" % year},
		"a 10 minute timer: %s" % str(body)
	)
	from = s._log.size()
	h.things.act("timer:30")
	await _wait()
	body = _sent("/api/home/add", from)
	s._check(
		body["at"] == "%d-01-01T00:00" % (year + 1),
		"a 30 minute timer crosses midnight: %s" % str(body)
	)
	from = s._log.size()
	h.things.act("timer:60")
	await _wait()
	s._check(_sent("/api/home/add", from)["at"] == "%d-01-01T00:30" % (year + 1), "a 1 h timer")
	h.things.act("timer_named")
	s._check(
		f.visible and f._text.text == "timer" and f._time.text == "00:00",
		"a named timer opens the form: %s" % f._time.text
	)
	f.cancel()
	h.fake_day = day0
	h.fake_hour = hour0
	h.dismiss_slip()


func _errors() -> void:
	var f = main._sidebar.form
	_opens({"kinds": ["reminder"], "date": _date(2026, 11, 30)})
	f.fill({"text": "keep me", "time": "9:75"})
	var from: int = s._log.size()
	f.submit()
	s._check(
		f.visible and "09:30" in f._err.text and s._log.size() == from,
		"a bad time is said on the form and not sent: '%s'" % f._err.text
	)
	f.fill({"time": "10:00"})
	s._mode = "400"
	f.submit()
	await _wait()
	s._check(
		f.visible and f._err.text == "at is more than a year back" and f._text.text == "keep me",
		"the server's 400 line shows and the form keeps what was typed"
	)
	s._mode = "404"
	f.submit()
	await _wait()
	s._check(f.visible and "not there" in f._err.text, "404: %s" % f._err.text)
	if s.served:
		main._backend.base = "http://127.0.0.1:1"
		f.submit()
		await _wait()
		s._check(
			f.visible and "couldn't reach" in f._err.text and f._text.text == "keep me",
			"a dead server is said and nothing is lost: '%s' visible %s text '%s'" % [f._err.text, f.visible, f._text.text]
		)
		main._backend.base = "http://127.0.0.1:%d" % s._srv.get_local_port()
	s._mode = ""
	f.submit()
	await _wait()
	s._check(not f.visible, "the same form saves once the server answers")
	_opens({"kinds": ["waiting"]})
	f.fill({"text": "x"})
	from = s._log.size()
	f.submit()
	s._check("who" in f._err.text and s._log.size() == from, "a waiting-on needs who")
	f.cancel()
	_opens({"kinds": ["project"]})
	f.fill({"text": "p"})
	f.submit()
	s._check("first step" in f._err.text, "a project needs a step")
	f.cancel()
	s._check(not f.visible, "cancel closes")


func _edits() -> void:
	var f = main._sidebar.form
	var due := _iso_utc(2026, 11, 24, 9, 0)
	await _refresh_state(
		[{"id": 8, "kind": "todo", "text": "buy milk", "due_at": null, "every": null}],
		[{"id": 7, "kind": "reminder", "text": "bins", "due_at": due, "every": "week"}]
	)
	h.things.act("edit:7")
	s._check(
		f.visible and f._text.text == "bins" and f._time.text == "09:00" and f._stop.visible,
		"the edit form is filled in"
	)
	var from: int = s._log.size()
	f._stop.pressed.emit()
	await _wait()
	var body: Variant = _sent("/api/home/7/edit", from)
	s._check(
		body == {"text": "bins", "at": "2026-11-24T09:00", "every": null},
		"stop repeating: %s" % str(body)
	)
	h.things.act("edit:7")
	f.fill({"text": "bins out", "time": "18:30", "every": "2 week"})
	from = s._log.size()
	f.submit()
	await _wait()
	body = _sent("/api/home/7/edit", from)
	s._check(
		body == {"text": "bins out", "at": "2026-11-24T18:30", "every": "2 week"},
		"a changed text, time and repeat: %s" % str(body)
	)
	h.things.act("edit:8")
	f.fill({"kind": "reminder", "date": _date(2026, 12, 2), "time": "10:00"})
	from = s._log.size()
	f.submit()
	await _wait()
	body = _sent("/api/home/8/edit", from)
	s._check(
		body == {"text": "buy milk", "kind": "reminder", "at": "2026-12-02T10:00", "every": null},
		"a to-do becomes a reminder: %s" % str(body)
	)
	h.things.act("edit:7")
	f.fill({"kind": "todo"})
	from = s._log.size()
	f.submit()
	await _wait()
	body = _sent("/api/home/7/edit", from)
	s._check(body == {"text": "bins", "kind": "todo"}, "a reminder becomes a to-do: %s" % str(body))
	h.things.act("edit:8")
	f.fill({"list": "Work"})
	from = s._log.size()
	f.submit()
	await _wait()
	body = _sent("/api/home/8/edit", from)
	s._check(body == {"text": "buy milk", "list": "Work"}, "a list set on a to-do: %s" % str(body))
	h.things.act("edit:8")
	f.fill({"text": "buy oat milk", "kind": "todo"})
	from = s._log.size()
	f.submit()
	await _wait()
	s._check(
		_sent("/api/home/8/edit", from) == {"text": "buy oat milk"}, "a to-do edited stays a to-do"
	)
	h.things.act("edit:8")
	from = s._log.size()
	f._done.pressed.emit()
	await _wait()
	s._check(_sent("/api/home/8/done", from) != null and not f.visible, "Done in the edit form")


func _deletes() -> void:
	var f = main._sidebar.form
	await _refresh_state(
		[{"id": 8, "kind": "todo", "text": "buy milk", "due_at": null, "every": null}],
		[
			{
				"id": 7,
				"kind": "reminder",
				"text": "bins",
				"due_at": _iso_utc(2026, 11, 24, 9, 0),
				"every": "week"
			}
		],
		{
			"waiting":
			[{"id": 41, "kind": "waiting", "text": "the lease", "who": "Dana", "since": null}],
			"projects":
			[
				{
					"id": 61,
					"kind": "project",
					"text": "Move",
					"next": {"id": 62, "text": "book the van"},
					"plan": ["a", "b", "c"],
					"steps_done": []
				}
			]
		}
	)
	var from: int = s._log.size()
	h.things.act("del:8")
	await _wait()
	s._check(_sent("/api/home/8/drop", from) != null, "a one-off to-do is deleted with one click")
	from = s._log.size()
	h.things.act("del:7")
	await _wait()
	s._check(_sent("/api/home/7/drop", from) == null, "a repeating reminder asks first")
	s._check(h.sure.armed("del:7"), "and is armed")
	h.things.act("del:7")
	await _wait()
	s._check(_sent("/api/home/7/drop", from) != null, "the second click deletes it")
	from = s._log.size()
	h.things.act("del:61")
	h.sure.tick(5.0)
	h.things.act("del:61")
	await _wait()
	s._check(
		_sent("/api/home/61/drop", from) == null,
		"after the seconds are up the second click only asks again"
	)
	h.things.act("del:61")
	await _wait()
	s._check(
		_sent("/api/home/61/drop", from) != null, "a project is deleted on the second click in time"
	)
	h.things.act("note_del:5")
	s._check(h.sure.armed("note_del:5"), "a note asks once")
	h.sure.tick(9.0)
	# the paper menu
	await _refresh_state(
		[
			{
				"id": 9,
				"kind": "reminder",
				"text": "water",
				"due_at": _iso_utc(2026, 11, 24, 9, 0),
				"every": "day"
			}
		]
	)
	h.open_item(9)
	var sb = main._sidebar
	await s._until(func(): return sb.view == "item" and sb.arg == 9, "the reminder's view opens")
	s._check(sb.view == "item" and sb.arg == 9, "a click on a reminder opens its view")
	var acts: Array = sb._views._actions(h.things.find(9), "reminder")
	s._check(acts[-1]["act"] == "delete", "the item view ends with Delete")
	from = s._log.size()
	sb.item_act(9, "delete")
	s._check(
		sb._views._actions(h.things.find(9), "reminder")[-1]["label"] == "Delete for good?",
		"a repeating one's view asks again on the same button"
	)
	sb.item_act(9, "delete")
	await _wait()
	s._check(_sent("/api/home/9/drop", from) != null, "and the second click deletes")
	var waiting := {"id": 9, "kind": "waiting", "text": "the lease", "who": "Dana"}
	var wacts: Array = sb._views._actions(waiting, "waiting")
	s._check(
		wacts[0]["label"] == "Got it" and wacts[0]["act"] == "got",
		"a waiting-on's Got it is its own act, not done"
	)
	from = s._log.size()
	sb.item_act(9, "got")
	await _wait()
	s._check(
		_sent("/api/home/9/drop", from) != null and _sent("/api/home/9/done", from) == null,
		"Got it closes a waiting-on through drop"
	)
	f.close()


func _plan_and_now() -> void:
	await _refresh_state(
		[
			{"id": 1, "kind": "todo", "text": "one"},
			{"id": 2, "kind": "todo", "text": "two"},
			{"id": 3, "kind": "todo", "text": "three"}
		],
		[],
		{
			"projects":
			[
				{
					"id": 61,
					"kind": "project",
					"text": "Move",
					"next": {"id": 62, "text": "book the van"},
					"plan": ["a", "b", "c"],
					"steps_done": ["z"]
				}
			]
		}
	)
	h.things.proj = 61
	h.things.tab = "projects"
	for case in [["up:2", ["a", "c", "b"]], ["dn:0", ["b", "a", "c"]], ["rm:1", ["a", "c"]]]:
		var from: int = s._log.size()
		h.things.act(case[0])
		await _wait()
		s._check(
			_sent("/api/home/61/plan", from) == {"plan": case[1]},
			"%s sends %s" % [case[0], str(case[1])]
		)
	var from: int = s._log.size()
	h.things.act("up:0")
	h.things.act("dn:2")
	await _wait()
	s._check(
		_sent("/api/home/61/plan", from) == null, "the first one cannot go up, nor the last down"
	)
	# what now
	main._what_now()
	await _wait()
	s._check(int(h.things.pick["id"]) == 1, "what now picks the thing")
	h.things.act("pk_else")
	await _wait()
	s._check(int(h.things.pick["id"]) == 2, "something else asks again with the first skipped")
	h.things.act("pk_else")
	await _wait()
	var asks: Array = s._log.filter(
		func(l): return l[0] == "GET" and l[1].begins_with("/api/home/now")
	)
	s._check(
		(
			asks.map(func(l): return l[1]).slice(-3)
			== ["/api/home/now", "/api/home/now?skip=1", "/api/home/now?skip=1,2"]
		),
		"the skip list grows: %s" % str(asks.map(func(l): return l[1]))
	)
	from = s._log.size()
	h.things.act("pk_done")
	await _wait()
	s._check(_sent("/api/home/3/done", from) != null and not h.card.is_open(), "Done on the slip")
	await _refresh_state([{"id": 4, "kind": "todo", "text": "four"}])
	main._what_now()
	await _wait()
	from = s._log.size()
	h.things.act("pk_not")
	await _wait()
	s._check(
		_sent("/api/home/4/answer", from) == {"choice": "nottoday"}, "Not today answers nottoday"
	)
	main._what_now()
	await _wait()
	from = s._log.size()
	h.things.act("pk_del")
	await _wait()
	s._check(_sent("/api/home/4/drop", from) != null, "Delete on the slip")
	s._mode = "404"
	await _refresh_state([{"id": 5, "kind": "todo", "text": "five"}])
	s._mode = ""
	main._what_now()
	await _wait()
	h.things.act("pk_not")
	s._mode = "404"
	await _wait()
	s._mode = ""


func _blockers() -> void:
	var f = main._sidebar.form
	var sb = main._sidebar
	var spec := {"kinds": ["note"]}
	s._check(main._open_form("new", spec), "a form opens in the sidebar")
	s._check(sb.view == "add" and f.visible, "the sidebar shows the form")
	s._check(h.form_open or sb.takes_text(), "the form is up")
	h.rhythm.kind = "home"
	h.rhythm.left = 30.0
	await s._quiet_frames(3)
	s._check(f.visible, "a slip appearing does not close the form")
	h.rhythm.dismiss()
	main._open_form("new", {"kinds": ["todo"]})
	s._check(f.visible and f.kind == "todo", "one form at a time: the second replaces the first")
	f.cancel()
	await s._until(func(): return not f.visible and sb.view == "home", "the form's end brings the home view back")
	s._check(not f.visible and sb.view == "home", "the form's end brings the home view back")


func _card_things() -> void:
	h.card.open("calendar", "cal")
	h.things.reset()
	var turned: bool = h.key(KEY_RIGHT) and h.things.mo == 1
	s._check(turned, "the right arrow turns the month")
	h.key(KEY_LEFT)
	h.key(KEY_LEFT)
	s._check(h.things.mo == -1, "the left arrow turns it back")
	h.things.act("mtoday")
	s._check(h.things.mo == 0, "a click on the month name returns to today")
	var found := false
	for b in h.card_blocks():
		found = found or (b["t"] == "month" and b.get("pick", false) and b["today"] > 0)
	s._check(found, "today is marked in the shown month")
	h.things.act("mnext")
	for b in h.card_blocks():
		if b["t"] == "month":
			s._check(b["today"] == 0, "no today mark in another month")
	h.things.reset()
	h.settings.put("birthday", "")
	var feet: Array = h.card_blocks().filter(func(b): return b["t"] == "foot")
	s._check(feet.is_empty(), "no birthday set: the card says nothing of one")
	h.settings.put("birthday", "01-01" if h.finds.today_key() != "01-01" else "01-02")
	s._check(
		h.card_blocks().filter(func(b): return b["t"] == "foot").is_empty(),
		"a birthday set: no line, no button"
	)
	h.settings.put("birthday", h.finds.today_key())
	feet = h.card_blocks().filter(func(b): return b["t"] == "foot")
	s._check(
		feet.size() == 1 and feet[0].get("act", "") == "", "on the day the card says so in a line"
	)
	h.settings.put("birthday", "")
	h.card.close()


func _opens(preset: Dictionary) -> void:
	var ok: bool = main._open_form("new", preset)
	s._check(
		ok,
		(
			"a form opens (view %s decorate %s slip %s)"
			% [main._sidebar.view, main._decorate.active, h.rhythm.kind]
		)
	)


# a parsed body with whole numbers as ints, as they were sent
func _norm(v: Variant) -> Variant:
	if v is float and v == floorf(v):
		return int(v)
	if v is Array:
		return v.map(_norm)
	if v is Dictionary:
		var out := {}
		for k in v:
			out[k] = _norm(v[k])
		return out
	return v
