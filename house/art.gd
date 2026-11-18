extends RefCounted

# Where the bought art is read from. Every loader takes one `art_dir` string and opens files under it
# through FileAccess/DirAccess/Image, which read a mounted pack at res:// like a folder. The order:
# `--art <folder|.zip|.pck>`, then art the program carries inside it (a `res://art` already there at
# start: scripts/house-build.sh exports it into the pck), then a `house-art.zip|pck` beside the
# executable (macOS: the .app's Resources), then TLON_ART_DIR or the checkout's default folder. No
# art at all is a folder that is not there, which the loaders already draw around.
const MOUNT := "res://art"
const PACK_NAMES := ["house-art.pck", "house-art.zip"]
const DEFAULT_FOLDER := "projects/thatch/packs/x"


static func dir(
	args: Array,
	exe_dir: String = OS.get_executable_path().get_base_dir(),
	carried: bool = DirAccess.dir_exists_absolute(MOUNT)
) -> String:
	var at := args.find("--art")
	if at >= 0 and at + 1 < args.size():
		var given: String = args[at + 1]
		return MOUNT if given.get_extension() in ["zip", "pck"] and _mount(given) else given
	if carried:
		return MOUNT
	for base in [exe_dir, exe_dir.path_join("../Resources")]:
		for name in PACK_NAMES:
			if _mount(base.path_join(name)):
				return MOUNT
	return folder()


static func folder() -> String:
	if OS.has_environment("TLON_ART_DIR"):
		return OS.get_environment("TLON_ART_DIR")
	return OS.get_environment("HOME").path_join(DEFAULT_FOLDER)


static func _mount(pack: String) -> bool:
	return FileAccess.file_exists(pack) and ProjectSettings.load_resource_pack(pack, true)
