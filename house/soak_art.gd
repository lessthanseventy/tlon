extends RefCounted

# The soak's checks of where the art is read from (`art.gd`): the order arg > art carried in the
# program > pack beside the executable > folder > none,
# over packs made here from generated 1x1 PNGs, never the bought art.
const Art := preload("res://art.gd")
const Room := preload("res://room.gd")

var s
var _tmp: DirAccess


func _init(soak) -> void:
	s = soak


func _png(path: String, colour: Color) -> void:
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(colour)
	img.save_png(path)


func _folder(name: String, marker: String) -> String:
	var dir := _tmp.get_current_dir().path_join(name)
	DirAccess.make_dir_recursive_absolute(dir.path_join("sub"))
	var f := FileAccess.open(dir.path_join("marker.txt"), FileAccess.WRITE)
	f.store_string(marker)
	f.close()
	_png(dir.path_join("sub/dot.png"), Color.RED)
	return dir


# a zip whose entries sit under art/, the way scripts/house-art-pack.sh lays them out
func _zip(at: String, marker: String) -> String:
	DirAccess.make_dir_recursive_absolute(at)
	var path := at.path_join("house-art.zip")
	var z := ZIPPacker.new()
	z.open(path)
	z.start_file("art/marker.txt")
	z.write_file(marker.to_utf8_buffer())
	z.close_file()
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(Color.BLUE)
	z.start_file("art/sub/dot.png")
	z.write_file(img.save_png_to_buffer())
	z.close_file()
	z.close()
	return path


func _marker(dir: String) -> String:
	return FileAccess.get_file_as_string(dir.path_join("marker.txt"))


func run() -> void:
	_tmp = DirAccess.create_temp("house-art-soak")
	var base := _tmp.get_current_dir()
	var env_before := OS.get_environment("TLON_ART_DIR")
	var folder := _folder("folder", "folder")
	var other := _folder("other", "other")
	OS.set_environment("TLON_ART_DIR", folder)
	var bare := base.path_join("bare")
	DirAccess.make_dir_recursive_absolute(bare)
	s._check(Art.dir([], bare, false) == folder, "with no pack and no arg the art folder is read")
	s._check(Art.dir([], bare, true) == Art.MOUNT, "art carried inside the program beats the folder")
	s._check(Art.dir(["--art", other], bare, true) == other, "--art beats art carried inside")
	var beside := base.path_join("beside")
	_zip(beside, "beside")
	s._check(Art.dir(["--art", other], beside) == other, "--art beats a pack beside the executable")
	s._check(not FileAccess.file_exists("res://art/marker.txt"), "an --art folder mounts nothing")
	var got := Art.dir([], beside, false)
	s._check(got == Art.MOUNT and _marker(got) == "beside", "a pack beside the executable beats the folder")
	var given := _zip(base.path_join("given"), "given")
	got = Art.dir(["--art", given], beside)
	s._check(got == Art.MOUNT and _marker(got) == "given", "--art <pack> beats the pack beside the executable")
	var app := base.path_join("the.app/Contents")
	_zip(app.path_join("Resources"), "resources")
	DirAccess.make_dir_recursive_absolute(app.path_join("MacOS"))
	got = Art.dir([], app.path_join("MacOS"), false)
	s._check(got == Art.MOUNT and _marker(got) == "resources", "an app's Resources holds the pack")
	var room := Room.new()
	room.art_dir = got
	s._check(room._load_texture(got.path_join("sub/dot.png")) != null, "a loader reads a texture out of the pack")
	s._check(DirAccess.get_files_at(got.path_join("sub")) == PackedStringArray(["dot.png"]), "the pack lists like a folder")
	room.free()
	OS.set_environment("TLON_ART_DIR", base.path_join("nothing"))
	got = Art.dir([], bare, false)
	s._check(got == base.path_join("nothing") and not FileAccess.file_exists(got.path_join("marker.txt")), "no pack and no folder is no art")
	OS.set_environment("TLON_ART_DIR", env_before)
