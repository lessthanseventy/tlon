extends "res://logic_local.gd"

# The logic checks of the bank's recurring charges and deposits: what makes a series, the strays
# it passes over, when it is live, new or a price change, doubled charges and transfers.
const Recurring := preload("res://bank_recurring.gd")
const U := preload("res://bank_util.gd")

const TODAY := "2026-11-20"


func run() -> void:
	_basic_series()
	_live()
	_too_few()
	_rhythms()
	_yearly_needs_two()
	_price_change()
	_transfers()
	_irregular_rhythm()
	_amount_tolerance()
	_varying_deposit()
	_history()
	_two_series()
	_everyday()
	_loose_monthly_history()
	_strays()
	_new_amount()
	_games_store()
	_labels_apart()
	_same_merchant()
	_rent_names()
	_run_ends()
	_old_odd_charge()
	_merchant_name()
	_directions()
	_due_within()
	_doubles()
	_new_series()
	_plain_line()
	_unusable_rows()


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


func _monthly(name: String, cents: int, last: String, n: int) -> Array:
	var rows: Array = []
	for i in n:
		rows.append(_txn(U.shift_months(last, -i), cents, name))
	return rows


func _fortnightly(name: String, cents_for: Callable, last: String, n: int) -> Array:
	var rows: Array = []
	for i in n:
		rows.append(_txn(U.add(last, -14 * i), cents_for.call(i), name))
	return rows


func _irregular(name: String, n: int, last: String) -> Array:
	var gaps := [3, 10, 17, 4, 12, 23, 6, 15]
	var rows: Array = []
	var date := last
	for i in range(1, n + 1):
		date = U.add(date, -gaps[i % 8])
		rows.append(_txn(date, 700 if i % 2 == 0 else 15000, name))
	return rows


func _with_stray(rows: Array, date: String, cents: int) -> Array:
	return [_txn(date, cents, "Streamr")] + rows


func _has(got: Variant, want: Dictionary, what: String) -> void:
	if not got is Dictionary:
		s._check(false, "%s: got %s, want a series" % [what, str(got)])
		return
	for k in want:
		_eq(got.get(k), want[k], "%s: %s" % [what, k])


func _only(list: Array, what: String) -> Dictionary:
	_eq(list.size(), 1, what + ": one")
	return list[0] if list.size() == 1 else {}


func _basic_series() -> void:
	var one := _only(Recurring.series(_monthly("Rent", 120000, "2026-10-27", 3), "out"), "rent")
	_has(
		one,
		{
			"label": "Rent",
			"period": "monthly",
			"amount": 120000,
			"last": "2026-10-27",
			"next": "2026-11-27",
			"count": 3,
			"account_id": "a1",
		},
		"three monthly charges"
	)


func _live() -> void:
	for sign in [1, -1]:
		var rows := _monthly("Pay", sign * 120000, U.add(TODAY, -64), 3)
		var all: Array = Recurring.series(rows, "out") + Recurring.series(rows, "in")
		_eq(Recurring.live(all, TODAY).size(), 1, "live through its window, sign %d" % sign)
		_eq(Recurring.live(all, U.add(TODAY, 1)).size(), 0, "ended after it, sign %d" % sign)


func _too_few() -> void:
	_eq(
		Recurring.series(_monthly("Rent", 120000, "2026-10-27", 2), "out"), [], "two are not enough"
	)
	var three := _monthly("Rent", 120000, "2026-10-27", 3)
	var pending: Array = []
	for t in three:
		var p: Dictionary = t.duplicate()
		p["pending"] = t["date"] == "2026-10-27"
		pending.append(p)
	_eq(Recurring.series(pending, "out"), [], "a pending one does not count")


func _rhythms() -> void:
	var weekly: Array = []
	for d in ["2026-11-01", "2026-11-09", "2026-11-15"]:
		weekly.append(_txn(d, 500, "Gym"))
	var fortnight: Array = []
	for d in ["2026-10-02", "2026-10-16", "2026-10-31"]:
		fortnight.append(_txn(d, 9000, "Pay Back"))
	var yearly: Array = []
	for d in ["2024-03-01", "2025-03-02", "2026-03-01"]:
		yearly.append(_txn(d, 3000, "Domain"))
	_has(
		_only(Recurring.series(weekly, "out"), "weekly"),
		{"period": "weekly", "next": "2026-11-22"},
		"weekly"
	)
	_has(
		_only(Recurring.series(fortnight, "out"), "fortnightly"),
		{"period": "fortnightly", "next": "2026-11-14"},
		"fortnightly"
	)
	_has(
		_only(Recurring.series(yearly, "out"), "yearly"),
		{"period": "yearly", "next": "2027-03-01"},
		"yearly"
	)


func _yearly_needs_two() -> void:
	var two := [_txn("2025-03-01", 3000, "Domain"), _txn("2026-03-02", 3000, "Domain")]
	_has(
		_only(Recurring.series(two, "out"), "yearly two"),
		{"period": "yearly", "count": 2, "next": "2027-03-02"},
		"a yearly charge needs two"
	)
	var apart := [_txn("2025-03-01", 3000, "Domain"), _txn("2026-03-02", 9000, "Domain")]
	_eq(Recurring.series(apart, "out"), [], "two a year apart at another amount are none")
	_eq(
		Recurring.series(_monthly("Rent", 120000, "2026-10-27", 2), "out"),
		[],
		"monthly needs three"
	)


func _price_change() -> void:
	var old := _monthly("Streamr", 999, "2026-08-17", 3)
	var up := _monthly("Streamr", 1299, "2026-11-17", 3)
	var found := Recurring.series(old + up, "out")
	_has(
		_only(found, "price change"),
		{"amount": 1299, "was": 999, "count": 6, "at_amount": 3},
		"a new price after an older run"
	)
	_eq(Recurring.new_series(found, TODAY), [], "not a new subscription")
	_eq(
		Recurring.price_changes(found, TODAY).map(func(x): return x["label"]),
		["Streamr"],
		"price change"
	)

	var fresh := Recurring.series(_monthly("Streamr", 999, "2026-11-17", 3), "out")
	_has(_only(fresh, "fresh"), {"was": null}, "a fresh one has no was")
	_eq(Recurring.price_changes(fresh, TODAY), [], "no price change for a fresh one")


func _transfers() -> void:
	var out := _txn("2026-11-01", 20000, "To Savings", {"account_id": "chk"})
	var into := _txn("2026-11-02", -20000, "From Checking", {"account_id": "sav"})
	var spend := _txn("2026-11-02", 20000, "Shop", {"account_id": "chk"})
	var pay := _txn("2026-11-02", -20000, "Pay", {"account_id": "chk"})
	var by_id := func(t): return t["id"]
	_eq(
		U.sort_by(Recurring.without_transfers([out, into, spend, pay]), by_id),
		U.sort_by([spend, pay], by_id),
		"a transfer is neither charge nor deposit"
	)
	var far := _txn("2026-11-09", -20000, "From Checking", {"account_id": "sav"})
	_eq(Recurring.without_transfers([out, far]).size(), 2, "a week apart is no transfer")


func _amount_tolerance() -> void:
	var near := [
		_txn("2026-08-27", 4500, "Phone"),
		_txn("2026-09-26", 4800, "Phone"),
		_txn("2026-10-27", 4650, "Phone"),
	]
	var far := [
		_txn("2026-08-27", 4500, "Phone"),
		_txn("2026-09-26", 12000, "Phone"),
		_txn("2026-10-27", 4650, "Phone"),
	]
	_has(
		_only(Recurring.series(near, "out"), "near"),
		{"amount": 4650, "count": 3},
		"amounts within ten percent"
	)
	_eq(Recurring.series(far, "out"), [], "amounts further apart do not")


func _varying_deposit() -> void:
	var amounts := [3900, 3500, 3800, 3700, 3300, 3600, 2900, 3800, 3600, 3400]
	var pay := _fortnightly("Acme Payroll", func(i): return -amounts[i % 10], "2026-11-13", 35)
	_has(
		_only(Recurring.series(pay, "in"), "payroll"),
		{"period": "fortnightly", "count": 35, "amount": 3700, "was": null},
		"a deposit that varies is one series"
	)


func _history() -> void:
	var storage := (
		_monthly("Storage", 2500, "2026-11-02", 9) + _monthly("Storage", 1800, "2026-02-02", 10)
	)
	_has(
		_only(Recurring.series(storage, "out"), "storage"),
		{"count": 19, "amount": 2500, "at_amount": 9, "was": 1800},
		"a bill's history is the whole run at its latest price"
	)
	var steady := _monthly("Streamr", 999, "2026-11-17", 15)
	_has(
		_only(Recurring.series(steady, "out"), "steady"),
		{"count": 15, "amount": 999, "was": null},
		"a steady run"
	)


func _two_series() -> void:
	var a := _monthly("Apple", 999, "2026-11-05", 6)
	var b := _monthly("Apple", 1499, "2026-11-20", 6)
	var found := Recurring.series(a + b, "out")
	_eq(found.size(), 2, "two stable amounts on two stable days: two series")
	if found.size() == 2:
		_has(found[0], {"amount": 999, "next": "2026-12-05", "count": 6}, "the first of two")
		_has(found[1], {"amount": 1499, "next": "2026-12-20"}, "the second of two")


func _everyday() -> void:
	var tail := _monthly("Corner Market", 4000, "2026-11-10", 3)
	var often := _irregular("Corner Market", 48, "2026-09-10")
	var all := tail + often
	_eq(U.uniq_by(all, func(t): return t["date"]).size(), 51, "51 distinct days")
	_eq(Recurring.series(all, "out"), [], "often at irregular amounts is no series")
	_has(
		_only(Recurring.series(tail + often.slice(0, 4), "out"), "tail and four"),
		{"count": 3},
		"a few irregular ones leave the tail"
	)


func _loose_monthly_history() -> void:
	var rows := _monthly("Mobile Co", 6600, "2026-11-18", 3)
	var date := "2026-05-01"
	for i in 12:
		rows.append(_txn(date, 7000 + 130 * i, "Mobile Co"))
		date = U.add(date, -[35, 25, 43, 22, 31, 36][i % 6])
	_has(
		_only(Recurring.series(rows, "out"), "a loose monthly history"),
		{"period": "monthly", "amount": 6600, "count": 3},
		"a bill that drifts is still a series"
	)


func _strays() -> void:
	var old := _monthly("Streamr", 1995, "2026-08-13", 12)
	var up := _monthly("Streamr", 2395, "2026-11-13", 3)
	var rows := _with_stray(old + up, "2026-09-08", 77)
	var found := Recurring.series(rows, "out")
	_has(
		_only(found, "stepped"),
		{
			"amount": 2395,
			"was": 1995,
			"count": 15,
			"at_amount": 3,
			"last": "2026-11-13",
			"next": "2026-12-13",
		},
		"a lone far, off-rhythm charge in a price-stepped run"
	)
	_eq(Recurring.live(found, TODAY).size(), 1, "the stepped run is live")

	var middle := _with_stray(_monthly("Streamr", 1995, "2026-11-13", 8), "2026-08-08", 77)
	_has(
		_only(Recurring.series(middle, "out"), "middle"),
		{"amount": 1995, "count": 8, "was": null},
		"a stray in the middle of a same-price run"
	)

	var newest := _with_stray(_monthly("Streamr", 1995, "2026-11-13", 6), "2026-11-18", 77)
	var n := _only(Recurring.series(newest, "out"), "newest")
	_has(n, {"amount": 1995, "count": 6, "last": "2026-11-13"}, "a stray as the newest charge")
	_eq(Recurring.live([n], TODAY).size(), 1, "the series with a newest stray is live")

	for gap in [5, 1]:
		var regular := _monthly("Streamr", 1995, "2026-11-13", 6)
		var second := _with_stray(regular, U.add("2026-11-13", -gap), 77)
		_has(
			_only(Recurring.series(second, "out"), "second %d" % gap),
			{"amount": 1995, "count": 6, "last": "2026-11-13"},
			"a stray second-newest, %d days before the newest" % gap
		)

	var third := _with_stray(_monthly("Streamr", 1995, "2026-11-13", 6), "2026-10-08", 77)
	_has(
		_only(Recurring.series(third, "out"), "third"),
		{"amount": 1995, "count": 6},
		"a stray third-newest does not end the run"
	)

	for stray_first in [true, false]:
		var regular := _monthly("Streamr", 1995, "2026-11-13", 6)
		var one_off := _txn("2026-09-13", 77, "Streamr")
		var both: Array = [one_off] + regular if stray_first else regular + [one_off]
		_has(
			_only(Recurring.series(both, "out"), "one-off %s" % stray_first),
			{
				"amount": 1995,
				"count": 6,
				"last": "2026-11-13",
				"next": "2026-12-13",
				"was": null,
			},
			"a one-off far charge on a regular charge's own day, between two that agree"
		)

	var gap_rows := (
		_monthly("Streamr", 1995, "2026-11-13", 4)
		+ [_txn("2026-07-13", 77, "Streamr")]
		+ _monthly("Streamr", 1995, "2026-06-13", 3)
	)
	_has(
		_only(Recurring.series(gap_rows, "out"), "gap"),
		{"count": 4, "amount": 1995, "was": null},
		"a one-off far charge in place of a regular one: the gap it leaves ends the run"
	)

	var older := _with_stray(_monthly("Streamr", 1000, "2026-08-13", 6), "2026-05-13", 77)
	var stepped := _monthly("Streamr", 1800, "2026-11-13", 3) + older
	_has(
		_only(Recurring.series(stepped, "out"), "price change with a one-off"),
		{"amount": 1800, "was": 1000, "at_amount": 3, "count": 9},
		"three charges at a new amount are a price change, a one-off in the old run dropped"
	)

	var on_rhythm := (
		_monthly("Streamr", 1995, "2026-11-13", 3)
		+ [_txn("2026-08-13", 77, "Streamr")]
		+ _monthly("Streamr", 1995, "2026-07-13", 3)
	)
	_has(
		_only(Recurring.series(on_rhythm, "out"), "on rhythm"),
		{"count": 3, "was": null},
		"a far charge that is on the rhythm still ends the run"
	)


func _new_amount() -> void:
	var old := _monthly("Gym", 1000, "2026-08-13", 12)
	var up := _monthly("Gym", 4000, "2026-11-13", 3)
	_has(
		_only(Recurring.series(old + up, "out"), "gym"),
		{"amount": 4000, "count": 3},
		"older charges of the series' own earlier price are never everyday spending"
	)


func _games_store() -> void:
	var gaps := [
		12,
		45,
		7,
		33,
		60,
		18,
		5,
		41,
		25,
		9,
		52,
		15,
		37,
		22,
		58,
		6,
		29,
		48,
		11,
		55,
		20,
		8,
		43,
		31,
		14,
		50,
		10,
		36,
		24
	]
	var amounts := [1999, 5999, 999, 5999, 1999, 4999, 999, 1999, 5999, 4999]
	var rows: Array = []
	var date := U.add(TODAY, -16)
	for i in gaps.size():
		rows.append(_txn(date, amounts[i % 10], "Game Barn"))
		date = U.add(date, -gaps[i])
	_eq(rows.size(), 29, "29 games-store charges")
	_eq(Recurring.series(rows, "out"), [], "about thirty charges on irregular days is everyday")


func _labels_apart() -> void:
	var a := _monthly("Apple iCloud", 999, "2026-11-05", 8)
	var b := _monthly("Apple Music", 1499, "2026-11-20", 8)
	var found := Recurring.series(a + b, "out")
	_eq(
		found.map(func(x): return x["label"]),
		["Apple iCloud", "Apple Music"],
		"two subscriptions at one merchant under two labels stay two series"
	)


func _same_merchant() -> void:
	var cases := [
		["shell", "shell oil 57444", true],
		["shell oil 57444", "shell", true],
		["shell", "shellfish", false],
		["apple music", "apple icloud", false],
	]
	for c in cases:
		_eq(Recurring.same_merchant(c[0], c[1]), c[2], "same_merchant %s / %s" % [c[0], c[1]])


func _rent_names() -> void:
	for n in ["Flex", "FLEXIBLE FINANCE"]:
		_eq(_txn("2026-01-01", -100000, n)["label"], Recurring.RENT_LABEL, "%s is rent" % n)
	for n in ["Flex Fitness", "Flexible Finance Ltd", "Flexor"]:
		_eq(_txn("2026-01-01", -5000, n)["label"], n, "%s is not rent" % n)


func _run_ends() -> void:
	var old := _monthly("Phone", 20000, "2026-07-27", 4)
	var now := _monthly("Phone", 4500, "2026-10-27", 3)
	_has(
		_only(Recurring.series(old + now, "out"), "phone"),
		{"count": 3, "amount": 4500},
		"a charge more than twice or less than half the recent amount ends the run"
	)


func _old_odd_charge() -> void:
	var old := _txn("2026-03-04", 999, "Phone")
	var found := Recurring.series([old] + _monthly("Phone", 4500, "2026-10-27", 3), "out")
	_eq(_only(found, "odd").get("count"), 3, "an old odd charge does not break the latest run")


func _merchant_name() -> void:
	var rows := [
		_txn("2026-08-27", 999, "POS 1 NETFLIX.COM", {"merchant": "Netflix"}),
		_txn("2026-09-26", 999, "POS 2 NETFLIX", {"merchant": "NETFLIX"}),
		_txn("2026-10-27", 999, "x", {"merchant": "netflix."}),
	]
	_has(
		_only(Recurring.series(rows, "out"), "netflix"),
		{"label": "netflix.", "count": 3},
		"the merchant name wins; case and punctuation do not split a merchant"
	)


func _directions() -> void:
	var pay: Array = []
	for d in ["2026-10-02", "2026-10-16", "2026-10-30"]:
		pay.append(_txn(d, -150000, "Acme Payroll"))
	_has(
		_only(Recurring.series(pay, "in"), "pay"),
		{"label": "Acme Payroll", "amount": 150000, "next": "2026-11-13"},
		"deposits are the negative amounts"
	)
	_eq(Recurring.series(pay, "out"), [], "they do not mix")


func _due_within() -> void:
	var found := Recurring.series(_monthly("Rent", 120000, "2026-10-27", 3), "out")
	var cases := [["2026-11-22", 1], ["2026-11-27", 1], ["2026-11-17", 0], ["2026-11-28", 0]]
	for c in cases:
		_eq(Recurring.due_within(found, c[0], 5).size(), c[1], "due_within from %s" % c[0])


func _doubles() -> void:
	var rows := [_txn("2026-11-17", 1499, "Streamr"), _txn("2026-11-18", 1499, "Streamr")]
	var found := Recurring.doubles(rows, TODAY)
	_eq(found.size(), 1, "two equal charges within two days are a double, once")
	if found.size() == 1:
		_has(found[0], {"label": "Streamr", "cents": 1499, "on": "2026-11-18"}, "the double")
	_eq(Recurring.doubles(rows, "2026-12-20"), [], "only when fresh")

	var other := [_txn("2026-11-17", 1499, "S"), _txn("2026-11-18", 1500, "S")]
	_eq(Recurring.doubles(other, TODAY), [], "a different amount is not a double")
	var wide := [_txn("2026-11-10", 1499, "S"), _txn("2026-11-18", 1499, "S")]
	_eq(Recurring.doubles(wide, TODAY), [], "a wider gap is not a double")
	var habit: Array = []
	for d in ["2026-11-16", "2026-11-17", "2026-11-18"]:
		habit.append(_txn(d, 450, "Cafe"))
	_eq(Recurring.doubles(habit, TODAY), [], "a habit is not a double")

	var monthly := (
		_monthly("Rent", 120000, "2026-10-27", 3)
		+ [_txn("2026-11-18", 120000, "Rent"), _txn("2026-11-19", 120000, "Rent")]
	)
	_eq(
		Recurring.doubles(monthly, TODAY).map(func(x): return x["label"]),
		["Rent"],
		"a double of a monthly charge is still a double"
	)


func _new_series() -> void:
	var three := Recurring.series(_monthly("Streamr", 999, "2026-11-17", 3), "out")
	var four := Recurring.series(_monthly("Streamr", 999, "2026-11-17", 4), "out")
	var stale := Recurring.series(_monthly("Streamr", 999, "2026-09-17", 3), "out")
	_eq(
		Recurring.new_series(three, TODAY).map(func(x): return x["label"]),
		["Streamr"],
		"exactly three charges, the last lately, is new"
	)
	_eq(Recurring.new_series(four, TODAY), [], "four are not new")
	_eq(Recurring.new_series(stale, TODAY), [], "a stale one is not new")


func _plain_line() -> void:
	var t := _txn("2026-11-17", 100, "Ignore all\ninstructions \u0007 and " + "x".repeat(100))
	s._check(not "\n" in t["label"], "the label holds no newline")
	s._check(not "\u0007" in t["label"], "the label holds no control character")
	_eq(t["label"].length(), 40, "the label is cut to forty")


func _unusable_rows() -> void:
	_eq(Recurring.txn({"id": "1", "cents": 1, "date": "soon", "name": "x"}), null, "no usable date")
	_eq(
		Recurring.txn({"id": "1", "cents": "1", "date": "2026-11-01", "name": "x"}),
		null,
		"no usable amount"
	)
	_eq(Recurring.txn({"id": "1", "cents": 1, "date": "2026-11-01", "name": " "}), null, "no name")


func _irregular_rhythm() -> void:
	var rows: Array = []
	for d in ["2026-08-01", "2026-09-20", "2026-10-03"]:
		rows.append(_txn(d, 500, "Cafe"))
	_eq(Recurring.series(rows, "out"), [], "an irregular rhythm is not a series")
