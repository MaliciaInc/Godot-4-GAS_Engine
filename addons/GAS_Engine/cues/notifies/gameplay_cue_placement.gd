## Where a cue's effects go, and what they do once they are there.
##
## Three answers, and they are genuinely different questions rather than three
## spellings of one. A flame on a burning character has to follow it around; a
## crater belongs to the ground it was made in and must not; and most impacts
## want the target's own origin because that is where the thing that happened,
## happened.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayCuePlacement extends Resource

enum Mode {
	## A child of the target, so it moves with it. For anything that is on the
	## character rather than where the character was.
	ATTACH_TO_TARGET,
	## At the world location the cue was given, staying where it was put. Falls
	## back to the target's origin when the cue carries no location, because a
	## crater at (0, 0, 0) is worse than a crater in the wrong place.
	AT_LOCATION,
	## At the target's origin, once, without following it. The default, and
	## what an impact usually wants.
	AT_TARGET_ORIGIN,
}

@export var mode: GameplayCuePlacement.Mode = Mode.AT_TARGET_ORIGIN

## Moved by this much from wherever the mode put it, in the target's own frame
## for ATTACH_TO_TARGET and in world space otherwise.
@export var offset: Vector3 = Vector3.ZERO

## Whether an attached effect turns with what it is attached to. Off for
## anything that should stay upright while its owner spins.
@export var follow_rotation: bool = true

## Whether the effect is scaled by the cue's normalised magnitude.
##
## Normalised rather than raw, so a cue authored once scales sensibly in a game
## whose numbers are later rebalanced - which is the whole reason a binding
## declares the range it reads against.
@export var scale_by_magnitude: bool = false
