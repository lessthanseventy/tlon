extends SceneTree

# The house's logic checks: rules that need no scene tree and no simulated room (due times, the
# reader, the list, the forecast, voices, the jar, the knock and rhythm rules). Seconds, not minutes:
# `mise run house:check` runs it. The scripted room is `soak.gd`.
const Jar := preload("res://jar.gd")
const Knock := preload("res://knock.gd")
const Rhythm := preload("res://rhythm.gd")
const Hacks := preload("res://hacks.gd")
const Tv := preload("res://tv.gd")
const Voices := preload("res://voices.gd")
const Pets := preload("res://pets.gd")
const Settings := preload("res://settings.gd")
const Card := preload("res://card.gd")
const When := preload("res://when.gd")
const LocalLogic := preload("res://logic_local.gd")
const WeatherLogic := preload("res://logic_weather.gd")

var _failures: Array = []


func _initialize() -> void:
	_logic()
	_when()
	_pet_settings()
	_pet_voices()
	LocalLogic.new(self).run()
	WeatherLogic.new(self).run()
	print("LOGIC %s (%d failures)" % ["OK" if _failures.is_empty() else "FAILED", _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures.append(what)
		print("FAIL: ", what)


func _iso(days_ago: float) -> String:
	var at := Time.get_unix_time_from_system() - days_ago * 86400.0
	return Time.get_datetime_string_from_unix_time(int(at)) + "Z"


func _unix(text: String) -> float:
	return Time.get_unix_time_from_datetime_string(text)


func _logic() -> void:
	_jar_logic()
	_knock_logic()
	_rhythm_logic()
	_tv_logic()
	_voices_logic()
	_card_logic()


func _jar_logic() -> void:
	var monday := Jar.week_key(_unix("2026-11-16T09:00:00"))
	_check(Jar.week_key(_unix("2026-11-22T23:00:00")) == monday, "Sunday is in its Monday's week")
	_check(Jar.week_key(_unix("2026-11-23T00:30:00")) != monday, "Monday starts a new week")
	var jar := Jar.new()
	jar.set_count(4, monday)
	_check(jar.shown == 4 and jar.drops.is_empty(), "the first count shows at once")
	jar.set_count(5, monday)
	_check(jar.drops.size() == 1 and jar.shown == 4, "one more done queues one drop")
	for i in 20:
		jar.process(0.05)
	_check(jar.shown == 5 and jar.drops.is_empty(), "the drop lands and the jar holds it")
	jar.set_count(60, monday)
	_check(jar.shown == Jar.CAP, "the drawn marbles are capped")
	jar.set_count(2, monday + 7)
	_check(jar.shown == 2 and jar.drops.is_empty(), "a new week starts again, quietly")
	var a := Jar.new()
	var b := Jar.new()
	var c := Jar.new()
	a.set_count(1, monday)
	b.set_count(1, monday)
	c.set_count(1, monday + 7)
	var same := true
	var differs := false
	for i in Jar.CAP:
		same = same and a.colour(i) == b.colour(i)
		differs = differs or a.colour(i) != c.colour(i)
	_check(same, "a week's colours are the same every time")
	_check(differs, "another week has other colours")


func _knock_logic() -> void:
	var now := Time.get_unix_time_from_system()
	var old := {"id": 1, "since": _iso(5.0), "due_at": null}
	var older := {"id": 2, "since": _iso(9.0), "due_at": null}
	var fresh := {"id": 3, "since": _iso(1.0), "due_at": null}
	var future := {"id": 4, "since": _iso(20.0), "due_at": _iso(-1.0)}
	_check(Knock.oldest([old, older, fresh], now) == 2, "the oldest open thing is the one")
	_check(Knock.oldest([fresh], now) == -1, "nothing under three days is knocked")
	_check(Knock.oldest([future, fresh], now) == -1, "a thing with a future due is never knocked")
	_check(Knock.oldest([future, old], now) == 1, "a future due is passed over for the next oldest")
	var k := Knock.new()
	k.persist = false
	_check(k.candidate([old], now, 12.0, false) == 1, "by day the old sticky is a candidate")
	_check(k.candidate([old], now, 12.0, true) == -1, "never at night")
	_check(k.candidate([old], now, 7.0, false) == -1, "never before the morning")
	_check(k.candidate([old], now, 22.0, false) == -1, "never late in the evening")
	k.last = now - 3600.0
	_check(k.candidate([old], now, 12.0, false) == -1, "at most once every few hours")
	k.last = now - 5.0 * 3600.0
	_check(k.candidate([old], now, 12.0, false) == 1, "after the gap it can again")
	k.pending = 1
	_check(k.candidate([old], now, 12.0, false) == -1, "not while one is on its way")
	k.pending = -1
	k.id = 1
	_check(k.candidate([old], now, 12.0, false) == -1, "one knocked sticky at a time")
	k.clear()
	var pets := Pets.new()
	pets.setup("", 3)
	var nina := pets.critter("nina")
	pets.knock(nina)
	var swats := 0
	for i in 400:
		pets.process(0.1)
		for ev in pets.events:
			swats += 1 if ev == "swat" else 0
		pets.events = []
	_check(swats == 1, "Nina swats once (%d)" % swats)
	_check(nina.spot == "knocked", "Nina ends beside the sticky (%s)" % nina.spot)


func _rhythm_logic() -> void:
	_check(Rhythm.parse_time("17:30") == 17.5, "17:30 parses")
	_check(Rhythm.parse_time("") == -1.0 and Rhythm.parse_time("later") == -1.0, "no time, no beat")
	_check(Rhythm.home_due(17.6, 17.5, "", "d"), "home beat is due after the list time")
	_check(not Rhythm.home_due(17.4, 17.5, "", "d"), "not before it")
	_check(not Rhythm.home_due(17.6, 17.5, "d", "d"), "not twice a day")
	_check(not Rhythm.home_due(21.0, 17.5, "", "d"), "not hours after")
	_check(not Rhythm.home_due(17.6, -1.0, "", "d"), "not when the list is off")
	_check(Rhythm.morning_due(9.0, 9.0, "", "d"), "first run after 05:30 is a morning")
	_check(not Rhythm.morning_due(6.0, 4.0, "", "d"), "running since before 05:30 waits for 08:00")
	_check(Rhythm.morning_due(8.1, 4.0, "", "d"), "the clock passing 08:00 is a morning")
	_check(not Rhythm.morning_due(8.1, 4.0, "d", "d"), "once a day")
	_check(not Rhythm.morning_due(13.0, 13.0, "", "d"), "no morning in the afternoon")
	var r := Rhythm.new()
	r.persist = false
	_check(r.due(9.0, "d1") == "morning", "the morning comes")
	_check(r.due(9.1, "d1") == "", "and not again that day")
	_check(r.due(17.6, "d1") == "home", "then the homecoming")
	_check(r.due(17.7, "d1") == "", "and not again")
	_check(r.due(9.0, "d2") == "morning", "the next day it all comes back")


func _tv_logic() -> void:
	var tv := Tv.new()
	tv.setup(5)
	tv.process(0.1, false, false)
	_check(not tv.on, "the TV is off when nobody watches")
	tv.process(0.1, true, false)
	_check(tv.on, "it is on while he watches")
	tv.process(0.1, true, true)
	_check(not tv.on, "it is off in the deep night")
	tv.process(0.1, false, false)
	tv.click()
	_check(tv.on, "a click turns the TV on")
	for i in 20:
		tv.process(0.5, false, false)
	_check(tv.on, "a clicked-on TV stays on while nobody watches")
	tv.click()
	_check(not tv.on, "a second click turns it off")
	tv.process(0.1, false, false)
	_check(not tv.on, "and it stays off")
	tv.process(0.1, true, false)
	_check(tv.on, "he sits down to watch: automatic again, on")
	tv.click()
	for i in 20:
		tv.process(0.5, true, false)
	_check(not tv.on, "a click-off survives the frames after it while he watches")
	tv.process(0.1, false, false)
	tv.process(0.1, true, false)
	_check(tv.on, "he leaves and comes back: automatic again, on")
	tv.process(0.1, false, false)
	tv.click()
	tv.process(0.1, false, false)
	_check(tv.on, "clicked on again while nobody watches")
	tv.process(0.1, false, true)
	_check(not tv.on, "the deep night turns a clicked-on TV off")
	tv.click()
	tv.process(0.1, false, true)
	_check(tv.on, "a click in the deep night turns it on")
	tv.process(0.1, false, false)
	tv.process(0.1, true, false)
	tv.process(0.1, false, false)
	_check(not tv.on, "he leaves the sofa: the automatic rule turns it off")
	tv.click()
	tv.process(0.1, true, false)
	tv.process(0.1, false, false)
	_check(not tv.on, "a clicked-on TV does not outlast his watching")
	var before: String = tv.hacks.current
	tv.hacks.advance()
	_check(tv.hacks.current != before, "the pictures still change")
	_check(Hacks.NAMES.size() >= 8, "at least eight hacks")
	var seen := {}
	var last: String = tv.hacks.current
	for i in 400:
		tv.hacks.advance()
		_check(tv.hacks.current != last, "never the same hack twice in a row")
		seen[tv.hacks.current] = true
		last = tv.hacks.current
	_check(seen.size() == Hacks.NAMES.size(), "every hack comes up")
	for n in Hacks.NAMES:
		_check(tv.hacks.has_method("_" + n), "hack %s has a drawer" % n)
	var h := Hacks.new()
	h.setup(9)
	var at := 0.0
	var changed: Array = []
	var cur: String = h.current
	for i in 36000:
		h.update(0.1, true)
		at += 0.1
		if h.current != cur:
			changed.append(at)
			cur = h.current
	var spaced := changed.size() > 8
	for i in range(1, changed.size()):
		var gap: float = changed[i] - changed[i - 1]
		spaced = spaced and gap >= 119.0 and gap <= 241.0
	_check(spaced, "a new hack every two to four minutes (%d changes in an hour)" % changed.size())
	var frozen := Hacks.new()
	frozen.setup(9)
	for i in 10:
		frozen.update(0.1, false)
	_check(frozen.t == 0.0, "an off TV runs no clock")


func _voices_logic() -> void:
	var v := Voices.new()
	v.rng.seed = 7
	v.set_batch({"Nina": {"done": ["a {thing}", "b {thing}", "c {thing}"]}})
	var last := ""
	var same := 0
	var chunks_ok := true
	for chunk in 6:
		var seen := {}
		for i in 3:
			var l := v.line("Nina", "done", "buy milk")
			seen[l] = true
			same += 1 if l == last else 0
			last = l
		chunks_ok = chunks_ok and seen.size() == 3
	_check(chunks_ok, "no line repeats until every other has been used")
	_check(same == 0, "never the same line twice in a row")
	_check(v.line("Nina", "done", "buy milk").ends_with("buy milk"), "{thing} is filled in")
	v.set_batch({"Nina": {"done": ["a {thing}", "plain"]}})
	var only_plain := true
	for i in 12:
		only_plain = only_plain and v.line("Nina", "done") == "plain"
	_check(only_plain, "a line with {thing} and no thing to name is skipped")
	v.set_batch({"Nina": {"done": ["a {thing}"]}})
	_check(v.line("Nina", "done") == "", "all lines skipped: no bubble, not a built-in")
	_check(
		Voices.short("  a   very long thing that goes on and on and on  ").length()
		<= Voices.THING_MAX,
		"a thing is trimmed to fit a bubble"
	)
	v.set_batch({"Nina": {"pet": ["x"], "muse": ["x", "y"]}})
	var first := v.line("Nina", "pet")
	_check(first == "x" and v.line("Nina", "muse") == "y", "not twice in a row across occasions")
	v.set_batch({})
	_check(
		v.line("Nina", "pet") in v._offline("Nina", "pet"),
		"nothing served: the built-in line"
	)
	_check(v.line("Nina", "pet") != v.line("Nina", "pet"), "nothing served: two pats, two lines")
	_check(v.line("Nina", "tv") == "", "nothing served and no built-in: no bubble")
	v.set_batch({"Nina": {"muse": ["served"]}})
	_check(
		v.line("Nina", "pet") in v._offline("Nina", "pet"),
		"the pet with nothing for an occasion falls back"
	)
	var mixed := false
	for i in 40:
		mixed = mixed or v.line("Nina", "muse") != "served"
	_check(not mixed, "a served occasion never mixes in a built-in")
	_check(Voices.bubble_time("hi") == 3.5, "a short line shows for the minimum")
	_check(Voices.bubble_time("x".repeat(130)) >= 8.5, "a long line stays long enough to read")
	_check(Voices.bubble_time("x".repeat(400)) == 9.0, "no bubble stays past the maximum")
	v.set_batch({"duo": [["Bob: hi"], ["Nina: one", "Argos: two"]]})
	_check(v.duo() == [["Nina", "one"], ["Argos", "two"]], "a malformed exchange is skipped")


func _card_logic() -> void:
	_check(Card.until_text(130 * 60.0) == "in 2 h 10 min", "in 2 h 10 min: " + Card.until_text(7800.0))
	_check(Card.until_text(25 * 60.0) == "in 25 min", "in 25 min")
	_check(Card.until_text(2 * 3600.0) == "in 2 h", "in 2 h")
	_check(Card.until_text(25 * 3600.0) == "in 1 day 1 h", "in 1 day 1 h")
	_check(Card.until_text(3 * 86400.0) == "in 3 days", "in 3 days")
	_check(Card.until_text(20.0) == "now", "under half a minute is now")
	var nov := Card.month_info(2026, 11)
	_check(nov["first"] == 0 and nov["days"] == 30, "November 2026 starts on a Sunday, 30 days")
	_check(Card.days_in(2028, 2) == 29 and Card.days_in(2026, 12) == 31, "days in a month")
	var from := Card.unix(2026, 11, 1)
	var to := Card.unix(2026, 12, 1)
	var days := func(list: Array) -> Array:
		return list.map(func(at): return Time.get_datetime_dict_from_unix_time(int(at))["day"])
	var due := Card.unix(2026, 11, 3, 9, 0)
	_check(days.call(Card.occurrences(due, "week", from, to)) == [3, 10, 17, 24], "every week")
	_check(days.call(Card.occurrences(due, "", from, to)) == [3], "once")
	_check(days.call(Card.occurrences(due, "day", from, to)).size() == 28, "every day from the 3rd")
	var late := Card.unix(2026, 1, 31, 9, 0)
	_check(days.call(Card.occurrences(late, "month", Card.unix(2026, 2, 1), from)).has(28), "month end")
	_check(Card.occurrences(late, "month", Card.unix(2026, 2, 1), Card.unix(2026, 3, 1)).size() == 1, "once a month")
	_every_logic()


func _every_logic() -> void:
	var days := func(list: Array) -> Array:
		return list.map(func(at): return Time.get_datetime_dict_from_unix_time(int(at))["day"])
	var nov := Card.unix(2026, 11, 1)
	var dec := Card.unix(2026, 12, 1)
	var due := Card.unix(2026, 11, 3, 9, 0)
	_check(days.call(Card.occurrences(due, "1 week", nov, dec)) == [3, 10, 17, 24], "1 week is every week")
	_check(days.call(Card.occurrences(due, "2 week", nov, dec)) == [3, 17], "every other week")
	_check(days.call(Card.occurrences(due, "6 week", nov, dec)) == [3], "every 6 weeks: one in the month")
	_check(days.call(Card.occurrences(due, "6 week", dec, Card.unix(2027, 1, 1))) == [15], "every 6 weeks lands on the 15th of December")
	_check(days.call(Card.occurrences(due, "3 day", nov, dec)) == [3, 6, 9, 12, 15, 18, 21, 24, 27, 30], "every 3 days")
	var k31 := Card.unix(2026, 1, 31, 9, 0)
	var want := {2: 28, 3: 31, 4: 30, 5: 31, 6: 30}
	for m in want:
		var got: Array = days.call(Card.occurrences(k31, "month", Card.unix(2026, m, 1), Card.unix(2026, m + 1, 1)))
		_check(got == [want[m]], "monthly from the 31st in month %d: %s" % [m, str(got)])
	var q := Card.unix(2026, 1, 15, 8, 30)
	var hits: Array = []
	for m in range(1, 13):
		hits.append(Card.occurrences(q, "3 month", Card.unix(2026, m, 1), Card.unix(2026 + m / 12, m % 12 + 1, 1)).size())
	_check(hits == [1, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0], "every 3 months: Jan, Apr, Jul, Oct (%s)" % str(hits))
	_check(Card.occurrences(due, "garbage", nov, dec) == [due], "an unknown every counts as once")
	_check(Card.every_words("week") == "every week" and Card.every_words("day") == "every day", "every week, every day")
	_check(Card.every_words("2 week") == "every other week", "2 weeks is every other week")
	_check(Card.every_words("6 week") == "every 6 weeks", "every 6 weeks")
	_check(Card.every_words("3 month") == "every 3 months", "every 3 months")
	_check(Card.every_words("1 month") == "every month", "1 month is every month")



func _when() -> void:
	var now := Time.get_unix_time_from_datetime_string("2026-11-18T12:00:00")
	var at := func(day_gap: int, hm: String) -> float:
		var p := hm.split(":")
		return float(int(now / 86400.0) + day_gap) * 86400.0 + int(p[0]) * 3600.0 + int(p[1]) * 60.0
	for case in [
		[0, "14:00", "14:00", "today is the time alone"],
		[1, "14:00", "tomorrow 14:00", "tomorrow"],
		[3, "14:00", "Sat 14:00", "within six days, the weekday"],
		[6, "09:30", "Tue 09:30", "the sixth day is still a weekday"],
		[10, "14:00", "28 Nov", "later, the date"],
		[0, "09:00", "since 09:00", "past due today"],
		[-2, "09:00", "since Mon", "past due on an earlier day"],
		[-9, "09:00", "since 9 Nov", "a week back is dated"],
	]:
		var got := When.text(at.call(case[0], case[1]), now)
		_check(got == case[2], "%s: '%s' (wanted '%s')" % [case[3], got, case[2]])
	_check(When.text(at.call(-2, "09:00"), now, "") == "Mon", "a time that is only a time has no since")


func _pet_settings() -> void:
	var path := "user://soak_pets_settings.json"
	DirAccess.remove_absolute(path)
	var a := Settings.new()
	a.store = path
	a.setup(true)
	_check(a.value("pet1") == "cat_black" and a.value("pet2") == "dog_golden", "no pet keys are the cat and the dog")
	a.put("pet1", "rabbit_white")
	a.put("pet2", Pets.NONE)
	var b := Settings.new()
	b.store = path
	b.setup(true)
	_check(b.value("pet1") == "rabbit_white" and b.value("pet2") == "none", "the pet keys round-trip")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string('{"pet1": "zebra", "zzz": 1}')
	f.close()
	var c := Settings.new()
	c.store = path
	c.setup(true)
	c.put("pet2", "pig_pink")
	_check(FileAccess.get_file_as_string(path).contains("zzz"), "other keys are kept")
	_check(Pets.kind_of(c.value("pet1"), "nina") == "cat_black", "an unknown kind is the default")
	_check(Pets.kind_of("none", "argos") == "none" and Pets.kind_of(5, "argos") == "dog_golden", "none is a kind")
	DirAccess.remove_absolute(path)
	var d := Settings.new()
	d.put("cat", "Mimi")
	d.put("pet1", "fox_red")
	_check(Settings.pets("Nina sits") == "Mimi sits" and d.value("dog") == "Argos", "names stay whatever the animal")
	d.put("cat", "")




func _pet_voices() -> void:
	var v := Voices.new()
	v.species = {"Nina": "rabbit", "Argos": "rabbit"}
	for i in 20:
		_check(v.line("Argos", "muse") != "Is Nina a small dog?", "a rabbit is no small dog")
	v.species = {"Nina": "cat", "Argos": "dog"}
	_check(v.line("Argos", "muse") == "Is Nina a small dog?", "a dog wonders")
	_check(Voices.fits("the bed is a cat's.", ["dog"]) == false and Voices.fits("anything", []), "fits")
	var pets := Pets.new()
	pets.setup("", 3)
	pets.set_kind(pets.critter("nina"), "rabbit_brown")
	_check(pets.cry(pets.critter("nina")) == "", "a rabbit has no cry")
	pets.set_kind(pets.critter("nina"), "cat_grey")
	_check(pets.cry(pets.critter("nina")) == "purr", "a cat purrs")
	pets.set_kind(pets.critter("argos"), "dog_brown")
	_check(pets.cry(pets.critter("argos")) == "bark", "a dog barks")

