## Wait for one of two input slots: a confirm, or a cancel. Never no UI of
## its own - the caller wires whichever prompt it wants to these two ids.
##
## Succeeds on either press: this task is not itself cancelled by a cancel
## input, it *succeeds knowing the caller chose CANCELLED* - the ability's
## own cancellation, if any, is still expressed through Task.CancelReason
## the ordinary way.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name AbilityTaskWaitConfirmCancel extends GameplayAbilityTask

enum Decision {
	CONFIRMED,
	CANCELLED,
}

var confirm_input_id: int = -1
var cancel_input_id: int = -1

var decision: AbilityTaskWaitConfirmCancel.Decision = Decision.CONFIRMED


static func create(
	ability: GameplayAbility, confirm_id: int = -1, cancel_id: int = -1
) -> AbilityTaskWaitConfirmCancel:
	var task: AbilityTaskWaitConfirmCancel = AbilityTaskWaitConfirmCancel.new()
	task.owner_ability = ability
	task.confirm_input_id = confirm_id
	task.cancel_input_id = cancel_id
	return task


func handle_input_pressed(input_id: int) -> void:
	if input_id == confirm_input_id:
		handle_confirm()
	elif input_id == cancel_input_id:
		handle_cancel()


## The generic yes.
##
## A task created without slots waits on this alone, which is the ordinary
## case: an ability that asks "confirm or cancel?" usually means whatever the
## game decided those are, not two particular keys. One created with slots
## still answers them, and answers this too - both are somebody saying yes.
func handle_confirm() -> void:
	decision = Decision.CONFIRMED
	succeed()


## And the generic no.
func handle_cancel() -> void:
	decision = Decision.CANCELLED
	succeed()
