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

## Where a packed ability lives, so two machines can name the same one.
##
## A PackedScene built in memory has no `resource_path`, and a definition that
## lives nowhere cannot be named to another process: the id both ends use is
## made from the path. Nothing is ever written to these paths - the scenes are
## built here, in both processes, from the same code - and giving each one a
## path is what makes the two agree about which ability a request is for.
const SCENE_PATH: String = "res://examples/action_sample/abilities/%s.tscn"

## The packed abilities, built once and shared by every character.
##
## Once, and this is the part that is easy to get wrong: `take_over_path` is a
## rename rather than a label. A second scene taking the same path takes it -
## the first is left holding an empty `resource_path`, and every character
## granted before that moment holds abilities that can no longer be named to
## anybody. Three characters in this sample, one loadout each, and the hero's
## abilities went nameless the moment the first dummy was built.
##
## Shared is also what a real game does: one `.tscn` on disk, granted to twenty
## characters, instantiated once per grant. A PackedScene is a description, and
## nothing about a character is kept in it.
static var _packed: Dictionary[StringName, PackedScene] = {}


## The loadout, built fresh.
##
## Fresh in what has state - the attribute set, which is this character's own
## numbers - and shared in what does not. A set is a description, and two
## characters sharing one attribute set would share the Resource inside it.
static func built() -> GameplayAbilitySet:
	var loadout: GameplayAbilitySet = GameplayAbilitySet.new()
	loadout.resource_name = "SampleLoadout"
	loadout.attribute_sets = [SampleAttributes.new()]
	loadout.abilities = [
		_entry(SampleBasicAttack.NAME),
		_entry(SampleChannel.NAME),
		_entry(SampleGroundSlam.NAME),
	]
	return loadout


## One grant: a packed ability, at level one.
##
## Packed rather than handed over as a Node, because a grant instantiates its
## own copy - which is what lets one loadout be given to twenty characters
## without them sharing an ability instance between them.
static func _entry(named: StringName) -> GameplayAbilitySetEntry:
	var entry: GameplayAbilitySetEntry = GameplayAbilitySetEntry.new()
	entry.ability_scene = _scene_of(named)
	entry.level = 1.0
	return entry


## The packed scene for one of the three, built the first time it is asked for.
static func _scene_of(named: StringName) -> PackedScene:
	if _packed.has(named):
		return _packed[named]

	var ability: GameplayAbility = _template(named)
	if ability == null:
		return null
	var scene: PackedScene = PackedScene.new()
	var packed: Error = scene.pack(ability)
	# `pack()` copies rather than consumes, so the template left alive is an
	# orphan - one per ability, which a suite counts and reports.
	ability.free()
	if packed != OK:
		return null

	scene.take_over_path(SCENE_PATH % String(named).to_snake_case())
	_packed[named] = scene
	return scene


## A fresh instance of one of the three, to be packed and thrown away.
##
## By name because the caller above lists three names; a dictionary of
## Callables would be the same three lines with one more thing to keep in step.
static func _template(named: StringName) -> GameplayAbility:
	match named:
		SampleBasicAttack.NAME:
			return SampleBasicAttack.build()
		SampleChannel.NAME:
			return SampleChannel.build()
		SampleGroundSlam.NAME:
			return SampleGroundSlam.build()
		_:
			return null
