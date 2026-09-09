## Everything one execution calculation is allowed to know, and the scratch
## space it is allowed to keep.
##
## An execution used to be handed a spec and a target and nothing else, so
## anything it wanted to remember between two of its own steps had to go
## somewhere that outlives it - a field on the calculation Resource, which is
## shared by every application using it, or the spec, which is carried into the
## runtime. Both are how one hit ends up reading another hit's number.
##
## What is here lives exactly as long as one run of one effect's executions and
## is then dropped. Nothing on it is read afterwards, and that is the property
## worth keeping: a scratch value that escaped would be a value somebody starts
## depending on.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayExecutionContext extends RefCounted

var spec: GameplayEffectSpec = null
var source_asc: AbilitySystemComponent = null
var target_asc: AbilitySystemComponent = null

## The tags this application was handed by whoever made it - a hit that knows
## it was a critical, an effect told what element it arrived as. Copied from
## the spec rather than read through it, so an execution cannot append to what
## the application will carry afterwards.
var passed_in_tags: Array[StringName] = []

## Scratch numbers, by name, for one run.
##
## Floats rather than Variant: a scratch space that could hold anything is a
## second payload format, and the whole reason this is not a Dictionary on the
## spec is that it must not become one.
var transient: Dictionary[StringName, float] = {}

## The adjustments in force for this run only, gathered from the calculations
## that declared them and already filtered by their requirements.
var scoped: Array[GameplayExecutionScopedModifier] = []


## What this execution reads for a capture, with its scoped adjustments in.
##
## The door a calculation should ask through when it has declared scoped
## modifiers. Asking `spec.resolve_capture()` directly still works and still
## answers the unadjusted value, which is right: a calculation that declared no
## adjustments is not affected by this, and one that reads around them is
## reading the world rather than its own scope.
## @composer
func captured(definition: GameplayAttributeCaptureDefinition) -> AttributeCaptureResult:
	var read: AttributeCaptureResult = spec.resolve_capture(definition, source_asc, target_asc)
	if not read.is_ok() or definition == null:
		return read
	var adjusted: AttributeCaptureResult = AttributeCaptureResult.new()
	adjusted.value = adjust(definition.attribute_name, read.value)
	return adjusted


## One number with this run's adjustments folded into it.
##
## Folded by the arithmetic every other contribution is folded by, in this
## entity's own profile of it - never a second formula written here, which is
## the difference between a scoped modifier and a calculation doing its own
## multiplication.
## @composer
func adjust(attribute_name: StringName, value: float) -> float:
	var writes: Array[AttributeModifierContribution] = _writes_for(attribute_name)
	if writes.is_empty():
		return value
	var unreal: bool = target_asc != null and target_asc.uses_ue_5_7_contracts()
	var folded: AttributeAggregateMath.Composed = (
		AttributeAggregateMath.unreal(value, attribute_name, writes)
		if unreal
		else AttributeAggregateMath.godot_native(value, attribute_name, writes)
	)
	return folded.value if folded.is_ok() else value


## This run's adjustments for one attribute, as contributions the fold reads.
func _writes_for(attribute_name: StringName) -> Array[AttributeModifierContribution]:
	var writes: Array[AttributeModifierContribution] = []
	for index: int in scoped.size():
		var modifier: GameplayExecutionScopedModifier = scoped[index]
		if modifier == null or modifier.attribute == null:
			continue
		if modifier.attribute.attribute_name != attribute_name:
			continue
		var write: AttributeModifierContribution = AttributeModifierContribution.new()
		write.attribute_name = attribute_name
		write.operation = modifier.operation
		write.magnitude = _magnitude_of(modifier)
		write.evaluation_channel = modifier.evaluation_channel
		write.modifier_index = index
		write.application_order = 0
		writes.append(write)
	return writes


## What one adjustment is worth, resolved against this application.
##
## A scoped modifier with no magnitude at all is worth the identity of its own
## operation rather than zero: an author who left it empty wrote nothing, and
## nothing should not silently mean "multiply by zero".
func _magnitude_of(modifier: GameplayExecutionScopedModifier) -> float:
	if modifier.magnitude == null:
		return _identity_of(modifier.operation)
	var resolved: GameplayMagnitudeResult = modifier.magnitude.resolve(
		GameplayMagnitudeContext.of(spec, source_asc, target_asc)
	)
	return resolved.value if resolved.is_ok() else _identity_of(modifier.operation)


static func _identity_of(operation: GameplayEffectModifier.Operation) -> float:
	match operation:
		GameplayEffectModifier.Operation.MULTIPLY, \
		GameplayEffectModifier.Operation.DIVIDE, \
		GameplayEffectModifier.Operation.MULTIPLY_ADDITIVE, \
		GameplayEffectModifier.Operation.DIVIDE_ADDITIVE, \
		GameplayEffectModifier.Operation.MULTIPLY_COMPOUND:
			return 1.0
		_:
			return 0.0
