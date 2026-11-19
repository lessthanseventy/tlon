extends RefCounted

const Hacks := preload("res://hacks.gd")

var on := false
var hacks := Hacks.new()
var forced := false
var override := 0
var _auto := false
var _deep := false


func setup(seed_value: int) -> void:
	hacks.setup(seed_value)


func force_on(value: bool) -> void:
	forced = true
	on = value


func process(dt: float, watching: bool, deep_night: bool) -> void:
	var auto := watching and not deep_night
	if auto != _auto or (deep_night and not _deep):
		override = 0
	_auto = auto
	_deep = deep_night
	if not forced:
		on = auto if override == 0 else override > 0
	hacks.update(dt, on)


func click() -> void:
	if forced:
		on = not on
	else:
		override = -1 if on else 1
		on = override > 0


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
