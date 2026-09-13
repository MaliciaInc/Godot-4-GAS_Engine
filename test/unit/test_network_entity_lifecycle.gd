## What the registry and the runtime remember about one entity, and what
## letting go of it actually lets go of.
##
## Three questions that used to have the wrong answer. Two tables turn a name
## into a thing and back - `_asc_by_entity` and `_entity_by_asc` - and only the
## first direction was ever checked, so one component could be told it named
## two different entities and both tables would go on agreeing with whichever
## half had last been written. A component already pointed at one runtime
## could be pointed at a second while the first runtime's own registry still
## believed it owned it. And detaching an entity forgot who it was without
## forgetting what had already happened to it - a run counter, a duplicate
## fingerprint, a replication mode - so the next character given that id
## inherited a stranger's history.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const AbilityFactory = preload("res://test/fixtures/test_ability_factory.gd")

const OWNING_PEER: int = 2
const OTHER_PEER: int = 3


func _asc(named: String) -> AbilitySystemComponent:
	var fixture: ASCFixture = Fixture.create(named)
	add_child_autofree(fixture.owner)
	return fixture.asc


#region AUD-03: the registry is a bijection
## One component cannot be told it names two different entities.
func test_one_component_cannot_answer_to_two_entities() -> void:
	var registry: GameplayNetRegistry = GameplayNetRegistry.new()
	var asc: AbilitySystemComponent = _asc("Split")
	var first: GameplayNetEntityId = GameplayNetEntityId.of(1)
	var second: GameplayNetEntityId = GameplayNetEntityId.of(2)

	assert_true(registry.register_entity(first, asc, OWNING_PEER))
	assert_false(
		registry.register_entity(second, asc, OWNING_PEER),
		"the same component under a second id is refused"
	)
	assert_true(registry.entity_for(asc).same_as(first), "and still names the first")
	assert_null(registry.asc_for(second), "the second id names nobody")


## A repeated registration is idempotent only while nothing about it changes.
## An owner or a mode that has is a transfer, and a transfer is refused here -
## it goes through `set_owner()` or `set_replication_mode()` instead.
func test_a_repeated_registration_with_a_different_owner_is_refused() -> void:
	var registry: GameplayNetRegistry = GameplayNetRegistry.new()
	var asc: AbilitySystemComponent = _asc("Reregistered")
	var id: GameplayNetEntityId = GameplayNetEntityId.of(1)
	registry.register_entity(id, asc, OWNING_PEER)

	assert_false(
		registry.register_entity(id, asc, OTHER_PEER),
		"a silent change of owner through the retransmission door"
	)
	assert_true(registry.is_owned_by(id, OWNING_PEER), "ownership did not move")

	assert_true(registry.set_owner(id, OTHER_PEER), "the dedicated door works")
	assert_true(registry.is_owned_by(id, OTHER_PEER))


func test_set_owner_on_nobody_is_refused() -> void:
	var registry: GameplayNetRegistry = GameplayNetRegistry.new()
	assert_false(registry.set_owner(GameplayNetEntityId.of(99), OWNING_PEER))
#endregion


#region AUD-04: one component, one runtime
## A second runtime cannot take over a component the first still holds.
func test_a_second_runtime_cannot_attach_what_the_first_already_holds() -> void:
	var asc: AbilitySystemComponent = _asc("Contested")
	var first: GameplayNetworkRuntime = GameplayNetworkRuntime.new()
	first.role = GameplayNetAuthority.Role.AUTHORITY
	var second: GameplayNetworkRuntime = GameplayNetworkRuntime.new()
	second.role = GameplayNetAuthority.Role.AUTHORITY
	var id: GameplayNetEntityId = GameplayNetEntityId.of(1)

	assert_true(first.attach(asc, id, OWNING_PEER))
	assert_false(second.attach(asc, id, OWNING_PEER), "the second runtime is refused")
	assert_same(asc.network, first, "the reference never moved")
	assert_same(first.registry.asc_for(id), asc, "and the first registry still has it")
	assert_null(second.registry.asc_for(id), "the second registry never got it")

	first.dispose()
	second.dispose()


## Re-attaching to the SAME runtime is not the case above: it is the ordinary
## retransmission `register_entity` already allows.
func test_reattaching_to_the_same_runtime_is_still_fine() -> void:
	var asc: AbilitySystemComponent = _asc("Retold")
	var runtime: GameplayNetworkRuntime = GameplayNetworkRuntime.new()
	runtime.role = GameplayNetAuthority.Role.AUTHORITY
	var id: GameplayNetEntityId = GameplayNetEntityId.of(1)

	assert_true(runtime.attach(asc, id, OWNING_PEER))
	assert_true(runtime.attach(asc, id, OWNING_PEER), "told twice about the same entity")
	runtime.dispose()


## Detaching gives the reference back, so a legitimately later attachment to a
## different runtime is not the AUD-04 case at all.
func test_detaching_frees_a_component_for_a_different_runtime() -> void:
	var asc: AbilitySystemComponent = _asc("Handed Off")
	var first: GameplayNetworkRuntime = GameplayNetworkRuntime.new()
	first.role = GameplayNetAuthority.Role.AUTHORITY
	var second: GameplayNetworkRuntime = GameplayNetworkRuntime.new()
	second.role = GameplayNetAuthority.Role.AUTHORITY
	var id: GameplayNetEntityId = GameplayNetEntityId.of(1)

	first.attach(asc, id, OWNING_PEER)
	first.detach(asc)

	assert_true(second.attach(asc, id, OWNING_PEER), "let go, and free to be somebody else's")
	assert_same(asc.network, second)
	first.dispose()
	second.dispose()
#endregion


#region AUD-05: detach purges what this runtime remembers
## An id reused by a different character starts its run count over rather
## than continuing whoever had it before's count.
func test_a_reused_id_starts_its_run_counter_over() -> void:
	var runtime: GameplayNetworkRuntime = GameplayNetworkRuntime.new()
	runtime.role = GameplayNetAuthority.Role.AUTHORITY
	var id: GameplayNetEntityId = GameplayNetEntityId.of(1)
	var scene: PackedScene = AbilityFactory.net_ability(
		GameplayAbility.NetExecutionPolicy.LOCAL_PREDICTED, "res://test_only/lifecycle_probe.tscn"
	)
	runtime.registry.register_definition(scene)

	var first_owner: AbilitySystemComponent = _asc("First")
	runtime.attach(first_owner, id, OWNING_PEER)
	var asking: GameplayNetMessage = GameplayNetMessage.of(
		GameplayNetMessage.Kind.ACTIVATION_REQUEST, id
	)
	asking.definition = GameplayNetDefinitionId.of_resource(scene)
	asking.prediction_key = GameplayPredictionKey.of(OWNING_PEER, 1)
	var answers: Array[GameplayNetMessage] = []
	runtime.message_ready.connect(func(m: GameplayNetMessage) -> void: answers.append(m))
	runtime.receive(asking)
	assert_eq(answers[0].activation.sequence, 1, "the first run of a fresh entity")

	runtime.detach(first_owner)
	var second_owner: AbilitySystemComponent = _asc("Second")
	runtime.attach(second_owner, id, OTHER_PEER)
	answers.clear()
	var asking_again: GameplayNetMessage = GameplayNetMessage.of(
		GameplayNetMessage.Kind.ACTIVATION_REQUEST, id
	)
	asking_again.definition = GameplayNetDefinitionId.of_resource(scene)
	asking_again.prediction_key = GameplayPredictionKey.of(OTHER_PEER, 1)
	runtime.receive(asking_again)

	assert_eq(
		answers[0].activation.sequence, 1,
		"the next occupant's first run, not a continuation of the last one's"
	)
	runtime.dispose()


## A message fingerprint that happened to repeat under a reused id is not
## mistaken for a duplicate of what the last occupant already did.
func test_a_reused_id_does_not_inherit_the_last_occupants_seen_messages() -> void:
	var runtime: GameplayNetworkRuntime = GameplayNetworkRuntime.new()
	runtime.role = GameplayNetAuthority.Role.AUTHORITY
	var id: GameplayNetEntityId = GameplayNetEntityId.of(1)

	var first_owner: AbilitySystemComponent = _asc("Fingerprinted First")
	runtime.attach(first_owner, id, OWNING_PEER)
	assert_true(runtime.receive(GameplayNetMessage.of(GameplayNetMessage.Kind.GENERIC_CONFIRM, id)))
	assert_false(
		runtime.receive(GameplayNetMessage.of(GameplayNetMessage.Kind.GENERIC_CONFIRM, id)),
		"the repeat is refused, while it is still about the first occupant"
	)

	runtime.detach(first_owner)
	var second_owner: AbilitySystemComponent = _asc("Fingerprinted Second")
	runtime.attach(second_owner, id, OWNING_PEER)
	var confirmed: Array[bool] = []
	second_owner.generic_confirmed.connect(func() -> void: confirmed.append(true))

	assert_true(
		runtime.receive(GameplayNetMessage.of(GameplayNetMessage.Kind.GENERIC_CONFIRM, id)),
		"the identical message is news again for the new occupant"
	)
	assert_eq(confirmed.size(), 1)
	runtime.dispose()


## A replication mode set on one occupant does not survive to the next.
func test_a_reused_id_does_not_inherit_the_last_occupants_replication_mode() -> void:
	var runtime: GameplayNetworkRuntime = GameplayNetworkRuntime.new()
	runtime.role = GameplayNetAuthority.Role.AUTHORITY
	var id: GameplayNetEntityId = GameplayNetEntityId.of(1)

	var first_owner: AbilitySystemComponent = _asc("Minimal First")
	runtime.attach(first_owner, id, OWNING_PEER)
	runtime.registry.set_replication_mode(id, GameplayNetReplication.Mode.MINIMAL)
	runtime.detach(first_owner)

	var second_owner: AbilitySystemComponent = _asc("Full Second")
	runtime.attach(second_owner, id, OWNING_PEER)

	assert_eq(
		runtime.registry.replication_mode_for(id, GameplayNetReplication.Mode.FULL),
		GameplayNetReplication.Mode.FULL,
		"the new occupant follows the runtime's own default, not the last one's opinion"
	)
	runtime.dispose()
#endregion


#region dispose() lets go of every component pointing here
func test_disposing_the_runtime_clears_every_components_reference() -> void:
	var runtime: GameplayNetworkRuntime = GameplayNetworkRuntime.new()
	runtime.role = GameplayNetAuthority.Role.AUTHORITY
	var one: AbilitySystemComponent = _asc("One")
	var two: AbilitySystemComponent = _asc("Two")
	runtime.attach(one, GameplayNetEntityId.of(1), OWNING_PEER)
	runtime.attach(two, GameplayNetEntityId.of(2), OTHER_PEER)

	runtime.dispose()

	assert_null(one.network, "the first component was told it is nobody's now")
	assert_null(two.network, "and so was the second")


## Once disposed, this runtime is no longer listening to its own transport -
## a packet still arriving on the wire has nobody here to reach.
func test_disposing_the_runtime_stops_listening_to_its_transport() -> void:
	var wires: Array[LoopbackTransport] = LoopbackTransport.pair()
	var runtime: GameplayNetworkRuntime = GameplayNetworkRuntime.new()
	runtime.role = GameplayNetAuthority.Role.AUTHORITY
	runtime.set_transport(wires[0])
	var asc: AbilitySystemComponent = _asc("Late Packet")
	runtime.attach(asc, GameplayNetEntityId.of(1), OWNING_PEER)
	assert_true(
		wires[0].packet_received.is_connected(runtime._on_packet_received),
		"listening, before it is disposed"
	)

	runtime.dispose()

	assert_null(runtime.transport, "the reference itself is gone")
	assert_false(
		wires[0].packet_received.is_connected(runtime._on_packet_received),
		"and so is the connection a packet would have arrived through"
	)
#endregion
