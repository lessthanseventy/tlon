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


# whole days from the local date `from_iso` to `to_iso` ("YYYY-MM-DD"), negative when it is behind
static func days_between(from_iso: String, to_iso: String) -> int:
	var a := Time.get_unix_time_from_datetime_string(from_iso + "T00:00:00")
	var b := Time.get_unix_time_from_datetime_string(to_iso + "T00:00:00")
	return roundi((b - a) / 86400.0)


static func add_days(date_iso: String, days: int) -> String:
	var at := Time.get_unix_time_from_datetime_string(date_iso + "T00:00:00")
	return Time.get_date_string_from_unix_time(int(at) + days * 86400)


# a date with no time: "today", "tomorrow", the next six days "Sat", later or past "28 Nov"
static func day_word(date_iso: String, today_iso: String) -> String:
	var gap := days_between(today_iso, date_iso)
	if gap == 0:
		return "today"
	if gap == 1:
		return "tomorrow"
	var d := Time.get_datetime_dict_from_unix_time(
		int(Time.get_unix_time_from_datetime_string(date_iso + "T00:00:00"))
	)
	return DAYS[d["weekday"]] if gap > 1 and gap <= 6 else date(d)


# a birthday `days` from today, on local `date_iso` ("YYYY-MM-DD"): "today",
# "tomorrow · Fri 21 Nov", "in 3 days · Mon 23 Nov"
static func birthday(days: int, date_iso: String) -> String:
	if days == 0:
		return "today"
	var d := Time.get_datetime_dict_from_unix_time(
		int(Time.get_unix_time_from_datetime_string(date_iso + "T00:00:00"))
	)
	var day := "%s %s" % [DAYS[d["weekday"]], date(d)]
	return "tomorrow · " + day if days == 1 else "in %d days · %s" % [days, day]
