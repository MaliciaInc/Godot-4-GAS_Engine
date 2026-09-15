## What a message looks like on a wire, and what a wire is allowed to become.
##
## The one place bytes turn into a message. Everything the addon sends goes
## through `encode` and everything it receives goes through `decode`, so what a
## sender may say and what a receiver will accept are one list rather than two
## that drift.
##
## A bit stream, laid out the way the reference replicates the same things. A
## packet opens with the schema version it speaks and a byte of flags; when any
## name in it was written as a position in the shared table, the table's
## fingerprint follows, and a peer holding a different table refuses a protocol
## mismatch instead of reading every tag as some other tag. Then the kind in four
## bits, the entity, six presence bits, and only the fields and the body those
## bits vouch for. A bare confirm is a handful of bytes.
##
## Nothing here decodes an object. Godot can put one in a packet and take it out
## again, and a receiver that allowed it would be constructing whatever class a
## sender named - which is remote code execution wearing a serialisation format.
## What crosses is numbers, names and the typed shapes the serializers in `wire/`
## rebuild by hand.
##
## Versioned, and refused rather than guessed at when the version is not this
## one. A build that sent v3 to a build that speaks v2 is two processes
## disagreeing about what a bit means, and the failure mode of guessing is a
## character whose state is subtly wrong on one side.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayNetCodec extends RefCounted

## What this codec speaks. Bumped whenever a bit changes meaning: a bit stream
## has no field an older reader can skip, so every change to the layout is one.
const SCHEMA_VERSION: int = 2

## Why a packet was not turned into a message. Named rather than logged: a
## caller that has to parse a sentence to find out is a caller that stops
## checking.
const REASON_UNSUPPORTED_SCHEMA: StringName = &"unsupported_schema"
const REASON_MALFORMED: StringName = &"malformed"
const REASON_INCOMPLETE: StringName = &"incomplete"

## A packet written against a different table of names. Its own reason, because
## it is not a broken packet: it is two builds that disagree, and the fix is on
## a machine rather than in a sender.
const REASON_PROTOCOL_MISMATCH: StringName = &"protocol_mismatch"

const VERSION_BITS: int = 8
const FLAGS_BITS: int = 8
const FLAG_SHARED_NAMES: int = 1
const KIND_BITS: int = 4

## Which of a message's optional fields it carries, one bit each, in this order.
enum Carries { DEFINITION, ACTIVATION, PREDICTION, SEQUENCE, BODY, PAYLOAD }

const CARRIES_BITS: int = 6

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
## bug here, and finding it here is better than finding it there. So does one
## the wire cannot carry - a list past its bound, a position that is not a place.
static func encode(message: GameplayNetMessage, names: GameplayNetNames = null) -> PackedByteArray:
	if message == null or not message.is_complete():
		return PackedByteArray()
	var body: GameplayNetBitWriter = GameplayNetBitWriter.new()
	body.names = names
	write_message(body, message)
	var written: PackedByteArray = body.finish()
	if written.is_empty():
		return written

	var header: GameplayNetBitWriter = GameplayNetBitWriter.new()
	header.write_bits(SCHEMA_VERSION, VERSION_BITS)
	header.write_bits(FLAG_SHARED_NAMES if body.used_shared_names else 0, FLAGS_BITS)
	if body.used_shared_names:
		header.write_u32(names.fingerprint)
	var packet: PackedByteArray = header.finish()
	packet.append_array(written)
	return packet


## One message into a stream that is already open.
##
## Public because a batch writes its members through it - a member is a message
## without a packet of its own - and a batch inside a batch is refused here.
static func write_message(
	writer: GameplayNetBitWriter, message: GameplayNetMessage, inside_batch: bool = false
) -> void:
	if message == null or (inside_batch and message.kind == GameplayNetMessage.Kind.BATCH):
		writer.fail()
		return
	writer.write_bits(int(message.kind), KIND_BITS)
	writer.write_signed(message.entity.value if message.entity != null else GameplayNetEntityId.NONE)

	var carries: Array[bool] = [
		message.definition != null and message.definition.is_valid(),
		message.activation != null and message.activation.sequence != GameplayNetActivationId.NONE,
		message.prediction_key != null and message.prediction_key.is_valid(),
		message.sequence != 0,
		_carries_body(message),
		not message.payload.is_empty(),
	]
	var mask: int = 0
	for index: int in carries.size():
		if carries[index]:
			mask |= 1 << index
	writer.write_bits(mask, CARRIES_BITS)

	if carries[Carries.DEFINITION]:
		writer.write_u32(message.definition.value)
	if carries[Carries.ACTIVATION]:
		# The run only: an activation is a run of the entity this message is
		# already about, so the entity is not sent twice.
		writer.write_signed(message.activation.sequence)
	if carries[Carries.PREDICTION]:
		writer.write_signed(message.prediction_key.peer)
		writer.write_signed(message.prediction_key.value)
	if carries[Carries.SEQUENCE]:
		writer.write_signed(message.sequence)
	if carries[Carries.BODY]:
		_write_body(writer, message)
	if carries[Carries.PAYLOAD]:
		GameplayNetPayloadSerializer.write(writer, message.payload)


## Whether this message has a body of its kind to carry.
static func _carries_body(message: GameplayNetMessage) -> bool:
	match message.kind:
		GameplayNetMessage.Kind.STATE_SNAPSHOT, GameplayNetMessage.Kind.STATE_DELTA:
			return message.state != null
		GameplayNetMessage.Kind.TARGET_DATA:
			return message.aim != null
		GameplayNetMessage.Kind.GAMEPLAY_EVENT:
			return message.event != null
		GameplayNetMessage.Kind.INPUT_PRESSED, GameplayNetMessage.Kind.INPUT_RELEASED:
			return true
		GameplayNetMessage.Kind.BATCH:
			return message.batch != null
		GameplayNetMessage.Kind.CUE:
			return message.cue != null
	return false


static func _write_body(writer: GameplayNetBitWriter, message: GameplayNetMessage) -> void:
	match message.kind:
		GameplayNetMessage.Kind.STATE_SNAPSHOT, GameplayNetMessage.Kind.STATE_DELTA:
			GameplayNetStateSerializer.write(writer, message.state)
		GameplayNetMessage.Kind.TARGET_DATA:
			GameplayNetAimSerializer.write(writer, message.aim)
		GameplayNetMessage.Kind.GAMEPLAY_EVENT:
			GameplayNetEventSerializer.write(writer, message.event)
		GameplayNetMessage.Kind.INPUT_PRESSED, GameplayNetMessage.Kind.INPUT_RELEASED:
			writer.write_signed(message.input_id)
		GameplayNetMessage.Kind.BATCH:
			_write_batch(writer, message.batch)
		GameplayNetMessage.Kind.CUE:
			GameplayNetCueSerializer.write(writer, message.cue)


## A batch is its atomicity, a bounded count, and its members. An empty one
## says nothing and is not written.
static func _write_batch(writer: GameplayNetBitWriter, batch: GameplayNetBatch) -> void:
	if batch.messages.is_empty():
		writer.fail()
		return
	writer.write_bool(batch.atomic)
	writer.write_count(batch.messages.size(), GameplayNetBatch.MAX_MESSAGES)
	for member: GameplayNetMessage in batch.messages:
		write_message(writer, member, true)
#endregion


#region In
## Bytes as a message, or null with `last_refusal` saying why.
##
## Every way this can fail is a refusal rather than a half-built message: a
## version this does not speak, a table it does not hold, a stream that runs out
## or runs on past the message, a field no writer produces, or a message missing
## what its own kind requires.
static func decode(bytes: PackedByteArray, names: GameplayNetNames = null) -> GameplayNetMessage:
	last_refusal = &""
	if bytes.is_empty():
		return _refused(REASON_MALFORMED)

	var reader: GameplayNetBitReader = GameplayNetBitReader.new(bytes)
	if reader.read_bits(VERSION_BITS) != SCHEMA_VERSION:
		return _refused(REASON_UNSUPPORTED_SCHEMA)
	var flags: int = reader.read_bits(FLAGS_BITS)
	if not reader.is_ok() or (flags & ~FLAG_SHARED_NAMES) != 0:
		return _refused(REASON_MALFORMED)
	if (flags & FLAG_SHARED_NAMES) != 0:
		var fingerprint: int = reader.read_u32()
		if not reader.is_ok():
			return _refused(REASON_MALFORMED)
		if names == null or names.fingerprint != fingerprint:
			return _refused(REASON_PROTOCOL_MISMATCH)
		# Handed to the reader only when the packet says it used it: a packet
		# that wrote every name out has no business naming one by position.
		reader.names = names

	var message: GameplayNetMessage = read_message(reader)
	if message == null or not reader.is_ok() or not reader.is_exhausted():
		return _refused(REASON_MALFORMED)
	# Checked here rather than by every reader. A confirm with no run to confirm
	# is a message that will be acted on with a null in the middle of it.
	if not message.is_complete():
		return _refused(REASON_INCOMPLETE)
	return message


## One message out of a stream that is already open, or null with the reader
## failed. Public for the reason `write_message` is.
static func read_message(
	reader: GameplayNetBitReader, inside_batch: bool = false
) -> GameplayNetMessage:
	var kind: int = reader.read_bits(KIND_BITS)
	if (
		not reader.is_ok()
		or kind >= GameplayNetMessage.Kind.size()
		or (inside_batch and kind == GameplayNetMessage.Kind.BATCH)
	):
		reader.fail()
		return null

	var made: GameplayNetMessage = GameplayNetMessage.new()
	made.kind = kind as GameplayNetMessage.Kind
	var entity: int = reader.read_signed()
	made.entity = GameplayNetEntityId.of(entity) if entity != GameplayNetEntityId.NONE else null

	var mask: int = reader.read_bits(CARRIES_BITS)
	if _has(mask, Carries.DEFINITION):
		var definition: int = reader.read_u32()
		_refuse_nothing(reader, definition, GameplayNetDefinitionId.NONE)
		made.definition = GameplayNetDefinitionId.from_wire(definition)
	if _has(mask, Carries.ACTIVATION):
		var run: int = reader.read_signed()
		_refuse_nothing(reader, run, GameplayNetActivationId.NONE)
		made.activation = GameplayNetActivationId.of(made.entity, run)
	if _has(mask, Carries.PREDICTION):
		var peer: int = reader.read_signed()
		var guess: int = reader.read_signed()
		_refuse_nothing(reader, guess, GameplayPredictionKey.NONE)
		made.prediction_key = GameplayPredictionKey.of(peer, guess)
	if _has(mask, Carries.SEQUENCE):
		made.sequence = reader.read_signed()
	if _has(mask, Carries.BODY):
		_read_body(reader, made)
	if _has(mask, Carries.PAYLOAD):
		made.payload = GameplayNetPayloadSerializer.read(reader)
	return made if reader.is_ok() else null


static func _read_body(reader: GameplayNetBitReader, into: GameplayNetMessage) -> void:
	match into.kind:
		GameplayNetMessage.Kind.STATE_SNAPSHOT, GameplayNetMessage.Kind.STATE_DELTA:
			into.state = GameplayNetStateSerializer.read(reader)
		GameplayNetMessage.Kind.TARGET_DATA:
			into.aim = GameplayNetAimSerializer.read(reader)
		GameplayNetMessage.Kind.GAMEPLAY_EVENT:
			into.event = GameplayNetEventSerializer.read(reader)
		GameplayNetMessage.Kind.INPUT_PRESSED, GameplayNetMessage.Kind.INPUT_RELEASED:
			into.input_id = reader.read_signed()
		GameplayNetMessage.Kind.BATCH:
			into.batch = _read_batch(reader)
		GameplayNetMessage.Kind.CUE:
			into.cue = GameplayNetCueSerializer.read(reader)
		_:
			# A body on a kind that has none is a bit no writer sets.
			reader.fail()


static func _read_batch(reader: GameplayNetBitReader) -> GameplayNetBatch:
	var made: GameplayNetBatch = GameplayNetBatch.new()
	made.atomic = reader.read_bool()
	var count: int = reader.read_count(GameplayNetBatch.MAX_MESSAGES)
	if count == 0:
		reader.fail()
		return made
	for _member: int in count:
		var member: GameplayNetMessage = read_message(reader, true)
		if member == null:
			reader.fail()
			return made
		made.messages.append(member)
	return made


static func _has(mask: int, which: GameplayNetCodec.Carries) -> bool:
	return (mask & (1 << which)) != 0


## A presence bit followed by the value that means nothing is not something a
## writer produces - it only writes a field that holds one.
static func _refuse_nothing(reader: GameplayNetBitReader, value: int, nothing: int) -> void:
	if value == nothing:
		reader.fail()


static func _refused(reason: StringName) -> GameplayNetMessage:
	last_refusal = reason
	return null
#endregion
