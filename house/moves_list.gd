extends RefCounted

# The list's own sources of Your move: a waiting-on past its date, and a to-do open for STALE_DAYS.
# Pure over a status as `LocalList.status()` answers it; the stamps are ISO UTC, so they compare as
# strings. A to-do's age is its `since`: the list keeps no later touch. `bias` is the list's offset
# from UTC, so a `why` names the person's day, not UTC's.
const Money := preload("res://money.gd")
const STALE_DAYS := 14
const WEEKDAYS := ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]


# `now` and `stale` are ISO stamps: the present, and the present less STALE_DAYS.
static func sources(status: Dictionary, now: String, stale: String, bias: float = 0.0) -> Array:
	var out: Array = []
	for w in status.get("waiting", []):
		if str(w.get("due_at", "")) != "" and str(w["due_at"]) < now:
			out.append(_nudge(w, bias))
	for t in status.get("open", []):
		if t.get("kind") == "todo" and str(t.get("since", "")) != "" and str(t["since"]) < stale:
			out.append(_someday(t, bias))
	return out


# The one move money being short makes: `budget` is `bank.budget()`'s `ok`. It is the source's word
# that this is urgent, and keyed by the deposit so it is offered once for each.
static func money_short(budget: Dictionary) -> Array:
	var short := roundi(float(budget.get("short_cents", 0)))
	if short <= 0 or budget.get("until") == null:
		return []
	var text := "Cover the %s shortfall before %s" % [Money.fmt_whole(short), budget["until"]]
	return [
		{
			"key": "money-short-%s" % budget["until"],
			"kind": "proposal",
			"source": "money",
			"text": text,
			"why": "spare cash runs out before the %s deposit" % budget["deposit"],
			"action": {"do": "add", "kind": "todo", "text": text},
			"date": str(budget["until"]),
			"urgent": true
		}
	]


static func _day(stamp: String, bias: float) -> Dictionary:
	return Time.get_datetime_dict_from_unix_time(
		int(Time.get_unix_time_from_datetime_string(stamp.trim_suffix("Z")) + bias)
	)


static func _nudge(w: Dictionary, bias: float) -> Dictionary:
	var who := str(w.get("who", "")).strip_edges() if w.get("who") != null else ""
	var text := (
		"Nudge %s about %s" % [who, w["text"]] if who != "" else "Follow up on %s" % w["text"]
	)
	return {
		"key": "waiting-%d" % int(w["id"]),
		"kind": "proposal",
		"source": "list",
		"text": text,
		"why": "waiting since %s" % WEEKDAYS[_day(str(w["since"]), bias)["weekday"]],
		"action": {"do": "add", "kind": "todo", "text": text},
		"date": str(w["due_at"]).substr(0, 10)
	}


static func _someday(t: Dictionary, bias: float) -> Dictionary:
	var d := _day(str(t["since"]), bias)
	return {
		"key": "stale-%d" % int(t["id"]),
		"kind": "proposal",
		"source": "list",
		"text": 'Put "%s" on someday' % t["text"],
		"why": "open since %d %s, never moved" % [d["day"], MONTHS[d["month"] - 1]],
		"action": {"do": "someday", "id": int(t["id"])},
		"date": str(t["since"]).substr(0, 10)
	}
