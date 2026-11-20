extends RefCounted

# The sidebar's small icons, drawn in code on whole pixels: chevrons (left, right, up, down) and a
# plus. `icon_button.gd` is one as a button; `draw` puts one on any canvas.
const WIDTH := 2.0


static func draw(c: CanvasItem, kind: String, at: Vector2, color: Color, r: float = 5.0) -> void:
	var m := at.round()
	var a := Vector2.ZERO
	var b := Vector2.ZERO
	var d := Vector2.ZERO
	match kind:
		"plus":
			c.draw_line(m + Vector2(-r, 0), m + Vector2(r, 0), color, WIDTH)
			c.draw_line(m + Vector2(0, -r), m + Vector2(0, r), color, WIDTH)
			return
		"left":
			a = Vector2(r * 0.5, -r)
			b = Vector2(-r * 0.5, 0)
			d = Vector2(r * 0.5, r)
		"right":
			a = Vector2(-r * 0.5, -r)
			b = Vector2(r * 0.5, 0)
			d = Vector2(-r * 0.5, r)
		"up":
			a = Vector2(-r, r * 0.5)
			b = Vector2(0, -r * 0.5)
			d = Vector2(r, r * 0.5)
		_:
			a = Vector2(-r, -r * 0.5)
			b = Vector2(0, r * 0.5)
			d = Vector2(r, -r * 0.5)
	c.draw_polyline(PackedVector2Array([m + a.round(), m + b.round(), m + d.round()]), color, WIDTH)
