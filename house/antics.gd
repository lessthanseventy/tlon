extends RefCounted

# What a pet gets up to now and then, as a table: ANTICS names who may do it (`who`: species by
# weight, `pers`: personality multipliers), when (`hours`, `wx`, `need`), how long (`dur`), where it
# walks first (`go`, spots or an @token), the moves (`pose`, defaults to the name), an optional line
# (LINES) and sound (`cue`). One antic runs at a time, never over a card, form, menu or ring. To add
# one: a row here, a branch in `_pose` if its moves are new, lines in LINES.
const Pets := preload("res://pets.gd")

const GAP := Vector2(120.0, 240.0)
const RATE := {"few": 0.5, "some": 1.0, "lots": 2.5}
const LEG_MAX := 25.0
const SAY_CHANCE := 0.55
const GROUND := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]
const ANTICS := {
	"loaf":
	{"who": {"cat": 1.5}, "dur": [7.0, 12.0], "e": "lo", "pers": {"lazy": 2.0, "bold": 0.5}},
	"slow_blink": {"who": {"cat": 1.4}, "dur": [3.2, 4.4], "pers": {"sweet": 2.0, "sassy": 0.7}},
	"knead": {"who": {"cat": 1.0}, "go": ["sofa"], "dur": [5.0, 8.0], "e": "lo"},
	"bird_chatter": {"who": {"cat": 4.0}, "need": "bird", "go": ["sill"], "dur": [6.0, 9.0]},
	"pounce":
	{
		"who": {"cat": 1.2, "fox": 1.5, "dog": 0.4},
		"dur": [2.8, 3.4],
		"e": "hi",
		"pers": {"mischievous": 2.5, "lazy": 0.3, "bold": 1.4}
	},
	"stretch":
	{"who": {"*": 1.0}, "hours": [5.5, 11.0], "dur": [2.6, 3.6], "wakes": true, "w": 1.5},
	"wall_stare": {"who": {"cat": 1.0}, "go": ["corner"], "dur": [6.0, 9.0], "pers": {"lazy": 1.5}},
	"witching":
	{"who": {"cat": 1.2}, "hours": [19.5, 23.5], "scene": "zoomies", "dur": [1.0, 1.0], "e": "hi"},
	"yowl": {"who": {"cat": 1.0}, "hours": [23.5, 4.0], "dur": [3.0, 3.6], "cue": "meow"},
	"tail_chase":
	{
		"who": {"dog": 1.6, "wolf": 0.8, "fox": 1.0},
		"go": ["mid"],
		"dur": [6.5, 8.0],
		"e": "hi",
		"pers": {"sweet": 2.0, "mischievous": 2.0, "bold": 1.4, "lazy": 0.3, "sassy": 0.5}
	},
	"play_bow":
	{
		"who": {"dog": 1.4, "wolf": 0.6, "fox": 0.8},
		"dur": [3.4, 4.4],
		"e": "hi",
		"pers": {"sweet": 1.8, "mischievous": 1.8, "lazy": 0.3}
	},
	"roll_over": {"who": {"dog": 1.2, "fox": 0.8, "wolf": 0.5}, "go": ["rug"], "dur": [3.6, 4.6]},
	"ear_scratch": {"who": {"dog": 1.4, "wolf": 1.0, "fox": 1.0}, "dur": [2.6, 3.6]},
	"sniff_line": {"who": {"dog": 1.4, "wolf": 1.2, "fox": 1.2}, "go": ["lamp"], "dur": [5.0, 7.0]},
	"head_tilt":
	{"who": {"dog": 1.5, "wolf": 0.8, "fox": 1.0}, "dur": [3.2, 4.4], "pers": {"sweet": 1.6}},
	"door_bark":
	{
		"who": {"dog": 1.0},
		"go": ["door_in"],
		"dur": [5.0, 6.0],
		"cue": "cry",
		"pers": {"bold": 2.0, "sweet": 1.5, "shy": 0.3}
	},
	"carry_bone":
	{
		"who": {"dog": 1.0, "wolf": 0.8, "fox": 0.8},
		"need": "bone",
		"go": ["bone", "mid", "lounge", "bone"],
		"carry": "bone",
		"dur": [0.6, 0.9],
		"pers": {"sweet": 1.5}
	},
	"three_circles":
	{
		"who": {"dog": 1.2, "wolf": 1.0, "fox": 1.0},
		"go": ["rug"],
		"dur": [9.0, 10.0],
		"keep": true,
		"e": "lo"
	},
	"dream":
	{
		"who": {"dog": 1.0, "wolf": 1.0, "fox": 1.0, "cat": 0.8},
		"need": "asleep",
		"dur": [5.0, 6.5],
		"keep": true,
		"w": 1.4
	},
	"binky":
	{
		"who": {"rabbit": 2.0},
		"dur": [2.2, 2.8],
		"e": "hi",
		"pers": {"sweet": 1.6, "bold": 1.4, "lazy": 0.4}
	},
	"bunny_flop": {"who": {"rabbit": 1.5}, "dur": [3.4, 4.2], "e": "lo"},
	"thump": {"who": {"rabbit": 1.2}, "dur": [2.2, 2.8], "pers": {"sassy": 1.8, "bold": 1.8}},
	"nose_wiggle": {"who": {"rabbit": 1.5}, "dur": [2.4, 3.2]},
	"periscope": {"who": {"rabbit": 1.5}, "dur": [3.2, 4.4], "pers": {"shy": 1.5}},
	"scratch_peck": {"who": {"chicken": 2.0}, "dur": [5.0, 7.0]},
	"dust_bath": {"who": {"chicken": 1.2}, "dur": [4.5, 6.0], "e": "lo"},
	"flap_run":
	{"who": {"chicken": 1.2}, "go": ["mid", "lounge"], "run": true, "dur": [1.4, 2.0], "e": "hi"},
	"lay_egg": {"who": {"chicken": 1.0}, "go": ["corner"], "dur": [4.5, 5.5], "e": "lo", "w": 1.2},
	"roost": {"who": {"chicken": 1.0}, "go": ["sofa"], "dur": [9.0, 14.0], "e": "lo"},
	"root_floor": {"who": {"pig": 2.0, "boar": 2.0}, "go": ["rug2"], "dur": [5.0, 7.0]},
	"happy_spin":
	{
		"who": {"pig": 1.5, "boar": 0.8},
		"dur": [3.0, 3.8],
		"e": "hi",
		"pers": {"sweet": 1.8, "lazy": 0.3}
	},
	"flop_nap": {"who": {"pig": 1.5, "boar": 1.0}, "dur": [9.0, 13.0], "keep": true, "e": "lo"},
	"bin_snuffle": {"who": {"pig": 1.2, "boar": 1.2}, "go": ["nook"], "dur": [4.5, 6.0]},
	"graze":
	{
		"who": {"sheep": 2.0, "cow": 2.0, "horse": 1.5, "deer": 1.5},
		"go": ["rug"],
		"dur": [6.0, 9.0]
	},
	"slow_chew":
	{"who": {"sheep": 1.5, "cow": 2.0, "horse": 0.8, "deer": 0.8}, "dur": [4.5, 6.0], "e": "lo"},
	"stamp": {"who": {"sheep": 0.8, "cow": 1.0, "horse": 1.5, "deer": 1.0}, "dur": [2.2, 3.0]},
	"horse_trot":
	{"who": {"horse": 2.0}, "go": ["mid", "lounge"], "run": true, "dur": [1.6, 2.2], "e": "hi"},
	"deer_freeze":
	{"who": {"deer": 2.0}, "go": ["lamp"], "dur": [4.5, 5.5], "pers": {"shy": 2.0, "bold": 0.5}},
	"nose_lick": {"who": {"cow": 1.5, "sheep": 0.6}, "dur": [2.4, 3.2]},
	"back_scratch": {"who": {"bear": 2.0}, "go": ["@shelf"], "dur": [4.5, 6.0]},
	"sit_like_person": {"who": {"bear": 1.5}, "dur": [5.0, 7.0], "e": "lo"},
	"big_yawn": {"who": {"bear": 1.2}, "dur": [3.2, 4.0], "e": "lo"},
	"pat_jar": {"who": {"bear": 1.0}, "go": ["nook"], "dur": [4.5, 5.5], "pers": {"sweet": 1.6}},
}
const LINES := {
	"loaf": {"cat": ["loaf mode. do not unfold me.", "{me} is a bread now."], "*": ["tucked."]},
	"slow_blink":
	{
		"cat": ["I trust you. a little.", "that was a slow blink. it means things."],
		"sassy": ["noted. blink."]
	},
	"knead": {"cat": ["making biscuits. professionally.", "mine now. softer."]},
	"bird_chatter":
	{"cat": ["ek ek ek ek", "it knows. it KNOWS."], "sassy": ["come in, then. I'll wait."]},
	"pounce":
	{"*": ["got it. it was nothing.", "dust. my nemesis."], "mischievous": ["it moved first."]},
	"stretch": {"*": ["aaah.", "all legs accounted for."], "lazy": ["that's the day's exercise."]},
	"wall_stare":
	{"cat": ["there's something there. you can't see it.", "the wall is hiding something."]},
	"yowl": {"cat": ["MROW.", "it is 3 a.m. somewhere."]},
	"tail_chase":
	{
		"dog": ["I almost had it!", "{me} vs the tail. round two."],
		"sweet": ["it keeps running away!"]
	},
	"play_bow": {"*": ["play? play. play!", "bow. now you must play."]},
	"roll_over":
	{"dog": ["belly check.", "this is a good floor."], "*": ["the world is upside down. fine."]},
	"ear_scratch": {"*": ["the itch is gone. the itch is back."]},
	"sniff_line": {"*": ["someone was here. it was me.", "very interesting. very."]},
	"head_tilt": {"dog": ["...what?", "say it again. slower."], "*": ["hm?"]},
	"door_bark": {"dog": ["WOOF", "...that was nobody."], "*": ["no one. I checked."]},
	"carry_bone": {"*": ["mine. all mine. look.", "it's a very good bone."]},
	"three_circles": {"*": ["three. always three.", "circle. circle. circle. ah."]},
	"dream": {"*": ["wuf.", "mrf.", "...fetch..."], "cat": ["mrrp."]},
	"binky": {"rabbit": ["!!! (a happy one)", "I did a thing. I felt it."]},
	"bunny_flop": {"rabbit": ["flop. no notes.", "I am a puddle."]},
	"thump": {"rabbit": ["thump. I said what I said.", "THUMP. regarding you."]},
	"nose_wiggle": {"rabbit": ["sniffing the situation."]},
	"periscope": {"rabbit": ["up periscope. all clear?", "tall now."]},
	"scratch_peck": {"chicken": ["scratch. peck. scratch.", "something is down here. maybe."]},
	"dust_bath": {"chicken": ["a dust bath. the good kind.", "bwk. refreshed."]},
	"flap_run": {"chicken": ["BWAK! (no reason)", "I'm fine! it's fine!"]},
	"lay_egg": {"chicken": ["bwaaak. I made this.", "one egg. for you."]},
	"roost": {"chicken": ["up high. much better.", "this is a perch now."]},
	"root_floor": {"*": ["truffles? maybe. no.", "snuffle snuffle."]},
	"happy_spin": {"*": ["wheee, in a pig way.", "so happy. spinning."]},
	"flop_nap": {"*": ["flopped. nap time.", "here. now. sleep."]},
	"bin_snuffle": {"*": ["the bin smells like opportunity."]},
	"graze": {"*": ["the rug is grass if I believe.", "nom. nom. nom."]},
	"slow_chew": {"*": ["chewing. thinking.", "chew. chew. nothing."]},
	"stamp": {"*": ["stomp. a point was made.", "I'd like this noted."]},
	"horse_trot": {"horse": ["a trot. nobody asked. I did.", "look at my legs."]},
	"deer_freeze": {"deer": ["...was that you?", "I didn't move. you didn't see."]},
	"nose_lick": {"*": ["lick. there. clean."]},
	"back_scratch": {"bear": ["the shelf gets the itch.", "ahh. right there. no, there."]},
	"sit_like_person": {"bear": ["hello. I sit like you now.", "this is how people do it?"]},
	"big_yawn": {"bear": ["HAAAAH. sorry. hibernation.", "that one took a while."]},
	"pat_jar": {"bear": ["careful. careful. honey colour.", "pat pat. don't tell."]},
}

var h:
	get:
		return _hw.get_ref()
var rng := RandomNumberGenerator.new()
var act := {}
var forced: Array = []
var started: Array = []
var staged: Array = []
var next := {}

var _hw: WeakRef
var _extra: Array = []
var _prev_mode := {}
var _was_eat := {}


func setup(home) -> void:
	_hw = weakref(home)
	rng.seed = home.eggs.rng.randi()
	act = {}
	forced = []
	for id in ["nina", "argos"]:
		next[id] = _gap(id)


func force(name: String, who: String = "") -> void:
	forced.append([name, who])


func busy() -> bool:
	return not act.is_empty()


func _rate() -> float:
	return RATE.get(str(h.settings.value("pet_antics")), 1.0)


func _gap(id: String) -> float:
	var c = h.pets.critter(id)
	return rng.randf_range(GAP.x, GAP.y) * h.pets.talk_scale(c) / _rate()


func other(c):
	return h.pets.critter("argos" if c.id == "nina" else "nina")


func process(dt: float) -> void:
	if not staged.is_empty():
		var st: Array = staged
		staged = []
		_stage(st)
	if not act.is_empty():
		_run(dt)
	while not forced.is_empty() and act.is_empty():
		var f: Array = forced.pop_front()
		_force(str(f[0]), str(f[1]))
	if not act.is_empty() or h.pets.freeze or not _gate():
		return
	for id in ["nina", "argos"]:
		next[id] -= dt
		if next[id] > 0.0:
			continue
		next[id] = _gap(id)
		var c = h.pets.critter(id)
		var name := _pick(c)
		if name != "" and begin(name, c, false):
			return


func _gate() -> bool:
	return h._seen_data and h.eggs.scene.is_empty() and not h.eggs.laser_on and h.eggs.calm()


func _stage(st: Array) -> void:
	_force(str(st[0]), str(st[1]))
	var secs: float = float(st[2])
	var n := int(secs / 0.05)
	for i in n:
		h.pets.process(0.05)
		process(0.05)
	if secs > 0.0 and not act.is_empty():
		act["pin"] = true


func _force(name: String, who: String) -> void:
	if not ANTICS.has(name):
		return
	var order: Array = [who] if who != "" else ["nina", "argos"]
	for id in order:
		var c = h.pets.critter(id)
		var e: Dictionary = ANTICS[name]
		if c.mode == "sleep" and not (e.has("keep") or e.has("wakes") or e.has("need")):
			c.mode = "idle"
			c.anim = "idle"
		if not c.away and begin(name, c, true):
			return


func _ok_species(e: Dictionary, c) -> float:
	var who: Dictionary = e["who"]
	return float(who.get(c.species, who.get("*", 0.0)))


func _hour_ok(e: Dictionary) -> bool:
	if not e.has("hours"):
		return true
	var hr: float = h._hour()
	var a: float = e["hours"][0]
	var b: float = e["hours"][1]
	return (hr >= a and hr < b) if a < b else (hr >= a or hr < b)


func _need(need: String, c) -> bool:
	var env: Dictionary = h._env
	match need:
		"":
			return true
		"asleep":
			return c.mode == "sleep"
		"bird":
			return h.outside.act.has("bird")
		"bone":
			return h.petlife.has_mat() and c.species in ["dog", "wolf", "fox"]
	return false


func _weight(name: String, c) -> float:
	var e: Dictionary = ANTICS[name]
	var w: float = _ok_species(e, c) * float(e.get("w", 1.0))
	if w <= 0.0 or e.has("trig") or not _hour_ok(e) or not _need(str(e.get("need", "")), c):
		return 0.0
	w *= float(e.get("pers", {}).get(c.persona, 1.0))
	var hr: float = h._hour()
	if hr >= 13.0 and hr < 16.5:
		w *= {"hi": 0.5, "lo": 1.8}.get(str(e.get("e", "")), 1.0)
	return w


func _pick(c) -> String:
	var total := 0.0
	var opts: Array = []
	for name in ANTICS:
		var w := _weight(name, c)
		if w > 0.0:
			opts.append([name, w])
			total += w
	if opts.is_empty():
		return ""
	var roll := rng.randf() * total
	for o in opts:
		roll -= o[1]
		if roll <= 0.0:
			return o[0]
	return opts[0][0]


func _free(c, e: Dictionary) -> bool:
	if c.away or c.hold or not c.jump.is_empty() or c.goal != "" or c.mode == "walk":
		return false
	if c.mode == "sleep":
		return (
			bool(e.get("keep", false)) or bool(e.get("wakes", false)) or e.get("need") == "asleep"
		)
	return c.mode in ["idle", "sit"] and (c.z <= 0.0 or e.has("go"))


func begin(name: String, c, forced_run: bool) -> bool:
	var e: Dictionary = ANTICS[name]
	if not act.is_empty() or not _free(c, e) or c.species == "":
		return false
	if not forced_run and not _need(str(e.get("need", "")), c):
		return false
	if e.has("scene"):
		started.append(name)
		return h.eggs.start(e["scene"], c.id)
	var legs: Array = []
	for tok in e.get("go", []):
		var spot := _resolve(tok, c)
		if spot == "" or not _reach(c, spot):
			return false
		legs.append(spot)
	act = {
		"name": name,
		"id": c.id,
		"t": 0.0,
		"st": "go",
		"gi": 0,
		"legs": legs,
		"fx": [],
		"dur": rng.randf_range(e["dur"][0], e["dur"][1]),
		"species": c.species,
		"said": false,
		"base": c.pos,
		"d0": c.dir,
	}
	c.hold = true
	c.run = bool(e.get("run", false))
	started.append(name)
	_leg(c)
	return true


func _reach(c, spot: String) -> bool:
	var cell: Vector2i = h.pets.spots[spot]["cell"]
	var from: Vector2i = h.pets._cell_of(c.pos)
	return not h.pets._blocked(cell) and (cell == from or not h.pets.route(from, cell).is_empty())


func _resolve(tok: String, _c) -> String:
	if tok == "@shelf":
		var p: Dictionary = h.eggs.piece("bookshelf")
		var cell: Vector2i = h.eggs.front_cell(p) if not p.is_empty() else Vector2i(-1, -1)
		return h.eggs.spot("ant_shelf", {"cell": cell, "face": 3}) if cell.x >= 0 else "board"
	return tok if h.pets.spots.has(tok) else ""


func _leg(c) -> void:
	var legs: Array = act["legs"]
	if act["gi"] >= legs.size():
		_enter(c)
		return
	h.pets.go(c, legs[act["gi"]], "sit", 0.1)
	act["leg_t"] = 0.0


func _arrived(c) -> bool:
	return c.goal == "" and c.jump.is_empty() and c.mode in ["idle", "sleep"] and c.path.is_empty()


func _enter(c) -> void:
	var e: Dictionary = ANTICS[act["name"]]
	act["st"] = "play"
	act["t"] = 0.0
	act["base"] = c.pos
	act["d0"] = c.dir
	c.run = false
	if e.has("carry"):
		c.carry = e["carry"]
	if c.mode != "sleep":
		c.mode = "idle"
	var fwd := Vector2(1, 0)
	for d in [c.dir, 7, 3, 1, 5]:
		var v: Vector2 = vec(d)
		var ahead: Vector2i = h.pets._cell_of(c.pos + v * 1.2)
		if not h.pets._blocked(ahead) and c.pos.x + v.x * 1.2 < 10.0 and c.pos.y + v.y * 1.2 < 10.0:
			fwd = v
			break
	act["fwd"] = fwd


func vec(d: int) -> Vector2:
	match d:
		7:
			return Vector2(1, 0)
		3:
			return Vector2(-1, 0)
		1:
			return Vector2(0, 1)
	return Vector2(0, -1)


func _run(dt: float) -> void:
	var c = h.pets.critter(act["id"])
	if c.away or not c.hold or c.species != act["species"] or not h.eggs.calm():
		_end(c, false)
		return
	if not act.get("pin", false):
		act["t"] += dt
	if act["st"] == "go":
		act["leg_t"] += dt
		if _arrived(c):
			act["gi"] += 1
			_leg(c)
		elif act["leg_t"] > LEG_MAX:
			_end(c, false)
		return
	c.lift = 0.0
	act["fx"] = []
	_pose(act["name"], c, float(act["t"]), float(act["dur"]))
	if act["t"] >= act["dur"] and (c.mode != "walk" or act["t"] > act["dur"] + LEG_MAX):
		_end(c, true)


func _end(c, done: bool) -> void:
	var e: Dictionary = ANTICS[act["name"]]
	c.hold = false
	c.run = false
	c.lift = 0.0
	c.flip = false
	if c.carry == e.get("carry", "-"):
		c.carry = ""
	if not c.away and c.mode != "walk":
		c.pos = act["base"] if act["st"] == "play" and c.jump.is_empty() else c.pos
	if bool(e.get("keep", false)) and c.mode == "sleep":
		c.wait = rng.randf_range(15.0, 28.0)
	else:
		c.mode = "idle"
		c.anim = "idle"
		c.wait = rng.randf_range(2.0, 5.0)
	if done:
		_after(act["name"], c)
	act = {}


func _after(name: String, c) -> void:
	match name:
		"lay_egg":
			var n: int = h.eggs.things.filter(func(t): return t["kind"] == "egg").size()
			if n < 3:
				h.eggs.things.append(
					{"kind": "egg", "pos": c.pos + Vector2(0.1, 0.4), "life": 150.0}
				)


func _say(c, name: String) -> void:
	var lines: Dictionary = LINES.get(name, {})
	var pool: Array = []
	for key in [c.persona, c.species, "*"]:
		pool.append_array(lines.get(key, []))
	if pool.is_empty() or c.say_left > 0.0 or rng.randf() > SAY_CHANCE:
		return
	var text: String = pool[rng.randi() % pool.size()]
	h.pets.say(c, text.replace("{me}", c.title))


func _cue(c, e: Dictionary) -> void:
	var cue: String = e.get("cue", "")
	h.sound.request(h.pets.cry(c) if cue == "cry" else cue)


func _face_person(c) -> void:
	c.dir = h.pets._face(h.person.c.pos - c.pos, c.dir)


func _fx(c, kind: String, u: float = 0.0) -> void:
	act["fx"].append([c.id, kind, u])


func _hearts(c, n: int = 3) -> void:
	if c.hearts.is_empty():
		for i in n:
			c.hearts.append({"t": -0.2 * i, "dx": rng.randf_range(-8.0, 8.0)})


func _pulse(t: float, on: float, period: float) -> bool:
	return fmod(t, period) < on


func _pose(name: String, c, t: float, dur: float) -> void:
	var u := t / dur
	var base: Vector2 = act["base"]
	var d0: int = act["d0"]
	var fwd: Vector2 = act["fwd"]
	var e: Dictionary = ANTICS[name]
	c.anim = "idle"
	if not act["said"] and t > 0.5 and name in LINES:
		act["said"] = true
		_say(c, name)
		_cue(c, e)
	match name:
		"loaf":
			c.anim = "sleep"
		"slow_blink":
			_face_person(c)
			if u > 0.55:
				_hearts(c, 2)
		"knead":
			c.anim = "walk"
			c.lift = 0.8 * absf(sin(t * 6.0))
			if u > 0.4:
				_hearts(c, 2)
		"bird_chatter":
			c.dir = Pets.DIRS["nw"]
			c.anim = "attack" if _pulse(t, 0.35, 0.9) else "idle"
			c.lift = 0.7 * sin(t * 30.0) if c.anim == "attack" else 0.0
			if _pulse(t, 0.05, 1.8):
				h.sound.request("squeak")
		"pounce":
			c.dir = Pets.DIRS["se"] if fwd.x > 0 else Pets.DIRS["nw"] if fwd.x < 0 else c.dir
			if t < 1.1:
				c.pos = base + Vector2(sin(t * 38.0) * 0.012, 0.0)
				c.lift = -0.6
			elif t < 1.7:
				var f := (t - 1.1) / 0.6
				c.pos = base + fwd * 0.8 * f
				c.lift = 8.0 * sin(PI * f)
				c.anim = "attack"
			else:
				c.pos = base + fwd * 0.8
				_fx(c, "question")
		"stretch":
			c.lift = 1.4 * sin(PI * clampf(u * 1.6, 0.0, 1.0))
			if u < 0.6:
				_fx(c, "yawn", u)
		"wall_stare":
			c.dir = Pets.DIRS["nw"]
			if u > 0.55:
				_fx(c, "question")
		"yowl":
			c.dir = Pets.DIRS["se"]
			c.anim = "attack" if _pulse(t, 1.0, 1.6) else "idle"
			c.lift = 1.2 if c.anim == "attack" else 0.0
			_fx(c, "yawn", 0.5)
		"tail_chase":
			var spin := dur - 2.4
			if t < spin:
				var ph := t * 5.0 + t * t * 0.9
				c.dir = int(ph) % 8
				c.anim = "run"
				c.pos = base + Vector2(sin(ph * 0.8), cos(ph * 0.8)) * 0.05
			elif t < dur - 0.7:
				c.pos = base + Vector2(sin(t * 8.0) * 0.05, cos(t * 6.0) * 0.03)
				c.dir = (d0 + int(sin(t * 3.0) * 1.5)) % 8
				_fx(c, "stars", t)
				c.lift = 0.6 * sin(t * 9.0)
			else:
				_fx(c, "stars", t)
		"play_bow":
			_face_person(c)
			c.anim = "attack" if _pulse(t, 0.55, 1.2) else "idle"
			if t < 0.4:
				_fx(c, "bang")
			c.lift = 1.0 if c.anim == "attack" else 0.0
		"roll_over":
			if u > 0.15 and u < 0.85:
				c.flip = true
				c.pos = base + Vector2(sin(t * 9.0) * 0.03, 0.0)
			if u > 0.7:
				_hearts(c, 2)
		"ear_scratch":
			c.lift = 1.0 * absf(sin(t * 14.0))
			c.dir = (d0 + 1) % 8 if _pulse(t, 0.12, 0.3) else d0
		"sniff_line":
			c.anim = "eat"
			var step: float = t * 0.45
			var to: Vector2 = base + fwd * step
			if not h.pets._blocked(h.pets._cell_of(to)) and to.x < 9.8 and to.y < 9.8:
				c.pos = to
			c.dir = h.pets._face(fwd, d0)
		"head_tilt":
			_face_person(c)
			c.dir = (c.dir + (1 if int(t * 1.1) % 2 == 0 else 0)) % 8
			_fx(c, "question")
		"door_bark":
			c.dir = Pets.DIRS["sw"]
			if t < 1.0:
				c.anim = "idle"
			elif t < 2.2:
				c.anim = "attack"
				c.lift = 3.0 * sin(PI * clampf(t - 1.0, 0.0, 1.0))
				_fx(c, "bang")
			else:
				c.dir = Pets.DIRS["se"]
				_fx(c, "sweat", t)
		"carry_bone":
			c.anim = "idle"
		"three_circles":
			if t < 6.0:
				c.dir = int(t * 4.0) % 8
				c.anim = "walk"
				c.pos = base + Vector2(sin(t * 3.0), cos(t * 3.0)) * 0.04
			else:
				c.mode = "sleep"
				c.anim = "sleep"
		"dream":
			c.mode = "sleep"
			c.anim = "sleep"
			c.lift = 0.9 * absf(sin(t * 28.0)) if _pulse(t, 0.5, 1.6) else 0.0
		"binky":
			var f := fmod(t, 1.1) / 1.1
			c.lift = 11.0 * sin(PI * f)
			c.dir = (d0 + int(f * 8.0)) % 8 if f > 0.2 and f < 0.8 else d0
			c.anim = "run" if c.lift > 1.0 else "idle"
		"bunny_flop":
			if u > 0.2 and u < 0.85:
				c.flip = true
				c.anim = "sleep"
			if u > 0.5:
				_hearts(c, 2)
		"thump":
			c.anim = "attack" if _pulse(t, 0.22, 0.65) else "idle"
			c.lift = -0.8 if c.anim == "attack" else 0.0
			if _pulse(t, 0.04, 0.65) and t > 0.3:
				h.sound.request("squeak")
				_fx(c, "dust", fmod(t, 0.65) / 0.4)
		"nose_wiggle":
			c.lift = 0.5 * sin(t * 40.0)
			c.dir = (d0 + (1 if _pulse(t, 0.12, 0.25) else 0)) % 8
		"periscope":
			c.lift = 5.0 * clampf(minf(t, dur - t) * 3.0, 0.0, 1.0)
			c.dir = Pets.DIRS["nw"] if int(t / 1.2) % 2 == 0 else Pets.DIRS["se"]
			if u > 0.5:
				_fx(c, "question")
		"scratch_peck":
			c.anim = "eat" if _pulse(t, 0.4, 0.9) else "idle"
			c.pos = base - fwd * 0.12 * sin(t * 3.0)
			if not _pulse(t, 0.4, 0.9):
				_fx(c, "dust", fmod(t, 0.9) / 0.9)
		"dust_bath":
			c.anim = "sleep"
			c.pos = base + Vector2(sin(t * 18.0) * 0.03, 0.0)
			_fx(c, "dust", fmod(t * 1.6, 1.0))
		"flap_run":
			c.anim = "run"
			c.lift = 2.0 * absf(sin(t * 20.0))
			_fx(c, "feather", t)
		"lay_egg":
			c.anim = "sleep"
			c.pos = base + Vector2(sin(t * 22.0) * 0.02, 0.0) * (1.0 if u < 0.8 else 0.0)
			if u > 0.8:
				_fx(c, "bang")
				if not act.get("cued", false):
					act["cued"] = true
					h.sound.request("cluck")
		"roost":
			c.mode = "sleep"
			c.anim = "sleep"
		"root_floor":
			c.anim = "eat"
			var to: Vector2 = base + fwd * t * 0.3
			if not h.pets._blocked(h.pets._cell_of(to)) and to.x < 9.8 and to.y < 9.8:
				c.pos = to
			_fx(c, "dust", fmod(t * 1.4, 1.0))
		"happy_spin":
			c.dir = int(t * 9.0) % 8
			c.anim = "run"
			c.lift = 3.0 * absf(sin(t * 5.0))
			_hearts(c, 2)
		"flop_nap":
			c.mode = "sleep"
			c.anim = "sleep"
		"bin_snuffle":
			c.dir = Pets.DIRS["ne"]
			c.anim = "eat" if _pulse(t, 0.7, 1.2) else "idle"
		"graze":
			c.anim = "eat"
		"slow_chew":
			c.lift = 0.5 * sin(t * 10.0)
		"stamp":
			c.anim = "attack" if _pulse(t, 0.3, 0.9) else "idle"
			c.lift = 1.2 if c.anim == "attack" else 0.0
			if not _pulse(t, 0.3, 0.9) and _pulse(t, 0.5, 0.9):
				_fx(c, "dust", fmod(t, 0.9) / 0.6)
		"horse_trot":
			c.dir = d0
			c.anim = "attack" if t < 0.8 else "idle"
			c.lift = 2.0 * sin(PI * clampf(t / 0.8, 0.0, 1.0))
		"deer_freeze":
			if t < 2.0:
				c.dir = Pets.DIRS["sw"]
				_fx(c, "bang")
			elif not act.get("sent", false):
				act["sent"] = true
				c.run = true
				h.pets.go(c, "corner", "sit", 0.1)
			if c.mode == "walk":
				c.lift = 4.0 * absf(sin(t * 9.0))
		"nose_lick":
			c.dir = Pets.DIRS["se"]
			c.lift = 0.4 * sin(t * 12.0)
			if int(t * 2.0) % 2 == 0:
				_fx(c, "lick")
		"back_scratch":
			c.pos = base + Vector2(sin(t * 10.0) * 0.03, 0.0)
			c.lift = absf(sin(t * 10.0)) * 1.2
			if u > 0.6:
				_hearts(c, 2)
		"sit_like_person":
			c.dir = Pets.DIRS["se"]
			c.lift = 0.5 * sin(t * 1.3)
		"big_yawn":
			c.dir = Pets.DIRS["se"]
			_fx(c, "yawn", 1.0 if u > 0.2 and u < 0.8 else 0.4)
			c.lift = 1.0 * sin(PI * u)
		"pat_jar":
			c.dir = Pets.DIRS["ne"]
			c.anim = "attack" if _pulse(t, 0.4, 1.3) else "idle"
			if u > 0.7:
				_hearts(c, 2)


func dust(c, u: float) -> void:
	_extra.append([c.id, "dust", u])


func draw_over(canvas: CanvasItem) -> void:
	var k: int = h._k
	var all: Array = _extra.duplicate()
	_extra = []
	if not act.is_empty():
		all.append_array(act["fx"])
	for fx in all:
		var c = h.pets.critter(fx[0])
		var f: Vector2 = h.pets.feet(c, h._o, k)
		_draw_fx(canvas, c, f, k, fx[1], float(fx[2]))


func _draw_fx(canvas: CanvasItem, c, f: Vector2, k: int, kind: String, u: float) -> void:
	var top := f + Vector2(0, -(c.head + 3) * k)
	match kind:
		"stars":
			for i in 3:
				var a := u * 5.0 + i * TAU / 3.0
				var p := top + Vector2(cos(a) * 8.0, sin(a) * 2.5) * k
				var col := Color("f2d34a")
				canvas.draw_rect(Rect2(p + Vector2(-1.5 * k, -0.5 * k), Vector2(3 * k, k)), col)
				canvas.draw_rect(Rect2(p + Vector2(-0.5 * k, -1.5 * k), Vector2(k, 3 * k)), col)
		"bang":
			var bob := sin(h._t * 14.0) * k
			var col := Color("e8576b")
			canvas.draw_rect(Rect2(top + Vector2(-k, -8 * k + bob), Vector2(2 * k, 5 * k)), col)
			canvas.draw_rect(Rect2(top + Vector2(-k, -2 * k + bob), Vector2(2 * k, 2 * k)), col)
		"question":
			canvas.draw_string(
				ThemeDB.fallback_font,
				top + Vector2(-3 * k, -3 * k),
				"?",
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				16,
				Color("f1e9dc")
			)
		"dust":
			for i in 3:
				var at := f + Vector2((i - 1) * 6.0 * u * k, -(2 + i % 2) * k)
				canvas.draw_circle(
					at, (1.5 + 3.0 * u) * k, Color(0.86, 0.82, 0.76, (1.0 - u) * 0.7)
				)
		"sweat":
			var at := top + Vector2(7 * k, 3 * k + fmod(u * 6.0, 1.0) * 3.0 * k)
			canvas.draw_rect(Rect2(at, Vector2(k, 2 * k)), Color("8fd3f0"))
		"yawn":
			var at := f + Vector2(5 * k, -(c.head - 4) * k)
			canvas.draw_circle(at, (1.5 + 2.0 * u) * k, Color("3a2a30"))
		"feather":
			for i in 4:
				var ph := fmod(u * 1.5 + i * 0.25, 1.0)
				var at := f + Vector2((i - 1.5) * 7.0 * k, -(6 + ph * 10) * k)
				canvas.draw_rect(Rect2(at, Vector2(2 * k, k)), Color(1, 1, 1, 1.0 - ph))
		"lick":
			canvas.draw_rect(
				Rect2(f + Vector2(6 * k, -(c.head - 6) * k), Vector2(2 * k, 2 * k)), Color("e88a9a")
			)
