## A read-only picture of one running ability task, for the runtime debugger.
##
## No terminated task is ever captured: AbilityTaskRuntime drops one the
## instant it finishes, and this never keeps a second copy alive just to
## show it afterward.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_license: MIT
class_name GasTaskSnapshot extends RefCounted

var ability_handle: GameplayAbilityHandle = null
var instance_id: int = 0
## The task's own script, e.g. AbilityTaskWaitTagAdded - read from the
## instance rather than duplicating a type enum the task classes would then
## have to keep in sync.
var task_type: Script = null
var state: GameplayAbilityTask.State = GameplayAbilityTask.State.CREATED
## See GameplayAbilityTask.debug_description().
var description: String = ""


static func capture_all(asc: AbilitySystemComponent) -> Array[GasTaskSnapshot]:
	var snapshots: Array[GasTaskSnapshot] = []
	if asc == null:
		return snapshots
	for task: GameplayAbilityTask in asc.ability_runtime.tasks.active_tasks():
		snapshots.append(_capture_one(task))
	return snapshots


static func _capture_one(task: GameplayAbilityTask) -> GasTaskSnapshot:
	var snapshot: GasTaskSnapshot = GasTaskSnapshot.new()
	if task.owner_ability != null:
		snapshot.ability_handle = task.owner_ability.get_ability_handle()
		snapshot.instance_id = task.owner_ability.get_instance_id()
	snapshot.task_type = task.get_script()
	snapshot.state = task.state
	snapshot.description = task.debug_description()
	return snapshot
