extends RefCounted

# The list's own sources of Your move: a waiting-on past its date, and a to-do open for STALE_DAYS.
# Pure over a status as `LocalList.status()` answers it; the stamps are ISO UTC, so they compare as
# strings. A to-do's age is its `since`: the list keeps no later touch.
const STALE_DAYS := 14
const WEEKDAYS := ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]


# `now` and `stale` are ISO stamps: the present, and the present less STALE_DAYS.
static func sources(status: Dictionary, now: String, stale: String) -> Array:
	var out: Array = []
	for w in status.get("waiting", []):
		if str(w.get("due_at", "")) != "" and str(w["due_at"]) < now:
			out.append(_nudge(w))
	for t in status.get("open", []):
		if t.get("kind") == "todo" and str(t.get("since", "")) != "" and str(t["since"]) < stale:
			out.append(_someday(t))
	return out


static func _day(stamp: String) -> Dictionary:
	return Time.get_datetime_dict_from_unix_time(
		int(Time.get_unix_time_from_datetime_string(stamp.trim_suffix("Z")))
	)


static func _nudge(w: Dictionary) -> Dictionary:
	var text := "Nudge %s about %s" % [w["who"], w["text"]]
	return {
		"key": "waiting-%d" % int(w["id"]),
		"kind": "proposal",
		"source": "list",
		"text": text,
		"why": "waiting since %s" % WEEKDAYS[_day(str(w["since"]))["weekday"]],
		"action": {"do": "add", "kind": "todo", "text": text},
		"date": str(w["due_at"]).substr(0, 10)
	}


static func _someday(t: Dictionary) -> Dictionary:
	var d := _day(str(t["since"]))
	return {
		"key": "stale-%d" % int(t["id"]),
		"kind": "proposal",
		"source": "list",
		"text": 'Put "%s" on someday' % t["text"],
		"why": "open since %d %s, never moved" % [d["day"], MONTHS[d["month"] - 1]],
		"action": {"do": "someday", "id": int(t["id"])},
		"date": str(t["since"]).substr(0, 10)
	}
