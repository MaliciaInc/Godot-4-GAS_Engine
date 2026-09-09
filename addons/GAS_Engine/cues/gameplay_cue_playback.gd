## One persistent cue that is currently running, and everything needed to
## decide whether a second request is the same one.
##
## A record rather than three parallel dictionaries keyed by the same handle id.
## That is what this replaced, and the reason to replace it is that a handle
## living in one map and its params in another is two things that can disagree -
## and did, the moment a second kind of endpoint arrived.
##
## Both kinds of endpoint live here, and exactly one of them is set: a tag is
## answered by a scene or by a script, never by both.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayCuePlayback extends RefCounted

const CueParams = preload("res://addons/GAS_Engine/cues/gameplay_cue_params.gd")
const CueNotify = preload("res://addons/GAS_Engine/cues/gameplay_cue_notify.gd")
const CueHandler = preload("res://addons/GAS_Engine/cues/gameplay_cue_handler.gd")
const CueFlags = preload("res://addons/GAS_Engine/cues/gameplay_cue_flags.gd")

## The tag that answered the request, not the tag that was asked for: two
## requests answered by the same binding are the same cue as far as uniqueness
## is concerned, however specifically each of them was spelled.
var tag: StringName = &""

var target: Node = null
var instigator: Node = null
var source_object: Object = null

## The scene-backed endpoint, or the scriptless one. Exactly one is set.
var node: CueNotify = null
var handler: CueHandler = null

## What this playback was told, kept so `while_active` can be given the same
## thing `on_active` was.
var params: CueParams = null


## Whether `other` would be the same running cue as this one.
##
## Asked with the flags of the cue itself rather than with a rule written
## here: whether two of something may run at once is a property of the
## something. A cue that declares neither kind of uniqueness is never the same
## as another, which is what every cue authored before those flags existed
## does.
##
## A record rather than four loose values, because the caller already has one:
## a request that is about to become a playback is described by exactly the
## same fields as the playback it might duplicate.
func is_same_as(other: GameplayCuePlayback, flags: CueFlags) -> bool:
	if not flags.unique_per_instigator and not flags.unique_per_source_object:
		return false
	# A playback whose target has been freed is not the same as anything: the
	# comparison would be against an object that no longer exists.
	if not is_instance_valid(target) or not is_instance_valid(other.target):
		return false
	if tag != other.tag or target != other.target:
		return false
	if flags.unique_per_instigator and instigator != other.instigator:
		return false
	if flags.unique_per_source_object and source_object != other.source_object:
		return false
	return true
