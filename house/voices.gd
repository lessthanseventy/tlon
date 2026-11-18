extends RefCounted

const Settings := preload("res://settings.gd")
const THING_MAX := 32
const BUBBLE_MIN := 3.5
const BUBBLE_MAX := 9.0
# a line that only fits one species is left out for any other (the house's own, not the server's)
const SPECIES := {
	"Is Nina a small dog?": "dog",
	"the bed is a cat's.": "cat",
	"the cat has opinions.": "cat",
}

# Last resort: only when the server has given nothing for that pet and occasion.
const FALLBACK := {
	"Nina":
	{
		"pet": ["I permit this."],
		"wake": ["I was not asleep, peasant."],
		"muse": ["Still the smartest one here."],
		"old": ["It fell. I saw nothing."],
		"visitor": ["I have seen worse.", "hm. unimpressed."],
	},
	"Argos":
	{
		"pet": ["Me? Good? Me!"],
		"muse": ["Is Nina a small dog?"],
		"done": ["Done! Done! What was it?"],
		"home": ["You're back! Who are you?"],
		"visitor": ["is it friendly?", "hello?? hello monster?"],
	},
}

# what a species says when the server has said nothing, beside the pet's own fallback
const OWN := {
	"rabbit":
	{
		"pet": ["thump. yes.", "soft paws. thank you."],
		"wake": ["twitch. I'm up."],
		"muse": ["carrot thoughts."],
	},
	"fox":
	{
		"pet": ["hehe. clever hands.", "I knew you'd come."],
		"wake": ["one ear was awake."],
		"muse": ["I have a plan. it is a nap."],
	},
	"chicken":
	{
		"pet": ["bwak. acceptable.", "cluck. again."],
		"wake": ["bawk? is it seeds?"],
		"muse": ["I may lay something. no hurry."],
	},
	"pig":
	{
		"pet": ["oink. more belly.", "snuffle. yes."],
		"wake": ["mmph. breakfast?"],
		"muse": ["mud would be nice. the rug will do."],
	},
	"sheep":
	{
		"pet": ["baa. soft hands.", "baa. you smell of tea."],
		"wake": ["baa? I counted myself."],
		"muse": ["I am a cloud with legs."],
	},
	"cow":
	{
		"pet": ["moo. thank you.", "a good scratch. moo."],
		"wake": ["mm? is it grass?"],
		"muse": ["chewing. thinking. chewing."],
	},
	"horse":
	{
		"pet": ["yes. there. my mane thanks you.", "hm. noble of you."],
		"wake": ["hay? is it hay?"],
		"muse": ["I could gallop. I won't."],
	},
	"deer":
	{
		"pet": ["...ah. okay.", "gentle. keep going."],
		"wake": ["who is there? oh. you."],
		"muse": ["quiet is a skill."],
	},
	"bear":
	{
		"pet": ["grr. that is a yes.", "mm. paw there."],
		"wake": ["I am hibernating. nicely."],
		"muse": ["snack?"],
	},
	"wolf":
	{
		"pet": ["awoo, quietly.", "pack. you are pack."],
		"wake": ["I heard it first."],
		"muse": ["someone should howl."],
	},
	"boar":
	{
		"pet": ["snort. fine.", "hrm. more."],
		"wake": ["snrk. what."],
		"muse": ["I root. there is nothing to root. I root anyway."],
	},
}

# what a personality says offline, beside the species' lines; the two the house began with also
# keep the lines of the pet they belong to
const ROLE_PERSONALITY := {"Nina": "sassy", "Argos": "sweet"}
const PERSONA := {
	"sassy":
	{
		"pet": ["Fine. Two more.", "You may continue."],
		"wake": ["Do not narrate my naps."],
		"muse": ["I am right. It is tiring."],
		"visitor": ["Another one. How tedious.", "hm. unimpressed."],
	},
	"sweet":
	{
		"pet": ["More! please!", "I love this. I love you."],
		"wake": ["Oh! hi! I was dreaming of you."],
		"muse": ["Everything is nice."],
		"visitor": ["Hello! Hello! Who are you?", "is it friendly?"],
	},
	"lazy":
	{
		"pet": ["mm. a little left.", "yes. do not stop. do not move."],
		"wake": ["five more minutes. a year."],
		"muse": ["...", "the floor is good."],
		"visitor": ["...visitor? tell me later."],
	},
	"mischievous":
	{
		"pet": ["pet me and I take your pen.", "hehe. distracted."],
		"wake": ["I was plotting."],
		"muse": ["something is about to fall."],
		"visitor": ["I will hide their shoe."],
	},
	"shy":
	{
		"pet": ["oh. ...okay.", "...thank you."],
		"wake": ["oh. you saw me."],
		"muse": ["I like it quiet."],
		"visitor": ["...is it safe?", "I will be over there."],
	},
	"bold":
	{
		"pet": ["Of course. I am excellent.", "Yes! Again! Louder!"],
		"wake": ["Up! What are we conquering?"],
		"muse": ["I could do anything today."],
		"visitor": ["Halt! Who goes there?", "I'll greet them."],
	},
}

var batch := {}
var rng := RandomNumberGenerator.new()
# each pet's species by name, kept by `Pets.set_kind`
var species := {"Nina": "cat", "Argos": "dog"}
# each pet's personality by name, kept by `Pets.set_persona`
var personality := ROLE_PERSONALITY.duplicate()

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
		return _pick("fb|" + who + "|" + occasion, _offline(who, occasion), thing, who)
	return _pick(who + "|" + occasion, served, thing, who)


func _offline(who: String, occasion: String) -> Array:
	var pool: Array = []
	if personality.get(who) == ROLE_PERSONALITY.get(who):
		pool.append_array(FALLBACK.get(who, {}).get(occasion, []))
	else:
		pool.append_array(PERSONA.get(personality.get(who, ""), {}).get(occasion, []))
	pool.append_array(OWN.get(species.get(who, ""), {}).get(occasion, []))
	return pool


# whether a line of the house's own suits one of these species
static func fits(text: String, kinds: Array) -> bool:
	return not SPECIES.has(text) or SPECIES[text] in kinds


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


func _pick(key: String, pool: Array, thing: String, who: String) -> String:
	var usable := pool.filter(
		func(l):
			return (
				(thing != "" or not "{thing}" in l)
				and (Settings.person != "" or not "{name}" in l)
				and fits(l, [species.get(who, "")])
			)
	)
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
	return text.replace("{thing}", short(thing)).replace("{name}", Settings.person)
