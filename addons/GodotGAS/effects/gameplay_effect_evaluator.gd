## Pure evaluation of one spec into staged work.
##
## This class reads state and returns a result. It does not emit signals, write
## to Resources, touch the SceneTree, start timers, write tags or mutate active
## effects. That is what makes a cost preview and the commit that follows it
## provably the same computation: they call this, once each, on the same inputs.
##
## The split is enforced here:
##
##     standard active modifier  -> contribution to the aggregator
##     execution calculation     -> instant mutation of the underlying base
##
## and an attribute that would receive both in one evaluation fails the whole
## application with AMBIGUOUS_ATTRIBUTE_WRITE. There is no correct order for
## "add 5 flat" and "multiply by 2" arriving from two different mechanisms, so
## the engine refuses rather than picking one and being quietly wrong.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_license: MIT
class_name GameplayEffectEvaluator extends RefCounted


## How this effect's standard modifiers are meant to land.
##
## BASE_MUTATION covers INSTANT and PERIODIC: the modifiers transform the
## durable value once and leave nothing behind. CONTRIBUTION covers DURATION and
## INFINITE: the modifiers join the aggregator and are removed with the effect.
enum Mode { BASE_MUTATION, CONTRIBUTION }


## The inputs one evaluation needs, as one typed value.
##
## Bundled so `evaluate` stays inside the project's parameter-count limit and so
## a caller cannot pass the application order of one effect with the spec of
## another.
class Request extends RefCounted:
	var spec: GameplayEffectSpec = null
	var attributes: GameplayAttributeRuntime = null
	var owner_asc: AbilitySystemComponent = null
	var mode: Mode = Mode.CONTRIBUTION
	var application_order: int = 0
	## Populated from `spec.source_asc`. A magnitude or execution calculation
	## that needs the instigator's ASC reads it from here rather than
	## re-deriving it from a Node each has its own opinion about.
	var source_asc: AbilitySystemComponent = null


## Evaluate a spec into staged base mutations and contributions.
##
## Nothing here is applied. The caller commits, and only if `is_ok()`.
static func evaluate(request: Request) -> GameplayEffectEvaluationResult:
	if request == null or request.spec == null or request.spec.effect_def == null:
		return GameplayEffectEvaluationResult.failure(AttributeEvaluationResult.Status.INVALID_SPEC, &"")

	# Brackets every return path below in one place, so a per-evaluation
	# magnitude cache never leaks into the next evaluation of the same spec -
	# a PERIODIC tick reusing an earlier tick's LIVE reading would be exactly
	# the staleness that cache exists to prevent.
	request.spec._begin_evaluation_cache()
	var result: GameplayEffectEvaluationResult = _evaluate_inner(request)
	request.spec._end_evaluation_cache()
	return result


static func _evaluate_inner(request: Request) -> GameplayEffectEvaluationResult:
	var spec: GameplayEffectSpec = request.spec
	var result: GameplayEffectEvaluationResult = GameplayEffectEvaluationResult.new()

	# Authored magnitudes resolve once, before executions run, so an
	# execution calculation's own get_magnitude()/set_magnitude() sees this
	# evaluation's real values rather than nothing yet prepared.
	if not _resolve_authored_magnitudes(request, result):
		return result

	var execution_deltas: Dictionary[StringName, float] = _run_executions(request)
	if spec.had_invalid_magnitude_access():
		return GameplayEffectEvaluationResult.failure(AttributeEvaluationResult.Status.INVALID_MODIFIER_INDEX, &"")

	var modifier_targets: Array[StringName] = _modifier_attribute_names(spec)

	var ambiguous: StringName = _first_ambiguous_attribute(execution_deltas, modifier_targets)
	if ambiguous != &"":
		return GameplayEffectEvaluationResult.failure(AttributeEvaluationResult.Status.AMBIGUOUS_ATTRIBUTE_WRITE, ambiguous)

	_stage_execution_deltas(request, execution_deltas, result)
	if not result.is_ok():
		return result

	if request.mode == Mode.CONTRIBUTION:
		_build_contributions(request, modifier_targets, result)
	else:
		_stage_modifier_base_mutations(request, modifier_targets, result)

	return result


#region Magnitudes
## Resolve every modifier's authored magnitude once for this evaluation and
## cache each by index, so get_magnitude() answers consistently for the rest
## of it. One modifier failing to resolve fails the whole evaluation, the
## same as any other refusal here.
static func _resolve_authored_magnitudes(
	request: Request, result: GameplayEffectEvaluationResult
) -> bool:
	var spec: GameplayEffectSpec = request.spec
	var context: GameplayMagnitudeContext = GameplayMagnitudeContext.new()
	context.spec = spec
	context.source_asc = request.source_asc
	context.target_asc = request.owner_asc
	context.level = spec.level

	for index: int in spec.effect_def.modifiers.size():
		var modifier: GameplayEffectModifier = spec.effect_def.modifiers[index]
		if modifier == null or modifier.magnitude == null:
			continue
		if _is_direct_live_self_cycle(modifier):
			result.status = AttributeEvaluationResult.Status.LIVE_MAGNITUDE_CYCLE
			result.error_attribute_name = modifier.attribute_name
			return false
		var resolved: GameplayMagnitudeResult = modifier.magnitude.resolve(context)
		if not resolved.is_ok():
			result.status = _translate_magnitude_status(resolved.status)
			result.error_attribute_name = modifier.attribute_name
			return false
		spec._cache_evaluation_magnitude(index, resolved.value)
	return true


## A modifier whose magnitude reads, LIVE, the exact TARGET attribute it
## itself writes: the contribution's own output would be an input to
## computing itself, on every single read, not merely on a later reactive
## update - refused before it is ever evaluated once, not just before a
## GameplayLiveMagnitudeBinding would be created for it.
static func _is_direct_live_self_cycle(modifier: GameplayEffectModifier) -> bool:
	var attribute_based: GameplayAttributeBasedMagnitude = modifier.magnitude as GameplayAttributeBasedMagnitude
	if attribute_based == null or attribute_based.capture == null:
		return false
	var capture: GameplayAttributeCaptureDefinition = attribute_based.capture
	return (
		capture.policy == GameplayAttributeCaptureDefinition.Policy.LIVE
		and capture.actor == GameplayAttributeCaptureDefinition.Actor.TARGET
		and capture.attribute_name == modifier.attribute_name
	)


## GameplayMagnitudeResult's reasons, translated to this evaluator's own
## vocabulary - the one it already reports through, so a caller checking
## `result.status` never has to know two different failure enums exist.
static func _translate_magnitude_status(
	status: GameplayMagnitudeResult.Status
) -> AttributeEvaluationResult.Status:
	match status:
		GameplayMagnitudeResult.Status.MISSING_CAPTURE:
			return AttributeEvaluationResult.Status.MISSING_CAPTURE
		GameplayMagnitudeResult.Status.MISSING_SET_BY_CALLER:
			return AttributeEvaluationResult.Status.MISSING_SET_BY_CALLER
		GameplayMagnitudeResult.Status.ATTRIBUTE_NOT_FOUND:
			return AttributeEvaluationResult.Status.ATTRIBUTE_NOT_FOUND
		GameplayMagnitudeResult.Status.CALCULATION_FAILED:
			return AttributeEvaluationResult.Status.MAGNITUDE_CALCULATION_FAILED
		GameplayMagnitudeResult.Status.NON_FINITE_VALUE:
			return AttributeEvaluationResult.Status.NON_FINITE_VALUE
		_:
			return AttributeEvaluationResult.Status.INVALID_MAGNITUDE_DEFINITION
#endregion


#region Execution calculations
## Run every execution calculation and merge their flat deltas.
##
## The Dictionary is an extension boundary, not a domain contract: it is typed,
## it is produced by user scripts outside this addon, and it is converted into
## staged AttributeBaseMutations before it leaves this file.
static func _run_executions(request: Request) -> Dictionary[StringName, float]:
	var merged: Dictionary[StringName, float] = {}
	for execution: GameplayExecutionCalculation in request.spec.effect_def.executions:
		if execution == null:
			continue
		var produced: Dictionary[StringName, float] = execution.execute(request.spec, request.owner_asc)
		for attribute_name: StringName in produced:
			merged[attribute_name] = merged.get(attribute_name, 0.0) + produced[attribute_name]
	return merged


## Turn execution deltas into staged base writes.
static func _stage_execution_deltas(
	request: Request,
	execution_deltas: Dictionary[StringName, float],
	result: GameplayEffectEvaluationResult
) -> void:
	for attribute_name: StringName in execution_deltas:
		if not request.attributes.has(attribute_name):
			result.status = AttributeEvaluationResult.Status.ATTRIBUTE_NOT_FOUND
			result.error_attribute_name = attribute_name
			return

		var delta: float = execution_deltas[attribute_name]
		if not is_finite(delta):
			result.status = AttributeEvaluationResult.Status.NON_FINITE_VALUE
			result.error_attribute_name = attribute_name
			return

		var requested: float = request.attributes.get_base_value(attribute_name) + delta
		var staged: AttributeBaseMutation = request.attributes.stage_base_write(attribute_name, requested)
		if staged == null or not is_finite(staged.committed_base_value):
			result.status = AttributeEvaluationResult.Status.NON_FINITE_VALUE
			result.error_attribute_name = attribute_name
			return
		result.base_mutations.append(staged)
#endregion


#region Modifiers
## A standard modifier's resolved magnitude, scaled by the stack it belongs
## to when the effect asks for it. Never applies to an execution
## calculation's own math - that reads spec.stack_count itself and decides.
static func _stack_scaled_magnitude(spec: GameplayEffectSpec, index: int) -> float:
	var magnitude: float = spec.get_magnitude(index)
	if spec.effect_def.factor_in_stack_count:
		return magnitude * float(spec.stack_count)
	return magnitude


## Every attribute a standard modifier writes to, without duplicates.
static func _modifier_attribute_names(spec: GameplayEffectSpec) -> Array[StringName]:
	var names: Array[StringName] = []
	for modifier: GameplayEffectModifier in spec.effect_def.modifiers:
		if modifier == null or modifier.attribute_name.is_empty():
			continue
		if not names.has(modifier.attribute_name):
			names.append(modifier.attribute_name)
	return names


## The first attribute written by both mechanisms, or empty when there is none.
static func _first_ambiguous_attribute(
	execution_deltas: Dictionary[StringName, float], modifier_targets: Array[StringName]
) -> StringName:
	for attribute_name: StringName in modifier_targets:
		if execution_deltas.has(attribute_name):
			return attribute_name
	return &""


## Build one contribution per modifier, for an effect that stays active.
static func _build_contributions(
	request: Request, modifier_targets: Array[StringName], result: GameplayEffectEvaluationResult
) -> void:
	var spec: GameplayEffectSpec = request.spec
	for attribute_name: StringName in modifier_targets:
		if not request.attributes.has(attribute_name):
			result.status = AttributeEvaluationResult.Status.ATTRIBUTE_NOT_FOUND
			result.error_attribute_name = attribute_name
			result.contributions.clear()
			return

	for index: int in spec.effect_def.modifiers.size():
		var modifier: GameplayEffectModifier = spec.effect_def.modifiers[index]
		if modifier == null or modifier.attribute_name.is_empty():
			continue

		var magnitude: float = _stack_scaled_magnitude(spec, index)
		if not is_finite(magnitude):
			result.status = AttributeEvaluationResult.Status.NON_FINITE_VALUE
			result.error_attribute_name = modifier.attribute_name
			result.contributions.clear()
			return

		if modifier.operation == GameplayEffectModifier.Operation.DIVIDE and is_zero_approx(magnitude):
			result.status = AttributeEvaluationResult.Status.DIVISION_BY_ZERO
			result.error_attribute_name = modifier.attribute_name
			result.contributions.clear()
			return

		var contribution: AttributeModifierContribution = AttributeModifierContribution.new()
		contribution.attribute_name = modifier.attribute_name
		contribution.operation = modifier.operation
		contribution.magnitude = magnitude
		contribution.modifier_index = index
		contribution.application_order = request.application_order
		result.contributions.append(contribution)


## Apply the canonical formula to each affected attribute's BASE and stage the
## outcome. This is the instant and periodic path: the transformation happens
## once and nothing is registered with the aggregator.
static func _stage_modifier_base_mutations(
	request: Request, modifier_targets: Array[StringName], result: GameplayEffectEvaluationResult
) -> void:
	for attribute_name: StringName in modifier_targets:
		if not request.attributes.has(attribute_name):
			result.status = AttributeEvaluationResult.Status.ATTRIBUTE_NOT_FOUND
			result.error_attribute_name = attribute_name
			result.base_mutations.clear()
			return

		var composed: float = _compose_for_attribute(request, attribute_name, result)
		if not result.is_ok():
			result.base_mutations.clear()
			return

		var staged: AttributeBaseMutation = request.attributes.stage_base_write(attribute_name, composed)
		if staged == null or not is_finite(staged.committed_base_value):
			result.status = AttributeEvaluationResult.Status.NON_FINITE_VALUE
			result.error_attribute_name = attribute_name
			result.base_mutations.clear()
			return
		result.base_mutations.append(staged)


## The canonical order applied to one attribute using only THIS spec's modifiers.
##
## The aggregator applies the same order over active contributions. Both had to
## exist because the inputs differ - a base transformation versus a live stack -
## but the arithmetic is written once in each and verified against the same
## table of cases: base 10, +10, x2 is 40 in both.
static func _compose_for_attribute(
	request: Request, attribute_name: StringName, result: GameplayEffectEvaluationResult
) -> float:
	var spec: GameplayEffectSpec = request.spec
	var total_add: float = 0.0
	var product_multiply: float = 1.0
	var product_divide: float = 1.0
	var winning_index: int = -1
	var winning_magnitude: float = 0.0

	for index: int in spec.effect_def.modifiers.size():
		var modifier: GameplayEffectModifier = spec.effect_def.modifiers[index]
		if modifier == null or modifier.attribute_name != attribute_name:
			continue

		var magnitude: float = _stack_scaled_magnitude(spec, index)
		if not is_finite(magnitude):
			result.status = AttributeEvaluationResult.Status.NON_FINITE_VALUE
			result.error_attribute_name = attribute_name
			return 0.0

		match modifier.operation:
			GameplayEffectModifier.Operation.ADD:
				total_add += magnitude
			GameplayEffectModifier.Operation.MULTIPLY:
				product_multiply *= magnitude
			GameplayEffectModifier.Operation.DIVIDE:
				if is_zero_approx(magnitude):
					result.status = AttributeEvaluationResult.Status.DIVISION_BY_ZERO
					result.error_attribute_name = attribute_name
					return 0.0
				product_divide *= magnitude
			GameplayEffectModifier.Operation.OVERRIDE:
				# Within one effect the higher modifier index wins.
				if index > winning_index:
					winning_index = index
					winning_magnitude = magnitude
			_:
				result.status = AttributeEvaluationResult.Status.INVALID_OPERATION
				result.error_attribute_name = attribute_name
				return 0.0

	var base: float = request.attributes.get_base_value(attribute_name)
	var composed: float = ((base + total_add) * product_multiply) / product_divide
	if winning_index >= 0:
		composed = winning_magnitude

	if not is_finite(composed):
		result.status = AttributeEvaluationResult.Status.NON_FINITE_VALUE
		result.error_attribute_name = attribute_name
		return 0.0

	return composed
#endregion
