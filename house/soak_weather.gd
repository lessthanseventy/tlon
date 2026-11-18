extends RefCounted

# The soak's checks of the weather the house shows: the degrees the person chose or the locale
# implies, the forecast on the window's card, and `wttr.gd` (the j1 reader, the address it builds,
# its pace, its switch) against a stub of wttr.in on the soak's local server. The real wttr.in is
# never reached.
const Settings := preload("res://settings.gd")
const Forecast := preload("res://forecast.gd")
const Card := preload("res://card.gd")
const Wttr := preload("res://wttr.gd")

var s
var _t := 0.0


func _init(soak) -> void:
	s = soak


func _eq(got: Variant, want: Variant, what: String) -> void:
	s._check(got == want, "%s: got %s, want %s" % [what, str(got), str(want)])


func run() -> void:
	if not s._srv.is_listening():
		s._srv.listen(0, "127.0.0.1")
	OS.set_environment("TLON_URL", _stub())
	_degrees()
	_forecast()
	_parse()
	_address()
	await _served()
	await _pace()
	await _local()
	s._srv.stop()


func _plus(day: String, n: int) -> String:
	var at := int(Time.get_unix_time_from_datetime_string(day + "T00:00:00"))
	return Time.get_date_string_from_unix_time(at + n * 86400)


func _day(date: String, kind: String, wet: int = 0) -> Dictionary:
	return {"date": date, "high_c": 12, "low_c": -1, "kind": kind, "wet": wet}


func _days_of(h) -> Array:
	return h._weather_blocks().filter(func(b): return b["t"] == "day")


func _forecast() -> void:
	var wed := "2026-11-18"
	var rows := [
		_day("2026-11-17", "rain"),
		_day(wed, "clear"),
		_day("2026-11-19", "rain", 60),
		_day("2026-11-20", "snow", 55),
		_day("2026-11-21", "fog"),
	]
	var up := Forecast.upcoming(rows, wed)
	_eq(
		up.map(func(d): return d["date"]),
		["2026-11-18", "2026-11-19", "2026-11-20"],
		"from today, three"
	)
	_eq(Forecast.upcoming(rows.slice(0, 1), wed), [], "a day gone is dropped, none is left")
	_eq(Forecast.upcoming(null, wed), [], "no list is no days")
	_eq(
		Forecast.upcoming([{"date": wed, "kind": "hail", "high_c": 1, "low_c": 0}], wed),
		[],
		"an unknown kind"
	)
	_eq(Forecast.upcoming([{"date": wed, "kind": "rain"}], wed), [], "a day with no temperatures")
	_eq(Forecast.name_of(wed, wed), "Today", "today")
	_eq(Forecast.name_of("2026-11-19", wed), "Tomorrow", "tomorrow")
	_eq(Forecast.name_of("2026-11-20", wed), "Friday", "then the weekday")
	_eq(Forecast.name_of("2026-12-01", "2026-11-30"), "Tomorrow", "tomorrow over a month end")
	_eq(Forecast.wet_text(_day(wed, "rain", 19)), "", "under 20 percent is not said")
	_eq(Forecast.wet_text(_day(wed, "rain", 20)), "20% rain", "20 percent is said")
	_eq(Forecast.wet_text(_day(wed, "snow", 55)), "55% snow", "snow is named")
	var room: Control = s._room(42)
	var h = room.home
	h.set_weather({"kind": "clear", "temp_c": 13, "desc": "Sunny"})
	var bare: int = h._weather_blocks().size()
	var today: String = h.today()
	h.set_forecast(
		[_day(_plus(today, -1), "rain"), _day(today, "clear"), _day(_plus(today, 1), "rain", 60)]
	)
	var shown := _days_of(h)
	_eq(shown.map(func(b): return b["name"]), ["Today", "Tomorrow"], "the card names its days")
	_eq(shown[1]["kind"], "rain", "the card's kind")
	_eq(shown[1]["wet"], "60% rain", "the card's chance")
	_eq(shown[0]["wet"], "", "no chance said for a dry day")
	h.settings.forced["degrees"] = "f"
	_eq(_days_of(h)[0]["temps"], "54°F / 30°F", "a day's high and low in Fahrenheit")
	h.settings.forced["degrees"] = "c"
	_eq(_days_of(h)[0]["temps"], "12°C / -1°C", "a day's high and low in Celsius")
	h.set_forecast([])
	_eq(h._weather_blocks().size(), bare, "no forecast adds nothing to the card")
	h.set_forecast("nonsense")
	_eq(h._weather_blocks().size(), bare, "a forecast that is no list adds nothing")
	room.queue_free()

	var row := {"t": "day", "name": "Today", "kind": "clear", "temps": "1", "wet": ""}
	_eq(Card._height(ThemeDB.fallback_font, row, 298.0), Card.DAY_HEIGHT, "a day row's height")


# the server's /api/home carries the forecast to the card; an older one has no key
func _served() -> void:
	var main: Control = _main()
	main.pets_every = 100.0
	s.root.add_child(main)
	var h = main._room.home
	h.fake_hour = 15.0
	var today: String = h.today()
	await _until(func(): return not main._busy)
	s._state["forecast"] = [
		_day(_plus(today, -1), "snow"), _day(today, "storm", 80), _day(_plus(today, 2), "fog")
	]
	main._poll()
	await _until(func(): return not _days_of(h).is_empty())
	_eq(
		_days_of(h).map(func(b): return b["kind"]),
		["storm", "fog"],
		"the server's forecast reaches the card"
	)
	_eq(
		_days_of(h).map(func(b): return b["name"]),
		["Today", Forecast.name_of(_plus(today, 2), today)],
		"named from today"
	)
	s._state.erase("forecast")
	await _until(func(): return not main._busy)
	main._poll()
	await _until(func(): return _days_of(h).is_empty())
	_eq(_days_of(h), [], "an older server's answer has no forecast, and none is shown")
	main.queue_free()


func _degrees() -> void:
	_eq(Settings.default_degrees("en_US"), "f", "a US locale is Fahrenheit")
	_eq(Settings.default_degrees("en_US.UTF-8"), "f", "a US locale with an encoding")
	_eq(Settings.default_degrees("en-US"), "f", "a US locale with a dash")
	_eq(Settings.default_degrees("en_GB"), "c", "a British locale is Celsius")
	_eq(Settings.default_degrees("de"), "c", "a locale with no country is Celsius")
	_eq(Settings.default_degrees(""), "c", "no locale is Celsius")
	_eq(Settings.temp(11, "f"), "52°F", "11 C in Fahrenheit")
	_eq(Settings.temp(-1, "f"), "30°F", "-1 C in Fahrenheit")
	_eq(Settings.temp(11, "c"), "11°C", "11 C as it is")
	_eq(Settings.temp(11.6, "c"), "12°C", "a fraction rounds")
	var st := Settings.new()
	_eq(st.degrees(), Settings.default_degrees(OS.get_locale()), "no choice follows the locale")
	st.forced["degrees"] = "c"
	_eq(st.degrees(), "c", "the choice beats the locale")
	st.forced["degrees"] = "kelvin"
	_eq(
		st.degrees(), Settings.default_degrees(OS.get_locale()), "an unknown choice is the locale's"
	)
	var room: Control = s._room(41)
	var h = room.home
	h.set_weather({"kind": "rain", "temp_c": 11, "desc": "Light rain"})
	h.settings.forced["degrees"] = "f"
	_eq(_temp_line(h), "52°F", "the card says Fahrenheit")
	h.settings.forced["degrees"] = "c"
	_eq(_temp_line(h), "11°C", "the card says Celsius")
	room.queue_free()


func _temp_line(h) -> String:
	for b in h._weather_blocks():
		if b["t"] == "text" and "°" in b["text"]:
			return b["text"]
	return ""


func _hour(time: String, code: String, rain: String = "0", snow: String = "0") -> Dictionary:
	return {"time": time, "weatherCode": code, "chanceofrain": rain, "chanceofsnow": snow}


# eight entries as wttr.in gives them; the night's are storms that must not count
func _hours(by_day: Array) -> Array:
	var out: Array = []
	for t in ["0", "300", "600", "2100"]:
		out.append(_hour(t, "389", "99", "99"))
	for i in 4:
		out.append(_hour(str([900, 1200, 1500, 1800][i]), by_day[i][0], by_day[i][1], by_day[i][2]))
	return out


func _wday(date: String, high: String, low: String, hours: Array) -> Dictionary:
	return {"date": date, "maxtempC": high, "mintempC": low, "hourly": hours}


func _clear_hours() -> Array:
	return _hours([["113", "0", "0"], ["113", "0", "0"], ["113", "0", "0"], ["113", "0", "0"]])


func _report(code: String, temp: String, desc: String, days: Variant) -> Dictionary:
	var doc := {
		"current_condition":
		[{"weatherCode": code, "temp_C": temp, "weatherDesc": [{"value": desc}]}]
	}
	if days != null:
		doc["weather"] = days
	return doc


func _fixture() -> Dictionary:
	var stormy := _hours(
		[["116", "0", "0"], ["302", "70", "0"], ["389", "40", "0"], ["113", "0", "0"]]
	)
	return _report(
		"296",
		"11",
		"Light rain ",
		[
			_wday("2026-11-18", "14", "6", _clear_hours()),
			_wday("2026-11-19", "9", "-1", stormy),
			_wday("2026-11-20", "x", "3", _clear_hours()),
		]
	)


func _parse() -> void:
	var got := Wttr.parse(JSON.stringify(_fixture()))
	_eq(got["report"], {"kind": "rain", "temp_c": 11, "desc": "Light rain"}, "the current report")
	var days: Array = got["days"]
	_eq(days.size(), 2, "a day that does not read is left out")
	_eq(
		days[0],
		{"date": "2026-11-18", "high_c": 14, "low_c": 6, "kind": "clear", "wet": 0},
		"day one"
	)
	_eq(days[1]["kind"], "storm", "a storm beats rain and the night's storms do not count")
	_eq(days[1]["wet"], 70, "the day's wettest daytime chance")
	_eq(days[1]["low_c"], -1, "a negative low")
	var snowy := _hours(
		[["227", "0", "30"], ["296", "20", "0"], ["122", "0", "0"], ["143", "0", "0"]]
	)
	var snow := Wttr.parse(
		JSON.stringify(_report("113", "3", "Sunny", [_wday("2026-11-18", "1", "-4", snowy)]))
	)
	_eq(snow["days"][0]["kind"], "snow", "snow beats rain, fog and cloud")
	_eq(snow["days"][0]["wet"], 30, "snow's chance counts")
	var fog := _hours([["143", "0", "0"], ["122", "0", "0"], ["116", "0", "0"], ["113", "0", "0"]])
	var foggy := Wttr.parse(
		JSON.stringify(_report("113", "3", "Sunny", [_wday("2026-11-18", "1", "0", fog)]))
	)
	_eq(foggy["days"][0]["kind"], "fog", "fog beats cloud")
	var wild := _hours(
		[["113", "150", "0"], ["113", "0", "0"], ["113", "0", "0"], ["113", "0", "0"]]
	)
	var capped := Wttr.parse(
		JSON.stringify(_report("113", "3", "Sunny", [_wday("2026-11-18", "1", "0", wild)]))
	)
	_eq(capped["days"][0]["wet"], 100, "a chance is at most 100")
	var four: Array = []
	for d in 4:
		four.append(_wday(_plus("2026-11-18", d), "5", "1", _clear_hours()))
	_eq(
		Wttr.parse(JSON.stringify(_report("113", "3", "Sunny", four)))["days"].size(),
		3,
		"three days"
	)
	var bare := Wttr.parse(JSON.stringify(_report("116", "7", "Partly cloudy", null)))
	_eq(bare["report"]["kind"], "partly", "no weather list still gives the current report")
	_eq(bare["days"], [], "and no days")
	var night_only := _wday("2026-11-18", "5", "1", [_hour("0", "113"), _hour("2100", "113")])
	var none := Wttr.parse(JSON.stringify(_report("113", "3", "Sunny", [night_only])))
	_eq(none["days"], [], "a day with no daytime entry is left out")
	var no_desc := _report("113", "n/a", "", [])
	_eq(
		Wttr.parse(JSON.stringify(no_desc))["report"],
		{"kind": "clear", "temp_c": null, "desc": "clear"},
		"no temperature, desc from the kind"
	)
	_eq(
		Wttr.parse(JSON.stringify(_report("999", "3", "Hail", []))),
		{},
		"a code the room cannot draw"
	)
	_eq(Wttr.parse("not json"), {}, "not JSON")
	_eq(Wttr.parse("{}"), {}, "no current conditions")
	_eq(Wttr.parse(JSON.stringify({"current_condition": []})), {}, "an empty list of conditions")
	for pair in [
		[113, "clear"],
		[116, "partly"],
		[122, "cloudy"],
		[248, "fog"],
		[389, "storm"],
		[338, "snow"],
		[353, "rain"]
	]:
		_eq(Wttr.kind_of(pair[0]), pair[1], "code %d" % pair[0])
	_eq(Wttr.kind_of(1), "", "an unknown code")


func _address() -> void:
	_eq(Wttr.town_of(""), "", "no town")
	_eq(Wttr.town_of("  Paris "), "Paris", "a town is trimmed")
	_eq(Wttr.town_of("New York"), "New York", "a space")
	_eq(Wttr.town_of("St. John's, NL"), "St. John's, NL", "comma, period and apostrophe")
	_eq(Wttr.town_of("Aix-en-Provence"), "Aix-en-Provence", "a hyphen")
	_eq(Wttr.town_of("Zürich"), "Zürich", "a letter with a mark")
	_eq(Wttr.town_of("a/b"), "", "a slash is no town")
	_eq(Wttr.town_of("x?y=1"), "", "a query is no town")
	_eq(Wttr.town_of("a<b>"), "", "angle brackets are no town")
	_eq(Wttr.town_of("a".repeat(60)), "a".repeat(60), "sixty characters")
	_eq(Wttr.town_of("a".repeat(61)), "", "sixty-one characters")
	_eq(Wttr.url("https://wttr.in", ""), "https://wttr.in/?format=j1", "placed by the address")
	_eq(
		Wttr.url("https://wttr.in", "New York"),
		"https://wttr.in/New%20York?format=j1",
		"a town with a space"
	)
	_eq(
		Wttr.url("https://wttr.in", "Zürich"),
		"https://wttr.in/Z%C3%BCrich?format=j1",
		"a town with a mark"
	)


func _hits() -> int:
	return s._log.filter(func(l): return "format=j1" in l[1]).size()


func _last_path() -> String:
	var all: Array = s._log.filter(func(l): return "format=j1" in l[1])
	return "" if all.is_empty() else all[-1][1]


func _until(done: Callable, secs: float = 4.0) -> void:
	var end := Time.get_ticks_msec() + int(secs * 1000.0)
	while not done.call() and Time.get_ticks_msec() < end:
		await s.create_timer(0.02).timeout


func _quiet_for(secs: float = 0.3) -> void:
	await s.create_timer(secs).timeout


func _stub() -> String:
	return "http://127.0.0.1:%d" % s._srv.get_local_port()


func _pace() -> void:
	_t = 1000.0
	var w := Wttr.new()
	w.base = _stub()
	w.live = true
	w.on = true
	w.clock = func() -> float: return _t
	s.root.add_child(w)
	s.wttr_body = _fixture()
	var before := _hits()
	await _until(func(): return w.report != null)
	_eq(_hits() - before, 1, "the first turn asks once")
	_eq(_last_path(), "/?format=j1", "placed by the address")
	_eq(w.report["kind"], "rain", "the report is kept")
	_eq(w.days.size(), 2, "and its days")
	_t += 1799.0
	await _quiet_for()
	_eq(_hits() - before, 1, "nothing before the interval is up")
	_t += 1.0
	await _until(func(): return _hits() - before == 2)
	_eq(_hits() - before, 2, "the next turn asks again")
	var kept: Variant = w.report
	s.wttr_code = 500
	_t += 1800.0
	await _until(func(): return _hits() - before == 3)
	await _quiet_for()
	_eq(_hits() - before, 3, "a refused request is asked once, no storm of retries")
	_eq(w.report, kept, "a failure keeps the last report")
	_eq(w.days.size(), 2, "and its days")
	_t += 1799.0
	await _quiet_for()
	_eq(_hits() - before, 3, "a failure waits for the next turn")
	s.wttr_code = 200
	s.wttr_body = {"nothing": "here"}
	_t += 1.0
	await _until(func(): return _hits() - before == 4)
	await _quiet_for()
	_eq(w.report, kept, "an answer that is no report keeps the last one")
	s.wttr_body = _fixture()
	w.town = Wttr.town_of("New York")
	w.poke()
	w.poke()
	await _quiet_for()
	_eq(_hits() - before, 4, "a change waits for things to be quiet")
	_t += 2.0
	await _until(func(): return _hits() - before == 5)
	await _quiet_for()
	_eq(_hits() - before, 5, "a change is one request however often it is poked")
	_eq(_last_path(), "/New%20York?format=j1", "a town with a space goes into the path")
	w.town = Wttr.town_of("a/b")
	w.poke()
	_t += 2.0
	await _until(func(): return _hits() - before == 6)
	_eq(_last_path(), "/?format=j1", "a bad town is no town")
	w.on = false
	w.clear()
	_t += 100000.0
	await _quiet_for()
	_eq(_hits() - before, 6, "switched off, nothing is asked")
	_eq(w.report, null, "and nothing is held")
	w.queue_free()
	var idle := Wttr.new()
	idle.base = _stub()
	idle.on = true
	idle.clock = func() -> float: return _t
	s.root.add_child(idle)
	idle.poke()
	_t += 100000.0
	await _quiet_for()
	_eq(_hits() - before, 6, "a staged module asks nothing")
	idle.queue_free()


# the room over the house's own list: staged, it never asks; with the module let loose it takes
# the report and the days, and switching the weather off takes them away
func _local() -> void:
	var main: Control = _main()
	s.root.add_child(main)
	var h = main._room.home
	h.fake_hour = 15.0
	h.settings.forced["where"] = "local"
	main._make_backend()
	main._wttr.base = _stub()
	_eq(main._wttr.live, false, "a staged room's module is not live")
	_eq(main._wttr.on, true, "over the house's own list the weather is on")
	var before := _hits()
	await _quiet_for(2.5)
	_eq(_hits() - before, 0, "a staged room asks nothing")
	s.wttr_body = _fixture()
	main._wttr.live = true
	await _until(func(): return h.weather == "rain")
	_eq(h.weather, "rain", "the report reaches the window")
	_eq(h.weather_desc, "Light rain", "its words")
	_eq(h.temp_c, 11, "its temperature")
	_eq(h.forecast.size(), 2, "the days reach the card")
	h.settings.forced["weather"] = false
	main._apply_weather()
	_eq(main._wttr.on, false, "the switch turns it off")
	_eq(
		[h.weather, h.weather_desc, h.temp_c, h.forecast],
		["clear", "", null, []],
		"and the window shows none"
	)
	var asked := _hits()
	await _quiet_for(2.5)
	_eq(_hits(), asked, "off asks nothing")
	h.settings.forced["where"] = "server"
	main._make_backend()
	_eq(main._wttr.on, false, "a server's house leaves the weather to the server")
	main.queue_free()


func _main() -> Control:
	return load("res://main.gd").new()
