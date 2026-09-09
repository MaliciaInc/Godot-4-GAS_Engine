## Which persistent cues are running, and which of them a new request would be
## a second copy of.
##
## Split out of GameplayCueManager the same way the pool bucket was: the manager
## resolves a tag, takes an instance and parents it, which is work about scenes.
## This is bookkeeping about playbacks, and the two grew into one file.
##
## Holds no scenes, no pool and no tree. Everything here is answered from the
## records themselves, which is what makes it safe to ask from the middle of an
## ending - the manager is mutating nodes at that moment and this is not.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayCuePlaybackRegistry extends RefCounted

const Playback = preload("res://addons/GAS_Engine/cues/gameplay_cue_playback.gd")
const CueFlags = preload("res://addons/GAS_Engine/cues/gameplay_cue_flags.gd")
const CueNotify = preload("res://addons/GAS_Engine/cues/gameplay_cue_notify.gd")

## The handle id that means no playback, so an absent one is not playback zero.
const NO_PLAYBACK: int = -1

var _running: Dictionary[int, Playback] = {}

## Never reused, so a handle from a finished playback can never resolve to the
## one that took its place in the pool.
var _next_id: int = 1


## Put a playback under a fresh id and answer with it.
func begin(record: Playback) -> int:
	var id: int = _next_id
	_next_id += 1
	_running[id] = record
	return id


func has(id: int) -> bool:
	return _running.has(id)


func get_playback(id: int) -> Playback:
	return _running.get(id)


## Take a playback out and hand it back, or null when the id names none.
func end(id: int) -> Playback:
	var ending: Playback = _running.get(id)
	if ending != null:
		_running.erase(id)
	return ending


## Every id running on one target, as a snapshot.
##
## A snapshot because the caller is going to end them, and ending one erases it
## from the very dictionary a live walk would be walking.
func ids_for(target: Node) -> Array[int]:
	var found: Array[int] = []
	for id: int in _running:
		if _running[id].target == target:
			found.append(id)
	return found


## The id of a running cue this request would be a second copy of, or
## NO_PLAYBACK.
##
## Only a cue that declares itself unique can answer yes, so a project that
## never sets either flag behaves exactly as it did before the flags existed.
func matching(candidate: Playback, flags: CueFlags) -> int:
	if flags == null:
		return NO_PLAYBACK
	for id: int in _running:
		if _running[id].is_same_as(candidate, flags):
			return id
	return NO_PLAYBACK


## Whether a persistent cue with this tag is running on this target.
func is_running(target: Node, tag: StringName) -> bool:
	for id: int in _running:
		var playback: Playback = _running[id]
		if playback.target == target and playback.tag == tag:
			return true
	return false


## Drop any registration a node still holds.
##
## `begin` is the only writer and `end` was its only eraser, but a cue can leave
## the active state a third way: `finish_cue()` is a documented override point
## and nothing stops a persistent cue from reporting itself done through it. The
## node was pooled while its id stayed registered, so the next activation to
## take that instance out of the pool inherited a second, older handle - and
## deactivating through the older one ended the newer playback.
func forget(node: CueNotify) -> void:
	for id: int in _running.keys():
		if _running[id].node == node:
			_running.erase(id)


## Tell every running handler playback that it is still running.
##
## The scriptless counterpart of GameplayCueNotify's own while_active: a
## RefCounted has no frame of its own. Over a snapshot of the ids, because a
## handler is entitled to end its own cue and a walk over the live dictionary
## would then be walking something that changed underneath it.
func tick_handlers() -> void:
	for id: int in _running.keys():
		if not _running.has(id):
			continue
		var running: Playback = _running[id]
		if running.handler != null:
			running.handler.while_active(running.params)


func any_handler_running() -> bool:
	for id: int in _running:
		if _running[id].handler != null:
			return true
	return false
