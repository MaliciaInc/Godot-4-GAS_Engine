## A gameplay event in the only shape a wire can carry.
##
## `GameplayEventData` holds Nodes and Objects, and neither crosses a network:
## an ObjectID is a slot in one process's table and means something else in the
## next one. This is the same event said in identities, tags and numbers, which
## every machine can agree about.
##
## It is a separate class rather than a method on the payload for one reason:
## turning a Node into an identity is something only `GameplayNetRegistry` can
## do, and a payload that reached for a network singleton would be a payload no
## single-player game could construct. The conversion lives with the network
## runtime; this is only the shape it converts into.
##
## Malformed input is refused rather than repaired. A field of the wrong type is
## a message from a machine that disagrees about the contract, and guessing what
## it meant is how one bad sender becomes two.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayEventWire extends RefCounted

## The keys, spelled once and namespaced.
##
## A dictionary whose keys are written at both ends is a contract with two
## authors, so they live here. The prefix is not decoration: `magnitude` and
## `target_tags` are words other parts of this addon use for their own
## unrelated purposes, and a wire key that collides with one of those is a
## rename waiting to break a format.
const TAG_KEY: String = "ev.tag"
const INSTIGATOR_KEY: String = "ev.instigator"
const TARGET_KEY: String = "ev.target"
const OPTIONAL_KEY: String = "ev.optional"
const OPTIONAL_TWO_KEY: String = "ev.optional2"
const INSTIGATOR_TAGS_KEY: String = "ev.instigator_tags"
const TARGET_TAGS_KEY: String = "ev.target_tags"
const MAGNITUDE_KEY: String = "ev.magnitude"
const TARGET_DATA_KEY: String = "ev.target_data"
const CONTEXT_KEY: String = "ev.context"

var event_tag: StringName = &""

## Who caused it and who it is about, as identities the receiving machine can
## resolve against its own registry. Null when the sender could not name them,
## which is not the same as naming nobody.
var instigator: GameplayNetEntityId = null
var target: GameplayNetEntityId = null

## The optional objects, but only when the registry could name them as
## definitions. An object it does not know is left out rather than turned into
## its own address or its name: a receiver resolving either would get something
## that is not the thing.
var optional_definition: GameplayNetDefinitionId = null
var optional_definition2: GameplayNetDefinitionId = null

## The two snapshots, which cross as themselves - tags are already names every
## machine agrees about.
var instigator_tags: Array[StringName] = []
var target_tags: Array[StringName] = []

var magnitude: float = 0.0

## What the event was aimed at, and where it came from, each already reduced to
## primitives by whoever owns that shape.
var target_data: Dictionary = {}
var context: Dictionary = {}


## Primitives only. Nothing here is an object, so nothing here means anything
## different on the machine that reads it.
func to_wire() -> Dictionary:
	return {
		TAG_KEY: String(event_tag),
		INSTIGATOR_KEY: instigator.to_wire() if instigator != null else GameplayNetEntityId.NONE,
		TARGET_KEY: target.to_wire() if target != null else GameplayNetEntityId.NONE,
		OPTIONAL_KEY: (
			optional_definition.to_wire()
			if optional_definition != null
			else GameplayNetDefinitionId.NONE
		),
		OPTIONAL_TWO_KEY: (
			optional_definition2.to_wire()
			if optional_definition2 != null
			else GameplayNetDefinitionId.NONE
		),
		INSTIGATOR_TAGS_KEY: _as_strings(instigator_tags),
		TARGET_TAGS_KEY: _as_strings(target_tags),
		MAGNITUDE_KEY: magnitude,
		TARGET_DATA_KEY: target_data.duplicate(true),
		CONTEXT_KEY: context.duplicate(true),
	}


## The same event back, or null.
##
## Every field is checked. A wire with a tag that is not a string, or a tag list
## holding something that is not one, is a message from a machine that disagrees
## about this contract - and a receiver that repaired it would be inventing an
## event nobody sent.
static func from_wire(wire: Dictionary) -> GameplayEventWire:
	if not _has_shape(wire):
		return null

	var made: GameplayEventWire = GameplayEventWire.new()
	made.event_tag = StringName(str(wire[TAG_KEY]))
	if made.event_tag == &"":
		return null

	made.instigator = _entity_from(wire[INSTIGATOR_KEY])
	made.target = _entity_from(wire[TARGET_KEY])
	made.optional_definition = _definition_from(wire[OPTIONAL_KEY])
	made.optional_definition2 = _definition_from(wire[OPTIONAL_TWO_KEY])

	if (
		not _tags_are_named(wire[INSTIGATOR_TAGS_KEY])
		or not _tags_are_named(wire[TARGET_TAGS_KEY])
	):
		return null
	made.instigator_tags = _tags_from(wire[INSTIGATOR_TAGS_KEY])
	made.target_tags = _tags_from(wire[TARGET_TAGS_KEY])

	made.magnitude = float(wire[MAGNITUDE_KEY])
	made.target_data = (wire[TARGET_DATA_KEY] as Dictionary).duplicate(true)
	made.context = (wire[CONTEXT_KEY] as Dictionary).duplicate(true)
	return made


## Whether every key is present and of the type this contract declares.
static func _has_shape(wire: Dictionary) -> bool:
	var expected: Dictionary[String, int] = {
		TAG_KEY: TYPE_STRING,
		INSTIGATOR_KEY: TYPE_INT,
		TARGET_KEY: TYPE_INT,
		OPTIONAL_KEY: TYPE_INT,
		OPTIONAL_TWO_KEY: TYPE_INT,
		INSTIGATOR_TAGS_KEY: TYPE_ARRAY,
		TARGET_TAGS_KEY: TYPE_ARRAY,
		MAGNITUDE_KEY: TYPE_FLOAT,
		TARGET_DATA_KEY: TYPE_DICTIONARY,
		CONTEXT_KEY: TYPE_DICTIONARY,
	}
	for key: String in expected:
		if not wire.has(key) or typeof(wire[key]) != expected[key]:
			return false
	return true


## An identity, or null when the wire said there was none.
static func _entity_from(value: Variant) -> GameplayNetEntityId:
	var named: int = int(value)
	return GameplayNetEntityId.from_wire(named) if named != GameplayNetEntityId.NONE else null


static func _definition_from(value: Variant) -> GameplayNetDefinitionId:
	var named: int = int(value)
	return GameplayNetDefinitionId.from_wire(named) if named != GameplayNetDefinitionId.NONE else null


## Whether every entry of a wire tag list is a name.
##
## Asked before converting rather than during: a converter that stopped at the
## first bad entry would hand a receiver a snapshot that is a subset of what was
## sent, with nothing to say so.
static func _tags_are_named(value: Variant) -> bool:
	for entry: Variant in (value as Array):
		if typeof(entry) != TYPE_STRING and typeof(entry) != TYPE_STRING_NAME:
			return false
	return true


## A validated tag list, as names.
static func _tags_from(value: Variant) -> Array[StringName]:
	var read: Array[StringName] = []
	for entry: Variant in (value as Array):
		read.append(StringName(str(entry)))
	return read


## Tags as plain strings, because a StringName is an engine-side interning
## detail rather than something a wire format should assume on both ends.
static func _as_strings(tags: Array[StringName]) -> Array:
	var said: Array = []
	for tag: StringName in tags:
		said.append(String(tag))
	return said
