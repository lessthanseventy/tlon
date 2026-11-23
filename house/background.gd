extends RefCounted

# Keeping the house running with its window shut: the autostart entry per OS, and the one-instance
# handshake. Nothing here runs in a staged or scripted run; `main.gd` decides when.
const APP := "asterion"
const FLAG := "--background"
const RUN_KEY := "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run"
const LIVE := "user://house_running.json"
const SHOW := "user://house_show"
const TELL := "user://house_tell"
const TELL_FLAG := "--tell"
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
					% [_exec_quote(exe), FLAG]
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


# inside a quoted Exec argument `"`, `` ` ``, `$` and `\` take a backslash, and the string value's
# own rule then doubles every backslash: a literal backslash is four in the file
static func _exec_quote(s: String) -> String:
	for c in ["\\", '"', "`", "$"]:
		s = s.replace(c, "\\" + c)
	return s.replace("\\", "\\\\")


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
# dropped for it (unless `ask_window` is false: a hidden launch asks for no window) and false
# answers (this one should quit). Otherwise this one is the house.
static func claim(
	now: float, live: String = LIVE, show: String = SHOW, ask_window: bool = true
) -> bool:
	if alive(now, live):
		var f := FileAccess.open(show, FileAccess.WRITE) if ask_window else null
		if f != null:
			f.store_string("1")
		return false
	beat(now, live)
	return true


static func alive(now: float, live: String = LIVE) -> bool:
	if not FileAccess.file_exists(live):
		return false
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(live))
	return d is Dictionary and now - float(d.get("at", 0.0)) < STALE


# a line for the running house, one per line of the file; a newline inside it is a space
static func hand(line: String, tell: String = TELL) -> bool:
	var f := FileAccess.open(
		tell, FileAccess.READ_WRITE if FileAccess.file_exists(tell) else FileAccess.WRITE
	)
	if f == null:
		return false
	f.seek_end()
	f.store_line(line.replace("\r", " ").replace("\n", " ").strip_edges())
	return true


# the lines handed since last asked, in order; the file is taken, so one is never read twice
static func told(tell: String = TELL) -> Array:
	var taken := tell + ".taken"
	if not FileAccess.file_exists(tell) or DirAccess.rename_absolute(tell, taken) != OK:
		return []
	var out: Array = []
	for l in FileAccess.get_file_as_string(taken).split("\n"):
		if l.strip_edges() != "":
			out.append(l.strip_edges())
	DirAccess.remove_absolute(taken)
	return out


# the command line of a launch that starts the house for a `--tell` when none runs: the same
# arguments without the tell, hidden
static func house_args(cmdline: Array) -> Array:
	var out: Array = []
	var skip := false
	for a in cmdline:
		if skip:
			skip = false
		elif a == TELL_FLAG:
			skip = true
		else:
			out.append(a)
	if FLAG not in out:
		out.append(FLAG)
	return out


# the reply as a desktop notice where the system has a way
static func notify(os_name: String, text: String) -> void:
	match os_name:
		"Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD":
			OS.create_process("notify-send", ["--app-name=Asterion", "Asterion", text])
		"macOS":
			var q := text.replace("\\", "\\\\").replace('"', '\\"')
			OS.create_process(
				"osascript", ["-e", 'display notification "%s" with title "Asterion"' % q]
			)


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
