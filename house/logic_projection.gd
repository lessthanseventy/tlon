extends "res://logic_local.gd"

# The logic checks of the bank projection: the forecast day by day, a purchase's verdict, what-ifs,
# the history by month, the merchants and the subscriptions, over transactions built the way the
# keep stores them.
const Projecting := preload("res://bank_projection.gd")
const Recurring := preload("res://bank_recurring.gd")
const U := preload("res://bank_util.gd")

const TODAY := "2026-11-20"


func run() -> void:
	_forecast_basics()
	_forecast_overdue()
	_forecast_ended()
	_forecast_everyday()
	_afford()
	_what_if()
	_history()
	_subscriptions()
	_budget()
	_no_clock()


func _accounts() -> Array:
	return [
		{
			"id": "a1",
			"type": "depository",
			"subtype": "checking",
			"current": 500000,
			"available": 480000
		},
		{
			"id": "s1",
			"type": "depository",
			"subtype": "savings",
			"current": 9000000,
			"available": 9000000
		},
	]


func _txn(date: String, cents: int, name: String, extra: Dictionary = {}) -> Dictionary:
	var row := {
		"id": "%s-%s-%d" % [name, date, cents],
		"account_id": "a1",
		"cents": cents,
		"date": date,
		"name": name,
		"merchant": null,
		"pending": false,
	}
	row.merge(extra, true)
	return Recurring.txn(row)


func _repeated(name: String, cents: int, last: String, n: int, shift: Callable) -> Array:
	var out: Array = []
	for i in n:
		out.append(_txn(shift.call(last, i), cents, name))
	return out


func _monthly(name: String, cents: int, last: String, n: int) -> Array:
	return _repeated(name, cents, last, n, func(d, i): return U.shift_months(d, -i))


func _weekly(name: String, cents: int, last: String, n: int) -> Array:
	return _repeated(name, cents, last, n, func(d, i): return U.add(d, -7 * i))


func _fortnightly(name: String, cents: int, last: String, n: int) -> Array:
	return _repeated(name, cents, last, n, func(d, i): return U.add(d, -14 * i))


func _everyday(n: int, cents: int = 3000) -> Array:
	var out: Array = []
	for i in range(1, n + 1):
		out.append(_txn(U.add(TODAY, -i), cents, "Shop %d" % i))
	return out


func _flat(parts: Array) -> Array:
	var out: Array = []
	for p in parts:
		if p is Array:
			out.append_array(_flat(p))
		else:
			out.append(p)
	return out


func _data(txns: Array, accounts: Variant = null) -> Dictionary:
	return {
		"transactions": _flat(txns),
		"accounts": accounts if accounts != null else _accounts(),
	}


func _base() -> Dictionary:
	return _data(
		[
			_monthly("Rent", 120000, "2026-10-27", 4),
			_monthly("Salary", -300000, "2026-11-13", 4),
			_weekly("Gym", 1500, "2026-11-17", 5),
			_everyday(100),
		]
	)


func _ok(r: Dictionary, what: String) -> Dictionary:
	s._check(r.has("ok"), "%s: ok, got %s" % [what, str(r)])
	return r.get("ok", {})


func _forecast(data: Dictionary, until: String = "2027-01-20") -> Dictionary:
	return _ok(Projecting.forecast(data, TODAY, until), "forecast")


func _named(events: Array, name: String) -> Array:
	return events.filter(func(e): return e["name"] == name)


func _pairs(events: Array) -> Array:
	return events.map(func(e): return [e["date"], e["amount_cents"]])


func _dates(events: Array) -> Array:
	return events.map(func(e): return e["date"])


func _expected(days: Array) -> Array:
	return days.map(func(d): return d["expected_cents"])


func _sum(values: Array) -> int:
	return U.sum(values)


func _amounts(events: Array) -> Array:
	return events.map(func(e): return e["amount_cents"])


func _minus(a: Array, b: Array) -> Array:
	var out := a.duplicate()
	for y in b:
		var at := out.find(y)
		if at >= 0:
			out.remove_at(at)
	return out


func _forecast_basics() -> void:
	var f := _forecast(_base())
	_eq(f["start_cents"], 480000, "starts at the spendable available balance")
	_eq(
		_pairs(_named(f["events"], "Rent")),
		[["2026-11-27", -120000], ["2026-12-27", -120000]],
		"the rent at its rhythm"
	)
	var salary: Array = _named(f["events"], "Salary")
	_eq(salary.size() > 0, true, "the salary is an event")
	var first: Dictionary = salary[0]
	_eq(
		[first["date"], first["amount_cents"], first["kind"], first["rhythm"], first["count"]],
		["2026-12-13", 300000, "deposit", "monthly", 4],
		"the first salary event"
	)
	_eq(
		f["basis"]["next_deposit"],
		{"name": "Salary", "date": "2026-12-13", "overdue": false},
		"the next deposit"
	)
	_eq("one_off_bills_unknown" in f["basis"]["caveats"], true, "the one-off caveat is named")
	_eq("short_history" in f["basis"]["caveats"], false, "ninety days is not a short history")

	f = _forecast(_base(), "2026-12-31")
	var days := U.diff(f["until"], TODAY)
	var events := _sum(_amounts(f["events"]))
	_eq(
		f["days"][-1]["expected_cents"],
		f["start_cents"] + events - f["everyday"]["expected_daily_cents"] * days,
		"the end balance is the start plus the events minus everyday spending"
	)
	_eq(f["days"].size(), days + 1, "a day for each date, today included")
	_eq(
		f["days"][0],
		{"date": TODAY, "low_cents": 480000, "expected_cents": 480000, "high_cents": 480000},
		"today is the balance as it is"
	)

	var ordered := true
	for d in _forecast(_base())["days"]:
		ordered = ordered and d["low_cents"] <= d["expected_cents"]
		ordered = ordered and d["expected_cents"] <= d["high_cents"]
	_eq(ordered, true, "the low line is never above the expected, nor the high below it")

	f = _forecast(_base(), "2030-01-01")
	_eq([f["clamped"], f["until"]], [true, U.add(TODAY, 180)], "the horizon is capped at 180 days")
	_eq(_forecast(_base(), "2026-12-01")["clamped"], false, "a near horizon is not clamped")

	f = _forecast(_base(), "2026-12-31")
	_eq(f["lowest"]["balance_cents"], _expected(f["days"]).min(), "the lowest point")
	var before: Array = f["days"].filter(func(d): return d["date"] < "2026-12-13")
	_eq(
		f["before_next_deposit"]["balance_cents"],
		_expected(before).min(),
		"the lowest point before the next deposit"
	)

	f = _forecast(_data([_monthly("Rent", 120000, "2026-10-27", 3), _everyday(100)]))
	_eq(f["before_next_deposit"], null, "no deposit series, no before_next_deposit")
	_eq("no_deposit_seen" in f["basis"]["caveats"], true, "no deposit is named")

	var no_data := {"error": "no_data"}
	_eq(Projecting.forecast(_data([_everyday(10)], []), TODAY, TODAY), no_data, "no accounts")
	_eq(Projecting.forecast(_data([[]], _accounts()), TODAY, TODAY), no_data, "no transactions")
	_eq(
		Projecting.forecast(_data([_everyday(10)], _accounts().slice(1)), TODAY, TODAY),
		no_data,
		"no spendable account"
	)

	var pending := _txn(TODAY, 900, "Cafe", {"pending": true})
	f = _forecast(_data([pending, _base()["transactions"]]))
	_eq("pending_ignored" in f["basis"]["caveats"], true, "pending transactions are named")

	var other := _txn(U.add(TODAY, -3), 900, "Elsewhere", {"account_id": "s1"})
	f = _forecast(_data([other]))
	_eq(
		f["everyday"],
		{
			"expected_daily_cents": 0,
			"low_daily_cents": 0,
			"high_daily_cents": 0,
			"mean_daily_cents": 0,
			"occasional_daily_cents": 0,
			"history_days": 0,
		},
		"a checking account with no transactions of its own spends nothing everyday"
	)
	_eq(f["days"][-1]["expected_cents"], 480000, "and stays at its balance")

	var loan := _data([_monthly("Loan", 10000, "2026-10-31", 3), _everyday(100)])
	_eq(
		_dates(_named(_forecast(loan, "2027-03-31")["events"], "Loan")),
		["2026-11-30", "2026-12-31", "2027-01-31", "2027-02-28", "2027-03-31"],
		"a charge of the 31st falls on a short month's last day and keeps the 31st after"
	)

	var counts := _data(
		[
			_weekly("Gym", 1500, "2026-11-17", 4),
			_fortnightly("Cleaner", 5000, "2026-11-12", 4),
			_everyday(100),
		]
	)
	f = _forecast(counts, U.add(TODAY, 28))
	_eq(_named(f["events"], "Gym").size(), 4, "four weekly gyms in four weeks")
	_eq(_named(f["events"], "Cleaner").size(), 2, "two fortnightly cleaners in four weeks")

	var yearly := [_txn("2025-12-05", 9900, "Domain"), _txn("2024-12-05", 9900, "Domain")]
	f = _forecast(_data([yearly, _everyday(100)]), "2027-01-01")
	_eq(_dates(_named(f["events"], "Domain")), ["2026-12-05"], "a yearly charge is there once")
	f = _forecast(_data([yearly, _everyday(100)]), "2026-12-01")
	_eq(_named(f["events"], "Domain"), [], "or not at all")


func _forecast_overdue() -> void:
	var late := _data([_monthly("Rent", 120000, "2026-10-17", 4), _everyday(100)])
	var f := _forecast(late, "2026-12-31")
	var rent := _named(f["events"], "Rent").slice(0, 2)
	_eq(rent.size(), 2, "an overdue rent and the next one")
	_eq(
		[rent[0]["date"], rent[0]["amount_cents"], rent[0]["overdue"], rent[0]["expected_on"]],
		["2026-11-21", -120000, true, "2026-11-17"],
		"an overdue charge inside the grace stays, tomorrow"
	)
	_eq(
		[rent[1]["date"], rent[1]["overdue"], rent[1]["expected_on"]],
		["2026-12-17", false, null],
		"and the next is as usual"
	)
	_eq(
		f["days"][1]["expected_cents"],
		480000 - 120000 - f["everyday"]["expected_daily_cents"],
		"the overdue charge lowers the line tomorrow"
	)
	_eq(f["basis"]["skipped"], [], "nothing is skipped")
	var days := U.diff(f["until"], TODAY)
	_eq(
		f["days"][-1]["expected_cents"],
		480000 + _sum(_amounts(f["events"])) - f["everyday"]["expected_daily_cents"] * days,
		"the end balance holds with the overdue event"
	)

	var posted := _data([_monthly("Rent", 120000, "2026-11-18", 4), _everyday(100)])
	var events: Array = _forecast(posted, "2026-12-31")["events"]
	_eq(events.size(), 1, "a charge that has arrived is expected once")
	_eq([events[0]["date"], events[0]["overdue"]], ["2026-12-18", false], "next month")

	var pending := _data(
		[
			_monthly("Rent", 120000, "2026-10-17", 4),
			_txn("2026-11-19", 120000, "Rent", {"pending": true}),
			_everyday(100),
		]
	)
	events = _forecast(pending, "2026-12-31")["events"]
	_eq(events.size(), 1, "a pending charge is not counted twice")
	_eq([events[0]["date"], events[0]["overdue"]], ["2026-12-17", false], "it is the arrival")

	f = _forecast(_data([_monthly("Rent", 120000, "2026-10-01", 4), _everyday(100)]), "2026-12-31")
	_eq(f["events"].size(), 1, "past the grace a charge is rolled forward")
	_eq([f["events"][0]["date"], f["events"][0]["overdue"]], ["2026-12-01", false], "to its next")
	_eq(f["basis"]["skipped"], ["Rent"], "and named")
	_eq("skipped_charge" in f["basis"]["caveats"], true, "with its caveat")

	f = _forecast(_data([_monthly("Rent", 120000, "2026-10-15", 4), _everyday(100)]))
	var two := _named(f["events"], "Rent").slice(0, 2)
	_eq([two[0]["overdue"], two[1]["overdue"]], [true, false], "one cycle late is still overdue")
	f = _forecast(_data([_monthly("Rent", 120000, "2026-09-25", 4), _everyday(100)]))
	_eq(f["basis"]["skipped"], ["Rent"], "past the grace it is skipped")
	f = _forecast(_data([_monthly("Rent", 120000, "2026-09-10", 4), _everyday(100)]))
	_eq(f["basis"]["skipped"], [], "beyond the window it has ended, not skipped")
	_eq(_named(f["events"], "Rent"), [], "and is no event")

	var rent_series := _monthly("Corner Shop", 4000, "2026-10-01", 3)
	f = _forecast(_data([rent_series, _everyday(100)]), "2026-12-31")
	_eq(f["basis"]["skipped"], ["Corner Shop"], "an unseen monthly charge is skipped")
	var visit := _txn(U.add(TODAY, -7), 912, "Corner Shop 042")
	f = _forecast(_data([rent_series, visit, _everyday(100)]), "2026-12-31")
	_eq(f["basis"]["skipped"], [], "a charge under a longer label of the merchant, at any amount")

	f = _forecast(
		_data([_monthly("Salary", -300000, "2026-10-17", 4), _everyday(100)]), "2026-12-31"
	)
	_eq(
		f["basis"]["next_deposit"],
		{"name": "Salary", "date": "2026-11-21", "overdue": true},
		"an overdue deposit is placed tomorrow"
	)
	_eq(f["before_next_deposit"]["date"], TODAY, "and bounds before_next_deposit there")


func _forecast_ended() -> void:
	var ended := [
		_monthly("Old gym", 4000, "2026-03-10", 6), _weekly("Old coffee", 900, "2026-02-01", 5)
	]
	var old_pay := _monthly("Old employer", -300000, "2026-03-13", 5)
	var f := _forecast(_data([ended, old_pay, _base()["transactions"]]), "2027-01-20")
	var gone: Array = f["events"].filter(
		func(e): return e["name"] in ["Old gym", "Old coffee", "Old employer"]
	)
	_eq(gone, [], "a series past its window has ended: no event")
	_eq(f["basis"]["skipped"], [], "no skip")
	_eq("skipped_charge" in f["basis"]["caveats"], false, "no skip caveat")
	_eq(f["basis"]["series"], _forecast(_base())["basis"]["series"], "no series")

	var pay := [
		_fortnightly("Acme Payroll", -300000, U.add(TODAY, -550), 11),
		_fortnightly("ACME PAYROLL INC", -300000, U.add(TODAY, -480), 5),
		_fortnightly("Acme Co Salary", -300000, U.add(TODAY, -7), 35),
	]
	f = _forecast(_data([pay, _everyday(100)]), U.add(TODAY, 28))
	var deposits: Array = f["events"].filter(func(e): return e["kind"] == "deposit")
	_eq(
		deposits.map(func(e): return e["name"]),
		["Acme Co Salary", "Acme Co Salary"],
		"one payer under three labels: only the live label is a deposit"
	)
	_eq(_dates(deposits), [U.add(TODAY, 7), U.add(TODAY, 21)], "on its fortnightly dates")

	var d := _data([_monthly("Old gym", 4000, "2026-03-10", 6), _base()["transactions"]])
	var a := _ok(Projecting.afford(d, TODAY, 10000, null), "afford")
	_eq(_named(a["without"]["events"], "Old gym"), [], "ended series leave afford")
	var dropped := Projecting.what_if(d, TODAY, [{"kind": "drop", "name": "Old gym"}], "2026-12-31")
	_eq([dropped.get("error"), dropped.get("name")], ["no_series", "Old gym"], "and drop")
	var changed := Projecting.what_if(
		d, TODAY, [{"kind": "change", "name": "Old gym", "cost": 100}], "2026-12-31"
	)
	_eq([changed.get("error"), changed.get("name")], ["no_series", "Old gym"], "and change")
	var subs := Projecting.subscriptions(d, TODAY)
	_eq(subs.filter(func(x): return x["name"] == "Old gym"), [], "and subscriptions")

	var cases := [
		[func(e): return _weekly("W", 500, e, 4), 16],
		[func(e): return _fortnightly("F", 500, e, 4), 31],
		[func(e): return _monthly("M", 500, e, 4), 64],
		[func(e): return [_txn(e, 500, "Y"), _txn(U.shift_years(e, -1), 500, "Y")], 395],
	]
	for c in cases:
		var build: Callable = c[0]
		var edge: int = c[1]
		var live := _data([build.call(U.add(TODAY, -edge)), _everyday(100)])
		var over := _data([build.call(U.add(TODAY, -edge - 1)), _everyday(100)])
		_eq(
			Projecting.subscriptions(live, TODAY).is_empty(),
			false,
			"live on the last day of its window (%d)" % edge
		)
		_eq(Projecting.subscriptions(over, TODAY).is_empty(), true, "ended the day after (%d)" % edge)


func _forecast_everyday() -> void:
	var often: Array = []
	for i in range(1, 31):
		often.append(_txn(U.add(TODAY, -3 * i - (i * i) % 4), 600 + 100 * (i % 3), "Corner Market"))
	var rent := _monthly("Rent", 12000, "2026-10-27", 3)
	var transfer := [
		_txn(U.add(TODAY, -5), 50000, "To savings"),
		_txn(U.add(TODAY, -5), -50000, "From checking", {"account_id": "s1"}),
	]
	var d := _data([often, rent, transfer])
	var f := _forecast(d)
	var window := U.add(TODAY, 1 - f["everyday"]["history_days"])
	var outflow := 0
	for t in d["transactions"]:
		if (
			t["cents"] > 0
			and t["account_id"] == "a1"
			and t["date"] >= window
			and t["label"] != "To savings"
		):
			outflow += t["cents"]
	var series_out := 0
	for t in rent:
		if t["date"] >= window:
			series_out += t["cents"]
	_eq(outflow > 0, true, "there is outflow in the window")
	var rounding := absi(
		outflow - series_out - f["everyday"]["mean_daily_cents"] * f["everyday"]["history_days"]
	)
	_eq(
		rounding <= f["everyday"]["history_days"] / 2,
		true,
		"series outflow and everyday outflow add up to the outflow over the window"
	)

	var tr := [
		_txn(U.add(TODAY, -3), 50000, "To savings"),
		_txn(U.add(TODAY, -3), -50000, "From checking", {"account_id": "s1"}),
	]
	var only_shops := _forecast(_data([_everyday(100)]))
	var with_rest := _forecast(
		_data([_everyday(100), _monthly("Rent", 120000, "2026-10-27", 4), tr])
	)
	_eq(
		with_rest["everyday"]["expected_daily_cents"],
		only_shops["everyday"]["expected_daily_cents"],
		"recurring charges and transfers do not count toward everyday spending"
	)
	_eq(only_shops["everyday"]["expected_daily_cents"], 3000, "the everyday figure, a median week")
	_eq(only_shops["everyday"]["mean_daily_cents"], 2967, "and the plain average")

	var lumps := [
		_txn(U.add(TODAY, -9), 100000, "Cash one"),
		_txn(U.add(TODAY, -32), 90000, "Transfer to a friend"),
		_txn(U.add(TODAY, -70), 120000, "Cash two"),
	]
	var lumpy: Dictionary = _forecast(_data([_everyday(100), lumps]))["everyday"]
	_eq(
		lumpy["expected_daily_cents"] * 4 <= only_shops["everyday"]["expected_daily_cents"] * 5,
		true,
		"three lumps in 90 days move the expected daily figure at most a quarter: %s" % str(lumpy)
	)
	_eq(
		lumpy["mean_daily_cents"] > only_shops["everyday"]["mean_daily_cents"] + 3000,
		true,
		"the plain average carries them"
	)
	_eq(
		lumpy["occasional_daily_cents"],
		lumpy["mean_daily_cents"] - lumpy["expected_daily_cents"],
		"what they add is said apart as occasional"
	)
	_eq(
		lumpy["high_daily_cents"] > lumpy["expected_daily_cents"],
		true,
		"and the cautious line still counts them"
	)

	var flex := [
		_txn("2026-11-13", 50000, "Flexible Finance Inc.", {"merchant": "Flexible Finance"}),
		_txn("2026-11-02", 70000, "Flex* Flexible Finance", {"merchant": "Flex"}),
		_txn("2026-10-16", 50000, "Flex* Flexible Finance", {"merchant": "Flex"}),
		_txn("2026-10-03", 52000, "Flexible Finance Inc.", {"merchant": "Flexible Finance"}),
		_txn("2026-09-07", 50000, "Flex* Flexible Finance", {"merchant": "Flex"}),
		_txn("2026-09-02", 51000, "Flex* Flexible Finance", {"merchant": "Flex"}),
		_txn("2026-08-11", 50000, "Flex* Flexible Finance", {"merchant": "Flex"}),
		_txn("2026-08-02", 51000, "Flex* Flexible Finance", {"merchant": "Flex"}),
	]
	var on_flex := _forecast(_data([_everyday(100), flex]), "2026-12-31")
	_eq(
		_pairs(_named(on_flex["events"], Recurring.RENT_LABEL)),
		[["2026-12-02", -52000], ["2026-12-13", -50000]],
		"rent in two installments on two merchant names is one monthly bill, each on its day"
	)
	_eq(
		on_flex["everyday"],
		only_shops["everyday"],
		"and none of it is everyday spending"
	)

	var labels := [
		"Transfer to Acme Savings Account", "Moved to Acme Savings account", "Acme transfer"
	]
	var moves: Array = []
	for i in range(1, 61):
		for leg in [[20000 + 100 * i, "a1", "s1"], [7000 + 100 * i, "s1", "a1"]]:
			var day := U.add(TODAY, -((i * 7) % 85) - 2)
			var lag := 1 if i % 2 == 0 else 0
			moves.append(_txn(day, leg[0], labels[i % 3], {"account_id": leg[1]}))
			moves.append(_txn(U.add(day, lag), -leg[0], "Acme transfer", {"account_id": leg[2]}))
	var with_moves := _forecast(_data([_everyday(100), moves]))
	_eq(with_moves["everyday"], only_shops["everyday"], "moves never reach everyday spending")
	_eq(with_moves["basis"]["series"], only_shops["basis"]["series"], "nor the series")
	_eq(with_moves["events"], only_shops["events"], "nor the events")

	f = _forecast(_data([_everyday(10)]))
	_eq(f["everyday"]["history_days"], 11, "eleven days of history")
	_eq(f["everyday"]["low_daily_cents"], f["everyday"]["expected_daily_cents"], "low is expected")
	_eq(
		f["everyday"]["high_daily_cents"], f["everyday"]["expected_daily_cents"], "high is expected"
	)
	_eq("short_history" in f["basis"]["caveats"], true, "the short history is named")

	var quiet: Array = []
	for i in range(61, 91):
		quiet.append(_txn(U.add(TODAY, -i), 1000, "Old %d" % i))
	var busy: Array = []
	for i in range(1, 61):
		busy.append(_txn(U.add(TODAY, -i), 4000, "New %d" % i))
	f = _forecast(_data([quiet, busy]))
	_eq(
		f["everyday"]["low_daily_cents"] <= f["everyday"]["expected_daily_cents"],
		true,
		"low is at most expected"
	)
	_eq(f["everyday"]["high_daily_cents"], 4000, "high is the busy 30 days")
	_eq(f["everyday"]["low_daily_cents"] < 4000, true, "low is below it")


func _budget_of(txns: Array, available: int = 480000) -> Dictionary:
	var accounts := _accounts()
	accounts[0]["available"] = available
	return _ok(Projecting.budget(_data(txns, accounts), TODAY), "budget")


func _budget() -> void:
	var salary := _monthly("Salary", -300000, "2026-10-24", 4)
	var rent := _monthly("Rent", 120000, "2026-10-22", 4)
	var gym := _weekly("Gym", 1500, TODAY, 5)
	var today := [
		_txn(TODAY, 2300, "Corner Cafe"),
		_txn(TODAY, 500, "Bakery", {"pending": true}),
	]
	var week := [
		_txn("2026-11-17", 14000, "Walmart"),
		_txn("2026-11-16", 2500, "Lyft"),
		_txn("2026-11-18", 3100, "Lyft"),
		_txn("2026-11-12", 20000, "ATM Withdrawal"),
	]
	var all := [salary, rent, gym, today, week, _everyday(100)]
	var b := _budget_of(all)
	_eq(b["until"], "2026-11-24", "until the next deposit")
	_eq(b["deposit"], "Salary", "named")
	_eq(b["days"], 4, "four days to it")
	_eq(b["bills_cents"], 120000, "the rent before the deposit is a bill; the gym after today too")
	_eq(
		b["bills"].map(func(x): return x["name"]),
		["Rent"],
		"listed: %s" % str(b["bills"])
	)
	_eq(b["spent_today_cents"], 2800, "today's spend counts pending and leaves out the gym bill")
	_eq(b["cushion_cents"] > 0, true, "a day of everyday spending is the cushion")
	_eq(
		b["safe_daily_cents"],
		(480000 + 2800 - 120000 - b["cushion_cents"]) / 4,
		"spare at the start of today over the days to the deposit"
	)
	_eq(b["short_cents"], 0, "nothing short")

	var short := _budget_of(all, 100000)
	_eq(short["safe_daily_cents"], 0, "nothing spare")
	_eq(
		short["short_cents"],
		120000 + short["cushion_cents"] - 100000 - 2800,
		"short by what the bills and the cushion are over what is there"
	)
	_eq(short["other_available_cents"], 9000000, "the savings are beside it")

	var late := _budget_of(
		[_monthly("Salary", -300000, "2026-10-20", 4), today, _everyday(100)]
	)
	_eq(late["until"], U.add(TODAY, 1), "a deposit due today and not in is kept just ahead")
	_eq(late["days"], 1, "one day to it")

	var none := _budget_of([rent, today, _everyday(100)])
	_eq([none["until"], none["safe_daily_cents"]], [null, null], "no deposit seen, no figure")
	_eq(none["spent_today_cents"], 2800, "today's spend still")

	var this: Dictionary = b["weeks"][0]
	_eq([this["from"], this["to"]], ["2026-11-16", TODAY], "this week runs from Monday")
	_eq(
		this["top"].slice(0, 2),
		[{"name": "Walmart", "amount_cents": 14000}, {"name": "Lyft", "amount_cents": 5600}],
		"the week's top merchants by amount, a merchant's spends together"
	)
	_eq(this["top"].size(), 4, "at most four")
	_eq(
		this["top"].any(func(m): return m["name"] == "Gym"),
		false,
		"a bill is not where it went"
	)
	var last: Dictionary = b["weeks"][1]
	_eq([last["from"], last["to"]], ["2026-11-09", "2026-11-15"], "last week, Monday to Sunday")
	_eq(last["top"][0], {"name": "ATM Withdrawal", "amount_cents": 20000}, "its biggest")
	_eq(last["total_cents"], 20000 + 7 * 3000, "its total")


func _afford_ok(
	data: Dictionary, cents: int, on: Variant = TODAY, opts: Dictionary = {}
) -> Dictionary:
	return _ok(Projecting.afford(data, TODAY, cents, on, opts), "afford %d" % cents)


func _afford() -> void:
	var a := _afford_ok(_base(), 12345, "2026-12-01")
	var exact := true
	for i in a["with"]["days"].size():
		var w: Dictionary = a["with"]["days"][i]
		var wo: Dictionary = a["without"]["days"][i]
		var want := 0 if w["date"] < "2026-12-01" else 12345
		exact = exact and wo["expected_cents"] - w["expected_cents"] == want
		exact = exact and wo["low_cents"] - w["low_cents"] == want
	_eq(exact, true, "a purchase lowers every day on and after its date by its amount, none before")

	var checking := {
		"id": "a1",
		"type": "depository",
		"subtype": "checking",
		"current": 50000,
		"available": 50000,
	}
	var saving := func(available: int) -> Dictionary:
		return {
			"id": "s1",
			"name": "Acme Savings",
			"type": "depository",
			"subtype": "savings",
			"current": available,
			"available": available,
		}
	var rent := _monthly("Rent", 120000, "2026-10-27", 4)
	var big := _afford_ok(_data([rent, _everyday(100)], [checking, saving.call(9000000)]), 5000)
	_eq(
		[
			big["verdict"],
			big["other_available_cents"],
			big["other_accounts"],
			big["covered_by_other"]
		],
		["short", 9000000, ["Acme Savings"], true],
		"savings is named beside the forecast and covers the shortfall"
	)
	_eq(big["with"]["other_available_cents"], 9000000, "the forecast carries it")
	_eq(big["with"]["start_cents"], 50000, "on checking alone")
	var small := _afford_ok(_data([rent, _everyday(100)], [checking, saving.call(1000)]), 5000)
	_eq(
		[small["verdict"], small["covered_by_other"]],
		["short", false],
		"a small saving is not enough"
	)
	var covers := _afford_ok(_base(), 1000)
	_eq([covers["verdict"], covers["covered_by_other"]], ["covers", null], "covers has no answer")
	_eq(
		[covers["other_available_cents"], covers["other_accounts"]],
		[9000000, []],
		"the other accounts, unnamed"
	)

	var low := [
		{
			"id": "a1",
			"type": "depository",
			"subtype": "checking",
			"current": 50000,
			"available": 50000
		}
	]
	a = _afford_ok(_data([_monthly("Rent", 120000, "2026-10-27", 4), _everyday(100)], low), 5000)
	var base_short: int = a["baseline_shortfall_cents"]
	_eq(
		[a["verdict"], a["short_without"], a["baseline_short_on"]],
		["short", true, "2026-11-27"],
		"a baseline that is already short says so"
	)
	_eq(base_short, -a["without"]["lowest"]["balance_cents"], "with its shortfall")
	_eq(a["adds_cents"], 5000, "and what the purchase adds")
	_eq(a["shortfall_cents"], base_short + 5000, "to the shortfall")
	_eq(
		[
			covers["short_without"],
			covers["baseline_shortfall_cents"],
			covers["baseline_short_on"],
			covers["adds_cents"]
		],
		[false, null, null, null],
		"a covered baseline has none"
	)

	for bad in [0, -500, 10.5, "20"]:
		_eq(
			Projecting.afford(_base(), TODAY, bad, null),
			{"error": "bad_amount"},
			"%s is a bad amount" % str(bad)
		)

	_eq(
		Projecting.afford(_base(), TODAY, 1000, U.add(TODAY, 181)),
		{"error": "beyond_horizon"},
		"a purchase past the cap is refused"
	)
	a = _afford_ok(_base(), 1000, U.add(TODAY, 180))
	_eq(a["without"]["until"], U.add(TODAY, 180), "on the cap it is counted")
	_eq(
		a["without"]["days"][-1]["expected_cents"] - a["with"]["days"][-1]["expected_cents"],
		1000,
		"to the last day"
	)

	a = _afford_ok(_base(), 1000)
	_eq(a["with"]["days"][0]["expected_cents"], 479000, "a purchase today lowers today too")

	var base_low: int = _afford_ok(_base(), 1)["without"]["lowest"]["balance_cents"]
	var cushion := 50000
	var fits := base_low - cushion
	var opts := {"cushion_cents": cushion}
	a = _afford_ok(_base(), fits, TODAY, opts)
	_eq(
		[a["verdict"], a["shortfall_cents"], a["short_on"]],
		["covers", null, null],
		"the verdict is covers at exactly the cushion"
	)
	_eq(_afford_ok(_base(), fits + 1, TODAY, opts)["verdict"], "tight", "tight just under it")
	_eq(_afford_ok(_base(), base_low, TODAY, opts)["verdict"], "tight", "tight at exactly zero")
	a = _afford_ok(_base(), base_low + 1, TODAY, opts)
	_eq([a["verdict"], a["shortfall_cents"]], ["short", 1], "short below zero")

	a = _afford_ok(_base(), 470000, TODAY, {"cushion_cents": 0})
	_eq(a["verdict"], "short", "a big purchase is short")
	var first: Variant = null
	for d in a["with"]["days"]:
		if d["expected_cents"] < 0:
			first = d["date"]
			break
	_eq(a["short_on"], first, "short names the first day below zero")
	_eq(a["shortfall_cents"], -_expected(a["with"]["days"]).min(), "and the shortfall")

	a = _afford_ok(_base(), 1000)
	_eq(
		a["cushion_cents"],
		7 * a["with"]["everyday"]["expected_daily_cents"],
		"the default cushion is a week of everyday spending"
	)
	_eq(a["worst_case"] in ["covers", "tight", "short"], true, "the worst case is a verdict")
	_eq(
		_afford_ok(_base(), 1000, TODAY, {"cushion_cents": 10000000})["worst_case"],
		"tight",
		"a huge cushion is tight on the low line"
	)
	_eq(
		_afford_ok(_base(), 900000)["worst_case"],
		"short",
		"a huge purchase is short on the low line"
	)

	a = _afford_ok(_base(), 1000)
	_eq(U.diff(a["with"]["until"], TODAY), 60, "the horizon is 60 days")
	_eq(a["with"]["until"], a["without"]["until"], "the same with and without")


func _what_if_ok(changes: Array, until: String = "2027-01-20") -> Dictionary:
	return _ok(Projecting.what_if(_base(), TODAY, changes, until), "what_if")


func _what_if() -> void:
	var bad := [
		{"kind": "one_off", "cost": 0, "on": "2026-12-02", "name": "X"},
		{"kind": "one_off", "cost": 1.5, "on": "2026-12-02", "name": "X"},
		{"kind": "recurring", "cost": 0, "rhythm": "weekly", "from": "2026-12-02", "name": "X"},
		{"kind": "recurring", "cost": -5, "rhythm": "weekly", "from": "2026-12-02", "name": "X"},
		{"kind": "change", "name": "salary", "cost": 0},
		{"kind": "change", "name": "salary", "cost": -1},
		{"kind": "change", "name": "salary", "cost": "9"},
	]
	for change in bad:
		_eq(
			Projecting.what_if(_base(), TODAY, [change], "2026-12-31"),
			{"error": "bad_amount"},
			"a bad cost: %s" % str(change)
		)
	var r := _what_if_ok(
		[{"kind": "one_off", "cost": -7000, "on": "2026-12-02", "name": "Gift"}], "2026-12-31"
	)
	_eq(r["difference"]["end_cents"], 7000, "a negative one-off is money in")

	var beyond := {"error": "beyond_horizon"}
	_eq(
		Projecting.what_if(
			_base(),
			TODAY,
			[{"kind": "one_off", "cost": 100, "on": "2026-12-02", "name": "X"}],
			"2026-12-01"
		),
		beyond,
		"a one-off past the horizon is refused"
	)
	_eq(
		Projecting.what_if(
			_base(),
			TODAY,
			[{"kind": "one_off", "cost": 100, "on": U.add(TODAY, 181), "name": "X"}],
			"2030-01-01"
		),
		beyond,
		"or past the cap"
	)
	_eq(
		Projecting.what_if(
			_base(),
			TODAY,
			[
				{
					"kind": "recurring",
					"cost": 100,
					"rhythm": "weekly",
					"from": U.add(TODAY, 181),
					"name": "X"
				}
			],
			"2030-01-01"
		),
		beyond,
		"a recurring change past the cap is refused"
	)
	r = _what_if_ok(
		[{"kind": "recurring", "cost": 100, "rhythm": "weekly", "from": "2026-12-10", "name": "X"}],
		"2026-12-01"
	)
	_eq(r["changed"], r["baseline"], "a recurring past until but within the cap is not refused")

	_eq(
		_what_if_ok([], "2030-01-01")["clamped"],
		true,
		"the result says when the horizon was clamped"
	)
	_eq(_what_if_ok([])["clamped"], false, "and when it was not")

	r = _what_if_ok([])
	_eq(r["changed"], r["baseline"], "an empty list of changes equals the baseline")
	_eq(r["difference"], {"end_cents": 0, "lowest_cents": 0}, "with no difference")

	r = _what_if_ok([{"kind": "drop", "name": "rEnT"}])
	_eq(
		r["changed"]["events"],
		r["baseline"]["events"].filter(func(e): return e["name"] != "Rent"),
		"dropping a series removes exactly its events, matched in any case"
	)
	_eq(r["difference"]["end_cents"], 240000, "and gains their sum")

	r = _what_if_ok(
		[
			{
				"kind": "recurring",
				"cost": 2000,
				"rhythm": "weekly",
				"from": "2026-12-01",
				"name": "Course"
			}
		],
		"2026-12-31"
	)
	var added := _minus(r["changed"]["events"], r["baseline"]["events"])
	_eq(
		_dates(added),
		["2026-12-01", "2026-12-08", "2026-12-15", "2026-12-22", "2026-12-29"],
		"a recurring change appears at its rhythm from its date"
	)
	_eq(
		added.all(func(e): return e["amount_cents"] == -2000 and e["name"] == "Course"),
		true,
		"each at its cost"
	)

	r = _what_if_ok(
		[
			{"kind": "one_off", "cost": 7000, "on": "2026-12-02", "name": "Fridge"},
			{"kind": "change", "name": "salary", "cost": 350000},
		],
		"2026-12-31"
	)
	_eq(
		r["changed"]["events"].any(
			func(e): return e["name"] == "Fridge" and e["amount_cents"] == -7000
		),
		true,
		"a one-off is a single event"
	)
	_eq(
		r["changed"]["events"].any(
			func(e): return e["name"] == "Salary" and e["amount_cents"] == 350000
		),
		true,
		"a change resizes a series"
	)
	_eq(r["difference"]["end_cents"], 50000 - 7000, "and the difference is both")

	var unknown := Projecting.what_if(_base(), TODAY, [{"kind": "drop", "name": "Rant"}], "2026-12-31")
	_eq([unknown.get("error"), unknown.get("name")], ["no_series", "Rant"], "an unknown series")
	_eq("Rent" in unknown.get("suggestions", []), true, "is an error with the nearest names")


func _special() -> Array:
	return [
		_txn("2026-09-30", 1000, "Corner Cafe"),
		_txn("2026-10-01", 2000, "CORNER CAFE #2"),
		_txn("2026-10-31", 3000, "corner cafe"),
		_txn("2026-11-02", -500, "Corner Cafe refund"),
		_txn("2026-11-03", 700, "Other", {"pending": true}),
		_txn("2026-11-04", 99900, "Move out"),
		_txn("2026-11-04", -99900, "Move in", {"account_id": "a2"}),
	]


func _history_of(matcher: Variant, from: String, to: String) -> Dictionary:
	var r := Projecting.history(
		_data([_everyday(5), _special()]), {"match": matcher, "from": from, "to": to}
	)
	return _ok(r, "history")


func _history() -> void:
	var from := "2026-09-01"
	var to := "2026-11-30"
	var h := _history_of(["cafe refund", "move out", "no such store"], from, to)
	_eq(h["count"], 1, "a list of matches is any-of")
	_eq(
		h["merchants"],
		[{"name": "Corner Cafe refund", "out_cents": 0, "in_cents": 500, "count": 1}],
		"the merchants counted are named with their totals"
	)
	var both := _history_of(["corner cafe", "shop 1"], from, to)
	_eq(
		both["count"], _history_of("corner cafe", from, to)["count"] + 1, "either list entry counts"
	)
	var top: Dictionary = both["merchants"][0]
	_eq([top["out_cents"], top["count"]], [-4000, 2], "the biggest merchant first")
	_eq(top["name"].to_lower(), "corner cafe", "named")
	_eq(_history_of(null, from, to)["merchants"], [], "no match names no merchants")
	_eq(_history_of([], from, to)["count"], 0, "an empty list matches nothing")

	var shops: Array = []
	for i in range(1, 71):
		shops.append(_txn(U.add(TODAY, -1 - i % 80), 500, "Store %02d" % i))
	var often: Array = []
	for d in range(1, 6):
		often.append(_txn(U.add(TODAY, -d), 300, "Daily Bread"))
	var old := _txn(U.add(TODAY, -91), 500, "Long Ago")
	var pending := _txn(TODAY, 500, "Pending Place", {"pending": true})
	var long := _txn(TODAY, 500, "x".repeat(60))
	var move := [
		_txn(TODAY, 90000, "Move out"),
		_txn(TODAY, -90000, "Move in", {"account_id": "a2"}),
	]
	var labels := Projecting.merchants(_data([shops, often, old, pending, long, move]), TODAY)
	_eq(labels[0], "Daily Bread", "merchants lists the most frequent first")
	_eq(labels.size(), 60, "capped")
	_eq(
		labels.any(func(l): return l in ["Long Ago", "Pending Place", "Move out", "Move in"]),
		false,
		"transfers, pending and old rows out"
	)
	_eq(labels.all(func(l): return l.length() <= 40), true, "each at most 40 characters")

	h = _history_of("CAFE", from, to)
	_eq(
		h["months"],
		[
			{"month": "2026-09", "out_cents": -1000, "in_cents": 0, "count": 1},
			{"month": "2026-10", "out_cents": -5000, "in_cents": 0, "count": 2},
			{"month": "2026-11", "out_cents": 0, "in_cents": 500, "count": 1},
		],
		"buckets by calendar month with the case-insensitive match, out and in apart"
	)
	_eq(h["count"], 4, "four rows")
	_eq(h["average_out_cents"], -2000, "the average out per month")
	_eq(h["average_in_cents"], 167, "the average in per month")
	_eq(
		h["largest"][0],
		{"date": "2026-10-31", "name": "corner cafe", "amount_cents": -3000},
		"the largest first"
	)

	h = _history_of(null, "2026-11-01", to)
	_eq(h["count"], 5 + 1, "a nil match is everything posted")
	_eq(
		h["largest"].any(func(x): return x["name"] in ["Other", "Move out", "Move in"]),
		false,
		"pending and transfers stay out"
	)
	_eq(_sum(h["months"].map(func(m): return m["out_cents"])), -15000, "out over the months")
	_eq(_sum(h["months"].map(func(m): return m["in_cents"])), 500, "in over the months")

	_eq(
		Projecting.history(
			_data([_everyday(5)]), {"match": null, "from": "2026-11-02", "to": "2026-11-01"}
		),
		{"error": "bad_range"},
		"from after to is a bad range"
	)

	var empty := _ok(
		Projecting.history(
			_data([_everyday(5)]), {"match": null, "from": "2025-03-05", "to": "2025-03-05"}
		),
		"empty month"
	)
	_eq(
		empty["months"],
		[{"month": "2025-03", "out_cents": 0, "in_cents": 0, "count": 0}],
		"a range inside one empty month gives zeros"
	)
	_eq([empty["count"], empty["largest"]], [0, []], "no rows")
	_eq([empty["average_out_cents"], empty["average_in_cents"]], [0, 0], "no averages")

	_eq(_history_of(null, "2026-01-01", "2026-12-31")["largest"].size(), 5, "the five largest")


func _subscriptions() -> void:
	var raised := [
		_txn("2026-11-05", 1299, "Stream"),
		_txn("2026-10-05", 1299, "Stream"),
		_txn("2026-09-05", 1299, "Stream"),
	]
	var older := [
		_txn("2026-08-05", 999, "Stream"),
		_txn("2026-07-05", 999, "Stream"),
		_txn("2026-06-05", 999, "Stream"),
	]
	var subs := Projecting.subscriptions(_data([_base()["transactions"], raised, older]), TODAY)
	var stream: Dictionary = subs.filter(func(x): return x["name"] == "Stream")[0]
	_eq(
		[stream["amount_cents"], stream["rhythm"], stream["next"], stream["was_cents"]],
		[-1299, "monthly", "2026-12-05", -999],
		"lists the outflow series with their next date and a changed price"
	)
	var rent: Dictionary = subs.filter(func(x): return x["name"] == "Rent")[0]
	_eq(
		[rent["amount_cents"], rent["was_cents"], rent["count"]],
		[-120000, null, 4],
		"a series with no change has no was"
	)
	_eq(subs.any(func(x): return x["name"] == "Salary"), false, "deposits are not subscriptions")
	_eq(subs, U.sort_by(subs, func(x): return [x["next"], x["name"]]), "by next date, then name")


func _no_clock() -> void:
	var source := FileAccess.get_file_as_string("res://bank_projection.gd")
	var re := RegEx.create_from_string(
		"Time\\.|OS\\.get_|get_unix_time|get_datetime|get_ticks|Clock"
	)
	_eq(re.search(source) == null, true, "the module never reads the clock")
