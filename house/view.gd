extends RefCounted

const Props := preload("res://props.gd")
const Weather := preload("res://weather.gd")

const S0 := 66.0
const S1 := 100.0
const H0 := 22.0
const H1 := 44.0
const FRAME := Color("ece3d0")
const SILL := Color("d8ccb4")
const CURTAIN := Color("a8605a")
const SKYLINE := [
	[0.02, 0.08, 0.22],
	[0.1, 0.06, 0.34],
	[0.17, 0.09, 0.2],
	[0.27, 0.07, 0.4],
	[0.35, 0.1, 0.26],
	[0.46, 0.06, 0.18],
	[0.53, 0.08, 0.3],
	[0.62, 0.07, 0.2],
]
const CLOUDS := {"partly": 3, "cloudy": 5, "rain": 5, "storm": 5, "snow": 4, "fog": 2}
const CLOUD_COLORS := {
	"partly": Color("f4f6f8"),
	"cloudy": Color("b7bec8"),
	"rain": Color("8b95a4"),
	"storm": Color("5b6475"),
	"snow": Color("e6ebf2"),
	"fog": Color("e8ecef"),
}


static func quad(o: Vector2, k: int) -> PackedVector2Array:
	return Props.wall_quad(o, k, -1, (S0 + S1) / 2.0, (H0 + H1) / 2.0, S1 - S0, H1 - H0)


static func _sub(
	q: PackedVector2Array, u0: float, v0: float, u1: float, v1: float
) -> PackedVector2Array:
	return PackedVector2Array(
		[
			Props.qlerp(q, u0, v0),
			Props.qlerp(q, u1, v0),
			Props.qlerp(q, u1, v1),
			Props.qlerp(q, u0, v1)
		]
	)


static func _shade(col: Color, day: float, overcast: float) -> Color:
	var c := col.lerp(Color("1b2040"), (1.0 - day) * 0.7)
	return c.lerp(Color("8a929c"), overcast * 0.45 * (0.3 + 0.7 * day))


static func draw(
	c: CanvasItem, o: Vector2, k: int, env: Dictionary, t: float, hover: bool, extra: Callable = Callable()
) -> PackedVector2Array:
	var q := quad(o, k)
	var w: String = env["weather"]
	var day: float = env["day"]
	var hour: float = env["hour"]
	var overcast: float = Props.SKIES.get(w, Props.SKIES["clear"])[1]
	var frame := Props.wall_quad(
		o, k, -1, (S0 + S1) / 2.0, (H0 + H1) / 2.0, S1 - S0 + 3.4, H1 - H0 + 3.4
	)
	c.draw_colored_polygon(Props.shifted(frame, Vector2(1.2, 2.0) * k), Color(0, 0, 0, 0.25))
	c.draw_colored_polygon(frame, FRAME)
	_sky(c, q, k, env, t, w, day, hour, overcast)
	_ground(c, q, k, w, day, overcast, t)
	_clouds(c, q, k, w, day, t)
	if extra.is_valid():
		extra.call(q)
	_glass(c, q, k, w, t, day)
	var bar := FRAME.darkened(0.04)
	c.draw_colored_polygon(
		Props.wall_quad(o, k, -1, (S0 + S1) / 2.0, (H0 + H1) / 2.0, 1.5, H1 - H0), bar
	)
	c.draw_colored_polygon(
		Props.wall_quad(o, k, -1, (S0 + S1) / 2.0, H0 + (H1 - H0) * 0.58, S1 - S0, 1.5), bar
	)
	_curtains(c, o, k)
	_sill(c, o, k, w)
	if hover:
		c.draw_polyline(
			PackedVector2Array([frame[0], frame[1], frame[2], frame[3], frame[0]]),
			Color("e8b86d"),
			maxf(1.0, 0.7 * k)
		)
	return frame


static func _sky(
	c: CanvasItem,
	q: PackedVector2Array,
	k: int,
	env: Dictionary,
	t: float,
	w: String,
	day: float,
	hour: float,
	overcast: float
) -> void:
	var sky: Color = env["sky"]
	var glow := (
		clampf(maxf(1.0 - absf(hour - 6.8) / 1.4, 1.0 - absf(hour - 19.0) / 1.6), 0.0, 1.0)
		* (1.0 - overcast)
	)
	var top := sky.darkened(0.22)
	var hor := sky.lightened(0.18).lerp(Color("f6a878"), glow * 0.7)
	var n := 14
	for i in n:
		c.draw_colored_polygon(
			_sub(q, 0, float(i) / n, 1, float(i + 1) / n), hor.lerp(top, (i + 0.5) / n)
		)
	var clear := w in ["clear", "partly"]
	var night := clampf(1.0 - day * 3.0, 0.0, 1.0)
	if night > 0.05 and clear:
		for i in 26:
			var p := Props.qlerp(
				q,
				fmod(i * 0.618 + 0.07, 1.0) * 0.9 + 0.05,
				0.3 + 0.65 * fmod(i * 0.381 + 0.11, 1.0)
			)
			var a := (0.45 + 0.45 * sin(t * 1.6 + i * 2.3)) * night
			c.draw_rect(Rect2(p, Vector2(k, k) * (1.0 if i % 4 != 0 else 1.6)), Color("f8f0c8", a))
		var moon := Props.qlerp(q, 0.7, 0.72)
		c.draw_circle(moon, 3.2 * k, Color("f2eec8", night))
		c.draw_circle(
			moon + Vector2(1.6, -0.8) * k,
			2.9 * k,
			hor.lerp(top, 0.72).darkened(0.05 * (1.0 - night))
		)
	if day > 0.1 and clear:
		var p := clampf((hour - 6.0) / 13.0, 0.0, 1.0)
		var at := Props.qlerp(q, 0.12 + 0.76 * p, 0.2 + 0.62 * sin(PI * p))
		var warm := clampf(1.0 - sin(PI * p) * 2.0, 0.0, 1.0)
		var col := Color("ffe27a").lerp(Color("ff9a4a"), warm)
		c.draw_circle(at, 7.5 * k, Color(col, 0.12))
		c.draw_circle(at, 5.2 * k, Color(col, 0.2))
		c.draw_circle(at, 3.2 * k, col)


static func _ground(
	c: CanvasItem, q: PackedVector2Array, k: int, w: String, day: float, overcast: float, t: float
) -> void:
	var snow := w == "snow"
	var far := _shade(Color("8a97b4"), day, overcast)
	for b in SKYLINE:
		var r := _sub(q, b[0], 0.1, b[0] + b[1], 0.1 + b[2])
		c.draw_colored_polygon(r, far.lerp(Color("e8eef6"), 0.5) if snow else far)
		if snow:
			c.draw_colored_polygon(
				_sub(q, b[0], 0.1 + b[2] - 0.035, b[0] + b[1], 0.1 + b[2]), Color("f4f8fc")
			)
		var lit := (1.0 - day) * (1.0 - overcast * 0.5)
		if lit > 0.05:
			for j in 2:
				var wu: float = b[0] + b[1] * (0.25 + 0.4 * j)
				var wv: float = 0.1 + b[2] * (0.3 + 0.3 * fmod(b[0] * 7.0 + j, 1.0))
				c.draw_rect(
					Rect2(Props.qlerp(q, wu, wv), Vector2(k, k) * 1.2), Color("ffd98a", 0.85 * lit)
				)
	var hill := PackedVector2Array([Props.qlerp(q, 0, 0)])
	for i in 13:
		var u := i / 12.0
		hill.append(Props.qlerp(q, u, 0.12 + 0.07 * sin(i * 1.1 + 0.5) + 0.04 * sin(i * 2.3)))
	hill.append(Props.qlerp(q, 1, 0))
	var green := _shade(Color("5f8f58"), day, overcast)
	c.draw_colored_polygon(hill, green.lerp(Color("eef3f8"), 0.8) if snow else green)
	var trunk := _shade(Color("6b4528"), day, overcast)
	c.draw_colored_polygon(_sub(q, 0.76, 0.05, 0.8, 0.34), trunk)
	var crown := _shade(Color("3f7a4a"), day, overcast)
	var base := Props.qlerp(q, 0.78, 0.48)
	for d in [Vector2(-2.4, 1.0), Vector2(2.4, 1.0), Vector2(0, -1.6), Vector2(0, 1.8)]:
		c.draw_circle(base + d * k, 3.2 * k, crown.lerp(Color("e8eef6"), 0.7) if snow else crown)
	if snow:
		c.draw_circle(base + Vector2(0, -3.0) * k, 2.4 * k, Color("f4f8fc"))
	if w in ["rain", "storm"] and not Weather.shown(w):
		for i in 4:
			var u := 0.1 + 0.22 * i + 0.04 * sin(t * 0.8 + i)
			var a := Props.qlerp(q, u, 0.03 + 0.025 * (i % 2))
			c.draw_line(
				a,
				a + Vector2(-5, 2.5) * k,
				Color("c8d8ee", 0.4 + 0.2 * sin(t * 1.4 + i)),
				maxf(1.0, 0.6 * k)
			)
	if w == "fog" and not Weather.shown(w):
		c.draw_colored_polygon(q, Color("dfe3e6", 0.42))
		c.draw_colored_polygon(_sub(q, 0, 0, 1, 0.45), Color("dfe3e6", 0.3))


static func _clouds(
	c: CanvasItem, q: PackedVector2Array, k: int, w: String, day: float, t: float
) -> void:
	var n: int = CLOUDS.get(w, 0)
	var col: Color = CLOUD_COLORS.get(w, Color.WHITE)
	col = col.lerp(Color("2a3050"), (1.0 - day) * 0.7)
	for i in n:
		var u := fmod(i * 0.29 + t * 0.012 * (1.0 + 0.3 * i), 1.5) - 0.25
		var fade := clampf(minf(u, 1.0 - u) / 0.16, 0.0, 1.0)
		if fade <= 0.0:
			continue
		var v := 0.62 + 0.28 * fmod(i * 0.53, 1.0)
		if w == "storm" or w == "rain":
			v = 0.7 + 0.22 * fmod(i * 0.53, 1.0)
		var r := (2.8 + 0.9 * (i % 3)) * k
		var p := Props.qlerp(q, u, v)
		var cc := Color(col, 0.92 * fade)
		c.draw_circle(p, r, cc)
		c.draw_circle(p + Vector2(-r * 0.9, r * 0.2), r * 0.75, cc)
		c.draw_circle(p + Vector2(r * 0.9, r * 0.25), r * 0.7, cc)
		c.draw_circle(p + Vector2(0, -r * 0.5), r * 0.7, cc)


static func _glass(
	c: CanvasItem, q: PackedVector2Array, k: int, w: String, t: float, day: float
) -> void:
	var art := Weather.draw(c, q, k, w, t, day)
	var wet := w in ["rain", "storm"]
	if wet:
		for i in 0 if art else 22:
			var ph := fmod(t * 1.9 + i * 0.37, 1.0)
			var u := 0.06 + 0.88 * fmod(i * 0.618, 1.0)
			var top := Props.qlerp(q, u, 1.0 - ph * 0.9)
			c.draw_line(
				top, top + Vector2(-0.6, 3.0) * k, Color("e4f0fc", 0.75), maxf(1.0, 0.6 * k)
			)
		for i in 9:
			var u := 0.08 + 0.84 * fmod(i * 0.37, 1.0)
			var v := 1.0 - fmod(i * 0.29 + t * 0.02 * (1.0 + i % 3), 0.9)
			var d := Props.qlerp(q, u, v)
			c.draw_line(d, d + Vector2(0, -4) * k * 0.6, Color("dce8f6", 0.3), maxf(1.0, 0.5 * k))
			c.draw_circle(d, 0.8 * k, Color("e8f2fc", 0.65))
		c.draw_colored_polygon(_sub(q, 0, 0, 1, 0.16), Color("c8d8ee", 0.16))
	elif w == "snow":
		for i in 0 if art else 26:
			var ph := fmod(t * 0.5 + i * 0.29, 1.0)
			var u := 0.06 + 0.88 * fmod(i * 0.618, 1.0) + 0.03 * sin(t * 2.0 + i)
			c.draw_rect(
				Rect2(
					Props.qlerp(q, clampf(u, 0.05, 0.95), 1.0 - ph * 0.92),
					Vector2(k, k) * (1.0 if i % 3 else 1.6)
				),
				Color.WHITE
			)
		c.draw_colored_polygon(_sub(q, 0, 0, 1, 0.07), Color("f4f8fc"))
	c.draw_colored_polygon(
		PackedVector2Array(
			[
				Props.qlerp(q, 0.12, 0),
				Props.qlerp(q, 0.24, 0),
				Props.qlerp(q, 0.52, 1),
				Props.qlerp(q, 0.4, 1)
			]
		),
		Color(1, 1, 1, 0.09)
	)
	if w == "storm" and not art:
		var ph := fmod(t + 4.2, 5.5)
		var flash := 1.0 if ph < 0.1 else (0.6 if ph > 0.18 and ph < 0.3 else 0.0)
		if flash > 0.0:
			c.draw_colored_polygon(q, Color(1, 1, 0.92, 0.6 * flash))
			var bolt := PackedVector2Array()
			for i in 6:
				bolt.append(
					Props.qlerp(q, 0.46 - 0.05 * i + (0.05 if i % 2 else -0.03), 1.0 - 0.15 * i)
				)
			c.draw_polyline(bolt, Color("fffbd0"), maxf(1.5, 0.9 * k))


static func _curtains(c: CanvasItem, o: Vector2, k: int) -> void:
	var mid := (H0 + H1) / 2.0 + 1.0
	var hh := H1 - H0 + 6.0
	for side in [S0 - 0.6, S1 + 0.6]:
		var q := Props.wall_quad(o, k, -1, side, mid, 6.0, hh)
		c.draw_colored_polygon(q, CURTAIN)
		for j in 3:
			var u := 0.2 + 0.3 * j
			c.draw_line(
				Props.qlerp(q, u, 0.0),
				Props.qlerp(q, u, 1.0),
				CURTAIN.darkened(0.25),
				maxf(1.0, 0.5 * k)
			)
		c.draw_colored_polygon(
			PackedVector2Array(
				[
					Props.qlerp(q, 0.0, 0.42),
					Props.qlerp(q, 1.0, 0.42),
					Props.qlerp(q, 1.0, 0.5),
					Props.qlerp(q, 0.0, 0.5)
				]
			),
			CURTAIN.darkened(0.4)
		)
	var rod_a := Props.wall_pt(o, k, -1, S0 - 4.0, H1 + 3.4)
	var rod_b := Props.wall_pt(o, k, -1, S1 + 4.0, H1 + 3.4)
	c.draw_line(rod_a, rod_b, Color("6b4528"), maxf(1.0, 0.9 * k))
	c.draw_circle(rod_a, 1.0 * k, Color("6b4528"))
	c.draw_circle(rod_b, 1.0 * k, Color("6b4528"))


static func _sill(c: CanvasItem, o: Vector2, k: int, w: String) -> void:
	var d := Vector2(3.6, 1.8) * k
	var a := Props.wall_pt(o, k, -1, S0 - 2.0, H0 - 1.2)
	var b := Props.wall_pt(o, k, -1, S1 + 2.0, H0 - 1.2)
	c.draw_colored_polygon(PackedVector2Array([a, b, b + d, a + d]), SILL)
	c.draw_colored_polygon(
		PackedVector2Array(
			[a + d, b + d, b + d + Vector2(0, 1.6 * k), a + d + Vector2(0, 1.6 * k)]
		),
		SILL.darkened(0.22)
	)
	if w == "snow":
		var drift := PackedVector2Array([a + d * 0.2, b + d * 0.2, b + d * 0.9, a + d * 0.9])
		c.draw_colored_polygon(drift, Color("f4f8fc"))
