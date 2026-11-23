extends RefCounted

# The model's plan for a money question, read strictly: {"asks": [ask, ...]} (one to four) or
# {"cannot": "why"}. Dates are YYYY-MM-DD within a year ahead (a history's `from` may go ten years
# back), amounts whole cents up to $1,000,000, names and labels trimmed text: anything else is no
# plan, and nothing is guessed. Each ask is {"json": its canonical ask, "call": the engine call}.

const U := preload("res://bank_util.gd")

const MAX_ASKS := 4
const MAX_CHANGES := 10
const MAX_CENTS := 100_000_000
const MAX_NAME := 80
const MAX_MATCHES := 12
const MAX_LABEL := 40
const HORIZON := 365
const PAST := 3_650
const RHYTHMS := ["weekly", "fortnightly", "monthly", "yearly"]


# {"ok": [ask, ...]}, {"cannot": sentence} or {"error": true} for the plan in `out` as of `today`
static func parse(out: String, today: String) -> Dictionary:
	var found := RegEx.create_from_string("(?s)\\{.*\\}").search(out)
	if found == null:
		return {"error": true}
	var json := JSON.new()
	if json.parse(found.get_string()) != OK or not json.data is Dictionary:
		return {"error": true}
	return _plan(json.data, today)


static func _plan(plan: Dictionary, today: String) -> Dictionary:
	if plan.get("cannot") is String:
		var why: String = plan["cannot"].strip_edges()
		return {"error": true} if why == "" else {"cannot": why}
	var asks: Variant = plan.get("asks")
	if asks is Array and not asks.is_empty() and asks.size() <= MAX_ASKS:
		var parsed: Variant = _each(asks, func(a: Variant) -> Variant: return _ask(a, today))
		return {"error": true} if parsed == null else {"ok": parsed}
	return {"error": true}


# the parsed items, or null at the first one `fun` refuses (null)
static func _each(items: Array, fun: Callable) -> Variant:
	var out: Array = []
	for item in items:
		var parsed: Variant = fun.call(item)
		if parsed == null:
			return null
		out.append(parsed)
	return out


# a JSON number that is a whole number, as an int; null for anything else. JSON numbers arrive
# as floats, so 1500.0 is accepted as 1500.
static func _int(v: Variant) -> Variant:
	if v is int:
		return v
	if v is float and v == floorf(v) and absf(v) < 1e15:
		return int(v)
	return null


static func _ask(ask: Variant, today: String) -> Variant:
	if not ask is Dictionary:
		return null
	match ask.get("ask"):
		"summary":
			return {"json": {"ask": "summary"}, "call": {"call": "summary"}}
		"subscriptions":
			return {"json": {"ask": "subscriptions"}, "call": {"call": "subscriptions"}}
		"budget":
			return {"json": {"ask": "budget"}, "call": {"call": "budget"}}
		"forecast":
			if ask.has("until"):
				return _forecast(ask["until"], today)
		"afford":
			return _afford(ask, today)
		"what_if":
			if ask.has("until") and ask.get("changes") is Array:
				return _what_if(ask, today)
		"history":
			if ask.has("from") and ask.has("to"):
				return _history(ask, today)
	return null


static func _forecast(text: Variant, today: String) -> Variant:
	var until: Variant = _ahead(text, today)
	if until == null:
		return null
	return {
		"json": {"ask": "forecast", "until": until}, "call": {"call": "forecast", "until": until}
	}


static func _afford(ask: Dictionary, today: String) -> Variant:
	var cents: Variant = _int(ask.get("amount_cents"))
	if cents == null or cents < 1 or cents > MAX_CENTS:
		return null
	var on: Variant = null
	if ask.get("on") != null:
		on = _ahead(ask["on"], today)
		if on == null:
			return null
	return {
		"json": {"ask": "afford", "amount_cents": cents, "on": on},
		"call": {"call": "afford", "cents": cents, "on": on},
	}


static func _what_if(ask: Dictionary, today: String) -> Variant:
	var changes: Array = ask["changes"]
	if changes.is_empty() or changes.size() > MAX_CHANGES:
		return null
	var until: Variant = _ahead(ask["until"], today)
	if until == null:
		return null
	var parsed: Variant = _each(changes, func(c: Variant) -> Variant: return _change(c, today))
	if parsed == null:
		return null
	return {
		"json":
		{
			"ask": "what_if",
			"until": until,
			"changes": parsed.map(func(p: Dictionary) -> Dictionary: return p["json"]),
		},
		"call":
		{
			"call": "what_if",
			"changes": parsed.map(func(p: Dictionary) -> Dictionary: return p["change"]),
			"until": until,
		},
	}


static func _history(ask: Dictionary, today: String) -> Variant:
	var from: Variant = _date(ask["from"], U.add(today, -PAST), U.add(today, HORIZON))
	if from == null:
		return null
	var to: Variant = _date(ask["to"], from, U.add(today, HORIZON))
	if to == null:
		return null
	var matched: Variant = _match(ask.get("match"))
	if matched == null:
		return null
	var m: Variant = matched["ok"]
	return {
		"json": {"ask": "history", "match": m, "from": from, "to": to},
		"call": {"call": "history", "query": {"match": m, "from": from, "to": to}},
	}


static func _change(change: Variant, today: String) -> Variant:
	if not change is Dictionary:
		return null
	match change.get("kind"):
		"one_off":
			if not (change.has("amount_cents") and change.has("on") and change.has("name")):
				return null
			var cents: Variant = _int(change["amount_cents"])
			if cents == null or cents == 0 or absi(cents) > MAX_CENTS:
				return null
			var on: Variant = _ahead(change["on"], today)
			var name: Variant = _name(change["name"])
			if on == null or name == null:
				return null
			return {
				"json": {"kind": "one_off", "amount_cents": cents, "on": on, "name": name},
				"change": {"kind": "one_off", "cost": cents, "on": on, "name": name},
			}
		"recurring":
			var keys := ["amount_cents", "rhythm", "from", "name"]
			if not keys.all(func(k: String) -> bool: return change.has(k)):
				return null
			var cents: Variant = _int(change["amount_cents"])
			if cents == null or cents < 1 or cents > MAX_CENTS or not change["rhythm"] in RHYTHMS:
				return null
			var from: Variant = _ahead(change["from"], today)
			var name: Variant = _name(change["name"])
			if from == null or name == null:
				return null
			return {
				"json":
				{
					"kind": "recurring",
					"amount_cents": cents,
					"rhythm": change["rhythm"],
					"from": from,
					"name": name,
				},
				"change":
				{
					"kind": "recurring",
					"cost": cents,
					"rhythm": change["rhythm"],
					"from": from,
					"name": name,
				},
			}
		"drop":
			if not change.has("name"):
				return null
			var name: Variant = _name(change["name"])
			if name == null:
				return null
			return {
				"json": {"kind": "drop", "name": name}, "change": {"kind": "drop", "name": name}
			}
		"change":
			if not (change.has("name") and change.has("amount_cents")):
				return null
			var cents: Variant = _int(change["amount_cents"])
			if cents == null or cents < 1 or cents > MAX_CENTS:
				return null
			var name: Variant = _name(change["name"])
			if name == null:
				return null
			return {
				"json": {"kind": "change", "name": name, "amount_cents": cents},
				"change": {"kind": "change", "name": name, "cost": cents},
			}
	return null


static func _ahead(text: Variant, today: String) -> Variant:
	return _date(text, today, U.add(today, HORIZON))


# `text` when it is a real date in first..last (as text), else null
static func _date(text: Variant, first: String, last: String) -> Variant:
	if U.valid(text) and text >= first and text <= last:
		return text
	return null


# {"ok": the match} (null, a name or a list of labels), or null when it is not one
static func _match(texts: Variant) -> Variant:
	if texts == null:
		return {"ok": null}
	if texts is Array:
		if texts.is_empty() or texts.size() > MAX_MATCHES:
			return null
		var labels: Variant = _each(texts, func(t: Variant) -> Variant: return _text(t, MAX_LABEL))
		return null if labels == null else {"ok": labels}
	var name: Variant = _name(texts)
	return null if name == null else {"ok": name}


static func _name(text: Variant) -> Variant:
	return _text(text, MAX_NAME)


# `text` trimmed when it is one to `max_bytes` bytes, else null
static func _text(text: Variant, max_bytes: int) -> Variant:
	if not text is String:
		return null
	var trimmed: String = text.strip_edges()
	var size := trimmed.to_utf8_buffer().size()
	return trimmed if size >= 1 and size <= max_bytes else null
