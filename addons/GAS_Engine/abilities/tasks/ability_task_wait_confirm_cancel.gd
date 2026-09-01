## Wait for one of two input slots: a confirm, or a cancel. Never no UI of
## its own - the caller wires whichever prompt it wants to these two ids.
##
## Succeeds on either press: this task is not itself cancelled by a cancel
## input, it *succeeds knowing the caller chose CANCELLED* - the ability's
## own cancellation, if any, is still expressed through Task.CancelReason
## the ordinary way.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT
class_name AbilityTaskWaitConfirmCancel extends GameplayAbilityTask

enum Decision {
	CONFIRMED,
	CANCELLED,
}

var confirm_input_id: int = -1
var cancel_input_id: int = -1

var decision: AbilityTaskWaitConfirmCancel.Decision = Decision.CONFIRMED


static func create(
	ability: GameplayAbility, confirm_id: int, cancel_id: int
) -> AbilityTaskWaitConfirmCancel:
	var task: AbilityTaskWaitConfirmCancel = AbilityTaskWaitConfirmCancel.new()
	task.owner_ability = ability
	task.confirm_input_id = confirm_id
	task.cancel_input_id = cancel_id
	return task


func handle_input_pressed(input_id: int) -> void:
	if input_id == confirm_input_id:
		decision = Decision.CONFIRMED
		succeed()
	elif input_id == cancel_input_id:
		decision = Decision.CANCELLED
		succeed()
