extends RefCounted

# What a list of bank transactions says about the days ahead, in plain arithmetic: the steady
# charges and deposits (series) and what follows from them. A transaction's `cents` is as Plaid
# gives it: positive is money out, negative money in.
#
# A series is one merchant (its normalised key) with at least three posted charges (a yearly one
# two) at a steady rhythm, the latest run of them: the gaps all within one of weekly (5 to 9 days),
# fortnightly (11 to 17), monthly (26 to 34) or yearly (355 to 375). The series' `amount` is the
# median of the latest three charges (the latest six for a deposit), the run stops at a charge
# more than twice or less than half of that that falls on the rhythm, and `count` is the whole
# run. A lone far charge off the rhythm (or far from both neighbours when those agree) is passed
# over and not counted; the newest charge is passed over only off the rhythm. `was` is the amount
# of an older run at another amount, `at_amount` how many of the latest charges are at the current
# one (within 10%). A merchant whose charges fall into two or more steady amount groups that hold
# four fifths of its charges, and whose latest charges are within one rhythm of each other, has
# those series. A merchant with ten or more charges in no steady rhythm and more than twice as
# many as its series holds is everyday spending and has none. Pending transactions never count;
# several on one day count once.
#
# A series is live while its latest charge is within two rhythms plus the rhythm's tolerance of
# today (a yearly one: one rhythm plus 30 days).

const U := preload("res://bank_util.gd")

const BANDS := [
	["weekly", 5, 9], ["fortnightly", 11, 17], ["monthly", 26, 34], ["yearly", 355, 375]
]
const LABEL_MAX := 40


# a stored row {id, account_id, cents, date, name, merchant, pending} as a transaction, null when
# its id, amount, date or label is not usable
static func txn(row: Dictionary) -> Variant:
	var id: Variant = row.get("id")
	var cents: Variant = row.get("cents")
	var date: Variant = row.get("date")
	if not id is String:
		return null
	if cents is float and cents == floorf(cents):
		cents = int(cents)
	if not cents is int:
		return null
	if not U.valid(date):
		return null
	var label := _label(row.get("merchant"), row.get("name"))
	if label == "":
		return null
	return {
		"id": id,
		"account_id": row.get("account_id"),
		"cents": cents,
		"date": date,
		"key": key(label),
		"label": label,
		"pending": row.get("pending") == true,
	}


# the normalised form of a merchant name that series are matched on: lower case, letters and
# digits in single-space runs
static func key(label: String) -> String:
	var re := RegEx.create_from_string("[^\\p{L}\\p{N}]+")
	return re.sub(label.to_lower(), " ", true).strip_edges()


static func _label(merchant: Variant, name: Variant) -> String:
	for v in [merchant, name]:
		if v is String and v.strip_edges() != "":
			return line(v, LABEL_MAX)
	return line("", LABEL_MAX)


static func line(text: Variant, max_len: int) -> String:
	return U.line(text, max_len)


# the series among `txns` in the direction "out" (charges) or "in" (deposits)
static func series(txns: Array, direction: String) -> Array:
	var kept := txns.filter(func(t): return not t["pending"] and _direction(t, direction))
	var groups := U.group_by(kept, func(t): return t["key"])
	var out: Array = []
	for k in groups:
		out.append_array(_key_series(groups[k], direction))
	return U.sort_by(out, func(s): return [s["next"], s["key"]])


static func _direction(t: Dictionary, direction: String) -> bool:
	return t["cents"] > 0 if direction == "out" else t["cents"] < 0


static func _band(gap: int) -> Variant:
	for b in BANDS:
		if gap >= b[1] and gap <= b[2]:
			return b
	return null


static func _close(a: int, b: int) -> bool:
	return absi(a - b) * 10 <= b


static func _next(date: String, period: String) -> String:
	match period:
		"weekly":
			return U.add(date, 7)
		"fortnightly":
			return U.add(date, 14)
		"monthly":
			return U.shift_months(date, 1)
		_:
			return U.shift_years(date, 1)


# whether two merchant keys name one merchant: equal, or one the other with more words after it
static func same_merchant(a: String, b: String) -> bool:
	return a == b or a.begins_with(b + " ") or b.begins_with(a + " ")


# the days either side of a series' expected date within which a charge of the merchant counts as
# that one arriving; takes a series or a period
static func tolerance(period_or_series: Variant) -> int:
	var period: String = (
		period_or_series["period"] if period_or_series is Dictionary else period_or_series
	)
	match period:
		"weekly":
			return 2
		"fortnightly":
			return 3
		"monthly":
			return 4
		_:
			return 10


# the series still live on `today`
static func live(series_list: Array, today: String) -> Array:
	return series_list.filter(func(s): return U.diff(today, s["last"]) <= _window(s["period"]))


# the series whose next date falls from `today` through `days` days after it
static func due_within(series_list: Array, today: String, days: int) -> Array:
	return series_list.filter(
		func(s): return s["next"] >= today and U.diff(s["next"], today) <= days
	)


# charges that look doubled: two posted charges of one amount at one merchant within two days of
# each other, the later one in the last three days, and not a habit (three or more of that amount at
# that merchant inside six days); {key, label, cents, account_id, on}
static func doubles(txns: Array, today: String) -> Array:
	var kept := txns.filter(func(t): return not t["pending"] and t["cents"] > 0)
	var groups := U.group_by(kept, func(t): return [t["key"], t["cents"]])
	var out: Array = []
	for k in U.sort_by(groups.keys(), func(k): return k):
		out.append_array(_doubled(U.sort_by(groups[k], func(t): return t["date"]), today))
	return out


static func _doubled(group: Array, today: String) -> Array:
	var out: Array = []
	for i in range(group.size() - 1):
		var a: Dictionary = group[i]
		var b: Dictionary = group[i + 1]
		var gap := U.diff(b["date"], a["date"])
		var since := U.diff(today, b["date"])
		if gap < 0 or gap > 2 or since < 0 or since > 3:
			continue
		var near := 0
		for g in group:
			if absi(U.diff(b["date"], g["date"])) <= 6:
				near += 1
		if near < 3:
			var double := {}
			for k in ["key", "label", "cents", "account_id"]:
				double[k] = b[k]
			double["on"] = b["date"]
			out.append(double)
	return out


# the series that are new: made by just enough charges, the latest within the last ten days, with
# no older steady run at that rhythm behind them
static func new_series(series_list: Array, today: String) -> Array:
	return series_list.filter(
		func(s):
			return _fresh(s, today) and s["count"] == _minimum(s["period"]) and s["was"] == null
	)


# the series that are a price change: just made by enough charges, but with an older steady run at
# another amount (`was`) behind them
static func price_changes(series_list: Array, today: String) -> Array:
	return series_list.filter(
		func(s):
			return _fresh(s, today) and s["at_amount"] == _minimum(s["period"]) and s["was"] != null
	)


# `txns` without the transfers between the item's own accounts: a charge and a deposit of equal and
# opposite amounts on two different accounts within a day of each other
static func without_transfers(txns: Array) -> Array:
	var charges: Array = []
	var deposits: Array = []
	for t in txns:
		(charges if t["cents"] > 0 else deposits).append(t)
	var unpaired_charges: Array = []
	for charge in charges:
		var found := -1
		for i in deposits.size():
			if _mirror(charge, deposits[i]):
				found = i
				break
		if found < 0:
			unpaired_charges.push_front(charge)
		else:
			deposits.remove_at(found)
	return unpaired_charges + deposits


static func _mirror(charge: Dictionary, deposit: Dictionary) -> bool:
	return (
		deposit["cents"] == -charge["cents"]
		and deposit["account_id"] != charge["account_id"]
		and absi(U.diff(charge["date"], deposit["date"])) <= 1
	)


static func _minimum(period: String) -> int:
	return 2 if period == "yearly" else 3


static func _was(at_amount: Array, rest: Array, period: String) -> Variant:
	if rest.is_empty():
		return null
	var older: Dictionary = rest[0]
	var chunk := 0
	for c in rest:
		if not _close(absi(c["cents"]), absi(older["cents"])):
			break
		chunk += 1
	if at_amount.size() >= _minimum(period) and chunk >= _minimum(period):
		return absi(older["cents"])
	return null


static func _fresh(s: Dictionary, today: String) -> bool:
	var d := U.diff(today, s["last"])
	return d >= 0 and d <= 10


static func _window(period: String) -> int:
	match period:
		"yearly":
			return 365 + 30
		"monthly":
			return 2 * 30 + tolerance("monthly")
		"fortnightly":
			return 2 * 14 + tolerance("fortnightly")
		_:
			return 2 * 7 + tolerance("weekly")


static func _key_series(group: Array, direction: String) -> Array:
	var dated := U.sort_by(group, func(t): return t["date"], true)
	var charges := U.uniq_by(dated, func(t): return t["date"])
	var parts: Array = []
	for cluster in _amount_clusters(charges):
		var d: Variant = _detect(cluster, direction)
		if d != null:
			parts.append(d)
	var covered := 0
	for p in parts:
		covered += p["count"]
	var found: Array = []
	if parts.size() >= 2 and covered * 5 >= charges.size() * 4:
		found = parts if _concurrent(parts) else _wrap(_detect(_without_strays(dated), direction))
	else:
		found = _wrap(_detect(_without_strays(dated), direction))
	var explained := 0
	for f in found:
		explained += f["count"]
	var unexplained := _unsteady(charges)
	if unexplained >= 10 and unexplained > 2 * explained:
		return []
	return found


static func _wrap(found: Variant) -> Array:
	return [] if found == null else [found]


static func _unsteady(charges: Array) -> int:
	var steady := {}
	for i in range(charges.size() - 2):
		var ab: Variant = _same_band(charges[i], charges[i + 1])
		var bc: Variant = _same_band(charges[i + 1], charges[i + 2])
		if ab == bc and ab != null:
			steady[i] = true
			steady[i + 1] = true
			steady[i + 2] = true
	return charges.size() - steady.size()


static func _same_band(newer: Dictionary, older: Dictionary) -> Variant:
	var b: Variant = _band(U.diff(newer["date"], older["date"]))
	return null if b == null else b[0]


static func _without_strays(charges: Array) -> Array:
	var kept: Array = []
	var newer: Variant = null
	var i := 0
	while charges.size() - i >= 2:
		var charge: Dictionary = charges[i]
		var older: Dictionary = charges[i + 1]
		var beyond: Variant = charges[i + 2] if i + 2 < charges.size() else null
		if not _stray(newer, charge, older, beyond):
			kept.append(charge)
			newer = charge
		i += 1
	kept.append_array(charges.slice(i))
	return U.uniq_by(kept, func(t): return t["date"])


static func _stray(newer: Variant, charge: Dictionary, older: Dictionary, beyond: Variant) -> bool:
	return (
		_far(charge, older)
		and _far_from_newer(newer, charge, beyond)
		and (_neighbours_agree(newer, older) or not _on_rhythm(newer, charge, older, beyond))
	)


static func _neighbours_agree(newer: Variant, older: Dictionary) -> bool:
	return newer != null and not _far(newer, older)


static func _far_from_newer(newer: Variant, charge: Dictionary, beyond: Variant) -> bool:
	if newer == null:
		return true if beyond == null else _far(charge, beyond)
	return _far(charge, newer)


static func _far(a: Dictionary, b: Dictionary) -> bool:
	return not _comparable(absi(a["cents"]), absi(b["cents"]))


static func _on_rhythm(
	newer: Variant, charge: Dictionary, older: Dictionary, beyond: Variant
) -> bool:
	if newer == null:
		if beyond == null:
			return false
		var b: Variant = _band(U.diff(older["date"], beyond["date"]))
		if b == null:
			return false
		return _in_band(U.diff(charge["date"], older["date"]), b)
	var nb: Variant = _band(U.diff(newer["date"], older["date"]))
	if nb == null:
		return true
	return (
		_in_band(U.diff(newer["date"], charge["date"]), nb)
		and _in_band(U.diff(charge["date"], older["date"]), nb)
	)


static func _in_band(gap: int, b: Array) -> bool:
	return gap >= b[1] and gap <= b[2]


static func _concurrent(parts: Array) -> bool:
	var newest: String = parts[0]["last"]
	for p in parts:
		newest = U.max_date(newest, p["last"])
	for p in parts:
		if U.diff(newest, p["last"]) > _days(p["period"]):
			return false
	return true


static func _days(period: String) -> int:
	match period:
		"weekly":
			return 7
		"fortnightly":
			return 14
		"monthly":
			return 30
		_:
			return 365


static func _amount_clusters(charges: Array) -> Array:
	var ordered := U.sort_by(charges, func(t): return absi(t["cents"]))
	var clusters: Array = []
	for charge in ordered:
		var c := absi(charge["cents"])
		if not clusters.is_empty() and _close(c, clusters[-1]["low"]):
			clusters[-1]["members"].append(charge)
		else:
			clusters.append({"low": c, "members": [charge]})
	clusters.reverse()
	var out: Array = []
	for cl in clusters:
		var members: Array = cl["members"].duplicate()
		members.reverse()
		out.append(U.sort_by(members, func(t): return t["date"], true))
	return out


static func _detect(charges: Array, direction: String) -> Variant:
	if charges.size() < 2:
		return null
	var last: Dictionary = charges[0]
	var previous: Dictionary = charges[1]
	var b: Variant = _band(U.diff(last["date"], previous["date"]))
	if b == null:
		return null
	var period: String = b[0]
	var run := _rhythm_run(charges, b)
	var lvl := _level(run, direction)
	var comparable_run: Array = []
	for c in run:
		if not _comparable(absi(c["cents"]), lvl):
			break
		comparable_run.append(c)
	run = comparable_run
	if run.size() < _minimum(period):
		return null
	var split := 0
	while split < run.size() and _close(absi(run[split]["cents"]), lvl):
		split += 1
	var at_amount := run.slice(0, split)
	var older := run.slice(split)
	return {
		"key": last["key"],
		"label": last["label"],
		"period": period,
		"amount": lvl,
		"last": last["date"],
		"next": _next(last["date"], period),
		"count": run.size(),
		"at_amount": at_amount.size(),
		"was": _was(at_amount, older, period),
		"account_id": last["account_id"],
	}


static func _rhythm_run(charges: Array, b: Array) -> Array:
	var taken: Array = [charges[0]]
	for i in range(1, charges.size()):
		if not _in_band(U.diff(taken[-1]["date"], charges[i]["date"]), b):
			break
		taken.append(charges[i])
	return taken


static func _level(run: Array, direction: String) -> int:
	var recent: Array = run.slice(0, 3 if direction == "out" else 6).map(
		func(c): return absi(c["cents"])
	)
	recent.sort()
	return recent[recent.size() / 2]


static func _comparable(a: int, level: int) -> bool:
	return a * 2 >= level and a <= level * 2
