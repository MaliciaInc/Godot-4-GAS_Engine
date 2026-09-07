## Base for a typed, extensible modifier magnitude.
##
## Replaces a bare `float` plus an optional `Curve` as the only way to
## express "how much": a magnitude may also read a captured attribute, ask
## for a value the caster supplied at cast time, or run an arbitrary
## calculation - and every one of those needs more than two fields to say so
## honestly.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
@abstract
class_name GameplayMagnitude extends Resource


## Every attribute capture this magnitude needs resolved before resolve()
## runs. The default, empty, costs a subclass nothing that reads no capture.
func required_captures() -> Array[GameplayAttributeCaptureDefinition]:
	return []


## Anything outside the attribute system this magnitude depends on.
##
## A LIVE magnitude is only live if something re-resolves it when what it reads
## moves. `required_captures()` above says which attributes that is; this says
## the rest - the weather, the time of day, an inventory - as signals, because a
## dependency the engine cannot subscribe to is one it cannot honour.
##
## Empty by default: a magnitude that reads only attributes has nothing to add.
func external_dependencies() -> Array[Signal]:
	var none: Array[Signal] = []
	return none


## Compute this magnitude's value for one evaluation.
func resolve(_context: GameplayMagnitudeContext) -> GameplayMagnitudeResult:
	push_error(
		"GAS_Engine: resolve() called on the base GameplayMagnitude. "
		+ "Override it in the subclass that authors this magnitude kind."
	)
	return GameplayMagnitudeResult.failure(GameplayMagnitudeResult.Status.INVALID_DEFINITION)
