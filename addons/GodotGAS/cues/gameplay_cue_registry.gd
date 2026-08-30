## A registry resource that holds mappings of gameplay tags to visual/audio cues.
##
## Used by the global GameplayCueManager to look up which PackedScene 
## should be instantiated or pooled when a specific cue tag is executed.
##
## @meta_addon: GodotGAS Version 1 (See plugin version for exact version)
## @meta_author: YulRun (https://YulRun.Dev)
## @meta_license: MIT

@tool
@icon("res://addons/GodotGAS/icons/godot_gas_asc.svg")
class_name GameplayCueRegistry extends Resource

## The element type comes from preload, not the global `GameplayCueEntry`
## name. The GameplayCueManager autoload preloads this file, and Godot
## parses it before a global class cache exists on a never-imported checkout.

## The list of all registered gameplay cues.
@export var entries: Array[GameplayCueEntry] = []


#region Registry Queries
## Helper to find a PackedScene by its mapped gameplay tag quickly.
func get_scene_for_tag(tag: StringName) -> PackedScene:
	for entry: GameplayCueEntry in entries:
		if entry != null and entry.tag == tag:
			return entry.scene
	return null
#endregion
