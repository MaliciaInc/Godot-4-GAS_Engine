## How packets leave and arrive, and what the runtime does once one does.
##
## Three things: that a runtime with no transport behaves exactly as it always
## did, that a runtime with one puts what it announces on the wire and acts on
## what comes off it, and that the adapter over Godot's own multiplayer is bound
## the way it says it is.
##
## The two-process claim is not made here - F6.6.7 makes it. What is made here
## is that everything between the runtime and the socket is right, so that when
## two processes disagree, this is not where to look.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Probe = preload("res://test/fixtures/probe_ability.gd")
const AbilityFactory = preload("res://test/fixtures/test_ability_factory.gd")

const ENTITY: int = 11
const ABILITY_TAG: StringName = &"Ability.Probe"

var authority: GameplayNetworkRuntime = null
var client: GameplayNetworkRuntime = null
var wires: Array[LoopbackTransport] = []


func before_each() -> void:
	authority = GameplayNetworkRuntime.new()
	authority.role = GameplayNetAuthority.Role.AUTHORITY
	client = GameplayNetworkRuntime.new()
	client.role = GameplayNetAuthority.Role.CLIENT
	wires = LoopbackTransport.pair()


func after_each() -> void:
	authority.dispose()
	client.dispose()
	authority = null
	client = null
	wires = []


#region The base
## A transport nobody implemented answers "nothing is connected" to everything.
##
## Not a stub: a runtime with no transport is what a single-player game has, and
## every one of these has to be safe there rather than guarded at each call.
func test_the_base_transport_is_safe_to_ask_anything() -> void:
	var nothing: GameplayNetTransport = GameplayNetTransport.new()

	assert_false(nothing.send(PackedByteArray([1]), 1), "it sends nothing")
	assert_eq(nothing.local_peer(), GameplayNetRegistry.NO_PEER, "it is nobody")
	assert_eq(nothing.peers().size(), 0, "and knows nobody")
	assert_false(nothing.is_connected_to_network(), "and says so")
#endregion


#region With a wire and without one
## Without a transport, the runtime announces and nothing leaves.
##
## The baseline the whole suite is built on: a caller carrying messages itself
## is what every network test did before this, and it still works.
func test_without_a_transport_a_message_is_announced_and_nothing_leaves() -> void:
	var heard: Array[GameplayNetMessage] = []
	authority.message_ready.connect(func(message: GameplayNetMessage) -> void:
		heard.append(message)
	)
	_grant_something(authority)

	assert_eq(heard.size(), 1, "it was announced")
	assert_eq(wires[0].sent.size(), 0, "and nothing was put on a wire nobody set")


## With one, what is announced is also encoded and sent.
func test_with_a_transport_what_is_announced_is_also_sent() -> void:
	authority.set_transport(wires[0])

	_grant_something(authority)

	assert_eq(wires[0].sent.size(), 1, "one packet went out")
	var back: GameplayNetMessage = GameplayNetCodec.decode(wires[0].sent[0])
	assert_not_null(back, "and it is a message")
	assert_eq(back.kind, GameplayNetMessage.Kind.GRANT, "the one that was announced")


## What arrives off the wire goes through the same door a direct call does.
func test_what_arrives_off_the_wire_goes_through_the_one_door() -> void:
	client.set_transport(wires[1])
	var heard: Array[GameplayNetMessage] = []
	client.message_refused.connect(
		func(message: GameplayNetMessage, _reason: StringName) -> void:
			heard.append(message)
	)

	# A state reading about an entity this client has never registered: refused
	# for not knowing the entity, which is the door doing its job.
	var reading: GameplayNetMessage = GameplayNetMessage.of(
		GameplayNetMessage.Kind.STATE_SNAPSHOT, GameplayNetEntityId.of(ENTITY)
	)
	reading.state = GameplayNetState.snapshot()
	wires[0].send(GameplayNetCodec.encode(reading), 2)

	assert_eq(heard.size(), 1, "it arrived and was judged")


## A packet that is not a message is refused with the codec's own reason.
##
## A peer speaking a version this build does not is a thing somebody has to be
## able to find out, and a dropped packet says nothing.
func test_a_packet_that_is_not_a_message_says_why_it_was_refused() -> void:
	client.set_transport(wires[1])
	var reasons: Array[StringName] = []
	client.message_refused.connect(
		func(_message: GameplayNetMessage, reason: StringName) -> void:
			reasons.append(reason)
	)

	wires[0].send('{"v":2,"kind":0}'.to_utf8_buffer(), 2)

	assert_eq(reasons.size(), 1, "it was refused")
	assert_eq(
		reasons[0], GameplayNetCodec.REASON_UNSUPPORTED_SCHEMA,
		"saying the far side speaks a version this build does not"
	)


## Binding twice does not deliver twice.
##
## Every packet arriving twice is one ability activating twice, and for a state
## delta it is nothing at all - so it is only ever noticed by the half that
## hurts.
func test_binding_a_second_transport_lets_go_of_the_first() -> void:
	client.set_transport(wires[1])
	client.set_transport(wires[1])

	var arrivals: Array[StringName] = []
	client.message_refused.connect(
		func(_message: GameplayNetMessage, reason: StringName) -> void:
			arrivals.append(reason)
	)
	wires[0].send("not json".to_utf8_buffer(), 2)

	assert_eq(arrivals.size(), 1, "one packet, judged once")


## A snapshot may be lost; nothing else may.
##
## A snapshot says everything the lost one did, so the next one repairs it. A
## delta carries what changed, and what changed is gone with the packet.
##
##     [what it is, the kind, whether it must arrive]
func _reliability_cases() -> Array:
	return [
		["a snapshot", GameplayNetMessage.Kind.STATE_SNAPSHOT, false],
		["a delta", GameplayNetMessage.Kind.STATE_DELTA, true],
		["a grant", GameplayNetMessage.Kind.GRANT, true],
		["an activation request", GameplayNetMessage.Kind.ACTIVATION_REQUEST, true],
		["a cue", GameplayNetMessage.Kind.CUE, true],
	]


func test_only_a_snapshot_may_be_lost(
	case: Array = use_parameters(_reliability_cases())
) -> void:
	var described: String = case[0]
	var kind: GameplayNetMessage.Kind = case[1]
	var must_arrive: bool = case[2]

	var message: GameplayNetMessage = GameplayNetMessage.of(
		kind, GameplayNetEntityId.of(ENTITY)
	)
	assert_eq(authority._must_arrive(message), must_arrive, described)
#endregion


#region Over Godot's own multiplayer
## The adapter binds, refuses object decoding, and lets go again.
##
## Object decoding is the one thing this must never turn on: a peer that allowed
## it would construct whatever class the far side named, which is remote code
## execution wearing a serialisation format.
func test_the_multiplayer_adapter_binds_without_allowing_objects() -> void:
	var adapter: GameplayNetTransportMultiplayer = GameplayNetTransportMultiplayer.new()
	var api: SceneMultiplayer = SceneMultiplayer.new()
	api.allow_object_decoding = true

	assert_true(adapter.bind(api), "it bound")
	assert_false(api.allow_object_decoding, "and turned object decoding off")
	assert_true(api.peer_packet.is_connected(adapter._on_peer_packet), "and is listening")

	adapter.unbind()
	assert_false(
		api.peer_packet.is_connected(adapter._on_peer_packet),
		"and stops listening when it lets go"
	)
	assert_null(adapter.api, "holding nothing afterwards")


## Binding a second time lets go of the first, so a packet is not heard twice.
func test_the_adapter_binding_twice_listens_once() -> void:
	var adapter: GameplayNetTransportMultiplayer = GameplayNetTransportMultiplayer.new()
	var first: SceneMultiplayer = SceneMultiplayer.new()
	var second: SceneMultiplayer = SceneMultiplayer.new()

	adapter.bind(first)
	adapter.bind(second)

	assert_false(
		first.peer_packet.is_connected(adapter._on_peer_packet),
		"the first one is no longer being listened to"
	)
	assert_true(second.peer_packet.is_connected(adapter._on_peer_packet), "the second one is")
	adapter.unbind()


## Off a network, the adapter answers the same as no transport at all.
func test_the_adapter_off_a_network_answers_like_nothing_at_all() -> void:
	var adapter: GameplayNetTransportMultiplayer = GameplayNetTransportMultiplayer.new()

	assert_false(adapter.is_connected_to_network(), "nothing is connected")
	assert_eq(adapter.local_peer(), GameplayNetRegistry.NO_PEER, "it is nobody")
	assert_eq(adapter.peers().size(), 0, "and knows nobody")
	assert_false(adapter.send(PackedByteArray([1]), 1), "and sends nothing")

	var api: SceneMultiplayer = SceneMultiplayer.new()
	adapter.bind(api)
	assert_false(
		adapter.is_connected_to_network(),
		"bound to a multiplayer with no peer, it is still not on a network"
	)
	adapter.unbind()
#endregion


#region Getting there
func _grant_something(runtime: GameplayNetworkRuntime) -> void:
	var fixture: ASCFixture = Fixture.create("Granted")
	add_child_autofree(fixture.owner)
	var id: GameplayNetEntityId = GameplayNetEntityId.of(ENTITY)
	runtime.registry.register_entity(id, fixture.asc, 2)

	# At a path, because a definition that lives nowhere cannot be named to
	# another machine - which is what a net definition id is.
	var scene: PackedScene = AbilityFactory.net_ability(
		GameplayAbility.NetExecutionPolicy.SERVER_INITIATED,
		"res://test_only/transport_probe.tscn",
		ABILITY_TAG
	)
	assert_true(runtime.grant(id, scene), "the authority granted something")
#endregion
