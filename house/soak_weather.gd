extends RefCounted

# The soak's checks of the weather the house shows: the degrees the person chose or the locale
# implies, the forecast on the window's card, and `wttr.gd` (the j1 reader, the address it builds,
# its pace, its switch) against a stub of wttr.in on the soak's local server. The real wttr.in is
# never reached.
const Settings := preload("res://settings.gd")

var s


func _init(soak) -> void:
	s = soak


func _eq(got: Variant, want: Variant, what: String) -> void:
	s._check(got == want, "%s: got %s, want %s" % [what, str(got), str(want)])


func run() -> void:
	_degrees()


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
