extends RefCounted

# The soak's checks of the weather the house shows: the degrees the person chose or the locale
# implies, the forecast on the window's card, and `wttr.gd` (the j1 reader, the address it builds,
# its pace, its switch) against a stub of wttr.in on the soak's local server. The real wttr.in is
# never reached.
const Settings := preload("res://settings.gd")
const Forecast := preload("res://forecast.gd")
const Card := preload("res://card.gd")

var s


func _init(soak) -> void:
	s = soak


func _eq(got: Variant, want: Variant, what: String) -> void:
	s._check(got == want, "%s: got %s, want %s" % [what, str(got), str(want)])


func run() -> void:
	_degrees()
	_forecast()
	await _served()


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
	var main: Control = load("res://main.gd").new()
	main.pets_every = 100.0
	s.root.add_child(main)
	var h = main._room.home
	h.fake_hour = 15.0
	var today: String = h.today()
	s._state["forecast"] = [
		_day(_plus(today, -1), "snow"), _day(today, "storm", 80), _day(_plus(today, 2), "fog")
	]
	main._poll()
	await s.create_timer(0.8).timeout
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
	main._poll()
	await s.create_timer(0.8).timeout
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
