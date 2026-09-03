## An ability that registers one task and waits on it, and the task it uses.
##
## The base task's handlers do nothing by design, so the only way to see that a
## dispatch arrived is to subclass and count. The same goes for the ability: a
## real channelled cast suspends inside `_activate_ability` on something it
## registered, and nothing else reproduces that shape.
##
## @meta_license: GAS_Engine Community Use License 1.0
class_name TaskProbeAbility extends GameplayAbility


## A task that records everything delivered to it and ends only when told.
class ProbeTask extends GameplayAbilityTask:
	var starts: int = 0
	var finishes: int = 0
	var deltas: Array[float] = []
	var presses: Array[int] = []
	var releases: Array[int] = []
	var events: Array[GameplayEventData] = []
	var targets: Array[GameplayAbilityTargetData] = []

	## Set to another task to cancel it from inside this one's `advance_time`,
	## which is how a test reaches the case of a task ending its neighbour
	## partway through a dispatch.
	var cancels_on_delta: GameplayAbilityTask = null

	func _on_start() -> void:
		starts += 1

	func _on_finish() -> void:
		finishes += 1

	func advance_time(delta: float) -> void:
		deltas.append(delta)
		if cancels_on_delta != null:
			cancels_on_delta.cancel(CancelReason.MANUAL)

	func handle_input_pressed(input_id: int) -> void:
		presses.append(input_id)

	func handle_input_released(input_id: int) -> void:
		releases.append(input_id)

	func handle_gameplay_event(event: GameplayEventData) -> void:
		events.append(event)

	func handle_target_data(data: GameplayAbilityTargetData) -> void:
		targets.append(data)


## The task this ability's last activation registered.
var last_task: ProbeTask = null

## How many times `_activate_ability` actually ran.
var activations: int = 0


static func build(tag: StringName) -> TaskProbeAbility:
	var probe: TaskProbeAbility = TaskProbeAbility.new()
	probe.name = String(tag).replace(".", "_")
	probe.ability_tags = [tag]
	return probe


## Register a task and suspend on it, the way a channelled cast does.
##
## Reporting success from the task's own state rather than from what `finished`
## carried is deliberate: a cancelled task must not be able to report success,
## and the state is the single place that already decided.
func _activate_ability() -> bool:
	activations += 1
	last_task = ProbeTask.new()
	last_task.owner_ability = self
	if owner_asc.register_ability_task(last_task) == null:
		return false
	await last_task.finished
	return last_task.state == GameplayAbilityTask.State.SUCCEEDED


## A task owned by this ability, registered without activating anything.
##
## Most of what the runtime promises - dispatch, removal, teardown - is about a
## registered task rather than about a running cast, and arranging a cast to
## reach it would test two things at once.
func register_loose_task() -> ProbeTask:
	var task: ProbeTask = ProbeTask.new()
	task.owner_ability = self
	owner_asc.register_ability_task(task)
	return task
