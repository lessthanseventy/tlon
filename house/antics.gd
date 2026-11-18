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
	{
		"moves": true,
		"who": {"deer": 2.0},
		"go": ["lamp"],
		"dur": [4.5, 5.5],
		"pers": {"shy": 2.0, "bold": 0.5}
	},
	"nose_lick": {"who": {"cow": 1.5, "sheep": 0.6}, "dur": [2.4, 3.2]},
	"back_scratch": {"who": {"bear": 2.0}, "go": ["@shelf"], "dur": [4.5, 6.0]},
	"sit_like_person": {"who": {"bear": 1.5}, "dur": [5.0, 7.0], "e": "lo"},
	"big_yawn": {"who": {"bear": 1.2}, "dur": [3.2, 4.0], "e": "lo"},
	"pat_jar": {"who": {"bear": 1.0}, "go": ["nook"], "dur": [4.5, 5.5], "pers": {"sweet": 1.6}},
	"greet": {"pair": true, "who": {"*": 1.5}, "go": ["@p"], "dur": [3.6, 4.6]},
	"chase_game":
	{
		"pair": true,
		"who": {"*": 1.0},
		"dur": [9.0, 12.0],
		"moves": true,
		"e": "hi",
		"pers": {"mischievous": 2.0, "bold": 2.0, "sweet": 1.5, "lazy": 0.3}
	},
	"nap_pile":
	{
		"pair": true,
		"who": {"*": 1.0},
		"go": ["rug"],
		"pgo": ["@i"],
		"dur": [16.0, 24.0],
		"keep": true,
		"psleep": true,
		"e": "lo",
		"pers": {"lazy": 2.5, "sweet": 1.3}
	},
	"boop":
	{
		"pair": true,
		"who": {"cat": 1.5},
		"go": ["@p"],
		"dur": [3.0, 3.8],
		"pers": {"sassy": 2.0, "mischievous": 2.0}
	},
	"groom":
	{
		"pair": true,
		"who": {"*": 0.8},
		"go": ["@p"],
		"dur": [6.0, 8.0],
		"e": "lo",
		"pers": {"sweet": 2.0}
	},
	"steal_spot":
	{
		"pair": true,
		"who": {"*": 0.8},
		"need": "pspot",
		"go": ["@pspot"],
		"pgo": ["corner"],
		"psleep": true,
		"dur": [10.0, 13.0],
		"pers": {"mischievous": 3.0, "bold": 2.0, "sassy": 1.5, "sweet": 0.2, "shy": 0.1}
	},
	"copy_cat":
	{
		"pair": true,
		"who": {"*": 0.8},
		"go": ["mid"],
		"pgo": ["@i"],
		"dur": [5.0, 6.5],
		"pers": {"mischievous": 2.0}
	},
	"standoff":
	{
		"pair": true,
		"who": {"*": 1.0},
		"need": "toy",
		"go": ["@toy"],
		"pgo": ["@toy2"],
		"dur": [6.0, 7.5]
	},
	"herd":
	{
		"pair": true,
		"who": {"*": 1.0},
		"only": true,
		"pers": {"bold": 3.0, "mischievous": 1.0},
		"bpers": ["shy"],
		"go": ["@p"],
		"dur": [8.0, 9.0],
		"moves": true
	},
	"follow_around":
	{
		"pair": true,
		"pfree": true,
		"who": {"sheep": 2.0, "deer": 0.5, "pig": 0.6, "cow": 0.6},
		"dur": [12.0, 18.0],
		"moves": true
	},
}
const RANK := {"bold": 5, "mischievous": 4, "sassy": 3, "sweet": 2, "lazy": 1, "shy": 0}
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
	"greet":
	{
		"sassy": ["hello. don't make it a thing."],
		"sweet": ["HI! hi! it's you!"],
		"*": ["a nose. hello."]
	},
	"greet_b": {"sassy": ["hm. hello."], "sweet": ["hello hello hello!"], "*": ["oh. hi."]},
	"chase_game": {"*": ["tag! you're it!", "can't catch me!"]},
	"chase_game_b": {"*": ["I'm coming!", "wait! rules!"]},
	"nap_pile": {"*": ["scoot. there.", "warm. fine. stay."]},
	"nap_pile_b": {"*": ["mm. toasty.", "a pile. the best shape."]},
	"boop": {"cat": ["boop. you're welcome.", "{me} has booped."]},
	"boop_b": {"*": ["!?", "what was that for?"]},
	"groom": {"*": ["hold still. you're a mess.", "there. presentable."]},
	"groom_b": {"*": ["aww. thanks.", "mm. a little left."]},
	"steal_spot": {"*": ["this is my spot now.", "thank you for warming it."]},
	"steal_spot_b": {"*": ["...that was MINE.", "I'll be over here. judging."]},
	"copy_cat": {"*": ["watch this.", "hop. hop. hop."]},
	"copy_cat_b": {"*": ["watch ME. hop.", "I'm not copying. I'm also hopping."]},
	"standoff": {"*": ["the yarn is mine.", "step back."]},
	"standoff_b": {"*": ["no, mine.", "we'll see."]},
	"herd": {"bold": ["out you come. the world is big.", "come along. I'll protect you."]},
	"herd_b": {"shy": ["...okay.", "I was fine in there."]},
	"follow_around": {"sheep": ["baa. where you go, I go.", "I'm in your flock now."]},
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
		next[id] = rng.randf_range(6.0, 15.0)


func _gate() -> bool:
	return h._seen_data and h.eggs.scene.is_empty() and not h.eggs.laser_on and h.eggs.calm()


func _stage(st: Array) -> void:
	if ANTICS.get(str(st[0]), {}).get("pair", false):
		var mate = other(h.pets.critter(str(st[1]) if st[1] != "" else "nina"))
		if not mate.away and (mate.mode == "sleep" or mate.z > 0.0):
			h.pets.place(mate, "lounge", "idle")
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
		"toy":
			return not h.pets._toy_of("yarn").is_empty()
		"pspot":
			return _resolve("@pspot", c, other(c), Vector2i.ZERO) != ""
	return false


func _weight(name: String, c) -> float:
	var e: Dictionary = ANTICS[name]
	var w: float = _ok_species(e, c) * float(e.get("w", 1.0))
	if w <= 0.0 or e.has("trig") or not _hour_ok(e) or not _need(str(e.get("need", "")), c):
		return 0.0
	if e.get("pair", false) and not _pair_ok(e, c, other(c)):
		return 0.0
	w *= float(e.get("pers", {}).get(c.persona, 0.0 if e.get("only", false) else 1.0))
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
	var p = null
	if e.get("pair", false):
		p = other(c)
		if not _pair_ok(e, c, p):
			return false
	var ilegs = null
	var plegs = null
	var ptoks: Array = e.get("pgo", [])
	if "@i" in ptoks:
		ilegs = _legs(e.get("go", []), c, p, h.pets._cell_of(p.pos) if p != null else Vector2i.ZERO)
		plegs = _legs(ptoks, p, c, _fin(c, ilegs)) if ilegs != null else null
	else:
		plegs = _legs(ptoks, p, c, h.pets._cell_of(c.pos)) if p != null else []
		ilegs = _legs(e.get("go", []), c, p, _fin(p, plegs)) if plegs != null else null
	if ilegs == null or plegs == null:
		return false
	act = {
		"name": name,
		"id": c.id,
		"pid": p.id if p != null else "",
		"t": 0.0,
		"st": "go",
		"gi": 0,
		"pgi": 0,
		"legs": ilegs,
		"plegs": plegs,
		"fx": [],
		"dur": rng.randf_range(e["dur"][0], e["dur"][1]),
		"species": c.species,
		"said": false,
		"base": c.pos,
		"pbase": p.pos if p != null else Vector2.ZERO,
		"leg_t": 0.0,
		"d0": c.dir,
	}
	c.hold = true
	c.run = bool(e.get("run", false))
	if p != null:
		p.hold = not e.get("pfree", false)
		if p.mode == "sleep" and not e.get("keep", false):
			p.mode = "idle"
			p.anim = "idle"
	started.append(name)
	_start_leg(c, "gi", "legs")
	if p != null:
		_start_leg(p, "pgi", "plegs")
	return true


func _pair_ok(e: Dictionary, c, p) -> bool:
	if p.away or p.species == "" or c.away:
		return false
	if e.has("bwho") and p.species not in e["bwho"]:
		return false
	if e.has("bpers") and p.persona not in e["bpers"]:
		return false
	var e2: Dictionary = e.duplicate()
	e2["wakes"] = bool(e.get("psleep", false))
	return p.hold == false and (e.get("pfree", false) or _free(p, e2))


func _fin(c, legs: Variant) -> Vector2i:
	if c == null or legs == null or (legs as Array).is_empty():
		return h.pets._cell_of(c.pos) if c != null else Vector2i.ZERO
	return h.pets.spots[(legs as Array)[-1]]["cell"]


func _legs(toks: Array, who, mate, mate_cell: Vector2i) -> Variant:
	var out: Array = []
	for tok in toks:
		var spot := _resolve(tok, who, mate, mate_cell)
		if spot == "" or not _reach(who, spot):
			return null
		out.append(spot)
	return out


func _reach(c, spot: String) -> bool:
	var cell: Vector2i = h.pets.spots[spot]["cell"]
	var from: Vector2i = h.pets._cell_of(c.pos)
	return not h.pets._blocked(cell) and (cell == from or not h.pets.route(from, cell).is_empty())


func _resolve(tok: String, c, mate, mate_cell: Vector2i) -> String:
	match tok:
		"@shelf":
			var p: Dictionary = h.eggs.piece("bookshelf")
			var cell: Vector2i = h.eggs.front_cell(p) if not p.is_empty() else Vector2i(-1, -1)
			return h.eggs.spot("ant_shelf", {"cell": cell, "face": 3}) if cell.x >= 0 else "board"
		"@p", "@i":
			return next_to(mate_cell, c, 0)
		"@toy", "@toy2":
			var toy: Dictionary = h.pets._toy_of("yarn")
			return (
				""
				if toy.is_empty()
				else next_to(h.pets._cell_of(toy["pos"]), c, int(tok == "@toy2"))
			)
		"@pspot":
			var s: String = mate.spot if mate != null else ""
			return s if h.pets.spots.has(s) and s not in ["bowl", "water", ""] else ""
		"@sun":
			var f := clampf((h._hour() - 8.0) / 9.0, 0.0, 1.0)
			var cell := Vector2i(clampi(int(lerpf(0.4, 2.2, f) + 1.3), 1, 9), 6)
			return (
				h.eggs.spot("ant_sun", {"cell": cell, "face": 7})
				if not h.pets._blocked(cell)
				else ""
			)
	return tok if h.pets.spots.has(tok) else ""


# a spot beside `cell` that `c` can reach, the `skip`th nearest to it
func next_to(cell: Vector2i, c, skip: int) -> String:
	var from: Vector2i = h.pets._cell_of(c.pos)
	var opts: Array = []
	for d in GROUND:
		var n: Vector2i = cell + d
		if h.pets._blocked(n) or (n != from and h.pets.route(from, n).is_empty()):
			continue
		opts.append(n)
	opts.sort_custom(func(a, b): return Vector2(a - from).length() < Vector2(b - from).length())
	if opts.size() <= skip:
		return ""
	var at: Vector2i = opts[skip]
	var face: int = h.pets._face(Vector2(cell - at), 7)
	return h.eggs.spot("ant_nx_%s_%d" % [c.id, skip], {"cell": at, "face": face})


func _start_leg(c, gk: String, lk: String) -> void:
	var legs: Array = act[lk]
	if act[gk] < legs.size():
		h.pets.go(c, legs[act[gk]], "sit", 0.1)


func _advance(c, gk: String, lk: String) -> bool:
	var legs: Array = act[lk]
	if act[gk] < legs.size() and _arrived(c):
		act[gk] += 1
		_start_leg(c, gk, lk)
	return act[gk] >= legs.size()


func _arrived(c) -> bool:
	return c.goal == "" and c.jump.is_empty() and c.mode in ["idle", "sleep"] and c.path.is_empty()


func _enter(c, p) -> void:
	var e: Dictionary = ANTICS[act["name"]]
	act["st"] = "play"
	act["t"] = 0.0
	act["base"] = c.pos
	act["d0"] = c.dir
	if p != null:
		act["pbase"] = p.pos
		p.run = false
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
	var p = h.pets.critter(act["pid"]) if act["pid"] != "" else null
	var e: Dictionary = ANTICS[act["name"]]
	var lost: bool = c.away or not c.hold or c.species != act["species"] or not h.eggs.calm()
	if p != null and (p.away or (not p.hold and not e.get("pfree", false))):
		lost = true
	if lost:
		_end(c, false)
		return
	if not act.get("pin", false):
		act["t"] += dt
	if act["st"] == "go":
		act["leg_t"] += dt
		var a_done := _advance(c, "gi", "legs")
		var p_done := p == null or _advance(p, "pgi", "plegs")
		if a_done and p_done:
			_enter(c, p)
		elif act["leg_t"] > LEG_MAX:
			_end(c, false)
		return
	c.lift = 0.0
	if p != null:
		p.lift = 0.0
		if p.mode != "walk" and not e.get("pfree", false):
			p.anim = "sleep" if p.mode == "sleep" else "idle"
	act["fx"] = []
	_pose(act["name"], c, float(act["t"]), float(act["dur"]), p)
	if act["t"] >= act["dur"] and (c.mode != "walk" or act["t"] > act["dur"] + LEG_MAX):
		_end(c, true)


func _end(c, done: bool) -> void:
	var e: Dictionary = ANTICS[act["name"]]
	var p = h.pets.critter(act["pid"]) if act["pid"] != "" else null
	_release(c, e, act["base"])
	if p != null:
		_release(p, e, act["pbase"])
	if done:
		_after(act["name"], c, p)
	act = {}


func _release(c, e: Dictionary, base: Vector2) -> void:
	c.hold = false
	c.run = false
	c.lift = 0.0
	c.flip = false
	if c.carry == e.get("carry", "-"):
		c.carry = ""
	var posed: bool = act["st"] == "play" and not e.get("moves", false) and not e.get("pair", false)
	if posed and not c.away and c.mode != "walk" and c.jump.is_empty():
		c.pos = base
	if bool(e.get("keep", false)) and c.mode == "sleep":
		c.wait = rng.randf_range(15.0, 28.0)
	else:
		if c.mode == "walk" and c.jump.is_empty():
			c.path = []
			c.goal = ""
		c.mode = "idle" if c.jump.is_empty() else c.mode
		c.anim = "idle"
		c.wait = rng.randf_range(2.0, 5.0)


func _after(name: String, c, p) -> void:
	match name:
		"standoff":
			var toy: Dictionary = h.pets._toy_of("yarn")
			if not toy.is_empty() and p != null:
				h.pets.chase(c if _rank(c) >= _rank(p) else p, toy, 2)
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


func _toward(a, b) -> int:
	return h.pets._face(b.pos - a.pos, a.dir)


func _rank(c) -> int:
	return RANK.get(c.persona, 0)


func _chase_step(lead, fol) -> void:
	var cells: Array = h.eggs.ZOOM_CELLS.filter(
		func(x):
			return (
				not h.pets._blocked(x) and not h.pets.route(h.pets._cell_of(lead.pos), x).is_empty()
			)
	)
	if cells.is_empty():
		return
	var cell: Vector2i = cells[rng.randi() % cells.size()]
	lead.run = true
	h.pets.go(lead, h.eggs.spot("ant_ch_l", {"cell": cell}), "sit", 0.1)
	var s := next_to(h.pets._cell_of(lead.pos), fol, 0)
	if s != "":
		fol.run = true
		h.pets.go(fol, s, "sit", 0.1)


func _pose(name: String, c, t: float, dur: float, p) -> void:
	var u := t / dur
	var base: Vector2 = act["base"]
	var d0: int = act["d0"]
	var fwd: Vector2 = act["fwd"]
	var e: Dictionary = ANTICS[name]
	if c.mode != "walk":
		c.anim = "idle"
	if not act["said"] and t > 0.5 and name in LINES:
		act["said"] = true
		_say(c, name)
		_cue(c, e)
	if p != null and not act.get("said_b", false) and t > 1.6 and (name + "_b") in LINES:
		act["said_b"] = true
		_say(p, name + "_b")
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
		"greet":
			c.dir = _toward(c, p)
			p.dir = _toward(p, c)
			if t > 0.7 and t < 1.7:
				c.lift = 1.0
				p.lift = 1.0
			if t > 1.0 and c.persona in ["sassy", "shy"]:
				_fx(c, "bang")
				_fx(p, "sweat", t)
			elif t > 1.0:
				_hearts(c, 2)
				_hearts(p, 2)
		"chase_game":
			var half: bool = t > dur * 0.5
			if t >= act.get("nxt", 0.0):
				act["nxt"] = t + 1.3
				_chase_step(p if half else c, c if half else p)
		"nap_pile":
			for x in [c, p]:
				x.mode = "sleep"
				x.anim = "sleep"
			c.dir = Pets.DIRS["se"]
			p.dir = Pets.DIRS["se"]
		"boop":
			c.dir = _toward(c, p)
			p.dir = _toward(p, c)
			c.anim = "attack" if t > 0.7 and t < 1.2 else "idle"
			if t > 0.9 and t < 1.9:
				p.lift = 2.5
				_fx(p, "bang")
			if t > 1.9:
				_hearts(p, 2)
		"groom":
			c.dir = _toward(c, p)
			p.dir = _toward(p, c)
			c.anim = "eat" if int(t * 2.0) % 2 == 0 else "idle"
			p.anim = "sleep"
			if t > 1.0:
				_hearts(p, 2)
		"steal_spot":
			c.mode = "sleep"
			c.anim = "sleep"
			p.dir = _toward(p, c)
			_fx(p, "bang" if t < 1.5 else "sweat", t)
		"copy_cat":
			c.dir = Pets.DIRS["se"]
			p.dir = Pets.DIRS["se"]
			c.lift = 6.0 * absf(sin(t * 3.5))
			if t > 0.5:
				p.lift = 6.0 * absf(sin((t - 0.5) * 3.5))
		"standoff":
			var toy: Dictionary = h.pets._toy_of("yarn")
			if not toy.is_empty():
				c.dir = h.pets._face(toy["pos"] - c.pos, c.dir)
				p.dir = h.pets._face(toy["pos"] - p.pos, p.dir)
			c.anim = "attack" if _pulse(t, 0.45, 1.2) else "idle"
			p.anim = "attack" if _pulse(t + 0.6, 0.45, 1.2) else "idle"
			if u > 0.85:
				_fx(c if _rank(c) < _rank(p) else p, "sweat", t)
		"herd":
			if t < 1.2:
				c.dir = _toward(c, p)
				_fx(c, "bang")
			elif not act.get("sent", false):
				act["sent"] = true
				h.pets.go(p, "rug", "sit", 0.1)
				var s := next_to(h.pets.spots["rug"]["cell"], c, 0)
				if s != "":
					h.pets.go(c, s, "sit", 0.1)
			if t > 1.2:
				_fx(p, "sweat", t)
		"follow_around":
			if t >= act.get("nxt", 0.0):
				act["nxt"] = t + 1.4
				var s := next_to(h.pets._cell_of(p.pos), c, 0)
				if s != "":
					h.pets.go(c, s, "sit", 0.1)


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
