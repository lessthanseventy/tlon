extends RefCounted

# Where the checking balance goes in the days ahead, worked out from the transactions kept: pure
# arithmetic, no clock (`today` is always passed in), in cents. A port of the server's
# `Server.Home.Bank.Projection`; the rules are the same but for everyday spending's median week
# and the rent series (`bank_recurring.gd`).
#
# `data` is {"transactions": [txn], "accounts": [account]}. What is handed in is a magnitude (the
# cost of a purchase, the new size of a series); what comes back is the effect on the balance: money
# out negative, money in positive. Events start tomorrow, the horizon is capped at 180 days, and
# only live series count. An expected charge or deposit not posted by today stays on tomorrow as
# overdue for a grace of half its rhythm (a yearly one 30 days), then is skipped and named.
# Everyday spending is what is in no series: the posted outflows of the spendable accounts over the
# last 90 days. The expected daily figure is the median week of them over seven (their mean with
# under three weeks of history), so a few lumps (cash, a transfer to someone) do not spread over
# every day; `mean_daily_cents` is the plain average and `occasional_daily_cents` what it is above
# the expected. The low and high lines are the 25th and 75th percentile (nearest rank) of rolling
# 30-day totals, never above or below the expected, equal to it under 30 days of history.

const Recurring := preload("res://bank_recurring.gd")
const U := preload("res://bank_util.gd")

const CAP := 180
const WINDOW := 90
const LABELS := 60
const MONTH := 30
const WEEK := 7
const AFFORD_DAYS := 60
const CUSHION_DAYS := 7


# The balance day by day from `today` to `until` (clamped to 180 days ahead, saying so in
# `clamped`); {"error": "no_data"} with no accounts, no transactions or no spendable account.
static func forecast(data: Dictionary, today: String, until: String) -> Dictionary:
	var c := _context(data, today)
	if c.has("error"):
		return c
	var ctx: Dictionary = c["ok"]
	return {"ok": _build(ctx, today, until, _items(ctx, today))}


# Whether a purchase of `amount_cents` on `on` (null: today) is covered: the forecast with and
# without it, to the later of 60 days and the second next deposit. `opts` may hold "cushion_cents".
static func afford(
	data: Dictionary, today: String, amount_cents: Variant, on: Variant, opts: Dictionary = {}
) -> Dictionary:
	if not amount_cents is int or amount_cents <= 0:
		return {"error": "bad_amount"}
	var on_date: String = on if on != null else today
	if on_date > U.add(today, CAP):
		return {"error": "beyond_horizon"}
	var c := _context(data, today)
	if c.has("error"):
		return c
	var ctx: Dictionary = c["ok"]
	var base := _items(ctx, today)
	var until: String = U.max_date(
		U.max_date(U.add(today, AFFORD_DAYS), _second_deposit(base, today)), on_date
	)
	var purchase := _user_item("Purchase", -amount_cents, "once", on_date, today)
	var without := _build(ctx, today, until, base)
	var with := _build(ctx, today, until, [purchase] + base)
	var every: Dictionary = ctx["everyday"]
	var cushion: int = opts.get("cushion_cents", CUSHION_DAYS * every["expected_daily_cents"])
	var short := _shortfall(with["days"])
	var baseline := _shortfall(without["days"])
	var other: Dictionary = ctx["other"]
	var low_expected: int = _lowest_day(with["days"])["expected_cents"]
	var low_line: int = _min_of(with["days"].map(func(d): return d["low_cents"]))
	return {
		"ok":
		{
			"verdict": _verdict(low_expected, cushion),
			"worst_case": _verdict(low_line, cushion),
			"with": with,
			"without": without,
			"shortfall_cents": short[1],
			"short_on": short[0],
			"short_without": baseline[1] != null,
			"baseline_shortfall_cents": baseline[1],
			"baseline_short_on": baseline[0],
			"adds_cents": null if baseline[1] == null else short[1] - baseline[1],
			"other_available_cents": other["cents"],
			"other_accounts": other["names"],
			"covered_by_other": _covered_by_other(with, short[1], cushion, other["cents"]),
			"cushion_cents": cushion,
		}
	}


# The forecast to `until` as it is and with `changes` made (one_off, recurring, drop, change; see
# the spec). An unknown series is {"error": "no_series", "name", "suggestions"}.
static func what_if(data: Dictionary, today: String, changes: Array, until: String) -> Dictionary:
	var cap := U.add(today, CAP)
	var horizon := U.min_date(until, cap)
	var c := _context(data, today)
	if c.has("error"):
		return c
	var ctx: Dictionary = c["ok"]
	var base := _items(ctx, today)
	var applied := _apply_changes(base, changes, today, horizon, cap)
	if applied.has("error"):
		return applied
	var baseline := _build(ctx, today, until, base)
	var changed := _build(ctx, today, until, applied["ok"])
	var changed_days: Array = changed["days"]
	var baseline_days: Array = baseline["days"]
	return {
		"ok":
		{
			"clamped": baseline["clamped"],
			"baseline": baseline,
			"changed": changed,
			"difference":
			{
				"end_cents":
				changed_days[-1]["expected_cents"] - baseline_days[-1]["expected_cents"],
				"lowest_cents":
				changed["lowest"]["balance_cents"] - baseline["lowest"]["balance_cents"],
			},
		}
	}


# What went out and came in by calendar month from query "from" through "to", for the posted
# transactions whose merchant or name contains "match" (null: all; an array: any of its strings).
# {"error": "bad_range"} when "from" is after "to".
static func history(data: Dictionary, query: Dictionary) -> Dictionary:
	if query["from"] > query["to"]:
		return {"error": "bad_range"}
	return _months_of(data, query)


# The distinct merchant labels of the posted transactions of the last 90 days up to `today`, the
# most frequent first, at most 60, each at most 40 characters.
static func merchants(data: Dictionary, today: String) -> Array:
	var from := U.add(today, 1 - WINDOW)
	var rows := Recurring.without_transfers(data["transactions"]).filter(
		func(t): return not t["pending"] and t["date"] >= from and t["date"] <= today
	)
	var groups := U.group_by(rows, func(t): return t["key"])
	var listed: Array = []
	for k in groups:
		listed.append([k, groups[k]])
	listed = U.sort_by(listed, func(g): return [-g[1].size(), g[0]])
	var out: Array = []
	for g in listed.slice(0, LABELS):
		out.append(Recurring.line(g[1][0]["label"], 40))
	return out


# The live recurring outflow series for display, by next date: amounts are signed, "was_cents"
# the price before a change.
static func subscriptions(data: Dictionary, today: String) -> Array:
	var live := Recurring.live(
		Recurring.series(Recurring.without_transfers(data["transactions"]), "out"), today
	)
	var out: Array = []
	for s in live:
		var item := _series_item(s, "charge", -1, today)
		(
			out
			. append(
				{
					"name": s["label"],
					"amount_cents": -s["amount"],
					"rhythm": s["period"],
					"next": _first_date(item),
					"count": s["count"],
					"was_cents": null if s["was"] == null else -s["was"],
				}
			)
		)
	return U.sort_by(out, func(s): return [s["next"], s["name"]])


# What is safe to spend a day until the next deposit and where the money went. The day's figure is
# what is spare at the start of today (available, with today's everyday outflow given back, less
# the bills before the deposit and a day of expected everyday spending as cushion) over the days
# until it; `short_cents` is how far below nothing that is. Today's spend and the weeks (this one
# from Monday, and the last) are the everyday outflows, pending ones too, a week's top 4 merchants
# by amount. No deposit seen: `until` and the daily figure are null.
static func budget(data: Dictionary, today: String) -> Dictionary:
	var c := _context(data, today)
	if c.has("error"):
		return c
	var ctx: Dictionary = c["ok"]
	var items := _items(ctx, today)
	var deposit: Variant = _next_deposit(items)
	var bills_keys := {}
	for s in ctx["out"]:
		bills_keys[s["key"]] = true
	var spends: Array = ctx["txns"].filter(
		func(t): return t["cents"] > 0 and not bills_keys.has(t["key"]) and t["date"] <= today
	)
	var spent := U.sum(
		spends.filter(func(t): return t["date"] == today).map(func(t): return t["cents"])
	)
	var monday := U.add(today, -posmod(U.weekday(today) - 1, 7))
	var weeks := [_week(spends, monday, today), _week(spends, U.add(monday, -7), U.add(monday, -1))]
	var other: Dictionary = ctx["other"]
	var out := {
		"until": null,
		"deposit": null,
		"days": null,
		"bills_cents": 0,
		"bills": [],
		"cushion_cents": ctx["everyday"]["expected_daily_cents"],
		"safe_daily_cents": null,
		"short_cents": 0,
		"spent_today_cents": spent,
		"weeks": weeks,
		"other_available_cents": other["cents"],
		"other_accounts": other["names"],
	}
	if deposit == null:
		return {"ok": out}
	var until: String = deposit["date"]
	var charges := _events(items, until).filter(
		func(e): return e["kind"] == "charge" and e["date"] < until
	)
	var bills := -U.sum(charges.map(func(e): return e["amount_cents"]))
	var days := maxi(U.diff(until, today), 1)
	var spare: int = ctx["start"] + spent - bills - out["cushion_cents"]
	out["until"] = until
	out["deposit"] = deposit["name"]
	out["days"] = days
	out["bills_cents"] = bills
	out["bills"] = charges.map(
		func(e): return {"name": e["name"], "on": e["date"], "amount_cents": -e["amount_cents"]}
	)
	out["safe_daily_cents"] = maxi(spare, 0) / days
	out["short_cents"] = maxi(-spare, 0)
	return {"ok": out}


static func _week(spends: Array, from: String, to: String) -> Dictionary:
	var rows := spends.filter(func(t): return t["date"] >= from and t["date"] <= to)
	var groups := U.group_by(rows, func(t): return t["key"])
	var top: Array = []
	for k in groups:
		var g: Array = groups[k]
		top.append(
			{"name": g[0]["label"], "amount_cents": U.sum(g.map(func(t): return t["cents"]))}
		)
	top = U.sort_by(top, func(m): return [-m["amount_cents"], m["name"]])
	return {
		"from": from,
		"to": to,
		"total_cents": U.sum(rows.map(func(t): return t["cents"])),
		"top": top.slice(0, 4),
	}


static func _min_of(values: Array) -> int:
	var low: int = values[0]
	for v in values:
		low = mini(low, v)
	return low


static func _min_date_of(rows: Array) -> String:
	var low: String = rows[0]["date"]
	for t in rows:
		low = U.min_date(low, t["date"])
	return low


static func _per(total: int, days: int) -> int:
	return (2 * total + days) / (2 * days)


static func _rank(sorted: Array, percent: int) -> int:
	return sorted[maxi((sorted.size() * percent + 99) / 100, 1) - 1]


static func _needles(matcher: Variant) -> Variant:
	if matcher == null:
		return null
	if matcher is String:
		return [Recurring.key(matcher)]
	var out: Array = []
	for m in matcher:
		var k: String = Recurring.key(m)
		if k != "":
			out.append(k)
	return out


static func _contains(key: String, needles: Variant) -> bool:
	if needles == null:
		return true
	for n in needles:
		if key.contains(n):
			return true
	return false


static func _split_out(rows: Array) -> Array:
	var out := 0
	var into := 0
	for t in rows:
		if t["cents"] > 0:
			out += t["cents"]
		else:
			into += t["cents"]
	return [-out, -into]


static func _counted(rows: Array) -> Array:
	var groups := U.group_by(rows, func(t): return t["key"])
	var out: Array = []
	for k in groups:
		var group: Array = groups[k]
		var parts := _split_out(group)
		(
			out
			. append(
				{
					"name": group[0]["label"],
					"out_cents": parts[0],
					"in_cents": parts[1],
					"count": group.size(),
				}
			)
		)
	out = U.sort_by(out, func(m): return [-(absi(m["out_cents"]) + m["in_cents"]), m["name"]])
	return out.slice(0, 8)


static func _month(first: String, rows: Array) -> Dictionary:
	var parts := _split_out(rows)
	return {
		"month": U.month_key(first),
		"out_cents": parts[0],
		"in_cents": parts[1],
		"count": rows.size(),
	}


static func _months_of(data: Dictionary, query: Dictionary) -> Dictionary:
	var needle: Variant = _needles(query["match"])
	var from: String = query["from"]
	var to: String = query["to"]
	var rows := Recurring.without_transfers(data["transactions"]).filter(
		func(t):
			return (
				not t["pending"]
				and t["date"] >= from
				and t["date"] <= to
				and _contains(t["key"], needle)
			)
	)
	var by_month := U.group_by(rows, func(t): return U.month_start(t["date"]))
	var entries: Array = []
	var first := U.month_start(from)
	while first <= to:
		entries.append(_month(first, by_month.get(first, [])))
		first = U.shift_months(first, 1)
	var largest := (
		U
		. sort_by(rows, func(t): return absi(t["cents"]), true)
		. slice(0, 5)
		. map(func(t): return {"date": t["date"], "name": t["label"], "amount_cents": -t["cents"]})
	)
	var out_sum := 0
	var in_sum := 0
	for e in entries:
		out_sum += e["out_cents"]
		in_sum += e["in_cents"]
	return {
		"ok":
		{
			"months": entries,
			"count": rows.size(),
			"merchants": _counted(rows) if needle != null else [],
			"largest": largest,
			"average_out_cents": -_per(-out_sum, entries.size()),
			"average_in_cents": _per(in_sum, entries.size()),
		}
	}


static func _context(data: Dictionary, today: String) -> Dictionary:
	var txns: Array = data.get("transactions", [])
	var accounts: Array = data.get("accounts", [])
	if txns.is_empty() or accounts.is_empty():
		return {"error": "no_data"}
	var start: Variant = U.spendable_available(accounts)
	if start == null:
		return {"error": "no_data"}
	var ids: Array = []
	for a in accounts:
		if U.spendable(a):
			ids.append(a.get("id"))
	var mine := Recurring.without_transfers(txns).filter(func(t): return t["account_id"] in ids)
	var out := Recurring.live(Recurring.series(mine, "out"), today)
	var deposits := Recurring.live(Recurring.series(mine, "in"), today)
	return {
		"ok":
		{
			"start": int(start),
			"other": U.other_available(accounts),
			"out": out,
			"deposits": deposits,
			"everyday": _everyday(mine, out, today),
			"pending": txns.any(func(t): return t["pending"]),
			"txns": mine,
			"months": _months_of_history(mine, today),
		}
	}


static func _months_of_history(mine: Array, today: String) -> int:
	if mine.is_empty():
		return 0
	return U.diff(today, _min_date_of(mine)) / MONTH


static func _history_days(posted: Array, today: String) -> int:
	if posted.is_empty():
		return 0
	return mini(U.diff(today, _min_date_of(posted)) + 1, WINDOW)


static func _everyday(mine: Array, out: Array, today: String) -> Dictionary:
	var keys := {}
	for s in out:
		keys[s["key"]] = true
	var posted := mine.filter(func(t): return not t["pending"] and t["date"] <= today)
	var span := _history_days(posted, today)
	var from := U.add(today, 1 - span)
	var totals := {}
	for t in posted:
		if t["cents"] > 0 and not keys.has(t["key"]) and t["date"] >= from:
			totals[t["date"]] = int(totals.get(t["date"], 0)) + int(t["cents"])
	var per_day: Array = []
	for i in span:
		per_day.append(int(totals.get(U.add(today, -i), 0)))
	var mean := _per(U.sum(per_day), maxi(span, 1))
	var expected := mean
	if span >= 3 * WEEK:
		var weeks: Array = []
		for w in span / WEEK:
			weeks.append(U.sum(per_day.slice(w * WEEK, (w + 1) * WEEK)))
		weeks.sort()
		var mid: int = weeks.size() / 2
		var week: int = (
			weeks[mid] if weeks.size() % 2 == 1 else (weeks[mid - 1] + weeks[mid] + 1) / 2
		)
		expected = _per(week, WEEK)
	var low := expected
	var high := expected
	if span >= MONTH:
		var sums: Array = []
		for i in range(0, span - MONTH + 1):
			sums.append(U.sum(per_day.slice(i, i + MONTH)))
		sums.sort()
		low = mini(_per(_rank(sums, 25), MONTH), expected)
		high = maxi(_per(_rank(sums, 75), MONTH), expected)
	return {
		"expected_daily_cents": expected,
		"low_daily_cents": low,
		"high_daily_cents": high,
		"mean_daily_cents": mean,
		"occasional_daily_cents": maxi(mean - expected, 0),
		"history_days": span,
	}


static func _items(ctx: Dictionary, today: String) -> Array:
	var out: Array = []
	for s in ctx["out"]:
		out.append_array(_series_items(ctx, s, "charge", -1, today))
	for s in ctx["deposits"]:
		out.append_array(_series_items(ctx, s, "deposit", 1, today))
	return out


static func _series_items(
	ctx: Dictionary, series: Dictionary, kind: String, sign: int, today: String
) -> Array:
	var normal := _series_item(series, kind, sign, U.add(today, 1))
	if series["next"] > today or _arrived(ctx["txns"], series, sign):
		return [normal]
	if U.diff(today, series["next"]) <= _grace(series["period"]):
		var late := normal.duplicate()
		late["overdue"] = true
		late["anchor"] = normal["from"]
		late["expected_on"] = series["next"]
		return [late, normal]
	var skipped := normal.duplicate()
	skipped["skipped"] = true
	return [skipped]


static func _arrived(txns: Array, series: Dictionary, sign: int) -> bool:
	var since := U.add(series["next"], -Recurring.tolerance(series))
	for t in txns:
		if (
			Recurring.same_merchant(t["key"], series["key"])
			and t["cents"] * sign < 0
			and t["date"] >= since
		):
			return true
	return false


static func _grace(period: String) -> int:
	match period:
		"yearly":
			return 30
		"monthly":
			return 14
		"fortnightly":
			return 7
	return 3


static func _series_item(series: Dictionary, kind: String, sign: int, from: String) -> Dictionary:
	return {
		"name": series["label"],
		"key": series["key"],
		"kind": kind,
		"amount": sign * series["amount"],
		"rhythm": series["period"],
		"anchor": series["last"],
		"from": from,
		"count": series["count"],
		"overdue": false,
		"expected_on": null,
		"skipped": false,
	}


static func _user_item(
	name: String, effect: int, rhythm: String, anchor: String, today: String
) -> Dictionary:
	return {
		"name": name,
		"key": Recurring.key(name),
		"kind": "charge" if effect < 0 else "deposit",
		"amount": effect,
		"rhythm": rhythm,
		"anchor": U.max_date(anchor, today) if rhythm == "once" else anchor,
		"from": today,
		"count": 0,
		"overdue": false,
		"expected_on": null,
		"skipped": false,
	}


static func _shift(date: String, rhythm: String, k: int) -> String:
	match rhythm:
		"weekly":
			return U.add(date, 7 * k)
		"fortnightly":
			return U.add(date, 14 * k)
		"monthly":
			return U.shift_months(date, k)
	return U.shift_years(date, k)


static func _single(date: String, from: String, until: String) -> Array:
	return [date] if date >= from and date <= until else []


static func _dates(item: Dictionary, until: String) -> Array:
	if item["rhythm"] == "once" or item["overdue"]:
		return _single(item["anchor"], item["from"], until)
	var out: Array = []
	var k := 0
	while true:
		var d := _shift(item["anchor"], item["rhythm"], k)
		k += 1
		if d < item["from"]:
			continue
		if d > until:
			break
		out.append(d)
	return out


static func _first_date(item: Dictionary) -> String:
	if item["overdue"]:
		return item["anchor"]
	var k := 0
	while true:
		var d := _shift(item["anchor"], item["rhythm"], k)
		if d >= item["from"]:
			return d
		k += 1
	return ""


static func _events(items: Array, until: String) -> Array:
	var out: Array = []
	for item in items:
		for date in _dates(item, until):
			(
				out
				. append(
					{
						"date": date,
						"amount_cents": item["amount"],
						"name": item["name"],
						"kind": item["kind"],
						"rhythm": item["rhythm"],
						"count": item["count"],
						"overdue": item["overdue"],
						"expected_on": item["expected_on"],
					}
				)
			)
	return U.sort_by(out, func(e): return [e["date"], e["amount_cents"], e["name"]])


static func _next_deposit(items: Array) -> Variant:
	var best: Variant = null
	for item in items:
		if item["kind"] == "deposit" and item["rhythm"] != "once":
			var date := _first_date(item)
			if best == null or date < best["date"]:
				best = {"name": item["name"], "date": date, "overdue": item["overdue"]}
	return best


static func _second_deposit(items: Array, today: String) -> String:
	var cap := U.add(today, CAP)
	var deposits := items.filter(func(i): return i["kind"] == "deposit")
	var evs := _events(deposits, cap)
	return evs[1]["date"] if evs.size() > 1 else cap


static func _lowest_day(days: Array) -> Dictionary:
	var best: Dictionary = days[0]
	for d in days:
		if d["expected_cents"] < best["expected_cents"]:
			best = d
	return best


static func _lowest(days: Array) -> Dictionary:
	var day := _lowest_day(days)
	return {"date": day["date"], "balance_cents": day["expected_cents"]}


static func _build(ctx: Dictionary, today: String, until_in: String, items: Array) -> Dictionary:
	var cap := U.add(today, CAP)
	var clamped := until_in > cap
	var until := cap if clamped else until_in
	if until < today:
		until = today
	var evs := _events(items, until)
	var effects := {}
	for e in evs:
		effects[e["date"]] = int(effects.get(e["date"], 0)) + int(e["amount_cents"])
	var every: Dictionary = ctx["everyday"]
	var days: Array = []
	var running: int = ctx["start"]
	for i in U.diff(until, today) + 1:
		var date := U.add(today, i)
		running += int(effects.get(date, 0))
		(
			days
			. append(
				{
					"date": date,
					"low_cents": running - i * every["high_daily_cents"],
					"expected_cents": running - i * every["expected_daily_cents"],
					"high_cents": running - i * every["low_daily_cents"],
				}
			)
		)
	var deposit: Variant = _next_deposit(items)
	var skipped: Array = []
	for item in items:
		if item["skipped"]:
			skipped.append(item["name"])
	var before: Variant = null
	if deposit != null:
		before = _lowest(days.filter(func(d): return d["date"] < deposit["date"]))
	var caveats: Array = []
	if ctx["pending"]:
		caveats.append("pending_ignored")
	if every["history_days"] < MONTH:
		caveats.append("short_history")
	if not skipped.is_empty():
		caveats.append("skipped_charge")
	if deposit == null:
		caveats.append("no_deposit_seen")
	caveats.append("one_off_bills_unknown")
	var other: Dictionary = ctx["other"]
	return {
		"start_cents": ctx["start"],
		"other_available_cents": other["cents"],
		"other_accounts": other["names"],
		"until": until,
		"clamped": clamped,
		"events": evs,
		"everyday": every,
		"days": days,
		"lowest": _lowest(days),
		"before_next_deposit": before,
		"basis":
		{
			"months_of_history": ctx["months"],
			"series": ctx["out"].size() + ctx["deposits"].size(),
			"next_deposit": deposit,
			"skipped": skipped,
			"caveats": caveats,
		},
	}


static func _covered_by_other(
	with: Dictionary, shortfall: Variant, cushion: int, other: int
) -> Variant:
	var low: int = _lowest_day(with["days"])["expected_cents"]
	match _verdict(low, cushion):
		"covers":
			return null
		"tight":
			return low + other >= cushion
	return other >= shortfall


static func _verdict(low: int, cushion: int) -> String:
	if low >= cushion:
		return "covers"
	return "tight" if low >= 0 else "short"


# [first day below zero, the shortfall at the lowest point], or [null, null]
static func _shortfall(days: Array) -> Array:
	for d in days:
		if d["expected_cents"] < 0:
			return [d["date"], -_min_of(days.map(func(x): return x["expected_cents"]))]
	return [null, null]


static func _apply_changes(
	items: Array, changes: Array, today: String, horizon: String, cap: String
) -> Dictionary:
	var current := items
	for change in changes:
		var bad: Variant = _checked(change, horizon, cap)
		if bad != null:
			return bad
		var applied: Variant = _apply_change(current, change, today)
		if applied is Dictionary:
			return applied
		current = applied
	return {"ok": current}


static func _within(date: String, limit: String) -> Variant:
	return {"error": "beyond_horizon"} if date > limit else null


static func _checked(change: Dictionary, horizon: String, cap: String) -> Variant:
	var cost: Variant = change.get("cost")
	match change["kind"]:
		"one_off":
			if not cost is int or cost == 0:
				return {"error": "bad_amount"}
			return _within(change["on"], horizon)
		"recurring":
			if not cost is int or cost <= 0:
				return {"error": "bad_amount"}
			return _within(change["from"], cap)
		"change":
			if not cost is int or cost <= 0:
				return {"error": "bad_amount"}
	return null


# the items after the change, or an {"error": ..} dictionary
static func _apply_change(items: Array, change: Dictionary, today: String) -> Variant:
	match change["kind"]:
		"one_off":
			return (
				[_user_item(change["name"], -change["cost"], "once", change["on"], today)] + items
			)
		"recurring":
			return (
				[
					_user_item(
						change["name"], -change["cost"], change["rhythm"], change["from"], today
					)
				]
				+ items
			)
	var found := _series_key(items, change["name"])
	if found.has("error"):
		return found
	var key: String = found["ok"]
	if change["kind"] == "drop":
		return items.filter(func(i): return i["key"] != key)
	var out: Array = []
	for item in items:
		if item["key"] == key:
			var resized: Dictionary = item.duplicate()
			resized["amount"] = -change["cost"] if item["amount"] < 0 else change["cost"]
			out.append(resized)
		else:
			out.append(item)
	return out


static func _series_key(items: Array, name: String) -> Dictionary:
	var key: String = Recurring.key(name)
	for i in items:
		if i["key"] == key:
			return {"ok": key}
	return {"error": "no_series", "name": name, "suggestions": _suggestions(items, key)}


static func _suggestions(items: Array, key: String) -> Array:
	var scored: Array = []
	for i in U.uniq_by(items, func(i): return i["key"]):
		var score := _jaro(i["key"], key)
		if score >= 0.6:
			scored.append([score, i["name"]])
	var names: Array = []
	for s in U.sort_by(scored, func(s): return s, true).slice(0, 3):
		names.append(s[1])
	return names


# Elixir's String.jaro_distance (Erlang's string:jaro_similarity): matches within half the longer
# length, a character matched at most once, the nearest unused one first.
static func _jaro(a: String, b: String) -> float:
	if a == b:
		return 1.0
	var alen := a.length()
	var blen := b.length()
	if alen == 0 or blen == 0:
		return 0.0
	var slots := {}
	for j in blen:
		if not slots.has(b[j]):
			slots[b[j]] = []
		slots[b[j]].append(j)
	var dist := maxi(1, maxi(alen, blen) / 2)
	var a_matched: Array = []
	var b_matched: Array = []
	for i in alen:
		var at: Array = slots.get(a[i], [])
		for n in at.size():
			var j: int = at[n]
			if j >= i + dist:
				break
			if j > i - dist:
				at.remove_at(n)
				a_matched.append(a[i])
				b_matched.append([j, b[j]])
				break
	var m := a_matched.size()
	if m == 0:
		return 0.0
	b_matched = U.sort_by(b_matched, func(p): return p[0])
	var t := 0
	for k in m:
		if a_matched[k] != b_matched[k][1]:
			t += 1
	return (float(m) / alen + float(m) / blen + (m - t / 2.0) / m) / 3
