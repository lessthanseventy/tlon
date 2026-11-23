extends RefCounted

# Godot keeps user:// in a folder named after the project, so renaming the project moves every
# list and Telegram pairing to an empty folder. The first start under the new name copies what the
# old folder held; the old one is left as it is, for the old build.
const OLD_NAME := "the house"
const MARK := "adopted_from_the_house"
# the marks of a running instance: stale the moment the old build quits
const SKIP := ["house_running.json", "house_show"]


# `new_dir` is OS.get_user_data_dir(); the old folder is its sibling. How many files came across.
static func adopt(new_dir: String, old_name: String = OLD_NAME) -> int:
	var old_dir := new_dir.get_base_dir().path_join(old_name)
	if (
		FileAccess.file_exists(new_dir.path_join(MARK))
		or not DirAccess.dir_exists_absolute(old_dir)
	):
		return 0
	var n := 0
	for f in DirAccess.get_files_at(old_dir):
		if f in SKIP or FileAccess.file_exists(new_dir.path_join(f)):
			continue
		if DirAccess.copy_absolute(old_dir.path_join(f), new_dir.path_join(f)) == OK:
			n += 1
	var mark := FileAccess.open(new_dir.path_join(MARK), FileAccess.WRITE)
	if mark != null:
		mark.store_string(old_dir)
	return n
