## Let an animation move the character, and take that back when it ends.
##
## Root motion is the animation deciding where the body goes, and the thing that
## goes wrong is ownership: two abilities both driving the same body, or one
## that was cancelled still driving it. So it is claimed, and released on the way
## out - including when the ability was interrupted, which is exactly when
## nobody remembers to.
##
## Whether the motion is applied is the game's business: this offers what the
## animation produced and says when it stops. Reaching into a CharacterBody to
## move it would be this engine deciding how a game handles collision.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name AbilityTaskRootMotion extends GameplayAbilityTask

## What the motion came out of, and what it is driving.
var animation_tree: AnimationTree = null
var driven: Node3D = null

## How long to drive for, or zero for "until somebody stops it".
var duration: float = 0.0
var elapsed: float = 0.0

## What the last frame produced, for a game applying it itself.
var last_motion: Vector3 = Vector3.ZERO

## Whether this task is the one currently driving.
##
## Released in `_on_finish()` whichever way it ended, which is the whole reason
## this is a task: a cancelled ability that stayed the owner is a body nothing
## else can ever drive again.
var owns_motion: bool = false


static func create(
	ability: GameplayAbility, tree: AnimationTree, body: Node3D, seconds: float = 0.0
) -> AbilityTaskRootMotion:
	var task: AbilityTaskRootMotion = AbilityTaskRootMotion.new()
	task.owner_ability = ability
	task.animation_tree = tree
	task.driven = body
	task.duration = seconds
	return task


func _on_start() -> void:
	if animation_tree == null or driven == null:
		cancel(GameplayAbilityTask.CancelReason.ABILITY_ABORTED)
		return
	owns_motion = true


func advance_time(delta: float) -> void:
	if is_finished() or not owns_motion:
		return
	last_motion = animation_tree.get_root_motion_position()
	elapsed += delta
	if duration > 0.0 and elapsed >= duration:
		succeed()


func _on_finish() -> void:
	owns_motion = false
	last_motion = Vector3.ZERO
	animation_tree = null
	driven = null
