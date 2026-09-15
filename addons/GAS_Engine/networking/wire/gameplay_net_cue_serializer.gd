## A cue onto a wire and back.
##
## Shaped like the reference's own cue parameters: the tag, then thirteen
## presence bits, then only the fields that are not their defaults - a magnitude
## of zero, a level of zero and a stack of one cost nothing. The two tag
## snapshots cross as name lists, and the location as a quantized position.
##
## `source_object` and `causer` never cross. Their identities do, and a peer that
## cannot resolve one is handed nothing rather than something else.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayNetCueSerializer extends RefCounted

## Which fields a cue carries, one bit each, in this order.
enum Carries {
	MATCHED,
	INSTIGATOR,
	TARGET,
	SOURCE,
	CAUSER,
	RAW,
	NORMALIZED,
	EFFECT_LEVEL,
	ABILITY_LEVEL,
	STACK,
	SOURCE_TAGS,
	TARGET_TAGS,
	LOCATION,
}

const CARRIES_BITS: int = 13

const MOST_TAGS: int = 255


static func write(writer: GameplayNetBitWriter, cue: GameplayCueWire) -> void:
	writer.write_name(cue.cue_tag)
	var carries: Array[bool] = [
		cue.matched_cue_tag != &"",
		_named(cue.instigator),
		_named(cue.target),
		_named(cue.source_entity),
		_named(cue.causer_entity),
		cue.raw_magnitude != 0.0,
		cue.normalized_magnitude != 0.0,
		cue.effect_level != 0.0,
		cue.ability_level != 0.0,
		cue.stack_count != 1,
		not cue.source_tags.is_empty(),
		not cue.target_tags.is_empty(),
		cue.has_location,
	]
	var mask: int = 0
	for index: int in carries.size():
		if carries[index]:
			mask |= 1 << index
	writer.write_bits(mask, CARRIES_BITS)

	if carries[Carries.MATCHED]:
		# The answering tag is most often the requested one; saying so is a bit.
		var same: bool = cue.matched_cue_tag == cue.cue_tag
		writer.write_bool(same)
		if not same:
			writer.write_name(cue.matched_cue_tag)
	if carries[Carries.INSTIGATOR]:
		writer.write_signed(cue.instigator.value)
	if carries[Carries.TARGET]:
		writer.write_signed(cue.target.value)
	if carries[Carries.SOURCE]:
		writer.write_signed(cue.source_entity.value)
	if carries[Carries.CAUSER]:
		writer.write_signed(cue.causer_entity.value)
	if carries[Carries.RAW]:
		writer.write_float32(cue.raw_magnitude)
	if carries[Carries.NORMALIZED]:
		writer.write_float32(cue.normalized_magnitude)
	if carries[Carries.EFFECT_LEVEL]:
		writer.write_float32(cue.effect_level)
	if carries[Carries.ABILITY_LEVEL]:
		writer.write_float32(cue.ability_level)
	if carries[Carries.STACK]:
		writer.write_signed(cue.stack_count)
	if carries[Carries.SOURCE_TAGS]:
		writer.write_names(cue.source_tags, MOST_TAGS)
	if carries[Carries.TARGET_TAGS]:
		writer.write_names(cue.target_tags, MOST_TAGS)
	if carries[Carries.LOCATION]:
		GameplayNetQuantize.write_position_3d(writer, cue.location)


## The cue back, or null with the reader failed.
static func read(reader: GameplayNetBitReader) -> GameplayCueWire:
	var made: GameplayCueWire = GameplayCueWire.new()
	made.cue_tag = reader.read_name()
	var mask: int = reader.read_bits(CARRIES_BITS)

	if _has(mask, Carries.MATCHED):
		made.matched_cue_tag = made.cue_tag if reader.read_bool() else reader.read_name()
	if _has(mask, Carries.INSTIGATOR):
		made.instigator = _entity(reader)
	if _has(mask, Carries.TARGET):
		made.target = _entity(reader)
	if _has(mask, Carries.SOURCE):
		made.source_entity = _entity(reader)
	if _has(mask, Carries.CAUSER):
		made.causer_entity = _entity(reader)
	if _has(mask, Carries.RAW):
		made.raw_magnitude = reader.read_float32()
	if _has(mask, Carries.NORMALIZED):
		made.normalized_magnitude = reader.read_float32()
	if _has(mask, Carries.EFFECT_LEVEL):
		made.effect_level = reader.read_float32()
	if _has(mask, Carries.ABILITY_LEVEL):
		made.ability_level = reader.read_float32()
	if _has(mask, Carries.STACK):
		made.stack_count = reader.read_signed()
	if _has(mask, Carries.SOURCE_TAGS):
		made.source_tags = reader.read_names(MOST_TAGS)
	if _has(mask, Carries.TARGET_TAGS):
		made.target_tags = reader.read_names(MOST_TAGS)
	if _has(mask, Carries.LOCATION):
		made.location = GameplayNetQuantize.read_position_3d(reader)
		made.has_location = true
	return made if reader.is_ok() else null


static func _has(mask: int, which: GameplayNetCueSerializer.Carries) -> bool:
	return (mask & (1 << which)) != 0


static func _named(id: GameplayNetEntityId) -> bool:
	return id != null and id.is_valid()


static func _entity(reader: GameplayNetBitReader) -> GameplayNetEntityId:
	var value: int = reader.read_signed()
	if value == GameplayNetEntityId.NONE:
		reader.fail()
	return GameplayNetEntityId.of(value)
