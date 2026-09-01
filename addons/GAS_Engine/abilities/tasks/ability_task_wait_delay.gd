## Wait a fixed number of seconds before continuing.
##
## Counted from the deltas the ASC already advances, not from a `SceneTreeTimer`.
## A tree timer keeps its own clock: it would keep counting while the rest of the
## engine was paused, and it would answer to a different authority than the
## effect scheduler running beside it. One clock, or the two eventually disagree.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT
class_name AbilityTaskWaitDelay extends GameplayAbilityTask

## How long to wait. Never negative: a negative wait is a caller's mistake, and
## clamping it to zero is a shorter wait rather than a wrong one.
var duration: float = 0.0

var elapsed: float = 0.0


static func create(ability: GameplayAbility, duration_seconds: float) -> AbilityTaskWaitDelay:
	var task: AbilityTaskWaitDelay = AbilityTaskWaitDelay.new()
	task.owner_ability = ability
	task.duration = maxf(duration_seconds, 0.0)
	return task


## A zero-second wait still costs one advance.
##
## Finishing inside `start` would report before the caller had a chance to
## connect to `finished` or await it, so the shortest wait this can express is
## "the next time the ASC ticks" rather than "no time at all".
func advance_time(delta: float) -> void:
	elapsed += maxf(delta, 0.0)
	if elapsed >= duration:
		succeed()
