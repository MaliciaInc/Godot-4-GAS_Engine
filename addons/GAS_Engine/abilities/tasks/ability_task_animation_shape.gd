## Everything about a playback except which animation it is.
##
## An object rather than four more parameters, for the reason the parameter
## limit exists: a call with six arguments is one nobody reads at the call
## site, and three of these are the kind of thing that gets passed in the
## wrong order exactly once and then behaves oddly for a week.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name AbilityTaskAnimationShape extends RefCounted

## How fast. Zero or less is refused rather than guessed at.
var rate: float = 1.0

## Where to start, in seconds, clamped to the animation's length.
var start_time: float = 0.0

## A marker to start from instead. Named and missing is a failure.
var section: StringName = &""

## Whether cancelling the task stops the animation, or leaves it to a shared
## surface something else is also driving.
var stop_on_cancel: bool = false
