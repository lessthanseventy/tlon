extends "res://logic_local.gd"

# The logic checks of Your move (`moves.gd`): the order, the limits, settling by go, no and answer,
# the closed set of actions, taking an item back and the file. Fixtures only.
const Moves := preload("res://moves.gd")
const MovesList := preload("res://moves_list.gd")
const DAY := 86400.0
const STORE := "user://soak_moves.json"


func run() -> void:
	t = at(2026, 11, 18, 10)
	_order()
	_limits()
	_retract()
	_go()
	_no()
	_answer()
	_file()
	_status()
	_words()
	_sources()


func _moves(l: RefCounted = null, path: String = "") -> RefCounted:
	return Moves.new(path, Callable(self, "_clock"), l)


func _p(key: String, date: String = "", action: Dictionary = {}) -> Dictionary:
	var a := action if not action.is_empty() else {"do": "add", "kind": "todo", "text": key}
	return {
		"key": key,
		"kind": "proposal",
		"source": "list",
		"text": key,
		"why": "w",
		"action": a,
		"date": date
	}


func _a(key: String, date: String = "") -> Dictionary:
	return {
		"key": key,
		"kind": "ask",
		"source": "money",
		"text": key,
		"why": "w",
		"options": ["keep", "cancel", "not a bill"],
		"date": date
	}


func _keys(m: RefCounted) -> Array:
	return m.open_items().map(func(x): return x["key"])


func _order() -> void:
	var m := _moves()
	m.sweep([_p("late", "2026-11-25"), _p("soon", "2026-11-19"), _a("ask-late", "2026-11-30")])
	_eq(_keys(m), ["ask-late", "soon", "late"], "asks first, then the soonest date")
	var n := _moves()
	n.sweep([_p("a-undated"), _p("dated", "2026-12-01")])
	_eq(_keys(n), ["dated", "a-undated"], "an undated item goes last")
	var o := _moves()
	o.sweep([_p("one", "2026-11-19")])
	t += 60.0
	o.sweep([_p("one", "2026-11-19"), _p("two", "2026-11-19")])
	_eq(_keys(o), ["one", "two"], "the oldest first within a date")
	t = at(2026, 11, 18, 10)
	var bad := _moves()
	bad.sweep(
		[
			{"key": "x"},
			{"key": "y", "kind": "ask", "source": "s", "text": "t"},
			{"key": "z", "kind": "proposal", "source": "s", "text": "t"}
		]
	)
	_eq(_keys(bad), [], "an item with no options or no action is not shown")


func _limits() -> void:
	var m := _moves()
	var many: Array = []
	for i in 8:
		many.append(_p("p%d" % i, "2026-11-%02d" % (20 + i)))
	m.sweep(many)
	_eq(_keys(m), ["p0", "p1", "p2", "p3", "p4"], "five new items a day, by date")
	m.sweep(many)
	_eq(m.open_items().size(), 5, "the same day, the rest wait")
	t = at(2026, 11, 19, 10)
	m.sweep(many)
	_eq(_keys(m), ["p0", "p1", "p2", "p3", "p4", "p5", "p6", "p7"], "the next day takes the rest")
	t = at(2026, 11, 18, 20)
	var utc := _moves()
	var zoned := _moves(_list("", -3.0 * 3600.0))
	utc.sweep(many)
	zoned.sweep(many)
	t = at(2026, 11, 18, 22)
	utc.sweep(many)
	zoned.sweep(many)
	_eq(utc.open_items().size(), 5, "at 22:00 UTC it is still the same day in UTC")
	_eq(zoned.open_items().size(), 8, "three hours east of UTC it is already the next day")
	t = at(2026, 11, 18, 10)
	var a := _moves()
	a.sweep([_a("a1"), _a("a2"), _a("a3"), _p("p")])
	_eq(_keys(a), ["a1", "a2", "p"], "two open asks, a third waits")
	a.settle("a1", 1)
	a.sweep([_a("a1"), _a("a2"), _a("a3"), _p("p")])
	_eq(_keys(a), ["a2", "a3", "p"], "an answered ask makes room, and is not asked again")


func _retract() -> void:
	var m := _moves()
	m.sweep([_p("rent"), _p("sam")])
	m.sweep([_p("sam")])
	_eq(_keys(m), ["sam"], "an item whose cause is gone takes itself back")
	_eq(m.settled("rent"), {}, "and is not a settled key")
	m.sweep([_p("rent"), _p("sam")])
	_eq(_keys(m), ["rent", "sam"], "it can come back when the cause does")


func _go() -> void:
	var l := _list()
	var todo: int = l.add({"kind": "todo", "text": "renew passport"})["body"]["id"]
	var rem: int = (
		l.add({"kind": "reminder", "text": "call", "at": "2026-11-19T09:00"})["body"]["id"]
	)
	var m := _moves(l)
	(
		m
		. sweep(
			[
				_p(
					"add",
					"",
					{"do": "add", "kind": "reminder", "text": "move $120", "at": "2026-11-19T18:00"}
				),
				_p("wait", "", {"do": "add", "kind": "waiting", "text": "invoice", "who": "Sam"}),
				_p("some", "", {"do": "someday", "id": todo}),
				_p("day", "", {"do": "day", "id": rem, "at": "2026-11-21T09:00"}),
			]
		)
	)
	_eq(m.settle("add", "go").get("ok"), "Added: move $120.", "go adds a reminder")
	_eq(
		l.status()["coming"].map(func(r): return r["text"]).has("move $120"),
		true,
		"it is in the list"
	)
	_eq(m.settle("wait", "go").has("ok"), true, "go adds a waiting-on")
	_eq(l.status()["waiting"][0]["who"], "Sam", "with who")
	_eq(m.settle("some", "go").get("ok"), "Moved to someday.", "go moves a to-do to someday")
	_eq(l.status()["someday"].map(func(r): return r["id"]), [todo], "it is in someday")
	_eq(m.settle("day", "go").get("ok"), "Moved.", "go moves a reminder to a day")
	_eq(
		l.status()["coming"].any(
			func(r): return r["id"] == rem and r["due_at"].begins_with("2026-11-21")
		),
		true,
		"to that day"
	)
	_eq(_keys(m), [], "a settled item is closed")
	_eq(m.settled("add")["how"], "go", "its go is kept")
	_eq(m.settle("add", "go").has("error"), true, "a settled item cannot be settled again")

	var link := _moves(l)
	link.sweep(
		[
			_p("web", "", {"do": "open", "url": "https://example.com/a"}),
			_p("file", "", {"do": "open", "url": "file:///etc/passwd"}),
			_p("del", "", {"do": "drop", "id": todo}),
			_p("kind", "", {"do": "add", "kind": "note", "text": "n"})
		]
	)
	_eq(
		link.settle("web", "go"),
		{"ok": "Opening it.", "open": "https://example.com/a"},
		"go opens a link"
	)
	_eq(link.settle("file", "go").has("error"), true, "a file link is refused")
	_eq(link.settle("del", "go").has("error"), true, "a go that deletes is not in the set")
	_eq(link.settle("kind", "go").has("error"), true, "a go adds no note")
	_eq(_keys(link), ["del", "file", "kind"], "a refused go leaves the item open")
	_eq(link.settle("file", "maybe").has("error"), true, "a choice is go or no")


func _no() -> void:
	var l := _list()
	var m := _moves(l)
	m.sweep([_p("rent-nov", "", {"do": "add", "kind": "todo", "text": "x"})])
	_eq(m.settle("rent-nov", "no").get("ok"), "Dropped: rent-nov.", "no drops it")
	_eq(l.status()["open"].size(), 0, "and does nothing")
	m.sweep([_p("rent-nov"), _p("rent-dec")])
	_eq(_keys(m), ["rent-dec"], "no is final for the key, the next month is a new one")
	_eq(m.settled("rent-nov")["how"], "no", "recorded")


func _answer() -> void:
	var m := _moves()
	m.sweep([_a("spotify"), _a("flex")])
	_eq(m.settle("spotify", 2).get("ok"), "Noted: cancel.", "an option is an answer")
	_eq(m.facts()["spotify"], "cancel", "kept as a fact")
	_eq(m.settle("flex", "Flex is rent").get("ok"), "Noted: Flex is rent.", "words are an answer")
	_eq(m.facts()["flex"], "Flex is rent", "kept as a fact")
	m.sweep([_a("x")])
	_eq(m.settle("x", 9).has("error"), true, "an option out of range is refused")
	_eq(m.settle("x", "  ").has("error"), true, "an empty answer is refused")
	_eq(m.settle("x", "go").get("ok"), "Noted: go.", "an ask takes go as words, it has no action")
	_eq(m.settle("nope", "go").has("error"), true, "an item not waiting is refused")


func _file() -> void:
	_wipe_moves()
	var m := _moves(null, STORE)
	m.sweep([_p("a", "2026-11-20"), _a("b")])
	m.settle("b", 1)
	var again := _moves(null, STORE)
	again.load_file()
	_eq(_keys(again), ["a"], "the open items come back from the file")
	_eq(again.facts(), {"b": "keep"}, "and the facts")
	_eq(again.settled("b")["how"], "answer", "and the settled keys")
	again.sweep([_p("a", "2026-11-20"), _a("b")])
	_eq(_keys(again), ["a"], "a settled key stays settled after a reload")
	_eq(FileAccess.get_unix_permissions(STORE), 0x180, "the file is 0600")
	var f := FileAccess.open(STORE, FileAccess.WRITE)
	f.store_string("not json")
	f.close()
	var broken := _moves(null, STORE)
	broken.load_file()
	_eq(_keys(broken), [], "a file that cannot be read starts empty")
	f = FileAccess.open(STORE, FileAccess.WRITE)
	f.store_string(
		JSON.stringify(
			{"open": [_p("a"), {"kind": "ask"}, {"key": "k"}, 7, _a("b")], "settled": {}}
		)
	)
	f.close()
	var odd := _moves(null, STORE)
	odd.load_file()
	_eq(_keys(odd).size(), 2, "an open entry that is not whole is dropped on load")
	_eq(odd.open_items().size(), 2, "and the rest can be sorted")
	_wipe_moves()


func _wipe_moves() -> void:
	for p in [STORE, STORE + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


func _status() -> void:
	var l := _list()
	_eq(l.status()["moves"], [], "a list with no moves answers none")
	l.moves = _moves(l)
	l.moves.sweep([_a("ask"), _p("p")])
	_eq(l.status()["moves"].map(func(x): return x["key"]), ["ask", "p"], "status answers moves")
	_eq(l.status().has("proposals"), false, "and not proposals")


func _words() -> void:
	_eq(
		Moves.says({"do": "add", "kind": "reminder", "text": "x", "at": "2026-11-19T18:00"}),
		"a reminder Thu 18:00",
		"a reminder is said with its day and time"
	)
	_eq(
		Moves.says({"do": "add", "kind": "waiting", "text": "x", "who": "S"}),
		"a waiting-on",
		"a waiting-on"
	)
	_eq(Moves.says({"do": "add", "kind": "todo", "text": "x"}), "a to-do", "a to-do")
	_eq(Moves.says({"do": "someday", "id": 1}), "someday", "someday")
	_eq(
		Moves.says({"do": "day", "id": 1, "at": "2026-11-21T09:00"}),
		"a reminder Sat 09:00",
		"a day"
	)
	_eq(Moves.says({"do": "open", "url": "https://a"}), "opens the link", "a link")
	var shown := Moves.shown([_p("p1"), {"key": "l", "kind": "look_at"}, _a("a1"), _p("p2")])
	_eq(shown.map(func(x): return x["key"]), ["a1", "p1", "p2", "l"], "asks, proposals, look-ats")


func _sources() -> void:
	var l := _list()
	l.add({"kind": "waiting", "text": "the invoice", "who": "Sam"})
	l.add({"kind": "todo", "text": "Renew passport"})
	t += 20 * DAY
	l.add({"kind": "waiting", "text": "the quote", "who": "Dana"})
	l.add({"kind": "todo", "text": "Fresh"})
	l.add({"kind": "reminder", "text": "an old reminder", "at": "2026-11-17T09:00"})
	var got := _sources_of(l)
	_eq(
		got.map(func(x): return x["text"]),
		["Nudge Sam about the invoice", 'Put "Renew passport" on someday'],
		"an overdue waiting-on and a stale to-do, nothing newer and no reminder"
	)
	_eq(got[0]["why"], "waiting since Wed", "the waiting-on says since when")
	_eq(got[0]["date"], "2026-11-21", "dated by when it fell due")
	_eq(got[1]["why"], "open since 18 Nov, never moved", "the to-do says since when")
	_eq(got[1]["action"], {"do": "someday", "id": 2}, "go moves that to-do to someday")
	var m := _moves(l)
	m.sweep(got)
	_eq(m.settle("waiting-1", "go").get("ok"), "Added: Nudge Sam about the invoice.", "go nudges")
	_eq(
		l.status()["open"].any(func(r): return r["text"] == "Nudge Sam about the invoice"),
		true,
		"a to-do today"
	)
	_eq(m.settle("stale-2", "go").get("ok"), "Moved to someday.", "go puts it on someday")
	m.sweep(_sources_of(l))
	_eq(_keys(m), [], "a settled one is not offered again, and the fresh ones are not due")
	var n := _moves(l)
	n.sweep(got)
	n.settle("waiting-1", "no")
	n.sweep(_sources_of(l))
	_eq(n.settled("waiting-1")["how"], "no", "no is final for that waiting-on")
	var r := _moves(l)
	r.sweep(_sources_of(l))
	_eq(_keys(r), ["waiting-1"], "the waiting-on is still a move")
	l.done(1)
	r.sweep(_sources_of(l))
	_eq(_keys(r), [], "a ticked waiting-on takes its move back")
	t = at(2026, 11, 18, 10)


func _sources_of(l: RefCounted) -> Array:
	return MovesList.sources(l.status(), l.iso(t), l.iso(t - MovesList.STALE_DAYS * DAY))
