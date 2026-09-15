## The pieces a packet is made of, one at a time.
##
## Driven on the writer and the reader rather than through the codec, because a
## codec's refusal can be right for the wrong reason - a packet thrown out by the
## next check along looks exactly like a packet this one caught. Every piece is
## written and read back, and every refusal is the reader meeting exactly the one
## thing a writer never produces.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const TOLERANCE: float = 0.0001

## Half a centimetre and a little float32 room: the most a position moves by
## being rounded to the centimetre.
const CENTIMETRE_ROUNDING: float = 0.0051

const BIGGEST: int = 9223372036854775807
const SMALLEST: int = -9223372036854775807 - 1


#region Getting there
func _reader_of(writer: GameplayNetBitWriter) -> GameplayNetBitReader:
	var bytes: PackedByteArray = writer.finish()
	assert_true(writer.is_ok(), "the writer honoured everything it was asked")
	return GameplayNetBitReader.new(bytes)


func _bytes(listed: Array) -> PackedByteArray:
	var made: PackedByteArray = PackedByteArray()
	for one: Variant in listed:
		var byte: int = one
		made.append(byte)
	return made
#endregion


#region Bits and whole numbers
## Bits go in low first and come out in the order they went in.
func test_bits_come_back_in_the_order_they_went() -> void:
	var writer: GameplayNetBitWriter = GameplayNetBitWriter.new()
	writer.write_bool(true)
	writer.write_bits(5, 3)
	writer.write_bits(0xABCD, 16)
	writer.write_bits(0xFFFFFFFF, 32)

	var reader: GameplayNetBitReader = _reader_of(writer)

	assert_true(reader.read_bool(), "the flag")
	assert_eq(reader.read_bits(3), 5, "three bits")
	assert_eq(reader.read_bits(16), 0xABCD, "sixteen")
	assert_eq(reader.read_bits(32), 0xFFFFFFFF, "and thirty-two")
	assert_true(reader.is_ok() and reader.is_exhausted(), "and nothing is left over")


##     [what it is, the value, how many bytes it packs into]
func _packed_cases() -> Array:
	return [
		["zero", 0, 1],
		["the most one group holds", 127, 1],
		["one past it", 128, 2],
		["a count in the thousands", 1023, 2],
		["the largest there is", BIGGEST, 9],
	]


## A count costs as many groups of seven as its digits need.
func test_a_whole_number_packs_into_the_groups_it_needs(
	case: Array = use_parameters(_packed_cases())
) -> void:
	var described: String = case[0]
	var value: int = case[1]
	var groups: int = case[2]
	var writer: GameplayNetBitWriter = GameplayNetBitWriter.new()
	writer.write_packed(value)

	var bytes: PackedByteArray = writer.finish()

	assert_eq(bytes.size(), groups, "%s: in %d bytes" % [described, groups])
	assert_eq(GameplayNetBitReader.new(bytes).read_packed(), value, "%s: and back" % described)


## A signed number zig-zags, so both extremes and both small signs cross.
func test_a_signed_number_crosses_at_every_extreme() -> void:
	for value: int in [0, 1, -1, 63, -64, BIGGEST, SMALLEST]:
		var writer: GameplayNetBitWriter = GameplayNetBitWriter.new()
		writer.write_signed(value)
		var reader: GameplayNetBitReader = _reader_of(writer)
		assert_eq(reader.read_signed(), value, "%d crossed as itself" % value)
		assert_true(reader.is_exhausted(), "%d left nothing behind" % value)


## What a writer refuses to write rather than writing something close.
func test_a_writer_refuses_what_no_pattern_carries() -> void:
	var negative: GameplayNetBitWriter = GameplayNetBitWriter.new()
	negative.write_packed(-1)
	assert_false(negative.is_ok(), "a count below zero")
	assert_true(negative.finish().is_empty(), "and the packet is nothing at all")

	var wide: GameplayNetBitWriter = GameplayNetBitWriter.new()
	wide.write_u32(GameplayNetBitWriter.MOST_U32 + 1)
	assert_false(wide.is_ok(), "an identity past thirty-two bits")

	var crowded: GameplayNetBitWriter = GameplayNetBitWriter.new()
	crowded.write_count(65, 64)
	assert_false(crowded.is_ok(), "and a list past its bound")


## What a reader refuses, where a sender is allowed to be wrong.
func test_a_reader_refuses_a_number_no_writer_makes() -> void:
	var eleven_groups: PackedByteArray = _bytes([0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x00])
	var overflowing: PackedByteArray = _bytes([0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x03])

	var long: GameplayNetBitReader = GameplayNetBitReader.new(eleven_groups)
	long.read_packed()
	assert_false(long.is_ok(), "a number that never ends")

	var past: GameplayNetBitReader = GameplayNetBitReader.new(overflowing)
	past.read_signed()
	assert_false(past.is_ok(), "a number past sixty-four bits")

	var short: GameplayNetBitReader = GameplayNetBitReader.new(_bytes([0x05]))
	short.read_bits(16)
	assert_false(short.is_ok(), "a read past the end of the packet")
	assert_eq(short.read_bits(1), 0, "and every read after a failure answers nothing")


## A count is refused past its bound and past what the packet can still hold.
func test_a_count_is_refused_past_what_it_may_be() -> void:
	var writer: GameplayNetBitWriter = GameplayNetBitWriter.new()
	writer.write_packed(300)
	var bytes: PackedByteArray = writer.finish()

	var bounded: GameplayNetBitReader = GameplayNetBitReader.new(bytes)
	bounded.read_count(255)
	assert_false(bounded.is_ok(), "past its bound")

	var hollow: GameplayNetBitReader = GameplayNetBitReader.new(bytes)
	hollow.read_count(1000)
	assert_false(hollow.is_ok(), "and past what the packet has left to hold")
#endregion


#region Fractions
## A 32-bit float crosses bit for bit, and rounds what 32 bits round.
func test_a_float32_crosses_as_a_float32() -> void:
	var writer: GameplayNetBitWriter = GameplayNetBitWriter.new()
	writer.write_float32(0.5)
	writer.write_float32(0.1)
	writer.write_float64(0.1)

	var reader: GameplayNetBitReader = _reader_of(writer)

	assert_eq(reader.read_float32(), 0.5, "a value it holds exactly")
	assert_almost_eq(reader.read_float32(), 0.1, 0.0000001, "one it rounds, to its own width")
	assert_eq(reader.read_float64(), 0.1, "and a 64-bit one, exactly")
#endregion


#region Text and names
## Text crosses as UTF-8, whatever it spells.
func test_text_crosses_as_utf8() -> void:
	var writer: GameplayNetBitWriter = GameplayNetBitWriter.new()
	writer.write_bool(true)
	writer.write_text("Ñandú ✓ 𝄞")

	var reader: GameplayNetBitReader = _reader_of(writer)
	reader.read_bool()

	assert_eq(reader.read_text(), "Ñandú ✓ 𝄞", "every character of it")


##     [what is wrong with it, the bytes after the length]
func _bad_text_cases() -> Array:
	return [
		["an overlong encoding", [0xC0, 0x80]],
		["a surrogate", [0xED, 0xA0, 0x80]],
		["a continuation with nothing before it", [0x80]],
		["a sequence cut short", [0xE2, 0x82]],
		["a code point past the last one", [0xF4, 0x90, 0x80, 0x80]],
		["a NUL", [0x41, 0x00]],
	]


## Text that is not well-formed UTF-8 is refused before a String is made of it.
func test_malformed_utf8_is_refused(case: Array = use_parameters(_bad_text_cases())) -> void:
	var described: String = case[0]
	var raw: Array = case[1]
	var bytes: PackedByteArray = _bytes([raw.size()])
	bytes.append_array(_bytes(raw))

	var reader: GameplayNetBitReader = GameplayNetBitReader.new(bytes)
	reader.read_text()

	assert_false(reader.is_ok(), described)


## Text longer than a name may be is refused before anything is allocated for it.
func test_text_past_its_length_is_refused() -> void:
	var writer: GameplayNetBitWriter = GameplayNetBitWriter.new()
	writer.write_text("a".repeat(GameplayNetBitReader.MAX_TEXT_BYTES + 1))

	var reader: GameplayNetBitReader = GameplayNetBitReader.new(writer.finish())
	reader.read_text()

	assert_false(reader.is_ok(), "one byte too long")


## A name nobody agreed about is spelled once per packet and pointed back at after.
func test_a_name_is_spelled_once_and_pointed_back_at() -> void:
	var once: GameplayNetBitWriter = GameplayNetBitWriter.new()
	once.write_name(&"Status.Debuff.Slowed")
	var twice: GameplayNetBitWriter = GameplayNetBitWriter.new()
	twice.write_name(&"Status.Debuff.Slowed")
	twice.write_name(&"Status.Debuff.Slowed")

	var twice_bytes: PackedByteArray = twice.finish()
	var reader: GameplayNetBitReader = GameplayNetBitReader.new(twice_bytes)

	# Ten bits for the pointer, which a byte boundary rounds to two bytes at most -
	# against the twenty the text would have cost again.
	assert_lte(twice_bytes.size(), once.finish().size() + 2, "the second one is a pointer, not the text")
	assert_eq(reader.read_name(), &"Status.Debuff.Slowed", "the first")
	assert_eq(reader.read_name(), &"Status.Debuff.Slowed", "and the second")


## A name in the shared table is its position there, and a reader without the
## table cannot read one.
func test_a_shared_name_needs_the_shared_table() -> void:
	var names: GameplayNetNames = GameplayNetNames.of([&"Status.Burning", &"Status.Slowed"] as Array[StringName])
	var writer: GameplayNetBitWriter = GameplayNetBitWriter.new()
	writer.names = names
	writer.write_name(&"Status.Slowed")
	var bytes: PackedByteArray = writer.finish()

	assert_true(writer.used_shared_names, "it was written as a position")
	var with_table: GameplayNetBitReader = GameplayNetBitReader.new(bytes)
	with_table.names = names
	assert_eq(with_table.read_name(), &"Status.Slowed", "and read back with the table")

	var without: GameplayNetBitReader = GameplayNetBitReader.new(bytes)
	without.read_name()
	assert_false(without.is_ok(), "and refused without one")

	var nothing: GameplayNetBitWriter = GameplayNetBitWriter.new()
	nothing.write_name(&"")
	assert_false(nothing.is_ok(), "a name that says nothing is not written at all")


## The table is ordered by text and fingerprinted by what it holds.
func test_the_table_is_ordered_by_what_it_holds() -> void:
	var one_way: GameplayNetNames = GameplayNetNames.of([&"B.Two", &"A.One", &"C.Three"] as Array[StringName])
	var other_way: GameplayNetNames = GameplayNetNames.of([&"C.Three", &"A.One", &"B.Two"] as Array[StringName])
	var more: GameplayNetNames = GameplayNetNames.of([&"C.Three", &"A.One", &"B.Two", &"D.Four"] as Array[StringName])

	assert_eq(one_way.name_at(0), &"A.One", "first by text, not by who added it first")
	assert_eq(one_way.fingerprint, other_way.fingerprint, "the same names are the same table")
	assert_ne(one_way.fingerprint, more.fingerprint, "and one more name is a different one")
	assert_eq(one_way.index_of(&"Nobody.Added"), -1, "a name it does not hold has no position")


## The project's table holds the project's tags.
func test_the_project_table_holds_the_project_tags() -> void:
	var declared: Array[StringName] = GameplayTagGenerator.tags_in_file()
	var table: GameplayNetNames = GameplayNetNames.from_project()

	assert_eq(table.size(), declared.size(), "one position per declared tag")
	for tag: StringName in declared:
		assert_true(table.index_of(tag) >= 0, "%s has a position" % tag)
#endregion


#region Positions and normals
## A place with whole centimetres crosses exactly, in the bits it needs.
func test_a_whole_centimetre_place_crosses_exactly() -> void:
	var writer: GameplayNetBitWriter = GameplayNetBitWriter.new()
	GameplayNetQuantize.write_position_3d(writer, Vector3(5.0, 0.0, -9.0))
	var bytes: PackedByteArray = writer.finish()

	var back: Vector3 = GameplayNetQuantize.read_position_3d(GameplayNetBitReader.new(bytes))

	assert_eq(back, Vector3(5.0, 0.0, -9.0), "to the centimetre and past it")
	assert_lte(bytes.size(), 6, "in a header and eleven bits a side, not ninety-six")


## A place with more digits than a centimetre comes back within half of one.
func test_a_place_rounds_to_the_centimetre() -> void:
	var spot: Vector2 = Vector2(3.14159, -2.71828)
	var writer: GameplayNetBitWriter = GameplayNetBitWriter.new()
	GameplayNetQuantize.write_position_2d(writer, spot)

	var back: Vector2 = GameplayNetQuantize.read_position_2d(_reader_of(writer))

	assert_almost_eq(back.x, spot.x, CENTIMETRE_ROUNDING, "across")
	assert_almost_eq(back.y, spot.y, CENTIMETRE_ROUNDING, "and up")


## A place too far out for scaling to help crosses at full precision.
func test_a_place_too_far_out_crosses_whole() -> void:
	var far: Vector3 = Vector3(5.0e9, -1.0, 0.25)
	var writer: GameplayNetBitWriter = GameplayNetBitWriter.new()
	GameplayNetQuantize.write_position_3d(writer, far)

	var back: Vector3 = GameplayNetQuantize.read_position_3d(_reader_of(writer))

	assert_eq(back, far, "every bit a float32 has")


## A place that is not a place is refused on the machine that tried to send it.
func test_a_position_that_is_not_finite_is_refused() -> void:
	var writer: GameplayNetBitWriter = GameplayNetBitWriter.new()
	GameplayNetQuantize.write_position_3d(writer, Vector3(INF, 0.0, 0.0))

	assert_false(writer.is_ok(), "INF is nowhere")


## A normal crosses in sixteen bits a component, exact on the axes and clamped
## to the range a direction has.
func test_a_normal_crosses_in_sixteen_bits_a_component() -> void:
	var writer: GameplayNetBitWriter = GameplayNetBitWriter.new()
	GameplayNetQuantize.write_normal_3d(writer, Vector3(0.0, 1.0, -1.0))
	GameplayNetQuantize.write_normal_2d(writer, Vector2(0.6, 0.8))
	GameplayNetQuantize.write_normal_2d(writer, Vector2(3.0, -3.0))
	var bytes: PackedByteArray = writer.finish()
	var reader: GameplayNetBitReader = GameplayNetBitReader.new(bytes)

	assert_eq(bytes.size(), 7 * 2, "seven components, two bytes each")
	assert_eq(GameplayNetQuantize.read_normal_3d(reader), Vector3(0.0, 1.0, -1.0), "the axes exactly")
	var slanted: Vector2 = GameplayNetQuantize.read_normal_2d(reader)
	assert_almost_eq(slanted.x, 0.6, 1.0 / GameplayNetQuantize.NORMAL_STEPS, "a slant to a step")
	assert_eq(GameplayNetQuantize.read_normal_2d(reader), Vector2(1.0, -1.0), "and past the range, clamped to exactly one")

	# The one pattern below the symmetric range, beside a component that is fine,
	# so what refuses it is that pattern and not a read past the end.
	var below: GameplayNetBitWriter = GameplayNetBitWriter.new()
	below.write_bits(0, GameplayNetQuantize.NORMAL_BITS)
	below.write_bits(GameplayNetQuantize.NORMAL_BIAS, GameplayNetQuantize.NORMAL_BITS)
	var lowest: GameplayNetBitReader = GameplayNetBitReader.new(below.finish())
	GameplayNetQuantize.read_normal_2d(lowest)
	assert_false(lowest.is_ok(), "and a pattern no writer makes is refused")
#endregion


#region The game's own payload
## Every type a payload may hold crosses as itself.
func test_every_payload_type_crosses_as_itself() -> void:
	var payload: Dictionary = {
		&"nothing": null,
		"yes": true,
		"no": false,
		"whole": -12345678901,
		"fraction": 0.1,
		"text": "héllo",
		"name": &"Status.Burning",
		"empty_name": &"",
		"flat": Vector2(1.5, -2.0),
		"spatial": Vector3(0.25, 0.5, 1.0),
		"list": [1, "two", [3.0]],
		"nested": {4: {"five": 5}},
	}
	var writer: GameplayNetBitWriter = GameplayNetBitWriter.new()
	GameplayNetPayloadSerializer.write(writer, payload)

	var reader: GameplayNetBitReader = _reader_of(writer)
	var back: Dictionary = GameplayNetPayloadSerializer.read(reader)

	assert_true(reader.is_ok() and reader.is_exhausted(), "it read whole")
	assert_eq(back, payload, "and is what went in")
	for key: Variant in payload:
		assert_eq(typeof(back[key]), typeof(payload[key]), "`%s` kept its type" % str(key))


##     [what it is, the payload]
func _unsendable_payload_cases() -> Array:
	var deep: Dictionary = {}
	var level: Dictionary = deep
	for _index: int in GameplayNetPayloadSerializer.MOST_DEPTH + 2:
		var inner: Dictionary = {}
		level["down"] = inner
		level = inner
	var wide: Array = []
	wide.resize(GameplayNetPayloadSerializer.MOST_ENTRIES + 1)
	return [
		["an object", {"o": RefCounted.new()}],
		["a type the wire has no tag for", {"colour": Color.RED}],
		["nesting past its depth", deep],
		["a list past its entries", {"wide": wide}],
	]


## What a payload may not hold never becomes bytes.
func test_a_payload_the_wire_cannot_carry_is_refused(
	case: Array = use_parameters(_unsendable_payload_cases())
) -> void:
	var described: String = case[0]
	var payload: Dictionary = case[1]
	var writer: GameplayNetBitWriter = GameplayNetBitWriter.new()

	GameplayNetPayloadSerializer.write(writer, payload)

	assert_false(writer.is_ok(), described)


## Two entries under one key are not a dictionary a writer wrote.
func test_a_payload_with_a_key_twice_is_refused() -> void:
	var writer: GameplayNetBitWriter = GameplayNetBitWriter.new()
	writer.write_packed(2)
	for _entry: int in 2:
		writer.write_bits(GameplayNetPayloadSerializer.Tag.WHOLE, GameplayNetPayloadSerializer.TAG_BITS)
		writer.write_signed(1)
		writer.write_bits(GameplayNetPayloadSerializer.Tag.YES, GameplayNetPayloadSerializer.TAG_BITS)

	var reader: GameplayNetBitReader = _reader_of(writer)
	GameplayNetPayloadSerializer.read(reader)

	assert_false(reader.is_ok(), "the same key twice")
#endregion
