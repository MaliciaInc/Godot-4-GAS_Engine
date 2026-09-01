## What a commit will accept as a resolved cost and as a cooldown.
##
## These are properties of an effect, not of an ability, and they are the reason
## a commit can promise anything: a charge that can be previewed and reversed,
## and a cooldown that leaves nothing behind when it is retired. Keeping them
## here rather than on `GameplayAbility` also keeps them answerable without one
## - a tool validating a resource can ask the same questions the runtime asks.
##
## Every function is static and reads only its arguments. There is no state to
## get out of step with the ability that consults it.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT
class_name AbilityCommitContract extends RefCounted


#region Cost
## Whether `effect` is still a reversible charge. Null is legal: an ability may
## have no cost, or every declared cost may have resolved to nothing owed.
##
## `effect` is never author-supplied here. `GameplayAbility` no longer accepts
## a hand-authored cost effect at all - it declares a list of
## `GameplayAbilityCost` entries, and `GameplayAbilityCostResolver` is the only
## code that builds what this function checks. A violation here can therefore
## only mean the resolver itself is broken, which is exactly why the check
## stays: a broken resolver must fail loudly rather than commit a charge
## nothing could have previewed honestly.
static func is_reversible_charge(effect: GameplayEffect, level: float) -> bool:
	if effect == null:
		return true
	if effect.policy != GameplayEffect.DurationPolicy.INSTANT:
		return false
	# A resolved cost is built once, internally, by GameplayAbilityCostResolver
	# alone, and it never attaches a component - not TargetTags (an instant
	# effect grants no tags in any case), not anything else that would concede
	# state. A component here can only mean the resolver stopped being the
	# only thing that builds this effect.
	if not effect.components.is_empty():
		return false
	if not effect.is_silent():
		return false
	return _is_add_only_non_positive(effect, level)


## Every modifier subtracts or does nothing at all; none of them reads the
## value it changes; none of them can become dynamic again after resolving.
##
## Only ADD is allowed. MULTIPLY, DIVIDE and OVERRIDE each depend on the value
## they are charged against, so the amount previewed and the amount taken
## could differ, and the charge could not be undone by adding a fixed amount
## back. An empty modifier list is legal: a cost list that resolved to nothing
## owed on every attribute is a real, declared cost that happens to be free,
## not a missing one.
##
## A magnitude must be a bare GameplayScalableMagnitude, not an
## attribute-based, SetByCaller or custom one: `GameplayAbilityCostResolver`
## is the only code that ever builds this effect, and it always resolves a
## percentage once into a fixed value before this is asked. Anything else
## here can only mean the resolver stopped freezing what it resolves.
static func _is_add_only_non_positive(effect: GameplayEffect, level: float) -> bool:
	for modifier: GameplayEffectModifier in effect.modifiers:
		if modifier == null:
			return false
		if modifier.operation != GameplayEffectModifier.Operation.ADD:
			return false
		var scalable: GameplayScalableMagnitude = modifier.magnitude as GameplayScalableMagnitude
		if scalable == null or scalable.value == null:
			return false
		if scalable.value.evaluate(level) > 0.0:
			return false
	return true
#endregion


#region Cooldown
## Whether `effect` is a legal cooldown. Null is legal: an ability may have none.
##
## A cooldown is a tag that expires. It moves no attribute, because an attribute
## it had moved would be reverted by the same rollback that retires it.
static func is_legal_cooldown(effect: GameplayEffect) -> bool:
	if effect == null:
		return true
	if not effect.modifiers.is_empty():
		return false
	# The tag is the cooldown. Without one, nothing can be asked whether the
	# ability is still on cooldown, and the effect expires unobserved.
	if effect.get_granted_tags().is_empty():
		return false
	if not _cooldown_components_are_legal(effect):
		return false
	if not effect.is_silent():
		return false
	if effect.policy == GameplayEffect.DurationPolicy.DURATION:
		return effect.duration > 0.0
	if effect.policy == GameplayEffect.DurationPolicy.TURN_BASED:
		return effect.duration_turns > 0
	return false


## A cooldown may carry exactly the TargetTags it needs plus descriptive
## UIData - never Chance, Custom, RemoveOtherEffects, AdditionalEffects,
## GrantAbilities or Block/Cancel, none of which is_silent() alone would
## catch for something like AssetTags. A new component kind not yet named
## here is refused by default rather than silently allowed.
static func _cooldown_components_are_legal(effect: GameplayEffect) -> bool:
	for component: GameplayEffectComponent in effect.components:
		if component == null:
			continue
		if not (component is GameplayEffectTargetTagsComponent or component is GameplayEffectUIDataComponent):
			return false
	return true


## Every cooldown a commit must start, once each.
##
## The ability's own first, then the shared ones in declaration order. A Resource
## listed in both is one cooldown, not two: applying it twice would either
## refresh it - hiding the second application - or stack it, and neither is what
## sharing a cooldown means.
static func unique_cooldowns(
	own: GameplayEffect, shared: Array[GameplayEffect]
) -> Array[GameplayEffect]:
	var unique: Array[GameplayEffect] = []
	if own != null:
		unique.append(own)
	for effect: GameplayEffect in shared:
		if effect != null and not unique.has(effect):
			unique.append(effect)
	return unique
#endregion
