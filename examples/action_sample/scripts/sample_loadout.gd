## Everything a character in this sample is given, said once.
##
## Three abilities and an attribute set, granted in one call and taken back in
## one call. The friction F6.0.9 measured was five calls each way, made one at a
## time because there was no way to say it once - and a loadout half-granted
## because the third call failed was something a game had to unwind itself.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name SampleLoadout extends RefCounted


## The loadout, built fresh.
##
## Fresh because the ability scenes are built from templates: two characters
## sharing one set would share the Resources inside it, and a set is meant to be
## a description rather than a thing with state.
static func built() -> GameplayAbilitySet:
	var loadout: GameplayAbilitySet = GameplayAbilitySet.new()
	loadout.resource_name = "SampleLoadout"
	loadout.attribute_sets = [SampleAttributes.new()]
	loadout.abilities = [
		_entry(SampleBasicAttack.build()),
		_entry(SampleChannel.build()),
		_entry(SampleGroundSlam.build()),
	]
	return loadout


## One grant: an ability packed into a scene, at level one.
##
## Packed rather than handed over as a Node, because a grant instantiates its
## own copy - which is what lets one loadout be given to twenty characters
## without them sharing an ability instance between them.
static func _entry(ability: GameplayAbility) -> GameplayAbilitySetEntry:
	var entry: GameplayAbilitySetEntry = GameplayAbilitySetEntry.new()
	var scene: PackedScene = PackedScene.new()
	var packed: Error = scene.pack(ability)
	# `pack()` copies rather than consumes, so the template left alive is an
	# orphan - one per ability, which a suite counts and reports.
	ability.free()
	entry.ability_scene = scene if packed == OK else null
	entry.level = 1.0
	return entry
