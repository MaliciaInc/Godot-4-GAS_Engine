## Reads a grant's cooldown state fresh from the tags its cooldown effects
## grant - never an own clock, which would part company the first time one
## refreshed or expired early.
##
## Split out of AbilityRuntime the same way AbilityInstancingRuntime/
## AbilityTagSemanticsRuntime are - AbilityRuntime.get_cooldown_tags()/
## get_ability_cooldown_state() are thin wrappers there.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_license: MIT
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
	return state
