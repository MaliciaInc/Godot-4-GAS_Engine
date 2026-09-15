## What a message becomes on a wire, and what comes back off it.
##
## Both halves in one suite, because a codec is only ever right as a pair: an
## encoder and a decoder tested apart agree with each other's mistakes. Every
## message here goes out as bytes and comes back, and what comes back is compared
## with what went in - its types included, which is the part a text wire got
## wrong for a whole phase.
##
## What a wire may not become is test_network_codec_refusals.gd, and matters as
## much as the round trips here.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const ENTITY: int = 42
const DEFINITION: int = 7
const TOLERANCE: float = 0.0001

const HEALTH: StringName = &"health"
const BURNING: StringName = &"Status.Burning"
const CUE: StringName = &"Cue.Impact"

## What a few ordinary messages may cost, in bytes. Ceilings rather than exact
## sizes, set a little above what the layout produces: a change that grew one
## past them is a change somebody has to look at, and a text wire would be past
## every one of them by an order of magnitude.
const MOST_FOR_A_CONFIRM: int = 6
const MOST_FOR_A_REQUEST: int = 14
const MOST_FOR_A_READING: int = 80
const MOST_FOR_A_DELTA: int = 24


#region Getting there
func _entity() -> GameplayNetEntityId:
	return GameplayNetEntityId.of(ENTITY)


func _round_tripped(message: GameplayNetMessage, names: GameplayNetNames = null) -> GameplayNetMessage:
	var packet: PackedByteArray = GameplayNetCodec.encode(message, names)
	assert_false(packet.is_empty(), "a complete message encodes to something")
	return GameplayNetCodec.decode(packet, names)


## A state with one of everything in it, so nothing can be dropped unnoticed.
func _a_full_state() -> GameplayNetState:
	var state: GameplayNetState = GameplayNetState.snapshot()
	state.attributes[HEALTH] = 73.5
	state.current_attributes[HEALTH] = 98.5
	state.tags[BURNING] = 2
	state.abilities = [DEFINITION]
	state.running_abilities = [DEFINITION]
	state.cues = [CUE]

	var effect: GameplayNetEffectState = GameplayNetEffectState.of(3, DEFINITION)
	effect.stack_count = 4
	effect.time_remaining = 12.25
	effect.remaining_turns = 2
	effect.inhibited = true
	state.effects = [effect]
	return state
#endregion


#region There and back
## A grant goes out and comes back saying the same thing.
func test_a_grant_survives_the_round_trip() -> void:
	var sent: GameplayNetMessage = GameplayNetMessage.of(
		GameplayNetMessage.Kind.GRANT, _entity()
	)
	sent.definition = GameplayNetDefinitionId.from_wire(DEFINITION)

	var back: GameplayNetMessage = _round_tripped(sent)

	assert_not_null(back, "it decoded")
	assert_eq(back.kind, GameplayNetMessage.Kind.GRANT, "the same kind")
	assert_eq(back.entity.value, ENTITY, "about the same entity")
	assert_eq(back.definition.value, DEFINITION, "naming the same definition")


## A definition's identity is a hash spread over all thirty-two bits, and the
## top of that range crosses as itself.
func test_a_definition_at_the_top_of_its_range_crosses_as_itself() -> void:
	var sent: GameplayNetMessage = GameplayNetMessage.of(
		GameplayNetMessage.Kind.REVOKE, _entity()
	)
	sent.definition = GameplayNetDefinitionId.from_wire(GameplayNetBitWriter.MOST_U32)

	var back: GameplayNetMessage = _round_tripped(sent)

	assert_eq(back.definition.value, GameplayNetBitWriter.MOST_U32, "every bit of it")


## A predicted request carries the guess it belongs to.
##
## Both halves of the key, because a prediction key is a peer and a number: two
## clients counting from one would collide on the value alone, and the authority
## would answer one client's guess with the other's outcome.
func test_a_predicted_request_carries_whose_guess_it_is() -> void:
	var sent: GameplayNetMessage = GameplayNetMessage.of(
		GameplayNetMessage.Kind.ACTIVATION_REQUEST, _entity()
	)
	sent.definition = GameplayNetDefinitionId.from_wire(DEFINITION)
	sent.prediction_key = GameplayPredictionKey.of(5, 11)

	var back: GameplayNetMessage = _round_tripped(sent)

	assert_not_null(back, "it decoded")
	assert_true(back.is_predicted(), "it is still a guess")
	assert_eq(back.prediction_key.peer, 5, "made by the same peer")
	assert_eq(back.prediction_key.value, 11, "and the same one of theirs")


## An activation names a run of the entity the message is already about.
func test_an_activation_names_a_run_of_the_entity_it_is_about() -> void:
	var sent: GameplayNetMessage = GameplayNetMessage.of(
		GameplayNetMessage.Kind.ACTIVATION_CONFIRM, _entity()
	)
	sent.activation = GameplayNetActivationId.of(_entity(), 9)
	sent.prediction_key = GameplayPredictionKey.of(5, 11)

	var back: GameplayNetMessage = _round_tripped(sent)

	assert_not_null(back, "it decoded")
	assert_true(back.activation.is_valid(), "the run came back whole")
	assert_eq(back.activation.sequence, 9, "the same run")
	assert_eq(back.activation.entity.value, ENTITY, "of the same entity")


## Everything a state can carry, out and back.
func test_a_state_survives_the_round_trip_whole() -> void:
	var sent: GameplayNetMessage = GameplayNetMessage.of(
		GameplayNetMessage.Kind.STATE_SNAPSHOT, _entity()
	)
	sent.state = _a_full_state()
	sent.sequence = 17

	var back: GameplayNetMessage = _round_tripped(sent)

	assert_not_null(back, "it decoded")
	assert_eq(back.sequence, 17, "which reading it is")
	assert_almost_eq(back.state.attributes[HEALTH], 73.5, TOLERANCE, "the base attribute")
	assert_almost_eq(
		back.state.current_attributes[HEALTH], 98.5, TOLERANCE, "and the composed one - AUD-08"
	)
	assert_eq(back.state.tags[BURNING], 2, "the tag, at its count")
	assert_eq(back.state.abilities, [DEFINITION] as Array[int], "the grants")
	assert_eq(
		back.state.running_abilities, [DEFINITION] as Array[int],
		"and which of them is running"
	)
	assert_eq(back.state.cues, [CUE] as Array[StringName], "the cues")

	assert_eq(back.state.effects.size(), 1, "the effect")
	var effect: GameplayNetEffectState = back.state.effects[0]
	assert_eq(effect.stack_count, 4, "at its stack count")
	assert_almost_eq(effect.time_remaining, 12.25, TOLERANCE, "with its clock")
	assert_eq(effect.remaining_turns, 2, "and its turns")
	assert_true(effect.inhibited, "and whether it is in force")


## A delta says it is one, which is not visible in the data.
##
## A snapshot that happens to be empty is a character with nothing on it, and a
## delta that happens to be empty is nothing having happened.
func test_a_delta_says_it_is_one() -> void:
	var sent: GameplayNetMessage = GameplayNetMessage.of(
		GameplayNetMessage.Kind.STATE_DELTA, _entity()
	)
	sent.state = GameplayNetState.delta()
	sent.state.removed_tags = [BURNING]
	sent.state.ended_effects = [3]

	var back: GameplayNetMessage = _round_tripped(sent)

	assert_not_null(back, "it decoded")
	assert_true(back.state.is_delta(), "it is still a delta")
	assert_eq(back.state.removed_tags, [BURNING] as Array[StringName], "what went away")
	assert_eq(back.state.ended_effects, [3] as Array[int], "and what ended")


## The game's own payload crosses untouched, and as the types it left as.
##
## A whole number is still a whole number, a vector still a vector, a name still
## a name - the things a text wire turned into floats and strings on the way.
func test_a_game_s_own_payload_crosses_as_the_types_it_left_as() -> void:
	var sent: GameplayNetMessage = GameplayNetMessage.of(
		GameplayNetMessage.Kind.CUE, _entity()
	)
	sent.payload = {
		"cue": "Cue.Impact",
		"loudness": 0.5,
		"hits": 3,
		"named": BURNING,
		"at": Vector3(1.5, 0.0, -2.25),
		"facing": Vector2(0.0, 1.0),
		"flags": [true, false, null],
		"nested": {7: "seven"},
	}

	var back: GameplayNetMessage = _round_tripped(sent)

	assert_not_null(back, "it decoded")
	assert_eq(back.payload, sent.payload, "everything the game put in it")
	assert_eq(typeof(back.payload.get("hits")), TYPE_INT, "a whole number is still whole")
	assert_eq(typeof(back.payload.get("named")), TYPE_STRING_NAME, "a name is still a name")
	assert_eq(typeof(back.payload.get("at")), TYPE_VECTOR3, "and a vector is still a vector")


## A cue of the ability system's own crosses whole.
func test_a_cue_survives_the_round_trip() -> void:
	var cue: GameplayCueWire = GameplayCueWire.new()
	cue.cue_tag = CUE
	cue.matched_cue_tag = CUE
	cue.instigator = GameplayNetEntityId.of(7)
	cue.raw_magnitude = 30.0
	cue.normalized_magnitude = 0.5
	cue.effect_level = 2.0
	cue.stack_count = 3
	cue.source_tags = [BURNING] as Array[StringName]
	cue.location = Vector3(1.0, 2.0, 3.0)
	cue.has_location = true
	var sent: GameplayNetMessage = GameplayNetMessage.of(GameplayNetMessage.Kind.CUE, _entity())
	sent.cue = cue

	var back: GameplayCueWire = _round_tripped(sent).cue

	assert_eq(back.cue_tag, CUE, "the tag")
	assert_eq(back.matched_cue_tag, CUE, "and what answered it")
	assert_eq(back.instigator.value, 7, "who caused it")
	assert_null(back.target, "and nobody it was not said to play on")
	assert_almost_eq(back.raw_magnitude, 30.0, TOLERANCE, "the number")
	assert_almost_eq(back.normalized_magnitude, 0.5, TOLERANCE, "and its fraction")
	assert_almost_eq(back.effect_level, 2.0, TOLERANCE, "the level")
	assert_eq(back.stack_count, 3, "the stack")
	assert_eq(back.source_tags, [BURNING] as Array[StringName], "the snapshot")
	assert_true(back.has_location, "a place")
	assert_eq(back.location, Vector3(1.0, 2.0, 3.0), "and the place it was")


## An input names its slot, including the one that means none.
func test_an_input_names_its_slot() -> void:
	for slot: int in [4, GameplayNetMessage.NO_INPUT]:
		var sent: GameplayNetMessage = GameplayNetMessage.of(
			GameplayNetMessage.Kind.INPUT_RELEASED, _entity()
		)
		sent.definition = GameplayNetDefinitionId.from_wire(DEFINITION)
		sent.input_id = slot

		var back: GameplayNetMessage = _round_tripped(sent)

		assert_eq(back.input_id, slot, "slot %d crossed as itself" % slot)


## A batch crosses with its members and with what it promised about them.
func test_a_batch_crosses_with_its_members_and_its_promise() -> void:
	var answer: GameplayNetMessage = GameplayNetMessage.of(
		GameplayNetMessage.Kind.ACTIVATION_CONFIRM, _entity()
	)
	answer.activation = GameplayNetActivationId.of(_entity(), 9)
	answer.prediction_key = GameplayPredictionKey.of(5, 11)
	var batch: GameplayNetBatch = GameplayNetBatch.new()
	batch.atomic = false
	batch.messages = [
		answer,
		GameplayNetMessage.of(GameplayNetMessage.Kind.GENERIC_CONFIRM, _entity()),
	]
	var sent: GameplayNetMessage = GameplayNetMessage.of(GameplayNetMessage.Kind.BATCH, _entity())
	sent.batch = batch

	var back: GameplayNetBatch = _round_tripped(sent).batch

	assert_false(back.atomic, "that its members are independent")
	assert_eq(back.messages.size(), 2, "both members")
	assert_eq(back.messages[0].activation.sequence, 9, "the first one whole")
	assert_eq(
		back.messages[1].kind, GameplayNetMessage.Kind.GENERIC_CONFIRM, "and the second"
	)
#endregion


#region Names both machines agree about
## A name in the shared table crosses as its position, and costs less than its text.
func test_a_name_in_the_shared_table_crosses_as_its_position() -> void:
	var names: GameplayNetNames = GameplayNetNames.of([BURNING, CUE, HEALTH] as Array[StringName])
	var sent: GameplayNetMessage = GameplayNetMessage.of(
		GameplayNetMessage.Kind.STATE_SNAPSHOT, _entity()
	)
	sent.state = _a_full_state()

	var shared: PackedByteArray = GameplayNetCodec.encode(sent, names)
	var spelled: PackedByteArray = GameplayNetCodec.encode(sent)
	var back: GameplayNetMessage = GameplayNetCodec.decode(shared, names)

	assert_lt(shared.size(), spelled.size(), "positions cost less than text")
	assert_not_null(back, "and it decoded against the same table")
	assert_eq(back.state.tags[BURNING], 2, "to the same tag")


## A packet written against another table is refused as a protocol mismatch.
##
## Two tables that differ make every position mean a different name, so the
## packet is refused - by its own reason, because it is not a broken packet but
## two builds that disagree.
func test_a_packet_written_against_another_table_is_a_protocol_mismatch() -> void:
	var ours: GameplayNetNames = GameplayNetNames.of([BURNING, CUE] as Array[StringName])
	var theirs: GameplayNetNames = GameplayNetNames.of([BURNING, CUE, HEALTH] as Array[StringName])
	var sent: GameplayNetMessage = GameplayNetMessage.of(
		GameplayNetMessage.Kind.STATE_DELTA, _entity()
	)
	sent.state = GameplayNetState.delta()
	sent.state.removed_tags = [BURNING]
	var packet: PackedByteArray = GameplayNetCodec.encode(sent, ours)

	assert_null(GameplayNetCodec.decode(packet, theirs), "a different table")
	assert_eq(GameplayNetCodec.last_refusal, GameplayNetCodec.REASON_PROTOCOL_MISMATCH)
	assert_null(GameplayNetCodec.decode(packet), "and no table at all")
	assert_eq(GameplayNetCodec.last_refusal, GameplayNetCodec.REASON_PROTOCOL_MISMATCH)
	assert_not_null(GameplayNetCodec.decode(packet, ours), "while the same table reads it")


## A packet that spelled every name out is read by a machine with any table.
func test_a_packet_that_spelled_every_name_needs_no_table() -> void:
	var sent: GameplayNetMessage = GameplayNetMessage.of(
		GameplayNetMessage.Kind.STATE_DELTA, _entity()
	)
	sent.state = GameplayNetState.delta()
	sent.state.removed_tags = [BURNING]
	var packet: PackedByteArray = GameplayNetCodec.encode(sent)

	var back: GameplayNetMessage = GameplayNetCodec.decode(
		packet, GameplayNetNames.of([CUE] as Array[StringName])
	)

	assert_not_null(back, "it decoded")
	assert_eq(back.state.removed_tags, [BURNING] as Array[StringName], "naming what it named")
#endregion


#region What it costs
## A message costs bytes, not text.
##
## Ceilings, measured once and asserted since: the layout is the same on every
## machine, so a message that grew past one grew because somebody changed the
## layout, which is a change to look at rather than to discover in a capture.
func test_a_message_costs_bytes_not_text() -> void:
	var confirm: GameplayNetMessage = GameplayNetMessage.of(
		GameplayNetMessage.Kind.GENERIC_CONFIRM, _entity()
	)
	var request: GameplayNetMessage = GameplayNetMessage.of(
		GameplayNetMessage.Kind.ACTIVATION_REQUEST, _entity()
	)
	request.definition = GameplayNetDefinitionId.from_wire(GameplayNetBitWriter.MOST_U32)
	request.prediction_key = GameplayPredictionKey.of(2, 17)
	var reading: GameplayNetMessage = GameplayNetMessage.of(
		GameplayNetMessage.Kind.STATE_SNAPSHOT, _entity()
	)
	reading.state = _a_full_state()
	reading.sequence = 1234
	var delta: GameplayNetMessage = GameplayNetMessage.of(
		GameplayNetMessage.Kind.STATE_DELTA, _entity()
	)
	delta.state = GameplayNetState.delta()
	delta.state.current_attributes[HEALTH] = 61.25
	delta.sequence = 1235

	assert_lte(GameplayNetCodec.encode(confirm).size(), MOST_FOR_A_CONFIRM, "a confirm")
	assert_lte(GameplayNetCodec.encode(request).size(), MOST_FOR_A_REQUEST, "a predicted request")
	assert_lte(GameplayNetCodec.encode(reading).size(), MOST_FOR_A_READING, "a whole reading")
	assert_lte(GameplayNetCodec.encode(delta).size(), MOST_FOR_A_DELTA, "and one attribute moving")
#endregion
