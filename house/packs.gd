extends RefCounted

# The other bought packs the decorate catalogue draws from. Each is merged into the interiors'
# sprite index under "<pack>." ids, so a saved piece names its pack and an id without a dot is
# still the interiors'. Only the curated pieces, walls and floors are merged; a pack that is not
# there adds nothing. Every pack shares the interiors' 32x16 grid, anchors and footprints.

const NAMES := ["castle", "mansion", "farm"]
const TABS := ["home", "castle", "mansion", "garden"]
const FRAME := "_f(\\d)$"
const SIDE := "_(nwse|nesw|sw|se|ne|nw)$"
const WALL_PARTS := ["_ne", "_corner", "_ne_window", "_nw", "_nw_door", "_nw_window"]

# pieces: [base id, group, options]; a group's pieces stay together. Options: `faces` (only
# these), `still` (frame 1 only, no animation), `as` (the id it is saved under)
const PACKS := {
	"castle":
	{
		"dir": "isometric-castle-interiors/Gridwright Isometric Castle Interiors/",
		"tab": "castle",
		"walls": ["ashlar", "rubble", "lime", "dungeon"],
		"floors": ["flagstone", "worn", "cobble", "planks", "straw"],
		"pieces":
		[
			["throne", "court"],
			["royal_dais", "court"],
			["high_chair", "court"],
			["pillar", "court"],
			["standing_banner_red", "court", {"as": "banner_red"}],
			["standing_banner_blue", "court", {"as": "banner_blue"}],
			["canopy_bed", "rooms"],
			["bookcase", "rooms"],
			["reading_desk", "rooms"],
			["map_table", "rooms"],
			["lectern", "rooms"],
			["feast_table", "hall"],
			["bench", "hall"],
			["hearth", "hall"],
			["barrel", "hall"],
			["crate", "hall"],
			["sacks", "hall"],
			["treasure_chest", "treasure", {"as": "chest"}],
			["treasure_chest_open", "treasure", {"as": "chest_open"}],
			["gold_pile", "treasure"],
			["coin_stacks", "treasure"],
			["armour_stand", "armoury"],
			["weapon_rack", "armoury"],
			["training_dummy", "armoury", {"as": "dummy"}],
			["brazier", "lights"],
			["standing_torch", "lights", {"as": "torch"}],
			["candelabra", "lights"],
			["tapestry", "on the wall"],
			["wall_banner_red", "on the wall", {"as": "hanging_red"}],
			["wall_banner_blue", "on the wall", {"as": "hanging_blue"}],
			["shield_wall", "on the wall"],
			["wall_torch", "on the wall"],
			["runner_red", "rugs"],
		],
	},
	"mansion":
	{
		"dir": "isometric-haunted-mansion/Gridwright Isometric Haunted Mansion/",
		"tab": "mansion",
		"walls": ["damask", "panel", "plaster", "stone"],
		"floors": ["rotten", "parquet", "checker", "carpet", "flagstone", "cellar"],
		"pieces":
		[
			["grand_piano", "living"],
			["wingback_chair", "living", {"as": "wingback"}],
			["gothic_chair", "living"],
			["sheet_chair", "living"],
			["sheet_sofa", "living"],
			["rocking_chair", "living", {"as": "rocker"}],
			["long_table", "living"],
			["seance_table", "living"],
			["dusty_bookshelf", "living", {"as": "bookshelf"}],
			["grandfather_clock", "living", {"as": "tall_clock", "faces": ["sw", "se"]}],
			["fireplace", "living"],
			["four_poster_bed", "rooms", {"as": "four_poster"}],
			["old_wardrobe", "rooms"],
			["writing_desk", "rooms"],
			["dress_form", "rooms"],
			["wine_rack", "rooms"],
			["candelabra", "candles"],
			["floor_candles", "candles", {"as": "candles"}],
			["ghost", "spooky"],
			["coffin", "spooky", {"still": true}],
			["dead_plant", "spooky"],
			["book_pile", "spooky"],
			["portrait", "on the wall"],
			["moon_painting", "on the wall", {"as": "painting"}],
			["cracked_mirror", "on the wall", {"as": "mirror"}],
			["torn_curtains", "on the wall", {"as": "curtains"}],
			["cobweb", "on the wall"],
			["sconce", "on the wall"],
			["rug_moth", "rugs", {"as": "moth_rug"}],
			["summoning_circle", "rugs", {"as": "circle"}],
		],
	},
	"farm":
	{
		"dir": "isometric-farm/Gridwright Isometric Farm/",
		"tab": "garden",
		"walls": [],
		"floors": ["grass", "farmyard"],
		"pieces":
		[
			["tree_apple", "trees", {"as": "apple_tree"}],
			["tree_apple_fruit", "trees", {"as": "apple_fruit"}],
			["tree_pear", "trees", {"as": "pear_tree"}],
			["tree_peach", "trees", {"as": "peach_tree"}],
			["crop_sunflower_stage4", "beds", {"as": "sunflowers"}],
			["crop_tomato_stage4", "beds", {"as": "tomatoes"}],
			["crop_strawberry_stage4", "beds", {"as": "strawberries"}],
			["crop_pumpkin_stage4", "beds", {"as": "pumpkins"}],
			["crop_cabbage_stage4", "beds", {"as": "cabbages"}],
			["crop_wheat_stage4", "beds", {"as": "wheat"}],
			["crop_grapes_stage4", "beds", {"as": "grapes"}],
			["trough", "farm"],
			["hay_bale_round", "farm", {"as": "hay_round"}],
			["hay_bale_square", "farm", {"as": "hay_square"}],
			["crate_apples", "farm", {"as": "apple_crate"}],
			["crate_carrots", "farm", {"as": "carrot_crate"}],
			["sacks", "farm"],
			["milk_cans", "farm"],
			["beehive", "farm"],
			["scarecrow", "farm"],
			["well", "farm"],
			["vegetable_cart", "farm", {"as": "cart"}],
			["sprinkler", "farm"],
		],
	},
}


# `index` (the interiors' sprites) with every present pack's curated sprites added
static func extend(index: Dictionary, art_dir: String) -> Dictionary:
	var out := index.duplicate()
	for ns in NAMES:
		var spec: Dictionary = PACKS[ns]
		var dir := art_dir.path_join(spec["dir"])
		if not FileAccess.file_exists(dir + "isometric.json"):
			continue
		var parsed: Variant = JSON.parse_string(
			FileAccess.get_file_as_string(dir + "isometric.json")
		)
		if parsed is Dictionary and parsed.get("sprites") is Dictionary:
			_add(out, ns, spec, dir, parsed["sprites"])
	return out


static func _add(
	out: Dictionary, ns: String, spec: Dictionary, dir: String, sprites: Dictionary
) -> void:
	var rows := {}
	for i in spec["pieces"].size():
		rows[spec["pieces"][i][0]] = i
	var frame := RegEx.create_from_string(FRAME)
	var side := RegEx.create_from_string(SIDE)
	var floor_re := RegEx.create_from_string("^floor_(.+)_0([12])$")
	for key in sprites:
		var s: Dictionary = sprites[key]
		var file: String = s["file"]
		if "/walls/" in file:
			var style := str(s.get("style"))
			var stem := "wall_" + style
			var part: String = key.substr(stem.length())
			if style in spec["walls"] and key.begins_with(stem) and part in WALL_PARTS:
				var made := "wall_%s.%s%s" % [ns, style, part]
				_put(out, made, s, dir, spec["tab"])
				out[made]["style"] = ns + "." + style
		elif "/floors/" in file:
			var m := floor_re.search(key)
			if m != null and m.get_string(1) in spec["floors"]:
				var made := "floor_%s.%s_0%s" % [ns, m.get_string(1), m.get_string(2)]
				_put(out, made, s, dir, spec["tab"])
		elif "/shadows/" not in file and "/doors/" not in file:
			var id: String = key
			var fr := ""
			var m := frame.search(id)
			if m != null:
				fr = m.get_string(1)
				id = id.substr(0, m.get_start())
			var face := ""
			m = side.search(id)
			if m != null:
				face = m.get_string(1)
				id = id.substr(0, m.get_start())
			if not rows.has(id):
				continue
			var row: Array = spec["pieces"][rows[id]]
			var opts: Dictionary = row[2] if row.size() > 2 else {}
			if face != "" and opts.has("faces") and face not in opts["faces"]:
				continue
			if opts.get("still", false) and fr != "" and fr != "1":
				continue
			var name: String = ns + "." + str(opts.get("as", id))
			var made := name + ("_" + face if face != "" else "")
			if fr != "" and not opts.get("still", false):
				made += "_f" + fr
			_put(out, made, s, dir, spec["tab"])
			var e: Dictionary = out[made]
			e["group"] = row[1]
			e["order"] = rows[id]
			var shadow := str(s.get("shadow", ""))
			if shadow != "" and sprites.has(shadow):
				_put(out, ns + "." + shadow, sprites[shadow], dir, spec["tab"])
				e["shadow"] = ns + "." + shadow


static func _put(out: Dictionary, key: String, s: Dictionary, dir: String, tab: String) -> void:
	var e := s.duplicate()
	e["dir"] = dir
	e["tab"] = tab
	out[key] = e


# the tab a wall or floor style belongs to
static func tab_of(style: String) -> String:
	return PACKS[style.get_slice(".", 0)]["tab"] if "." in style else "home"


# "castle" for "castle.throne" when the pack is one of ours, else ""
static func pack_of(id: String) -> String:
	var ns := id.get_slice(".", 0)
	return ns if "." in id and ns in NAMES else ""
