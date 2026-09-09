## Wait until something the game itself decides becomes true.
##
## The escape hatch, and it is a task rather than a loop for one reason: a loop
## in an ability body is a loop nothing can cancel, so an ability waiting on a
## condition that never comes true waits for ever holding everything it took.
## This is asked once per frame by the runtime that already advances tasks, and
## it is cancelled with the ability like anything else.
##
## The condition is a Callable answering a bool. Anything else the engine could
## have offered - a query language, a node path, an expression - would be a
## second way to say what GDScript already says.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name AbilityTaskWaitState extends GameplayAbilityTask

var condition: Callable = Callable()

## How long to wait before giving up, or zero for "as long as it takes".
##
## A timeout is not a nicety here: a condition that is never going to be true is
## indistinguishable from one that has not happened yet, and only the ability
## knows which of those it can live with.
var timeout: float = 0.0

## How long it has been waiting, and whether it gave up.
var waited: float = 0.0
var timed_out: bool = false


static func create(
	ability: GameplayAbility, until: Callable, give_up_after: float = 0.0
) -> AbilityTaskWaitState:
	var task: AbilityTaskWaitState = AbilityTaskWaitState.new()
	task.owner_ability = ability
	task.condition = until
	task.timeout = give_up_after
	return task


## Asked at the start as well: a condition already true is one this should not
## wait a frame for.
func _on_start() -> void:
	_ask()


func advance_time(delta: float) -> void:
	if is_finished():
		return
	waited += delta
	if _ask():
		return
	if timeout > 0.0 and waited >= timeout:
		timed_out = true
		cancel(GameplayAbilityTask.CancelReason.ABILITY_ENDED)


## Whether the condition answered true, having been asked.
##
## A condition that is not callable answers nothing rather than throwing: an
## ability handed a stale Callable would otherwise take the frame down with it.
func _ask() -> bool:
	if not condition.is_valid():
		return false
	var answered: bool = condition.call()
	if answered:
		succeed()
	return answered
