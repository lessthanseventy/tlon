extends "res://logic_local.gd"

# The logic checks of the Telegram bot's day card: the replies that tick by number, the times of
# the day, what the card numbers and says morning and evening, and its buttons.
const Telegram := preload("res://telegram.gd")


func run() -> void:
	_numbers()
	_reached()
	_card()
	_moves()


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


func _move(key: String, text: String, kind: String = "proposal", date: String = "") -> Dictionary:
	return {"key": key, "kind": kind, "text": text, "date": date}


func _moves() -> void:
	var now := at(2026, 11, 23, 8, 30)
	var st := {
		"open": [_row(1, "buy milk")],
		"coming": [],
		"done": [],
		"moves":
		[_move("a", "Move $120 from savings"), _move("b", "Nudge Sam"), _move("q", "Flex?", "ask")]
	}
	var c := Telegram.new_card("2026-11-23", "morning")
	Telegram.number(c, st, now, 0.0)
	_eq(
		Telegram.card_text(c, st, now, 0.0),
		"Today · Mon 23 Nov\n\nYour move\nA. Move $120 from savings\nB. Nudge Sam\n\nTo do\n1. buy milk",
		"the card letters Your move before To do, and leaves asks to the window"
	)
	_eq(
		Telegram.card_keys(c, st)["inline_keyboard"].map(
			func(row): return row.map(func(b): return b["callback_data"])
		),
		[["card:go:A", "card:go:B"], ["card:pick", "card:tick"]],
		"Go for each letter, then Pick… and ✓ Tick…"
	)
	c["keys"] = "pick"
	_eq(
		Telegram.card_keys(c, st)["inline_keyboard"].map(
			func(row): return row.map(func(b): return b["callback_data"])
		),
		[["card:go:A", "card:no:A"], ["card:go:B", "card:no:B"], ["card:back"]],
		"Pick… opens Go and No for each letter"
	)
	st["moves"] = [_move("a", "Move $120 from savings"), _move("c", "Pay rent")]
	st["moves_settled"] = {"b": "no"}
	Telegram.number(c, st, now, 0.0)
	c["moves"][0]["how"] = "go"
	_eq(
		Telegram.card_text(c, st, now, 0.0).split("\n\nTo do")[0].split("\n\n")[1],
		"Your move\nC. Pay rent\nDone: Move $120 from savings · Dropped: Nudge Sam",
		"a settled one leaves its line for Done and Dropped by name, a new one takes the next letter"
	)
	st["moves"] = []
	Telegram.number(c, st, now, 0.0)
	_eq(
		[c["moves"][2]["how"], Telegram.card_keys(c, st)["inline_keyboard"].size()],
		["gone", 1],
		"one gone with no word of how is dropped from the block, and the buttons follow"
	)
	for pair in [
		["go A", {"verb": "go", "letters": ["A"]}],
		[" No b, c ", {"verb": "no", "letters": ["B", "C"]}],
		["go all", {"verb": "go", "letters": ["all"]}],
		["go a walk", {}],
		["no thanks", {}],
		["go", {}]
	]:
		_eq(Telegram.move_words(pair[0]), pair[1], "'%s' as a reply to Your move" % pair[0])
	var today := Telegram.day_of(now)
	_eq(
		[
			Telegram.urgent_item(_move("a", "x", "proposal", today), now),
			Telegram.urgent_item(_move("a", "x", "proposal", "2026-11-25"), now),
			Telegram.urgent_item(_move("a", "x", "proposal", "2026-11-26"), now),
			Telegram.urgent_item(_move("a", "x", "proposal", "2026-11-20"), now),
			Telegram.urgent_item(_move("a", "x"), now),
			Telegram.urgent_item({"urgent": true}, now)
		],
		[true, true, false, false, false, true],
		"urgent is dated today to 48 hours on, or the source's word; overdue and undated wait for the card"
	)
	_eq(
		[
			Telegram.quiet("17:30", "08:30", at(2026, 11, 23, 18, 0)),
			Telegram.quiet("17:30", "08:30", at(2026, 11, 23, 8, 0)),
			Telegram.quiet("17:30", "08:30", at(2026, 11, 23, 12, 0)),
			Telegram.quiet("off", "08:30", at(2026, 11, 23, 18, 0))
		],
		[true, true, false, false],
		"quiet is from the evening card to the morning's, and never with either off"
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
	listed["open"][0]["list"] = "Work"
	listed["open"][1]["list"] = "Home"
	listed["open"][3].erase("list")
	_eq(
		Telegram.card_text(g, listed, now, 0.0),
		(
			"Today · Wed 18 Nov\n\nTo do\n4. essay\n\nWork\n1. read ch 4\n\nHome\n2. buy milk"
			+ "\n\nJude's lessons\n3. plan fractions"
		),
		"a list set or changed after the card was numbered shows at once"
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
