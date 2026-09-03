## Damage, paid for and delivered to whoever the player picked.
##
## The shortest complete ability there is: pay, ask where, apply, finish. Every
## other reference here is this with one more idea in it.
##
## Written by hand before it was ever opened in the Composer. That order is the
## point - if the Composer cannot read an ability a person wrote naturally, the
## subset it understands is wrong, not the file.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
extends GameplayAbility

## INSTANT. Applied once and gone; nothing to remove afterwards.
@export var damage: GameplayEffect


func _activate_ability() -> bool:
	if not commit_ability().is_ok():
		return false

	var pick: AbilityTaskWaitTargetData = wait_target_data()
	await pick.finished
	if pick.target_data == null:
		return false

	apply_effect_to_targets(damage, pick.target_data)
	end_ability()
	return true
