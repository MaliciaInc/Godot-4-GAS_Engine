## The game's own data, carried without being read.
##
## `GameplayNetMessage.payload` is where a game's data travels beside the ability
## system's, and the ability system never interprets it. What it does own is the
## crossing, and the crossing keeps the rule the reference keeps everywhere it
## serializes something it did not author: nothing a receiver would have to
## construct is carried. A payload is values - nothing, a truth, a whole number,
## a fraction, text, a name, a vector - and lists and dictionaries of those, each
## behind four bits that say which, and each arriving as exactly the type it left
## as. A whole number is still a whole number on the far side and a vector is
## still a vector, which no text format ever managed.
##
## Bounded, because a payload is read whole before anything is done with it: so
## deep, so many entries, so much text. Anything past a bound, and any type
## outside the list, refuses the packet on the machine that tried to write it.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayNetPayloadSerializer extends RefCounted

## What one value is, in four bits.
enum Tag { NOTHING, NO, YES, WHOLE, FRACTION, TEXT, NAME, EMPTY_NAME, VECTOR2, VECTOR3, LIST, DICTIONARY }

const TAG_BITS: int = 4

## How deeply lists and dictionaries may nest.
const MOST_DEPTH: int = 8

## How many entries one list or dictionary may hold.
const MOST_ENTRIES: int = 256

## How long one piece of text may be.
const MOST_TEXT_BYTES: int = 4096


## A payload onto the wire. An empty one is one count of zero.
static func write(writer: GameplayNetBitWriter, payload: Dictionary) -> void:
	_write_dictionary(writer, payload, 0)


## A payload off the wire, or an empty one with the reader failed.
static func read(reader: GameplayNetBitReader) -> Dictionary:
	return _read_dictionary(reader, 0)


static func _write_dictionary(writer: GameplayNetBitWriter, listed: Dictionary, depth: int) -> void:
	writer.write_count(listed.size(), MOST_ENTRIES)
	for key: Variant in listed:
		_write_value(writer, key, depth)
		_write_value(writer, listed[key], depth)


static func _read_dictionary(reader: GameplayNetBitReader, depth: int) -> Dictionary:
	var made: Dictionary = {}
	var count: int = reader.read_count(MOST_ENTRIES)
	for _entry: int in count:
		var key: Variant = _read_value(reader, depth)
		var value: Variant = _read_value(reader, depth)
		if not reader.is_ok():
			return {}
		# Two entries under one key are not something a dictionary can have been
		# written from, so a packet carrying them was not written by a writer.
		if made.has(key):
			reader.fail()
			return {}
		made[key] = value
	return made


static func _write_value(writer: GameplayNetBitWriter, value: Variant, depth: int) -> void:
	if depth > MOST_DEPTH:
		writer.fail()
		return
	match typeof(value):
		TYPE_NIL:
			writer.write_bits(Tag.NOTHING, TAG_BITS)
		TYPE_BOOL:
			var truth: bool = value
			writer.write_bits(Tag.YES if truth else Tag.NO, TAG_BITS)
		TYPE_INT:
			var whole: int = value
			writer.write_bits(Tag.WHOLE, TAG_BITS)
			writer.write_signed(whole)
		TYPE_FLOAT:
			var fraction: float = value
			writer.write_bits(Tag.FRACTION, TAG_BITS)
			writer.write_float64(fraction)
		TYPE_STRING:
			var text: String = value
			if text.to_utf8_buffer().size() > MOST_TEXT_BYTES:
				writer.fail()
				return
			writer.write_bits(Tag.TEXT, TAG_BITS)
			writer.write_text(text)
		TYPE_STRING_NAME:
			var name: StringName = value
			writer.write_bits(Tag.EMPTY_NAME if name == &"" else Tag.NAME, TAG_BITS)
			if name != &"":
				writer.write_name(name)
		TYPE_VECTOR2:
			var flat: Vector2 = value
			writer.write_bits(Tag.VECTOR2, TAG_BITS)
			writer.write_float32(flat.x)
			writer.write_float32(flat.y)
		TYPE_VECTOR3:
			var spot: Vector3 = value
			writer.write_bits(Tag.VECTOR3, TAG_BITS)
			writer.write_float32(spot.x)
			writer.write_float32(spot.y)
			writer.write_float32(spot.z)
		TYPE_ARRAY:
			var items: Array = value
			writer.write_bits(Tag.LIST, TAG_BITS)
			writer.write_count(items.size(), MOST_ENTRIES)
			for item: Variant in items:
				_write_value(writer, item, depth + 1)
		TYPE_DICTIONARY:
			var nested: Dictionary = value
			writer.write_bits(Tag.DICTIONARY, TAG_BITS)
			_write_dictionary(writer, nested, depth + 1)
		_:
			writer.fail()


static func _read_value(reader: GameplayNetBitReader, depth: int) -> Variant:
	if depth > MOST_DEPTH:
		reader.fail()
		return null
	match reader.read_bits(TAG_BITS):
		Tag.NOTHING:
			return null
		Tag.NO:
			return false
		Tag.YES:
			return true
		Tag.WHOLE:
			return reader.read_signed()
		Tag.FRACTION:
			return reader.read_float64()
		Tag.TEXT:
			return reader.read_text(MOST_TEXT_BYTES)
		Tag.NAME:
			return reader.read_name()
		Tag.EMPTY_NAME:
			return &""
		Tag.VECTOR2:
			return Vector2(reader.read_float32(), reader.read_float32())
		Tag.VECTOR3:
			return Vector3(reader.read_float32(), reader.read_float32(), reader.read_float32())
		Tag.LIST:
			var items: Array = []
			var count: int = reader.read_count(MOST_ENTRIES)
			for _item: int in count:
				items.append(_read_value(reader, depth + 1))
			return items
		Tag.DICTIONARY:
			return _read_dictionary(reader, depth + 1)
	reader.fail()
	return null
