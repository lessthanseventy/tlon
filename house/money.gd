extends RefCounted

# The money the home keeps in sight: the rules that need no scene (the envelope's three states,
# how a forecast is bucketed into days, the lowest-point sentence, the one way a sum is worded) and
# the piggy bank drawn in the room. `money` is `GET /api/home`'s key of that name, null when the
# bank is off; a forecast is `GET /api/home/money/forecast`. Dates are local "YYYY-MM-DD", amounts
# cents (money out negative in a forecast, a magnitude in `due_this_week`).
const PetThings := preload("res://pet_things.gd")
const When := preload("res://when.gd")

# the placed piece the piggy bank is, in the layout
const PIECE := "piggy_bank"
const SCALE := 0.55
# the points round the pig and its envelope, in the pig's own pixels from the cell's centre
const HIT := [
	Vector2(-22, -14),
	Vector2(-17, -22),
	Vector2(0, -25),
	Vector2(10, -24),
	Vector2(18, -19),
	Vector2(24, -10),
	Vector2(24, 2),
	Vector2(-20, 2),
	Vector2(-23, -6),
]
const SOON := 5
const STRIP_MIN := 7
const STRIP_MAX := 14
const WEEKDAYS := ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
const RHYTHMS := {
	"weekly": "weekly",
	"fortnightly": "every two weeks",
	"monthly": "monthly",
	"yearly": "yearly",
	"once": "once",
}
const PINK := Color("f0a5b8")
const PINK_DARK := Color("d9809a")
const SNOUT := Color("f8c6d2")
const PLUM := Color("5a3040")
const GOLD := Color("e8c77a")
const PAPER := Color("f6efe0")
const AMBER := Color("e3a33c")


# `$1,200` for whole dollars, `$14.99` otherwise, `-$40` below zero
static func fmt(cents: Variant) -> String:
	var n := roundi(float(cents))
	if n < 0:
		return "-" + fmt(-n)
	var digits := str(floori(n / 100.0))
	var out := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += ","
		out += digits[i]
	return "$" + out + ("" if n % 100 == 0 else ".%02d" % (n % 100))


# an estimate worded to the whole dollar: `-$826`, `$1,240`
static func fmt_whole(cents: Variant) -> String:
	return fmt(roundi(float(cents) / 100.0) * 100)


# a forecast's amount with its direction: "+$2,400" in, "-$1,200" out
static func signed(cents: Variant) -> String:
	return ("+" if roundi(float(cents)) > 0 else "") + fmt(cents)


# the recurring charges due today or within `SOON` days, soonest first: {name, cents, on, days}
static func soon(money: Variant, today: String) -> Array:
	var out: Array = []
	if not (money is Dictionary and money.get("due_this_week") is Array):
		return out
	for row in money["due_this_week"]:
		var days := When.days_between(today, str(row["on"]))
		if days >= 0 and days <= SOON:
			out.append(
				{
					"name": str(row["name"]),
					"cents": roundi(float(row["amount"])),
					"on": str(row["on"]),
					"days": days
				}
			)
	out.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return [a["days"], a["name"]] < [b["days"], b["name"]]
	)
	return out


# "none" with nothing due soon, "due" while the available balance holds it, else "short"
static func envelope(money: Variant, today: String) -> String:
	var due := soon(money, today)
	if due.is_empty():
		return "none"
	var have: Variant = money.get("available")
	if have == null:
		have = money.get("balance")
	if have == null:
		return "due"
	var total := 0
	for d in due:
		total += int(d["cents"])
	return "short" if roundi(float(have)) < total else "due"


# Home's one row in Today, "" when nothing is due soon: "Rent $1,200 due Fri"
static func today_row(money: Variant, today: String) -> String:
	var due := soon(money, today)
	if due.is_empty():
		return ""
	var first: Dictionary = due[0]
	return "%s %s due %s" % [first["name"], fmt(first["cents"]), When.day_word(first["on"], today)]


# the quieter line under it when more than one charge is due: "and 1 more", else ""
static func today_more(money: Variant, today: String) -> String:
	var n := soon(money, today).size() - 1
	return "and %d more" % n if n > 0 else ""


# the days from tomorrow the strip draws: through the next deposit, `STRIP_MIN` to `STRIP_MAX`
static func span(forecast: Dictionary, today: String) -> int:
	var basis: Variant = forecast.get("basis")
	var deposit: Variant = basis.get("next_deposit") if basis is Dictionary else null
	if not deposit is Dictionary:
		return STRIP_MIN
	return clampi(When.days_between(today, str(deposit["date"])), STRIP_MIN, STRIP_MAX)


# one entry a day from tomorrow through the span, each {date, events: [{name, cents, kind}]}
static func strip(forecast: Dictionary, today: String) -> Array:
	var days: Array = []
	for i in range(1, span(forecast, today) + 1):
		days.append({"date": When.add_days(today, i), "events": []})
	var events: Variant = forecast.get("events")
	for e in events if events is Array else []:
		for d in days:
			if d["date"] == str(e["date"]):
				var cents := roundi(float(e["amount_cents"]))
				d["events"].append(
					{
						"name": str(e["name"]),
						"cents": cents,
						"kind": str(e.get("kind", "deposit" if cents > 0 else "charge"))
					}
				)
	return days


# a forecast to draw from what an answer's `figures` hold: the forecast itself, a purchase's
# "with", else {}
static func forecast_of(figures: Variant) -> Dictionary:
	if not figures is Dictionary:
		return {}
	if figures.get("days") is Array and figures.get("events") is Array:
		return figures
	var with: Variant = figures.get("with")
	if with is Dictionary and with.get("days") is Array and with.get("events") is Array:
		return with
	return {}


static func _deposit_word(date: String, today: String) -> String:
	var gap := When.days_between(today, date)
	if gap == 1:
		return "tomorrow's"
	if gap > 1 and gap <= 6:
		var at := Time.get_unix_time_from_datetime_string(date + "T00:00:00")
		return WEEKDAYS[Time.get_datetime_dict_from_unix_time(int(at))["weekday"]] + "'s"
	var d := Time.get_datetime_dict_from_unix_time(
		int(Time.get_unix_time_from_datetime_string(date + "T00:00:00"))
	)
	return "the " + When.date(d)


# "tomorrow", "on Fri", "on 25 Nov"
static func _on(date: String, today: String) -> String:
	var word := When.day_word(date, today)
	return word if word in ["today", "tomorrow"] else "on " + word


# the savings' name for a sentence: the account's own when there is one, else "Savings"
static func savings_name(forecast: Dictionary) -> String:
	var names: Variant = forecast.get("other_accounts")
	return str(names[0]) if names is Array and names.size() == 1 else "Savings"


# "Lowest point before Friday's deposit: about $312." Below zero it says so plainly with the day
# and, when the savings cover it, what they hold. "" when there is no lowest point.
static func lowest_line(forecast: Dictionary, today: String) -> String:
	var basis: Variant = forecast.get("basis")
	var deposit: Variant = basis.get("next_deposit") if basis is Dictionary else null
	var low: Variant = forecast.get("before_next_deposit")
	var lead := ""
	if low is Dictionary and deposit is Dictionary:
		lead = "Lowest point before %s deposit" % _deposit_word(str(deposit["date"]), today)
	else:
		low = forecast.get("lowest")
		if not low is Dictionary:
			return ""
		lead = "Lowest point in the next %d days" % When.days_between(today, str(forecast["until"]))
	var cents := roundi(float(low["balance_cents"]))
	if cents >= 0:
		return "%s: about %s." % [lead, fmt_whole(cents)]
	var text := (
		"%s: about %s, %s. That is below zero."
		% [lead, fmt_whole(cents), _on(str(low["date"]), today)]
	)
	var held := roundi(float(forecast.get("other_available_cents", 0)))
	if held >= -cents:
		text += " %s holds %s, which covers it." % [savings_name(forecast), fmt_whole(held)]
	return text


# "" for a price that did not go up, else "was $9.99"
static func was_line(sub: Dictionary) -> String:
	var was: Variant = sub.get("was_cents")
	if was == null or absi(roundi(float(was))) >= absi(roundi(float(sub["amount_cents"]))):
		return ""
	return "was " + fmt(absi(roundi(float(was))))


static func rhythm_word(rhythm: String) -> String:
	return RHYTHMS.get(rhythm, rhythm)


# a summary as staged for the demo and the soak: `due_this_week` and `next_deposit` rows carry
# `in_days` where the server sends `on`, so a staged day never goes stale
static func staged_summary(spec: Dictionary, today: String) -> Dictionary:
	var out := spec.duplicate(true)
	var dated := func(row: Dictionary) -> Dictionary:
		var made := row.duplicate()
		made["on"] = When.add_days(today, int(made["in_days"]))
		made.erase("in_days")
		return made
	out["due_this_week"] = (spec.get("due_this_week", []) as Array).map(dated)
	out["next_deposit"] = (
		dated.call(spec["next_deposit"]) if spec.get("next_deposit") is Dictionary else null
	)
	return out


# a forecast as the server answers it, from a spec: `start_cents`, `everyday_cents` a day, `ahead`
# days (45), `events` [{in_days, kind, name, amount_cents, rhythm?}], `subscriptions` [{name,
# amount_cents, rhythm, in_days, was_cents?}], `other_available_cents`, `other_accounts`
static func staged_forecast(spec: Dictionary, today: String) -> Dictionary:
	var events: Array = []
	for e in spec.get("events", []):
		var row := {
			"date": When.add_days(today, int(e["in_days"])),
			"amount_cents": e["amount_cents"],
			"name": e["name"],
			"kind": e["kind"],
			"rhythm": e.get("rhythm", "monthly"),
			"count": 3,
			"overdue": false,
			"expected_on": null,
		}
		events.append(row)
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["date"] < b["date"])
	var every := int(spec.get("everyday_cents", 0))
	var running := int(spec["start_cents"])
	var days: Array = []
	for i in int(spec.get("ahead", 45)) + 1:
		var date := When.add_days(today, i)
		for e in events:
			if e["date"] == date:
				running += int(e["amount_cents"])
		var expected := running - i * every
		days.append(
			{
				"date": date,
				"low_cents": expected,
				"expected_cents": expected,
				"high_cents": expected
			}
		)
	var deposit: Variant = null
	for e in events:
		if e["kind"] == "deposit":
			deposit = {"name": e["name"], "date": e["date"], "overdue": false}
			break
	var before: Variant = null
	if deposit != null:
		before = _lowest(
			days.filter(func(d: Dictionary) -> bool: return d["date"] < deposit["date"])
		)
	var subs: Array = []
	for sub in spec.get("subscriptions", []):
		(
			subs
			. append(
				{
					"name": sub["name"],
					"amount_cents": sub["amount_cents"],
					"rhythm": sub["rhythm"],
					"next": When.add_days(today, int(sub["in_days"])),
					"count": 3,
					"was_cents": sub.get("was_cents"),
				}
			)
		)
	return {
		"start_cents": spec["start_cents"],
		"until": days[-1]["date"],
		"clamped": false,
		"days": days,
		"events": events,
		"everyday":
		{"expected_daily_cents": every, "low_daily_cents": every, "high_daily_cents": every},
		"lowest": _lowest(days),
		"before_next_deposit": before,
		"other_available_cents": spec.get("other_available_cents", 0),
		"other_accounts": spec.get("other_accounts", []),
		"basis": {"next_deposit": deposit, "skipped": [], "caveats": []},
		"subscriptions": subs,
	}


static func _lowest(days: Array) -> Dictionary:
	var low: Dictionary = days[0]
	for d in days:
		if d["expected_cents"] < low["expected_cents"]:
			low = d
	return {"date": low["date"], "balance_cents": low["expected_cents"]}


# the catalogue row of the piggy bank
static func entry() -> Dictionary:
	return {
		"key": PIECE,
		"name": "piggy bank",
		"kind": "floor",
		"anim": false,
		"faces": [],
		"tab": "home",
		"group": "living",
		"order": 1 * 1000 + 61,
	}


static func is_piggy(p: Dictionary) -> bool:
	return p["p"] == PIECE


static func _ellipse(
	s: PetThings.Pen, a: Vector2, cx: float, cy: float, rx: float, ry: float, color: Color
) -> void:
	var pts: Array = []
	for i in 24:
		var t := TAU * i / 24.0
		pts.append((a + Vector2(cx + cos(t) * rx, cy + sin(t) * ry) * s.k).round())
	s.poly(pts, color)


# a shape with a one pixel outline: the outline colour first, a little larger
static func _blob(
	s: PetThings.Pen, a: Vector2, cx: float, cy: float, rx: float, ry: float, color: Color
) -> void:
	_ellipse(s, a, cx, cy, rx + 1.0, ry + 1.0, PLUM)
	_ellipse(s, a, cx, cy, rx, ry, color)


static func _rect(
	s: PetThings.Pen, a: Vector2, x: float, y: float, w: float, h: float, color: Color
) -> void:
	s.c.draw_rect(Rect2((a + Vector2(x, y) * s.k).round(), Vector2(w, h) * s.k), s.col(color))


static func _pts(s: PetThings.Pen, a: Vector2, pts: Array) -> Array:
	return pts.map(func(v: Vector2) -> Vector2: return (a + v * s.k).round())


# the pig's outline on screen, for its hit and its hover
static func outline(pen: PetThings.Pen) -> PackedVector2Array:
	var a := pen.p(0.5, 0.5, 0.0)
	var pts := PackedVector2Array()
	for v in HIT:
		pts.append((a + v * pen.k * SCALE).round())
	return Geometry2D.convex_hull(pts)


# a pig in profile facing left, a coin standing in its slot; `envelope` ("none", "due" or "short")
# leans an envelope against its side, paper while the balance holds the charge and amber when it
# will not
static func piggy(pen: PetThings.Pen, envelope: String) -> void:
	var a := pen.p(0.5, 0.5, 0.0)
	var s := PetThings.Pen.new(pen.c, pen.o, pen.k * SCALE, pen.flip, pen.tint)
	_ellipse(s, a, 1.0, 0.0, 16.0, 4.0, Color(0, 0, 0, 0.16))
	for x in [-5.0, 3.0]:
		_rect(s, a, x - 1.0, -8.0, 6.0, 9.0, PLUM)
		_rect(s, a, x, -7.0, 4.0, 7.0, PINK_DARK.darkened(0.12))
	_ellipse(s, a, 2.5, -21.4, 3.4, 3.4, PLUM)
	_ellipse(s, a, 2.5, -21.4, 2.4, 2.4, GOLD)
	_blob(s, a, 1.0, -11.0, 13.5, 9.5, PINK)
	_ellipse(s, a, -1.0, -15.8, 5.0, 1.7, PINK.lightened(0.28))
	for x in [-10.0, 7.0]:
		_rect(s, a, x - 1.0, -8.0, 6.5, 9.0, PLUM)
		_rect(s, a, x, -7.0, 4.5, 7.0, PINK)
		_rect(s, a, x, -1.6, 4.5, 1.6, PINK_DARK)
	_rect(s, a, -3.0, -20.3, 9.0, 1.8, PLUM)
	var tail: Array = _pts(
		s, a, [Vector2(14, -13), Vector2(16.5, -15), Vector2(15.5, -17.5), Vector2(17.8, -18.6)]
	)
	for i in tail.size() - 1:
		s.c.draw_line(tail[i], tail[i + 1], s.col(PLUM), maxf(1.0, round(1.6 * s.k)))
	_blob(s, a, -12.0, -12.0, 6.8, 6.6, PINK)
	s.poly(_pts(s, a, [Vector2(-12, -19.6), Vector2(-7.0, -20.8), Vector2(-8.2, -14.4)]), PLUM)
	s.poly(
		_pts(s, a, [Vector2(-11.2, -18.4), Vector2(-8.0, -19.2), Vector2(-8.8, -15.6)]), PINK_DARK
	)
	_blob(s, a, -18.2, -10.6, 3.3, 3.6, SNOUT)
	for y in [-11.6, -9.6]:
		s.c.draw_circle((a + Vector2(-18.8, y) * s.k).round(), 0.75 * s.k, s.col(PLUM))
	s.c.draw_circle((a + Vector2(-13.6, -14.0) * s.k).round(), 1.05 * s.k, s.col(PLUM))
	_ellipse(s, a, -9.4, -9.4, 1.9, 1.5, PINK_DARK)
	if envelope != "none":
		_envelope(s, a, envelope)


# a card propped on the floor with its top leant on the pig's flank, a flap folded across it
static func _envelope(s: PetThings.Pen, a: Vector2, state: String) -> void:
	var paper := AMBER if state == "short" else PAPER
	var fold := paper.darkened(0.28)
	var card: Array = _pts(
		s, a, [Vector2(10, 0.5), Vector2(23.5, 0.5), Vector2(21.5, -9.5), Vector2(8.5, -10.5)]
	)
	s.poly(card, paper)
	s.outline(card, PLUM)
	var flap: Array = _pts(s, a, [Vector2(8.5, -10.5), Vector2(21.5, -9.5), Vector2(15.4, -4.2)])
	s.c.draw_polyline(PackedVector2Array(flap), s.col(fold), maxf(1.0, round(0.9 * s.k)))
	s.c.draw_circle((a + Vector2(15.4, -4.2) * s.k).round(), 0.9 * s.k, s.col(fold))
