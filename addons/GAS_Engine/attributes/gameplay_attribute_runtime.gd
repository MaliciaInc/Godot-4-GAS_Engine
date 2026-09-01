## The attribute aggregator: lookup, base mutation and recomposition.
##
## This is the authority for the canonical formula and nothing else may implement
## it:
##
##     current = ((base + sum(ADD)) * product(MULTIPLY)) / product(DIVIDE)
##
## then the last applicable OVERRIDE, then `pre_attribute_change`. Base 10 with
## +10 and x2 is 40, not 30.
##
## Recomposition recomputes from scratch every time. Upstream applied a flat
## delta per modifier and reversed it on removal, which is order-dependent and
## unrecoverable: removing +20 while x1.5 and x2 are still active cannot be
## expressed as one delta, and changing the base while buffs were active
## silently discarded them. Recomputing has no such failure mode, because there
## is no history to get wrong.
##
## This class emits nothing. It returns results and the ASC facade emits from
## them, so mutable state has exactly one owner and a caller cannot be surprised
## by a signal fired from inside a query.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT
class_name GameplayAttributeRuntime extends RefCounted


## The node handed to `post_attribute_change`, normally the ASC.
var owner_node: Node = null

var _sets: Array[AttributeSet] = []

## Every contribution from every active effect, in no particular order. Ordering
## is expressed by the contribution's own two axes, not by array position, so an
## erase from the middle cannot change the result.
var _contributions: Array[AttributeModifierContribution] = []


#region Sets and lookup
func set_attribute_sets(sets: Array[AttributeSet]) -> void:
	_sets = sets


## The set that declares an attribute, or null.
func find_set(attribute_name: StringName) -> AttributeSet:
	var property_name: String = String(attribute_name)
	for attribute_set: AttributeSet in _sets:
		if attribute_set == null:
			continue
		if attribute_set.get(property_name) is AttributeData:
			return attribute_set
	return null


## The attribute itself, or null when no set declares it.
func find(attribute_name: StringName) -> AttributeData:
	var attribute_set: AttributeSet = find_set(attribute_name)
	if attribute_set == null:
		return null
	return attribute_set.get(String(attribute_name))


func has(attribute_name: StringName) -> bool:
	return find(attribute_name) != null


func get_base_value(attribute_name: StringName) -> float:
	var attribute: AttributeData = find(attribute_name)
	return attribute.base_value if attribute != null else 0.0


func get_current_value(attribute_name: StringName) -> float:
	var attribute: AttributeData = find(attribute_name)
	return attribute.current_value if attribute != null else 0.0


## Every attribute name across every set, for a full recomposition.
func all_attribute_names() -> Array[StringName]:
	var names: Array[StringName] = []
	for attribute_set: AttributeSet in _sets:
		if attribute_set == null:
			continue
		for name: StringName in attribute_set.get_attribute_names():
			if not names.has(name):
				names.append(name)
	return names
#endregion


#region Contributions
func add_contributions(new_contributions: Array[AttributeModifierContribution]) -> void:
	for contribution: AttributeModifierContribution in new_contributions:
		if contribution != null:
			_contributions.append(contribution)


## Drop every contribution belonging to one application. Removal is by
## application order rather than by object identity so a caller cannot leave a
## stale contribution behind by holding a different array.
func remove_contributions_of(application_order: int) -> void:
	for index: int in range(_contributions.size() - 1, -1, -1):
		if _contributions[index].application_order == application_order:
			_contributions.remove_at(index)


func clear_contributions() -> void:
	_contributions.clear()


func contribution_count() -> int:
	return _contributions.size()


func contributions_for(attribute_name: StringName) -> Array[AttributeModifierContribution]:
	var found: Array[AttributeModifierContribution] = []
	for contribution: AttributeModifierContribution in _contributions:
		if contribution.attribute_name == attribute_name:
			found.append(contribution)
	return found
#endregion


#region Evaluation
## Compose one attribute from its base and its active contributions.
##
## Pure: reads state, writes none. `recompose` is what turns this into a value.
func evaluate(attribute_name: StringName) -> AttributeEvaluationResult:
	var result: AttributeEvaluationResult = AttributeEvaluationResult.new()

	var attribute_set: AttributeSet = find_set(attribute_name)
	if attribute_set == null:
		result.status = AttributeEvaluationResult.Status.ATTRIBUTE_NOT_FOUND
		return result

	var attribute: AttributeData = attribute_set.get(String(attribute_name))
	var composed: float = _compose(attribute.base_value, attribute_name, result)
	if not result.is_ok():
		return result

	result.raw_value = composed
	var clamped: float = attribute_set.pre_attribute_change(attribute_name, composed)
	if not is_finite(clamped):
		result.status = AttributeEvaluationResult.Status.NON_FINITE_VALUE
		return result

	result.final_value = clamped
	return result


## Apply the canonical order to one attribute. Writes failure into `result`.
func _compose(
	base: float, attribute_name: StringName, result: AttributeEvaluationResult
) -> float:
	var total_add: float = 0.0
	var product_multiply: float = 1.0
	var product_divide: float = 1.0
	var winner: AttributeModifierContribution = null

	for contribution: AttributeModifierContribution in _contributions:
		if contribution.attribute_name != attribute_name:
			continue
		match contribution.operation:
			GameplayEffectModifier.Operation.ADD:
				total_add += contribution.magnitude
			GameplayEffectModifier.Operation.MULTIPLY:
				product_multiply *= contribution.magnitude
			GameplayEffectModifier.Operation.DIVIDE:
				# A zero divisor is an invalid configuration, never a no-op.
				# Ignoring it silently is how a designer ships a stat that is
				# quietly wrong instead of loudly broken.
				if is_zero_approx(contribution.magnitude):
					result.status = AttributeEvaluationResult.Status.DIVISION_BY_ZERO
					return 0.0
				product_divide *= contribution.magnitude
			GameplayEffectModifier.Operation.OVERRIDE:
				if _override_beats(contribution, winner):
					winner = contribution
			_:
				result.status = AttributeEvaluationResult.Status.INVALID_OPERATION
				return 0.0

	var composed: float = ((base + total_add) * product_multiply) / product_divide

	if winner != null:
		composed = winner.magnitude
		result.winning_override_application_order = winner.application_order
		result.winning_override_modifier_index = winner.modifier_index

	if not is_finite(composed):
		result.status = AttributeEvaluationResult.Status.NON_FINITE_VALUE
		return 0.0

	return composed


## Last applied override wins: later application first, then higher modifier
## index within the same application. Both axes are compared, so two overrides
## from one effect are never resolved by array order.
func _override_beats(
	candidate: AttributeModifierContribution, incumbent: AttributeModifierContribution
) -> bool:
	if incumbent == null:
		return true
	if candidate.application_order != incumbent.application_order:
		return candidate.application_order > incumbent.application_order
	return candidate.modifier_index > incumbent.modifier_index
#endregion


#region Recomposition
## Recompute one attribute's current value and write it.
##
## Returns what happened. The caller emits from the result; this never emits,
## so a query and a notification can never interleave.

## The values a mutation started from, recorded before anything is written.
##
## Repeated verbatim in recompose() and commit_base_write(), which is three
## lines today and a field one of them forgets tomorrow.
func _snapshot(mutation: AttributeMutationResult, attribute: AttributeData) -> void:
	mutation.old_base_value = attribute.base_value
	mutation.new_base_value = attribute.base_value
	mutation.old_current_value = attribute.current_value
	mutation.new_current_value = attribute.current_value


func recompose(attribute_name: StringName) -> AttributeMutationResult:
	var mutation: AttributeMutationResult = AttributeMutationResult.new()
	mutation.attribute_name = attribute_name

	var attribute: AttributeData = find(attribute_name)
	if attribute == null:
		mutation.status = AttributeEvaluationResult.Status.ATTRIBUTE_NOT_FOUND
		return mutation

	_snapshot(mutation, attribute)

	var evaluation: AttributeEvaluationResult = evaluate(attribute_name)
	if not evaluation.is_ok():
		mutation.status = evaluation.status
		return mutation

	if is_equal_approx(evaluation.final_value, attribute.current_value):
		return mutation

	attribute.current_value = evaluation.final_value
	mutation.new_current_value = evaluation.final_value
	mutation.current_changed = true
	return mutation


## Recompose every attribute. Used after a base write or an effect change, since
## one attribute's clamp may depend on another's value.
func recompose_all() -> Array[AttributeMutationResult]:
	var results: Array[AttributeMutationResult] = []
	for attribute_name: StringName in all_attribute_names():
		var mutation: AttributeMutationResult = recompose(attribute_name)
		if mutation.current_changed or not mutation.is_ok():
			results.append(mutation)
	return results
#endregion


#region Bootstrap
## Deterministic attribute bootstrap.
##
## Lives here rather than on the ASC because attribute authority is this
## class: the facade should not be able to seed a value the aggregator did not
## sanction.
##
## A Resource authored with `base_value = 100` and a stale `current_value = 0`
## must come up at 100/100. The order matters: every base is validated and
## staged before any is written, so a set whose clamp reads a sibling sees a
## complete picture rather than a half-updated one.
##
## No `attribute_changed` is emitted here. This is bootstrap, not gameplay, and
## a UI connecting in `_ready` would otherwise receive a burst of changes for
## values that were never any different.
func initialize() -> void:
	var names: Array[StringName] = all_attribute_names()

	for name: StringName in names:
		var attribute: AttributeData = find(name)
		if not is_finite(attribute.base_value):
			push_error("GAS_Engine: attribute '" + String(name) + "' has a non-finite base value.")
			attribute.base_value = 0.0
		# Seed current so a dependent clamp can observe a complete set.
		attribute.current_value = attribute.base_value

	var staged: Array[AttributeBaseMutation] = []
	for name: StringName in names:
		var mutation: AttributeBaseMutation = stage_base_write(
			name, get_base_value(name)
		)
		if mutation != null:
			staged.append(mutation)

	for mutation: AttributeBaseMutation in staged:
		commit_base_write(mutation)

	for name: StringName in names:
		find(name).current_value = get_base_value(name)

	# Recompose against whatever contributions already exist, silently.
	recompose_all()
#endregion


#region Base mutation
## Stage a base write without applying it.
##
## Staging is what makes a multi-attribute effect atomic: the caller collects
## every mutation, and only commits when all of them are OK.
func stage_base_write(attribute_name: StringName, requested: float) -> AttributeBaseMutation:
	var attribute_set: AttributeSet = find_set(attribute_name)
	if attribute_set == null:
		return null
	return _stage_clamped(attribute_set, attribute_name, requested)


## The clamp core both stage_base_write and stage_gameplay_effect_base_write
## use, so pre_attribute_base_change runs identically for a plain write and
## an effect-driven one - only the execute-hook wrapping around it differs.
func _stage_clamped(
	attribute_set: AttributeSet, attribute_name: StringName, requested: float
) -> AttributeBaseMutation:
	var attribute: AttributeData = attribute_set.get(String(attribute_name))
	var staged: AttributeBaseMutation = AttributeBaseMutation.new()
	staged.attribute_name = attribute_name
	staged.old_base_value = attribute.base_value
	staged.requested_base_value = requested
	staged.committed_base_value = attribute_set.pre_attribute_base_change(attribute_name, requested)
	return staged


## Effect-aware base write: runs pre_gameplay_effect_execute before the same
## clamp core stage_base_write uses. Null means the pre hook rejected (or the
## attribute has no owning set) - either way nothing was staged, so the
## caller's evaluation fails atomically before any commit exists to undo.
func stage_gameplay_effect_base_write(data: GameplayEffectExecuteData) -> AttributeBaseMutation:
	var attribute_set: AttributeSet = find_set(data.attribute_name)
	if attribute_set == null:
		return null

	data.old_base = get_base_value(data.attribute_name)
	if not attribute_set.pre_gameplay_effect_execute(data):
		return null
	if not is_finite(data.proposed_base):
		return null

	var staged: AttributeBaseMutation = _stage_clamped(attribute_set, data.attribute_name, data.proposed_base)
	staged.execute_data = data
	data.committed_base = staged.committed_base_value
	return staged


## Write one staged base value. Returns what happened; recomposition is the
## caller's next step, because it must happen once after the whole batch rather
## than once per attribute.
func commit_base_write(staged: AttributeBaseMutation) -> AttributeMutationResult:
	var mutation: AttributeMutationResult = AttributeMutationResult.new()
	mutation.attribute_name = staged.attribute_name

	var attribute: AttributeData = find(staged.attribute_name)
	if attribute == null:
		mutation.status = AttributeEvaluationResult.Status.ATTRIBUTE_NOT_FOUND
		return mutation

	if not is_finite(staged.committed_base_value):
		mutation.status = AttributeEvaluationResult.Status.NON_FINITE_VALUE
		return mutation

	_snapshot(mutation, attribute)
	mutation.requested_base_value = staged.requested_base_value
	mutation.was_clamped = not is_equal_approx(
		staged.committed_base_value, staged.requested_base_value
	)

	if is_equal_approx(staged.committed_base_value, attribute.base_value):
		return mutation

	attribute.base_value = staged.committed_base_value
	mutation.new_base_value = staged.committed_base_value
	mutation.base_changed = true
	return mutation


## Notify the owning set that a current value moved. Separate from the write so
## the dependent-attribute hook runs after every value in a batch has settled.
func notify_current_changed(
	attribute_name: StringName, old_value: float, new_value: float
) -> void:
	var attribute_set: AttributeSet = find_set(attribute_name)
	if attribute_set == null:
		return
	attribute_set.post_attribute_change(owner_node, attribute_name, old_value, new_value)


## Fire post_gameplay_effect_execute for one already-committed effect-driven
## mutation. Never called for a mutation nothing actually committed - see
## GameplayEffectRuntime.notify_execute_hooks, the one caller.
func notify_gameplay_effect_execute(data: GameplayEffectExecuteData) -> void:
	var attribute_set: AttributeSet = find_set(data.attribute_name)
	if attribute_set == null:
		return
	attribute_set.post_gameplay_effect_execute(data)
#endregion
