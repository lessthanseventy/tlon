extends RefCounted

# The soak's checks of the pets' kinds, voices and sounds, the pet things, the picker, the visitors,
# the personalities and the settings that govern them.
const Pets := preload("res://pets.gd")
const Voices := preload("res://voices.gd")
const Sound := preload("res://sound.gd")

var s


func _init(soak) -> void:
	s = soak


func run() -> void:
	_kinds()


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
