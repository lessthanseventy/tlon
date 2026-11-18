extends SceneTree

# The list of every pack file the house can open, derived from its own loaders and indexes, for
# `mise run house:art-pack`. Writes one art-folder-relative path per line to `--out`, with the
# pack's LICENSE.txt, and prints the count and size per pack.
#   godot --headless --path house --script res://art_pack.gd -- --art-dir <folder> --out <file>
const Look := preload("res://look.gd")
const Packs := preload("res://packs.gd")
const Pets := preload("res://pets.gd")
const Sound := preload("res://sound.gd")
const Guests := preload("res://guests.gd")
const Room := preload("res://room.gd")
const Quirks := preload("res://quirks.gd")
const Glow := preload("res://glow.gd")
const Weather := preload("res://weather.gd")
const Spells := preload("res://spells.gd")
const Fonts := preload("res://fonts.gd")
const SCALES := [1, 2, 3]
const INTERIORS := "isometric-interiors/Gridwright Isometric Interiors/"

var _art := ""
var _files := {}
var _missing := {}


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	_art = args[args.find("--art-dir") + 1]
	var out: String = args[args.find("--out") + 1]
	_interiors()
	_look()
	_pets()
	_guests()
	_visitors()
	_sound()
	_looks()
	_licences()
	var names: Array = _files.keys()
	names.sort()
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string("\n".join(names) + "\n")
	f.close()
	_report(names)
	quit(1 if not _missing.is_empty() else 0)


func _add(rel: String) -> void:
	if FileAccess.file_exists(_art.path_join(rel)):
		_files[rel] = true
	else:
		_missing[rel] = true
		print("MISSING ", rel)


func _scaled(rel: String) -> void:
	for k in SCALES:
		_add(rel.replace("/1x/", "/%dx/" % k))


func _interiors() -> void:
	var index: Dictionary = Packs.extend(_sprites(INTERIORS), _art)
	for id in index:
		var s: Dictionary = index[id]
		var dir: String = str(s["dir"]).trim_prefix(_art + "/") if s.has("dir") else INTERIORS
		_scaled(dir + str(s["file"]))
	_add(INTERIORS + "isometric.json")
	for name in Packs.NAMES:
		_add(Packs.PACKS[name]["dir"] + "isometric.json")


func _sprites(dir: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_art.path_join(dir) + "isometric.json"))
	return parsed["sprites"]


func _under(dir: String, ext: String) -> void:
	for f in DirAccess.get_files_at(_art.path_join(dir)):
		if f.get_extension() == ext:
			_add(dir.path_join(f))


func _look() -> void:
	var look := Look.new()
	look.setup(_art)
	for root in [look.root, look.hero_root]:
		if root == "":
			continue
		var rel: String = root.trim_prefix(_art + "/")
		_under(rel + "/Recipes", "json")
		for build in ["broad", "slim"]:
			for g in DirAccess.get_directories_at(root.path_join("Layers").path_join(build)):
				_under("%s/Layers/%s/%s" % [rel, build, g], "png")
	if look.hero_root != "":
		_add(look.hero_root.trim_prefix(_art + "/") + "/layers.json")


func _pets() -> void:
	var pets := Pets.new()
	pets.setup(_art, 1)
	var animals: String = pets.animals_dir.trim_prefix(_art + "/")
	var chars: String = pets.chars_dir.trim_prefix(_art + "/")
	for kind in Pets.KINDS:
		for anim in Pets.ANIMS:
			_scaled("%sSheets/1x/%s/%s_%s.png" % [animals, kind, kind, anim])
	for c in pets.critters:
		if c.pack == "chars":
			for anim in ["idle", "walk"]:
				_scaled("%sSheets/1x/%s/%s_%s.png" % [chars, c.sheet, c.sheet, anim])
	for name in ["shadow_small", "shadow_medium"]:
		_scaled("%sEffects/1x/%s.png" % [animals, name])
	_scaled(chars + "Effects/1x/shadow.png")
	for name in Room.SKINS:
		_scaled("%sSheets/1x/%s/%s_idle.png" % [chars, name, name])


func _visitors() -> void:
	var city: String = Quirks.PACKS["city"]["dir"]
	for name in Quirks.PEDESTRIANS:
		for anim in ["idle", "walk", "phone"]:
			_scaled("%sSheets/1x/%s/%s_%s.png" % [city, name, name, anim])
	_scaled(city + "Effects/1x/shadow_small.png")
	var monsters: String = Quirks.PACKS["monster"]["dir"]
	for name in Quirks.MONSTERS:
		for anim in ["idle", Quirks.MONSTERS[name][0]]:
			_scaled("%sSheets/1x/%s/%s_%s.png" % [monsters, name, name, anim])
	for shadow in ["shadow_small", "shadow_medium"]:
		_scaled("%sEffects/1x/%s.png" % [monsters, shadow])


func _guests() -> void:
	for meal in Guests.MEALS:
		for dish in meal[3] + meal[4]:
			_add(Guests.FOOD + dish + ".png")


func _sound() -> void:
	for cue in Sound.CUES.values():
		for f in cue["f"]:
			_add(f)


func _looks() -> void:
	for rel in Glow.files() + Weather.files() + Spells.files() + Fonts.files():
		_add(rel)


func _licences() -> void:
	var inner := {}
	for rel in _files:
		inner[rel.get_slice("/", 0) + "/" + rel.get_slice("/", 1)] = true
	for dir in inner:
		_add(dir + "/LICENSE.txt")


func _report(names: Array) -> void:
	var packs := {}
	for rel in names:
		var p: Array = packs.get_or_add(rel.get_slice("/", 0), [0, 0])
		p[0] += 1
		p[1] += FileAccess.open(_art.path_join(rel), FileAccess.READ).get_length()
	var total := [0, 0]
	for p in packs:
		print("PACK %s: %d files, %.1f MB" % [p, packs[p][0], packs[p][1] / 1048576.0])
		total[0] += packs[p][0]
		total[1] += packs[p][1]
	print("TOTAL: %d files, %.1f MB" % [total[0], total[1] / 1048576.0])
