## Commits, waits for a target, then applies its payload with a
## caller-supplied SetByCaller value - built as a real top-level ability
## script rather than a test-file inner class, because PackedScene.pack()
## does not reliably duplicate an anonymous inner GDScript subclass the way
## it does an ordinary class_name script, which every other packable ability
## fixture in this suite already is.
##
## Builds its own spec instead of going through apply_effect_to_targets():
## that convenience wrapper builds its spec internally with no hook for a
## caller-supplied SetByCaller value, and Fase 3's own RPG-cast scenario
## needs one.
##
## @meta_license: MIT
class_name FireballAbility extends GameplayAbility

var payload: GameplayEffect = null
var damage: float = 0.0
var confirmation_tag: StringName = &""
var reached_target: bool = false
var finished_successfully: bool = false


func _activate_ability() -> bool:
	if not commit_ability().is_ok():
		return false

	var wait: AbilityTaskWaitTargetData = wait_target_data()
	if wait == null:
		return false
	await wait.finished
	if wait.state != GameplayAbilityTask.State.SUCCEEDED:
		return false
	reached_target = true

	var avatar: Node = owner_asc.get_effect_target()
	var context: GameplayEffectContext = GameplayEffectContext.new(avatar, avatar)
	context.ability_handle = get_ability_handle()
	var spec: GameplayEffectSpec = GameplayEffectSpec.new(payload, context, get_ability_level())
	spec.set_set_by_caller(&"Damage", damage)
	for target: Node in wait.target_data.get_target_nodes():
		var target_asc: AbilitySystemComponent = find_asc_on(target)
		if target_asc != null:
			owner_asc.apply_effect_spec_to_target_result(spec, target_asc)

	var confirmation: AbilityTaskWaitGameplayEvent = wait_gameplay_event(confirmation_tag)
	if confirmation == null:
		return false
	await confirmation.finished
	if confirmation.state != GameplayAbilityTask.State.SUCCEEDED:
		return false

	finished_successfully = true
	return true
