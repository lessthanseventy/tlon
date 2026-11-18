extends RefCounted

const Hacks := preload("res://hacks.gd")
const MANUAL_SECONDS := 90.0

var on := false
var hacks := Hacks.new()
var forced := false
var manual := 0.0


func setup(seed_value: int) -> void:
	hacks.setup(seed_value)


func force_on(value: bool) -> void:
	forced = true
	on = value


func process(dt: float, watching: bool, deep_night: bool) -> void:
	manual = maxf(0.0, manual - dt)
	if not forced:
		on = manual > 0.0 or (watching and not deep_night)
	hacks.update(dt, on)


func click() -> void:
	if on:
		hacks.advance()
	elif not forced:
		manual = MANUAL_SECONDS
		on = true
	else:
		on = true
		hacks.advance()


static func sub(
	q: PackedVector2Array, u0: float, v0: float, u1: float, v1: float
) -> PackedVector2Array:
	return PackedVector2Array(
		[
			q[0] + (q[1] - q[0]) * u0 + (q[3] - q[0]) * v0,
			q[0] + (q[1] - q[0]) * u1 + (q[3] - q[0]) * v0,
			q[0] + (q[1] - q[0]) * u1 + (q[3] - q[0]) * v1,
			q[0] + (q[1] - q[0]) * u0 + (q[3] - q[0]) * v1,
		]
	)


func screen(c: CanvasItem, q: PackedVector2Array) -> void:
	if not on:
		return
	hacks.draw(c, q)
