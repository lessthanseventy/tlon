extends RefCounted

# Cues play files from the two Gridwright packs (under the art dir, loaded at runtime, never
# imported) and fall back to a synthesized sound per cue when a file is missing; what the packs
# have no fit for stays synthesized. It starts muted; M toggles, - and = change the volume, both
# kept in user://house_sound.json ({"muted": bool, "volume": 0..1}).
const RATE := 22050
const PEAK := 0.4
const MAX_VOICES := 4
const SYNTH_DB := -9.0
const SYNTH_GAP := 0.06
const UI := "ui-sound-effects/Gridwright UI Sound Effects/OGG/"
const RT := "retro-sound-effects/Gridwright Retro Sound Effects/OGG/16-bit/"
const LOOPS := ["crackle", "rain"]
const EVENTS := [
	"piano",
	"bad_piano",
	"crackle",
	"rain",
	"clink",
	"purr",
	"bark",
	"rustle",
	"ring",
	"wish",
	"meow",
	"squeak",
	"moo",
	"neigh",
	"baa",
	"oink",
	"howl",
	"growl",
	"cluck"
]
# f: files, a repeat takes the next; v: dB; p: pitch jitter (+-fraction); gap: seconds before the
# same cue may sound again. `egg_<id>` is what `eggs.find(id)` requests.
const CUES := {
	"card_open": {"f": [UI + "Soft/menus/popup_open.ogg"], "v": -10.0, "gap": 0.2},
	"card_close": {"f": [UI + "Soft/menus/popup_close.ogg"], "v": -12.0, "gap": 0.2},
	"menu_open": {"f": [UI + "Soft/menus/menu_open.ogg"], "v": -11.0, "gap": 0.2},
	"menu_close": {"f": [UI + "Soft/menus/menu_close.ogg"], "v": -13.0, "gap": 0.2},
	"tab": {"f": [UI + "Soft/menus/tab_switch.ogg"], "v": -10.0, "p": 0.03, "gap": 0.12},
	"save": {"f": [UI + "Soft/game/save_game.ogg"], "v": -9.0, "gap": 0.5},
	"error": {"f": [UI + "Soft/buttons/error.ogg"], "v": -11.0, "gap": 0.5},
	"nope": {"f": [UI + "Soft/buttons/disabled.ogg"], "v": -11.0, "gap": 0.4},
	"delete": {"f": [UI + "Soft/menus/toggle_off.ogg"], "v": -10.0, "gap": 0.3},
	"done":
	{
		"f":
		[UI + "Soft/rewards/coin.ogg", UI + "Soft/rewards/gem.ogg", UI + "Soft/rewards/star.ogg"],
		"v": -9.0,
		"p": 0.03,
		"gap": 0.25
	},
	"all_done":
	{
		"f": [RT + "powerups/level_up_01.ogg", RT + "powerups/level_up_02.ogg"],
		"v": -10.0,
		"gap": 2.0
	},
	"decorate_on": {"f": [UI + "Soft/menus/toggle_on.ogg"], "v": -11.0, "gap": 0.3},
	"decorate_off": {"f": [UI + "Soft/menus/toggle_off.ogg"], "v": -11.0, "gap": 0.3},
	"place": {"f": [UI + "Soft/game/drop.ogg"], "v": -9.0, "p": 0.04, "gap": 0.15},
	"rotate": {"f": [UI + "Soft/menus/slider_tick.ogg"], "v": -11.0, "p": 0.05, "gap": 0.08},
	"remove": {"f": [UI + "Soft/menus/swipe.ogg"], "v": -11.0, "gap": 0.15},
	"closet_open": {"f": [UI + "Soft/game/inventory_open.ogg"], "v": -10.0, "gap": 0.3},
	"closet_close": {"f": [UI + "Soft/menus/menu_close.ogg"], "v": -12.0, "gap": 0.3},
	"vol": {"f": [UI + "Soft/menus/slider_tick.ogg"], "v": -9.0, "gap": 0.08},
	"clink":
	{
		"f": [RT + "world/drip_02.ogg", RT + "world/bubble_02.ogg", RT + "world/drip_01.ogg"],
		"v": -12.0,
		"p": 0.08,
		"gap": 0.1
	},
	"ring": {"f": [UI + "Soft/text/notification.ogg"], "v": -8.0, "gap": 1.0},
	"wish": {"f": [RT + "pickups/gem_01.ogg"], "v": -11.0, "gap": 1.0},
	"timer_done": {"f": [RT + "jingles/shop_01.ogg"], "v": -9.0, "gap": 2.0},
	"door": {"f": [RT + "doors/door_open_01.ogg"], "v": -12.0, "gap": 2.0},
	"egg_konami": {"f": [RT + "jingles/victory_02.ogg"], "v": -10.0, "gap": 3.0},
	"egg_zoomies":
	{"f": [RT + "jumps/bounce_01.ogg", RT + "jumps/bounce_02.ogg"], "v": -12.0, "gap": 2.0},
	"egg_bring":
	{"f": [RT + "pickups/item_01.ogg", RT + "pickups/item_02.ogg"], "v": -11.0, "gap": 2.0},
	"egg_visitor": {"f": [RT + "doors/door_open_01.ogg"], "v": -12.0, "gap": 2.0},
	"egg_jar_full": {"f": [RT + "pickups/heart_01.ogg"], "v": -10.0, "gap": 2.0},
}

var muted := true
var volume := 0.6
var store := "user://house_sound.json"
var persist := false
var requested: Array = []
var played: Array = []
var mark_left := 0.0
var clock := 0.0

var _root: Node
var _art := ""
var _players: Array = []
var _voices: Array = []
var _last := {}
var _rot := {}
var _oggs := {}
var _loops := {}
var _on := {}
var _cache := {}
var _was := {}
var _rng := RandomNumberGenerator.new()


func setup(root: Node, persist_it: bool = true, art_dir: String = "") -> void:
	_root = root
	_art = art_dir
	persist = persist_it
	if persist and FileAccess.file_exists(store):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(store))
		if d is Dictionary:
			muted = bool(d.get("muted", true))
			volume = clampf(float(d.get("volume", volume)), 0.0, 1.0)


# the cues named by what changed in the room since the last frame, so no call site has to ask
func process(dt: float, h: Object = null) -> void:
	mark_left = maxf(0.0, mark_left - dt)
	clock += dt
	if h == null:
		return
	_edge("card", h.card.is_open(), "card_open", "card_close")
	_edge("jot", h.jot_open, "card_open", "card_close")
	_edge("closet", h.closet_open, "closet_open", "closet_close")
	_edge("decorate", h.decorating, "decorate_on", "decorate_off")
	_edge("door", h.door.present(), "door", "")
	_edge("timer", h.focus.running() and h.focus.progress() >= 1.0, "timer_done", "")


func _edge(key: String, now: bool, up: String, down: String) -> void:
	if now != _was.get(key, false):
		_was[key] = now
		request(up if now else down)


func toggle() -> void:
	muted = not muted
	mark_left = 1.8
	if muted:
		for name in _loops:
			(_loops[name] as AudioStreamPlayer).stop()
	_save()


func nudge(by: float) -> void:
	volume = clampf(snappedf(volume + by, 0.1), 0.0, 1.0)
	mark_left = 1.8
	for name in _loops:
		(_loops[name] as AudioStreamPlayer).volume_db = _db(-22.0)
	_save()
	request("vol")


func _save() -> void:
	if persist:
		var f := FileAccess.open(store, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify({"muted": muted, "volume": volume}))


func _db(base: float) -> float:
	return base + linear_to_db(maxf(volume, 0.0001))


# the single door: logged always (a name with no cue is ignored), heard only when not muted, past
# its gap and within the voices. `arg` is a semitone for the keys.
func request(name: String, arg: float = 0.0) -> void:
	if name == "" or not (CUES.has(name) or name in EVENTS):
		return
	requested.append(name)
	if requested.size() > 400:
		requested = requested.slice(200)
	if muted or _root == null or name in LOOPS or volume <= 0.0:
		return
	var cue: Dictionary = CUES.get(name, {})
	if clock - float(_last.get(name, -99.0)) < float(cue.get("gap", SYNTH_GAP)):
		return
	var pick := _pick(name, arg)
	if pick.is_empty():
		return
	_last[name] = clock
	var s: AudioStream = pick["s"]
	var p := _voice()
	p.stream = s
	p.volume_db = _db(float(pick["db"]))
	p.pitch_scale = 1.0 + _rng.randf_range(-1.0, 1.0) * float(cue.get("p", 0.0))
	p.play()
	_voices.append({"p": p, "end": clock + s.get_length() / p.pitch_scale})
	played.append(name)
	if played.size() > 400:
		played = played.slice(200)


func active() -> int:
	return _voices.filter(func(v): return v["end"] > clock).size()


# a free voice; when all are busy the oldest is cut
func _voice() -> AudioStreamPlayer:
	_voices = _voices.filter(func(v): return v["end"] > clock)
	if _voices.size() >= MAX_VOICES:
		(_voices.pop_front()["p"] as AudioStreamPlayer).stop()
	var busy := _voices.map(func(v): return v["p"])
	for p in _players:
		if not busy.has(p):
			return p
	var p := AudioStreamPlayer.new()
	_root.add_child(p)
	_players.append(p)
	return p


# {"s": stream, "db": dB}: the cue's next file that loads, else its synth, else nothing
func _pick(name: String, arg: float) -> Dictionary:
	var cue: Dictionary = CUES.get(name, {})
	var files: Array = cue.get("f", [])
	for i in files.size():
		var at: int = (int(_rot.get(name, 0)) + i) % files.size()
		var s := _ogg(files[at])
		if s != null:
			_rot[name] = at + 1
			return {"s": s, "db": float(cue["v"])}
	if name in EVENTS:
		return {"s": _stream(name, arg), "db": SYNTH_DB}
	return {}


func _ogg(rel: String) -> AudioStreamOggVorbis:
	if not _oggs.has(rel):
		var path := _art.path_join(rel)
		_oggs[rel] = (
			AudioStreamOggVorbis.load_from_file(path)
			if _art != "" and FileAccess.file_exists(path)
			else null
		)
	return _oggs[rel]


# every cue with the file it plays (`synth` or `none` when it has no file), for `--sounds`
static func listing(art_dir: String) -> String:
	var names := CUES.keys()
	for n in EVENTS:
		if not names.has(n):
			names.append(n)
	var lines: Array = []
	for n in names:
		var found: Array = []
		for rel in CUES.get(n, {}).get("f", []):
			if art_dir != "" and FileAccess.file_exists(art_dir.path_join(rel)):
				found.append(rel)
		lines.append(
			(
				"%s -> %s"
				% [
					n,
					(
						", ".join(found)
						if not found.is_empty()
						else ("synth" if n in EVENTS else "none")
					)
				]
			)
		)
	return "\n".join(lines)


# a quiet loop that runs while `on`: the fire, the rain
func loop(name: String, on: bool) -> void:
	if on != _on.get(name, false):
		_on[name] = on
		if on:
			requested.append(name)
	if _root == null:
		return
	var p: AudioStreamPlayer = _loops.get(name)
	if p == null:
		p = AudioStreamPlayer.new()
		p.stream = _stream(name, 0.0)
		p.volume_db = _db(-22.0)
		_root.add_child(p)
		_loops[name] = p
	if on and not muted and not p.playing:
		p.play()
	elif (not on or muted) and p.playing:
		p.stop()


func _stream(name: String, arg: float) -> AudioStreamWAV:
	var key := "%s:%d" % [name, int(arg)]
	if not _cache.has(key):
		_cache[key] = _pcm(_synth(name, arg), name in LOOPS)
	return _cache[key]


static func _pcm(s: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var peak := 0.001
	for v in s:
		peak = maxf(peak, absf(v))
	var gain := minf(1.0, PEAK / peak) if not loop else PEAK / peak
	var bytes := PackedByteArray()
	bytes.resize(s.size() * 2)
	for i in s.size():
		bytes.encode_s16(i * 2, int(clampf(s[i] * gain, -PEAK, PEAK) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = s.size()
	return w


static func _synth(name: String, arg: float) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	match name:
		"piano", "bad_piano":
			var f := 261.63 * pow(2.0, arg / 12.0) * (1.0 + (0.035 if name == "bad_piano" else 0.0))
			return _tone(f, 1.1, 5.0, [1.0, 0.5, 0.25, 0.12], rng, 0.0)
		"clink":
			var a := _tone(2637.0, 0.22, 22.0, [1.0, 0.3], rng, 0.0)
			var b := _tone(3520.0, 0.22, 26.0, [1.0], rng, 0.0)
			for i in a.size():
				a[i] += b[i] * 0.6
			return a
		"wish":
			var out := PackedFloat32Array()
			out.resize(int(RATE * 1.4))
			for j in 3:
				var t := _tone(
					880.0 * pow(2.0, [0, 4, 9][j] / 12.0), 1.0, 4.0, [1.0, 0.4], rng, 0.0
				)
				var at := int(RATE * 0.16 * j)
				for i in t.size():
					if at + i < out.size():
						out[at + i] += t[i]
			return out
		"ring":
			var out := PackedFloat32Array()
			out.resize(int(RATE * 0.9))
			for j in 6:
				var t := _tone(1320.0 if j % 2 == 0 else 1100.0, 0.09, 10.0, [1.0, 0.3], rng, 0.0)
				var at := int(RATE * 0.12 * j)
				for i in t.size():
					if at + i < out.size():
						out[at + i] += t[i]
			return out
		"bark":
			return _sweep(300.0, 170.0, 0.14, rng)
		"meow":
			return _sweep(520.0, 760.0, 0.35, rng)
		"squeak":
			return _sweep(3200.0, 4200.0, 0.07, rng)
		"moo":
			return _sweep(190.0, 130.0, 0.7, rng)
		"neigh":
			return _sweep(700.0, 350.0, 0.5, rng)
		"baa":
			return _sweep(330.0, 300.0, 0.45, rng)
		"oink":
			return _sweep(240.0, 150.0, 0.16, rng)
		"howl":
			return _sweep(300.0, 620.0, 0.9, rng)
		"growl":
			return _noise(0.5, 0.45, 40.0, rng, 0.0)
		"cluck":
			return _sweep(900.0, 600.0, 0.06, rng)
		"purr":
			return _noise(1.6, 0.22, 25.0, rng, 0.0)
		"rustle":
			return _noise(0.28, 0.9, 0.0, rng, 9.0)
		"crackle":
			return _crackle(rng)
		"rain":
			return _noise(2.0, 0.5, 0.0, rng, 1.0)
	return PackedFloat32Array([0.0])


static func _tone(
	f: float, dur: float, decay: float, parts: Array, _rng: RandomNumberGenerator, _x: float
) -> PackedFloat32Array:
	var n := int(RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		for h in parts.size():
			v += sin(TAU * f * (h + 1) * t) * float(parts[h])
		var env := minf(1.0, t / 0.004) * exp(-decay * t)
		out[i] = v * env
	return out


static func _sweep(
	f0: float, f1: float, dur: float, rng: RandomNumberGenerator
) -> PackedFloat32Array:
	var n := int(RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var u := float(i) / n
		ph += TAU * lerpf(f0, f1, u) / RATE
		var env := sin(PI * u)
		out[i] = (sin(ph) + 0.4 * sin(ph * 2.0) + 0.05 * rng.randf_range(-1, 1)) * env
	return out


# smoothed noise; `wob` Hz modulates it (purr), `edge` shapes it into a short burst
static func _noise(
	dur: float, amp: float, wob: float, rng: RandomNumberGenerator, edge: float
) -> PackedFloat32Array:
	var n := int(RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var a := 0.25 if wob > 0.0 else 0.6
	for i in n:
		lp += (rng.randf_range(-1, 1) - lp) * a
		var t := float(i) / RATE
		var env := 1.0
		if wob > 0.0:
			env = 0.5 + 0.5 * sin(TAU * wob * t)
		if edge > 1.0:
			env = exp(-edge * t) * (0.6 + 0.4 * sin(t * 90.0))
		out[i] = lp * env * amp
	return out


static func _crackle(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := RATE * 2
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		lp += (rng.randf_range(-1, 1) - lp) * 0.05
		out[i] = lp * 0.15
	for j in 14:
		var at := rng.randi_range(0, n - 400)
		var amp := rng.randf_range(0.3, 1.0)
		for i in 200:
			out[at + i] += rng.randf_range(-1, 1) * amp * exp(-i / 40.0)
	return out


# the speaker mark shown a moment after a toggle
func draw_mark(c: CanvasItem, at: Vector2, k: int) -> void:
	if mark_left <= 0.0:
		return
	var a := minf(1.0, mark_left / 0.5)
	var ink := Color("2a2530", a)
	var paper := Color("f3ead6", 0.92 * a)
	c.draw_rect(Rect2(at, Vector2(42, 16) * k * 0.7), paper)
	for i in 5:
		var tall := (3 + i * 2) * k * 0.7
		var bar := Rect2(at + Vector2(23 + i * 3.4, 0) * k * 0.7, Vector2(2.4 * k * 0.7, tall))
		bar.position.y = at.y + 12.0 * k * 0.7 - tall
		c.draw_rect(bar, ink if i < roundi(volume * 5.0) else Color(ink, 0.25 * a))
	var o := at + Vector2(3, 8) * k * 0.7
	c.draw_rect(Rect2(o + Vector2(0, -2.5) * k * 0.7, Vector2(3, 5) * k * 0.7), ink)
	c.draw_colored_polygon(
		PackedVector2Array(
			[
				o + Vector2(3, -2.5) * k * 0.7,
				o + Vector2(8, -6) * k * 0.7,
				o + Vector2(8, 6) * k * 0.7,
				o + Vector2(3, 2.5) * k * 0.7
			]
		),
		ink
	)
	if muted:
		c.draw_line(
			o + Vector2(10, -4) * k * 0.7, o + Vector2(15, 4) * k * 0.7, Color("c8483f", a), 2.0
		)
		c.draw_line(
			o + Vector2(10, 4) * k * 0.7, o + Vector2(15, -4) * k * 0.7, Color("c8483f", a), 2.0
		)
	else:
		c.draw_arc(o + Vector2(8, 0) * k * 0.7, 4.0 * k * 0.7, -0.9, 0.9, 8, ink, 1.5)
		c.draw_arc(o + Vector2(8, 0) * k * 0.7, 7.0 * k * 0.7, -0.9, 0.9, 8, ink, 1.5)
