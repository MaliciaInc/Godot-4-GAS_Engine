## An opponent that picks something it can actually do, at random.
##
## Deliberately shallow - it exists so a fight has an opponent, not so the
## opponent is clever. What matters is that it asks the engine what is legal
## rather than deciding for itself: an ability it cannot afford, one on
## cooldown, or one blocked by a tag it is carrying is refused by the component,
## and the AI simply does not see it as a choice.
##
## @meta_license: MIT
class_name CombatAI extends Node

## One decision: what to use, and on whom.
class Choice extends RefCounted:
	var handle: GameplayAbilityHandle = null
	var targets: Array[Battler] = []

	func is_valid() -> bool:
		return handle != null and handle.is_valid() and not targets.is_empty()


## Choose for `source`, or return an invalid choice if it can do nothing.
##
## No retry loop and no iteration cap. The old design guessed at random and gave
## up after a fixed number of misses, which meant a battler with exactly one
## legal action could still be told it had none. This enumerates what is legal
## and picks from that, so "nothing to do" means it, and one option is always
## found.
func choose(source: Battler, roster: BattlerRoster) -> Choice:
	var choice: Choice = Choice.new()
	if source == null or source.asc == null or source.is_downed():
		return choice

	var affordable: Array[GameplayAbilityHandle] = []
	for handle: GameplayAbilityHandle in source.granted:
		var spec: GameplayAbilitySpec = source.asc.ability_runtime.get_spec(handle)
		if spec == null:
			continue
		if source.asc.ability_runtime.can_activate(spec):
			affordable.append(handle)

	if affordable.is_empty():
		return choice

	choice.handle = affordable[randi() % affordable.size()]
	choice.targets = _pick_targets(source, roster, choice.handle)
	return choice


func _pick_targets(
	source: Battler, roster: BattlerRoster, handle: GameplayAbilityHandle
) -> Array[Battler]:
	var spec: GameplayAbilitySpec = source.asc.ability_runtime.get_spec(handle)
	var ability: BattlerAbility = spec.per_actor_instance as BattlerAbility if spec != null else null
	if ability == null:
		return []

	var candidates: Array[Battler] = []
	match ability.scope:
		BattlerAbility.Scope.SELF:
			return [source] as Array[Battler]
		_:
			if ability.targets_allies:
				candidates.append_array(roster.get_standing(
					roster.get_player_battlers() if source.is_player else roster.get_enemy_battlers()
				))
			if ability.targets_enemies:
				candidates.append_array(roster.get_standing(
					roster.get_enemy_battlers() if source.is_player else roster.get_player_battlers()
				))

	candidates = candidates.filter(func _targetable(b: Battler) -> bool: return b.is_targetable())
	if candidates.is_empty():
		return []
	if ability.scope == BattlerAbility.Scope.ALL:
		return candidates
	return [candidates[randi() % candidates.size()]] as Array[Battler]
