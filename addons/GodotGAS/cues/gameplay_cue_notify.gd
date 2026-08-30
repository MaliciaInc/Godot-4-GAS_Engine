## Base class for every visual and audio effect the ASC triggers.
##
## Attach this to the root of a scene holding particles or AudioStreamPlayers.
## The GameplayCueManager owns the lifecycle: this class only reports when it is
## done and never frees itself, because a pooled node that queue_free()s itself
## leaves the pool holding a freed reference.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_author: YulRun (https://YulRun.Dev), Arhalies fork
## @meta_license: MIT

@icon("res://addons/GodotGAS/icons/godot_gas_asc.svg")
class_name GameplayCueNotify extends Node


## Emitted when the effect is complete so the manager can pool it again.
signal cue_finished(cue_node: GameplayCueNotify, tag: StringName)

@export_category("Lifecycle")
## Whether this node pools itself after playing. False for looping effects such
## as a persistent aura, which are ended explicitly instead.
@export var auto_destroy: bool = true

## How long to wait before pooling. Set slightly longer than the longest
## particle or audio duration in the scene.
@export_range(0.0, 600.0, 0.05, "or_greater") var destroy_delay: float = 2.0

## The cue tag this instance was spawned for, assigned by the manager.
var gameplay_cue_tag: StringName = &""

## The parameters of the current playback. Null between playbacks.
var current_params: GameplayCueParams = null

## Guards the auto-destroy timer so a cue re-taken from the pool before its
## previous timer fires cannot be finished twice.
var _playback_id: int = 0


#region Execution Lifecycle
## Called by the manager when this cue is pulled from the pool and parented.
func execute_cue(params: GameplayCueParams) -> void:
	current_params = params
	_playback_id += 1
	play_cue(params)

	if not auto_destroy:
		return

	var scheduled_id: int = _playback_id
	var timer: SceneTreeTimer = get_tree().create_timer(destroy_delay)
	timer.timeout.connect(_on_auto_destroy_elapsed.bind(scheduled_id))


## Only the playback that scheduled a timer may end it. Without this guard, a
## cue reused within `destroy_delay` would be pooled by its predecessor's timer
## while it is still playing.
func _on_auto_destroy_elapsed(scheduled_id: int) -> void:
	if scheduled_id != _playback_id:
		return
	finish_cue()


## Call this from an inherited script when the effect is genuinely done, e.g.
## from an AudioStreamPlayer `finished` signal.
func finish_cue() -> void:
	current_params = null
	cue_finished.emit(self, gameplay_cue_tag)


## Override this in a specific cue script. The default does nothing, so a cue
## that forgets to override still pools correctly instead of hanging forever.
func play_cue(_params: GameplayCueParams) -> void:
	pass
#endregion
