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
## and an attribute that receives both in one evaluation is written once, in a
## defined order: the execution decides the base, and the standard modifiers
## compose over what it decided. That is the order this file has always run in,
## and it is the order the aggregate already works by - a base, and passes over
## it - so there is one rule rather than one per mechanism.
##
## What is still refused is a write whose target is ambiguous: an attribute two
## of this entity's sets declare. Not for want of an order, but because the
## write itself has two possible destinations and picking the set that happens
## to be listed first is an answer that changes when somebody reorders a list.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
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
	var mode: GameplayEffectEvaluator.Mode = Mode.CONTRIBUTION
	var application_order: int = 0
	## Populated from `spec.source_asc`. A magnitude or execution calculation
	## that needs the instigator's ASC reads it from here rather than
	## re-deriving it from a Node each has its own opinion about.
	var source_asc: AbilitySystemComponent = null
	## The active effect this evaluation belongs to, for
	## GameplayEffectExecuteData.effect_handle - null for the initial
	## apply() evaluation, since no handle exists yet at that point for any
	## effect type.
	var effect_handle: GameplayEffectHandle = null


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

	var produced: GameplayExecutionOutput = GameplayExecutionPipeline.run(spec, request.owner_asc)
	result.execution_output = produced
	if spec.had_invalid_magnitude_access():
		return GameplayEffectEvaluationResult.failure(AttributeEvaluationResult.Status.INVALID_MODIFIER_INDEX, &"")

	var unresolved: GameplayAttributeRef = GameplayExecutionPipeline.first_unresolved(
		produced, request.attributes
	)
	if unresolved != null:
		return GameplayEffectEvaluationResult.failure(
			AttributeEvaluationResult.Status.ATTRIBUTE_NOT_FOUND, unresolved.attribute_name
		)

	var writes: Array[AttributeModifierContribution] = GameplayExecutionPipeline.writes_of(
		produced, request.application_order
	)
	var modifier_targets: Array[StringName] = _modifier_attribute_names(spec)

	# An attribute two of this entity's sets declare - a driver and the vehicle
	# both having `health` - is two attributes with one name, and every write
	# below is addressed by that name. Refused rather than sent to whichever set
	# was listed first, which is an answer that changes when somebody reorders
	# the list and reports nothing when it does.
	var ambiguous: StringName = request.attributes.first_ambiguous(
		GameplayExecutionPipeline.attributes_of(writes)
	)
	if ambiguous == &"":
		ambiguous = request.attributes.first_ambiguous(modifier_targets)
	if ambiguous != &"":
		return GameplayEffectEvaluationResult.failure(AttributeEvaluationResult.Status.AMBIGUOUS_ATTRIBUTE_WRITE, ambiguous)

	_stage_execution_writes(request, writes, modifier_targets, result)
	if not result.is_ok():
		return result

	if request.mode == Mode.CONTRIBUTION:
		_build_contributions(request, modifier_targets, result)
	else:
		_stage_modifier_base_mutations(request, modifier_targets, writes, result)

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
## Turn what the executions decided into staged base writes. Always routed
## through the execute-hook - an ExecCalc output triggers pre/post regardless of
## the containing effect's duration policy, unlike a standard modifier.
##
## An attribute the effect's own modifiers also write is skipped here when they
## write the base too, because then both belong in one write: staging it twice
## would move the base twice and fire the execute hook twice for one
## application. Under CONTRIBUTION they never collide - the modifiers become
## contributions and compose over whatever base this leaves behind.
static func _stage_execution_writes(
	request: Request,
	writes: Array[AttributeModifierContribution],
	modifier_targets: Array[StringName],
	result: GameplayEffectEvaluationResult
) -> void:
	var modifiers_write_the_base: bool = request.mode == Mode.BASE_MUTATION
	for attribute_name: StringName in GameplayExecutionPipeline.attributes_of(writes):
		if modifiers_write_the_base and modifier_targets.has(attribute_name):
			continue

		var composed: float = _composed_execution_base(request, attribute_name, writes, result)
		if not result.is_ok():
			return
		if not _stage_effect_mutation(request, attribute_name, composed, result):
			return


## What one attribute is worth once this evaluation's executions have had their
## say - the base itself when none of them named it.
static func _composed_execution_base(
	request: Request,
	attribute_name: StringName,
	writes: Array[AttributeModifierContribution],
	result: GameplayEffectEvaluationResult
) -> float:
	# Which arithmetic this entity composes by is asked of the component every
	# time rather than cached, for the reason GameplayAttributeRuntime gives:
	# the profile is data somebody can change.
	var unreal: bool = _unreal_profile(request)
	var folded: AttributeAggregateMath.Composed = GameplayExecutionPipeline.compose(
		request.attributes, attribute_name, writes, unreal
	)
	if not folded.is_ok():
		result.status = folded.status
		result.error_attribute_name = attribute_name
		return 0.0
	return folded.value


## Stage one attribute's effect-driven base write through
## stage_gameplay_effect_base_write, appending to result.base_mutations on
## success. False means result already carries the failure -
## GAMEPLAY_EFFECT_EXECUTE_REJECTED for a pre-hook veto, the same as any other
## refusal an evaluation can produce.
static func _stage_effect_mutation(
	request: Request, attribute_name: StringName, requested: float, result: GameplayEffectEvaluationResult
) -> bool:
	var data: GameplayEffectExecuteData = GameplayEffectExecuteData.new()
	data.spec = request.spec
	data.effect_handle = request.effect_handle
	data.source_asc = request.source_asc
	data.target_asc = request.owner_asc
	data.attribute_name = attribute_name
	data.requested_base = requested
	data.proposed_base = requested

	var staged: AttributeBaseMutation = request.attributes.stage_gameplay_effect_base_write(data)
	if staged == null:
		result.status = AttributeEvaluationResult.Status.GAMEPLAY_EFFECT_EXECUTE_REJECTED
		result.error_attribute_name = attribute_name
		return false
	if not is_finite(staged.committed_base_value):
		result.status = AttributeEvaluationResult.Status.NON_FINITE_VALUE
		result.error_attribute_name = attribute_name
		return false

	result.base_mutations.append(staged)
	return true
#endregion


#region Modifiers
## A standard modifier's resolved magnitude, scaled by the stack it belongs
## to when the effect asks for it. Never applies to an execution
## calculation's own math - that reads spec.stack_count itself and decides.
static func stack_scaled_value(
	spec: GameplayEffectSpec, magnitude: float, unreal: bool = false
) -> float:
	return stack_scaled_for(
		spec, magnitude, GameplayEffectModifier.Operation.ADD, unreal
	)


## What one modifier of a stack is worth, by what its operation means.
static func stack_scaled_for(
	spec: GameplayEffectSpec,
	magnitude: float,
	operation: GameplayEffectModifier.Operation,
	unreal: bool = false
) -> float:
	if spec == null or spec.effect_def == null or not spec.effect_def.factor_in_stack_count:
		return magnitude
	return AttributeAggregateMath.stack_scaled(
		magnitude, float(spec.stack_count), operation, unreal
	)


static func _stack_scaled_magnitude(
	spec: GameplayEffectSpec, index: int, unreal: bool
) -> float:
	var modifier: GameplayEffectModifier = spec.effect_def.modifiers[index]
	return stack_scaled_for(spec, spec.get_magnitude(index), modifier.operation, unreal)


## Which arithmetic this request's entity composes by.
##
## Asked of the component every time rather than cached, for the reason
## GameplayAttributeRuntime gives: the profile is data somebody can change.
static func _unreal_profile(request: Request) -> bool:
	return request.owner_asc != null and request.owner_asc.uses_ue_5_7_contracts()


## Every attribute a standard modifier writes to, without duplicates.
static func _modifier_attribute_names(spec: GameplayEffectSpec) -> Array[StringName]:
	var names: Array[StringName] = []
	for modifier: GameplayEffectModifier in spec.effect_def.modifiers:
		if modifier == null or modifier.attribute_name.is_empty():
			continue
		if not names.has(modifier.attribute_name):
			names.append(modifier.attribute_name)
	return names


## Build one contribution per modifier, for an effect that stays active.
## Whether this one modifier applies to this pairing at all.
##
## A condition on the modifier rather than on the effect, which is what lets one
## effect hit harder against the undead and normally against everything else
## without being authored twice. Unmet is not a refusal: the modifier simply is
## not part of this application, and the rest of the effect goes on as written.
##
## The source is judged by the tags it had when the application was made, not by
## whatever it carries now - it is the same snapshot every other capture reads,
## for the same reason.
static func _qualifies(request: Request, modifier: GameplayEffectModifier) -> bool:
	if modifier.source_requirements != null:
		if not modifier.source_requirements.matches_tags(request.spec.source_tags_snapshot):
			return false
	if modifier.target_requirements != null:
		var target: AbilitySystemComponent = request.owner_asc
		var carried: Array[StringName] = (
			target.tags.active_tags() if target != null else [] as Array[StringName]
		)
		if not modifier.target_requirements.matches_tags(carried):
			return false
	return true


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
		if not _qualifies(request, modifier):
			continue

		var magnitude: float = _stack_scaled_magnitude(spec, index, _unreal_profile(request))
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

		# An operation outside the enum entirely - a resource written by another
		# version, or set from code. `_compose()` has a `_:` branch for it, but that
		# runs long after the effect is registered, so the refusal has nowhere to go
		# and the attribute silently stops recomposing for EVERY effect, not just
		# this one. Refused here, beside its two siblings, so no contribution ever
		# carries one.
		if not GameplayEffectModifier.Operation.values().has(modifier.operation):
			result.status = AttributeEvaluationResult.Status.INVALID_OPERATION
			result.error_attribute_name = modifier.attribute_name
			result.contributions.clear()
			return

		var contribution: AttributeModifierContribution = AttributeModifierContribution.new()
		contribution.attribute_name = modifier.attribute_name
		contribution.operation = modifier.operation
		contribution.evaluation_channel = modifier.evaluation_channel
		contribution.magnitude = magnitude
		contribution.modifier_index = index
		contribution.application_order = request.application_order
		result.contributions.append(contribution)

	if not result.contributions.is_empty():
		var aggregate_check: AttributeAggregateValidationResult = (
			request.attributes.validate_additional_contributions(result.contributions)
		)
		if not aggregate_check.is_ok():
			result.status = aggregate_check.status
			result.error_attribute_name = aggregate_check.attribute_name
			result.contributions.clear()


## Apply the canonical formula to each affected attribute's BASE and stage the
## outcome. This is the instant and periodic path: the transformation happens
## once and nothing is registered with the aggregator.
static func _stage_modifier_base_mutations(
	request: Request,
	modifier_targets: Array[StringName],
	writes: Array[AttributeModifierContribution],
	result: GameplayEffectEvaluationResult
) -> void:
	for attribute_name: StringName in modifier_targets:
		if not request.attributes.has(attribute_name):
			result.status = AttributeEvaluationResult.Status.ATTRIBUTE_NOT_FOUND
			result.error_attribute_name = attribute_name
			result.base_mutations.clear()
			return

		# Starting from what the executions made of it, which is the defined
		# order: the calculation decides the base and these compose over it.
		var starting: float = _composed_execution_base(request, attribute_name, writes, result)
		if not result.is_ok():
			result.base_mutations.clear()
			return

		var composed: float = _compose_for_attribute(request, attribute_name, starting, result)
		if not result.is_ok():
			result.base_mutations.clear()
			return

		if not _stage_effect_mutation(request, attribute_name, composed, result):
			result.base_mutations.clear()
			return


## The canonical order applied to one attribute using only THIS spec's modifiers.
##
## The aggregator applies the same order over active contributions. Both had to
## exist because the inputs differ - a base transformation versus a live stack -
## but the arithmetic is written once in each and verified against the same
## table of cases: base 10, +10, x2 is 40 in both.
static func _compose_for_attribute(
	request: Request,
	attribute_name: StringName,
	base: float,
	result: GameplayEffectEvaluationResult
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

		var magnitude: float = _stack_scaled_magnitude(spec, index, _unreal_profile(request))
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

	var composed: float = ((base + total_add) * product_multiply) / product_divide
	if winning_index >= 0:
		composed = winning_magnitude

	if not is_finite(composed):
		result.status = AttributeEvaluationResult.Status.NON_FINITE_VALUE
		result.error_attribute_name = attribute_name
		return 0.0

	return composed
#endregion

#region Affordability
## Whether every attribute this cost touches can pay it in full from its
## durable base. A temporary buff does not subsidise it - Mana base 10 with
## an active +20 cannot pay 20, since committing -20 to base gets reduced by
## the clamp, and a cost the clamp had to shrink was survivable, not
## affordable.
##
## Lives here rather than on the component that exposes it, because it is
## this evaluator's own answer read a second way: it builds the very request
## a commit builds, on an isolated spec copy, so a preview cannot disagree
## with the commit or mutate anything.
static func can_afford(
	effect: GameplayEffect, effect_level: float, asc: AbilitySystemComponent
) -> bool:
	if effect == null:
		return true

	var context: GameplayEffectContext = GameplayEffectContext.new(asc.get_effect_target())
	var probe: GameplayEffectSpec = GameplayEffectSpec.new(effect, context, effect_level)

	var request: Request = Request.new()
	request.spec = probe
	request.attributes = asc.attributes
	request.owner_asc = asc
	request.application_order = 0
	request.mode = Mode.BASE_MUTATION
	request.source_asc = probe.source_asc

	var evaluation: GameplayEffectEvaluationResult = evaluate(request)
	if not evaluation.is_ok():
		return false

	var against_current: bool = asc.uses_ue_5_7_contracts()
	for staged: AttributeBaseMutation in evaluation.base_mutations:
		if against_current:
			# Unreal's question, and the whole question: does it fit in what the
			# attribute is worth right now. The durable base is not what funds a
			# cost there, so its sign says nothing about affordability.
			if not _affordable_from_current(asc, staged):
				return false
			continue

		# A cost cannot create debt merely because an AttributeSet chose not to
		# clamp below zero. This check is independent of clamp behavior.
		if staged.requested_base_value < 0.0:
			return false
		if not is_equal_approx(staged.committed_base_value, staged.requested_base_value):
			return false
	return true


## Whether the charge fits in what the attribute is worth right now.
##
## Unreal prices against the current value, this engine has always priced
## against the durable base, and on a buffed attribute those are different
## numbers: a shield that adds 50 mana is mana you can spend under one contract
## and cannot under the other. Neither is wrong, and a project that changed
## answer without asking would have every cost in it silently repriced - so the
## profile decides, and the default keeps what a project already had.
static func _affordable_from_current(
	asc: AbilitySystemComponent, staged: AttributeBaseMutation
) -> bool:
	var spent: float = staged.old_base_value - staged.requested_base_value
	if spent <= 0.0:
		return true
	return asc.get_attribute_current(staged.attribute_name) >= spent
#endregion
