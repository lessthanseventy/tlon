extends "res://logic_weather.gd"

# The soak's checks of the weather the house shows on the card and `wttr.gd` (its pace, its switch)
# against a stub of wttr.in on the soak's local server. The real wttr.in is never reached.
const Card := preload("res://card.gd")

var _t := 0.0


func run() -> void:
	if not s._srv.is_listening():
		s._srv.listen(0, "127.0.0.1")
	OS.set_environment("TLON_URL", _stub())
	_forecast_card()
	_degrees_card()
	await _served()
	await _pace()
	await _local()
	s._srv.stop()


func _days_of(h) -> Array:
	return h._weather_blocks().filter(func(b): return b["t"] == "day")


func _forecast_card() -> void:
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


func _degrees_card() -> void:
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
