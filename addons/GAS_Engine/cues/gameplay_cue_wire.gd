## A cue in the only shape a wire can carry.
##
## `GameplayCueParams` holds a Node for the target, a Node for the causer and an
## arbitrary Object for whatever authored the thing - and none of those mean
## anything on another machine. This is the same cue said in identities, tags
## and numbers.
##
## What is deliberately absent is as much of the contract as what is here.
## `source_object` and `causer` do not cross: an ObjectID is a slot in one
## process's table, and a receiver resolving one would get whatever happens to
## be in that slot. Their identities cross instead, and a peer that cannot
## resolve one is handed nothing rather than something else.
##
## How a cue crosses is GameplayNetCueSerializer's, which refuses malformed
## input rather than repairing it: a field that does not read as one is a
## message from a machine that disagrees about the contract, and guessing what
## it meant is how one bad sender becomes two.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayCueWire extends RefCounted

## What was asked for, and what actually answered it. Both, because a cue that
## wants to know how specific the request was needs the pair.
var cue_tag: StringName = &""
var matched_cue_tag: StringName = &""

## Who caused it, who it plays on, and the two identities standing in for the
## objects that do not cross. Null when the sender could not name one, which is
## not the same as naming nobody.
var instigator: GameplayNetEntityId = null
var target: GameplayNetEntityId = null
var source_entity: GameplayNetEntityId = null
var causer_entity: GameplayNetEntityId = null

## The number as measured and the number as a fraction. Both travel: a receiver
## that only had the fraction could not show a damage figure, and one that only
## had the raw value would have to know this game's ranges to scale anything.
var raw_magnitude: float = 0.0
var normalized_magnitude: float = 0.0

var effect_level: float = 0.0
var ability_level: float = 0.0
var stack_count: int = 1

## The two snapshots, which cross as themselves - tags are already names every
## machine agrees about.
var source_tags: Array[StringName] = []
var target_tags: Array[StringName] = []

## Where it plays, when the effect had a located hit. `has_location` exists
## because Vector3.ZERO is a real place and cannot double as "nowhere".
var location: Vector3 = Vector3.ZERO
var has_location: bool = false
