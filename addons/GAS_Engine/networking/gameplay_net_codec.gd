## What a message looks like on a wire, and what a wire is allowed to become.
##
## The one place bytes turn into a message. Everything the addon sends goes
## through `encode` and everything it receives goes through `decode`, so what a
## sender may say and what a receiver will accept are the same list rather than
## two lists that drift.
##
## Nothing here decodes an object. Godot can put one in a packet and take it out
## again, and a receiver that allowed it would be constructing whatever class a
## sender named - which is remote code execution wearing a serialisation format.
## What crosses is numbers, strings, arrays and dictionaries of those, and a
## message is rebuilt from them by hand.
##
## Versioned, and refused rather than guessed at when the version is not this
## one. A build that sent v2 to a build that speaks v1 is two processes
## disagreeing about what a field means, and the failure mode of guessing is a
## character whose state is subtly wrong on one side.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayNetCodec extends RefCounted

## What this codec speaks. Bumped when a field changes meaning, never when one
## is added that an older reader can ignore.
const SCHEMA_VERSION: int = 1

## Why a packet was not turned into a message. Named rather than logged: a
## caller that has to parse a sentence to find out is a caller that stops
## checking.
const REASON_UNSUPPORTED_SCHEMA: StringName = &"unsupported_schema"
const REASON_MALFORMED: StringName = &"malformed"
const REASON_INCOMPLETE: StringName = &"incomplete"

#region The keys the wire uses
## Prefixed, the way every other contract in this addon prefixes its own:
## a bare `kind` or `state` is a word half the project uses for something
## else, and two contracts spelling one key the same way look
## interchangeable when they are not.
const VERSION: String = "wire.v"
const KIND: String = "wire.kind"
const ENTITY: String = "wire.entity"
const DEFINITION: String = "wire.definition"
const ACTIVATION: String = "wire.activation"
const PREDICTION_PEER: String = "wire.prediction_peer"
const PREDICTION_VALUE: String = "wire.prediction_value"
const SEQUENCE: String = "wire.sequence"
const STATE: String = "wire.state"
const PAYLOAD: String = "wire.payload"
#endregion

## Why the last decode answered null. Empty when it answered a message.
##
## A static rather than a returned pair, because every caller wants the message
## and only a diagnosing one wants the reason - and a decode that returned two
## things would have every caller unpacking a tuple to ignore half of it.
static var last_refusal: StringName = &""


#region Out
## A message as bytes, or nothing at all.
##
## An incomplete message encodes to nothing rather than to a packet the far side
## will refuse: a sender that put a grant with no definition on the wire has a
## bug here, and finding it here is better than finding it there.
static func encode(message: GameplayNetMessage) -> PackedByteArray:
	if message == null or not message.is_complete():
		return PackedByteArray()
	return JSON.stringify(to_wire(message), "", true, false).to_utf8_buffer()


## A message as the dictionary that goes on the wire.
##
## Separate from `encode` because a batch carries messages inside itself and has
## to write them without each one becoming its own packet.
static func to_wire(message: GameplayNetMessage) -> Dictionary:
	var said: Dictionary = {
		VERSION: SCHEMA_VERSION,
		KIND: int(message.kind),
		ENTITY: GameplayWireReader.entity_said(message.entity),
		DEFINITION: GameplayWireReader.definition_said(message.definition),
		ACTIVATION: message.activation.sequence if message.activation != null else 0,
		PREDICTION_PEER: message.prediction_key.peer if message.prediction_key != null else 0,
		PREDICTION_VALUE: message.prediction_key.value if message.prediction_key != null else 0,
		SEQUENCE: message.sequence,
		STATE: message.state.to_wire() if message.state != null else {},
		PAYLOAD: message.payload,
	}
	return said
#endregion


#region In
## Bytes as a message, or null with `last_refusal` saying why.
##
## Every way this can fail is a refusal rather than a half-built message: a
## packet that is not text, text that is not JSON, JSON that is not an object,
## an object from a version this does not speak, or a message missing what its
## own kind requires.
static func decode(bytes: PackedByteArray) -> GameplayNetMessage:
	last_refusal = &""
	if bytes.is_empty():
		return _refused(REASON_MALFORMED)

	var parser: JSON = JSON.new()
	if parser.parse(bytes.get_string_from_utf8()) != OK:
		return _refused(REASON_MALFORMED)
	return from_wire(parser.data)


## One message out of the dictionary a wire carried.
##
## Public because a batch decodes its own entries through it, and because a test
## driving the shape directly should not have to serialise first.
static func from_wire(wire: Variant) -> GameplayNetMessage:
	last_refusal = &""
	if not wire is Dictionary:
		return _refused(REASON_MALFORMED)
	var said: Dictionary = wire

	# Every one of these goes through the reader now. `int()` on a Variant
	# answers 0 for a string, a dictionary and null alike, so a wire that
	# disagreed about the contract was read as a wire that agreed and said
	# zero - which for a schema version is the one value that must not be
	# guessed.
	if GameplayWireReader.number_in(said, VERSION, 0) != SCHEMA_VERSION:
		return _refused(REASON_UNSUPPORTED_SCHEMA)

	var kind: int = GameplayWireReader.number_in(said, KIND, -1)
	if kind < 0 or kind >= GameplayNetMessage.Kind.size():
		return _refused(REASON_MALFORMED)

	var made: GameplayNetMessage = GameplayNetMessage.new()
	made.kind = kind as GameplayNetMessage.Kind
	made.entity = GameplayWireReader.entity_from(said.get(ENTITY, 0))
	made.definition = GameplayWireReader.definition_from(said.get(DEFINITION, 0))
	made.sequence = GameplayWireReader.number_in(said, SEQUENCE, 0)

	# An activation is a run of one entity's, so it is rebuilt from the entity
	# this message is already about rather than carrying a second copy of it.
	var activation: int = GameplayWireReader.number_in(said, ACTIVATION, 0)
	if activation != 0:
		made.activation = GameplayNetActivationId.of(made.entity, activation)

	var prediction: int = GameplayWireReader.number_in(said, PREDICTION_VALUE, 0)
	if prediction != 0:
		made.prediction_key = GameplayPredictionKey.of(
			GameplayWireReader.number_in(said, PREDICTION_PEER, 0), prediction
		)

	if not _read_state(said, made):
		return _refused(REASON_MALFORMED)
	if not _read_payload(said, made):
		return _refused(REASON_MALFORMED)

	# Checked here rather than by every reader. A confirm with no run to confirm
	# is a message that will be acted on with a null in the middle of it.
	if not made.is_complete():
		return _refused(REASON_INCOMPLETE)
	return made


## The state, when the message carries one. False when what is there is not a
## state - which takes the whole message with it rather than applying a
## character with one effect quietly missing.
static func _read_state(said: Dictionary, into: GameplayNetMessage) -> bool:
	var carried: Variant = said.get(STATE, {})
	if not carried is Dictionary:
		return false
	var listed: Dictionary = carried
	if listed.is_empty():
		return true
	into.state = GameplayNetState.from_wire(listed)
	return into.state != null


## The game's own data, which this addon never reads and never interprets.
static func _read_payload(said: Dictionary, into: GameplayNetMessage) -> bool:
	var carried: Variant = said.get(PAYLOAD, {})
	if not carried is Dictionary:
		return false
	into.payload = carried
	return true


static func _refused(reason: StringName) -> GameplayNetMessage:
	last_refusal = reason
	return null
#endregion
