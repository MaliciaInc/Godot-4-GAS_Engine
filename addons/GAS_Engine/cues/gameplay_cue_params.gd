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
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayCueParams extends RefCounted

## This script's own type, preloaded rather than named.
##
## This file is in the GameplayCueManager autoload's parse-time closure, and
## Godot parses autoloads before it has scanned the project for class_name
## declarations. A global name - even this file's own - does not resolve
## there, so the reference is a preload and the type is its alias.
const Params = preload("res://addons/GAS_Engine/cues/gameplay_cue_params.gd")


const EffectContext = preload("res://addons/GAS_Engine/target_data/gameplay_effect_context.gd")
const EffectHandle = preload("res://addons/GAS_Engine/effects/gameplay_effect_handle.gd")
const TargetHit = preload("res://addons/GAS_Engine/target_data/gameplay_target_hit.gd")
const NetEntityId = preload("res://addons/GAS_Engine/networking/gameplay_net_entity_id.gd")

## The cue tag as it was asked for.
var cue_tag: StringName = &""

## The tag whose binding actually answered it, which is not always the same.
##
## A request that nothing answers falls back up its own family, so a cue asked
## for as `Cue.Damage.Fire.Critical` may well be played by the scene bound to
## `Cue.Damage`. A cue that wants to know how specific the request was needs
## both tags; one that only needs to know what it itself is needs neither.
## Empty until the manager has resolved the request.
var matched_cue_tag: StringName = &""

## Who triggered the cue, and who it plays on.
var instigator: Node = null
var target: Node = null

## The scalar the cue may scale itself by - damage dealt, healing applied.
##
## The same number as `raw_magnitude`, kept under the name every cue written
## before this reads. Two names for one value rather than a rename that would
## silently zero every existing cue.
var magnitude: float = 0.0

## The number as it was measured, in whatever unit it is in - points of
## damage, points of shield left.
var raw_magnitude: float = 0.0

## Where the raw number lands in the range its binding declared, clamped to
## 0..1.
##
## This is the one a cue should scale itself by. A particle that scaled by the
## raw number is a particle authored against this game's damage numbers, and
## it breaks the day somebody rebalances them.
var normalized_magnitude: float = 0.0

## What the effect behind this cue was applied at, and what the ability that
## caused it was activated at. Zero when there was no effect or no ability,
## which is not the same as level zero and is why a cue that cares should ask
## whether it has a `context` first.
var effect_level: float = 0.0
var ability_level: float = 0.0

## What each side was at the moment the cue was made.
##
## Snapshots rather than a live read: by the time a removal cue plays, the
## effect it announces is gone and so are the tags it granted.
var source_tags: Array[StringName] = []
var target_tags: Array[StringName] = []

## The authored thing behind this cue - a weapon Resource, an ability scene -
## and the Node that physically caused it, which is not always the instigator:
## a turret shooting for its owner is the causer, the owner is the instigator.
## Local only; neither crosses a wire.
var source_object: Object = null
var causer: Node = null

## The same two, said in identities a receiving machine can resolve. Null on a
## component with no network, which is every single-player game.
var source_entity: NetEntityId = null
var causer_entity: NetEntityId = null

## How many of the effect were on the target when this cue was made.
##
## Carried rather than looked up: a cue that shows or scales with a stack
## count would otherwise have to resolve the handle and ask, and by the time
## a removal cue plays the effect it is announcing is already gone.
var stack_count: int = 1

## Where the effect landed on this target, when the application had a hit
## recorded for it - the point a spark plays at, the normal a decal aligns
## to. Null for an effect that hit nothing in particular, which is most of
## them: a poison tick has a target and no impact point.
var target_hit: TargetHit = null

## Where the cue should play, when the effect had a located hit. A cue attached
## to the target node ignores this. `has_location` exists because Vector3.ZERO
## is a real place, so it cannot double as "no location".
var location: Vector3 = Vector3.ZERO
var has_location: bool = false

## The originating effect context, when the cue came from an effect.
var context: EffectContext = null

## The stable identity of the effect that caused this cue, when one exists -
## null for INSTANT (no handle at all) and for a cue with no effect behind
## it. An opaque handle, never the live ActiveGameplayEffect: a cue script
## can resolve it through a query if it needs to, but cannot reach in and
## mutate runtime state through it.
var effect_handle: EffectHandle = null


## Build the common case in one call, so the ASC does not repeat six assignments
## at every cue site and forget one of them at the seventh.
static func for_target(
	tag: StringName, instigator_node: Node, target_node: Node, cue_magnitude: float
) -> GameplayCueParams:
	var params: GameplayCueParams = Params.new()
	params.cue_tag = tag
	params.instigator = instigator_node
	params.target = target_node
	params.set_magnitude(cue_magnitude)
	return params


## Set the measured number and its normalised reading in one call.
##
## One door rather than three assignments: `magnitude` and `raw_magnitude` are
## two names for one value, and a caller that set one of them and forgot the
## other would hand a cue two different answers to the same question.
func set_magnitude(measured: float, low: float = 0.0, high: float = 1.0) -> void:
	raw_magnitude = measured
	magnitude = measured
	# An empty range has no inside, so everything in it reads as the top: a
	# binding that named one level is saying "whenever this happens, fully".
	if is_equal_approx(low, high):
		normalized_magnitude = 1.0
	else:
		normalized_magnitude = clampf(inverse_lerp(low, high, measured), 0.0, 1.0)


func with_location(world_location: Vector3) -> GameplayCueParams:
	location = world_location
	has_location = true
	return self
