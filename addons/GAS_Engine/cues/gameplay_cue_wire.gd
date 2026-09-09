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
## Malformed input is refused rather than repaired, for the same reason the
## event wire refuses it: a field of the wrong type is a message from a machine
## that disagrees about the contract, and guessing what it meant is how one bad
## sender becomes two.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayCueWire extends RefCounted

## The keys, spelled once and namespaced, for the same reason the event wire
## namespaces its own: `magnitude` and `target_tags` are words this addon uses
## elsewhere for unrelated purposes.
const TAG_KEY: String = "cue.tag"
const MATCHED_KEY: String = "cue.matched"
const INSTIGATOR_KEY: String = "cue.instigator"
const TARGET_KEY: String = "cue.target"
const SOURCE_KEY: String = "cue.source"
const CAUSER_KEY: String = "cue.causer"
const RAW_KEY: String = "cue.raw"
const NORMALIZED_KEY: String = "cue.normalized"
const EFFECT_LEVEL_KEY: String = "cue.effect_level"
const ABILITY_LEVEL_KEY: String = "cue.ability_level"
const STACK_KEY: String = "cue.stack"
const SOURCE_TAGS_KEY: String = "cue.source_tags"
const TARGET_TAGS_KEY: String = "cue.target_tags"
const LOCATION_KEY: String = "cue.location"
const HAS_LOCATION_KEY: String = "cue.has_location"

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


## Primitives only. Nothing here is an object, so nothing here means anything
## different on the machine that reads it.
func to_wire() -> Dictionary:
	return {
		TAG_KEY: String(cue_tag),
		MATCHED_KEY: String(matched_cue_tag),
		INSTIGATOR_KEY: GameplayWireReader.entity_said(instigator),
		TARGET_KEY: GameplayWireReader.entity_said(target),
		SOURCE_KEY: GameplayWireReader.entity_said(source_entity),
		CAUSER_KEY: GameplayWireReader.entity_said(causer_entity),
		RAW_KEY: raw_magnitude,
		NORMALIZED_KEY: normalized_magnitude,
		EFFECT_LEVEL_KEY: effect_level,
		ABILITY_LEVEL_KEY: ability_level,
		STACK_KEY: stack_count,
		SOURCE_TAGS_KEY: GameplayWireReader.as_strings(source_tags),
		TARGET_TAGS_KEY: GameplayWireReader.as_strings(target_tags),
		LOCATION_KEY: location,
		HAS_LOCATION_KEY: has_location,
	}


## The same cue back, or null.
static func from_wire(wire: Dictionary) -> GameplayCueWire:
	if not GameplayWireReader.has_shape(wire, _expected()):
		return null

	var made: GameplayCueWire = GameplayCueWire.new()
	made.cue_tag = StringName(str(wire[TAG_KEY]))
	if made.cue_tag == &"":
		return null
	made.matched_cue_tag = StringName(str(wire[MATCHED_KEY]))

	made.instigator = GameplayWireReader.entity_from(wire[INSTIGATOR_KEY])
	made.target = GameplayWireReader.entity_from(wire[TARGET_KEY])
	made.source_entity = GameplayWireReader.entity_from(wire[SOURCE_KEY])
	made.causer_entity = GameplayWireReader.entity_from(wire[CAUSER_KEY])

	if (
		not GameplayWireReader.tags_are_named(wire[SOURCE_TAGS_KEY])
		or not GameplayWireReader.tags_are_named(wire[TARGET_TAGS_KEY])
	):
		return null
	made.source_tags = GameplayWireReader.tags_from(wire[SOURCE_TAGS_KEY])
	made.target_tags = GameplayWireReader.tags_from(wire[TARGET_TAGS_KEY])

	made.raw_magnitude = float(wire[RAW_KEY])
	made.normalized_magnitude = float(wire[NORMALIZED_KEY])
	made.effect_level = float(wire[EFFECT_LEVEL_KEY])
	made.ability_level = float(wire[ABILITY_LEVEL_KEY])
	made.stack_count = int(wire[STACK_KEY])
	made.location = wire[LOCATION_KEY]
	made.has_location = bool(wire[HAS_LOCATION_KEY])
	return made


## The type this contract declares for each key.
static func _expected() -> Dictionary[String, int]:
	return {
		TAG_KEY: TYPE_STRING,
		MATCHED_KEY: TYPE_STRING,
		INSTIGATOR_KEY: TYPE_INT,
		TARGET_KEY: TYPE_INT,
		SOURCE_KEY: TYPE_INT,
		CAUSER_KEY: TYPE_INT,
		RAW_KEY: TYPE_FLOAT,
		NORMALIZED_KEY: TYPE_FLOAT,
		EFFECT_LEVEL_KEY: TYPE_FLOAT,
		ABILITY_LEVEL_KEY: TYPE_FLOAT,
		STACK_KEY: TYPE_INT,
		SOURCE_TAGS_KEY: TYPE_ARRAY,
		TARGET_TAGS_KEY: TYPE_ARRAY,
		LOCATION_KEY: TYPE_VECTOR3,
		HAS_LOCATION_KEY: TYPE_BOOL,
	}
