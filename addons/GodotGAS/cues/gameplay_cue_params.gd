## The typed parameters a cue receives from the ASC.
##
## The cue system takes this instead of an arbitrary `Dictionary`. A cue that
## reads `payload.get("magnitude")` cannot be checked by anything: the key is
## invented at the call site and consumed at the cue, with nothing in between
## that would notice a rename.
##
## Types come from `preload` rather than global class names: this file is
## reachable from the GameplayCueManager autoload, which Godot parses before a
## global class cache exists on a checkout that was never imported.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_license: MIT
class_name GameplayCueParams extends RefCounted

const EffectContext: GDScript = preload("res://addons/GodotGAS/target_data/gameplay_effect_context.gd")

## The cue tag being executed.
var cue_tag: StringName = &""

## Who triggered the cue, and who it plays on.
var instigator: Node = null
var target: Node = null

## The scalar the cue may scale itself by - damage dealt, healing applied.
var magnitude: float = 0.0

## Where the cue should play, when the effect had a located hit. A cue attached
## to the target node ignores this. `has_location` exists because Vector3.ZERO
## is a real place, so it cannot double as "no location".
var location: Vector3 = Vector3.ZERO
var has_location: bool = false

## The originating effect context, when the cue came from an effect.
var context: EffectContext = null


## Build the common case in one call, so the ASC does not repeat six assignments
## at every cue site and forget one of them at the seventh.
static func for_target(
	tag: StringName, instigator_node: Node, target_node: Node, cue_magnitude: float
) -> GameplayCueParams:
	var params: GameplayCueParams = GameplayCueParams.new()
	params.cue_tag = tag
	params.instigator = instigator_node
	params.target = target_node
	params.magnitude = cue_magnitude
	return params


func with_location(world_location: Vector3) -> GameplayCueParams:
	location = world_location
	has_location = true
	return self
