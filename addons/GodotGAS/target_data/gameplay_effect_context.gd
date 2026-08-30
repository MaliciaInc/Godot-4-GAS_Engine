## Where an effect came from and who it hit.
##
## Wraps instigator, causer and target data into one object that travels through
## the execution pipeline, so no stage has to reassemble it from loose arguments.
##
## Types come from `preload` rather than global class names: this file is
## reachable from the GameplayCueManager autoload, which Godot parses before a
## global class cache exists on a checkout that was never imported.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_author: YulRun (https://YulRun.Dev), Arhalies fork
## @meta_license: MIT

@icon("res://addons/GodotGAS/icons/godot_gas_asc.svg")
class_name GameplayEffectContext extends RefCounted

## This script's own type, preloaded rather than named.
##
## This file is in the GameplayCueManager autoload's parse-time closure, and
## Godot parses autoloads before it has scanned the project for class_name
## declarations. A global name - even this file's own - does not resolve
## there. tooling/project_invariants.py enforces the rule.
const Context = preload("res://addons/GodotGAS/target_data/gameplay_effect_context.gd")


const TargetData = preload("res://addons/GodotGAS/target_data/gameplay_ability_target_data.gd")

## The entity that activated the ability, e.g. the player character.
var instigator: Node = null

## The entity that physically caused the effect, e.g. a fireball projectile.
## Defaults to the instigator when there is no secondary actor.
var causer: Node = null

## Who, what and where the ability hit.
var target_data: TargetData = null


#region Initialization
func _init(in_instigator: Node = null, in_causer: Node = null) -> void:
	instigator = in_instigator
	causer = in_causer if in_causer != null else in_instigator
	target_data = TargetData.new()
#endregion


#region Application copy
## A context for one more target.
##
## The logical origin - who cast this, and with what - is preserved. The target
## payload is NOT: each application resolves its own targets, and sharing the
## payload is how an AoE ends up applying target A's hits to target B.
func create_application_copy() -> GameplayEffectContext:
	var copy: GameplayEffectContext = Context.new(instigator, causer)
	return copy
#endregion


#region Payload Helpers
func has_targets() -> bool:
	return target_data != null and target_data.has_targets()


func get_target_nodes() -> Array[Node]:
	if target_data == null:
		return []
	return target_data.get_target_nodes()
#endregion
