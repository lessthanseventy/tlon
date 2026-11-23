extends RefCounted

# The engine's results as the money chat shows and checks them: present() turns them into plain data
# with a `*_cents_text` beside every `*_cents`, render() words that data without a model, check()
# finds the dollar amounts in a model's reply that are in no result, leads() are the sentences code
# writes itself, contradicts() the cheap word-list check of a verdict.

const U := preload("res://bank_util.gd")

const EVENTS := 40
const MONTHS := 36
const ROWS := 60
const AMOUNT := (
	"\\$\\s?(\\d[\\d,]*(?:\\.\\d+)?)([kKmMbB]\\b)?"
	+ "|(\\d[\\d,]*(?:\\.\\d+)?)\\s?(?:dollars|bucks|USD)\\b"
)
const AFFIRM := (
	"(?i)\\b(?:can afford|afford it|you can|should be fine|go for it|plenty|comfortabl[ey]"
	+ "|no issue|is covered|are covered|it covers|you're fine|you are fine|no problem|go ahead)\\b"
)
const DENY := (
	"(?i)\\b(?:can't afford|cannot|can not|won't be able|won't cover|not covered|not enough"
	+ "|don't have enough|short by|fall short|you're short|you are short|is short|overdraw"
	+ "|negative|hold off)\\b"
)
const NEGATED := (
	"(?i)\\b(?:can't|cannot|can not|won't|don't|doesn't|isn't|aren't|not|never)\\b"
	+ "(?:\\s+\\w+){0,3}"
)
const NOT_SHORT := "(?i)\\b(?:not|isn't|aren't|never|won't be)\\s+(?:be\\s+)?(?:short|negative)\\b"
const CAVEATS := {
	"pending_ignored": "Pending charges are already out of the available balance.",
	"short_history": "There is under a month of history, so everyday spending is a rough average.",
	"skipped_charge": "A charge I expected did not come.",
	"no_deposit_seen": "I have not seen a regular deposit.",
	"one_off_bills_unknown": "I cannot know about one-off bills that are not in the history.",
}


# the entries {"ask", "result"} as JSON-ready data: {"ask": ask, "result": result} each
static func present(entries: Array) -> Array:
	var out: Array = []
	for e in entries:
		var ask: Dictionary = e["ask"]
		out.append({"ask": _walk(ask), "result": _walk(_result(ask.get("ask"), e["result"]))})
	return out


static func _result(kind: Variant, result: Dictionary) -> Variant:
	if result.has("error"):
		return result
	var v: Variant = result["ok"]
	match kind:
		"forecast":
			return _horizon_note(_trim(v))
		"afford":
			var a: Dictionary = v.duplicate()
			a["with"] = _trim(v["with"])
			a["without"] = _slim(v["without"])
			return a
		"what_if":
			var w: Dictionary = v.duplicate()
			w["baseline"] = _slim(v["baseline"])
			w["changed"] = _trim(v["changed"])
			return _horizon_note(w)
		"history":
			var h: Dictionary = v.duplicate()
			var months: Array = v["months"]
			h["months"] = months.slice(maxi(0, months.size() - MONTHS))
			return h
		"subscriptions":
			return (v as Array).slice(0, ROWS)
	return v


static func _horizon_note(result: Dictionary) -> Dictionary:
	if result.get("clamped") == true:
		var r := result.duplicate()
		r["note"] = "The horizon was cut to 180 days: I can only look 180 days ahead."
		return r
	return result


static func _slim(forecast: Dictionary) -> Dictionary:
	var f := forecast.duplicate()
	f.erase("days")
	f.erase("events")
	var days: Array = forecast["days"]
	f["end"] = days.back() if not days.is_empty() else null
	return f


static func _trim(forecast: Dictionary) -> Dictionary:
	var f := _slim(forecast)
	var events: Array = forecast["events"]
	f["events"] = events.slice(0, EVENTS)
	return f


static func _walk(v: Variant) -> Variant:
	if v is Dictionary:
		var out := {}
		for key in v:
			var k := str(key)
			out[k] = _walk(v[key])
			if v[key] is int and k.ends_with("_cents"):
				out[k + "_text"] = U.money(v[key])
		return out
	if v is Array:
		return v.map(func(x: Variant) -> Variant: return _walk(x))
	return v


# {"ok": true}, or {"error": [the amounts of `reply` that are in none of `presented`'s *_text]}:
# compared in cents and without sign; a suffix ($1.2k) or over two decimals cannot be compared
# and counts as missing; only dollar amounts are looked at
static func check(reply: String, presented: Array) -> Dictionary:
	var known := {}
	for text in _texts(presented):
		for a in _amounts(text):
			if a[1] != null:
				known[a[1]] = true
	var missing: Array = []
	for a in _amounts(reply):
		var cents: Variant = a[1]
		if (cents != null and known.has(cents)) or cents == 0:
			continue
		missing.append(a[0])
	return {"ok": true} if missing.is_empty() else {"error": missing}


# [[the text, its cents or null when it cannot be compared]] for each amount in `reply`
static func _amounts(reply: String) -> Array:
	var out: Array = []
	for m in RegEx.create_from_string(AMOUNT).search_all(reply):
		var first := m.get_string(1)
		var cents: Variant
		if first != "":
			cents = _parse(first) if m.get_string(2) == "" else null
		else:
			cents = _parse(m.get_string(3))
		out.append([m.get_string(0), cents])
	return out


static func _parse(number: String) -> Variant:
	var parts := number.replace(",", "").split(".")
	if parts.size() == 1:
		return parts[0].to_int() * 100
	if parts.size() == 2 and parts[1].length() <= 2:
		return parts[0].to_int() * 100 + parts[1].rpad(2, "0").to_int()
	return null


static func _texts(v: Variant) -> Array:
	var out: Array = []
	if v is Dictionary:
		for key in v:
			if v[key] is String:
				if str(key).ends_with("_text"):
					out.append(v[key])
			else:
				out.append_array(_texts(v[key]))
	elif v is Array:
		for x in v:
			out.append_array(_texts(x))
	return out


# the presented results in plain words, one paragraph each, from the data alone
static func render(presented: Array) -> String:
	return "\n\n".join(
		PackedStringArray(presented.map(func(e: Dictionary) -> String: return _entry(e)))
	)


# the sentences code writes from the results: a purchase's verdict and a series not found
static func leads(presented: Array) -> Array:
	var out: Array = []
	for e in presented:
		var l: Variant = _lead(e)
		if l != null:
			out.append(l)
	return out


static func _lead(entry: Dictionary) -> Variant:
	var ask: Variant = entry.get("ask")
	var r: Variant = entry.get("result")
	if ask is Dictionary and ask.get("ask") == "afford" and r is Dictionary and r.has("verdict"):
		var on := _day(ask["on"]) if ask.get("on") != null else "today"
		var low: Dictionary = r["with"]["lowest"]
		var purchase := "A purchase of %s on %s" % [_t(ask.get("amount_cents_text")), on]
		var lowest := (
			"your lowest expected balance would be %s on %s"
			% [_t(low.get("balance_cents_text")), _day(low["date"]) if low.has("date") else ""]
		)
		match r["verdict"]:
			"covers":
				return "%s is covered: %s." % [purchase, lowest]
			"tight":
				return (
					(
						"%s is tight: %s, under the %s cushion."
						% [purchase, lowest, _t(r.get("cushion_cents_text"))]
					)
					+ _other(r, "lifts it to the cushion", "would not lift it to the cushion")
				)
			"short":
				return _short(purchase, r)
		return null
	if r is Dictionary and r.get("error") == "no_series" and r.has("name") and r.has("suggestions"):
		var named := 'I don\'t see a recurring charge called "%s".' % _t(r["name"])
		if r["suggestions"].is_empty():
			return named
		return named + " Did you mean %s?" % _join(" or ", r["suggestions"])
	if r is Dictionary and r.get("error") == "beyond_horizon" and ask is Dictionary:
		var date: Variant = ask.get("on")
		if date == null:
			for c in ask["changes"]:
				var d: Variant = c.get("on") if c.get("on") != null else c.get("from")
				if d != null and (date == null or d > date):
					date = d
		return "I can only look 180 days ahead, so I can't say for %s." % _day(date)
	return null


# `text` without any of `leads` that it begins with, compared by words in any case and spacing
# and with or without the closing full stop
static func drop_leads(text: String, leads: Array) -> String:
	var patterns: Array = []
	for lead in leads:
		var words: Array = []
		var body: String = lead
		while body.ends_with("."):
			body = body.left(-1)
		var spaced := RegEx.create_from_string("\\s+").sub(body.strip_edges(), " ", true)
		for w in spaced.split(" ", false):
			words.append(_escape(w))
		patterns.append(
			RegEx.create_from_string(
				"(?i)\\A\\s*" + "\\s+".join(PackedStringArray(words)) + "[.!]?\\s*"
			)
		)
	return _drop_leading(text.strip_edges(), patterns)


static func _drop_leading(text: String, patterns: Array) -> String:
	for i in patterns.size():
		if patterns[i].search(text) != null:
			var rest: Array = patterns.duplicate()
			rest.remove_at(i)
			return _drop_leading(patterns[i].sub(text, "", false), rest)
	return text


static func _escape(word: String) -> String:
	var out := ""
	for ch in word:
		out += ("\\" + ch) if ch in "\\^$*+?.|()[]{}-#/" else ch
	return out


# whether `text` says the opposite of a purchase's verdict in `presented`, by a word list:
# affirmations against short, denials against covers and tight
static func contradicts(text: String, presented: Array) -> bool:
	for e in presented:
		var ask: Variant = e.get("ask")
		var r: Variant = e.get("result")
		var afford: bool = ask is Dictionary and ask.get("ask") == "afford"
		if afford and r is Dictionary and r.get("verdict") == "short":
			if _says(AFFIRM, NEGATED, text):
				return true
		elif r is Dictionary and r.get("error") == "beyond_horizon":
			if _says(AFFIRM, NEGATED, text):
				return true
		elif afford and r is Dictionary and r.has("verdict"):
			if _says(DENY, NOT_SHORT, text):
				return true
	return false


static func _says(pattern: String, strip: String, text: String) -> bool:
	var plain := RegEx.create_from_string(strip).sub(text, " ", true)
	return RegEx.create_from_string(pattern).search(plain) != null


# the facts behind the code-written sentences of leads(), for a judge
static func facts(presented: Array) -> Array:
	var out: Array = []
	for e in presented:
		if _lead(e) == null or _beyond_horizon(e):
			continue
		var ask: Variant = e.get("ask")
		var r: Dictionary = e["result"]
		if ask is Dictionary and ask.get("ask") == "afford":
			(
				out
				. append(
					{
						"about": "can he afford a purchase",
						"verdict": r.get("verdict"),
						"purchase_text": ask.get("amount_cents_text"),
						"on": ask.get("on"),
						"shortfall_text": r.get("shortfall_cents_text"),
						"short_on": r.get("short_on"),
					}
				)
			)
		else:
			(
				out
				. append(
					{
						"about": "a series that was not found",
						"name": r["name"],
						"suggestions": r["suggestions"],
					}
				)
			)
	return out


# whether every result is a date past the horizon: nothing is left for a model to explain
static func only_beyond_horizon(presented: Array) -> bool:
	return (
		not presented.is_empty()
		and presented.all(func(e: Dictionary) -> bool: return _beyond_horizon(e))
	)


static func _beyond_horizon(entry: Dictionary) -> bool:
	var r: Variant = entry.get("result")
	return r is Dictionary and r.get("error") == "beyond_horizon"


static func _entry(e: Dictionary) -> String:
	var r: Variant = e["result"]
	var ask: Dictionary = e.get("ask", {})
	if r is Dictionary:
		match r.get("error"):
			"no_data":
				return "I have no bank data to work from yet."
			"bad_range":
				return "That date range runs backwards, so I can't look it up."
			"bad_amount":
				return "That amount can't be worked out, so I can't look it up."
			"no_series", "beyond_horizon":
				return _t(_lead(e))
	match ask.get("ask"):
		"summary":
			var parts := [
				"You have %s available in checking." % _t(r.get("available_cents_text")),
				_due(r["due_this_week"], r.get("next_deposit")),
				_deposit(r.get("next_deposit")),
			]
			return _join(" ", parts).strip_edges()
		"subscriptions":
			if r.is_empty():
				return "I see no recurring charges."
			var rows: Array = []
			for s in r:
				rows.append(
					(
						"%s %s %s, next %s"
						% [_t(s.get("name")), _abs_text(s), _t(s.get("rhythm")), _day(s["next"])]
					)
				)
			return "Recurring charges: " + _join("; ", rows) + "."
		"budget":
			return _budget(r)
		"forecast":
			return _join(" ", [_outlook(r)] + _basis(r))
		"afford":
			var parts: Array = [_lead(e)]
			if r.get("worst_case") != r.get("verdict"):
				parts.append(
					"If everyday spending runs high it would be %s." % _t(r.get("worst_case"))
				)
			parts.append_array(_basis(r["with"]))
			return _join(" ", parts.filter(func(p: Variant) -> bool: return p != null))
		"what_if":
			return _what_if(r)
		"history":
			return _history(ask, r)
	return ""


static func _what_if(r: Dictionary) -> String:
	var base: Dictionary = r["baseline"]["end"]
	var changed: Dictionary = r["changed"]["end"]
	var first := (
		(
			"As things are, your balance on %s is expected to be %s (lowest %s). "
			% [
				_day(base["date"]),
				_t(base.get("expected_cents_text")),
				_t(r["baseline"]["lowest"].get("balance_cents_text"))
			]
		)
		+ (
			"With the change it is %s (lowest %s), a difference of %s."
			% [
				_t(changed.get("expected_cents_text")),
				_t(r["changed"]["lowest"].get("balance_cents_text")),
				_t(r["difference"].get("end_cents_text")),
			]
		)
	)
	var parts: Array = [first]
	if r.get("note") != null:
		parts.append(r["note"])
	parts.append_array(_basis(r["changed"]))
	return _join(" ", parts)


static func _history(ask: Dictionary, r: Dictionary) -> String:
	var what := ""
	var names: Variant = ask.get("match")
	if names is Array and not names.is_empty():
		what = (
			" matching " + _join(", ", names.map(func(n: Variant) -> String: return '"%s"' % _t(n)))
		)
	elif names != null:
		what = ' matching "%s"' % (_t(names) if names is String else "")
	var rows: Array = []
	for m in (r["largest"] as Array).slice(0, 3):
		rows.append("%s %s on %s" % [_t(m.get("name")), _abs_text(m), _day(m["date"])])
	var largest := _join("; ", rows)
	return (
		(
			"From %s to %s%s: %s transactions, on average %s out and %s in a month."
			% [
				_day(ask["from"]),
				_day(ask["to"]),
				what,
				_t(r.get("count")),
				_t(r.get("average_out_cents_text")),
				_t(r.get("average_in_cents_text")),
			]
		)
		+ _counted(r.get("merchants", []))
		+ ("" if largest == "" else " Largest: %s." % largest)
	)


static func _budget(r: Dictionary) -> String:
	var parts: Array = []
	if r.get("until") == null:
		parts.append("I have seen no deposit, so I can't say what is spare a day.")
	elif int(r["short_cents"]) > 0:
		parts.append(
			(
				(
					"Nothing is spare until the next deposit (%s, %s): you are about %s short"
					+ " after %s of bills before it."
				)
				% [
					_t(r.get("deposit")),
					_day(r["until"]),
					_t(r.get("short_cents_text")),
					_t(r.get("bills_cents_text"))
				]
			)
		)
	else:
		parts.append(
			(
				(
					"You can spend about %s a day until the next deposit (%s, %s),"
					+ " after %s of bills before it and a %s cushion."
				)
				% [
					_t(r.get("safe_daily_cents_text")),
					_t(r.get("deposit")),
					_day(r["until"]),
					_t(r.get("bills_cents_text")),
					_t(r.get("cushion_cents_text"))
				]
			)
		)
	parts.append("Spent today: %s." % _t(r.get("spent_today_cents_text")))
	for pair in [["This week", r["weeks"][0]], ["Last week", r["weeks"][1]]]:
		var top: Array = pair[1]["top"].map(
			func(m: Dictionary) -> String:
				return "%s %s" % [_t(m.get("name")), _t(m.get("amount_cents_text"))]
		)
		parts.append(
			(
				"%s: %s in all%s."
				% [
					pair[0],
					_t(pair[1].get("total_cents_text")),
					"" if top.is_empty() else ", most at " + _join(", ", top)
				]
			)
		)
	return _join(" ", parts)


static func _outlook(r: Dictionary) -> String:
	var note := (" " + _t(r["note"])) if r.get("note") != null and r["note"] != false else ""
	return (
		(
			(
				"Your checking balance is %s today. By %s it is expected to be %s, "
				+ "and the lowest it is expected to get is %s on %s."
			)
			% [
				_t(r.get("start_cents_text")),
				_day(r["until"]),
				_t(r["end"].get("expected_cents_text")),
				_t(r["lowest"].get("balance_cents_text")),
				_day(r["lowest"]["date"]),
			]
		)
		+ note
	)


static func _basis(r: Dictionary) -> Array:
	var basis: Dictionary = r["basis"]
	var out: Array = []
	var months: Variant = basis["months_of_history"]
	out.append(
		(
			"This rests on %s of history and the charges that repeat in it."
			% ("1 month" if months == 1 else "%s months" % _t(months))
		)
	)
	var events: Array = r.get("events") if r.get("events") != null else []
	for e in events:
		if e.get("overdue") == true:
			out.append(
				(
					"%s was expected on %s and has not posted; I have kept it just ahead."
					% [_t(e.get("name")), _day(e["expected_on"])]
				)
			)
	if not (basis["skipped"] as Array).is_empty():
		out.append(
			"I left out %s: no charge has come for a long while." % _join(", ", basis["skipped"])
		)
	for c in basis["caveats"]:
		out.append(CAVEATS.get(c, ""))
	return out


static func _due(items: Array, deposit: Variant) -> String:
	if items.is_empty():
		return "Nothing recurring is due this week."
	var rows: Array = []
	for i in items:
		rows.append(
			(
				"%s %s %s%s"
				% [
					_t(i.get("name")),
					_t(i.get("amount_cents_text")),
					_day(i["on"]),
					_against(i, deposit)
				]
			)
		)
	return "Due this week: " + _join(", ", rows) + "."


static func _against(item: Dictionary, deposit: Variant) -> String:
	if deposit == null:
		return ""
	if item["on"] < deposit["on"]:
		return " (before the next deposit)"
	if item["on"] == deposit["on"]:
		return " (the same day as the next deposit)"
	return " (after the next deposit)"


static func _deposit(d: Variant) -> String:
	if d == null:
		return ""
	return (
		"Next deposit: %s, %s on %s."
		% [_t(d.get("name")), _t(d.get("amount_cents_text")), _day(d["on"])]
	)


static func _abs_text(item: Dictionary) -> String:
	return U.money(absi(int(item["amount_cents"])))


static func _short(purchase: String, r: Dictionary) -> String:
	if r.get("short_without") == true:
		var deepens := (
			"would not make it any deeper."
			if r.get("adds_cents") == 0
			else "would deepen it by %s." % _t(r.get("adds_cents_text"))
		)
		return (
			(
				"Without it your balance is already projected short by %s on %s. %s %s"
				% [
					_t(r.get("baseline_shortfall_cents_text")),
					_day(r["baseline_short_on"]),
					purchase,
					deepens,
				]
			)
			+ _other(r, "covers it", "does not cover it")
		)
	return (
		(
			"%s would leave you short by %s on %s."
			% [purchase, _t(r.get("shortfall_cents_text")), _day(r["short_on"])]
		)
		+ _other(r, "covers it", "does not cover it")
	)


static func _other(r: Dictionary, yes: String, no: String) -> String:
	var cents: Variant = r.get("other_available_cents")
	if not (cents is int or cents is float) or cents <= 0:
		return ""
	var accounts: Variant = r.get("other_accounts")
	var holds := (
		"Your other accounts hold"
		if accounts is Array and accounts.is_empty()
		else "%s holds" % _join(" and ", accounts)
	)
	return (
		" This is checking alone; %s %s, which %s."
		% [holds, _t(r.get("other_available_cents_text")), yes if r.get("covered_by_other") else no]
	)


static func _counted(merchants: Array) -> String:
	if merchants.is_empty():
		return ""
	var rows: Array = []
	for m in merchants:
		rows.append("%s %s" % [_t(m.get("name")), _totals(m)])
	return " Counted: " + _join("; ", rows) + "."


static func _totals(m: Dictionary) -> String:
	var parts: Array = []
	for pair in [[m.get("out_cents"), "out"], [m.get("in_cents"), "in"]]:
		if pair[0] != 0:
			parts.append("%s %s" % [U.money(absi(int(pair[0]))), pair[1]])
	return _join(", ", parts)


static func _join(sep: String, items: Array) -> String:
	var parts := PackedStringArray()
	for i in items:
		parts.append(_t(i))
	return sep.join(parts)


static func _t(v: Variant) -> String:
	return "" if v == null else str(v)


static func _day(iso: Variant) -> String:
	return U.day_long(iso)
