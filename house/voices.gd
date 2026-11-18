extends RefCounted

const THING_MAX := 32
const BUBBLE_MIN := 3.5
const BUBBLE_MAX := 9.0

# Last resort: only when the server has given nothing for that pet and occasion.
const FALLBACK := {
	"Nina":
	{
		"pet": ["I permit this."],
		"wake": ["I was not asleep, peasant."],
		"muse": ["Still the smartest one here."],
		"old": ["It fell. I saw nothing."],
	},
	"Argos":
	{
		"pet": ["Me? Good? Me!"],
		"muse": ["Is Nina a small dog?"],
		"done": ["Done! Done! What was it?"],
		"home": ["You're back! Who are you?"],
	},
}

var batch := {}
var rng := RandomNumberGenerator.new()

var _used := {}
var _last := ""


func set_batch(b: Dictionary) -> void:
	batch = b
	_used = {}


func has_any() -> bool:
	for who in ["Nina", "Argos"]:
		var theirs: Variant = batch.get(who)
		if theirs is Dictionary:
			for occasion in theirs:
				if theirs[occasion] is Array and not theirs[occasion].is_empty():
					return true
	return batch.get("duo") is Array and not batch["duo"].is_empty()


func line(who: String, occasion: String, thing: String = "") -> String:
	var served: Array = []
	var theirs: Variant = batch.get(who)
	if theirs is Dictionary and theirs.get(occasion) is Array:
		for l in theirs[occasion]:
			if l is String and l.strip_edges() != "":
				served.append(l)
	if served.is_empty():
		return _pick("fb|" + who + "|" + occasion, FALLBACK.get(who, {}).get(occasion, []), thing)
	return _pick(who + "|" + occasion, served, thing)


func duo() -> Array:
	var ok: Array = []
	var all: Variant = batch.get("duo")
	if not all is Array:
		return []
	for i in all.size():
		if _turns(all[i]).size() > 0:
			ok.append(i)
	if ok.is_empty():
		return []
	var fresh := ok.filter(func(i): return not (_used.get("duo", []) as Array).has(i))
	if fresh.is_empty():
		_used["duo"] = []
		fresh = ok
	var pick: int = fresh[rng.randi() % fresh.size()]
	var used: Array = _used.get("duo", [])
	used.append(pick)
	_used["duo"] = used
	return _turns(all[pick])


static func bubble_time(text: String) -> float:
	return clampf(1.2 + text.length() * 0.06, BUBBLE_MIN, BUBBLE_MAX)


static func short(thing: String) -> String:
	var t := " ".join(thing.split(" ", false)).strip_edges()
	return t if t.length() <= THING_MAX else t.substr(0, THING_MAX - 3).strip_edges() + "..."


static func _turns(exchange: Variant) -> Array:
	var out: Array = []
	if not exchange is Array or exchange.is_empty():
		return out
	for t in exchange:
		if not t is String:
			return []
		var who := ""
		for name in ["Nina", "Argos"]:
			if t.begins_with(name + ":"):
				who = name
		var text: String = t.substr(who.length() + 1).strip_edges() if who != "" else ""
		if text == "":
			return []
		out.append([who, text])
	return out


func _pick(key: String, pool: Array, thing: String) -> String:
	var usable := pool.filter(func(l): return thing != "" or not "{thing}" in l)
	if usable.is_empty():
		return ""
	var used: Array = _used.get(key, [])
	var fresh := usable.filter(func(l): return not used.has(l))
	if fresh.is_empty():
		used = []
		fresh = usable
	var apart := fresh.filter(func(l): return _fill(l, thing) != _last)
	if not apart.is_empty():
		fresh = apart
	var pick: String = fresh[rng.randi() % fresh.size()]
	used.append(pick)
	_used[key] = used
	_last = _fill(pick, thing)
	return _last


func _fill(text: String, thing: String) -> String:
	return text.replace("{thing}", short(thing))
