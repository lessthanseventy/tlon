extends RefCounted

# The server's calendar tests (`Server.Calendar.Feed`, Outlook feeds, `Server.Calendar.clean/1`,
# `Server.Home.Day`) as cases of `ics.gd` and `calendar_feed.gd`: UTC instants, recurrences,
# exceptions, zones, busy and cancelled, the day's and the range's rows.
const Ics := preload("res://ics.gd")
const Feed := preload("res://calendar_feed.gd")

var s


func _init(soak) -> void:
	s = soak


func _eq(got: Variant, want: Variant, what: String) -> void:
	s._check(got == want, "%s: got %s, want %s" % [what, str(got), str(want)])


func run() -> void:
	_one_off()
	_zones()
	_series()
	_all_day()
	_status()
	_cleaning()
	_days()


static func _vevent(lines: Array) -> String:
	return "BEGIN:VEVENT\r\n%s\r\nEND:VEVENT\r\n" % "\r\n".join(lines)


static func _ics(events: String, zones: String = "") -> String:
	return (
		"BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//t//t//EN\r\n%s%sEND:VCALENDAR\r\n"
		% [zones, events]
	)


static func _utc(text: String) -> float:
	return Time.get_unix_time_from_datetime_string(text.trim_suffix("Z"))


static func _within(ics: String, from: String, to: String) -> Array:
	return Ics.occurrences(Ics.read(ics), _utc(from), _utc(to))


static func _all(ics: String) -> Array:
	return _within(ics, "2026-01-01T00:00:00", "2027-01-01T00:00:00")


static func _at(m: Dictionary, key: String = "start") -> String:
	return Time.get_datetime_string_from_unix_time(int(m[key])) + "Z"


func _starts(ms: Array) -> Array:
	return ms.map(func(m): return _at(m))


func _one_off() -> void:
	var feed := _ics(
		_vevent(
			[
				"UID:a@x",
				"DTSTART:20261008T160000Z",
				"DTEND:20261008T163000Z",
				"SUMMARY:Standup\\, daily",
				"DESCRIPTION:Join: https://meet.google.com/abc-defg-hij\\nor dial in"
			]
		)
	)
	var ms := _within(feed, "2026-10-08T00:00:00", "2026-10-09T00:00:00")
	_eq(ms.size(), 1, "a one-off in UTC")
	_eq(
		[ms[0]["uid"], ms[0]["title"], _at(ms[0]), _at(ms[0], "stop"), ms[0]["link"]],
		[
			"a@x",
			"Standup, daily",
			"2026-10-08T16:00:00Z",
			"2026-10-08T16:30:00Z",
			"https://meet.google.com/abc-defg-hij"
		],
		"its title unescaped, its end and the Meet link out of the description"
	)
	var zoom := _ics(
		_vevent(
			[
				"UID:tz@x",
				"DTSTART;TZID=America/Denver:20261008T090000",
				"DTEND;TZID=America/Denver:20261008T093000",
				"SUMMARY:Planning",
				"LOCATION:https://us02web.zoom.us/j/123456789"
			]
		)
	)
	ms = _within(zoom, "2026-10-08T00:00:00", "2026-10-09T00:00:00")
	_eq(
		[_at(ms[0]), ms[0]["link"]],
		["2026-10-08T15:00:00Z", "https://us02web.zoom.us/j/123456789"],
		"a meeting in Denver in October is at UTC-6, the Zoom link from its location"
	)
	var dur := _ics(
		_vevent(["UID:dur@x", "DTSTART:20261008T160000Z", "DURATION:PT1H15M", "SUMMARY:Review"])
	)
	_eq(
		_at(_all(dur)[0], "stop"),
		"2026-10-08T17:15:00Z",
		"a DURATION instead of an end lasts that long"
	)
	_eq(
		Ics.occurrences(Ics.read("<html>not a calendar</html>"), 0.0, 1.0e10),
		[],
		"a feed that is not one is no meetings"
	)
	var alarm := _ics(
		_vevent(
			[
				"UID:v@x",
				"DTSTART:20261008T160000Z",
				"DTEND:20261008T163000Z",
				"SUMMARY:Real",
				"BEGIN:VALARM",
				"SUMMARY:alarm text",
				"END:VALARM"
			]
		)
	)
	_eq(
		_all(alarm).map(func(m): return m["title"]),
		["Real"],
		"an alarm's lines are not the event's"
	)


func _meeting(tzid: String, local: String) -> String:
	return _vevent(
		[
			"UID:%s%s" % [tzid, local],
			"DTSTART;TZID=%s:%s" % [tzid, local],
			"DTEND;TZID=%s:%s" % [tzid, local],
			"SUMMARY:M"
		]
	)


func _vtimezone(id: String, std: String, dst: String) -> String:
	return (
		"BEGIN:VTIMEZONE\r\nTZID:%s\r\n" % id
		+ (
			"BEGIN:STANDARD\r\nDTSTART:16010101T020000\r\nTZOFFSETFROM:%s\r\nTZOFFSETTO:%s\r\n"
			% [dst, std]
		)
		+ "RRULE:FREQ=YEARLY;INTERVAL=1;BYDAY=1SU;BYMONTH=11\r\nEND:STANDARD\r\n"
		+ (
			"BEGIN:DAYLIGHT\r\nDTSTART:16010101T020000\r\nTZOFFSETFROM:%s\r\nTZOFFSETTO:%s\r\n"
			% [std, dst]
		)
		+ "RRULE:FREQ=YEARLY;INTERVAL=1;BYDAY=2SU;BYMONTH=3\r\nEND:DAYLIGHT\r\nEND:VTIMEZONE\r\n"
	)


func _zones() -> void:
	for c in [
		["Eastern Standard Time", "20261119T090000", "2026-11-19T14:00:00Z"],
		["Mountain Standard Time", "20261119T090000", "2026-11-19T16:00:00Z"],
		["UTC", "20261119T090000", "2026-11-19T09:00:00Z"],
		["Pacific Standard Time", "20261119T090000", "2026-11-19T17:00:00Z"],
		["Central Standard Time", "20261119T090000", "2026-11-19T15:00:00Z"],
		["GMT Standard Time", "20260617T090000", "2026-06-17T08:00:00Z"],
		["W. Europe Standard Time", "20260617T090000", "2026-06-17T07:00:00Z"],
		["India Standard Time", "20261119T090000", "2026-11-19T03:30:00Z"],
		["Eastern Standard Time", "20260617T090000", "2026-06-17T13:00:00Z"],
		["America/New_York", "20260308T013000", "2026-03-08T06:30:00Z"],
		["America/New_York", "20260308T033000", "2026-03-08T07:30:00Z"],
		["America/Los_Angeles", "20261101T003000", "2026-11-01T07:30:00Z"],
		["Europe/Berlin", "20260329T030000", "2026-03-29T01:00:00Z"],
		["Europe/Berlin", "20261025T030000", "2026-10-25T02:00:00Z"],
		["Australia/Sydney", "20261201T090000", "2026-11-30T22:00:00Z"],
		["Australia/Sydney", "20260601T090000", "2026-05-31T23:00:00Z"],
	]:
		var ms := _all(_ics(_meeting(c[0], c[1])))
		_eq(_starts(ms), [c[2]], "%s %s" % [c[0], c[1]])
	_eq(
		_starts(_all(_ics(_meeting('"Eastern Standard Time"', "20261119T090000")))),
		["2026-11-19T14:00:00Z"],
		"a quoted TZID is read without its quotes"
	)
	var display := "(UTC-05:00) Eastern Time (US & Canada)"
	var shown := func(local: String) -> String:
		return _vevent(
			[
				"UID:d%s" % local,
				'DTSTART;TZID="%s":%s' % [display, local],
				'DTEND;TZID="%s":%s' % [display, local],
				"SUMMARY:M"
			]
		)
	var zones := _vtimezone(display, "-0500", "-0400")
	_eq(
		_starts(_all(_ics(shown.call("20261119T090000"), zones))),
		["2026-11-19T14:00:00Z"],
		"the feed's own VTIMEZONE with a US rule: Eastern in winter"
	)
	_eq(
		_starts(_all(_ics(shown.call("20260617T090000"), zones))),
		["2026-06-17T13:00:00Z"],
		"and daylight time right in summer"
	)
	_eq(
		_starts(_all(_ics(shown.call("20260617T090000")))),
		["2026-06-17T14:00:00Z"],
		"with no VTIMEZONE the (UTC-05:00) prefix is fixed, so summer is an hour off"
	)
	var half := _ics(
		_vevent(["UID:h", 'DTSTART;TZID="(UTC+05:30) Chennai":20261119T090000', "SUMMARY:M"])
	)
	_eq(
		_starts(_all(half)), ["2026-11-19T09:00:00Z"], "a half-hour prefix with no VTIMEZONE is UTC"
	)
	var tonga := _ics(
		_vevent(["UID:t", 'DTSTART;TZID="(UTC+13:00) Nuku\'alofa":20261119T090000', "SUMMARY:M"])
	)
	_eq(_starts(_all(tonga)), ["2026-11-18T20:00:00Z"], "a +13:00 prefix is a fixed +13")
	var folded := (
		"BEGIN:VTIMEZONE\r\nTZID:(UTC+01:00) Amsterdam, Berlin, Bern, Rome,\r\n  Stockholm, Vienna\r\n"
		+ "BEGIN:STANDARD\r\nDTSTART:16010101T030000\r\nTZOFFSETFROM:+0200\r\nTZOFFSETTO:+0100\r\n"
		+ "RRULE:FREQ=YEARLY;INTERVAL=1;BYDAY=-1SU;BYMONTH=10\r\nEND:STANDARD\r\n"
		+ "BEGIN:DAYLIGHT\r\nDTSTART:16010101T020000\r\nTZOFFSETFROM:+0100\r\nTZOFFSETTO:+0200\r\n"
		+ "RRULE:FREQ=YEARLY;INTERVAL=1;BYDAY=-1SU;BYMONTH=3\r\nEND:DAYLIGHT\r\nEND:VTIMEZONE\r\n"
	)
	var long_name := _vevent(
		[
			"UID:f",
			(
				'DTSTART;TZID="(UTC+01:00) Amsterdam, Berlin, Bern, Rome,\r\n'
				+ '  Stockholm, Vienna":20260617T090000'
			),
			"SUMMARY:M"
		]
	)
	_eq(
		_starts(_all(_ics(long_name, folded))),
		["2026-06-17T07:00:00Z"],
		"a name folded mid-name still finds its VTIMEZONE, daylight time right"
	)
	var fiction := _ics(
		_meeting("Fictional Standard Time", "20261119T090000"),
		_vtimezone("Fictional Standard Time", "-0300", "-0300")
	)
	_eq(
		_starts(_all(fiction)),
		["2026-11-19T12:00:00Z"],
		"an unknown name takes its offset from the feed's VTIMEZONE"
	)
	var nowhere := _ics(_meeting("Nowhere Standard Time", "20261119T090000"))
	_eq(_starts(_all(nowhere)), ["2026-11-19T09:00:00Z"], "an unknown name without one is UTC")
	_eq(Ics.read(nowhere)["unknown"], ["Nowhere Standard Time"], "and is named once")
	_eq(Ics.read(fiction)["unknown"], [], "a name the feed explains is not unknown")


func _series() -> void:
	var weekly := _ics(
		(
			_vevent(
				[
					"UID:w@x",
					"DTSTART:20260907T150000Z",
					"DTEND:20260907T153000Z",
					"RRULE:FREQ=WEEKLY;BYDAY=MO,WE",
					"EXDATE:20261012T150000Z",
					"SUMMARY:Sync"
				]
			)
			+ _vevent(
				[
					"UID:w@x",
					"RECURRENCE-ID:20261014T150000Z",
					"DTSTART:20261014T180000Z",
					"DTEND:20261014T183000Z",
					"SUMMARY:Sync (moved)"
				]
			)
		)
	)
	_eq(
		_within(weekly, "2026-10-12T00:00:00", "2026-10-20T00:00:00").map(
			func(m): return [_at(m), m["title"]]
		),
		[["2026-10-14T18:00:00Z", "Sync (moved)"], ["2026-10-19T15:00:00Z", "Sync"]],
		"weekly: the exception skipped, a moved instance at its new time"
	)
	var short := _ics(
		_vevent(
			[
				"UID:c@x",
				"DTSTART:20261001T120000Z",
				"DTEND:20261001T130000Z",
				"RRULE:FREQ=DAILY;COUNT=3",
				"SUMMARY:Short run"
			]
		)
	)
	_eq(
		_starts(_within(short, "2026-10-02T00:00:00", "2026-10-10T00:00:00")),
		["2026-10-02T12:00:00Z", "2026-10-03T12:00:00Z"],
		"a recurrence that ended stays ended"
	)
	var old := _ics(
		_vevent(
			[
				"UID:p@x",
				"DTSTART:20260105T150000Z",
				"DTEND:20260105T153000Z",
				"RRULE:FREQ=WEEKLY;BYDAY=MO",
				"SUMMARY:Weekly"
			]
		)
	)
	_eq(
		_starts(_within(old, "2026-02-01T00:00:00", "2026-02-15T00:00:00")),
		["2026-02-02T15:00:00Z", "2026-02-09T15:00:00Z"],
		"a series is expanded for a range in the past too"
	)
	var z := "Eastern Standard Time"
	var windows := _ics(
		(
			_vevent(
				[
					"UID:s",
					"DTSTART;TZID=%s:20261116T090000" % z,
					"DTEND;TZID=%s:20261116T093000" % z,
					"RRULE:FREQ=DAILY;COUNT=5",
					"EXDATE;TZID=%s:20261117T090000" % z,
					"SUMMARY:Standup"
				]
			)
			+ _vevent(
				[
					"UID:s",
					"RECURRENCE-ID;TZID=%s:20261118T090000" % z,
					"DTSTART;TZID=%s:20261118T110000" % z,
					"DTEND;TZID=%s:20261118T113000" % z,
					"SUMMARY:Standup (moved)"
				]
			)
		)
	)
	_eq(
		_all(windows).map(func(m): return [_at(m), m["title"]]),
		[
			["2026-11-16T14:00:00Z", "Standup"],
			["2026-11-18T16:00:00Z", "Standup (moved)"],
			["2026-11-19T14:00:00Z", "Standup"],
			["2026-11-20T14:00:00Z", "Standup"],
		],
		"a series with an EXDATE and a moved instance, in a Windows zone"
	)
	var across := _ics(
		_vevent(
			[
				"UID:dst",
				"DTSTART;TZID=America/New_York:20261030T090000",
				"DTEND;TZID=America/New_York:20261030T093000",
				"RRULE:FREQ=DAILY;COUNT=4",
				"SUMMARY:Daily"
			]
		)
	)
	_eq(
		_starts(_all(across)),
		[
			"2026-10-30T13:00:00Z",
			"2026-10-31T13:00:00Z",
			"2026-11-01T14:00:00Z",
			"2026-11-02T14:00:00Z",
		],
		"a daily series keeps its wall time across the end of daylight time"
	)
	var rules := _ics(
		(
			_vevent(
				[
					"UID:m1",
					"DTSTART:20260105T100000Z",
					"DTEND:20260105T110000Z",
					"RRULE:FREQ=MONTHLY;BYDAY=2TU",
					"SUMMARY:Second Tuesday"
				]
			)
			+ _vevent(
				[
					"UID:m2",
					"DTSTART:20260131T100000Z",
					"DTEND:20260131T110000Z",
					"RRULE:FREQ=MONTHLY",
					"SUMMARY:On the 31st"
				]
			)
			+ _vevent(
				[
					"UID:m3",
					"DTSTART:20260106T100000Z",
					"DTEND:20260106T110000Z",
					"RRULE:FREQ=MONTHLY;BYDAY=-1FR",
					"SUMMARY:Last Friday"
				]
			)
			+ _vevent(
				[
					"UID:y1",
					"DTSTART:20250304T100000Z",
					"DTEND:20250304T110000Z",
					"RRULE:FREQ=YEARLY",
					"SUMMARY:Yearly"
				]
			)
			+ _vevent(
				[
					"UID:i1",
					"DTSTART:20261102T100000Z",
					"DTEND:20261102T110000Z",
					"RRULE:FREQ=WEEKLY;INTERVAL=2;UNTIL=20261231T000000Z",
					"SUMMARY:Fortnightly"
				]
			)
		)
	)
	var got := _within(rules, "2026-03-01T00:00:00", "2026-04-01T00:00:00")
	_eq(
		got.map(func(m): return m["title"]),
		["Yearly", "Second Tuesday", "Last Friday", "On the 31st"],
		"the rules of March, by start"
	)
	_eq(
		got.map(func(m): return _at(m)),
		[
			"2026-03-04T10:00:00Z",
			"2026-03-10T10:00:00Z",
			"2026-03-27T10:00:00Z",
			"2026-03-31T10:00:00Z",
		],
		"the nth Tuesday, the last Friday, the 31st and the yearly one"
	)
	_eq(
		_starts(_within(rules, "2026-04-01T00:00:00", "2026-05-01T00:00:00")).size(),
		2,
		"April has no 31st: the second Tuesday and the last Friday only"
	)
	_eq(
		(
			_within(rules, "2026-11-01T00:00:00", "2027-02-01T00:00:00")
			. filter(func(m): return m["title"] == "Fortnightly")
			. map(func(m): return _at(m))
		),
		[
			"2026-11-02T10:00:00Z",
			"2026-11-16T10:00:00Z",
			"2026-11-30T10:00:00Z",
			"2026-12-14T10:00:00Z",
			"2026-12-28T10:00:00Z"
		],
		"every other week, until its UNTIL"
	)


func _all_day() -> void:
	var feed := _ics(
		(
			_vevent(
				[
					"UID:d@x",
					"DTSTART;VALUE=DATE:20261008",
					"DTEND;VALUE=DATE:20261009",
					"SUMMARY:Holiday"
				]
			)
			+ _vevent(["UID:a", "DTSTART;VALUE=DATE:20261119", "SUMMARY:Out"])
		)
	)
	var ms := _all(feed)
	_eq(
		ms.map(func(m): return [_at(m), _at(m, "stop"), m["all_day"]]),
		[
			["2026-10-08T00:00:00Z", "2026-10-09T00:00:00Z", true],
			["2026-11-19T00:00:00Z", "2026-11-20T00:00:00Z", true],
		],
		"an all-day event runs midnight to midnight UTC, one with no end lasts a day"
	)
	var offsite := _ics(
		_vevent(
			["UID:o", "DTSTART;VALUE=DATE:20261119", "DTEND;VALUE=DATE:20261121", "SUMMARY:Offsite"]
		)
	)
	_eq(
		_at(_all(offsite)[0], "stop"),
		"2026-11-21T00:00:00Z",
		"a multi-day one runs to its end date"
	)


func _status() -> void:
	var cancelled := _ics(
		(
			_vevent(
				[
					"UID:a",
					"DTSTART:20261119T150000Z",
					"DTEND:20261119T153000Z",
					"SUMMARY:Live",
					"STATUS:CONFIRMED"
				]
			)
			+ _vevent(
				[
					"UID:b",
					"DTSTART:20261119T160000Z",
					"DTEND:20261119T163000Z",
					"SUMMARY:Gone",
					"STATUS:CANCELLED"
				]
			)
			+ _vevent(
				[
					"UID:c",
					"DTSTART:20261119T170000Z",
					"DTEND:20261119T173000Z",
					"SUMMARY:Canceled: Sync"
				]
			)
			+ _vevent(
				[
					"UID:d",
					"DTSTART:20261119T180000Z",
					"DTEND:20261119T183000Z",
					"SUMMARY:Cancelled: Review"
				]
			)
		)
	)
	_eq(
		_all(cancelled).map(func(m): return [m["title"], m["cancelled"]]),
		[["Live", false], ["Gone", true], ["Canceled: Sync", true], ["Cancelled: Review", true]],
		"cancelled by STATUS or by a Canceled: / Cancelled: summary"
	)
	var base := func(uid: String, extra: Array) -> String:
		return _vevent(
			(
				[
					"UID:%s" % uid,
					"DTSTART:20261119T150000Z",
					"DTEND:20261119T153000Z",
					"SUMMARY:%s" % uid
				]
				+ extra
			)
		)
	var busy := _ics(
		(
			base.call("free", ["TRANSP:OPAQUE", "X-MICROSOFT-CDO-BUSYSTATUS:FREE"])
			+ base.call("tent", ["X-MICROSOFT-CDO-BUSYSTATUS:TENTATIVE"])
			+ base.call("busy", ["X-MICROSOFT-CDO-BUSYSTATUS:BUSY", "TRANSP:OPAQUE"])
			+ base.call("oof", ["X-MICROSOFT-CDO-BUSYSTATUS:OOF"])
			+ base.call("transp", ["TRANSP:TRANSPARENT"])
			+ base.call("status", ["STATUS:TENTATIVE"])
			+ base.call("plain", [])
		)
	)
	var by := {}
	for m in _all(busy):
		by[m["title"]] = m["busy"]
	_eq(
		by,
		{
			"free": "free",
			"tent": "tentative",
			"busy": "busy",
			"oof": "away",
			"transp": "free",
			"status": "tentative",
			"plain": "busy"
		},
		"busy: the Microsoft status, else TRANSP, else the event's status"
	)


func _m(title: String, start: String, stop: String, extra: Dictionary = {}) -> Dictionary:
	var m := {
		"title": title,
		"start": _utc(start),
		"stop": _utc(stop),
		"cancelled": false,
		"busy": "busy",
		"all_day": false,
	}
	m.merge(extra, true)
	return m


func _cleaning() -> void:
	var gone := Ics.clean(
		[
			_m("A", "2026-10-08T16:00:00", "2026-10-08T17:00:00", {"cancelled": true}),
			_m("B", "2026-10-08T16:00:00", "2026-10-08T17:00:00")
		]
	)
	_eq(gone.map(func(m): return m["title"]), ["B"], "cancelled meetings are dropped")
	var all := [
		_m(
			"Holiday",
			"2026-10-08T00:00:00",
			"2026-10-09T00:00:00",
			{"all_day": true, "busy": "free"}
		),
		_m("Offsite", "2026-10-08T00:00:00", "2026-10-09T00:00:00", {"all_day": true}),
		_m("Free", "2026-10-08T16:00:00", "2026-10-08T17:00:00", {"busy": "free"}),
	]
	_eq(
		Ics.clean(all).map(func(m): return m["title"]),
		["Offsite", "Free"],
		"a free all-day event is dropped, a busy one and a free meeting stay"
	)
	var doubles := (
		Ics
		. clean(
			[
				_m(
					"Synced invitation: [EXT] Standup @ Thu Oct 8, 2026 (a@b.com)",
					"2026-10-08T16:00:00",
					"2026-10-08T17:00:00"
				),
				_m("Standup", "2026-10-08T16:00:00", "2026-10-08T17:00:00"),
				_m("Standup", "2026-10-08T17:00:00", "2026-10-08T18:00:00"),
			]
		)
	)
	_eq(
		doubles.map(func(m): return [m["title"], _at(m)]),
		[["Standup", "2026-10-08T16:00:00Z"], ["Standup", "2026-10-08T17:00:00Z"]],
		"doubles by stripped title and start are one, under the stripped title"
	)
	_eq(Ics.title("[EXT] Design review"), "Design review", "[EXT] goes")
	_eq(Ics.title("Synced invitation: 1:1 @ Weekly (me@x.org)"), "1:1", "the recurrence blurb goes")
	_eq(Ics.title("Lunch @ the park"), "Lunch @ the park", "an ordinary @ stays")


# the day's and the range's rows, on a fixed local clock (Wednesday 2026-11-18 10:00, zone +0)
func _days() -> void:
	var feed := Feed.new()
	feed.clock = func() -> float: return _utc("2026-11-18T10:00:00")
	feed.bias = 0.0
	feed.found = Ics.read(
		_ics(
			(
				_vevent(
					["UID:1", "DTSTART:20261118T080000Z", "DTEND:20261118T090000Z", "SUMMARY:Over"]
				)
				+ _vevent(
					[
						"UID:2",
						"DTSTART:20261118T093000Z",
						"DTEND:20261118T103000Z",
						"SUMMARY:Running"
					]
				)
				+ _vevent(
					[
						"UID:3",
						"DTSTART:20261118T150000Z",
						"DTEND:20261118T153000Z",
						"SUMMARY:Late",
						"X-MICROSOFT-CDO-BUSYSTATUS:TENTATIVE"
					]
				)
				+ _vevent(
					[
						"UID:4",
						"DTSTART:20261119T090000Z",
						"DTEND:20261119T100000Z",
						"SUMMARY:Review"
					]
				)
				+ _vevent(
					[
						"UID:5",
						"DTSTART:20261125T090000Z",
						"DTEND:20261125T100000Z",
						"SUMMARY:Next week"
					]
				)
				+ _vevent(
					[
						"UID:6",
						"DTSTART:20261118T110000Z",
						"DTEND:20261118T113000Z",
						"SUMMARY:Gone",
						"STATUS:CANCELLED"
					]
				)
				+ _vevent(
					[
						"UID:7",
						"DTSTART;VALUE=DATE:20261118",
						"DTEND;VALUE=DATE:20261120",
						"SUMMARY:Away"
					]
				)
				+ _vevent(
					[
						"UID:8",
						"DTSTART:20261118T230000Z",
						"DTEND:20261119T000000Z",
						"SUMMARY:Late night"
					]
				)
			)
		)
	)
	var rows: Array = feed.meetings()
	_eq(
		rows.map(func(r): return [r["title"], r["day"], r["tentative"], r["all_day"]]),
		[
			["Away", "today", false, true],
			["Running", "today", false, false],
			["Late", "today", true, false],
			["Late night", "today", false, false],
			["Away", "tomorrow", false, true],
			["Review", "tomorrow", false, false],
		],
		"today's remaining and tomorrow's, soonest first, an all-day one on each date it covers"
	)
	_eq(
		rows[1],
		{
			"title": "Running",
			"starts_at": "2026-11-18T09:30:00Z",
			"ends_at": "2026-11-18T10:30:00Z",
			"tentative": false,
			"all_day": false,
			"day": "today",
		},
		"each row is the server's: title, UTC starts_at and ends_at, tentative, all_day, day"
	)
	var range_rows: Array = feed.between("2026-11-01", "2026-11-30")
	_eq(
		range_rows.map(func(r): return [r["date"], r["title"]]),
		[
			["2026-11-18", "Away"],
			["2026-11-18", "Over"],
			["2026-11-18", "Running"],
			["2026-11-18", "Late"],
			["2026-11-18", "Late night"],
			["2026-11-19", "Away"],
			["2026-11-19", "Review"],
			["2026-11-25", "Next week"],
		],
		"any run of dates: each meeting on its date, past included, all-day first"
	)
	_eq(feed.between("2026-12-01", "2026-12-05"), [], "a run with none is empty")
	feed.bias = -3600.0 * 8
	feed.clock = func() -> float: return _utc("2026-11-18T10:00:00") - 3600.0 * 8
	_eq(
		feed.between("2026-11-18", "2026-11-18").map(func(r): return r["title"]),
		["Away", "Over", "Running", "Late", "Late night"],
		"a local date at UTC-8 runs from 08:00 UTC to 08:00 UTC"
	)
	var none := Feed.new()
	_eq(
		[none.meetings(), none.between("2026-11-01", "2026-11-30")],
		[[], []],
		"no feed is no meetings"
	)
	feed.free()
	none.free()
	_validate()


func _validate() -> void:
	for c in [
		["2026-11-22", "2026-11-16", false],
		["2026-11-01", "2027-01-02", false],
		["2026-11-01", "2027-01-01", true],
		["2026-11-01", "2026-12-31", true],
		["2026-11-01", "2026-11-01", true],
		["2026-11-31", "2026-12-01", false],
		["", "2026-12-01", false],
		["2026-11-01", "nope", false],
	]:
		_eq(Feed.range_ok(c[0], c[1]), c[2], "range %s to %s" % [c[0], c[1]])
