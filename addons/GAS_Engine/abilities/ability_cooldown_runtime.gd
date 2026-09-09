## Reads a grant's cooldown state fresh from the tags its cooldown effects
## grant - never an own clock, which would part company the first time one
## refreshed or expired early.
##
## Split out of AbilityRuntime the same way AbilityInstancingRuntime/
## AbilityTagSemanticsRuntime are - AbilityRuntime.get_cooldown_tags()/
## get_ability_cooldown_state() are thin wrappers there.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name AbilityCooldownRuntime extends RefCounted

var ability_runtime: AbilityRuntime = null


## The definition's own tag, its shared cooldowns', and any declared
## explicitly - the one place this is computed, so the gate and a reading
## never disagree.
static func get_cooldown_tags(spec: GameplayAbilitySpec) -> Array[StringName]:
	var cooldown_tags: Array[StringName] = []
	if spec == null or spec.definition == null:
		return cooldown_tags
	if spec.definition.cooldown_effect != null:
		cooldown_tags.append_array(spec.definition.cooldown_effect.get_granted_tags())
	for effect: GameplayEffect in spec.definition.shared_cooldown_effects:
		if effect != null:
			cooldown_tags.append_array(effect.get_granted_tags())
	cooldown_tags.append_array(spec.definition.shared_cooldown_tags)
	return cooldown_tags


## Whether this grant's cooldown is standing in the way right now.
##
## The one gate. The activation preflight and the commit preflight both ask it,
## so they can never disagree about whether an ability is waiting - and it is
## the one place a debug build stops asking, which is what `gas.ignore_cooldowns`
## turns off. Nothing is cleared and no tag is touched: the moment the switch
## goes off again, the entity is waiting exactly as long as it was going to.
static func gates(spec: GameplayAbilitySpec, held: GameplayTagRuntime) -> bool:
	if GasDebugOptions.cooldowns_ignored():
		return false
	return held != null and held.has_any(get_cooldown_tags(spec))


## Everything a UI needs to draw one grant's cooldown.
func get_ability_cooldown_state(handle: GameplayAbilityHandle) -> AbilityCooldownState:
	var state: AbilityCooldownState = AbilityCooldownState.new()
	var spec: GameplayAbilitySpec = ability_runtime.get_spec(handle)
	if spec == null or ability_runtime.owner_asc == null:
		return state

	for tag: StringName in get_cooldown_tags(spec):
		# A tag shared between two of its cooldowns is one wait, not two.
		if state.tags.has(tag):
			continue
		state.tags.append(tag)

		var seconds: float = ability_runtime.owner_asc.get_tag_duration_remaining(tag)
		if is_inf(seconds):
			state.infinite = true
		elif seconds > state.seconds_remaining:
			state.seconds_remaining = seconds

		var turns: int = ability_runtime.owner_asc.get_tag_turns_remaining(tag)
		if turns > state.turns_remaining:
			state.turns_remaining = turns

		if ability_runtime.owner_asc.has_tag(tag):
			state.active = true

	if state.infinite or state.seconds_remaining > 0.0 or state.turns_remaining > 0:
		state.active = true
	_read_authorised_duration(spec, state)
	return state


## What the running cooldown was authorised for, from the application itself.
##
## The spec of the active effect rather than the authored number on the
## definition: a duration written as a magnitude of the ability's level is
## only a number once it has been applied, and the authored field would report
## whatever fallback it happened to carry.
func _read_authorised_duration(
	spec: GameplayAbilitySpec, state: AbilityCooldownState
) -> void:
	var declared: Array[GameplayEffect] = AbilityCommitContract.unique_cooldowns(
		spec.definition.cooldown_effect, spec.definition.shared_cooldown_effects
	)
	for effect: GameplayEffect in declared:
		var asking: GameplayEffectQuery = GameplayEffectQuery.new()
		asking.effect_definition = effect
		for active: ActiveGameplayEffect in ability_runtime.owner_asc.find_active_effects(asking):
			state.duration = maxf(state.duration, active.spec.duration)
			# Turns are authorised on the definition and counted down on the
			# spec, so the definition is the one that still knows the whole.
			state.turns = maxi(state.turns, effect.duration_turns)
