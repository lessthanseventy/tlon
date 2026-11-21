extends "res://logic_local.gd"

# The logic checks of the money: the envelope's three states, how a forecast is bucketed into days,
# the lowest-point sentence (above and below zero, with and without savings), the one way a sum is
# worded, and the dates the rules stand on.
const Money := preload("res://money.gd")
const When := preload("res://when.gd")

const TODAY := "2026-11-18"


func run() -> void:
	t = at(2026, 11, 18, 14)
	_format()
	_dates()
	_envelope()
	_today_row()
	_strip()
	_lowest()
	_subscriptions()
	_figures()
	_staged()


func _summary(available: Variant, due: Array, balance: Variant = null) -> Dictionary:
	var rows: Array = []
	for d in due:
		rows.append({"name": d[0], "amount": d[1], "on": When.add_days(TODAY, d[2])})
	return {
		"balance": balance if balance != null else available,
		"available": available,
		"due_this_week": rows,
		"next_deposit": null,
		"accounts": [],
	}


func _format() -> void:
	var cases := [
		[0, "$0"],
		[5, "$0.05"],
		[1499, "$14.99"],
		[120000, "$1,200"],
		[120050, "$1,200.50"],
		[123456789, "$1,234,567.89"],
		[100, "$1"],
		[-4000, "-$40"],
		[-1250, "-$12.50"],
		[181500.0, "$1,815"],
	]
	for c in cases:
		_eq(Money.fmt(c[0]), c[1], "%s is worded %s" % [str(c[0]), c[1]])
	for c in [
		[-82599, "-$826"], [124049, "$1,240"], [124050, "$1,241"], [31200, "$312"], [0, "$0"]
	]:
		_eq(Money.fmt_whole(c[0]), c[1], "%s is estimated as %s" % [str(c[0]), c[1]])
	_eq(Money.signed(240000), "+$2,400", "money in has its plus")
	_eq(Money.signed(-120000), "-$1,200", "money out its minus")
	_eq(Money.signed(0), "$0", "nothing has neither")


func _dates() -> void:
	_eq(When.days_between(TODAY, "2026-11-20"), 2, "two days on")
	_eq(When.days_between(TODAY, "2026-11-18"), 0, "the same day")
	_eq(When.days_between(TODAY, "2026-11-16"), -2, "two days back")
	_eq(When.days_between("2026-12-30", "2027-01-02"), 3, "across the year's end")
	_eq(When.add_days("2026-11-28", 5), "2026-12-03", "five days on across a month")
	_eq(When.add_days("2026-11-18", 0), "2026-11-18", "none on")
	_eq(When.day_word("2026-11-18", TODAY), "today", "today in words")
	_eq(When.day_word("2026-11-19", TODAY), "tomorrow", "tomorrow in words")
	_eq(When.day_word("2026-11-20", TODAY), "Fri", "the next six days by weekday")
	_eq(When.day_word("2026-11-24", TODAY), "Tue", "the sixth day")
	_eq(When.day_word("2026-11-25", TODAY), "25 Nov", "a week on by date")
	_eq(When.day_word("2026-11-10", TODAY), "10 Nov", "a past day by date")


func _envelope() -> void:
	_eq(Money.envelope(null, TODAY), "none", "no money, no envelope")
	_eq(Money.envelope({}, TODAY), "none", "an empty summary has none")
	_eq(Money.envelope(_summary(181500, []), TODAY), "none", "nothing due: quiet")
	_eq(Money.envelope(_summary(181500, [["Rent", 120000, 4]]), TODAY), "due", "due, covered")
	_eq(Money.envelope(_summary(181500, [["Rent", 120000, 5]]), TODAY), "due", "five days is in")
	_eq(Money.envelope(_summary(181500, [["Rent", 120000, 6]]), TODAY), "none", "six days is out")
	_eq(Money.envelope(_summary(181500, [["Rent", 120000, 0]]), TODAY), "due", "due today counts")
	_eq(Money.envelope(_summary(181500, [["Rent", 120000, -1]]), TODAY), "none", "gone by does not")
	_eq(Money.envelope(_summary(60000, [["Rent", 120000, 4]]), TODAY), "short", "not covered")
	_eq(Money.envelope(_summary(120000, [["Rent", 120000, 4]]), TODAY), "due", "exactly covered")
	_eq(Money.envelope(_summary(119999, [["Rent", 120000, 4]]), TODAY), "short", "a cent short")
	_eq(
		Money.envelope(_summary(100000, [["Rent", 60000, 4], ["Gym", 50000, 2]]), TODAY),
		"short",
		"the charges due soon add up against the balance"
	)
	_eq(
		Money.envelope(_summary(100000, [["Rent", 60000, 4], ["Phone", 50000, 9]]), TODAY),
		"due",
		"one beyond five days is not added"
	)
	_eq(
		Money.envelope(_summary(null, [["Rent", 120000, 4]], 50000), TODAY),
		"short",
		"no available figure: the balance"
	)
	_eq(
		Money.envelope(_summary(null, [["Rent", 120000, 4]], null), TODAY),
		"due",
		"no figure at all: due, never short"
	)
	_eq(
		Money.envelope(_summary(181500.0, [["Rent", 120000.0, 4]]), TODAY),
		"due",
		"numbers as JSON gives them"
	)


func _today_row() -> void:
	_eq(Money.today_row(null, TODAY), "", "no money, no row")
	_eq(Money.today_row(_summary(181500, []), TODAY), "", "nothing due: no row")
	_eq(
		Money.today_row(_summary(181500, [["Rent", 120000, 2]]), TODAY),
		"Rent $1,200 due Fri",
		"one row for what is due"
	)
	_eq(
		Money.today_row(_summary(181500, [["Rent", 120000, 0]]), TODAY),
		"Rent $1,200 due today",
		"due today"
	)
	_eq(
		Money.today_row(_summary(181500, [["Rent", 120000, 1]]), TODAY),
		"Rent $1,200 due tomorrow",
		"due tomorrow"
	)
	_eq(
		Money.today_row(_summary(181500, [["Gym", 3000, 4], ["Rent", 120000, 1]]), TODAY),
		"Rent $1,200 due tomorrow",
		"the soonest"
	)
	var three := _summary(181500, [["Gym", 3000, 4], ["Rent", 120000, 1], ["Phone", 6500, 2]])
	_eq(Money.today_more(three, TODAY), "and 2 more", "the others, counted")
	_eq(
		Money.today_more(_summary(181500, [["Rent", 120000, 1]]), TODAY), "", "one charge, no count"
	)
	_eq(Money.today_more(null, TODAY), "", "no money, no count")
	_eq(
		Money.today_row(_summary(181500, [["Rent", 120000, 7]]), TODAY),
		"",
		"beyond five days: no row"
	)
	var soon := Money.soon(_summary(1, [["B", 1, 3], ["A", 1, 3], ["C", 1, 1], ["D", 1, 8]]), TODAY)
	_eq(soon.map(func(d): return d["name"]), ["C", "A", "B"], "soonest first, a tie by name")


# a forecast as the server answers it, for a few days
func _forecast(
	events: Array, deposit: Variant, lowest: Dictionary, extra: Dictionary = {}
) -> Dictionary:
	var out := {
		"start_cents": 100000,
		"until": When.add_days(TODAY, 45),
		"events": events,
		"days": [{"date": TODAY, "low_cents": 1, "expected_cents": 1, "high_cents": 1}],
		"lowest": lowest,
		"before_next_deposit": lowest if deposit != null else null,
		"other_available_cents": 0,
		"other_accounts": [],
		"basis": {"next_deposit": deposit, "skipped": [], "caveats": []},
	}
	out.merge(extra, true)
	return out


func _event(in_days: int, name: String, cents: int, kind: String) -> Dictionary:
	return {
		"date": When.add_days(TODAY, in_days),
		"amount_cents": cents,
		"name": name,
		"kind": kind,
		"rhythm": "monthly",
		"count": 3,
		"overdue": false,
		"expected_on": null,
	}


func _deposit(in_days: int) -> Dictionary:
	return {"name": "Paycheck", "date": When.add_days(TODAY, in_days), "overdue": false}


func _strip() -> void:
	var events := [
		_event(2, "Streaming", -1599, "charge"),
		_event(2, "Gym", -3000, "charge"),
		_event(4, "Rent", -120000, "charge"),
		_event(6, "Paycheck", 240000, "deposit"),
		_event(30, "Far", -500, "charge"),
	]
	var low := {"date": When.add_days(TODAY, 5), "balance_cents": 30000}
	var strip := Money.strip(_forecast(events, _deposit(6), low), TODAY)
	_eq(strip.size(), 7, "a deposit in six days: seven days of strip, the least")
	_eq(strip[0]["date"], "2026-11-19", "it starts tomorrow")
	_eq(strip[6]["date"], "2026-11-25", "and ends a week on")
	_eq(
		strip[1]["events"].map(func(e): return e["name"]),
		["Streaming", "Gym"],
		"two charges on one day"
	)
	_eq(strip[1]["events"].map(func(e): return e["cents"]), [-1599, -3000], "their signed amounts")
	_eq(strip[3]["events"].size(), 1, "one on the fourth")
	_eq(strip[5]["events"][0]["kind"], "deposit", "the deposit on its date")
	_eq(strip[0]["events"].size() + strip[2]["events"].size(), 0, "the other days are empty")
	var all := 0
	for d in strip:
		all += d["events"].size()
	_eq(all, 4, "an event past the strip is left out")
	_eq(Money.span(_forecast([], _deposit(3), low), TODAY), 7, "a near deposit still gives a week")
	_eq(Money.span(_forecast([], _deposit(10), low), TODAY), 10, "a deposit in ten days: ten days")
	_eq(Money.span(_forecast([], _deposit(40), low), TODAY), 14, "a far one is capped at two weeks")
	_eq(Money.span(_forecast([], null, low), TODAY), 7, "no deposit seen: a week")
	var overdue := _event(1, "Rent", -120000, "charge")
	overdue["overdue"] = true
	overdue["expected_on"] = TODAY
	_eq(
		Money.strip(_forecast([overdue], _deposit(6), low), TODAY)[0]["events"].size(),
		1,
		"an overdue charge stands on tomorrow"
	)
	var bare := {"events": [{"date": "2026-11-19", "amount_cents": 500, "name": "Refund"}]}
	_eq(
		Money.strip(bare, TODAY)[0]["events"][0]["kind"],
		"deposit",
		"a row with no kind is read by its sign"
	)
	_eq(Money.strip({}, TODAY).size(), 7, "a forecast with nothing in it is seven empty days")


func _lowest() -> void:
	var fri := _deposit(2)
	var low := {"date": When.add_days(TODAY, 1), "balance_cents": 31200}
	_eq(
		Money.lowest_line(_forecast([], fri, low), TODAY),
		"Lowest point before Friday's deposit: about $312.",
		"above zero"
	)
	_eq(
		Money.lowest_line(_forecast([], _deposit(1), low), TODAY),
		"Lowest point before tomorrow's deposit: about $312.",
		"a deposit tomorrow"
	)
	_eq(
		Money.lowest_line(_forecast([], _deposit(12), low), TODAY),
		"Lowest point before the 30 Nov deposit: about $312.",
		"a deposit more than six days off by date"
	)
	_eq(
		Money.lowest_line(
			_forecast([], fri, {"date": "2026-11-19", "balance_cents": 120050}), TODAY
		),
		"Lowest point before Friday's deposit: about $1,201.",
		"an estimate is to the whole dollar"
	)
	var below := {"date": When.add_days(TODAY, 1), "balance_cents": -4000}
	_eq(
		Money.lowest_line(_forecast([], fri, below), TODAY),
		"Lowest point before Friday's deposit: about -$40, tomorrow. That is below zero.",
		"below zero, plainly, with no savings"
	)
	var covered := {"other_available_cents": 200000, "other_accounts": ["Rainy day"]}
	_eq(
		Money.lowest_line(_forecast([], fri, below, covered), TODAY),
		(
			"Lowest point before Friday's deposit: about -$40, tomorrow. That is below zero."
			+ " Rainy day holds $2,000, which covers it."
		),
		"below zero, the savings covering it, by name"
	)
	var two := {"other_available_cents": 200000, "other_accounts": ["Rainy day", "Holiday"]}
	_eq(
		Money.lowest_line(_forecast([], fri, below, two), TODAY).ends_with(
			"Savings holds $2,000, which covers it."
		),
		true,
		"two accounts are called Savings"
	)
	var short := {"other_available_cents": 3000, "other_accounts": ["Rainy day"]}
	_eq(
		Money.lowest_line(_forecast([], fri, below, short), TODAY).ends_with("below zero."),
		true,
		"savings that do not cover it are not offered as if they did"
	)
	var edge := {"date": "2026-11-19", "balance_cents": -4000}
	var exact := _forecast([], fri, edge, {"other_available_cents": 4000})
	_eq(Money.lowest_line(exact, TODAY).contains("covers it"), true, "savings exactly covering it")
	_eq(
		Money.lowest_line(_forecast([], fri, {"date": "2026-11-19", "balance_cents": 0}), TODAY),
		"Lowest point before Friday's deposit: about $0.",
		"exactly zero is not below it"
	)
	var none := _forecast([], null, {"date": "2026-11-22", "balance_cents": 52000})
	_eq(
		Money.lowest_line(none, TODAY),
		"Lowest point in the next 45 days: about $520.",
		"no deposit seen: the lowest over the forecast"
	)
	_eq(Money.lowest_line({}, TODAY), "", "no lowest point, no sentence")


func _subscriptions() -> void:
	_eq(
		Money.was_line({"amount_cents": -1299, "was_cents": -999}),
		"was $9.99",
		"a price that went up"
	)
	_eq(Money.was_line({"amount_cents": -1299, "was_cents": null}), "", "no earlier price")
	_eq(Money.was_line({"amount_cents": -1299}), "", "no key at all")
	_eq(Money.was_line({"amount_cents": -999, "was_cents": -1299}), "", "a price that went down")
	_eq(Money.was_line({"amount_cents": -999, "was_cents": -999}), "", "the same price")
	_eq(Money.rhythm_word("fortnightly"), "every two weeks", "the rhythms in words")
	_eq(Money.rhythm_word("monthly"), "monthly", "monthly")
	_eq(Money.rhythm_word("quarterly"), "quarterly", "one it does not know is said as it came")


func _figures() -> void:
	var low := {"date": "2026-11-19", "balance_cents": 5}
	var forecast := _forecast([], null, low)
	_eq(Money.forecast_of(forecast).is_empty(), false, "a forecast is a forecast")
	_eq(
		Money.forecast_of({"with": forecast, "without": forecast}) == forecast,
		true,
		"a purchase's with"
	)
	_eq(
		Money.forecast_of({"verdict": "covers"}).is_empty(),
		true,
		"a figure with no days draws nothing"
	)
	_eq(Money.forecast_of(null).is_empty(), true, "no figures")
	_eq(Money.forecast_of({"days": [], "events": "x"}).is_empty(), true, "events that are no list")


func _staged() -> void:
	var spec := {
		"start_cents": 100000,
		"everyday_cents": 1000,
		"events":
		[
			{"in_days": 3, "kind": "charge", "name": "Rent", "amount_cents": -50000},
			{"in_days": 6, "kind": "deposit", "name": "Paycheck", "amount_cents": 80000},
		],
		"other_available_cents": 7000,
		"other_accounts": ["Rainy day"],
	}
	var f := Money.staged_forecast(spec, TODAY)
	_eq(f["days"].size(), 46, "forty-five days and today")
	_eq(f["days"][0]["expected_cents"], 100000, "today is the start")
	_eq(f["days"][3]["expected_cents"], 100000 - 3 * 1000 - 50000, "a charge and the everyday")
	_eq(f["basis"]["next_deposit"]["date"], "2026-11-24", "the next deposit's date")
	_eq(f["before_next_deposit"]["balance_cents"], 100000 - 5 * 1000 - 50000, "lowest before it")
	_eq(f["events"].map(func(e): return e["name"]), ["Rent", "Paycheck"], "events by date")
	_eq(
		Money.lowest_line(f, TODAY),
		"Lowest point before Tuesday's deposit: about $450.",
		"read as the server's"
	)
	var spec_summary := {
		"available": 1,
		"due_this_week": [{"name": "Rent", "amount": 5, "in_days": 4}],
		"next_deposit": {"name": "Paycheck", "amount": 9, "in_days": 6},
	}
	var s := Money.staged_summary(spec_summary, TODAY)
	_eq(
		s["due_this_week"][0], {"name": "Rent", "amount": 5, "on": "2026-11-22"}, "a staged due row"
	)
	_eq(s["next_deposit"]["on"], "2026-11-24", "a staged deposit")
