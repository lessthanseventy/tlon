extends RefCounted

# The logic checks of the chores: which text names which thing, the rhythm, the three states from
# dates and the words.
const Chores := preload("res://chores.gd")

var s


func _init(logic) -> void:
	s = logic


func _eq(got: Variant, want: Variant, what: String) -> void:
	s._check(got == want, "%s: got %s, want %s" % [what, str(got), str(want)])


func run() -> void:
	_table()
	_interval()
	_states()
	_words()


# Wednesday 18 Nov, 10:00, local unix seconds
func _now() -> float:
	return Time.get_unix_time_from_datetime_string("2026-11-18T10:00:00")


func _table() -> void:
	var cases := {
		"do the laundry": "laundry",
		"Washing": "laundry",
		"wash the dishes": "",
		"take the bins out": "bins",
		"bin night": "bins",
		"binder": "",
		"Take out the TRASH": "bins",
		"recycling, then garbage": "bins",
		"rubbish": "bins",
		"feed the cat": "bowls",
		"Feed the dogs": "",
		"feed the pets": "bowls",
		"feed Mimi": "",
		"feed": "",
		"feed the baby": "",
		"take your meds": "pills",
		"vitamins": "pills",
		"medication at 9": "pills",
		"pills": "pills",
		"water the plants": "plant",
		"water the plant": "plant",
		"water": "",
		"plant a tree": "",
		"laundry bins": "laundry",
		"": "",
	}
	for text in cases:
		_eq(Chores.thing_of(text), cases[text], "'%s' names" % text)
	_eq(Chores.thing_of("feed Mimi", ["Mimi", "Argos"]), "bowls", "a pet's own name is a word")
	_eq(Chores.thing_of("feed Mimic", ["Mimi", "Argos"]), "", "and only as a whole word")
	_eq(Chores.thing_of("feed Mimi", ["", "Argos"]), "", "an empty name matches nothing")


func _interval() -> void:
	_eq(Chores.interval("week"), 7 * 86400.0, "every week in seconds")
	_eq(Chores.interval("2 week"), 14 * 86400.0, "every 2 weeks")
	_eq(Chores.interval("3 day"), 3 * 86400.0, "every 3 days")
	for bad in ["", "soon", "0 week", "-1 day", "x week", "1 2 week", "week day"]:
		_eq(Chores.interval(bad), 0.0, "'%s' is no rhythm" % bad)


func _states() -> void:
	var now := _now()
	var day := floorf(now / 86400.0) * 86400.0
	var cases := [
		["week", now + 6 * 86400.0, "fine"],
		["week", now + 3.6 * 86400.0, "fine"],
		["week", now + 3.4 * 86400.0, "soon"],
		["week", day + 86400.0 + 3600.0, "soon"],
		["week", day + 18 * 3600.0, "due"],
		["week", day + 3600.0, "due"],
		["week", now - 3 * 86400.0, "due"],
		["day", day + 86400.0 + 8 * 3600.0, "fine"],
		["day", day + 86400.0 + 5 * 3600.0, "fine"],
		["2 week", now + 8 * 86400.0, "fine"],
		["2 week", now + 6 * 86400.0, "soon"],
		["month", now + 14 * 86400.0, "soon"],
		["month", now + 16 * 86400.0, "fine"],
		["month", now + 12 * 86400.0, "soon"],
		["soon", now + 86400.0, "fine"],
	]
	for c in cases:
		_eq(
			Chores.state(c[1], c[0], now),
			c[2],
			"every %s, due in %.1f days" % [c[0], (c[1] - now) / 86400.0]
		)


func _words() -> void:
	var now := _now()
	var day := floorf(now / 86400.0) * 86400.0
	var phrases := [
		["due", day + 18 * 3600.0, "due today"],
		["due", now - 86400.0, "due since Tue"],
		["due", now - 9 * 86400.0, "due since 9 Nov"],
		["soon", day + 86400.0 + 3600.0, "tomorrow"],
		["fine", now + 2 * 86400.0, "Friday"],
		["fine", now + 12 * 86400.0, "30 Nov"],
	]
	for c in phrases:
		_eq(Chores.phrase(c[0], c[1], now), c[2], "%s reads" % c[0])
	_eq(
		Chores.hover("bins", "fine", now + 2 * 86400.0, now),
		"bins · Friday",
		"a thing's hover words"
	)

