extends RefCounted

# A desktop notice for a new ask or proposal, for a house with no Telegram paired (Telegram's own
# `on_moves` carries it otherwise, so it is never both). Raised once, only when dated within 48
# hours or the source says money is short, never with the window in front, never in quiet hours.
# `seen` is the keys already waiting; null before the first look, so what was open at launch is not
# new. Linux and macOS go through `notify-send` and `osascript`, Windows through the taskbar flash.
const Telegram := preload("res://telegram.gd")

var seen: Variant = null


# the items to raise now, remembering every key waiting
func fresh(items: Array, front: bool, evening_at: String, morning_at: String, now: float) -> Array:
	var live: Array = items.map(func(m): return str(m["key"]))
	var out: Array = []
	if seen != null and not front and not Telegram.quiet(evening_at, morning_at, now):
		out = items.filter(
			func(m): return not seen.has(str(m["key"])) and Telegram.urgent_item(m, now)
		)
	seen = live
	return out


static func text_of(m: Dictionary) -> String:
	var text := str(m["text"])
	return text if str(m.get("why", "")) == "" else text + "\n" + str(m["why"])


# not verified on macOS or Windows
static func raise(os_name: String, m: Dictionary) -> void:
	var text := text_of(m)
	match os_name:
		"Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD":
			OS.create_process("notify-send", ["--app-name=Asterion", "--", "Your move", text])
		"macOS":
			var q := text.replace("\\", "\\\\").replace('"', '\\"')
			OS.create_process(
				"osascript", ["-e", 'display notification "%s" with title "Your move"' % q]
			)
		"Windows":
			DisplayServer.window_request_attention()
