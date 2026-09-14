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

## The same input said by the name of an InputMap action, for a grant bound
## that way. Empty waits on the slot alone.
var input_action: StringName = &""

var transition: AbilityTaskWaitInput.Transition = Transition.PRESSED


static func create(ability: GameplayAbility, slot: int, wanted: AbilityTaskWaitInput.Transition) -> AbilityTaskWaitInput:
	var task: AbilityTaskWaitInput = AbilityTaskWaitInput.new()
	task.owner_ability = ability
	task.input_id = slot
	task.transition = wanted
	return task


func handle_input_pressed(pressed_id: int) -> void:
	_answer(pressed_id == input_id, Transition.PRESSED)


func handle_input_released(released_id: int) -> void:
	_answer(released_id == input_id, Transition.RELEASED)


func handle_input_action_pressed(action: StringName) -> void:
	_answer(input_action != &"" and action == input_action, Transition.PRESSED)


func handle_input_action_released(action: StringName) -> void:
	_answer(input_action != &"" and action == input_action, Transition.RELEASED)


## The input and the direction both have to match, and nothing else does.
func _answer(is_this_input: bool, arrived: AbilityTaskWaitInput.Transition) -> void:
	if is_this_input and arrived == transition:
		succeed()
