extends "res://logic_local.gd"

# The logic check of the rename: a person's list and Telegram pairing follow them to the new folder.
const Adopt := preload("res://adopt.gd")


func run() -> void:
	var root := OS.get_user_data_dir().path_join("soak_adopt")
	var old_dir := root.path_join("the house")
	var new_dir := root.path_join("Asterion")
	DirAccess.make_dir_recursive_absolute(old_dir)
	DirAccess.make_dir_recursive_absolute(new_dir)
	for f in ["house_list.json", "house_telegram.json", "house_running.json"]:
		_put(old_dir.path_join(f), "old " + f)
	_put(new_dir.path_join("house_chat.json"), "new chat")
	_put(old_dir.path_join("house_chat.json"), "old chat")
	_eq(Adopt.adopt(new_dir), 2, "the list and the pairing come across; a running mark does not")
	_eq(
		FileAccess.get_file_as_string(new_dir.path_join("house_list.json")),
		"old house_list.json",
		"the list is whole"
	)
	_eq(
		FileAccess.get_file_as_string(new_dir.path_join("house_telegram.json")),
		"old house_telegram.json",
		"the pairing is whole"
	)
	_eq(
		FileAccess.get_file_as_string(new_dir.path_join("house_chat.json")),
		"new chat",
		"a file already there is not overwritten"
	)
	_eq(
		FileAccess.file_exists(new_dir.path_join("house_running.json")),
		false,
		"the old build's running mark stays behind"
	)
	_eq(
		FileAccess.file_exists(old_dir.path_join("house_list.json")),
		true,
		"the old folder keeps its files"
	)
	DirAccess.remove_absolute(new_dir.path_join("house_list.json"))
	_eq(Adopt.adopt(new_dir), 0, "once only: a list deleted since is not brought back")
	_eq(FileAccess.file_exists(new_dir.path_join("house_list.json")), false, "and stays deleted")
	_eq(Adopt.adopt(root.path_join("none"), "no such folder"), 0, "no old folder, nothing to do")
	for d in [old_dir, new_dir, root]:
		for f in DirAccess.get_files_at(d):
			DirAccess.remove_absolute(d.path_join(f))
		DirAccess.remove_absolute(d)


func _put(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
