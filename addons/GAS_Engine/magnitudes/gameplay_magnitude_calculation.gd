## Base for a custom, arbitrary magnitude calculation.
##
## Produces exactly one value. This is not a replacement for
## GameplayExecutionCalculation, which can mutate several attributes at once
## from one effect; a custom magnitude only ever answers "how much" for the
## one modifier that references it.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT
@abstract
class_name GameplayMagnitudeCalculation extends Resource


func required_captures() -> Array[GameplayAttributeCaptureDefinition]:
	return []


func calculate(_context: GameplayMagnitudeContext) -> GameplayMagnitudeResult:
	push_error(
		"GAS_Engine: calculate() called on the base GameplayMagnitudeCalculation. "
		+ "Override it in the subclass that authors this calculation."
	)
	return GameplayMagnitudeResult.failure(GameplayMagnitudeResult.Status.CALCULATION_FAILED)
