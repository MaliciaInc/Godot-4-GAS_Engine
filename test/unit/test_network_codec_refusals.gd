## What a wire is not allowed to become, in either direction.
##
## Split from test_network_codec.gd, which proves what does cross, and every bit
## as much a part of the codec. A receiver that guessed at a packet it did not
## understand would be a receiver constructing state from whatever a sender
## happened to send, and the failure mode is two processes quietly disagreeing
## about a character. Each refused packet is built bit by bit with the same
## writer the codec uses, so it has exactly one thing wrong with it.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const ENTITY: int = 42
const DEFINITION: int = 7


#region Getting there
## The start of a message body written by hand: its kind, its entity, and which
## of the optional fields follow.
func _body(kind: int, carries: int) -> GameplayNetBitWriter:
	var body: GameplayNetBitWriter = GameplayNetBitWriter.new()
	body.write_bits(kind, GameplayNetCodec.KIND_BITS)
	body.write_signed(ENTITY)
	body.write_bits(carries, GameplayNetCodec.CARRIES_BITS)
	return body


## A hand-written body behind a header that says it used no shared names.
func _packet(body: GameplayNetBitWriter) -> PackedByteArray:
	var packet: PackedByteArray = PackedByteArray([GameplayNetCodec.SCHEMA_VERSION, 0])
	packet.append_array(body.finish())
	return packet


func _carrying(which: GameplayNetCodec.Carries) -> int:
	return 1 << which
#endregion


#region What a wire may not become
## An incomplete message does not become a packet.
##
## Refused here rather than by the far side: a grant with no definition is a bug
## on this side, and finding it here is better than finding it there.
func test_an_incomplete_message_encodes_to_nothing() -> void:
	var missing: GameplayNetMessage = GameplayNetMessage.of(
		GameplayNetMessage.Kind.GRANT, GameplayNetEntityId.of(ENTITY)
	)

	assert_true(
		GameplayNetCodec.encode(missing).is_empty(),
		"a grant naming no definition is not put on a wire"
	)
	assert_true(GameplayNetCodec.encode(null).is_empty(), "and neither is nothing")


##     [what arrived, the bytes, why it is refused]
func _malformed_cases() -> Array:
	var confirm: PackedByteArray = GameplayNetCodec.encode(
		GameplayNetMessage.of(GameplayNetMessage.Kind.GENERIC_CONFIRM, GameplayNetEntityId.of(ENTITY))
	)
	var trailing: PackedByteArray = confirm.duplicate()
	trailing.append(0xFF)
	var dirty_padding: PackedByteArray = confirm.duplicate()
	dirty_padding[dirty_padding.size() - 1] = dirty_padding[dirty_padding.size() - 1] | 0x80
	var unknown_flags: PackedByteArray = confirm.duplicate()
	unknown_flags[1] = 2

	var nested: GameplayNetBitWriter = _body(
		GameplayNetMessage.Kind.BATCH, _carrying(GameplayNetCodec.Carries.BODY)
	)
	nested.write_bool(true)
	nested.write_packed(1)
	nested.write_bits(GameplayNetMessage.Kind.BATCH, GameplayNetCodec.KIND_BITS)

	var too_many: GameplayNetBitWriter = _body(
		GameplayNetMessage.Kind.STATE_SNAPSHOT, _carrying(GameplayNetCodec.Carries.BODY)
	)
	too_many.write_bool(false)
	too_many.write_bits(1 << GameplayNetStateSerializer.Holds.ATTRIBUTES, GameplayNetStateSerializer.HOLDS_BITS)
	too_many.write_packed(GameplayNetStateSerializer.MOST_ENTRIES + 1)

	var promised: GameplayNetBitWriter = _body(
		GameplayNetMessage.Kind.STATE_SNAPSHOT, _carrying(GameplayNetCodec.Carries.BODY)
	)
	promised.write_bool(false)
	promised.write_bits(1 << GameplayNetStateSerializer.Holds.ATTRIBUTES, GameplayNetStateSerializer.HOLDS_BITS)
	promised.write_packed(50)

	var zero_definition: GameplayNetBitWriter = _body(
		GameplayNetMessage.Kind.GRANT, _carrying(GameplayNetCodec.Carries.DEFINITION)
	)
	zero_definition.write_u32(GameplayNetDefinitionId.NONE)

	var broken_effect: GameplayNetBitWriter = _body(
		GameplayNetMessage.Kind.STATE_SNAPSHOT, _carrying(GameplayNetCodec.Carries.BODY)
	)
	broken_effect.write_bool(false)
	broken_effect.write_bits(1 << GameplayNetStateSerializer.Holds.EFFECTS, GameplayNetStateSerializer.HOLDS_BITS)
	broken_effect.write_packed(1)
	broken_effect.write_packed(GameplayNetEffectState.NONE)
	broken_effect.write_u32(DEFINITION)
	broken_effect.write_bits(0, GameplayNetStateSerializer.DIFFERS_BITS)

	var unknown_value: GameplayNetBitWriter = _body(
		GameplayNetMessage.Kind.CUE, _carrying(GameplayNetCodec.Carries.PAYLOAD)
	)
	unknown_value.write_packed(1)
	unknown_value.write_bits(15, GameplayNetPayloadSerializer.TAG_BITS)

	return [
		["nothing at all", PackedByteArray(), GameplayNetCodec.REASON_MALFORMED],
		["a version this does not speak", PackedByteArray([GameplayNetCodec.SCHEMA_VERSION + 1, 0]), GameplayNetCodec.REASON_UNSUPPORTED_SCHEMA],
		["a header and nothing after it", PackedByteArray([GameplayNetCodec.SCHEMA_VERSION, 0]), GameplayNetCodec.REASON_MALFORMED],
		["flags nobody defined", unknown_flags, GameplayNetCodec.REASON_MALFORMED],
		["a kind that is not one", _packet(_body(15, 0)), GameplayNetCodec.REASON_MALFORMED],
		["a grant with no definition", _packet(_body(GameplayNetMessage.Kind.GRANT, 0)), GameplayNetCodec.REASON_INCOMPLETE],
		["a presence bit followed by the value that means nothing", _packet(zero_definition), GameplayNetCodec.REASON_MALFORMED],
		["a body on a kind that has none", _packet(_body(GameplayNetMessage.Kind.GENERIC_CONFIRM, _carrying(GameplayNetCodec.Carries.BODY))), GameplayNetCodec.REASON_MALFORMED],
		["bytes left over after the message", trailing, GameplayNetCodec.REASON_MALFORMED],
		["padding that is not zero", dirty_padding, GameplayNetCodec.REASON_MALFORMED],
		["a batch inside a batch", _packet(nested), GameplayNetCodec.REASON_MALFORMED],
		["a list past its bound", _packet(too_many), GameplayNetCodec.REASON_MALFORMED],
		["a count the packet cannot hold", _packet(promised), GameplayNetCodec.REASON_MALFORMED],
		["a state with an effect that is not one", _packet(broken_effect), GameplayNetCodec.REASON_MALFORMED],
		["a payload value of no type there is", _packet(unknown_value), GameplayNetCodec.REASON_MALFORMED],
	]


func test_a_packet_that_is_not_a_message_is_refused_and_says_why(
	case: Array = use_parameters(_malformed_cases())
) -> void:
	var described: String = case[0]
	var packet: PackedByteArray = case[1]
	var reason: StringName = case[2]

	assert_null(GameplayNetCodec.decode(packet), described)
	assert_eq(GameplayNetCodec.last_refusal, reason, "%s: refused as `%s`" % [described, reason])


## Nothing becomes an object, in either direction.
##
## Godot can put one in a packet and take one out, and a receiver that allowed
## it would construct whatever class the far side named. So a payload holding
## one never becomes bytes, and no value in a packet decodes into one - the
## payload's own tags name every type there is, and none of them is an object.
func test_nothing_a_wire_says_becomes_an_object() -> void:
	var sent: GameplayNetMessage = GameplayNetMessage.of(
		GameplayNetMessage.Kind.CUE, GameplayNetEntityId.of(ENTITY)
	)
	sent.payload = {"o": RefCounted.new()}

	assert_true(GameplayNetCodec.encode(sent).is_empty(), "a payload holding an object is not sent")
#endregion
