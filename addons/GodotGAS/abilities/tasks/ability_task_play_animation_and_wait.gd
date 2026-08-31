## Play one animation on a caller-supplied AnimationPlayer and wait for it to
## finish - Godot-native, never a reimplementation of AnimMontage's
## section/blend machinery this addon has no use for.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_license: MIT
class_name AbilityTaskPlayAnimationAndWait extends GameplayAbilityTask

var player: AnimationPlayer = null
var animation: StringName = &""

## A shared AnimationPlayer - one an idle/locomotion tree might also drive -
## is not stopped by default when this task cancels; the caller asks for
## that explicitly if this animation exclusively owns the player.
var stop_on_cancel: bool = false


static func create(
	ability: GameplayAbility,
	animation_player: AnimationPlayer,
	animation_name: StringName,
	stop_when_cancelled: bool = false
) -> AbilityTaskPlayAnimationAndWait:
	var task: AbilityTaskPlayAnimationAndWait = AbilityTaskPlayAnimationAndWait.new()
	task.owner_ability = ability
	task.player = animation_player
	task.animation = animation_name
	task.stop_on_cancel = stop_when_cancelled
	return task


func _on_start() -> void:
	if player == null or not player.has_animation(animation):
		cancel(GameplayAbilityTask.CancelReason.MANUAL)
		return
	player.animation_finished.connect(_on_animation_finished)
	player.play(animation)


func _on_finish() -> void:
	if player == null:
		return
	if player.animation_finished.is_connected(_on_animation_finished):
		player.animation_finished.disconnect(_on_animation_finished)
	if stop_on_cancel and state == GameplayAbilityTask.State.CANCELLED:
		player.stop()


func _on_animation_finished(finished_animation: StringName) -> void:
	if finished_animation != animation:
		return
	succeed()
