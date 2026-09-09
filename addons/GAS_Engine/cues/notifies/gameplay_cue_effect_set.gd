## One bundle of things to play, and where to put them.
##
## Authored data, not behaviour: this says a burst is two sounds, a particle
## scene and a decal at the target's origin. What plays it is a
## GameplayCueNotify, and how many bundles that notify owns is what makes a
## burst different from a loop.
##
## Camera shake and haptics are named here and are deliberately not performed
## here. This addon has no camera and no opinion about which device is in
## somebody's hands: it says what happened, in a name a game maps to its own
## shake and its own controller.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayCueEffectSet extends Resource

@export var sounds: Array[AudioStream] = []
@export var particles: Array[PackedScene] = []
@export var decals: Array[PackedScene] = []

## A request, by name. Empty means this set asks for none.
@export var camera_shake: StringName = &""
@export var haptics: StringName = &""

## Where everything in this set goes. Null means the target's own origin, which
## is what every set that never thought about it wants.
@export var placement: GameplayCuePlacement = null


## Whether this set would do anything at all.
##
## Asked before spawning, so an empty set on a looping cue - three of its four
## are usually empty - costs nothing rather than a node with no children.
func is_empty() -> bool:
	return (
		sounds.is_empty()
		and particles.is_empty()
		and decals.is_empty()
		and camera_shake == &""
		and haptics == &""
	)
