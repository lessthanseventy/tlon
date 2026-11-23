extends "res://logic_local.gd"

# The logic checks of the Telegram bot's day card: the replies that tick by number, the times of
# the day, what the card numbers and says morning and evening, and its buttons.
const Telegram := preload("res://telegram.gd")


func run() -> void:
	_numbers()
	_reached()
	_card()


func _numbers() -> void:
	for pair in [["2", [2]], ["2 4 5", [2, 4, 5]], [" 2, 4 ", [2, 4]], ["3 3", [3]]]:
		_eq(Telegram.numbers(pair[0]), pair[1], "'%s' ticks by number" % pair[0])
	for text in ["buy 2 eggs", "2pm", "", "call 911 now", "1234"]:
		_eq(Telegram.numbers(text), [], "'%s' is no reply by number" % text)


func _reached() -> void:
	var now := at(2026, 11, 18, 8, 30)
	_eq(
		[
			Telegram.reached("08:30", now),
			Telegram.reached("8:31", now),
			Telegram.reached("08:29", now)
		],
		[true, false, true],
		"a time is reached at it and after"
	)
	_eq(
		[Telegram.reached("off", now), Telegram.reached("25:00", now)],
		[false, false],
		"off never is"
	)


func _row(id: int, text: String, due: Variant = null) -> Dictionary:
	return {"id": id, "kind": "todo" if due == null else "reminder", "text": text, "due_at": due}


func _card() -> void:
	var now := at(2026, 11, 18, 8, 30)
	var st := {
		"open": [_row(1, "buy milk"), _row(2, "send photos")],
		"coming":
		[_row(3, "dentist", "2026-11-18T15:00:00Z"), _row(4, "later", "2026-11-25T09:00:00Z")],
		"done": [],
	}
	var c := Telegram.new_card("2026-11-18", "morning")
	Telegram.number(c, st, now, 0.0)
	_eq(
		Telegram.card_text(c, st, now, 0.0),
		"Today · Wed 18 Nov\n\nTo do\n1. buy milk\n2. send photos\n3. 15:00 dentist",
		"the morning card numbers the open things and today's reminders, with their time"
	)
	_eq(
		Telegram.card_keys(c, st),
		{"inline_keyboard": [[{"text": "✓ Tick…", "callback_data": "card:tick"}]]},
		"one button opens the numbers"
	)
	c["ticked"].append(2)
	st["open"] = [_row(5, "pay rent"), _row(1, "buy milk")]
	Telegram.number(c, st, now, 0.0)
	_eq(
		Telegram.card_text(c, st, now, 0.0),
		"Today · Wed 18 Nov\n\nTo do\n1. buy milk\n2. ✓ send photos\n3. 15:00 dentist\n4. pay rent",
		"a tick keeps its line and number, and a new thing takes the next number"
	)
	c["keys"] = "tick"
	_eq(
		Telegram.card_keys(c, st)["inline_keyboard"].map(
			func(row): return row.map(func(b): return b["callback_data"])
		),
		[["card:1", "card:3", "card:4"], ["card:back"]],
		"the picker is the numbers still to tick, and Back"
	)
	st["coming"] = [_row(4, "later", "2026-11-25T09:00:00Z")]
	st["done"] = [{"text": "send photos", "done_at": "2026-11-18T10:00:00Z"}]
	c["phase"] = "evening"
	_eq(
		Telegram.card_text(c, st, at(2026, 11, 18, 17, 30), 0.0),
		"This evening · Wed 18 Nov\n\nDone today: send photos\n\nStill to do\n1. buy milk\n4. pay rent",
		"the evening says what was done and what is left, under the same numbers"
	)
	var listed := {
		"open":
		[
			{"id": 1, "kind": "todo", "text": "read ch 4", "due_at": null, "list": "School"},
			_row(2, "buy milk"),
			{
				"id": 3,
				"kind": "todo",
				"text": "plan fractions",
				"due_at": null,
				"list": "Jude's lessons"
			},
			{"id": 4, "kind": "todo", "text": "essay", "due_at": null, "list": "School"},
		],
		"coming": [],
		"done": [],
	}
	var g := Telegram.new_card("2026-11-18", "morning")
	Telegram.number(g, listed, now, 0.0)
	_eq(
		Telegram.card_text(g, listed, now, 0.0),
		"Today · Wed 18 Nov\n\nTo do\n2. buy milk\n\nSchool\n1. read ch 4\n4. essay\n\nJude's lessons\n3. plan fractions",
		"the card groups by list, unlisted first, under one numbering"
	)
	var empty := Telegram.new_card("2026-11-18", "morning")
	var none := {"open": [], "coming": [], "done": []}
	Telegram.number(empty, none, now, 0.0)
	_eq(
		[Telegram.card_text(empty, none, now, 0.0), Telegram.card_keys(empty, none)],
		["", {"inline_keyboard": []}],
		"nothing to say is no card"
	)
	st["done"] = [{"text": "late night", "done_at": "2026-11-18T00:30:00Z"}]
	_eq(
		Telegram.card_text(c, st, at(2026, 11, 18, 17, 30), -3600.0).contains("Done today"),
		false,
		"done is read on the house clock: 00:30 UTC an hour behind is yesterday"
	)
