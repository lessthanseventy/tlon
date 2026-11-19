extends RefCounted

# What a pet is doing, in one phrase, from its own state alone: `state_of` reads a critter and the
# running antic, `phrase` words it, and nothing in it is invented. Also where each pet thing sends
# a pet (`spots_of`), for the pet view's rows and buttons.
const PetThings := preload("res://pet_things.gd")

const SPOTS_OF := {
	"bowls": ["bowl", "water"],
	"bed_round": ["bed"],
	"tower": ["tower_top", "tower_cube", "tower_bat"],
	"birdcage": ["cage"],
	"perch": ["roost"],
	"blanket": ["mat"],
	"hay": ["hay_top", "hay_eat"],
}
const NOUN := {
	"sofa": "the sofa",
	"sofa_stand": "the sofa",
	"desk": "the desk",
	"desk_stand": "the desk",
	"pad": "the notepad",
	"rug": "the rug",
	"rug2": "the rug",
	"sill": "the window",
	"tv": "the TV",
	"door": "the door",
	"door_in": "the door",
	"lamp": "the lamp",
	"mid": "the middle of the room",
	"lounge": "the middle of the room",
	"corner": "the corner",
	"nook": "the bin",
	"board": "the board",
	"board_stand": "the board",
}
const ON := [
	"sofa",
	"desk",
	"pad",
	"rug",
	"rug2",
	"bed",
	"bed_cushion",
	"mat",
	"tower_top",
	"tower_cube",
	"tower_bat",
	"hay_top",
	"roost",
	"window_perch"
]
const IN := [
	"mid",
	"lounge",
	"corner",
	"cardbox",
	"nest",
	"hutch",
	"den",
	"kennel",
	"basket",
	"pool",
	"litter"
]
const ANTIC := {
	"loaf": "loafing",
	"slow_blink": "slow-blinking at you",
	"knead": "kneading the sofa",
	"bird_chatter": "chattering at a bird",
	"cage_watch": "watching the bird cage",
	"pounce": "pouncing on nothing",
	"stretch": "having a stretch",
	"wall_stare": "staring at the wall",
	"witching": "tearing around the room",
	"yowl": "yowling at the night",
	"tail_chase": "chasing its tail",
	"play_bow": "bowing to play",
	"roll_over": "rolling over",
	"ear_scratch": "scratching an ear",
	"sniff_line": "following a smell",
	"head_tilt": "tilting its head",
	"door_bark": "barking at the door",
	"carry_bone": "carrying a bone",
	"three_circles": "turning three circles",
	"dream": "dreaming",
	"binky": "binkying",
	"bunny_flop": "flopping over",
	"thump": "thumping a foot",
	"nose_wiggle": "wiggling its nose",
	"periscope": "standing up to look around",
	"scratch_peck": "scratching and pecking",
	"dust_bath": "taking a dust bath",
	"flap_run": "flapping around",
	"lay_egg": "laying an egg",
	"roost": "roosting",
	"root_floor": "rooting about",
	"happy_spin": "spinning with joy",
	"flop_nap": "flopped out for a nap",
	"bin_snuffle": "snuffling at the bin",
	"graze": "grazing",
	"slow_chew": "chewing slowly",
	"stamp": "stamping a hoof",
	"horse_trot": "trotting about",
	"deer_freeze": "frozen, listening",
	"nose_lick": "licking its nose",
	"back_scratch": "scratching its back on the shelf",
	"sit_like_person": "sitting like a person",
	"big_yawn": "yawning",
	"pat_jar": "patting the jar",
	"greet": "saying hello to the other one",
	"pat_purr": "enjoying the pat",
	"pat_kick": "enjoying the pat",
	"pat_roll": "enjoying the pat",
	"trick_sit": "sitting pretty",
	"trick_spin": "spinning for you",
	"trick_dead": "playing dead",
	"trick_ignore": "pretending not to hear",
	"sunbathe": "sunbathing",
	"snow_watch": "watching the snow",
	"tv_hunt": "hunting what is on the TV",
	"tv_bark": "barking at the TV",
	"visitor_follow": "following the visitor",
	"visitor_shadow": "shadowing the visitor",
	"visitor_puff": "puffed up at the visitor",
	"festive_look": "looking at the lights",
	"meal_nap": "napping after a meal",
	"birthday_hop": "hopping for the birthday",
	"door_wait": "waiting by the door",
	"desk_beside": "waiting beside the desk",
	"lean_chair": "leaning on the chair",
	"feet_night": "keeping watch by the sofa",
	"cheer_done": "cheering",
	"phone_watch": "watching the phone",
	"board_look": "looking at the board",
	"chase_game": "playing chase",
	"nap_pile": "in a nap pile",
	"boop": "booping the other one",
	"groom": "grooming the other one",
	"steal_spot": "taking the other one's spot",
	"copy_cat": "copying the other one",
	"standoff": "in a standoff over the yarn",
	"herd": "herding the other one",
	"follow_around": "following the other one around",
}


# the critter's own fields, and the running antic's name once it is playing
static func state_of(c, act: Dictionary) -> Dictionary:
	var mine: bool = not act.is_empty() and c.id in [act["id"], act["pid"]]
	return {
		"away": c.away,
		"mode": c.mode,
		"anim": c.anim,
		"spot": c.spot,
		"goal": c.goal,
		"use": c.use,
		"plan": c.plan.get("mode", ""),
		"hopping": not c.jump.is_empty(),
		"antic": act["name"] if mine and act["st"] == "play" else "",
	}


static func phrase(s: Dictionary) -> String:
	if s["away"]:
		return "not here"
	if ANTIC.has(s["antic"]):
		return ANTIC[s["antic"]]
	var at := place(s["spot"])
	match s["mode"]:
		"sleep":
			return "asleep " + at if at != "" else "asleep"
		"walk":
			var to := noun(s["goal"])
			return "on its way to " + to if to != "" else "wandering"
		"bat", "stalk":
			return "after the yarn"
		"swat":
			return (
				{
					"knock": "knocking something off the desk",
					"push": "pushing something off the desk",
				}
				. get(s["plan"], "swatting at something")
			)
	if s["hopping"]:
		return "hopping up"
	if s["spot"] == "knocked":
		return "sitting by what it knocked down"
	if at == "":
		return "hanging out"
	if s["anim"] == "eat" and s["use"] == "":
		return "eating " + at
	if s["use"] == "litter":
		return "in the litter box"
	if s["use"] != "":
		return "playing " + at
	return "resting " + at


static func noun(spot: String) -> String:
	if NOUN.has(spot):
		return NOUN[spot]
	var key := key_of_spot(spot)
	return "the " + PetThings.THINGS[key]["name"] if key != "" else ""


static func place(spot: String) -> String:
	var n := noun(spot)
	if n == "":
		return ""
	return ("on " if spot in ON else "in " if spot in IN else "at ") + n


static func spots_of(key: String) -> Array:
	return SPOTS_OF.get(key, [key])


static func key_of_spot(spot: String) -> String:
	for key in PetThings.THINGS:
		if spot in spots_of(key):
			return key
	return ""
