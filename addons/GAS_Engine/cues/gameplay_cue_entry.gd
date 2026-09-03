## Maps a specific gameplay tag to a visual/audio cue scene.
##
## Used by the GameplayCueRegistry to define which PackedScene should be
## instantiated or pooled when a specific cue tag is executed.
##
## @meta_addon: GAS_Engine Version 1 (See plugin version for exact version)
## @meta_author: MaliciaInc
## @meta_license: GAS_Engine Community Use License 1.0

@tool
@icon("res://addons/GAS_Engine/icons/gas_engine_asc.svg")
class_name GameplayCueEntry extends Resource

## The gameplay tag associated with this cue. 
## Note: The GameplayTag inspector plugin automatically detects the variable name "tag".
@export var tag: StringName

## The PackedScene containing the visual or audio effects to trigger.
@export var scene: PackedScene
