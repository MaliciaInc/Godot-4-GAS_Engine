## A named stretch of an ability, that something else can end by name.
##
## The thing `wait_state` is not. That one waits for a condition to become true;
## this one *is* the condition - the ability declares "I am winding up now", and
## whatever ends the wind-up says so by name rather than by holding the task.
##
## The name identifies this task and nothing else. Two states with different
## names run at once quite happily, and two abilities can both be in a state
## called the same thing without either hearing about the other: a name that
## meant one global thing would be a singleton with extra steps.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name AbilityTaskAbilityState extends GameplayAbilityTask

## The state finished, and whether it was ended or called off.
signal state_ended(state_name: StringName, was_cancelled: bool)

var state_name: StringName = &""


static func create(ability: GameplayAbility, state_name: StringName) -> AbilityTaskAbilityState:
	var task: AbilityTaskAbilityState = AbilityTaskAbilityState.new()
	task.owner_ability = ability
	task.state_name = state_name
	task.instance_name = state_name
	return task


func _on_finish() -> void:
	state_ended.emit(state_name, state == State.CANCELLED)
