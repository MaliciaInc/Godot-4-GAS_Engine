## Global autoload that spawns and pools visual/audio cues.
##
## Every type this file names comes from `preload`, never from a global
## `class_name`. Godot instantiates autoloads before the global class cache is
## available on a checkout that has never been imported by the editor, so
## `var cue: GameplayCueNotify` here fails to parse with "Could not find type"
## and takes the whole boot down with it. Upstream never sees this because its
## EditorPlugin registers the autoload from inside the editor, where the cache
## already exists. Step 1.8 requires a clean, cache-free checkout to work, so
## the dependency is removed rather than worked around at the call site.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_author: YulRun (https://YulRun.Dev), Arhalies fork
## @meta_license: MIT

@icon("res://addons/GodotGAS/icons/godot_gas_asc.svg")
extends Node


## Dormant instances, one bucket per cue tag.
var _pool: Dictionary[StringName, GameplayCuePoolBucket] = {}

## Scenes to instantiate, one per cue tag.
var _cue_scenes: Dictionary[StringName, PackedScene] = {}


#region Initialization
func _ready() -> void:
	_load_registry()


## Load the cue registry from disk and prepare one empty bucket per tag.
func _load_registry() -> void:
	var cue_registry_path: String = GodotGasProjectSettings.get_registry_cue_path()
	if not ResourceLoader.exists(cue_registry_path):
		_warn_missing_registry(cue_registry_path)
		return

	var loaded: Resource = load(cue_registry_path)
	if not is_instance_of(loaded, GameplayCueRegistry):
		push_error("GodotGAS: resource at " + cue_registry_path + " is not a GameplayCueRegistry.")
		return

	var registry: GameplayCueRegistry = loaded
	for entry: GameplayCueEntry in registry.entries:
		if entry == null or entry.tag == &"" or entry.scene == null:
			continue
		_cue_scenes[entry.tag] = entry.scene
		_pool[entry.tag] = GameplayCuePoolBucket.new()


## A missing registry is normal in a project that declares no cues, and noisy in
## one that meant to. Only the second case warrants a warning.
func _warn_missing_registry(cue_registry_path: String) -> void:
	if Engine.is_editor_hint() and not EditorInterface.is_plugin_enabled(GodotGasProjectSettings.ADDON_NAME):
		return
	push_warning("GodotGAS: No cue registry found at " + cue_registry_path)
#endregion


#region Cue Execution
## Spawn a cue on its target. The ASC calls this with a typed parameter object;
## an arbitrary Dictionary payload would let the caller and the cue disagree
## about every key with nothing in between to notice.
func execute_cue(params: GameplayCueParams) -> void:
	if params == null or params.target == null:
		return
	if not _cue_scenes.has(params.cue_tag):
		return

	var cue_instance: GameplayCueNotify = _get_or_create_cue(params.cue_tag)
	if cue_instance == null:
		return

	var previous_parent: Node = cue_instance.get_parent()
	if previous_parent != null:
		previous_parent.remove_child(cue_instance)

	params.target.add_child(cue_instance)
	cue_instance.execute_cue(params)
#endregion


#region Object Pooling
## Retrieve a dormant cue or instantiate a fresh one.
func _get_or_create_cue(tag: StringName) -> GameplayCueNotify:
	var bucket: GameplayCuePoolBucket = _bucket_for(tag)
	var pooled: GameplayCueNotify = bucket.take()
	if pooled != null:
		_set_cue_state(pooled, true)
		return pooled

	var scene: PackedScene = _cue_scenes[tag]
	var raw_instance: Node = scene.instantiate()
	if not is_instance_of(raw_instance, GameplayCueNotify):
		push_error(
			"GodotGAS: Failed to load cue '" + String(tag)
			+ "'. The root node of this scene must extend 'GameplayCueNotify'."
		)
		raw_instance.free()
		return null

	var new_cue: GameplayCueNotify = raw_instance
	new_cue.gameplay_cue_tag = tag
	new_cue.cue_finished.connect(_on_cue_finished)
	_set_cue_state(new_cue, true)
	return new_cue


## The bucket for a tag, created on demand. Returning a bucket rather than a
## nullable one keeps every caller from re-deciding what an absent tag means.
func _bucket_for(tag: StringName) -> GameplayCuePoolBucket:
	if not _pool.has(tag):
		_pool[tag] = GameplayCuePoolBucket.new()
	return _pool[tag]


## Called when a cue reports itself finished.
func _on_cue_finished(cue_node: GameplayCueNotify, tag: StringName) -> void:
	var parent: Node = cue_node.get_parent()
	if parent != null:
		parent.remove_child(cue_node)

	_set_cue_state(cue_node, false)
	add_child(cue_node)
	_bucket_for(tag).give(cue_node)


## Centralised lifecycle state. Handles process mode and visual toggling for
## any node structure, because visibility propagates to the whole subtree.
func _set_cue_state(cue: GameplayCueNotify, active: bool) -> void:
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
