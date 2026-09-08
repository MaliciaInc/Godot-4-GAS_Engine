## Wait until whatever the ability is attached to is moving the way it was told.
##
## Read from the avatar rather than asked of the physics world: the body already
## knows its velocity, and a query would be a second opinion about a number
## nobody disagrees on. Read once per frame through the task runtime that already
## advances tasks, so nothing here polls on its own.
##
## `direction` is a hint, not a requirement. Zero means any direction and the
## magnitude alone decides, which is what "wait until I am moving" means; a real
## direction asks for movement along it, so a dash task can wait for the dash
## rather than for any motion at all.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name AbilityTaskWaitVelocityChange extends GameplayAbilityTask

## What it was moving at when the condition was met.
signal velocity_reached(velocity: Vector3)

## The direction that counts, or zero for any.
var direction: Vector3 = Vector3.ZERO

## How fast, along that direction or at all.
var min_magnitude: float = 0.0

var reached: Vector3 = Vector3.ZERO


static func create(
	ability: GameplayAbility,
	direction: Vector3 = Vector3.ZERO,
	min_magnitude: float = 0.0
) -> AbilityTaskWaitVelocityChange:
	var task: AbilityTaskWaitVelocityChange = AbilityTaskWaitVelocityChange.new()
	task.owner_ability = ability
	task.direction = direction
	task.min_magnitude = min_magnitude
	return task


func advance_time(_delta: float) -> void:
	if is_finished():
		return
	var moving: Vector3 = _velocity_of(_avatar())
	if not _counts(moving):
		return
	reached = moving
	velocity_reached.emit(moving)
	succeed()


## Whether this velocity satisfies what was asked for.
func _counts(moving: Vector3) -> bool:
	if direction.is_zero_approx():
		return moving.length() >= min_magnitude
	return moving.dot(direction.normalized()) >= min_magnitude


## The avatar's velocity, in three dimensions whichever it has.
##
## A 2D body's is a Vector2 and this answers in Vector3 for both, because a task
## that answered in whichever the body happened to be would make every caller
## branch on something the engine already knows.
static func _velocity_of(body: Node) -> Vector3:
	if body == null or not is_instance_valid(body):
		return Vector3.ZERO
	var two_d: CharacterBody2D = body as CharacterBody2D
	if two_d != null:
		return Vector3(two_d.velocity.x, two_d.velocity.y, 0.0)
	var three_d: CharacterBody3D = body as CharacterBody3D
	if three_d != null:
		return three_d.velocity
	# Anything else that says how fast it is going, which is what a game's own
	# mover looks like when it is not one of Godot's two bodies.
	if not body.has_method(&"get") or not (&"velocity" in body):
		return Vector3.ZERO
	var said: Variant = body.get(&"velocity")
	if said is Vector3:
		return said
	if said is Vector2:
		var flat: Vector2 = said
		return Vector3(flat.x, flat.y, 0.0)
	return Vector3.ZERO


func _avatar() -> Node:
	if owner_ability == null or owner_ability.owner_asc == null:
		return null
	return owner_ability.owner_asc.get_effect_target()
