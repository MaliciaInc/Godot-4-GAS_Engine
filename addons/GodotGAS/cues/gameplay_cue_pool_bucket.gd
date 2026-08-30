## The dormant cue instances pooled under one cue tag.
##
## Exists so the pool can be `Dictionary[StringName, GameplayCuePoolBucket]`
## rather than `Dictionary[StringName, Variant]` holding untyped arrays. GDScript
## has no nested collection type for the latter, and writing it as Variant means
## every read has to re-assert what the value is.
##
## The element type comes from `preload`, not from the `GameplayCueNotify`
## global name. This file is reached from the GameplayCueManager autoload, which
## is parsed before Godot has a global class cache on a clean checkout - and a
## clean checkout with no cache is exactly the state step 1.8 requires to work.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_license: MIT
class_name GameplayCuePoolBucket extends RefCounted

const CueNotify: GDScript = preload("res://addons/GodotGAS/cues/gameplay_cue_notify.gd")

var items: Array[CueNotify] = []


func is_empty() -> bool:
	return items.is_empty()


## Take a dormant cue, or null when the bucket is empty. The caller instantiates
## a fresh one in that case; this class never decides that for it.
func take() -> CueNotify:
	if items.is_empty():
		return null
	return items.pop_back()


func give(cue: CueNotify) -> void:
	if cue != null and not items.has(cue):
		items.append(cue)


func size() -> int:
	return items.size()
