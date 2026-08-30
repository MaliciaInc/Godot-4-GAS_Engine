## Wait for someone to hand this ability its targets.
##
## The targeting itself happens elsewhere - a cursor, a trace, a confirmation
## button - and this is only the ability's side of the handover, so an ability
## can be written as one readable sequence instead of being cut in half around a
## callback.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_license: MIT
class_name AbilityTaskWaitTargetData extends GameplayAbilityTask

## What arrived. Null until it does.
var target_data: GameplayAbilityTargetData = null


static func create(ability: GameplayAbility) -> AbilityTaskWaitTargetData:
	var task: AbilityTaskWaitTargetData = AbilityTaskWaitTargetData.new()
	task.owner_ability = ability
	return task


## Only data addressed to this task's ability reaches here: the runtime filters
## by owner before delivering, so a second ability's targets can never answer a
## request this one made.
func handle_target_data(data: GameplayAbilityTargetData) -> void:
	if data == null:
		return
	target_data = data
	succeed()
