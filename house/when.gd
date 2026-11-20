extends RefCounted

# The one way the sidebar words a due time. `at` and `now` are local unix seconds.
const DAYS := ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]


# today "14:00", tomorrow "tomorrow 14:00", the next six days "Sat 14:00", later "28 Nov"; a time
# gone by is `past` and the time today or the weekday ("since Tue", "since 09:00"), a week back
# or more the date. `past` is "" where a time is only a time.
static func text(at: float, now: float, past: String = "since ") -> String:
	var d := Time.get_datetime_dict_from_unix_time(int(at))
	var hm := "%02d:%02d" % [d["hour"], d["minute"]]
	var gap := int(at / 86400.0) - int(now / 86400.0)
	if at < now:
		if gap == 0:
			return past + hm
		return past + (DAYS[d["weekday"]] if gap > -7 else date(d))
	if gap == 0:
		return hm
	if gap == 1:
		return "tomorrow " + hm
	if gap <= 6:
		return "%s %s" % [DAYS[d["weekday"]], hm]
	return date(d)


static func date(d: Dictionary) -> String:
	return "%d %s" % [d["day"], MONTHS[d["month"] - 1]]
