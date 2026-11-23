extends RefCounted

# The money's sources of Your move, pure over what the bank answers: a proposal to move money from
# savings when the bills before the next deposit outrun what is available, and an ask for each new
# or raised recurring charge. Every amount is worded by `Money.fmt`. The bank stays read-only: go
# only adds a reminder the evening before.
const Money := preload("res://money.gd")
const U := preload("res://bank_util.gd")
const OPTIONS := ["keep it", "remind me to cancel", "it isn't a bill"]
const REMIND_HOUR := 18


# `available` is the spendable accounts' available cents (null: no bank), `budget` the bank's
# budget answer (`{}` without one), `notices` the bank's notices, `today` an ISO date.
static func sources(available: Variant, budget: Dictionary, notices: Array, today: String) -> Array:
	var out: Array = []
	if available is int and budget.get("until") != null:
		out.append_array(_short(available, budget, today))
	for n in notices:
		out.append(_charge(n, today))
	return out


# The bills before the deposit, in order, against what is available: the first one it cannot pay
# names the day, and savings must cover all that is missing or there is nothing to propose.
static func _short(available: int, budget: Dictionary, today: String) -> Array:
	var missing: int = int(budget["bills_cents"]) - available
	if missing <= 0 or missing > int(budget["other_available_cents"]):
		return []
	var left := available
	for bill in budget["bills"]:
		left -= int(bill["amount_cents"])
		if left < 0:
			return [_move(bill, missing, available, today)]
	return []


static func _move(bill: Dictionary, missing: int, available: int, today: String) -> Dictionary:
	var by: String = U.add(str(bill["on"]), -1)
	var remind: String = U.max_date(U.add(by, -1), today)
	var text := "Move %s from savings" % Money.fmt(missing)
	return {
		"key": "short-%s-%s" % [bill["on"], str(bill["name"]).to_lower()],
		"kind": "proposal",
		"source": "money",
		"text": "%s by %s" % [text, U.day_name(by)],
		"why":
		(
			"%s %s is due %s and checking has %s"
			% [
				bill["name"],
				Money.fmt(bill["amount_cents"]),
				U.day_name(bill["on"]),
				Money.fmt(available)
			]
		),
		"action":
		{"do": "add", "kind": "reminder", "text": text, "at": "%sT%02d:00" % [remind, REMIND_HOUR]},
		"date": by,
		"urgent": true
	}


static func _charge(n: Dictionary, today: String) -> Dictionary:
	return {
		"key": n["key"],
		"kind": "ask",
		"source": "money",
		"text": n["text"],
		"why": n["why"],
		"options": OPTIONS,
		"date": today
	}
