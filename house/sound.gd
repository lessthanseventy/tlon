extends RefCounted

# Every sound is synthesized here, nothing is loaded. It starts muted; M toggles and the choice is
# kept in user://house_sound.json ({"muted": bool}).
const RATE := 22050
const PEAK := 0.4
const POOL := 6
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
	"squeak"
]

var muted := true
var store := "user://house_sound.json"
var persist := false
var requested: Array = []
var mark_left := 0.0

var _root: Node
var _players: Array = []
var _loops := {}
var _on := {}
var _cache := {}
var _next := 0


func setup(root: Node, persist_it: bool = true) -> void:
	_root = root
	persist = persist_it
	if persist and FileAccess.file_exists(store):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(store))
		if d is Dictionary:
			muted = bool(d.get("muted", true))


func process(dt: float) -> void:
	mark_left = maxf(0.0, mark_left - dt)


func toggle() -> void:
	muted = not muted
	mark_left = 1.8
	if muted:
		for name in _loops:
			(_loops[name] as AudioStreamPlayer).stop()
	if persist:
		var f := FileAccess.open(store, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify({"muted": muted}))


# the single door: logged always, heard only when not muted. `arg` is a semitone for the keys.
func request(name: String, arg: float = 0.0) -> void:
	requested.append(name)
	if requested.size() > 400:
		requested = requested.slice(200)
	if muted or _root == null or name in LOOPS:
		return
	var p := _player(_next)
	_next = (_next + 1) % POOL
	p.stream = _stream(name, arg)
	p.volume_db = -9.0
	p.play()


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
		p.volume_db = -22.0
		_root.add_child(p)
		_loops[name] = p
	if on and not muted and not p.playing:
		p.play()
	elif (not on or muted) and p.playing:
		p.stop()


func _player(i: int) -> AudioStreamPlayer:
	while _players.size() <= i:
		var p := AudioStreamPlayer.new()
		_root.add_child(p)
		_players.append(p)
	return _players[i]


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
	c.draw_rect(Rect2(at, Vector2(22, 16) * k * 0.7), paper)
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
