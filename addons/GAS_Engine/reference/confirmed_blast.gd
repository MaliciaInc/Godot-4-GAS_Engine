## Aim, then confirm, then fire.
##
## Two waits in a row, which is the shape every placed-on-the-ground spell has.
## The ability is alive and holding the whole time, so anything that cancels it
## between the two waits has to leave nothing behind - which is why the cost is
## committed after the confirmation and not before it.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
extends GameplayAbility

@export var blast: GameplayEffect


func _activate_ability() -> bool:
	var pick: AbilityTaskWaitTargetData = wait_target_data()
	await pick.finished
	if pick.target_data == null:
		return false

	var confirm: AbilityTaskWaitInput = wait_input_pressed()
	await confirm.finished
	if confirm.state != GameplayAbilityTask.State.SUCCEEDED:
		return false

	if not commit_ability().is_ok():
		return false

	apply_effect_to_targets(blast, pick.target_data)
	end_ability()
	return true
