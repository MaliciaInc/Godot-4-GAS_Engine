## The attribute aggregator: lookup, base mutation and recomposition.
##
## This is the authority for the canonical formula and nothing else may implement it:
##
##     current = ((base + sum(ADD)) * product(MULTIPLY)) / product(DIVIDE)
##
## then the last applicable OVERRIDE, then `pre_attribute_change`. Base 10 with
## +10 and x2 is 40, not 30.
##
## Recomposition recomputes from scratch every time. Upstream applied a flat
## delta per modifier and reversed it on removal, which is order-dependent and
## unrecoverable: removing +20 while x1.5 and x2 are still active cannot be
## expressed as one delta. Recomputing has no such failure mode - there is no
## history to get wrong.
##
## This class emits nothing. It returns results and the ASC facade emits from
## them, so a caller cannot be surprised by a signal fired inside a query.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayAttributeRuntime extends RefCounted


## The node handed to `post_attribute_change`, normally the ASC.
var owner_node: Node = null

var _sets: Array[AttributeSet] = []

## Every contribution from every active effect, in no particular order. Ordering
## is expressed by the contribution's own two axes, not by array position, so an
## erase from the middle cannot change the result.
var _contributions: Array[AttributeModifierContribution] = []

## The same contributions, kept by the attribute they are about.
##
## Composing one attribute used to walk every contribution on the entity,
## skipping the ones about something else - measured at a thousand effects on
## one character, that is six seconds, because every attribute pays for every
## other attribute's modifiers.
##
## An index rather than a sort, because the order within one attribute is
## the application order the algebra reads and must not move. `_contributions`
## stays the ordered truth; this is a second way in to the same objects.
## The value type is a bare `Array` because GDScript will not nest typed
## collections. What is stored in it is always a typed one, made below and
## read back into a typed local - so the type survives even though the
## dictionary cannot declare it.
var _by_attribute: Dictionary[StringName, Array] = {}


#region Sets and lookup
## Take a set of authored attribute sets and make them this runtime's.
##
## `isolate` deep-copies them, so two runtimes handed the same authored resource
## do not share one pool of health - which looks like a working game until the
## whole party dies at once. It has no default value on purpose: the protective
## choice must not be the one a caller has to remember to ask for.
##
## Builds its own array and never writes into the caller's. Isolating in place
## did, and the array it rewrote belonged to the game: one array assigned to two
## components left the second holding the first's live, already-damaged copies,
## and left the game's own variable no longer holding what it authored. Nulls
## keep their positions - every reader here already skips them, and dropping
## them would silently renumber a caller's sets.
##
## Called again on every later assignment rather than once at wiring, because a
## game that builds its actors in code hands these over after the node exists.
## Taking them only once failed silently: this runtime kept the array it was
## wired with and the new sets were never read at all.
func set_attribute_sets(sets: Array[AttributeSet], isolate: bool) -> void:
	var taken: Array[AttributeSet] = []
	for authored: AttributeSet in sets:
		if isolate and authored != null:
			taken.append(authored.duplicate(true) as AttributeSet)
		else:
			taken.append(authored)
	_sets = taken
	initialize()


## Adopt one more set, leaving every set already here alone.
##
## Not set_attribute_sets() with one appended: that re-initialises the whole
## collection, and initialising seeds current from base on every attribute -
## so putting a kit on would wipe whatever a character's buffs had made of
## their health. Only what arrives is seeded.
##
## The instance adopted is returned rather than the one handed in, because an
## isolating component duplicates what it is given and a caller holding the
## original would be holding something this runtime has never seen.
func adopt_attribute_set(authored: AttributeSet, isolate: bool) -> AttributeSet:
	if authored == null:
		return null
	var taken: AttributeSet = (
		authored.duplicate(true) as AttributeSet if isolate else authored
	)
	_sets.append(taken)
	_seed_only(taken)
	return taken


## Let go of one set. False when this runtime is not holding it.
##
## Nothing else is touched, which is the contract: the attributes that stay
## keep the values they had, contributions and all.
func release_attribute_set(taken: AttributeSet) -> bool:
	if taken == null or not _sets.has(taken):
		return false
	_sets.erase(taken)
	return true


## Seed the attributes one set declares, and no others.
func _seed_only(taken: AttributeSet) -> void:
	for name: StringName in taken.get_attribute_names():
		var attribute: AttributeData = taken.attribute_named(name)
		if attribute == null:
			continue
		if not is_finite(attribute.base_value):
			push_error(
				"GAS_Engine: attribute '" + String(name) + "' has a non-finite base value."
			)
			attribute.base_value = 0.0
		attribute.current_value = attribute.base_value


## The set that declares an attribute, or null.
func find_set(attribute_name: StringName) -> AttributeSet:
	for attribute_set: AttributeSet in _sets:
		if attribute_set == null:
			continue
		if attribute_set.attribute_named(attribute_name) != null:
			return attribute_set
	return null


## Whether more than one set on this entity declares that attribute.
##
## The question a bare name cannot survive: two sets that both declare `health`
## make `health` mean two different values, and picking whichever was walked
## into first is an answer that changes with the order somebody listed them in.
func is_ambiguous(attribute_name: StringName) -> bool:
	return GameplayAttributeLookup.is_ambiguous(_sets, attribute_name)


## The first of these names this entity cannot uniquely address.
##
## Empty when every one of them means exactly one attribute, which is every
## entity carrying one set and most carrying two.
func first_ambiguous(names: Array[StringName]) -> StringName:
	for attribute_name: StringName in names:
		if is_ambiguous(attribute_name):
			return attribute_name
	return &""


## The set a reference names, or null when nothing answers to it.
func find_set_by_ref(reference: GameplayAttributeRef) -> AttributeSet:
	return GameplayAttributeLookup.set_for(_sets, reference)


## The attribute a reference names, or null.
func find_by_ref(reference: GameplayAttributeRef) -> AttributeData:
	return GameplayAttributeLookup.attribute_for(_sets, reference)


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


## Write a replicated reading of one attribute - base, current, or both - as
## one mutation, `current_value`'s own before and after taken across the
## whole write rather than around two independent public calls - R7-02. A
## base write through `set_attribute_base` used to recompose and could emit
## a value only this machine's own contributions produced, before an
## authoritative current then silently overwrote it. `commit_base_write`
## clamps the way `set_attribute_base` does, without the recompose it adds.
func apply_replicated_attribute(
	attribute_name: StringName, has_base: bool, new_base: float, has_current: bool, new_current: float
) -> AttributeMutationResult:
	var mutation: AttributeMutationResult = AttributeMutationResult.new()
	mutation.attribute_name = attribute_name

	var attribute: AttributeData = find(attribute_name)
	if attribute == null:
		mutation.status = AttributeEvaluationResult.Status.ATTRIBUTE_NOT_FOUND
		return mutation

	var old_current: float = attribute.current_value

	if has_base:
		var staged: AttributeBaseMutation = stage_base_write(attribute_name, new_base)
		if staged != null:
			var based: AttributeMutationResult = commit_base_write(staged)
			mutation.was_clamped = based.was_clamped

	if has_current:
		attribute.write_current_from_replication(new_current)
	elif has_base:
		# Base moved with no authoritative current alongside it - MIXED's own
		# shape for nothing but this machine's aggregator to answer.
		var evaluation: AttributeEvaluationResult = evaluate(attribute_name)
		if evaluation.is_ok():
			attribute.current_value = evaluation.final_value

	mutation.old_current_value = old_current
	mutation.new_current_value = attribute.current_value
	mutation.current_changed = not is_equal_approx(old_current, attribute.current_value)
	return mutation


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
			_bucket(contribution.attribute_name).append(contribution)


## Drop every contribution belonging to one application. Removal is by
## application order rather than by object identity so a caller cannot leave a
## stale contribution behind by holding a different array.
func remove_contributions_of(application_order: int) -> void:
	for index: int in range(_contributions.size() - 1, -1, -1):
		var leaving: AttributeModifierContribution = _contributions[index]
		if leaving.application_order == application_order:
			_contributions.remove_at(index)
			_bucket(leaving.attribute_name).erase(leaving)


func clear_contributions() -> void:
	_contributions.clear()
	_by_attribute.clear()


func contribution_count() -> int:
	return _contributions.size()


func contributions_for(attribute_name: StringName) -> Array[AttributeModifierContribution]:
	return _bucket(attribute_name).duplicate()


## The live list for one attribute, created empty the first time it is asked
## for. Private, because handing the stored array out is how a caller appends
## past the validation every contribution goes through on the way in.
func _bucket(attribute_name: StringName) -> Array[AttributeModifierContribution]:
	if not _by_attribute.has(attribute_name):
		var started: Array[AttributeModifierContribution] = []
		_by_attribute[attribute_name] = started
	var found: Array[AttributeModifierContribution] = _by_attribute[attribute_name]
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
## Composed from this attribute's own contributions rather than from every
## contribution on the entity. The algebra skips the ones about something
## else either way, so the answer is the same one - it is arrived at without
## walking a thousand modifiers about mana to work out a health value.
func _compose(
	base: float, attribute_name: StringName, result: AttributeEvaluationResult
) -> float:
	return _compose_from(base, attribute_name, result, _bucket(attribute_name))


## What this attribute would read if only the first channels had run.
##
## Only the UE profile has channels at all: the native one is a single pass,
## so every channel ceiling answers the whole composition there. That is the
## honest answer rather than a refusal - a project on the native profile
## asking this is asking what the attribute is, and that is what it gets.
func value_up_to_channel(attribute_name: StringName, through_channel: int) -> float:
	var attribute: AttributeData = find(attribute_name)
	if attribute == null:
		return 0.0
	var reading: AttributeEvaluationResult = AttributeEvaluationResult.new()
	return _compose_from(
		attribute.base_value,
		attribute_name,
		reading,
		_bucket(attribute_name),
		through_channel
	)


## How several contributions of one kind combine on this attribute, as the
## set that declares it says. ALL for an attribute nobody declares, which is
## what an empty aggregate composes to anyway.
func policy_for(attribute_name: StringName) -> AttributeSet.AggregatorPolicy:
	var declaring: AttributeSet = find_set(attribute_name)
	if declaring == null:
		return AttributeSet.AggregatorPolicy.ALL
	return declaring.aggregator_policy(attribute_name)


func _compose_from(
	base: float,
	attribute_name: StringName,
	result: AttributeEvaluationResult,
	contributions: Array[AttributeModifierContribution],
	through_channel: int = AttributeAggregateMath.CHANNELS - 1
) -> float:
	# Asked of the set that declares the attribute, and handed in: the
	# arithmetic knows nothing about sets, and an aggregate that went looking
	# for one would answer differently depending on who called it.
	var policy: AttributeSet.AggregatorPolicy = policy_for(attribute_name)
	var folded: AttributeAggregateMath.Composed = (
		AttributeAggregateMath.unreal(
			base, attribute_name, contributions, through_channel, policy
		)
		if _uses_unreal_algebra()
		else AttributeAggregateMath.godot_native(
			base, attribute_name, contributions, policy
		)
	)

	if not folded.is_ok():
		result.status = folded.status
		return 0.0

	result.winning_override_application_order = folded.winning_override_application_order
	result.winning_override_modifier_index = folded.winning_override_modifier_index
	return folded.value


## Which arithmetic this entity's attributes are composed by.
##
## Asked of the component rather than decided here, and asked every time rather
## than cached: the profile is data somebody can change, and an aggregate that
## remembered the answer would keep composing by the old rules until something
## else happened to invalidate it.
func _uses_unreal_algebra() -> bool:
	var component: AbilitySystemComponent = owner_node as AbilitySystemComponent
	return component != null and component.uses_ue_5_7_contracts()
## Pure aggregate preflight. It never publishes or temporarily installs the
## candidate contributions in the live runtime.
func validate_additional_contributions(
	additional: Array[AttributeModifierContribution]
) -> AttributeAggregateValidationResult:
	var validation: AttributeAggregateValidationResult = (
		AttributeAggregateValidationResult.new()
	)
	if additional.is_empty():
		return validation

	var combined: Array[AttributeModifierContribution] = _contributions.duplicate()
	combined.append_array(additional)

	var affected: Array[StringName] = []
	for contribution: AttributeModifierContribution in additional:
		if (
			contribution != null
			and contribution.attribute_name != &""
			and not affected.has(contribution.attribute_name)
		):
			affected.append(contribution.attribute_name)

	for attribute_name: StringName in affected:
		var attribute_set: AttributeSet = find_set(attribute_name)
		if attribute_set == null:
			validation.status = AttributeEvaluationResult.Status.ATTRIBUTE_NOT_FOUND
			validation.attribute_name = attribute_name
			return validation

		var attribute: AttributeData = attribute_set.get(String(attribute_name))
		var evaluated: AttributeEvaluationResult = AttributeEvaluationResult.new()
		var raw: float = _compose_from(
			attribute.base_value, attribute_name, evaluated, combined
		)
		if not evaluated.is_ok():
			validation.status = evaluated.status
			validation.attribute_name = attribute_name
			return validation

		var clamped: float = attribute_set.pre_attribute_change(attribute_name, raw)
		if not is_finite(clamped):
			validation.status = AttributeEvaluationResult.Status.NON_FINITE_VALUE
			validation.attribute_name = attribute_name
			return validation

	return validation


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
	_clear_meta(data.attribute_name)


## Return a meta attribute to zero, now that the set has read it.
##
## Here rather than in each execution, and after the hook rather than before:
## the hook is the one thing entitled to read the number, and an execution
## that cleared up after itself would be one place per calculation to forget
## to. An attribute that is not meta is left exactly as it was.
func _clear_meta(attribute_name: StringName) -> void:
	var attribute: AttributeData = find(attribute_name)
	if attribute == null or not attribute.is_meta:
		return
	attribute.base_value = 0.0
	attribute.current_value = 0.0
#endregion
