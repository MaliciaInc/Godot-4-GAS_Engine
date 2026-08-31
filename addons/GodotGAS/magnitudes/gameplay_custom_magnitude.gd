## A magnitude computed by an arbitrary GameplayMagnitudeCalculation.
##
## The escape hatch for math none of the other magnitude kinds express - a
## non-linear falloff, a value drawn from several captures at once.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_license: MIT
class_name GameplayCustomMagnitude extends GameplayMagnitude

@export var calculation: GameplayMagnitudeCalculation = null


func required_captures() -> Array[GameplayAttributeCaptureDefinition]:
	return calculation.required_captures() if calculation != null else []


func resolve(context: GameplayMagnitudeContext) -> GameplayMagnitudeResult:
	if calculation == null:
		return GameplayMagnitudeResult.failure(GameplayMagnitudeResult.Status.INVALID_DEFINITION)

	var result: GameplayMagnitudeResult = calculation.calculate(context)
	if result == null:
		return GameplayMagnitudeResult.failure(GameplayMagnitudeResult.Status.CALCULATION_FAILED)
	if result.is_ok() and not is_finite(result.value):
		return GameplayMagnitudeResult.failure(GameplayMagnitudeResult.Status.NON_FINITE_VALUE)
	return result
