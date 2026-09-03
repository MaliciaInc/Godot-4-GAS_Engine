## Wait for one input slot to be pressed, or to be released.
##
## Both halves matter. "Hold to charge, release to fire" is two waits on the same
## slot in opposite directions, and a release task woken by the press that
## preceded it would fire the moment the player started charging.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name AbilityTaskWaitInput extends GameplayAbilityTask


## Which half of a keypress this task is waiting for.
enum Transition {
	PRESSED,
	RELEASED,
}

var input_id: int = -1
var transition: AbilityTaskWaitInput.Transition = Transition.PRESSED


static func create(ability: GameplayAbility, slot: int, wanted: AbilityTaskWaitInput.Transition) -> AbilityTaskWaitInput:
	var task: AbilityTaskWaitInput = AbilityTaskWaitInput.new()
	task.owner_ability = ability
	task.input_id = slot
	task.transition = wanted
	return task


func handle_input_pressed(pressed_id: int) -> void:
	_answer(pressed_id, Transition.PRESSED)


func handle_input_released(released_id: int) -> void:
	_answer(released_id, Transition.RELEASED)


## The slot and the direction both have to match, and nothing else does.
func _answer(slot: int, arrived: AbilityTaskWaitInput.Transition) -> void:
	if slot == input_id and arrived == transition:
		succeed()
