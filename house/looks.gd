extends RefCounted

# The four looks the bought packs add (light glow, weather in the window, spell effects, a pixel
# font): which are on, and the one place their textures are read from. Each is on by default and
# his to turn off; a pack that is missing leaves the code-drawn look as it was.
const KEYS := ["glow", "weather_art"]

static var art_dir := ""
static var settings
static var _tex := {}


static func setup(dir: String, store) -> void:
	art_dir = dir
	settings = store
	_tex.clear()


static func on(key: String) -> bool:
	return settings != null and settings.value(key) == true


# a pack texture under the art folder, loaded once; null when the file is not there
static func tex(rel: String) -> Texture2D:
	if _tex.has(rel):
		return _tex[rel]
	var path := art_dir.path_join(rel)
	var t: Texture2D = null
	if FileAccess.file_exists(path):
		var image := Image.load_from_file(path)
		if image != null:
			t = ImageTexture.create_from_image(image)
	_tex[rel] = t
	return t


# the pack textures opened so far
static func loaded() -> Array:
	var out: Array = []
	for rel in _tex:
		if _tex[rel] != null:
			out.append(rel)
	return out
