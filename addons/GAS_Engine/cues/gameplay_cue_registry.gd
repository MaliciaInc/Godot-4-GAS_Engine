## A registry resource that holds mappings of gameplay tags to visual/audio cues.
##
## Used by the global GameplayCueManager to look up which PackedScene
## should be instantiated or pooled when a specific cue tag is executed.
##
## @meta_addon: GAS_Engine Version 1 (See plugin version for exact version)
## @meta_author: YulRun (https://YulRun.Dev)
## @meta_license: MIT

@tool
@icon("res://addons/GAS_Engine/icons/gas_engine_asc.svg")
class_name GameplayCueRegistry extends Resource

## The element type comes from preload, not the global `GameplayCueEntry`
## name. The GameplayCueManager autoload preloads this file, and Godot
## parses it before a global class cache exists on a never-imported checkout.
const CueEntry = preload("res://addons/GAS_Engine/cues/gameplay_cue_entry.gd")

## The list of all registered gameplay cues.
@export var entries: Array[CueEntry] = []


#region Registry Queries
## The PackedScene mapped to a tag, or null.
##
## Answers exactly what GameplayCueManager would play. The manager builds a
## Dictionary while loading, skipping an entry with no tag or no scene, so a tag
## listed twice resolves to the last usable entry. This read the list forwards
## and returned whatever the first entry carrying the tag held - so it answered
## null for a tag the manager plays happily, and the earlier scene for a tag
## listed twice.
##
## Two answers to one question, on a method nothing inside this addon calls -
## which is how they were free to drift - and which a game may well be the one
## asking.
func get_scene_for_tag(tag: StringName) -> PackedScene:
	for index: int in range(entries.size() - 1, -1, -1):
		var entry: CueEntry = entries[index]
		if entry != null and entry.tag == tag and entry.scene != null:
			return entry.scene
	return null
#endregion
