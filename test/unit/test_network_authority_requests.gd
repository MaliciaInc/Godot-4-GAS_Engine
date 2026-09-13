## The five things a client may send beyond a request, and what the authority
## does with each.
##
## Every one of them is something a client is asking the authority to do on its
## behalf, so every one of them is a place a client could ask for something it
## is not entitled to. What is checked is that each arrives, that each is
## refused for the right reason when it should be, and - the part that matters -
## that none of them travels the other way.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const AbilityFactory = preload("res://test/fixtures/test_ability_factory.gd")
const Probe = preload("res://test/fixtures/probe_ability.gd")

const ENTITY: int = 21
const OWNING_PEER: int = 2
const ABILITY_TAG: StringName = &"Ability.Net"
const EVENT_TAG: StringName = &"Event.Sent"
const A_PATH: String = "res://test_only/requests_probe.tscn"

var authority: GameplayNetworkRuntime = null
var client: GameplayNetworkRuntime = null
var fixture: ASCFixture = null
var asc: AbilitySystemComponent = null
var entity: GameplayNetEntityId = null
var refusals: Array[StringName] = []

## The ability that does the aiming, running so that its providers count as
## previewing.
var aimer: GameplayAbility = null


func before_each() -> void:
	refusals = []
	var bench: AimingBench = AimingBench.built(self, "Asked")
	autofree(bench.fixture.owner)
	autofree(bench.body)
	fixture = bench.fixture
	asc = fixture.asc
	asc.set_process(false)
	# Channelled rather than told not to auto-end: the auto-end flag is read
	# from the frozen definition, so setting it on the instance after the
	# grant changes nothing and the ability was over before it could aim.
	aimer = bench.ability
	var channelled: ProbeAbility = aimer as ProbeAbility
	channelled.channels = true
	asc.try_activate_ability_handle(aimer.get_ability_handle())
	entity = GameplayNetEntityId.of(ENTITY)

	authority = GameplayNetworkRuntime.new()
	authority.role = GameplayNetAuthority.Role.AUTHORITY
	authority.attach(asc, entity, OWNING_PEER)
	authority.message_refused.connect(
		func(_message: GameplayNetMessage, reason: StringName) -> void:
			refusals.append(reason)
	)

	client = GameplayNetworkRuntime.new()
	client.role = GameplayNetAuthority.Role.CLIENT
	client.peer = OWNING_PEER
	client.attach(asc, entity, OWNING_PEER)


func after_each() -> void:
	authority.dispose()
	client.dispose()
	authority = null
	client = null
	fixture = null
	asc = null
	entity = null


#region Which way each of them travels
## A client asks; an authority never asks a client.
##
## The rule used to be "everything except the request", which was right while
## there was one thing a client could ask for. F6.6 gave it five more, and a
## rule written that way would have let a confirm travel in both directions -
## which is one machine cancelling another ability.
##
##     [what it is, the kind, whether a client sends it to the authority]
func _direction_cases() -> Array:
	return [
		["an activation request", GameplayNetMessage.Kind.ACTIVATION_REQUEST, true],
		["an aim", GameplayNetMessage.Kind.TARGET_DATA, true],
		["a confirm", GameplayNetMessage.Kind.GENERIC_CONFIRM, true],
		["a cancel", GameplayNetMessage.Kind.GENERIC_CANCEL, true],
		["a press", GameplayNetMessage.Kind.INPUT_PRESSED, true],
		["a release", GameplayNetMessage.Kind.INPUT_RELEASED, true],
		["a grant", GameplayNetMessage.Kind.GRANT, false],
		["a state reading", GameplayNetMessage.Kind.STATE_SNAPSHOT, false],
		["a confirmation of an activation", GameplayNetMessage.Kind.ACTIVATION_CONFIRM, false],
	]


## An event and a batch travel in either direction, which the rule above cannot
## say on its own.
##
## An authority telling clients that something happened and a client telling the
## authority that something did are both ordinary, and a rule that picked one
## would make the other impossible to express.
func test_an_event_and_a_batch_travel_in_either_direction() -> void:
	for kind: GameplayNetMessage.Kind in [
		GameplayNetMessage.Kind.GAMEPLAY_EVENT,
		GameplayNetMessage.Kind.BATCH,
	]:
		assert_true(
			GameplayNetAuthority.EITHER_WAY.has(kind),
			"%d goes both ways" % int(kind)
		)
		assert_false(
			GameplayNetAuthority.ASKED_OF_THE_AUTHORITY.has(kind),
			"and is not one of the things only a client asks for"
		)


func test_each_kind_travels_one_way_only(
	case: Array = use_parameters(_direction_cases())
) -> void:
	var described: String = case[0]
	var kind: GameplayNetMessage.Kind = case[1]
	var towards_authority: bool = case[2]

	assert_eq(
		GameplayNetAuthority.ASKED_OF_THE_AUTHORITY.has(kind),
		towards_authority,
		"%s: %s" % [described, "asked of the authority" if towards_authority else "told to a client"]
	)
#endregion


#region An aim
## An aim reaches the provider that is waiting for it.
func test_an_aim_reaches_the_provider_waiting_for_it() -> void:
	var provider: GameplayLocationProvider3D = _aiming()
	var heard: Array[GameplayAbilityTargetData] = []
	provider.confirmed.connect(func(data: GameplayAbilityTargetData) -> void:
		heard.append(data)
	)

	assert_true(authority.receive(_an_aim_at(Vector3(1.0, 0.0, 2.0))), "it was accepted")
	assert_eq(heard.size(), 1, "and reached the provider")
	assert_true(heard[0].has_locations(), "carrying the place that was aimed at")


## An aim with nobody waiting for it is refused as unreachable.
##
## Not "invalid": the claim may be perfectly well formed, and what is wrong is
## that there is nothing on this machine it could be an answer to.
func test_an_aim_nobody_is_waiting_for_is_unreachable() -> void:
	assert_false(authority.receive(_an_aim_at(Vector3.ZERO)), "it was refused")
	assert_eq(
		refusals, [GameplayNetworkRuntime.REASON_TARGET_UNREACHABLE] as Array[StringName],
		"because nothing on this machine was waiting for one"
	)


## An aim outside what the provider could have produced is refused as invalid.
##
## The check the provider itself performs. A client that claimed a spot beyond
## its own reach is a client claiming something no provider of that kind would
## have confirmed.
func test_an_aim_the_provider_could_not_have_produced_is_invalid() -> void:
	var provider: GameplayLocationProvider3D = _aiming()
	provider.max_range = 2.0

	assert_false(
		authority.receive(_an_aim_at(Vector3(500.0, 0.0, 0.0))), "it was refused"
	)
	assert_eq(
		refusals, [GameplayNetworkRuntime.REASON_TARGET_INVALID] as Array[StringName],
		"because the provider would never have confirmed it"
	)


## An aim naming somebody this machine has never registered is refused as
## unknown.
##
## Three refusals rather than one, because they are three different things a
## client can be wrong about and a game reacting to one wants to know which.
func test_an_aim_naming_somebody_who_is_not_here_is_unknown() -> void:
	_aiming()
	# Written by the translator against a registry that knows the stranger, and
	# read by one that does not - which is what an aim naming somebody the
	# authority has never registered actually looks like. A hit built by hand
	# would be refused for its shape and prove nothing about identity.
	var elsewhere: GameplayNetRegistry = GameplayNetRegistry.new()
	var stranger: ASCFixture = Fixture.create("Stranger")
	add_child_autofree(stranger.owner)
	elsewhere.register_entity(GameplayNetEntityId.of(9999), stranger.asc, 7)

	var aimed: GameplayAbilityTargetData = GameplayAbilityTargetData.new()
	aimed.append_node(stranger.owner)
	var message: GameplayNetMessage = GameplayNetMessage.of(
		GameplayNetMessage.Kind.TARGET_DATA, entity
	)
	message.activation = _the_activation()
	message.prediction_key = _the_key()
	message.payload[GameplayNetMessage.TARGET_DATA_KEY] = (
		GameplayTargetDataTranslator.to_wire(aimed, elsewhere)
	)

	assert_false(authority.receive(message), "it was refused")
	assert_eq(
		refusals, [GameplayNetworkRuntime.REASON_TARGET_UNKNOWN] as Array[StringName],
		"because nobody here is that entity"
	)


## Something that is not an aim at all is refused as invalid.
func test_something_that_is_not_an_aim_is_invalid() -> void:
	_aiming()
	var message: GameplayNetMessage = GameplayNetMessage.of(
		GameplayNetMessage.Kind.TARGET_DATA, entity
	)
	message.activation = _the_activation()
	message.prediction_key = _the_key()
	message.payload[GameplayNetMessage.TARGET_DATA_KEY] = {"nonsense": true}

	assert_false(authority.receive(message), "it was refused")
	assert_eq(
		refusals, [GameplayNetworkRuntime.REASON_TARGET_INVALID] as Array[StringName]
	)
#endregion


#region Yes and no
## A confirm and a cancel reach the component's own doors.
##
## The same doors a local press reaches, which is the point: an ability waiting
## on a confirm cannot tell whether the player who confirmed was sitting at this
## machine.
func test_a_confirm_and_a_cancel_reach_the_component() -> void:
	var confirmed: Array[bool] = []
	var cancelled: Array[bool] = []
	asc.generic_confirmed.connect(func() -> void: confirmed.append(true))
	asc.generic_cancelled.connect(func() -> void: cancelled.append(true))

	assert_true(
		authority.receive(GameplayNetMessage.of(GameplayNetMessage.Kind.GENERIC_CONFIRM, entity)),
		"the confirm was accepted"
	)
	assert_eq(confirmed.size(), 1, "and reached the component")

	assert_true(
		authority.receive(GameplayNetMessage.of(GameplayNetMessage.Kind.GENERIC_CANCEL, entity)),
		"and so was the cancel"
	)
	assert_eq(cancelled.size(), 1, "which reached it too")
#endregion


#region An event
## An event crosses in the one shape events cross in, and arrives as one.
func test_an_event_crosses_and_arrives_as_an_event() -> void:
	var heard: Array[StringName] = []
	asc.gameplay_event_received.connect(func(event: GameplayEventData) -> void:
		heard.append(event.event_tag)
	)

	var sent: GameplayEventData = GameplayEventData.new()
	sent.event_tag = EVENT_TAG
	sent.magnitude = 3.0
	var message: GameplayNetMessage = client.send_gameplay_event(entity, sent)

	assert_not_null(message, "it became a message")
	assert_true(authority.receive(message), "which was accepted")
	assert_eq(heard, [EVENT_TAG] as Array[StringName], "and arrived as an event")


## An event message carrying something that is not one is refused.
func test_an_event_message_carrying_nonsense_is_refused() -> void:
	var message: GameplayNetMessage = GameplayNetMessage.of(
		GameplayNetMessage.Kind.GAMEPLAY_EVENT, entity
	)
	message.payload[GameplayNetMessage.EVENT_KEY] = {"not": "an event"}

	assert_false(authority.receive(message), "it was refused")
	assert_eq(refusals.size(), 1, "and said so")
#endregion


#region An input
## An input is resolved by the definition the authority granted, not by a
## handle the client made up.
func test_an_input_is_resolved_by_definition_rather_than_by_a_handle() -> void:
	var scene: PackedScene = AbilityFactory.net_ability(
		GameplayAbility.NetExecutionPolicy.SERVER_INITIATED, A_PATH, ABILITY_TAG
	)
	authority.registry.register_definition(scene)
	client.registry.register_definition(scene)

	var message: GameplayNetMessage = client.send_input(entity, scene, 4, true)

	assert_not_null(message, "it became a message")
	assert_eq(message.kind, GameplayNetMessage.Kind.INPUT_PRESSED, "a press")
	assert_true(message.definition.is_valid(), "naming the definition")
	assert_true(authority.receive(message), "and the authority accepted it")


## An input naming a definition the authority has never registered is refused.
func test_an_input_naming_an_unknown_definition_is_refused() -> void:
	var message: GameplayNetMessage = GameplayNetMessage.of(
		GameplayNetMessage.Kind.INPUT_RELEASED, entity
	)
	message.definition = GameplayNetDefinitionId.from_wire(4242)
	message.payload[GameplayNetMessage.INPUT_KEY] = 1

	assert_false(authority.receive(message), "it was refused")
	assert_eq(
		refusals, [GameplayNetworkRuntime.REASON_UNKNOWN_DEFINITION] as Array[StringName]
	)
#endregion


#region Getting there
## The run every aim in this file is for. One activation is enough here - the
## suite is about the three ways an aim itself can be wrong, not about
## AUD-09's own routing between two concurrent ones, which
## `test_network_peer_identity.gd` covers.
func _the_activation() -> GameplayNetActivationId:
	return GameplayNetActivationId.of(entity, 1)


## The guess every aim in this file rides on. One is enough for the same
## reason one activation is: this suite is about how an aim itself can be
## wrong, not about whose guess it was.
func _the_key() -> GameplayPredictionKey:
	return GameplayPredictionKey.of(OWNING_PEER, 1)


## A provider previewing on this entity, so an aim has something to answer.
##
## Through a running ability rather than registered directly, because that is
## the only way a provider is ever previewing: the runtime finds them by asking
## every live ability what it is aiming with, and a provider nobody is aiming
## with is not waiting for anything. Claimed under `_the_activation()`, the
## same run every message built here names.
func _aiming() -> GameplayLocationProvider3D:
	var provider: GameplayLocationProvider3D = GameplayLocationProvider3D.new()
	provider.max_range = 0.0
	aimer.aim_with(provider)
	provider.claim(_the_activation())
	return provider


func _an_aim_at(spot: Vector3) -> GameplayNetMessage:
	var data: GameplayAbilityTargetData = GameplayAbilityTargetData.new()
	data.append_location(spot)
	var message: GameplayNetMessage = GameplayNetMessage.of(
		GameplayNetMessage.Kind.TARGET_DATA, entity
	)
	message.activation = _the_activation()
	message.prediction_key = _the_key()
	message.payload[GameplayNetMessage.TARGET_DATA_KEY] = (
		GameplayTargetDataTranslator.to_wire(data, authority.registry)
	)
	return message
#endregion
