## A magnitude derived from one captured attribute: `((reading + pre_add) *
## coefficient) + post_add`, all evaluated at the spec's own level, and then
## passed through `attribute_curve` if one is authored.
##
## The capture it names decides where the value comes from - SOURCE or TARGET,
## SNAPSHOT or LIVE. `calculation` decides which reading of it is taken, which
## is a different question: "the target's armour" and "the bonus part of the
## target's armour" are the same capture and two numbers.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayAttributeBasedMagnitude extends GameplayMagnitude

## Which reading of the captured attribute this magnitude is about.
enum Calculation {
	## Whatever the capture itself says - BASE or CURRENT, as authored. The
	## default, and what every effect written before this enum existed does.
	MAGNITUDE,
	## The durable value, whatever the capture said. A cost priced off what a
	## character permanently is, unaffected by whatever is buffing them.
	BASE_VALUE,
	## Only the part that is not durable: current minus base. "Strip the
	## buffs" and "scale with how buffed they are" are this one.
	BONUS_MAGNITUDE,
	## The value the attribute would have if only the first `final_channel`
	## channels had been applied. For an effect that must see an attribute
	## before the last stages of its own composition run.
	MAGNITUDE_UP_TO_CHANNEL,
}

@export var capture: GameplayAttributeCaptureDefinition = null

## Which of the four readings is taken. Not a second capture field: SOURCE or
## TARGET and SNAPSHOT or LIVE are still the capture's to say.
@export var calculation: GameplayAttributeBasedMagnitude.Calculation = Calculation.MAGNITUDE

## For MAGNITUDE_UP_TO_CHANNEL, the last channel that counts. Ignored by every
## other calculation, and meaningless under the native aggregation profile,
## which is one pass with no channels in it.
@export_range(0, 9, 1) var final_channel: int = 0

@export var coefficient: GameplayScalableFloat = null
@export var pre_add: GameplayScalableFloat = null
@export var post_add: GameplayScalableFloat = null

## Applied last, to the finished number.
##
## Last rather than to the reading, because a curve here is how a designer says
## "and then bend it" - a diminishing return on the total, a threshold. A curve
## applied to the reading would be a different statement, and the capture is
## the place for that one.
@export var attribute_curve: Curve = null

## This magnitude counts for nothing unless both sides match.
##
## Nothing rather than a refusal: "twice as much damage against burning
## targets" is one modifier that is worth zero the rest of the time, and an
## effect that failed to apply instead would be an effect that does not land on
## anybody who is not on fire.
@export var source_requirements: GameplayTagQuery = null
@export var target_requirements: GameplayTagQuery = null

## The same capture, read the other way, built once and kept.
##
## Kept rather than built per resolve because a SNAPSHOT capture is keyed by the
## definition object: a fresh one each time would never find the snapshot the
## spec already took, and would silently read the world as it is now.
var _base_twin: GameplayAttributeCaptureDefinition = null
var _current_twin: GameplayAttributeCaptureDefinition = null


func required_captures() -> Array[GameplayAttributeCaptureDefinition]:
	if capture == null:
		return []
	var needed: Array[GameplayAttributeCaptureDefinition] = [capture]
	if calculation == Calculation.BASE_VALUE or calculation == Calculation.BONUS_MAGNITUDE:
		needed.append(_twin(GameplayAttributeCaptureDefinition.Value.BASE))
	if calculation == Calculation.BONUS_MAGNITUDE:
		needed.append(_twin(GameplayAttributeCaptureDefinition.Value.CURRENT))
	return needed


func resolve(context: GameplayMagnitudeContext) -> GameplayMagnitudeResult:
	if capture == null or context == null or context.spec == null:
		return GameplayMagnitudeResult.failure(GameplayMagnitudeResult.Status.INVALID_DEFINITION)

	# The capture is resolved first even when the reading does not come from it,
	# so a magnitude naming an attribute nobody has says so rather than quietly
	# counting for nothing.
	var captured: AttributeCaptureResult = context.spec.resolve_capture(
		capture, context.source_asc, context.target_asc
	)
	if not captured.is_ok():
		return GameplayMagnitudeResult.failure(_translate(captured.status))

	if not _requirements_hold(context):
		return GameplayMagnitudeResult.ok(0.0)

	var reading: AttributeCaptureResult = _reading(context, captured)
	if not reading.is_ok():
		return GameplayMagnitudeResult.failure(_translate(reading.status))

	var coeff: float = coefficient.evaluate(context.level) if coefficient != null else 1.0
	var pre: float = pre_add.evaluate(context.level) if pre_add != null else 0.0
	var post: float = post_add.evaluate(context.level) if post_add != null else 0.0
	var resolved: float = ((reading.value + pre) * coeff) + post
	if attribute_curve != null:
		resolved = attribute_curve.sample(resolved)

	if not is_finite(resolved):
		return GameplayMagnitudeResult.failure(GameplayMagnitudeResult.Status.NON_FINITE_VALUE)
	return GameplayMagnitudeResult.ok(resolved)


## Whether both sides are what this magnitude requires them to be.
##
## The source is read from the spec's own snapshot - what the caster was when
## the effect was made, which is the moment the magnitude is about. The target
## is read live, because the effect is landing on it now and there is no earlier
## moment to prefer.
func _requirements_hold(context: GameplayMagnitudeContext) -> bool:
	if source_requirements != null and not source_requirements.is_empty():
		if not source_requirements.matches_tags(context.spec.source_tags_snapshot):
			return false
	if target_requirements != null and not target_requirements.is_empty():
		if context.target_asc == null:
			return false
		if not target_requirements.matches_runtime(context.target_asc.tags):
			return false
	return true


## The number this calculation is about.
func _reading(
	context: GameplayMagnitudeContext, captured: AttributeCaptureResult
) -> AttributeCaptureResult:
	match calculation:
		Calculation.BASE_VALUE:
			return _twin_reading(context, GameplayAttributeCaptureDefinition.Value.BASE)
		Calculation.BONUS_MAGNITUDE:
			return _bonus(context)
		Calculation.MAGNITUDE_UP_TO_CHANNEL:
			return _up_to_channel(context)
		_:
			return captured


## Current minus base: only the part of the attribute that is not durable.
func _bonus(context: GameplayMagnitudeContext) -> AttributeCaptureResult:
	var base: AttributeCaptureResult = _twin_reading(
		context, GameplayAttributeCaptureDefinition.Value.BASE
	)
	if not base.is_ok():
		return base
	var current: AttributeCaptureResult = _twin_reading(
		context, GameplayAttributeCaptureDefinition.Value.CURRENT
	)
	if not current.is_ok():
		return current
	var made: AttributeCaptureResult = AttributeCaptureResult.new()
	made.value = current.value - base.value
	return made


## What the attribute would read with only the first channels applied.
##
## Read from the live component rather than through the capture, because there
## is nothing to snapshot: the question is about a composition, and a snapshot
## of one would be a number that stopped meaning anything the moment anything
## else was applied.
func _up_to_channel(context: GameplayMagnitudeContext) -> AttributeCaptureResult:
	var made: AttributeCaptureResult = AttributeCaptureResult.new()
	var asc: AbilitySystemComponent = _actor_asc(context)
	if asc == null:
		made.status = _missing_status()
		return made
	if not asc.has_attribute(capture.attribute_name):
		made.status = AttributeCaptureResult.Status.ATTRIBUTE_NOT_FOUND
		return made
	made.value = asc.get_attribute_up_to_channel(capture.attribute_name, final_channel)
	return made


## One of the two twins, resolved through the spec so a snapshot is honoured.
func _twin_reading(
	context: GameplayMagnitudeContext, value: GameplayAttributeCaptureDefinition.Value
) -> AttributeCaptureResult:
	return context.spec.resolve_capture(_twin(value), context.source_asc, context.target_asc)


## The capture this one names, read as BASE or as CURRENT instead.
func _twin(
	value: GameplayAttributeCaptureDefinition.Value
) -> GameplayAttributeCaptureDefinition:
	var wants_base: bool = value == GameplayAttributeCaptureDefinition.Value.BASE
	var kept: GameplayAttributeCaptureDefinition = _base_twin if wants_base else _current_twin
	if kept != null:
		return kept
	var made: GameplayAttributeCaptureDefinition = GameplayAttributeCaptureDefinition.new()
	made.actor = capture.actor
	made.attribute = capture.attribute
	made.attribute_name = capture.attribute_name
	made.policy = capture.policy
	made.value = value
	if wants_base:
		_base_twin = made
	else:
		_current_twin = made
	return made


func _actor_asc(context: GameplayMagnitudeContext) -> AbilitySystemComponent:
	if capture.actor == GameplayAttributeCaptureDefinition.Actor.SOURCE:
		return context.source_asc
	return context.target_asc


func _missing_status() -> AttributeCaptureResult.Status:
	if capture.actor == GameplayAttributeCaptureDefinition.Actor.SOURCE:
		return AttributeCaptureResult.Status.SOURCE_MISSING
	return AttributeCaptureResult.Status.TARGET_MISSING


## AttributeCaptureResult's own reasons, translated to this magnitude's own
## vocabulary: SOURCE_MISSING and TARGET_MISSING are both "the capture this
## magnitude needed never resolved", which is the one thing a caller here
## actually needs to know.
##
## INVALID_DEFINITION is not one of those, and used to fall through into the
## same answer. A capture whose attribute_name was left blank is a definition
## that is wrong, not one that is missing - this class already reports its own
## unset capture that way, a few lines up - and MISSING_CAPTURE sent an author
## looking for a capture nobody registered when the one they wrote is right
## there, empty.
static func _translate(status: AttributeCaptureResult.Status) -> GameplayMagnitudeResult.Status:
	match status:
		AttributeCaptureResult.Status.ATTRIBUTE_NOT_FOUND:
			return GameplayMagnitudeResult.Status.ATTRIBUTE_NOT_FOUND
		AttributeCaptureResult.Status.NON_FINITE_VALUE:
			return GameplayMagnitudeResult.Status.NON_FINITE_VALUE
		AttributeCaptureResult.Status.INVALID_DEFINITION:
			return GameplayMagnitudeResult.Status.INVALID_DEFINITION
		_:
			return GameplayMagnitudeResult.Status.MISSING_CAPTURE
