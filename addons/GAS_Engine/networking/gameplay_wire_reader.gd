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
		if actual != TYPE_FLOAT:
			return false
		# Assigned rather than converted. `float(x)` on a Variant is a
		# conversion the compiler cannot check, and this whole file exists
		# to be the place where wire values ARE checked - so the one step
		# that leaves Variant behind is taken after `typeof` has said what
		# the value is, by an assignment the compiler can see is sound.
		var number: float = value
		return number == floor(number)
	if kind == TYPE_FLOAT:
		return actual == TYPE_FLOAT or actual == TYPE_INT
	if kind == TYPE_STRING:
		return actual == TYPE_STRING or actual == TYPE_STRING_NAME
	return actual == kind


## A whole number off a wire, or `fallback` when the wire did not carry one.
##
## `is_a` first, and that is the point rather than a formality: `int()`
## answers 0 for a string, for a dictionary and for null alike, so a wire
## that said `"five"` where a count belongs used to become a count of zero
## and be applied. It is now the fallback, which is what a reader that was
## told nothing usable should answer.
static func number_from(value: Variant, fallback: int = 0) -> int:
	if not is_a(value, TYPE_INT):
		return fallback
	if typeof(value) == TYPE_INT:
		# Taken as it is. A float cannot hold a whole number past 2^53, so
		# converting one that already arrived as an integer would be this
		# reader changing a value nobody asked it to change.
		var exact: int = value
		return exact
	# A JSON wire has one number type, so an integer written to one comes
	# back a float, and that is the reading this converts.
	var number: float = value
	return int(number)


## A fractional number off a wire, or `fallback`, checked the same way.
static func fraction_from(value: Variant, fallback: float = 0.0) -> float:
	if not is_a(value, TYPE_FLOAT):
		return fallback
	var number: float = value
	return number


## A whole number under one key of a wire, or `fallback`.
##
## The key form as well as the value form because the call sites are
## `said.get(KEY, default)` and writing the default twice is how the two
## halves come to disagree.
static func number_in(said: Dictionary, key: String, fallback: int = 0) -> int:
	return number_from(said.get(key, fallback), fallback)


## A fractional number under one key of a wire, or `fallback`.
static func fraction_in(said: Dictionary, key: String, fallback: float = 0.0) -> float:
	return fraction_from(said.get(key, fallback), fallback)


## An entity identity, or null when the wire said there was none.
static func entity_from(value: Variant) -> GameplayNetEntityId:
	var named: int = number_from(value, GameplayNetEntityId.NONE)
	return GameplayNetEntityId.from_wire(named) if named != GameplayNetEntityId.NONE else null


## A definition identity, or null when the wire said there was none.
static func definition_from(value: Variant) -> GameplayNetDefinitionId:
	var named: int = number_from(value, GameplayNetDefinitionId.NONE)
	if named == GameplayNetDefinitionId.NONE:
		return null
	return GameplayNetDefinitionId.from_wire(named)


## Whether every entry of a wire tag list is a name.
##
## Asked before converting rather than during: a converter that stopped at the
## first bad entry would hand a receiver a list that is a subset of what was
## sent, with nothing to say so.
static func tags_are_named(value: Variant) -> bool:
	if not value is Array:
		return false
	var listed: Array = value
	for entry: Variant in listed:
		if typeof(entry) != TYPE_STRING and typeof(entry) != TYPE_STRING_NAME:
			return false
	return true


## A validated tag list, as names.
static func tags_from(value: Variant) -> Array[StringName]:
	var read: Array[StringName] = []
	if not value is Array:
		return read
	var listed: Array = value
	for entry: Variant in listed:
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
		var number: float = one
		read.append(number)
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
