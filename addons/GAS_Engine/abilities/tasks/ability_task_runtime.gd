## Every ability task currently running on one ASC, and the only thing that ends
## them.
##
## Tasks are owned here rather than by the abilities that create them. An
## ability that kept its own list would still be holding it while being freed,
## and the tasks would outlive the owner they report to. One registry means
## there is a single answer to "what is still running", which is also what makes
## `active_count() == 0` a checkable claim after teardown.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name AbilityTaskRuntime extends RefCounted

var owner_asc: AbilitySystemComponent = null

var _tasks: Array[GameplayAbilityTask] = []


#region Registry
## Take ownership of a task and start it. Returns the task, or null if refused.
##
## The order matters: the task is listed and connected *before* it is started,
## so a task that finishes immediately is still removed by its own callback. The
## reverse order would leave it in the list forever, because the finish would
## have happened before anyone was listening.
func register(task: GameplayAbilityTask) -> GameplayAbilityTask:
	if task == null:
		return null
	if task.owner_ability == null:
		push_error("GAS_Engine: an ability task must name the ability that owns it.")
		return null
	if task.owner_ability.owner_asc != owner_asc:
		push_error("GAS_Engine: an ability task cannot run on an ASC that does not own its ability.")
		return null

	_tasks.append(task)
	task.finished.connect(_on_task_finished)
	task.start()
	return task


func active_count() -> int:
	return _tasks.size()


## Every task currently running, as a copy - for the runtime debugger, the
## same reason active_effects()/specs() are copies elsewhere.
func active_tasks() -> Array[GameplayAbilityTask]:
	return _tasks.duplicate()


## Drop a finished task once, and stop listening to it.
func _on_task_finished(
	task: GameplayAbilityTask, _succeeded: bool, _reason: GameplayAbilityTask.CancelReason
) -> void:
	_tasks.erase(task)
	if task.finished.is_connected(_on_task_finished):
		task.finished.disconnect(_on_task_finished)
#endregion


#region Dispatch
## Hand one message to every task that can still receive it.
##
## Every delivery goes through here so the two rules that make dispatch safe are
## stated once. A snapshot, because a task that finishes mid-dispatch mutates
## `_tasks` and iterating the live array would skip its neighbour. A re-checked
## `is_finished`, because a task ended by an earlier neighbour in this same
## dispatch must not also be delivered to.
func _dispatch(deliver: Callable, only_for: GameplayAbility = null) -> void:
	for task: GameplayAbilityTask in _tasks.duplicate():
		if task.is_finished():
			continue
		if only_for != null and task.owner_ability != only_for:
			continue
		deliver.call(task)


func cancel_for_ability(
	ability: GameplayAbility, reason: GameplayAbilityTask.CancelReason
) -> void:
	_dispatch(func(task: GameplayAbilityTask) -> void: task.cancel(reason), ability)


func cancel_all(reason: GameplayAbilityTask.CancelReason) -> void:
	_dispatch(func(task: GameplayAbilityTask) -> void: task.cancel(reason))


func advance_time(delta: float) -> void:
	_dispatch(func(task: GameplayAbilityTask) -> void: task.advance_time(delta))


func input_pressed(input_id: int) -> void:
	_dispatch(func(task: GameplayAbilityTask) -> void: task.handle_input_pressed(input_id))


func input_released(input_id: int) -> void:
	_dispatch(func(task: GameplayAbilityTask) -> void: task.handle_input_released(input_id))


func gameplay_event(event: GameplayEventData) -> void:
	_dispatch(func(task: GameplayAbilityTask) -> void: task.handle_gameplay_event(event))


## Target data is addressed to one ability: a second ability waiting for targets
## must not be answered by a request it never made.
func target_data(ability: GameplayAbility, data: GameplayAbilityTargetData) -> void:
	_dispatch(func(task: GameplayAbilityTask) -> void: task.handle_target_data(data), ability)
#endregion
