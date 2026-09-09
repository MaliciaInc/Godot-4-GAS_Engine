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
		if not wire.has(key) or not is_a(wire[key], expected[key]):
			return false
	return true


## Whether one value is the kind the contract asked for.
##
## Numbers are one family here, and that is not leniency. This addon's wire
## is JSON and JSON has a single number type: every integer written to one
## comes back a float. A contract declaring TYPE_INT and comparing types
## exactly therefore refuses every message that has actually crossed a wire -
## which is what it did, and what nothing could see for as long as both ends
## of every test lived in one process.
##
## An integer contract still refuses a number with a fraction in it. A count
## that arrived as 2.5 is a machine that disagrees about the contract, not
## one that wrote its integers the way JSON writes them.
##
## A string contract accepts a StringName for the same kind of reason: which
## of the two a name is written as is an engine-side interning detail, and a
## format that made the far side care about it would be a format with an
## opinion about somebody else's memory.
static func is_a(value: Variant, kind: int) -> bool:
	var actual: int = typeof(value)
	if kind == TYPE_INT:
		if actual == TYPE_INT:
			return true
		return actual == TYPE_FLOAT and float(value) == floor(float(value))
	if kind == TYPE_FLOAT:
		return actual == TYPE_FLOAT or actual == TYPE_INT
	if kind == TYPE_STRING:
		return actual == TYPE_STRING or actual == TYPE_STRING_NAME
	return actual == kind


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


## A fixed-length list of numbers, or nothing when the wire said otherwise.
##
## What a vector crosses as. JSON has no vectors: `JSON.stringify` writes a
## Vector3 as the text `(3, 0, 0)` and the far side reads back a String, so a
## format that put one on the wire was a format whose positions never arrived.
## Numbers do arrive, and how many of them there are is the contract.
##
## Empty means refused, which a caller can tell from a real reading because a
## real one is never empty: a contract that asked for two numbers and got none
## did not get two.
static func numbers_from(said: Variant, how_many: int) -> PackedFloat64Array:
	var read: PackedFloat64Array = PackedFloat64Array()
	if not said is Array:
		return read
	var listed: Array = said
	if listed.size() != how_many:
		return read
	for one: Variant in listed:
		if typeof(one) != TYPE_FLOAT and typeof(one) != TYPE_INT:
			return PackedFloat64Array()
		read.append(float(one))
	return read


## A two-dimensional vector as the numbers a wire carries.
static func numbers_of_2d(value: Vector2) -> Array:
	return [value.x, value.y]


## And a three-dimensional one.
static func numbers_of_3d(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


## What an identity says, or the value that means nobody.
static func entity_said(id: GameplayNetEntityId) -> int:
	return id.to_wire() if id != null else GameplayNetEntityId.NONE


static func definition_said(id: GameplayNetDefinitionId) -> int:
	return id.to_wire() if id != null else GameplayNetDefinitionId.NONE
