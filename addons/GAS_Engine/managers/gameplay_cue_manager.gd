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

const CueParams = preload("res://addons/GAS_Engine/cues/gameplay_cue_params.gd")
const CueHandle = preload("res://addons/GAS_Engine/cues/gameplay_cue_handle.gd")
const CueHandler = preload("res://addons/GAS_Engine/cues/gameplay_cue_handler.gd")
const Playback = preload("res://addons/GAS_Engine/cues/gameplay_cue_playback.gd")
const CueFlags = preload("res://addons/GAS_Engine/cues/gameplay_cue_flags.gd")
const PlaybackRegistry = preload(
	"res://addons/GAS_Engine/cues/gameplay_cue_playback_registry.gd"
)
const Catalog = preload("res://addons/GAS_Engine/cues/gameplay_cue_catalog.gd")
const PoolBucket = preload("res://addons/GAS_Engine/cues/gameplay_cue_pool_bucket.gd")

## Where every caller outside this file's own closure finds this autoload -
## `get_node_or_null(AUTOLOAD_NODE_PATH)`, never the bare global identifier,
## since a caller that may run before the singleton exists (or, for the
## runtime debugger, one that must never assume a running game is even
## attached) needs a null it can check rather than a resolution error.
const AUTOLOAD_NODE_PATH: NodePath = ^"/root/GameplayCueManager"

## The method a target implements to hear about its own cues.
##
## Beside the binding, never instead of it: both receive. A target that
## wants to flash red when it is hit should not have to be the thing that
## plays the impact, and a project that binds a scene should not lose the
## chance to react in code.
const TARGET_INTERFACE_METHOD: StringName = &"handle_gameplay_cue"

## Dormant instances, one bucket per cue tag.
var _pool: Dictionary[StringName, PoolBucket] = {}


## Which persistent cues are running, keyed by handle id - the id rather
## than the handle object, so a caller's own copy still resolves. Its own
## collaborator, because resolving a tag and keeping track of what is playing
## are two jobs.
var _playbacks: PlaybackRegistry = PlaybackRegistry.new()

## What is bound to what, and which binding answers a request. Its own
## object, because a catalogue and a pool have no fields in common.
var catalog: Catalog = Catalog.new()


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
	_playbacks.tick_handlers()


## Fill the catalogue, and give each bound tag an empty bucket to be pooled
## into. The buckets are the manager's because the pool is.
func _load_registry() -> void:
	if not catalog.load_from_project():
		return
	for tag: StringName in catalog.scenes:
		_pool[tag] = PoolBucket.new()
#endregion


#region Cue Execution
## Spawn a cue on its target. The ASC calls this with a typed parameter object;
## an arbitrary Dictionary payload would let the caller and the cue disagree
## about every key with nothing in between to notice.
func execute_cue(params: CueParams) -> void:
	var handler: CueHandler = _handler_for(params)
	if handler != null:
		handler.on_execute(params)
		_told(params.target, params, CueNotify.Event.EXECUTED)
		return
	var cue_instance: CueNotify = _resolve_and_parent(params)
	if cue_instance != null:
		cue_instance.execute_cue(params)
	_told(params.target, params, CueNotify.Event.EXECUTED)


## Tell the target itself, when it has said it wants to hear.
##
## Duck-typed on purpose: an interface would be a class every target has to
## extend, and a target is whatever the game already had. Called even when
## nothing was bound to the tag, because "nobody has art for this yet" and
## "this did not happen" are different things and the target is entitled to
## know the difference.
func _told(target: Node, params: CueParams, event: CueNotify.Event) -> void:
	if target == null or not is_instance_valid(target):
		return
	if not target.has_method(TARGET_INTERFACE_METHOD):
		return
	target.call(TARGET_INTERFACE_METHOD, params.cue_tag, event, params)


## The handler answering this request, or null when a scene answers it.
##
## Resolves the tag through the one walk and stamps `matched_cue_tag` the way
## the scene path does, so a cue can always tell how specific the binding that
## answered it was - regardless of which kind it turned out to be.
func _handler_for(params: CueParams) -> CueHandler:
	if params == null:
		return null
	var matched: StringName = resolve_cue_tag(params.cue_tag)
	if matched == &"" or not catalog.handlers.has(matched):
		return null
	params.matched_cue_tag = matched
	return catalog.handlers[matched]


## Take/instantiate a cue, parent it, and run its PERSISTENT on_active/
## while_active. Returns an invalid handle for a missing registry entry -
## gameplay stays correct with no cue to show for it, per this task's own
## principle.
func activate_persistent_cue(params: CueParams) -> CueHandle:
	var handle: CueHandle = CueHandle.new()
	var handler: CueHandler = _handler_for(params)
	if handler != null:
		handle.id = _begin(params, null, handler)
		handler.on_active(params)
		_told(params.target, params, CueNotify.Event.ON_ACTIVE)
		set_process(true)
		return handle

	# A cue that declares itself unique may already be running for this
	# instigator or this source. The existing handle is what comes back, so
	# whoever asked can still end it - a second handle for one running cue
	# would leave the first caller holding one that does nothing.
	var already: int = _running_id_for(params)
	if already != PlaybackRegistry.NO_PLAYBACK:
		handle.id = already
		var standing: Playback = _playbacks.get_playback(already)
		var says: CueFlags = catalog.flags_for(standing.tag)
		if standing.node != null and says != null and says.allow_multiple_on_active:
			standing.node.begin_persistent(params)
			_told(params.target, params, CueNotify.Event.ON_ACTIVE)
		return handle

	var cue_instance: CueNotify = _resolve_and_parent(params)
	if cue_instance == null:
		return handle
	handle.id = _begin(params, cue_instance, null)
	cue_instance.begin_persistent(params)
	_told(params.target, params, CueNotify.Event.ON_ACTIVE)
	return handle


## Register a running playback and answer with the handle id it lives under.
func _begin(params: CueParams, node: CueNotify, handler: CueHandler) -> int:
	var record: Playback = _described(params)
	record.node = node
	record.handler = handler
	record.params = params
	return _playbacks.begin(record)


## What a request is, as the record a playback of it would be.
##
## The same shape for the request and for the thing running, because
## uniqueness is the question of whether those two are the same cue - and a
## request described differently from a playback could not be compared to one.
func _described(params: CueParams) -> Playback:
	var record: Playback = Playback.new()
	record.tag = params.matched_cue_tag if params.matched_cue_tag != &"" else params.cue_tag
	record.target = params.target
	record.instigator = params.instigator
	record.source_object = params.source_object
	return record


## The id of a running cue this request would be a second copy of, or
## NO_PLAYBACK.
##
## Only a cue that declares itself unique can answer yes, so a project that
## never sets either flag behaves exactly as it did before they existed.
func _running_id_for(params: CueParams) -> int:
	# A request whose target is already gone is not a second copy of
	# anything, and asking would mean handing a freed instance to a typed
	# Node parameter - which the engine refuses before the comparison runs,
	# so a guard inside the comparison would never get the chance.
	if params.target == null or not is_instance_valid(params.target):
		return PlaybackRegistry.NO_PLAYBACK
	var matched: StringName = resolve_cue_tag(params.cue_tag)
	if matched == &"" or not catalog.scenes.has(matched):
		return PlaybackRegistry.NO_PLAYBACK
	var candidate: Playback = _described(params)
	candidate.tag = matched
	return _playbacks.matching(candidate, catalog.flags_for(matched))


## Ends and pools a persistent cue by its handle. A handle that no longer
## resolves - already ended, or never valid - is a no-op, never an error:
## the same "gameplay stays correct without the cue" contract as a missing
## registry entry.
func deactivate_persistent_cue(handle: CueHandle, params: CueParams) -> void:
	if handle == null:
		return
	var ending: Playback = _playbacks.end(handle.id)
	if ending == null:
		return
	set_process(_playbacks.any_handler_running())
	# Asked before the call rather than inside it: a freed instance handed to
	# a typed Node parameter is refused by the engine before the function
	# body runs, so a guard in there would never get the chance.
	if is_instance_valid(ending.target):
		_told(ending.target, params, CueNotify.Event.REMOVED)
	if ending.handler != null:
		ending.handler.on_removed(params)
		return
	if not is_instance_valid(ending.node):
		return
	ending.node.end_persistent(params)


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
## Which tag answers a request. The walk itself is the catalogue's, since it
## is a question about bindings rather than about instances.
func resolve_cue_tag(requested: StringName) -> StringName:
	return catalog.resolve(requested)
#endregion


#region Object Pooling
## Retrieve a dormant cue or instantiate a fresh one.
func _get_or_create_cue(tag: StringName) -> CueNotify:
	var pooled: CueNotify = _bucket_for(tag).take()
	if pooled != null:
		_set_cue_state(pooled, true)
		return pooled
	var made: CueNotify = _instantiate_cue(tag)
	if made != null:
		_set_cue_state(made, true)
	return made


## Build one instance of a cue, without touching the pool.
##
## Apart from `_get_or_create_cue` because preallocation needs the making
## without the taking: asking that function for instances to put INTO the pool
## takes the last one straight back out again, and the bucket never grows.
func _instantiate_cue(tag: StringName) -> CueNotify:
	var scene: PackedScene = catalog.scenes[tag]
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
	_playbacks.forget(cue_node)


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
## End every persistent cue running on one target.
##
## For a character being despawned or reset: the effects that started them
## are gone with it, so nothing else is ever going to hand back their
## handles, and an aura nobody can end is an aura forever.
func remove_all_cues(target: Node) -> void:
	for id: int in _playbacks.ids_for(target):
		var running: Playback = _playbacks.get_playback(id)
		if running == null:
			continue
		var ending: CueHandle = CueHandle.new()
		ending.id = id
		deactivate_persistent_cue(ending, running.params)


## Whether a persistent cue with this tag is running on this target.
##
## By the tag that answered rather than the tag asked for, which is the same
## rule uniqueness uses: two requests answered by one binding are one cue.
func is_cue_active(target: Node, tag: StringName) -> bool:
	return _playbacks.is_running(target, resolve_cue_tag(tag))


## Make, ahead of time, as many of each cue as its scene asks for.
##
## Instantiating a scene is the expensive part of playing a cue, and a fight
## that needs forty impacts in its first second is forty of them during the
## fight. A project calls this when it can afford to - a loading screen, a
## level start - and never has to: every cue is made on demand otherwise.
func preallocate_from_registry() -> void:
	for tag: StringName in catalog.scenes:
		var declared: CueFlags = catalog.flags_for(tag)
		if declared == null or declared.preallocate <= 0:
			continue
		var bucket: PoolBucket = _bucket_for(tag)
		while bucket.size() < declared.preallocate:
			var made: CueNotify = _instantiate_cue(tag)
			if made == null:
				break
			_set_cue_state(made, false)
			add_child(made)
			bucket.give(made)


func get_pooled_count(tag: StringName) -> int:
	return _bucket_for(tag).size()
#endregion
