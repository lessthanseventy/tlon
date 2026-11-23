extends "res://logic_local.gd"

# The logic checks of background mode: the login entry per system, writing and removing it, and
# which of two launches is the house.
const Background := preload("res://background.gd")

const EXE := "/opt/asterion/asterion"


func run() -> void:
	_entries()
	_files()
	_instances()


func _entries() -> void:
	var linux := Background.entry("Linux", EXE, "/home/sam", "")
	_eq(linux["file"], "/home/sam/.config/autostart/asterion.desktop", "the Linux entry's place")
	_eq(
		linux["text"].contains('Exec="/opt/asterion/asterion" -- --background'),
		true,
		"it starts the app hidden"
	)
	var odd := Background.entry("Linux", '/o/a\\b"c$d', "/home/sam", "")
	_eq(
		odd["text"].contains('Exec="/o/a\\\\\\\\b\\\\"c\\\\$d" -- --background'),
		true,
		"a backslash is four in the file, and the quote and dollar take one backslash then doubled"
	)
	_eq(
		Background.entry("Linux", EXE, "/home/sam", "/cfg")["file"],
		"/cfg/autostart/asterion.desktop",
		"XDG_CONFIG_HOME is honoured"
	)
	var mac := Background.entry("macOS", EXE, "/Users/sam", "")
	_eq(mac["file"], "/Users/sam/Library/LaunchAgents/asterion.plist", "the macOS entry's place")
	_eq(
		[mac["text"].contains("<key>RunAtLoad</key><true/>"), mac["text"].contains(EXE)],
		[true, true],
		"launchd runs it at login"
	)
	var win := Background.entry("Windows", "C:\\Asterion\\asterion.exe", "", "")
	_eq(win["data"], '"C:\\Asterion\\asterion.exe" -- --background', "the Windows Run value")
	_eq(Background.entry("Haiku", EXE, "", ""), {}, "a system with no way gets no entry")


func _files() -> void:
	var dir := OS.get_user_data_dir().path_join("soak_background")
	var e := Background.entry("Linux", EXE, dir, "")
	_eq(Background.set_autostart(true, e), true, "the entry is written")
	_eq(FileAccess.get_file_as_string(e["file"]), e["text"], "with its text")
	_eq(Background.set_autostart(false, e), true, "and removed")
	_eq(FileAccess.file_exists(e["file"]), false, "it is gone")
	_eq(Background.set_autostart(false, e), true, "removing what is not there is fine")
	for d in ["autostart", ".config/autostart", ".config"]:
		DirAccess.remove_absolute(dir.path_join(d))
	DirAccess.remove_absolute(dir)


func _instances() -> void:
	var live := OS.get_user_data_dir().path_join("soak_running.json")
	var show := OS.get_user_data_dir().path_join("soak_show")
	_eq(Background.claim(100.0, live, show), true, "the first launch is the house")
	_eq(Background.claim(101.0, live, show), false, "a launch beside a beating house is not")
	_eq(Background.shown(show), true, "and asks it for its window")
	_eq(Background.shown(show), false, "once")
	Background.beat(102.0, live)
	_eq(
		Background.claim(103.0, live, show, false),
		false,
		"a hidden launch beside a beating house quits"
	)
	_eq(Background.shown(show), false, "and asks for no window")
	_eq(Background.claim(107.0, live, show), false, "a beat within the stale time still holds")
	DirAccess.remove_absolute(show)
	_eq(Background.claim(109.0, live, show), true, "a house that stopped beating is replaced")
	Background.release(live)
	_eq(FileAccess.file_exists(live), false, "a house leaving takes its mark")

	var tell := OS.get_user_data_dir().path_join("soak_tell")
	_eq(Background.told(tell), [], "no file, no lines")
	_eq(Background.alive(200.0, live), false, "no beat, no house")
	Background.beat(200.0, live)
	_eq(Background.alive(201.0, live), true, "a fresh beat is a house")
	_eq(Background.alive(207.0, live), false, "a stale one is not")
	Background.release(live)
	Background.hand("call mum\nsaturday", tell)
	Background.hand("  buy milk ", tell)
	_eq(
		Background.told(tell),
		["call mum saturday", "buy milk"],
		"lines come back in order, newlines flattened"
	)
	_eq(Background.told(tell), [], "and once")
	_eq(
		Background.house_args(["--path", "house", "--", "--tell", "buy milk"]),
		["--path", "house", "--", "--background"],
		"a house started for a tell is hidden and carries no tell"
	)
	_eq(
		Background.house_args(["--", "--background", "--tell", "x"]),
		["--", "--background"],
		"and is not hidden twice"
	)
