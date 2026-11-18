extends RefCounted

# The soak's checks of the pets' kinds, voices and sounds, the pet things, the picker, the visitors,
# the personalities and the settings that govern them.
const Pets := preload("res://pets.gd")
const Voices := preload("res://voices.gd")
const Sound := preload("res://sound.gd")
const Settings := preload("res://settings.gd")
const PetView := preload("res://pet_view.gd")

var s


func _init(soak) -> void:
	s = soak


func run() -> void:
	_kinds()
	_picker()


# the card writes the settings the settings screen writes, and the room follows at once
func _picker() -> void:
	var room: Control = s._room(41)
	var h = room.home
	var view: PanelContainer = PetView.new()
	view.setup(h.settings, h)
	s.root.add_child(view)
	view.open("nina")
	s._check(view.visible, "the card opens")
	s._check(view._tiles.size() == Pets.KINDS.size() + 1, "a tile for every kind and for none")
	view._put("kind", "bear_polar")
	s._check(h.settings.value("pet1") == "bear_polar", "the card writes pet1")
	s._check(
		h.pets.kinds["nina"] == "bear_polar" and h.pets.critter("nina").species == "bear",
		"the pet changes at once"
	)
	s._check(
		view._tiles["bear_polar"].chosen and not view._tiles["cat_black"].chosen,
		"the chosen tile is lit"
	)
	view._name.text = "Bruno"
	view._put("name", "Bruno")
	s._check(
		h.settings.value("cat") == "Bruno" and Settings.pets("Nina sits") == "Bruno sits",
		"the name is used in lines"
	)
	s._check(h.pets.critter("nina").title == "Nina", "the role keeps its key")
	view.open("argos")
	view._put("kind", Pets.NONE)
	s._check(
		h.pets.critter("argos").away and h.settings.value("pet2") == Pets.NONE,
		"none takes the pet away"
	)
	view._put("kind", "horse_bay")
	s._check(
		not h.pets.critter("argos").away and h.pets.critter("argos").species == "horse",
		"and a kind brings it back"
	)
	view.open("nina")
	s._check(view._name.text == "Bruno", "the card shows the kept name")
	view.close()
	s._check(not view.visible, "the card closes")
	h.settings.put("cat", "")
	view.queue_free()
	room.queue_free()


func _kinds() -> void:
	s._check(Pets.KINDS.size() == 29, "every animal of the pack is a kind (%d)" % Pets.KINDS.size())
	var species := {}
	for kind in Pets.KINDS:
		species[Pets.KINDS[kind]["species"]] = true
	for sp in species:
		if sp in ["cat", "dog"]:
			continue
		s._check(Voices.OWN.has(sp), "%s has lines of its own" % sp)
		var own: Dictionary = Voices.OWN.get(sp, {})
		for occasion in ["pet", "wake", "muse"]:
			s._check(own.get(occasion, []).size() > 0, "%s has a %s line" % [sp, occasion])
	var pets := Pets.new()
	pets.setup("", 5)
	for sp in species:
		var cry: String = Pets.CRIES.get(sp, "")
		s._check(cry == "" or cry in Sound.EVENTS, "%s's cry is a sound" % sp)
		if cry != "":
			s._check(Sound._synth(cry, 0.0).size() > 100, "%s has a synthesised cry" % cry)
	for kind in Pets.KINDS:
		var n := pets.critter("nina")
		pets.set_kind(n, kind)
		var cry := pets.cry(n)
		s._check(
			(
				(cry == "purr") == (Pets.KINDS[kind]["species"] == "cat")
				and (cry == "bark") == (Pets.KINDS[kind]["species"] == "dog")
			),
			"%s: only a cat purrs and only a dog barks" % kind
		)
		var v := Voices.new()
		v.species = {"Nina": Pets.KINDS[kind]["species"]}
		if Voices.OWN.has(Pets.KINDS[kind]["species"]):
			s._check(v.line("Nina", "pet") != "", "%s answers a pat" % kind)
