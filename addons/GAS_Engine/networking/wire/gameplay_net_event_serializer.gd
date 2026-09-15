## A gameplay event onto a wire and back.
##
## The tag always, then seven presence bits, then only what they vouch for -
## the reference's way with a structure whose fields are mostly empty. An event
## that names no instigator, no optional objects and carries no magnitude is a
## tag and seven zero bits.
##
## Malformed input is refused rather than repaired: a presence bit followed by
## the value that means nothing, or an event with no tag, fails the reader.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayNetEventSerializer extends RefCounted

## Which fields an event carries, one bit each, in this order.
enum Carries {
	INSTIGATOR,
	TARGET,
	OPTIONAL,
	OPTIONAL_TWO,
	MAGNITUDE,
	INSTIGATOR_TAGS,
	TARGET_TAGS,
}

const CARRIES_BITS: int = 7

## How many tags one snapshot of one side may carry.
const MOST_TAGS: int = 255


static func write(writer: GameplayNetBitWriter, said: GameplayEventWire) -> void:
	writer.write_name(said.event_tag)
	var carries: Array[bool] = [
		_named(said.instigator),
		_named(said.target),
		_defined(said.optional_definition),
		_defined(said.optional_definition2),
		said.magnitude != 0.0,
		not said.instigator_tags.is_empty(),
		not said.target_tags.is_empty(),
	]
	var mask: int = 0
	for index: int in carries.size():
		if carries[index]:
			mask |= 1 << index
	writer.write_bits(mask, CARRIES_BITS)
	if carries[Carries.INSTIGATOR]:
		writer.write_signed(said.instigator.value)
	if carries[Carries.TARGET]:
		writer.write_signed(said.target.value)
	if carries[Carries.OPTIONAL]:
		writer.write_u32(said.optional_definition.value)
	if carries[Carries.OPTIONAL_TWO]:
		writer.write_u32(said.optional_definition2.value)
	if carries[Carries.MAGNITUDE]:
		writer.write_float32(said.magnitude)
	if carries[Carries.INSTIGATOR_TAGS]:
		writer.write_names(said.instigator_tags, MOST_TAGS)
	if carries[Carries.TARGET_TAGS]:
		writer.write_names(said.target_tags, MOST_TAGS)


## The event back, or null with the reader failed.
static func read(reader: GameplayNetBitReader) -> GameplayEventWire:
	var made: GameplayEventWire = GameplayEventWire.new()
	made.event_tag = reader.read_name()
	var mask: int = reader.read_bits(CARRIES_BITS)
	if _has(mask, Carries.INSTIGATOR):
		made.instigator = _entity(reader)
	if _has(mask, Carries.TARGET):
		made.target = _entity(reader)
	if _has(mask, Carries.OPTIONAL):
		made.optional_definition = _definition(reader)
	if _has(mask, Carries.OPTIONAL_TWO):
		made.optional_definition2 = _definition(reader)
	if _has(mask, Carries.MAGNITUDE):
		made.magnitude = reader.read_float32()
	if _has(mask, Carries.INSTIGATOR_TAGS):
		made.instigator_tags = reader.read_names(MOST_TAGS)
	if _has(mask, Carries.TARGET_TAGS):
		made.target_tags = reader.read_names(MOST_TAGS)
	return made if reader.is_ok() else null


static func _has(mask: int, which: GameplayNetEventSerializer.Carries) -> bool:
	return (mask & (1 << which)) != 0


static func _named(id: GameplayNetEntityId) -> bool:
	return id != null and id.is_valid()


static func _defined(id: GameplayNetDefinitionId) -> bool:
	return id != null and id.is_valid()


## An identity behind a presence bit. The value that means nobody is not an
## identity a writer puts behind one.
static func _entity(reader: GameplayNetBitReader) -> GameplayNetEntityId:
	var value: int = reader.read_signed()
	if value == GameplayNetEntityId.NONE:
		reader.fail()
	return GameplayNetEntityId.of(value)


static func _definition(reader: GameplayNetBitReader) -> GameplayNetDefinitionId:
	var value: int = reader.read_u32()
	if value == GameplayNetDefinitionId.NONE:
		reader.fail()
	return GameplayNetDefinitionId.from_wire(value)
