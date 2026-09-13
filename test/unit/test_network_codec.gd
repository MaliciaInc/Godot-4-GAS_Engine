## What a message becomes on a wire, and what a wire is not allowed to become.
##
## Both halves in one suite, because a codec is only ever right as a pair: an
## encoder and a decoder tested apart agree with each other's mistakes. Every
## message here goes out and comes back, and what comes back is compared with
## what went in.
##
## The refusals matter as much as the round trips. A receiver that guessed at a
## packet it did not understand would be a receiver constructing state from
## whatever a sender happened to send, and the failure mode is two processes
## quietly disagreeing about a character.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const ENTITY: int = 42
const DEFINITION: int = 7
const TOLERANCE: float = 0.0001

const HEALTH: StringName = &"health"
const BURNING: StringName = &"Status.Burning"
const CUE: StringName = &"Cue.Impact"


#region Getting there
func _entity() -> GameplayNetEntityId:
	return GameplayNetEntityId.of(ENTITY)


func _round_tripped(message: GameplayNetMessage) -> GameplayNetMessage:
	var packet: PackedByteArray = GameplayNetCodec.encode(message)
	assert_false(packet.is_empty(), "a complete message encodes to something")
	return GameplayNetCodec.decode(packet)


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


## The game's own payload crosses untouched and unread.
func test_a_game_s_own_payload_crosses_untouched() -> void:
	var sent: GameplayNetMessage = GameplayNetMessage.of(
		GameplayNetMessage.Kind.CUE, _entity()
	)
	sent.payload = {"cue": "Cue.Impact", "loudness": 0.5}

	var back: GameplayNetMessage = _round_tripped(sent)

	assert_not_null(back, "it decoded")
	var cue: String = str(back.payload.get("cue", ""))
	var loudness: float = back.payload.get("loudness", 0.0)
	assert_eq(cue, "Cue.Impact", "the game's own key")
	assert_almost_eq(loudness, 0.5, TOLERANCE, "and value")
#endregion


#region What a wire may not become
## A message that is not complete does not become a packet.
##
## Refused here rather than by the far side: a grant with no definition is a bug
## on this side, and finding it here is better than finding it there.
func test_an_incomplete_message_encodes_to_nothing() -> void:
	var missing: GameplayNetMessage = GameplayNetMessage.of(
		GameplayNetMessage.Kind.GRANT, _entity()
	)

	assert_true(
		GameplayNetCodec.encode(missing).is_empty(),
		"a grant naming no definition is not put on a wire"
	)
	assert_true(GameplayNetCodec.encode(null).is_empty(), "and neither is nothing")


## The last three rows are numbers written as something else. `int()` reads
## `"1"` as 1 and `"five"` as 0 without complaining, so a wire disagreeing
## about the contract used to be read as a wire that agreed - and for a
## schema version that is the one field whose whole job is to catch this.
##     [what arrived, the bytes, why it is refused]
func _malformed_cases() -> Array:
	return [
		["nothing at all", PackedByteArray(), GameplayNetCodec.REASON_MALFORMED],
		["something that is not text", PackedByteArray([0xFF, 0xFE, 0x00]), GameplayNetCodec.REASON_MALFORMED],
		["text that is not JSON", "not json".to_utf8_buffer(), GameplayNetCodec.REASON_MALFORMED],
		["JSON that is not an object", "[1,2,3]".to_utf8_buffer(), GameplayNetCodec.REASON_MALFORMED],
		["an object from a version this does not speak", '{"wire.v":2,"wire.kind":0}'.to_utf8_buffer(), GameplayNetCodec.REASON_UNSUPPORTED_SCHEMA],
		["an object with no version at all", '{"wire.kind":0}'.to_utf8_buffer(), GameplayNetCodec.REASON_UNSUPPORTED_SCHEMA],
		["a kind that is not one", '{"wire.v":1,"wire.kind":99,"wire.entity":42}'.to_utf8_buffer(), GameplayNetCodec.REASON_MALFORMED],
		["a grant with no definition", '{"wire.v":1,"wire.kind":0,"wire.entity":42}'.to_utf8_buffer(), GameplayNetCodec.REASON_INCOMPLETE],
		["a state that is not one", '{"wire.v":1,"wire.kind":5,"wire.entity":42,"wire.state":7}'.to_utf8_buffer(), GameplayNetCodec.REASON_MALFORMED],
	["a version written as text", '{"wire.v":"1","wire.kind":0}'.to_utf8_buffer(), GameplayNetCodec.REASON_UNSUPPORTED_SCHEMA],
	["a version with a fraction in it", '{"wire.v":1.5,"wire.kind":0}'.to_utf8_buffer(), GameplayNetCodec.REASON_UNSUPPORTED_SCHEMA],
	["a kind written as text", '{"wire.v":1,"wire.kind":"0","wire.entity":42}'.to_utf8_buffer(), GameplayNetCodec.REASON_MALFORMED],
	]


func test_a_packet_that_is_not_a_message_is_refused_and_says_why(
	case: Array = use_parameters(_malformed_cases())
) -> void:
	var described: String = case[0]
	var packet: PackedByteArray = case[1]
	var reason: StringName = case[2]

	assert_null(GameplayNetCodec.decode(packet), described)
	assert_eq(GameplayNetCodec.last_refusal, reason, "refused as `%s`" % reason)


## A state carrying an effect that is not one takes the whole message with it.
##
## Applied with one effect silently missing, the two processes disagree about
## the character - and disagreeing quietly is what this refuses.
func test_a_state_with_a_broken_effect_refuses_the_whole_message() -> void:
	var packet: PackedByteArray = (
		'{"wire.v":1,"wire.kind":5,"wire.entity":42,"wire.state":{"state.kind":0,"state.effects":[7]}}'
	).to_utf8_buffer()

	assert_null(GameplayNetCodec.decode(packet), "the message is refused")
	assert_eq(GameplayNetCodec.last_refusal, GameplayNetCodec.REASON_MALFORMED)


## Nothing decodes into an object.
##
## Godot can put one in a packet and take one out, and a receiver that allowed
## it would construct whatever class the far side named. What arrives here is
## numbers and strings, and a payload that claims to be an object is a payload
## of strings.
func test_nothing_a_wire_says_becomes_an_object() -> void:
	var packet: PackedByteArray = (
		'{"wire.v":1,"wire.kind":7,"wire.entity":42,"wire.payload":{"o":{"__class__":"Node"}}}'
	).to_utf8_buffer()

	var back: GameplayNetMessage = GameplayNetCodec.decode(packet)

	assert_not_null(back, "it decoded, because a payload is the game's own")
	var carried: Variant = back.payload.get("o")
	assert_true(carried is Dictionary, "and what it carries is data, not a Node")
	assert_false(carried is Object, "nothing was constructed")
#endregion
