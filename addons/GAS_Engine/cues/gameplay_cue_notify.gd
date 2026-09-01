## Base class for every visual and audio effect the ASC triggers.
##
## Attach this to the root of a scene holding particles or AudioStreamPlayers.
## The GameplayCueManager owns the lifecycle: this class only reports when it is
## done and never frees itself, because a pooled node that queue_free()s itself
## leaves the pool holding a freed reference.
##
## @meta_addon: GAS_Engine
## @meta_author: YulRun (https://YulRun.Dev), Arhalies fork
## @meta_license: MIT

@icon("res://addons/GAS_Engine/icons/gas_engine_asc.svg")
class_name GameplayCueNotify extends Node

const CueParams = preload("res://addons/GAS_Engine/cues/gameplay_cue_params.gd")

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
var current_params: CueParams = null

## Guards the auto-destroy timer so a cue re-taken from the pool before its
## previous timer fires cannot be finished twice.
var _playback_id: int = 0


#region One-shot lifecycle
## Called by the manager when this cue is pulled from the pool and parented
## for an EXECUTED_ON_APPLICATION/EXECUTED_ON_PERIODIC binding.
func execute_cue(params: CueParams) -> void:
	_begin_playback(params)
	executed(params)

	if not auto_destroy:
		return

	# There is no tree to take a timer from when this node sits outside one,
	# and `get_tree()` answers null rather than raising. The manager refuses a
	# detached target before it ever gets here, so reaching this means a caller
	# parented and played the cue itself; it says so rather than pooling on a
	# schedule it has no way to keep.
	var tree: SceneTree = get_tree()
	if tree == null:
		push_warning(
			"GAS_Engine: cue '" + String(gameplay_cue_tag)
			+ "' played outside the scene tree; it will not auto-destroy."
		)
		return

	var scheduled_id: int = _playback_id
	var timer: SceneTreeTimer = tree.create_timer(destroy_delay)
	timer.timeout.connect(_on_auto_destroy_elapsed.bind(scheduled_id))


## Only the playback that scheduled a timer may end it. Without this guard, a
## cue reused within `destroy_delay` would be pooled by its predecessor's timer
## while it is still playing - and a cue since handed to a PERSISTENT
## activation would be stolen out from under it the same way.
func _on_auto_destroy_elapsed(scheduled_id: int) -> void:
	if scheduled_id != _playback_id:
		return
	finish_cue()


## Call this from an inherited script when the effect is genuinely done, e.g.
## from an AudioStreamPlayer `finished` signal.
func finish_cue() -> void:
	current_params = null
	cue_finished.emit(self, gameplay_cue_tag)


## New F2.5 entry point. Defaults to the legacy virtual so a subclass that
## still only overrides `play_cue()` keeps working unchanged.
func executed(params: CueParams) -> void:
	play_cue(params)


## The F2 override point. Never call `executed()` from here: that would
## recurse for a subclass using the new API, and do nothing silently for one
## still using this one.
func play_cue(_params: CueParams) -> void:
	pass
#endregion


#region Persistent lifecycle
## Called by the manager once, when a non-instant active effect's PERSISTENT
## binding becomes uninhibited. Never schedules an auto-destroy timer - a
## persistent cue ends explicitly, through `end_persistent()`, not on a delay.
func begin_persistent(params: CueParams) -> void:
	_begin_playback(params)
	on_active(params)
	while_active(params)


## Called once, when the owning active effect is inhibited or removed.
## Reuses `finish_cue()` - the same signal the manager already pools a
## one-shot cue from - so persistent cues need no second pooling path.
func end_persistent(params: CueParams) -> void:
	on_removed(params)
	finish_cue()


## Override for a cue that starts a loop when it becomes active.
func on_active(_params: CueParams) -> void:
	pass


## Override for anything that should run once the cue is already looping.
func while_active(_params: CueParams) -> void:
	pass


## Override for a cue that needs to stop something `on_active`/`while_active`
## started, before the Node is pooled.
func on_removed(_params: CueParams) -> void:
	pass


## Shared by both lifecycles: marks a new playback so a stale timer or a
## reused instance from a prior one can never finish this one.
func _begin_playback(params: CueParams) -> void:
	current_params = params
	_playback_id += 1
#endregion
