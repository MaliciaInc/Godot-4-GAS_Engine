## Move something to a place, and stop when the ability stops.
##
## A charge, a leap, a pull. What makes it a task rather than a tween is the
## cancel: an ability interrupted half way through a charge has to leave the
## character where it got to, not finish the movement it no longer owns.
##
## Moves by the clock the tasks already advance, so a paused game does not move
## anything and a test can step it by hand.
##
## One point, not two per dimension. A destination is kept as a Vector3 whether
## the thing being moved is flat or not, because a 2D point is that point with
## an unused z. A Vector2 field beside it would be a second spelling of one
## piece of state, and every method here would have to begin by asking which of
## the two had been filled in.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name AbilityTaskMoveTo extends GameplayAbilityTask

var moved: Node = null
var destination: Vector3 = Vector3.ZERO

## How long the whole move takes. Zero puts it there at once, which is a
## teleport and is a legitimate thing to ask for.
var duration: float = 0.0

var elapsed: float = 0.0
var started: Vector3 = Vector3.ZERO


static func to_2d(
	ability: GameplayAbility, node: Node2D, destination_point: Vector2, seconds: float
) -> AbilityTaskMoveTo:
	return _towards(ability, node, _lifted(destination_point), seconds)


static func to_3d(
	ability: GameplayAbility, node: Node3D, destination_point: Vector3, seconds: float
) -> AbilityTaskMoveTo:
	return _towards(ability, node, destination_point, seconds)


static func _towards(
	ability: GameplayAbility, node: Node, destination_point: Vector3, seconds: float
) -> AbilityTaskMoveTo:
	var task: AbilityTaskMoveTo = AbilityTaskMoveTo.new()
	task.owner_ability = ability
	task.moved = node
	task.destination = destination_point
	task.duration = seconds
	return task


static func _lifted(point: Vector2) -> Vector3:
	return Vector3(point.x, point.y, 0.0)


func _on_start() -> void:
	if moved == null or not is_instance_valid(moved):
		cancel(GameplayAbilityTask.CancelReason.ABILITY_ABORTED)
		return

	var spatial: Node3D = moved as Node3D
	if spatial != null:
		started = spatial.global_position
	var flat: Node2D = moved as Node2D
	if flat != null:
		started = _lifted(flat.global_position)
	if duration <= 0.0:
		_place(1.0)
		succeed()


func advance_time(delta: float) -> void:
	if is_finished() or duration <= 0.0:
		return
	elapsed += delta
	var through: float = clampf(elapsed / duration, 0.0, 1.0)
	_place(through)
	if through >= 1.0:
		succeed()


## Nothing to undo. What was moved stays where it got to, which is the whole
## point of cancelling a charge rather than rewinding one.
func _on_finish() -> void:
	moved = null


func _place(through: float) -> void:
	if moved == null or not is_instance_valid(moved):
		return
	var reached: Vector3 = started.lerp(destination, through)
	var spatial: Node3D = moved as Node3D
	if spatial != null:
		spatial.global_position = reached
		return
	var flat: Node2D = moved as Node2D
	if flat != null:
		flat.global_position = Vector2(reached.x, reached.y)
