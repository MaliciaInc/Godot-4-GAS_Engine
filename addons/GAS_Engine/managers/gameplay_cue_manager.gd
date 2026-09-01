## Global autoload that spawns and pools visual/audio cues.
##
## Every type this file names comes from `preload`, never from a global
## `class_name`. Godot instantiates autoloads before the global class cache is
## available on a checkout that has never been imported by the editor, so
## `var cue: GameplayCueNotify` here fails to parse with "Could not find type"
## and takes the whole boot down with it. Upstream never sees this because its
## EditorPlugin registers the autoload from inside the editor, where the cache
## already exists. This addon has to work from a clean, cache-free checkout, so
## the dependency is removed rather than worked around at the call site.
##
## @meta_addon: GAS_Engine
## @meta_author: YulRun (https://YulRun.Dev), Arhalies fork
## @meta_license: MIT

@icon("res://addons/GAS_Engine/icons/gas_engine_asc.svg")
extends Node

const GASEngineProjectSettings = preload("res://addons/GAS_Engine/utilities/project_settings.gd")
const CueNotify = preload("res://addons/GAS_Engine/cues/gameplay_cue_notify.gd")
const CueRegistry = preload("res://addons/GAS_Engine/cues/gameplay_cue_registry.gd")
const CueEntry = preload("res://addons/GAS_Engine/cues/gameplay_cue_entry.gd")
const CueParams = preload("res://addons/GAS_Engine/cues/gameplay_cue_params.gd")
const CueHandle = preload("res://addons/GAS_Engine/cues/gameplay_cue_handle.gd")
const PoolBucket = preload("res://addons/GAS_Engine/cues/gameplay_cue_pool_bucket.gd")

## Where every caller outside this file's own closure finds this autoload -
## `get_node_or_null(AUTOLOAD_NODE_PATH)`, never the bare global identifier,
## since a caller that may run before the singleton exists (or, for the
## runtime debugger, one that must never assume a running game is even
## attached) needs a null it can check rather than a resolution error.
const AUTOLOAD_NODE_PATH: NodePath = ^"/root/GameplayCueManager"

## Dormant instances, one bucket per cue tag.
var _pool: Dictionary[StringName, PoolBucket] = {}

## Scenes to instantiate, one per cue tag.
var _cue_scenes: Dictionary[StringName, PackedScene] = {}

## Every persistent cue currently running, keyed by its handle's own id -
## the id, not the handle object, so a caller's copy of the handle still
## resolves.
var _active_persistent_by_id: Dictionary[int, CueNotify] = {}

var _next_persistent_id: int = 1


#region Initialization
func _ready() -> void:
	_load_registry()


## Load the cue registry from disk and prepare one empty bucket per tag.
func _load_registry() -> void:
	var cue_registry_path: String = GASEngineProjectSettings.get_registry_cue_path()
	if not ResourceLoader.exists(cue_registry_path):
		_warn_missing_registry(cue_registry_path)
		return

	var loaded: Resource = load(cue_registry_path)
	if not is_instance_of(loaded, CueRegistry):
		push_error("GAS_Engine: resource at " + cue_registry_path + " is not a GameplayCueRegistry.")
		return

	var registry: CueRegistry = loaded
	for entry: CueEntry in registry.entries:
		if entry == null or entry.tag == &"" or entry.scene == null:
			continue
		_cue_scenes[entry.tag] = entry.scene
		_pool[entry.tag] = PoolBucket.new()


## A missing registry is normal in a project that declares no cues, and noisy in
## one that meant to. Only the second case warrants a warning.
func _warn_missing_registry(cue_registry_path: String) -> void:
	if Engine.is_editor_hint() and not EditorInterface.is_plugin_enabled(GASEngineProjectSettings.ADDON_NAME):
		return
	push_warning("GAS_Engine: No cue registry found at " + cue_registry_path)
#endregion


#region Cue Execution
## Spawn a cue on its target. The ASC calls this with a typed parameter object;
## an arbitrary Dictionary payload would let the caller and the cue disagree
## about every key with nothing in between to notice.
func execute_cue(params: CueParams) -> void:
	var cue_instance: CueNotify = _resolve_and_parent(params)
	if cue_instance != null:
		cue_instance.execute_cue(params)


## Take/instantiate a cue, parent it, and run its PERSISTENT on_active/
## while_active. Returns an invalid handle for a missing registry entry -
## gameplay stays correct with no cue to show for it, per this task's own
## principle.
func activate_persistent_cue(params: CueParams) -> CueHandle:
	var handle: CueHandle = CueHandle.new()
	var cue_instance: CueNotify = _resolve_and_parent(params)
	if cue_instance == null:
		return handle
	handle.id = _next_persistent_id
	_next_persistent_id += 1
	_active_persistent_by_id[handle.id] = cue_instance
	cue_instance.begin_persistent(params)
	return handle


## Ends and pools a persistent cue by its handle. A handle that no longer
## resolves - already ended, or never valid - is a no-op, never an error:
## the same "gameplay stays correct without the cue" contract as a missing
## registry entry.
func deactivate_persistent_cue(handle: CueHandle, params: CueParams) -> void:
	if handle == null or not _active_persistent_by_id.has(handle.id):
		return
	var cue_instance: CueNotify = _active_persistent_by_id[handle.id]
	_active_persistent_by_id.erase(handle.id)
	if not is_instance_valid(cue_instance):
		return
	cue_instance.end_persistent(params)


## Resolve the registry entry, take or instantiate the instance, and (re)parent
## it under the target - the setup both one-shot and persistent activation share.
func _resolve_and_parent(params: CueParams) -> CueNotify:
	if (
		params == null
		or not is_instance_valid(params.target)
		or not _cue_scenes.has(params.cue_tag)
	):
		return null

	var cue_instance: CueNotify = _get_or_create_cue(params.cue_tag)
	if cue_instance == null:
		return null

	var previous_parent: Node = cue_instance.get_parent()
	if previous_parent != null:
		previous_parent.remove_child(cue_instance)
	params.target.add_child(cue_instance)
	return cue_instance
#endregion


#region Object Pooling
## Retrieve a dormant cue or instantiate a fresh one.
func _get_or_create_cue(tag: StringName) -> CueNotify:
	var bucket: PoolBucket = _bucket_for(tag)
	var pooled: CueNotify = bucket.take()
	if pooled != null:
		_set_cue_state(pooled, true)
		return pooled

	var scene: PackedScene = _cue_scenes[tag]
	var raw_instance: Node = scene.instantiate()
	if not is_instance_of(raw_instance, CueNotify):
		push_error(
			"GAS_Engine: Failed to load cue '" + String(tag)
			+ "'. The root node of this scene must extend 'GameplayCueNotify'."
		)
		raw_instance.free()
		return null

	var new_cue: CueNotify = raw_instance
	new_cue.gameplay_cue_tag = tag
	new_cue.cue_finished.connect(_on_cue_finished)
	_set_cue_state(new_cue, true)
	return new_cue


## The bucket for a tag, created on demand. Returning a bucket rather than a
## nullable one keeps every caller from re-deciding what an absent tag means.
func _bucket_for(tag: StringName) -> PoolBucket:
	if not _pool.has(tag):
		_pool[tag] = PoolBucket.new()
	return _pool[tag]


## Called when a cue reports itself finished.
func _on_cue_finished(cue_node: CueNotify, tag: StringName) -> void:
	var parent: Node = cue_node.get_parent()
	if parent != null:
		parent.remove_child(cue_node)

	_set_cue_state(cue_node, false)
	add_child(cue_node)
	_bucket_for(tag).give(cue_node)


## Centralised lifecycle state. Handles process mode and visual toggling for
## any node structure, because visibility propagates to the whole subtree.
func _set_cue_state(cue: CueNotify, active: bool) -> void:
	cue.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	for child: Node in cue.get_children():
		var visual: CanvasItem = child as CanvasItem
		if visual != null:
			visual.visible = active
			continue
		var spatial: Node3D = child as Node3D
		if spatial != null:
			spatial.visible = active


## How many dormant instances are pooled for a tag. Exists for tests and for the
## dashboard; nothing in the runtime branches on it.
func get_pooled_count(tag: StringName) -> int:
	return _bucket_for(tag).size()
#endregion
