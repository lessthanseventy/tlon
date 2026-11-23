extends RefCounted

# Keeping the house running with its window shut: the autostart entry per OS, and the one-instance
# handshake. Nothing here runs in a staged or scripted run; `main.gd` decides when.
const APP := "asterion"
const FLAG := "--background"
const RUN_KEY := "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run"
const LIVE := "user://house_running.json"
const SHOW := "user://house_show"
const BEAT := 2.0
const STALE := 6.0


# where and what the login entry is: {"file", "text"} on Linux and macOS, {"reg", "data"} on
# Windows, {} on a system with no way
static func entry(os_name: String, exe: String, home: String, config: String) -> Dictionary:
	match os_name:
		"Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD":
			var dir := config if config != "" else home.path_join(".config")
			return {
				"file": dir.path_join("autostart").path_join(APP + ".desktop"),
				"text":
				(
					'[Desktop Entry]\nType=Application\nName=Asterion\nExec="%s" -- %s\nTerminal=false\n'
					% [exe.replace("\\", "\\\\").replace('"', '\\"'), FLAG]
				)
			}
		"macOS":
			return {
				"file": home.path_join("Library/LaunchAgents").path_join(APP + ".plist"),
				"text":
				(
					(
						'<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0">\n<dict>\n'
						+ "<key>Label</key><string>%s</string>\n<key>ProgramArguments</key>\n"
						+ "<array><string>%s</string><string>--</string><string>%s</string></array>\n"
						+ "<key>RunAtLoad</key><true/>\n</dict>\n</plist>\n"
					)
					% [APP, _xml(exe), FLAG]
				)
			}
		"Windows":
			return {"reg": APP, "data": '"%s" -- %s' % [exe, FLAG]}
	return {}


static func _xml(s: String) -> String:
	return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


# write (`on`) or remove the entry; false when it could not be done
static func set_autostart(on: bool, e: Dictionary) -> bool:
	if e.has("file"):
		if not on:
			return (
				not FileAccess.file_exists(e["file"]) or DirAccess.remove_absolute(e["file"]) == OK
			)
		DirAccess.make_dir_recursive_absolute(str(e["file"]).get_base_dir())
		var f := FileAccess.open(e["file"], FileAccess.WRITE)
		if f == null:
			return false
		f.store_string(e["text"])
		return true
	if e.has("reg"):
		var args: Array = (
			["add", RUN_KEY, "/v", e["reg"], "/t", "REG_SZ", "/d", e["data"], "/f"]
			if on
			else ["delete", RUN_KEY, "/v", e["reg"], "/f"]
		)
		return OS.execute("reg", PackedStringArray(args)) == 0 or not on
	return false


# Is another house running? A heartbeat younger than `STALE` says so; then the show marker is
# dropped for it and false answers (this one should quit). Otherwise this one is the house.
static func claim(now: float, live: String = LIVE, show: String = SHOW) -> bool:
	if FileAccess.file_exists(live):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(live))
		if d is Dictionary and now - float(d.get("at", 0.0)) < STALE:
			var f := FileAccess.open(show, FileAccess.WRITE)
			if f != null:
				f.store_string("1")
			return false
	beat(now, live)
	return true


static func beat(now: float, live: String = LIVE) -> void:
	var f := FileAccess.open(live, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"at": now}))


# was a window asked for by a second launch? takes the marker
static func shown(show: String = SHOW) -> bool:
	if not FileAccess.file_exists(show):
		return false
	DirAccess.remove_absolute(show)
	return true


static func release(live: String = LIVE) -> void:
	if FileAccess.file_exists(live):
		DirAccess.remove_absolute(live)
