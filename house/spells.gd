extends RefCounted

# Spell effects of the spell pack, each played once where it happens and then gone: a ring of
# flame at the hearth when a hero's spell lights the fire, a sparkle at the window for a wish.
# Every frame is 64x64 with its anchor in the middle, and the sheet is a row of `frames`; `scale`
# is screen pixels per pack pixel at the room's scale 2.
const Looks := preload("res://looks.gd")
const DIR := "spell-vfx/Gridwright Spell VFX/Sheets/1x/"
const CELL := 64
const EFFECTS := {
	"cast": {"file": DIR + "cast_fire.png", "frames": 8, "fps": 8.0, "scale": 1.0},
	"wish": {"file": DIR + "impact_holy.png", "frames": 7, "fps": 8.0, "scale": 0.5},
}

var live: Array = []


static func files() -> Array:
	var out: Array = []
	for e in EFFECTS.values():
		out.append(e["file"])
	return out


# false when the look is off or its sheet is not there: the caller has nothing to do about it
func play(name: String, at: Vector2) -> bool:
	if not Looks.on("spells") or Looks.tex(EFFECTS[name]["file"]) == null:
		return false
	live.append({"name": name, "at": at, "t": 0.0})
	return true


func process(dt: float) -> void:
	for e in live:
		e["t"] += dt
	live = live.filter(
		func(e): return e["t"] * EFFECTS[e["name"]]["fps"] < EFFECTS[e["name"]]["frames"]
	)


func draw(c: CanvasItem, k: int) -> void:
	for e in live:
		var spec: Dictionary = EFFECTS[e["name"]]
		var frame := int(e["t"] * spec["fps"])
		var side := CELL * float(spec["scale"]) * k / 2.0
		c.draw_texture_rect_region(
			Looks.tex(spec["file"]),
			Rect2(e["at"] - Vector2(side, side) / 2.0, Vector2(side, side)),
			Rect2(frame * CELL, 0, CELL, CELL)
		)
