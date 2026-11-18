extends RefCounted

# The second click: a delete that cannot be undone asks for the same button again within a few
# seconds. The time is whatever `tick` has been given, so a scripted run needs no clock.
const WINDOW := 4.0

var key := ""
var left := 0.0


# a repeating thing or a project is deleted for good, so it asks
static func needs(row: Dictionary) -> bool:
	return row.get("kind") == "project" or row.get("every") != null


# true when `what` was asked a moment ago (and forgets it); else arms it and answers false
func ask(what: String) -> bool:
	if key == what and left > 0.0:
		key = ""
		left = 0.0
		return true
	key = what
	left = WINDOW
	return false


func armed(what: String) -> bool:
	return key == what and left > 0.0


func tick(dt: float) -> void:
	left = maxf(0.0, left - dt)
	if left == 0.0:
		key = ""
