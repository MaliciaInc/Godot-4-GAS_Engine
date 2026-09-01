## Turns an ability's declared costs into one frozen, chargeable effect.
##
## This is the only place a percentage is computed. Everything after
## `resolve()` - affordability, charging, rollback - works against
## `resolved.absolute_effect` and never touches a `GameplayAbilityCost` again,
## which is what keeps the price frozen rather than recomputed mid-commit.
##
## Every function is static and reads only its arguments and the ASC it is
## given. It never mutates the ASC: resolving is a preview, the same way
## `can_afford_cost` is.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT
class_name GameplayAbilityCostResolver extends RefCounted


## Resolve `costs` against `asc` at `level`.
##
## Order: validate the ASC and level, resolve and validate each entry in
## declaration order, aggregate by target attribute, build the one effect that
## charges every target once, then preview whether `asc` can afford it.
static func resolve(
	costs: Array[GameplayAbilityCost], asc: AbilitySystemComponent, level: float
) -> GameplayResolvedCost:
	var resolved: GameplayResolvedCost = GameplayResolvedCost.new()
	if asc == null or not is_finite(level):
		resolved.status = GameplayResolvedCost.Status.INVALID_DEFINITION
		return resolved
	if costs.is_empty():
		# No costs declared is the same as F2's null cost_effect: the ability
		# is free, and there is nothing left to build or afford.
		return resolved

	# Summed per attribute so "Mana 30 absolute" and "Mana 50% current" become
	# one -70 modifier, not two separate charges an evaluator never sees
	# together.
	var totals: Dictionary[StringName, float] = {}
	var order: Array[StringName] = []

	for cost: GameplayAbilityCost in costs:
		var entry: GameplayResolvedCostEntry = _resolve_one(cost, asc, level, resolved)
		if entry == null:
			resolved.entries.clear()
			return resolved
		resolved.entries.append(entry)

		if not totals.has(entry.target_attribute):
			totals[entry.target_attribute] = 0.0
			order.append(entry.target_attribute)
		totals[entry.target_attribute] += entry.resolved_amount

	resolved.absolute_effect = _build_effect(totals, order)
	if not asc.can_afford_cost(resolved.absolute_effect, 1.0):
		resolved.status = GameplayResolvedCost.Status.INSUFFICIENT_RESOURCES
	return resolved


## One entry, or null with `resolved.status` already set to the refusal.
static func _resolve_one(
	cost: GameplayAbilityCost,
	asc: AbilitySystemComponent,
	level: float,
	resolved: GameplayResolvedCost
) -> GameplayResolvedCostEntry:
	if cost == null or cost.amount == null or String(cost.target_attribute).is_empty():
		resolved.status = GameplayResolvedCost.Status.INVALID_DEFINITION
		return null

	if cost.mode == GameplayAbilityCost.Mode.ABSOLUTE:
		if not String(cost.reference_attribute).is_empty():
			resolved.status = GameplayResolvedCost.Status.INVALID_DEFINITION
			return null
	elif String(cost.reference_attribute).is_empty():
		resolved.status = GameplayResolvedCost.Status.INVALID_DEFINITION
		return null

	if not asc.has_attribute(cost.target_attribute):
		resolved.status = GameplayResolvedCost.Status.TARGET_ATTRIBUTE_NOT_FOUND
		return null

	var entry: GameplayResolvedCostEntry = GameplayResolvedCostEntry.new()
	entry.target_attribute = cost.target_attribute
	entry.mode = cost.mode
	entry.reference_attribute = cost.reference_attribute
	entry.authored_value = cost.amount.evaluate(level)

	var amount: float = entry.authored_value
	if cost.mode != GameplayAbilityCost.Mode.ABSOLUTE:
		if not asc.has_attribute(cost.reference_attribute):
			resolved.status = GameplayResolvedCost.Status.REFERENCE_ATTRIBUTE_NOT_FOUND
			return null
		# The fraction itself, not yet multiplied by the reference value: a
		# 200% cost is illegal at any reference, so this is checked first.
		if not is_finite(amount) or amount < 0.0 or amount > 1.0:
			resolved.status = GameplayResolvedCost.Status.PERCENT_OUT_OF_RANGE
			return null
		entry.reference_value = (
			asc.get_attribute_base(cost.reference_attribute)
			if cost.mode == GameplayAbilityCost.Mode.PERCENT_OF_BASE
			else asc.get_attribute_current(cost.reference_attribute)
		)
		amount = entry.reference_value * amount

	if not is_finite(amount):
		resolved.status = GameplayResolvedCost.Status.NON_FINITE_VALUE
		return null

	entry.resolved_amount = maxf(amount, 0.0)
	return entry


## One INSTANT, silent effect with one negative ADD modifier per attribute
## that actually owes something, or null when nothing owes anything.
##
## An attribute whose aggregated total resolved to zero gets no modifier: a
## declared-but-free cost is not an unnecessary write. Nor is a whole list of
## them - this used to answer an effect carrying no modifiers at all, and the
## commit applied it, so the entire application pipeline ran for a charge of
## zero and `effect_received` fired over an effect that took nothing. Half of
## nothing is nothing, and a percentage cost against a resource already at zero
## is an ordinary moment in a fight, not an authoring mistake.
##
## Null is what an empty cost list already resolves to, so both ways of owing
## nothing now answer the same thing, and every caller already handles it:
## `can_afford_cost` and `is_reversible_charge` both accept null, and
## `commit_ability` only charges when there is something to charge.
##
## Each modifier's magnitude is a GameplayScalableMagnitude holding the
## percentage-or-absolute math already done - no curve, no capture, no
## SetByCaller - so nothing downstream can recompute a percentage mid-commit
## by resolving this magnitude a second time against state that has moved.
static func _build_effect(
	totals: Dictionary[StringName, float], order: Array[StringName]
) -> GameplayEffect:
	var modifiers: Array[GameplayEffectModifier] = []
	for attribute_name: StringName in order:
		var total: float = totals[attribute_name]
		if total <= 0.0:
			continue
		var modifier: GameplayEffectModifier = GameplayEffectModifier.new()
		modifier.attribute_name = attribute_name
		modifier.operation = GameplayEffectModifier.Operation.ADD
		var fixed_value: GameplayScalableFloat = GameplayScalableFloat.new()
		fixed_value.value = -total
		var scalable: GameplayScalableMagnitude = GameplayScalableMagnitude.new()
		scalable.value = fixed_value
		modifier.magnitude = scalable
		modifiers.append(modifier)

	if modifiers.is_empty():
		return null

	var effect: GameplayEffect = GameplayEffect.new()
	effect.policy = GameplayEffect.DurationPolicy.INSTANT
	effect.modifiers = modifiers
	return effect
