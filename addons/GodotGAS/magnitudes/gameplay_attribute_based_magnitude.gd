## A magnitude derived from one captured attribute: `((captured + pre_add) *
## coefficient) + post_add`, all evaluated at the spec's own level.
##
## The capture it names decides everything about where the value comes from -
## SOURCE or TARGET, BASE or CURRENT, SNAPSHOT or LIVE. This class only does
## the arithmetic once that capture resolves.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_license: MIT
class_name GameplayAttributeBasedMagnitude extends GameplayMagnitude

@export var capture: GameplayAttributeCaptureDefinition = null
@export var coefficient: GameplayScalableFloat = null
@export var pre_add: GameplayScalableFloat = null
@export var post_add: GameplayScalableFloat = null


func required_captures() -> Array[GameplayAttributeCaptureDefinition]:
	if capture == null:
		return []
	return [capture]


func resolve(context: GameplayMagnitudeContext) -> GameplayMagnitudeResult:
	if capture == null or context == null or context.spec == null:
		return GameplayMagnitudeResult.failure(GameplayMagnitudeResult.Status.INVALID_DEFINITION)

	var captured: AttributeCaptureResult = context.spec.resolve_capture(
		capture, context.source_asc, context.target_asc
	)
	if not captured.is_ok():
		return GameplayMagnitudeResult.failure(_translate(captured.status))

	var coeff: float = coefficient.evaluate(context.level) if coefficient != null else 1.0
	var pre: float = pre_add.evaluate(context.level) if pre_add != null else 0.0
	var post: float = post_add.evaluate(context.level) if post_add != null else 0.0
	var resolved: float = ((captured.value + pre) * coeff) + post

	if not is_finite(resolved):
		return GameplayMagnitudeResult.failure(GameplayMagnitudeResult.Status.NON_FINITE_VALUE)
	return GameplayMagnitudeResult.ok(resolved)


## AttributeCaptureResult's own reasons, translated to this magnitude's own
## vocabulary: SOURCE_MISSING and TARGET_MISSING are both "the capture this
## magnitude needed never resolved", which is the one thing a caller here
## actually needs to know.
static func _translate(status: AttributeCaptureResult.Status) -> GameplayMagnitudeResult.Status:
	match status:
		AttributeCaptureResult.Status.ATTRIBUTE_NOT_FOUND:
			return GameplayMagnitudeResult.Status.ATTRIBUTE_NOT_FOUND
		AttributeCaptureResult.Status.NON_FINITE_VALUE:
			return GameplayMagnitudeResult.Status.NON_FINITE_VALUE
		_:
			return GameplayMagnitudeResult.Status.MISSING_CAPTURE
