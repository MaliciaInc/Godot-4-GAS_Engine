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


## Evaluate a spec into staged base mutations and contributions.
##
## Nothing here is applied. The caller commits, and only if `is_ok()`.
static func evaluate(request: Request) -> GameplayEffectEvaluationResult:
	if request == null or request.spec == null or request.spec.effect_def == null:
		return GameplayEffectEvaluationResult.failure(AttributeEvaluationResult.Status.INVALID_SPEC, &"")

	var spec: GameplayEffectSpec = request.spec
	var result: GameplayEffectEvaluationResult = GameplayEffectEvaluationResult.new()

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
## Every attribute a standard modifier writes to, without duplicates.
static func _modifier_attribute_names(spec: GameplayEffectSpec) -> Array[StringName]:
	var names: Array[StringName] = []
	for modifier: GameplayEffectModifier in spec.effect_def.modifiers:
		if modifier == null or modifier.attribute_name.is_empty():
			continue
		var name: StringName = StringName(modifier.attribute_name)
		if not names.has(name):
			names.append(name)
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

		var magnitude: float = spec.get_magnitude(index)
		if not is_finite(magnitude):
			result.status = AttributeEvaluationResult.Status.NON_FINITE_VALUE
			result.error_attribute_name = StringName(modifier.attribute_name)
			result.contributions.clear()
			return

		if modifier.operation == GameplayEffectModifier.Operation.DIVIDE and is_zero_approx(magnitude):
			result.status = AttributeEvaluationResult.Status.DIVISION_BY_ZERO
			result.error_attribute_name = StringName(modifier.attribute_name)
			result.contributions.clear()
			return

		var contribution: AttributeModifierContribution = AttributeModifierContribution.new()
		contribution.attribute_name = StringName(modifier.attribute_name)
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
		if modifier == null or StringName(modifier.attribute_name) != attribute_name:
			continue

		var magnitude: float = spec.get_magnitude(index)
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
