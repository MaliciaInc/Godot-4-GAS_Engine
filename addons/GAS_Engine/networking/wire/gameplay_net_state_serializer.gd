## One entity's reading, and each running effect in it, onto a wire and back.
##
## Shaped like the reference's replication of the same things. Attributes cross
## as name and 32-bit value, the width the reference replicates an attribute
## at. Tags cross as name and count. Grants cross as definition identities.
## Effects cross the way the reference's fast array crosses active effects: each
## by the identity it keeps for its whole life, with only the readings that are
## not their defaults behind a presence bit, and the ones that went away by
## identity alone.
##
## Twelve presence bits say which of the twelve lists hold anything, so a delta
## that moved one attribute is that attribute and a dozen zero bits - not twelve
## empty containers spelled out.
##
## Every list is bounded, on both sides, and past its bound the packet is
## refused rather than trimmed: a reading with its last effects quietly missing
## is two machines disagreeing about a character with nothing to say so.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayNetStateSerializer extends RefCounted

## Which lists a reading holds anything in, one bit each, in this order.
enum Holds {
	ATTRIBUTES,
	CURRENT_ATTRIBUTES,
	TAGS,
	ABILITIES,
	RUNNING_ABILITIES,
	EFFECTS,
	CUES,
	REMOVED_TAGS,
	REVOKED_ABILITIES,
	STOPPED_ABILITIES,
	ENDED_EFFECTS,
	ENDED_CUES,
}

const HOLDS_BITS: int = 12

## Which of one effect's readings differ from their defaults.
enum Differs { STACKS, SECONDS, TURNS, INHIBITED }

const DIFFERS_BITS: int = 4

## How many entries one list of one reading may hold.
const MOST_ENTRIES: int = 1023


#region Out
static func write(writer: GameplayNetBitWriter, state: GameplayNetState) -> void:
	writer.write_bool(state.is_delta())
	writer.write_bits(_holds(state), HOLDS_BITS)

	if not state.attributes.is_empty():
		_write_values(writer, state.attributes)
	if not state.current_attributes.is_empty():
		_write_values(writer, state.current_attributes)
	if not state.tags.is_empty():
		writer.write_count(state.tags.size(), MOST_ENTRIES)
		for tag: StringName in state.tags:
			writer.write_name(tag)
			writer.write_packed(state.tags[tag])
	if not state.abilities.is_empty():
		_write_definitions(writer, state.abilities)
	if not state.running_abilities.is_empty():
		_write_definitions(writer, state.running_abilities)
	if not state.effects.is_empty():
		writer.write_count(state.effects.size(), MOST_ENTRIES)
		for effect: GameplayNetEffectState in state.effects:
			_write_effect(writer, effect)
	if not state.cues.is_empty():
		writer.write_names(state.cues, MOST_ENTRIES)
	if not state.removed_tags.is_empty():
		writer.write_names(state.removed_tags, MOST_ENTRIES)
	if not state.revoked_abilities.is_empty():
		_write_definitions(writer, state.revoked_abilities)
	if not state.stopped_abilities.is_empty():
		_write_definitions(writer, state.stopped_abilities)
	if not state.ended_effects.is_empty():
		writer.write_count(state.ended_effects.size(), MOST_ENTRIES)
		for id: int in state.ended_effects:
			writer.write_packed(id)
	if not state.ended_cues.is_empty():
		writer.write_names(state.ended_cues, MOST_ENTRIES)


static func _holds(state: GameplayNetState) -> int:
	var lists: Array[bool] = [
		not state.attributes.is_empty(),
		not state.current_attributes.is_empty(),
		not state.tags.is_empty(),
		not state.abilities.is_empty(),
		not state.running_abilities.is_empty(),
		not state.effects.is_empty(),
		not state.cues.is_empty(),
		not state.removed_tags.is_empty(),
		not state.revoked_abilities.is_empty(),
		not state.stopped_abilities.is_empty(),
		not state.ended_effects.is_empty(),
		not state.ended_cues.is_empty(),
	]
	var mask: int = 0
	for index: int in lists.size():
		if lists[index]:
			mask |= 1 << index
	return mask


static func _write_values(writer: GameplayNetBitWriter, values: Dictionary[StringName, float]) -> void:
	writer.write_count(values.size(), MOST_ENTRIES)
	for name: StringName in values:
		writer.write_name(name)
		writer.write_float32(values[name])


static func _write_definitions(writer: GameplayNetBitWriter, ids: Array[int]) -> void:
	writer.write_count(ids.size(), MOST_ENTRIES)
	for id: int in ids:
		writer.write_u32(id)


static func _write_effect(writer: GameplayNetBitWriter, effect: GameplayNetEffectState) -> void:
	if not effect.is_valid():
		writer.fail()
		return
	writer.write_packed(effect.id)
	writer.write_u32(effect.definition)
	var differs: int = 0
	if effect.stack_count != 1:
		differs |= 1 << Differs.STACKS
	if effect.time_remaining != 0.0:
		differs |= 1 << Differs.SECONDS
	if effect.remaining_turns != 0:
		differs |= 1 << Differs.TURNS
	if effect.inhibited:
		differs |= 1 << Differs.INHIBITED
	writer.write_bits(differs, DIFFERS_BITS)
	if effect.stack_count != 1:
		writer.write_signed(effect.stack_count)
	if effect.time_remaining != 0.0:
		writer.write_float32(effect.time_remaining)
	if effect.remaining_turns != 0:
		writer.write_signed(effect.remaining_turns)
#endregion


#region In
## A reading back, or null with the reader failed.
static func read(reader: GameplayNetBitReader) -> GameplayNetState:
	var made: GameplayNetState = GameplayNetState.delta() if reader.read_bool() else GameplayNetState.snapshot()
	var holds: int = reader.read_bits(HOLDS_BITS)

	if _has(holds, Holds.ATTRIBUTES):
		made.attributes.assign(_read_values(reader))
	if _has(holds, Holds.CURRENT_ATTRIBUTES):
		made.current_attributes.assign(_read_values(reader))
	if _has(holds, Holds.TAGS):
		var count: int = reader.read_count(MOST_ENTRIES)
		for _entry: int in count:
			var tag: StringName = reader.read_name()
			made.tags[tag] = reader.read_packed()
	if _has(holds, Holds.ABILITIES):
		made.abilities = _read_definitions(reader)
	if _has(holds, Holds.RUNNING_ABILITIES):
		made.running_abilities = _read_definitions(reader)
	if _has(holds, Holds.EFFECTS):
		var count: int = reader.read_count(MOST_ENTRIES)
		for _entry: int in count:
			made.effects.append(_read_effect(reader))
	if _has(holds, Holds.CUES):
		made.cues = reader.read_names(MOST_ENTRIES)
	if _has(holds, Holds.REMOVED_TAGS):
		made.removed_tags = reader.read_names(MOST_ENTRIES)
	if _has(holds, Holds.REVOKED_ABILITIES):
		made.revoked_abilities = _read_definitions(reader)
	if _has(holds, Holds.STOPPED_ABILITIES):
		made.stopped_abilities = _read_definitions(reader)
	if _has(holds, Holds.ENDED_EFFECTS):
		var count: int = reader.read_count(MOST_ENTRIES)
		for _entry: int in count:
			made.ended_effects.append(reader.read_packed())
	if _has(holds, Holds.ENDED_CUES):
		made.ended_cues = reader.read_names(MOST_ENTRIES)

	return made if reader.is_ok() else null


static func _has(holds: int, which: GameplayNetStateSerializer.Holds) -> bool:
	return (holds & (1 << which)) != 0


static func _read_values(reader: GameplayNetBitReader) -> Dictionary[StringName, float]:
	var read: Dictionary[StringName, float] = {}
	var count: int = reader.read_count(MOST_ENTRIES)
	for _entry: int in count:
		var name: StringName = reader.read_name()
		read[name] = reader.read_float32()
	return read


static func _read_definitions(reader: GameplayNetBitReader) -> Array[int]:
	var read: Array[int] = []
	var count: int = reader.read_count(MOST_ENTRIES)
	for _entry: int in count:
		read.append(reader.read_u32())
	return read


## One effect back. Null-free: an effect that does not read as one fails the
## reader, and the whole reading goes with it.
static func _read_effect(reader: GameplayNetBitReader) -> GameplayNetEffectState:
	var made: GameplayNetEffectState = GameplayNetEffectState.of(reader.read_packed(), reader.read_u32())
	var differs: int = reader.read_bits(DIFFERS_BITS)
	if (differs & (1 << Differs.STACKS)) != 0:
		made.stack_count = reader.read_signed()
	if (differs & (1 << Differs.SECONDS)) != 0:
		made.time_remaining = reader.read_float32()
	if (differs & (1 << Differs.TURNS)) != 0:
		made.remaining_turns = reader.read_signed()
	made.inhibited = (differs & (1 << Differs.INHIBITED)) != 0
	if reader.is_ok() and not made.is_valid():
		reader.fail()
	return made
#endregion
