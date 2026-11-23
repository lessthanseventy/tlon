extends RefCounted

# The soak's checks of the calendar feed (`calendar_feed.gd`) against a stub of a feed host on the
# soak's local server: the address kept at mode 0600 and nowhere else, a fetch read into meetings,
# a failure keeping the last good copy with a phrase that never holds the address, and the local
# backend's two routes over it. The address here is made up and no line of this file prints it.
const Feed := preload("res://calendar_feed.gd")
const BackendLocal := preload("res://backend_local.gd")
const STORE := "user://soak_calendar.json"
const SECRET := "s3cr3t-token-not-real"

var s
var _t := 0.0


func _init(soak) -> void:
	s = soak


func _eq(got: Variant, want: Variant, what: String) -> void:
	s._check(got == want, "%s: got %s, want %s" % [what, str(got), str(want)])


func _utc(text: String) -> float:
	return Time.get_unix_time_from_datetime_string(text)


func _feed(title: String, start: String, end: String) -> String:
	return (
		(
			"BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\nUID:1\r\nDTSTART:%s\r\nDTEND:%s\r\n"
			% [start, end]
		)
		+ "SUMMARY:%s\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n" % title
	)


func _address() -> String:
	return "http://127.0.0.1:%d/calendar/%s.ics" % [s._srv.get_local_port(), SECRET]


func _settled(f: Node) -> void:
	await s._until(func(): return not f._busy, "the feed's request answered")


func run() -> void:
	if not s._srv.is_listening():
		s._srv.listen(0, "127.0.0.1")
	if FileAccess.file_exists(STORE):
		DirAccess.remove_absolute(STORE)
	_eq(
		[
			Feed.address("webcal://example.com/a.ics"),
			Feed.address(" https://example.com/a.ics "),
			Feed.address("example.com/a.ics"),
			Feed.address("ftp://example.com/a.ics"),
			Feed.address("https://exa mple.com/a.ics"),
		],
		["https://example.com/a.ics", "https://example.com/a.ics", "", "", ""],
		"an address is http(s) or webcal with a host"
	)
	var f := Feed.new()
	f.store = STORE
	f.persist = true
	f.clock = func() -> float: return _utc("2026-11-18T10:00:00")
	s.root.add_child(f)
	_eq(f.meetings(), [], "no feed is no meetings")
	var said := []
	f.connect_feed(_address(), func(line: String) -> void: said.append(line))
	await s._until(func(): return not said.is_empty(), "a feed that is not live answers")
	_eq(said, ["not available in this run"], "a staged feed asks nothing and keeps nothing")
	_eq([f.has_url(), FileAccess.file_exists(STORE)], [false, false], "and no address is kept")

	f.live = true
	s.ics_body = _feed("Standup", "20261118T150000Z", "20261118T153000Z")
	said = []
	f.connect_feed(_address(), func(line: String) -> void: said.append(line))
	await s._until(func(): return not said.is_empty(), "the feed answers")
	_eq(said, ["ok"], "a feed that reads is connected")
	_eq(f.meetings().map(func(m): return m["title"]), ["Standup"], "its meetings are read")
	_eq(
		FileAccess.get_unix_permissions(STORE),
		FileAccess.UNIX_READ_OWNER | FileAccess.UNIX_WRITE_OWNER,
		"the address is kept at mode 0600"
	)
	var kept: Variant = JSON.parse_string(FileAccess.get_file_as_string(STORE))
	_eq(kept, {"url": _address()}, "it is kept in that file alone")
	var again := Feed.new()
	again.store = STORE
	again.persist = true
	again.load_state()
	_eq(again.url, _address(), "and read back at the next start")
	again.free()

	s.ics_body = _feed("Moved", "20261118T160000Z", "20261118T163000Z")
	f.refresh()
	await _settled(f)
	_eq(f.meetings().map(func(m): return m["title"]), ["Moved"], "a refresh takes the new copy")
	s.ics_code = 500
	f.refresh()
	await _settled(f)
	_eq(f.meetings().map(func(m): return m["title"]), ["Moved"], "a failure keeps the last copy")
	_eq(f.problem, "the calendar answered 500", "and says so in a fixed phrase")
	s.ics_code = 200
	s.ics_body = "<html>sign in</html>"
	f.refresh()
	await _settled(f)
	_eq(f.problem, "that link did not answer a calendar", "an answer that is no calendar")
	_eq(f.meetings().map(func(m): return m["title"]), ["Moved"], "keeps the last copy too")
	_eq(f.problem.contains(SECRET), false, "no phrase holds the address")

	var backend := BackendLocal.new()
	backend.setup("", func() -> float: return _utc("2026-11-18T10:00:00"), 0.0, false)
	backend.calendar = f
	var status: Dictionary = backend._route("GET", "/api/home", {})["body"]
	_eq(
		status["meetings"].map(func(m): return [m["title"], m["day"]]),
		[["Moved", "today"]],
		"GET /api/home carries the day's meetings"
	)
	var range_answer: Dictionary = backend._route(
		"GET", "/api/home/meetings?from=2026-11-16&to=2026-11-22", {}
	)
	_eq(range_answer["code"], 200, "a range is answered")
	_eq(
		range_answer["body"].map(func(m): return [m["title"], m["date"]]),
		[["Moved", "2026-11-18"]],
		"each meeting on its date"
	)
	backend.free()

	s.ics_body = "<html>sign in</html>"
	said = []
	var other := "http://127.0.0.1:%d/calendar/other.ics" % s._srv.get_local_port()
	f.connect_feed(other, func(line: String) -> void: said.append(line))
	await s._until(func(): return not said.is_empty(), "the other link answers")
	_eq(said, ["that link did not answer a calendar"], "a link that is no calendar is refused")
	_eq(f.url, _address(), "and the connected one stays")
	f.disconnect_feed()
	_eq(
		[f.has_url(), f.meetings(), FileAccess.file_exists(STORE)],
		[false, [], false],
		"disconnected: no address, no meetings, no file"
	)
	f.queue_free()
