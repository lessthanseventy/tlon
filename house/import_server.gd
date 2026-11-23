extends SceneTree

# `godot --headless --path house --script res://import_server.gd -- [URL] [--write]`: read the
# server's home (`GET /api/home/export`, URL or the settings' own) and say what it would add to the
# house's own list. Without `--write` that is all; with it the list is written and its times set,
# and the counts of both sides are printed. Run twice it adds nothing. The server loses nothing.
const Import := preload("res://import_list.gd")
const LocalList := preload("res://local_list.gd")
const Settings := preload("res://settings.gd")
const Background := preload("res://background.gd")
const BackendHttp := preload("res://backend_http.gd")

var _write := false
var _list


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_write = "--write" in args
	var settings := Settings.new()
	settings.setup(true)
	var base := settings.server_url()
	for a in args:
		if a.begins_with("http"):
			base = a.trim_suffix("/")
	var bias := float(Time.get_time_zone_from_system()["bias"]) * 60.0
	_list = LocalList.new(
		LocalList.STORE, func() -> float: return Time.get_unix_time_from_system() + bias, bias
	)
	_list.load_file()
	if _list.notice != "":
		_stop(_list.notice)
		return
	if _write and _running():
		_stop("the house is running: close it first, it would write its own list over this one")
		return
	var http := BackendHttp.new()
	http.base = base
	root.add_child(http)
	await process_frame
	print("reading %s/api/home/export" % base)
	http.fetch("/api/home/export", _read.bind(settings), 30.0)


func _running() -> bool:
	if not FileAccess.file_exists(Background.LIVE):
		return false
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(Background.LIVE))
	var at := float(d.get("at", 0.0)) if d is Dictionary else 0.0
	return Time.get_unix_time_from_system() - at < Background.STALE


func _read(reached: bool, code: int, parsed: Variant, settings: RefCounted) -> void:
	if not (reached and code == 200 and parsed is Dictionary):
		_stop("the server did not answer the export (reached %s, code %d)" % [reached, code])
		return
	var report: Dictionary = Import.run(_list, parsed, _write)
	if report.has("error"):
		_stop(report["error"])
		return
	print(_table(report))
	if _write:
		for key in report["settings"]:
			settings.put(key, report["settings"][key])
		var wrong := _mismatch(report)
		if wrong != "":
			_stop("written, but the counts differ: " + wrong)
			return
		print("written: %s" % LocalList.STORE)
	else:
		print("dry run: nothing written; add -- --write to import")
	quit(0)


# after a write every row the server gave must be in the list: server counts == local counts
func _mismatch(report: Dictionary) -> String:
	var server: Dictionary = report["server"]
	var local: Dictionary = report["local"]
	for kind in server:
		if int(local.get(kind, 0)) != int(server[kind]):
			return "%s: server %d, local %d" % [kind, server[kind], local.get(kind, 0)]
	return ""


func _table(report: Dictionary) -> String:
	var out := "%-10s %7s %7s %7s %7s\n" % ["kind", "server", "added", "already", "local"]
	for kind in report["server"]:
		out += (
			"%-10s %7d %7d %7d %7d\n"
			% [
				kind,
				report["server"][kind],
				report["added"].get(kind, 0),
				report["already"].get(kind, 0),
				report["local"].get(kind, 0),
			]
		)
	out += "proposals not carried (the list has no sources): %d\n" % report["proposals"]
	out += "settings: %s" % JSON.stringify(report["settings"])
	return out


func _stop(line: String) -> void:
	printerr("import: " + line)
	quit(1)
