extends "res://logic_local.gd"

# The logic checks of the desktop notice: which new items raise one, and when none does.
const Notices := preload("res://notices.gd")


func run() -> void:
	var now := at(2026, 11, 23, 12, 0)
	var soon := {"key": "a", "kind": "proposal", "text": "Move $120", "why": "short", "date": "2026-11-24"}
	var far := {"key": "f", "kind": "proposal", "text": "x", "date": "2026-12-30"}
	var short := {"key": "s", "kind": "proposal", "text": "y", "urgent": true}
	var ask := {"key": "q", "kind": "ask", "text": "Flex?", "date": "2026-11-23"}
	var n := Notices.new()
	_eq(n.fresh([soon], false, "17:30", "08:30", now), [], "what was open at launch is not new")
	var items := [soon, far, short, ask]
	_eq(
		n.fresh(items, false, "17:30", "08:30", now).map(func(m): return m["key"]),
		["s", "q"],
		"a new ask or proposal raises one when dated within 48 h or money is short, not a far one"
	)
	_eq(n.fresh(items, false, "17:30", "08:30", now), [], "once")
	var m := Notices.new()
	m.fresh([], true, "17:30", "08:30", now)
	_eq(m.fresh([soon], true, "17:30", "08:30", now), [], "never with the window in front")
	_eq(m.seen, ["a"], "but it is no longer new when the window goes back")
	var q := Notices.new()
	q.fresh([], false, "17:30", "08:30", now)
	_eq(q.fresh([soon], false, "17:30", "08:30", at(2026, 11, 23, 18, 0)), [], "not in quiet hours")
	_eq(Notices.text_of(soon), "Move $120\nshort", "the text carries its why")
	_eq(Notices.text_of(far), "x", "and nothing when there is none")
