## A strike you have to be able to afford, and then wait to use again.
##
## Nothing here charges anything by hand. `costs` and `cooldown_effect` are
## authored on the ability, and `commit_ability()` is the one place the price is
## paid - all of it or none of it. An ability that spends first and starts its
## cooldown second can bill a player for nothing.
##
## The refusal is the interesting line. Returning false before anything has
## happened is how an ability declines without leaving a mark.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT
extends GameplayAbility

@export var damage: GameplayEffect


func _activate_ability() -> bool:
	var paid: AbilityCommitResult = commit_ability()
	if not paid.is_ok():
		return false

	var pick: AbilityTaskWaitTargetData = wait_target_data()
	await pick.finished
	if pick.target_data == null:
		abort_ability()
		return false

	apply_effect_to_targets(damage, pick.target_data)
	end_ability()
	return true
