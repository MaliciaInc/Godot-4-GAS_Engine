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
## @meta_author: MaliciaInc
## @meta_license: GAS_Engine Community Use License 1.0

@icon("res://addons/GAS_Engine/icons/gas_engine_asc.svg")
extends Node

const GASEngineProjectSettings = preload("res://addons/GAS_Engine/utilities/project_settings.gd")
const CueNotify = preload("res://addons/GAS_Engine/cues/gameplay_cue_notify.gd")
const CueRegistry = preload("res://addons/GAS_Engine/cues/gameplay_cue_registry.gd")
const CueGenerator = preload("res://addons/GAS_Engine/cues/gameplay_cue_generator.gd")

const SCENE_MISSING: String = "GAS_Engine: cue %s names a scene that will not load: %s"
const CueEntry = preload("res://addons/GAS_Engine/cues/gameplay_cue_entry.gd")
const CueParams = preload("res://addons/GAS_Engine/cues/gameplay_cue_params.gd")
const CueHandle = preload("res://addons/GAS_Engine/cues/gameplay_cue_handle.gd")
const CueHandler = preload("res://addons/GAS_Engine/cues/gameplay_cue_handler.gd")
const PoolBucket = preload("res://addons/GAS_Engine/cues/gameplay_cue_pool_bucket.gd")

## What a tag family is, borrowed from the one place that already knows.
##
## The family and not the whole tag store: this file is an autoload, so
## everything it reaches is bound by the preload rule, and that is a
## reasonable thing to ask of ten lines about tag names and not of the
## reference-counted store the whole engine writes through.
const TagFamily = preload("res://addons/GAS_Engine/gameplay_tag/gameplay_tag_family.gd")

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

## The tags that end a fallback walk, from the same file as the bindings.
##
## A set rather than a list: this is asked once per level of every cue
## resolution, and the answer is only ever yes or no.
var _override_parent: Dictionary[StringName, bool] = {}

## Tags answered by a script rather than a scene.
##
## One handler answers for every entity that plays its tag: it is stateless
## by contract, so there is nothing to pool and nothing to parent.
var _handlers: Dictionary[StringName, CueHandler] = {}

## Persistent playbacks currently running on a handler, by the same handle
## ids the scene-backed ones use. A handle resolves in exactly one of the
## two maps, because a tag is answered by exactly one kind of binding.
var _active_handler_by_id: Dictionary[int, CueHandler] = {}

## What each running handler playback was told, so `while_active` can be
## given the same params `on_active` was.
var _handler_params_by_id: Dictionary[int, CueParams] = {}

## Every persistent cue currently running, keyed by its handle's own id -
## the id, not the handle object, so a caller's copy of the handle still
## resolves.
var _active_persistent_by_id: Dictionary[int, CueNotify] = {}

var _next_persistent_id: int = 1


#region Initialization
func _ready() -> void:
	_load_registry()
	# Nothing to tick until a handler-backed persistent cue is running, and
	# a manager that processed every frame regardless would be a per-frame
	# cost every project pays for a feature most of them do not use.
	set_process(false)


## Tell every running handler playback that it is still running.
##
## The scriptless counterpart of GameplayCueNotify's own while_active: a
## RefCounted has no frame of its own, so the manager gives it one. Over a
## snapshot of the ids, because a handler is entitled to end its own cue and
## a walk over the live dictionary would then be walking something that
## changed underneath it.
func _process(_delta: float) -> void:
	for id: int in _active_handler_by_id.keys():
		if not _active_handler_by_id.has(id):
			continue
		_active_handler_by_id[id].while_active(_handler_params_by_id[id])


## Load the cue registry from disk and prepare one empty bucket per tag.
func _load_registry() -> void:
	var path: String = GASEngineProjectSettings.get_generated_cue_script_path()
	if not FileAccess.file_exists(path):
		_warn_missing_registry(path)
		return

	var bindings: Dictionary[StringName, String] = CueGenerator.bindings_in_file()
	for tag: StringName in bindings:
		var scene: PackedScene = load(bindings[tag]) as PackedScene
		if scene == null:
			push_error(SCENE_MISSING % [String(tag), bindings[tag]])
			continue
		_cue_scenes[tag] = scene
		_pool[tag] = PoolBucket.new()

	var handler_paths: Dictionary[StringName, String] = CueGenerator.handlers_in_file()
	for tag: StringName in handler_paths:
		var handler_script: Script = load(handler_paths[tag]) as Script
		if handler_script == null:
			push_error(SCENE_MISSING % [String(tag), handler_paths[tag]])
			continue
		_handlers[tag] = handler_script.new()

	for tag: StringName in CueGenerator.overrides_in_file():
		_override_parent[tag] = true


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
	var handler: CueHandler = _handler_for(params)
	if handler != null:
		handler.on_execute(params)
		return
	var cue_instance: CueNotify = _resolve_and_parent(params)
	if cue_instance != null:
		cue_instance.execute_cue(params)


## The handler answering this request, or null when a scene answers it.
##
## Resolves the tag through the one walk and stamps `matched_cue_tag` the way
## the scene path does, so a cue can always tell how specific the binding that
## answered it was - regardless of which kind it turned out to be.
func _handler_for(params: CueParams) -> CueHandler:
	if params == null:
		return null
	var matched: StringName = resolve_cue_tag(params.cue_tag)
	if matched == &"" or not _handlers.has(matched):
		return null
	params.matched_cue_tag = matched
	return _handlers[matched]


## Take/instantiate a cue, parent it, and run its PERSISTENT on_active/
## while_active. Returns an invalid handle for a missing registry entry -
## gameplay stays correct with no cue to show for it, per this task's own
## principle.
func activate_persistent_cue(params: CueParams) -> CueHandle:
	var handle: CueHandle = CueHandle.new()
	var handler: CueHandler = _handler_for(params)
	if handler != null:
		handle.id = _next_persistent_id
		_next_persistent_id += 1
		_active_handler_by_id[handle.id] = handler
		_handler_params_by_id[handle.id] = params
		handler.on_active(params)
		set_process(true)
		return handle
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
	if handle == null:
		return
	if _active_handler_by_id.has(handle.id):
		var ending: CueHandler = _active_handler_by_id[handle.id]
		_active_handler_by_id.erase(handle.id)
		_handler_params_by_id.erase(handle.id)
		set_process(not _active_handler_by_id.is_empty())
		ending.on_removed(params)
		return
	if not _active_persistent_by_id.has(handle.id):
		return
	var cue_instance: CueNotify = _active_persistent_by_id[handle.id]
	_active_persistent_by_id.erase(handle.id)
	if not is_instance_valid(cue_instance):
		return
	cue_instance.end_persistent(params)


## Resolve the registry entry, take or instantiate the instance, and (re)parent
## it under the target - the setup both one-shot and persistent activation share.
##
## `is_inside_tree` is not redundant with `is_instance_valid`. A Node that was
## never added to a tree is perfectly valid, and a cue parented under one is
## outside the tree too - so its own `get_tree()` answers null, and
## `GameplayCueNotify.execute_cue` schedules its pooling timer through exactly
## that call. Playing a cue on a detached target was therefore a null
## dereference that took the whole process down: "Cannot call method
## 'create_timer' on a null value", which in a debug build stops at the
## debugger and never returns.
##
## Refusing is the same contract a missing registry entry already has, and the
## one this addon states for itself: gameplay stays correct with no cue to show
## for it. A cue under a detached node could not have been seen anyway, and
## would never have been pooled again either.
func _resolve_and_parent(params: CueParams) -> CueNotify:
	if (
		params == null
		or not is_instance_valid(params.target)
		or not params.target.is_inside_tree()
	):
		return null

	var matched: StringName = resolve_cue_tag(params.cue_tag)
	if matched == &"":
		return null
	params.matched_cue_tag = matched

	var cue_instance: CueNotify = _get_or_create_cue(matched)
	if cue_instance == null:
		return null

	var previous_parent: Node = cue_instance.get_parent()
	if previous_parent != null:
		previous_parent.remove_child(cue_instance)
	params.target.add_child(cue_instance)
	return cue_instance
#endregion


#region Resolution
## Which tag actually answers a request.
##
## The cue a game announces is often more specific than the cue it has art
## for: `Cue.Damage.Fire.Critical` is a reasonable thing to say and a silly
## thing to demand a separate scene for. So a request nothing answers falls
## back up its own family - A.B.C, then A.B, then A - and the first binding
## found is the one that plays.
##
## A tag under OVERRIDE_PARENT ends that walk where it stands. With a binding
## of its own, that binding is what plays; without one, nothing plays and
## nothing further up is consulted either - which is how a project says "this
## whole branch is silent" without binding every leaf under it to an empty
## scene.
##
## Answers &"" when nothing does, which every caller already treats as "no
## cue to show for it, and gameplay carries on regardless".
## Both kinds of binding are consulted at each level, in one walk. Two walks -
## scenes first, then handlers - would answer a request with an ancestor's
## scene while a handler was bound to the exact tag, so which kind a project
## chose would silently change which tag answered.
func resolve_cue_tag(requested: StringName) -> StringName:
	for candidate: StringName in TagFamily.ancestors_of(requested):
		if _cue_scenes.has(candidate) or _handlers.has(candidate):
			return candidate
		if _override_parent.has(candidate):
			return &""
	return &""
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
	_forget_persistent(cue_node)

	var parent: Node = cue_node.get_parent()
	if parent != null:
		parent.remove_child(cue_node)

	_set_cue_state(cue_node, false)
	add_child(cue_node)
	_bucket_for(tag).give(cue_node)


## Drop any persistent registration the node still holds.
##
## `activate_persistent_cue` is the only writer of that map and
## `deactivate_persistent_cue` was its only eraser, but a cue can leave the
## active state a third way: `finish_cue()` is a documented override point and
## nothing stops a persistent cue from reporting itself done through it. The
## node was pooled while its id stayed registered, so the next activation to
## take that instance out of the pool inherited a second, older handle - and
## deactivating through the older one ended the newer playback. Confirmed:
## `current_params` came back null on a cue that was still live.
##
## Keys are iterated from a copy, which `Dictionary.keys()` returns, so erasing
## inside the loop is safe.
func _forget_persistent(cue_node: CueNotify) -> void:
	for id: int in _active_persistent_by_id.keys():
		if _active_persistent_by_id[id] == cue_node:
			_active_persistent_by_id.erase(id)


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


## How many dormant instances are pooled for a tag. An observation point for
## tests and tools; nothing in the runtime branches on it.
func get_pooled_count(tag: StringName) -> int:
	return _bucket_for(tag).size()
#endregion
