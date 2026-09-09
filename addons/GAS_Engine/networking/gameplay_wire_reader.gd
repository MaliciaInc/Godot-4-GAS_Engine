## Reading primitives back off a wire, checked rather than trusted.
##
## Every wire format in this addon has the same three problems: is the key
## there and of the type the contract declares, is a list of tags actually a
## list of names, and is a numeric identity a real one or the value that means
## nobody. Written once here because two copies of these are two contracts that
## drift, and the second one drifts silently - a format whose reader is a
## little more forgiving than the other machine's writer looks like it works
## until the day it matters.
##
## Static and stateless. A codec calls these; nothing holds one.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayWireReader extends RefCounted


## Whether every key is present and of the type the contract declares.
##
## `expected` maps each key to its `TYPE_*` constant. A wire missing a key, or
## carrying one of the wrong type, is a message from a machine that disagrees
## about the contract - and a reader that repaired it would be inventing
## something nobody sent.
static func has_shape(wire: Dictionary, expected: Dictionary[String, int]) -> bool:
	for key: String in expected:
		if not wire.has(key) or typeof(wire[key]) != expected[key]:
			return false
	return true


## An entity identity, or null when the wire said there was none.
static func entity_from(value: Variant) -> GameplayNetEntityId:
	var named: int = int(value)
	return GameplayNetEntityId.from_wire(named) if named != GameplayNetEntityId.NONE else null


## A definition identity, or null when the wire said there was none.
static func definition_from(value: Variant) -> GameplayNetDefinitionId:
	var named: int = int(value)
	if named == GameplayNetDefinitionId.NONE:
		return null
	return GameplayNetDefinitionId.from_wire(named)


## Whether every entry of a wire tag list is a name.
##
## Asked before converting rather than during: a converter that stopped at the
## first bad entry would hand a receiver a list that is a subset of what was
## sent, with nothing to say so.
static func tags_are_named(value: Variant) -> bool:
	for entry: Variant in (value as Array):
		if typeof(entry) != TYPE_STRING and typeof(entry) != TYPE_STRING_NAME:
			return false
	return true


## A validated tag list, as names.
static func tags_from(value: Variant) -> Array[StringName]:
	var read: Array[StringName] = []
	for entry: Variant in (value as Array):
		read.append(StringName(str(entry)))
	return read


## Tags as plain strings, because a StringName is an engine-side interning
## detail rather than something a wire format should assume on both ends.
static func as_strings(tags: Array[StringName]) -> Array:
	var said: Array = []
	for tag: StringName in tags:
		said.append(String(tag))
	return said


## What an identity says, or the value that means nobody.
static func entity_said(id: GameplayNetEntityId) -> int:
	return id.to_wire() if id != null else GameplayNetEntityId.NONE


static func definition_said(id: GameplayNetDefinitionId) -> int:
	return id.to_wire() if id != null else GameplayNetDefinitionId.NONE
