extends RefCounted

const CREATOR := "isometric-character-creator"
const SHEET := Vector2i(3456, 512)
const STORE := "user://house_person.json"
const ANIMS := {
	"idle": [0, 4, 6.0],
	"walk": [4, 8, 10.0],
	"run": [12, 6, 12.0],
	"wave": [18, 6, 10.0],
	"talk": [24, 4, 6.0],
	"cheer": [28, 6, 10.0],
	"pickup": [34, 6, 10.0],
	"sit": [40, 4, 5.0],
	"type": [44, 4, 8.0],
	"eat": [48, 6, 8.0],
}
const DEFAULT := {
	"build": "broad",
	"skin": "pale",
	"hair": "swept",
	"hair_c": "darkbrown",
	"beard": "",
	"top": "shirt",
	"top_c": "blue",
	"bottom": "trousers",
	"bottom_c": "grey",
	"shoes": "shoes",
	"shoes_c": "black",
	"hat": "",
	"eyewear": "glasses_black",
	"scarf": "",
	"backpack": "",
	"apron": "",
	"flat_skin": 1,
	"flat_shirt": 0,
	"flat_hat": 0,
	"flat_glasses": 0,
	"flat_scarf": 0,
}
const LAYER_ROWS := [
	["build", "Build"],
	["skin", "Skin"],
	["hair", "Hair"],
	["hair_c", "Hair colour"],
	["beard", "Beard"],
	["top", "Top"],
	["top_c", "Top colour"],
	["bottom", "Trousers"],
	["bottom_c", "Trousers colour"],
	["shoes", "Shoes"],
	["shoes_c", "Shoe colour"],
	["hat", "Hat"],
	["eyewear", "Eyewear"],
	["scarf", "Scarf"],
	["backpack", "Backpack"],
	["apron", "Apron"],
]
const SLOTS := {
	"eyewear": ["glasses", "sunglasses"],
	"scarf": ["scarf"],
	"backpack": ["backpack"],
	"apron": ["apron"],
}
const OPTIONAL := ["hair", "beard", "hat", "eyewear", "scarf", "backpack", "apron"]
const FLAT_SKIN := [
	Color("f1c9a5"), Color("e0b07a"), Color("c68b59"), Color("8d5a3b"), Color("5e3a26")
]
const FLAT_SHIRT := [
	Color("6f8fb0"),
	Color("b0553c"),
	Color("5f8a4f"),
	Color("8a6fb0"),
	Color("d9b86a"),
	Color("4a4f5c"),
	Color("e8e4dc"),
	Color("c8483f"),
]
const FLAT_HATS := ["none", "cap", "beanie", "top hat"]
const FLAT_SCARF := [Color(0, 0, 0, 0), Color("c8483f"), Color("4f8fd9"), Color("5fb37a")]
const INK := Color("2a2530")

var root := ""
var store := STORE
var layered := false
var cfg := DEFAULT.duplicate()
var opts := {}
var recipes: Array = []

var _sheets := {}
var _imgs := {}


func setup(art_dir: String) -> void:
	var base := art_dir.path_join(CREATOR)
	var subs := PackedStringArray()
	if DirAccess.dir_exists_absolute(base):
		subs = DirAccess.get_directories_at(base)
	if subs.size() == 1:
		root = base.path_join(subs[0])
	layered = root != "" and DirAccess.dir_exists_absolute(root.path_join("Layers/broad"))
	if layered:
		_scan()
		_recipes()
	_load()


func _scan() -> void:
	opts = {"build": ["broad", "slim"]}
	var groups := {}
	for g in ["body", "hair", "facial", "top", "bottom", "shoes", "headwear", "accessory"]:
		var styles: Array = []
		var colours: Array = []
		var combos: Array = []
		for f in DirAccess.get_files_at(root.path_join("Layers/broad/" + g)):
			if not f.ends_with(".png"):
				continue
			var rest := f.trim_suffix(".png").trim_prefix("broad_" + g + "_")
			var i := rest.rfind("_")
			var style := rest.substr(0, i) if i >= 0 else rest
			var colour := rest.substr(i + 1) if i >= 0 else ""
			if not styles.has(style):
				styles.append(style)
			if colour != "" and not colours.has(colour):
				colours.append(colour)
			combos.append(rest)
		styles.sort()
		colours.sort()
		combos.sort()
		groups[g] = {"styles": styles, "colours": colours, "combos": combos}
	opts["skin"] = groups["body"]["combos"]
	opts["hair"] = [""] + groups["hair"]["styles"]
	opts["hair_c"] = groups["hair"]["colours"]
	opts["beard"] = [""] + groups["facial"]["combos"]
	opts["top"] = groups["top"]["styles"]
	opts["top_c"] = groups["top"]["colours"]
	opts["bottom"] = groups["bottom"]["styles"]
	opts["bottom_c"] = groups["bottom"]["colours"]
	opts["shoes"] = groups["shoes"]["styles"]
	opts["shoes_c"] = groups["shoes"]["colours"]
	opts["hat"] = [""] + groups["headwear"]["combos"]
	for slot in SLOTS:
		opts[slot] = (
			[""]
			+ groups["accessory"]["combos"].filter(
				func(combo: String) -> bool: return slot_of(combo) == slot
			)
		)


static func slot_of(combo: String) -> String:
	var style := combo.substr(0, maxi(combo.rfind("_"), 0))
	for slot in SLOTS:
		if style in SLOTS[slot]:
			return slot
	return ""


func _recipes() -> void:
	recipes = []
	var names: Array = []
	for f in DirAccess.get_files_at(root.path_join("Recipes")):
		if f.ends_with(".json"):
			names.append(f)
	names.sort()
	for f in names:
		var parsed: Variant = JSON.parse_string(
			FileAccess.get_file_as_string(root.path_join("Recipes").path_join(f))
		)
		if parsed is Dictionary and parsed.get("layers") is Array:
			recipes.append({"name": str(parsed.get("name", f)), "cfg": _from_recipe(parsed)})


func _from_recipe(r: Dictionary) -> Dictionary:
	var c := DEFAULT.duplicate()
	c["build"] = str(r.get("build", "broad"))
	c["hair"] = ""
	c["beard"] = ""
	c["hat"] = ""
	for slot in SLOTS:
		c[slot] = ""
	for l in r["layers"]:
		var key: String = l[0]
		var colour: String = l[1]
		if key == "body":
			c["skin"] = colour
			continue
		var group := key.get_slice("_", 0)
		var style := key.substr(group.length() + 1)
		match group:
			"shoes", "bottom", "top", "hair":
				c[group] = style
				c[group + "_c"] = colour
			"facial":
				c["beard"] = style + "_" + colour
			"headwear":
				c["hat"] = style + "_" + colour
			"accessory":
				var slot := slot_of(style + "_" + colour)
				if slot != "":
					c[slot] = style + "_" + colour
	return c


func _load() -> void:
	var parsed: Variant = (
		JSON.parse_string(FileAccess.get_file_as_string(store))
		if FileAccess.file_exists(store)
		else null
	)
	var base: Dictionary = (
		recipes[_recipe_index("office")]["cfg"]
		if layered and not recipes.is_empty()
		else DEFAULT.duplicate()
	)
	if parsed is Dictionary:
		for key in base:
			if parsed.has(key) and typeof(parsed[key]) == typeof(base[key]):
				base[key] = parsed[key]
		if parsed.get("extra") is String:
			for slot in SLOTS:
				base[slot] = ""
			var slot := slot_of(parsed["extra"])
			if slot != "":
				base[slot] = parsed["extra"]
	cfg = _sane(base)


func _recipe_index(name: String) -> int:
	for i in recipes.size():
		if recipes[i]["name"] == name:
			return i
	return 0


func _sane(c: Dictionary) -> Dictionary:
	if layered:
		for key in opts:
			if not (opts[key] as Array).has(c.get(key)):
				c[key] = "" if key in OPTIONAL else opts[key][0]
	return c


# `--look key=value,...`: a look for a picture, not kept
func stage(spec: String) -> void:
	for pair in spec.split(",", false):
		var kv := pair.split("=")
		cfg[kv[0]] = kv[1] if kv.size() > 1 else ""
	cfg = _sane(cfg)


func save() -> void:
	var f := FileAccess.open(store, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(cfg))


func random_cfg() -> Dictionary:
	var c := cfg.duplicate()
	if layered:
		for key in opts:
			var list: Array = opts[key]
			var pick: String = list[randi() % list.size()]
			if key in OPTIONAL and key != "hair" and randf() < 0.5:
				pick = ""
			c[key] = pick
	else:
		c["flat_skin"] = randi() % FLAT_SKIN.size()
		c["flat_shirt"] = randi() % FLAT_SHIRT.size()
		c["flat_hat"] = randi() % FLAT_HATS.size()
		c["flat_glasses"] = randi() % 2
		c["flat_scarf"] = randi() % FLAT_SCARF.size()
	return _sane(c)


func _file(b: String, group: String, name: String) -> String:
	return root.path_join("Layers/%s/%s/%s_%s.png" % [b, group, b, name])


func layer_paths(c: Dictionary, held: String = "") -> Array:
	var b: String = c["build"]
	var out: Array = [
		_file(b, "body", "body_" + str(c["skin"])),
		_file(b, "shoes", "shoes_%s_%s" % [c["shoes"], c["shoes_c"]]),
		_file(b, "bottom", "bottom_%s_%s" % [c["bottom"], c["bottom_c"]]),
		_file(b, "top", "top_%s_%s" % [c["top"], c["top_c"]]),
	]
	for slot in ["apron", "backpack", "scarf", "eyewear"]:
		if c[slot] != "":
			out.append(_file(b, "accessory", "accessory_" + str(c[slot])))
	if c["beard"] != "":
		out.append(_file(b, "facial", "facial_" + str(c["beard"])))
	if c["hair"] != "":
		out.append(_file(b, "hair", "hair_%s_%s" % [c["hair"], c["hair_c"]]))
	if c["hat"] != "":
		out.append(_file(b, "headwear", "headwear_" + str(c["hat"])))
	if held != "":
		out.append(_file(b, "held", "held_" + held))
	return out


func _layer(path: String) -> Image:
	if _imgs.has(path):
		return _imgs[path]
	if _imgs.size() > 40:
		_imgs.clear()
	var img := Image.load_from_file(path)
	if img != null and img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	_imgs[path] = img
	return img


func _compose(c: Dictionary, held: String) -> Image:
	var img := Image.create(SHEET.x, SHEET.y, false, Image.FORMAT_RGBA8)
	for p in layer_paths(c, held):
		var l := _layer(p)
		if l != null:
			img.blend_rect(l, Rect2i(Vector2i.ZERO, l.get_size()), Vector2i.ZERO)
	return img


func sheet(c: Dictionary, k: int, held: String = "") -> Texture2D:
	var key := "%s%s@%d" % [JSON.stringify(c), held, k]
	if _sheets.has(key):
		return _sheets[key]
	if _sheets.size() > 5:
		_sheets.clear()
	var img := _compose(c, held)
	if k > 1:
		img.resize(SHEET.x * k, SHEET.y * k, Image.INTERPOLATE_NEAREST)
	var tex := ImageTexture.create_from_image(img)
	_sheets[key] = tex
	return tex


func preview(c: Dictionary, k: int) -> Texture2D:
	var img := _compose(c, "").get_region(Rect2i(0, 0, 256, 64))
	img.resize(256 * k, 64 * k, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(img)


func draw_frame(
	canvas: CanvasItem,
	tex: Texture2D,
	anim: String,
	dir: int,
	t: float,
	feet: Vector2,
	k: int,
	frozen: bool = false
) -> void:
	var a: Array = ANIMS[anim]
	var frame := 0 if frozen else int(t * a[2]) % int(a[1])
	var cell := 64 * k
	canvas.draw_texture_rect_region(
		tex,
		Rect2((feet - Vector2(32, 46) * k).round(), Vector2(cell, cell)),
		Rect2((int(a[0]) + frame) * cell, dir * cell, cell, cell)
	)


func draw_flat(
	canvas: CanvasItem, f: Vector2, k: float, seated: bool, t: float, c: Dictionary = {}
) -> void:
	var cc := cfg if c.is_empty() else c
	var skin: Color = FLAT_SKIN[int(cc["flat_skin"]) % FLAT_SKIN.size()]
	var shirt: Color = FLAT_SHIRT[int(cc["flat_shirt"]) % FLAT_SHIRT.size()]
	var h := 0.72 if seated else 1.0
	var bob := sin(t * 3.0) * 0.35 * k
	canvas.draw_rect(Rect2(f + Vector2(-4, -10 * h) * k, Vector2(8, 10 * h) * k), Color("4a4f5c"))
	canvas.draw_rect(
		Rect2(f + Vector2(-5.5, -24 * h) * k + Vector2(0, bob), Vector2(11, 15 * h) * k), shirt
	)
	var scarf: Color = FLAT_SCARF[int(cc["flat_scarf"]) % FLAT_SCARF.size()]
	if scarf.a > 0.0:
		canvas.draw_rect(
			Rect2(f + Vector2(-5, -26 * h) * k + Vector2(0, bob), Vector2(10, 3) * k), scarf
		)
	var head := f + Vector2(0, -31 * h) * k + Vector2(0, bob)
	canvas.draw_circle(head, 5.5 * k, skin)
	canvas.draw_rect(Rect2(head + Vector2(-2.6, -0.6) * k, Vector2(1.2, 1.2) * k), INK)
	canvas.draw_rect(Rect2(head + Vector2(1.4, -0.6) * k, Vector2(1.2, 1.2) * k), INK)
	if int(cc["flat_glasses"]) == 1:
		canvas.draw_rect(
			Rect2(head + Vector2(-3.4, -1.4) * k, Vector2(3, 2.6) * k),
			INK,
			false,
			maxf(1.0, 0.5 * k)
		)
		canvas.draw_rect(
			Rect2(head + Vector2(0.4, -1.4) * k, Vector2(3, 2.6) * k),
			INK,
			false,
			maxf(1.0, 0.5 * k)
		)
	var hat := int(cc["flat_hat"]) % FLAT_HATS.size()
	var hat_col := Color("b0553c")
	match hat:
		1:
			canvas.draw_rect(Rect2(head + Vector2(-5.5, -7) * k, Vector2(11, 4) * k), hat_col)
			canvas.draw_rect(
				Rect2(head + Vector2(-1, -3.4) * k, Vector2(8, 1.6) * k), hat_col.darkened(0.25)
			)
		2:
			canvas.draw_rect(
				Rect2(head + Vector2(-5.5, -8) * k, Vector2(11, 5) * k), Color("4f8fd9")
			)
			canvas.draw_rect(
				Rect2(head + Vector2(-5.8, -4) * k, Vector2(11.6, 1.6) * k), Color("e8e4dc")
			)
		3:
			canvas.draw_rect(Rect2(head + Vector2(-7, -5) * k, Vector2(14, 1.8) * k), INK)
			canvas.draw_rect(Rect2(head + Vector2(-4.5, -13) * k, Vector2(9, 8.4) * k), INK)
			canvas.draw_rect(
				Rect2(head + Vector2(-4.5, -7.2) * k, Vector2(9, 1.6) * k), Color("c8483f")
			)
