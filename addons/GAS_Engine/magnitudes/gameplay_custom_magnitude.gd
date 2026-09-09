## A magnitude computed by an arbitrary GameplayMagnitudeCalculation, then
## shaped by the same four dials every other magnitude has.
##
## The escape hatch for math none of the other magnitude kinds express - a
## non-linear falloff, a value drawn from several captures at once. The dials
## are here so that reusing one calculation at three strengths is three
## Resources rather than three scripts.
##
## The order is fixed and it is not commutative:
##
##     raw
##     → + pre_add
##     → * coefficient
##     → final_curve(value)
##     → + post_add
##
## `post_add` is deliberately outside the curve. A curve is a shape - a
## diminishing return, a threshold - and a flat amount added before it would be
## bent by it, which is not what "and then add five" means. `pre_add` is inside
## for the same reason read the other way: it moves where on the curve the
## calculation lands, which is exactly what an author adjusting an input wants.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayCustomMagnitude extends GameplayMagnitude

@export var calculation: GameplayMagnitudeCalculation = null

## Evaluated at the spec's own level, like every other scalable float here.
@export var coefficient: GameplayScalableFloat = null
@export var pre_add: GameplayScalableFloat = null
@export var post_add: GameplayScalableFloat = null

## Applied after the multiplication and before `post_add`. Null leaves the
## number alone, which is what every custom magnitude authored before these
## dials existed does.
@export var final_curve: Curve = null


func required_captures() -> Array[GameplayAttributeCaptureDefinition]:
	return calculation.required_captures() if calculation != null else []


func resolve(context: GameplayMagnitudeContext) -> GameplayMagnitudeResult:
	if calculation == null:
		return GameplayMagnitudeResult.failure(GameplayMagnitudeResult.Status.INVALID_DEFINITION)

	var result: GameplayMagnitudeResult = calculation.calculate(context)
	if result == null:
		return GameplayMagnitudeResult.failure(GameplayMagnitudeResult.Status.CALCULATION_FAILED)
	if not result.is_ok():
		return result
	if not is_finite(result.value):
		return GameplayMagnitudeResult.failure(GameplayMagnitudeResult.Status.NON_FINITE_VALUE)

	var shaped: float = _shaped(result.value, context.level)
	if not is_finite(shaped):
		return GameplayMagnitudeResult.failure(GameplayMagnitudeResult.Status.NON_FINITE_VALUE)
	return GameplayMagnitudeResult.ok(shaped)


## The raw result put through the four dials, in the one order this class
## documents. Written as four statements rather than one expression because the
## order is the contract and an expression hides it inside precedence rules.
func _shaped(raw: float, level: float) -> float:
	var value: float = raw
	value += pre_add.evaluate(level) if pre_add != null else 0.0
	value *= coefficient.evaluate(level) if coefficient != null else 1.0
	if final_curve != null:
		value = final_curve.sample(value)
	value += post_add.evaluate(level) if post_add != null else 0.0
	return value
