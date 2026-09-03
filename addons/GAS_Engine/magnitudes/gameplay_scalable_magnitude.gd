## A magnitude that is just a number, optionally scaling with level.
##
## Wraps GameplayScalableFloat rather than re-implementing curve math: this
## and GameplayAbilityCost already share that class for exactly this reason.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayScalableMagnitude extends GameplayMagnitude

@export var value: GameplayScalableFloat = null


func resolve(context: GameplayMagnitudeContext) -> GameplayMagnitudeResult:
	if value == null:
		return GameplayMagnitudeResult.failure(GameplayMagnitudeResult.Status.INVALID_DEFINITION)
	var resolved: float = value.evaluate(context.level)
	if not is_finite(resolved):
		return GameplayMagnitudeResult.failure(GameplayMagnitudeResult.Status.NON_FINITE_VALUE)
	return GameplayMagnitudeResult.ok(resolved)
