## Everything one commit is holding, and everything it would have to undo.
##
## The commit contract has always been all-or-nothing, and it stayed that way
## while a cost was one shape. With three - the resolved attribute charge, an
## authored cost effect, and however many custom costs a game wrote - the parts
## have to be held somewhere that knows their order, because undoing them in the
## wrong one is not undoing them.
##
## Prepared and committed are separate lists on purpose. A prepared cost that
## was never committed must not be rolled back: it did not take anything, and
## `rollback()` on it would be a game putting back something it never removed.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayAbilityCostTransaction extends RefCounted

## What was charged against attributes, as the effects that did it and the
## levels they did it at.
##
## Effects rather than the applications they produced, because a charge is
## instant: it moves the base value and vanishes, so there is no active effect
## left to remove. Putting it back means adding back exactly what it took, and
## `AbilityCommitContract.is_reversible_charge` is what guarantees that is
## possible - only ADD, only non-positive, nothing that reads the value it
## changes. An effect that could not be inverted never reaches this list.
var attribute_charges: Array[GameplayEffect] = []
var attribute_charge_levels: Array[float] = []

## Every custom cost that answered `prepare` with something, in declared order.
var prepared_custom_costs: Array[GameplayAbilityPreparedCustomCost] = []

## The subset of those whose `commit()` answered true, in the order they did.
var committed_custom_costs: Array[GameplayAbilityPreparedCustomCost] = []

## Cooldowns started by this commit, held here so a failure after them can take
## them off again.
var applied_cooldowns: Array[ActiveGameplayEffect] = []


## Remember a prepared cost. Called before anything has been taken.
func prepared(cost: GameplayAbilityPreparedCustomCost) -> void:
	if cost != null:
		prepared_custom_costs.append(cost)


## Take every prepared custom cost, in declared order.
##
## Stops at the first refusal and leaves the rest unpaid, which is what makes
## `undo()` able to put things back: everything it has to reverse is in
## `committed_custom_costs`, and nothing else was touched.
func commit_custom_costs() -> bool:
	for cost: GameplayAbilityPreparedCustomCost in prepared_custom_costs:
		if not cost.commit():
			return false
		cost.committed = true
		committed_custom_costs.append(cost)
	return true


## Put back everything this transaction took, newest first.
##
## Reverse order because costs can depend on each other - a cost that consumed
## the item another one charged a durability on has to be restored before the
## durability is, or the second restores something that is not there yet.
##
## The attribute charge and the cost effect go last, for the same reason they
## were taken first.
func undo(asc: AbilitySystemComponent) -> void:
	for index: int in range(committed_custom_costs.size() - 1, -1, -1):
		committed_custom_costs[index].rollback()
		committed_custom_costs[index].committed = false
	committed_custom_costs.clear()

	for index: int in range(attribute_charges.size() - 1, -1, -1):
		var giving_back: GameplayEffect = _inverse_of(
			attribute_charges[index], attribute_charge_levels[index]
		)
		if giving_back != null:
			asc.apply_gameplay_effect(giving_back, asc, attribute_charge_levels[index])
	attribute_charges.clear()
	attribute_charge_levels.clear()

	for started: ActiveGameplayEffect in applied_cooldowns:
		asc.remove_active_effect(started)
	applied_cooldowns.clear()


## Remember a charge, so it can be given back.
func charged(effect: GameplayEffect, level: float) -> void:
	if effect != null:
		attribute_charges.append(effect)
		attribute_charge_levels.append(level)


## The same charge with every amount negated.
##
## Built rather than stored because the charge is data an author or the resolver
## owns, and mutating it to undo it would change what the ability costs next
## time. Only ADD is here to negate: the commit contract refuses anything that
## reads the value it changes, precisely so this is exact rather than close.
static func _inverse_of(effect: GameplayEffect, _level: float) -> GameplayEffect:
	var giving_back: GameplayEffect = GameplayEffect.new()
	giving_back.policy = GameplayEffect.DurationPolicy.INSTANT
	var undoing: Array[GameplayEffectModifier] = []
	for modifier: GameplayEffectModifier in effect.modifiers:
		if modifier == null or modifier.operation != GameplayEffectModifier.Operation.ADD:
			continue
		var back: GameplayEffectModifier = GameplayEffectModifier.new()
		back.attribute = modifier.attribute
		back.attribute_name = modifier.attribute_name
		back.operation = GameplayEffectModifier.Operation.ADD
		back.evaluation_channel = modifier.evaluation_channel
		var amount: GameplayScalableFloat = GameplayScalableFloat.new()
		amount.value = -_amount_of(modifier)
		var magnitude: GameplayScalableMagnitude = GameplayScalableMagnitude.new()
		magnitude.value = amount
		back.magnitude = magnitude
		undoing.append(back)
	giving_back.modifiers = undoing
	return giving_back


## What one modifier of a resolved charge is worth. Scalable and bare by
## contract - anything else is refused before it can be charged.
static func _amount_of(modifier: GameplayEffectModifier) -> float:
	var scalable: GameplayScalableMagnitude = modifier.magnitude as GameplayScalableMagnitude
	if scalable == null or scalable.value == null:
		return 0.0
	return scalable.value.value
