## Who is allowed to do what, and what happens to a message that is not.
##
## The rules under test are short, and every one of them is guarding the same
## thing: a client does not author. It asks, it is told, and it predicts what it
## will be told - but a grant it wrote itself, an effect it applied on its own
## authority, an id it invented are the same bug wearing different clothes, and
## the bug is a player giving themselves an ability.
##
## No transport. The runtime hands messages out through a signal and takes them
## in through a call, so two machines are two runtimes in one process here -
## which is also how the gate's adverse cases (a duplicate, a reorder, a
## dropped answer) are reachable at all.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Probe = preload("res://test/fixtures/probe_ability.gd")

const SERVER_PEER: int = 1
const OWNING_PEER: int = 2
const OTHER_PEER: int = 3

const A_SCENE_PATH: String = "res://test_only/net_ability_%d.tscn"

## Two paths Godot's own string hash cannot tell apart, found by search rather
## than asserted from theory. A definition id is a hash, hashes collide, and
## the registry's refusal is only worth having if a collision can be produced.
const COLLIDING_A: String = "res://c/43008.tres"
const COLLIDING_B: String = "res://c/17600980.tres"

var made: int = 0
var server: GameplayNetworkRuntime = null
var client: GameplayNetworkRuntime = null
var sent: Array[GameplayNetMessage] = []
var refusals: Array[StringName] = []


func before_each() -> void:
	server = GameplayNetworkRuntime.new()
	server.role = GameplayNetAuthority.Role.AUTHORITY
	server.peer = SERVER_PEER
	client = GameplayNetworkRuntime.new()
	client.role = GameplayNetAuthority.Role.CLIENT
	client.peer = OWNING_PEER
	sent = []
	refusals = []
	for runtime: GameplayNetworkRuntime in [server, client]:
		runtime.message_ready.connect(func(message: GameplayNetMessage) -> void: sent.append(message))
		runtime.message_refused.connect(
			func(_message: GameplayNetMessage, reason: StringName) -> void: refusals.append(reason)
		)


func after_each() -> void:
	server.dispose()
	client.dispose()
	server = null
	client = null


#region Getting there
func _asc(named: String) -> AbilitySystemComponent:
	var fixture: ASCFixture = Fixture.create(named)
	add_child_autofree(fixture.owner)
	return fixture.asc


## An ability scene with a policy authored on it, living at a path so it has an
## id at all: a resource that was never saved cannot be named to another
## machine, which is the point of the check that says so.
func _ability(policy: GameplayAbility.NetExecutionPolicy) -> PackedScene:
	var probe: ProbeAbility = Probe.build(&"Ability.Net")
	probe.net_execution_policy = policy
	var scene: PackedScene = PackedScene.new()
	scene.pack(probe)
	probe.free()
	made += 1
	scene.take_over_path(A_SCENE_PATH % made)
	return scene


func _an_entity(runtime: GameplayNetworkRuntime, value: int, owner_peer: int) -> GameplayNetEntityId:
	var id: GameplayNetEntityId = GameplayNetEntityId.of(value)
	runtime.attach(_asc("Entity%d" % value), id, owner_peer)
	return id
#endregion


#region The tables that turn a name into a thing
func test_an_entity_resolves_both_ways() -> void:
	var registry: GameplayNetRegistry = GameplayNetRegistry.new()
	var asc: AbilitySystemComponent = _asc("Registered")
	var id: GameplayNetEntityId = GameplayNetEntityId.of(4)

	assert_true(registry.register_entity(id, asc, OWNING_PEER))
	assert_same(registry.asc_for(id), asc, "the id names the component")
	assert_true(registry.entity_for(asc).same_as(id), "and the component names the id")


## A peer told twice about an entity it already has is ordinary, not an error.
func test_registering_the_same_entity_again_is_not_a_refusal() -> void:
	var registry: GameplayNetRegistry = GameplayNetRegistry.new()
	var asc: AbilitySystemComponent = _asc("Twice")
	var id: GameplayNetEntityId = GameplayNetEntityId.of(4)
	registry.register_entity(id, asc, OWNING_PEER)

	assert_true(registry.register_entity(id, asc, OWNING_PEER), "the same one is fine")
	assert_false(
		registry.register_entity(id, _asc("Impostor"), OWNING_PEER),
		"and somebody else under that id is not"
	)
	assert_eq(registry.entity_count(), 1)


func test_forgetting_an_entity_takes_out_both_directions() -> void:
	var registry: GameplayNetRegistry = GameplayNetRegistry.new()
	var asc: AbilitySystemComponent = _asc("Forgotten")
	var id: GameplayNetEntityId = GameplayNetEntityId.of(4)
	registry.register_entity(id, asc, OWNING_PEER)

	registry.forget_entity(id)

	assert_null(registry.asc_for(id))
	assert_false(registry.entity_for(asc).is_valid())
	assert_eq(registry.owner_of(id), GameplayNetRegistry.NO_PEER, "and nobody owns it any more")


## An entity nobody owns is ordinary - a monster, a door - and is not the same
## as an entity owned by peer zero.
func test_nobody_owning_something_is_not_peer_zero_owning_it() -> void:
	var registry: GameplayNetRegistry = GameplayNetRegistry.new()
	var id: GameplayNetEntityId = GameplayNetEntityId.of(4)
	registry.register_entity(id, _asc("Monster"))

	assert_eq(registry.owner_of(id), GameplayNetRegistry.NO_PEER)
	assert_false(registry.is_owned_by(id, 0), "peer zero does not own it")
	assert_false(registry.is_owned_by(id, GameplayNetRegistry.NO_PEER), "and neither does nobody")


func test_a_definition_resolves_back_to_the_resource() -> void:
	var registry: GameplayNetRegistry = GameplayNetRegistry.new()
	var scene: PackedScene = _ability(GameplayAbility.NetExecutionPolicy.LOCAL_ONLY)

	var id: GameplayNetDefinitionId = registry.register_definition(scene)

	assert_true(id.is_valid())
	assert_same(registry.definition_for(id), scene)


## The collision the id's own doc comment admits to, produced and refused.
##
## Two definitions answering one id is one of them activating in place of the
## other. Refused at registration, with both names in hand, rather than found
## out when the wrong ability fires.
func test_two_definitions_answering_one_id_are_refused() -> void:
	var registry: GameplayNetRegistry = GameplayNetRegistry.new()
	var first: Resource = Resource.new()
	first.take_over_path(COLLIDING_A)
	var second: Resource = Resource.new()
	second.take_over_path(COLLIDING_B)
	assert_true(
		GameplayNetDefinitionId.of_resource(first).same_as(
			GameplayNetDefinitionId.of_resource(second)
		),
		"the two paths really do hash the same"
	)

	assert_true(registry.register_definition(first).is_valid(), "the first one is registered")
	var refused: GameplayNetDefinitionId = registry.register_definition(second)

	assert_false(refused.is_valid(), "and the second is refused rather than overwriting it")
	assert_push_error("is claimed by both")
	assert_same(registry.definition_for(GameplayNetDefinitionId.of_resource(first)), first)
#endregion


#region Who may do what
## The whole of what the four policy values mean from a client's side, which is
## why they are four rather than two: the difference between predicting and
## waiting is not what is allowed but what happens while the answer is in
## flight.
##
##     [what it is, what a client may do, what the authority does]
func _policies() -> Array:
	return [
		[
			GameplayAbility.NetExecutionPolicy.LOCAL_ONLY,
			GameplayNetAuthority.Start.RUN_NOW,
		],
		[
			GameplayAbility.NetExecutionPolicy.LOCAL_PREDICTED,
			GameplayNetAuthority.Start.PREDICT_AND_ASK,
		],
		[
			GameplayAbility.NetExecutionPolicy.SERVER_INITIATED,
			GameplayNetAuthority.Start.ASK_AND_WAIT,
		],
		[
			GameplayAbility.NetExecutionPolicy.SERVER_ONLY,
			GameplayNetAuthority.Start.REFUSED,
		],
	]


func test_each_policy_says_what_a_client_may_do_with_it() -> void:
	var rows: Array = _policies()
	var checked: int = 0
	for row: Array in rows:
		var policy: GameplayAbility.NetExecutionPolicy = row[0]
		var allowed: GameplayNetAuthority.Start = row[1]

		assert_eq(GameplayNetAuthority.client_start(policy), allowed)
		assert_eq(
			GameplayNetAuthority.authority_start(policy),
			GameplayNetAuthority.Start.RUN_NOW,
			"and the authority runs every one of them, having nobody to ask"
		)
		checked += 1
	assert_eq(checked, rows.size(), "all four were asked")


## The direction of a message is part of what it is. A client receiving a
## request is a client being asked to be the authority.
func test_a_message_going_the_wrong_way_is_not_acted_on() -> void:
	var request: GameplayNetMessage = GameplayNetMessage.of(
		GameplayNetMessage.Kind.ACTIVATION_REQUEST, GameplayNetEntityId.of(1)
	)
	request.definition = GameplayNetDefinitionId.of_path(COLLIDING_A)
	var grant: GameplayNetMessage = GameplayNetMessage.of(
		GameplayNetMessage.Kind.GRANT, GameplayNetEntityId.of(1)
	)
	grant.definition = GameplayNetDefinitionId.of_path(COLLIDING_A)

	assert_true(GameplayNetAuthority.accepts(GameplayNetAuthority.Role.AUTHORITY, request))
	assert_false(GameplayNetAuthority.accepts(GameplayNetAuthority.Role.AUTHORITY, grant))
	assert_false(GameplayNetAuthority.accepts(GameplayNetAuthority.Role.CLIENT, request))
	assert_true(GameplayNetAuthority.accepts(GameplayNetAuthority.Role.CLIENT, grant))


func test_only_the_authority_authors() -> void:
	assert_true(GameplayNetAuthority.may_author(GameplayNetAuthority.Role.AUTHORITY))
	assert_false(GameplayNetAuthority.may_author(GameplayNetAuthority.Role.CLIENT))
#endregion


#region What the runtime refuses
## A client granting itself an ability is the bug this layer exists for.
func test_a_client_cannot_grant() -> void:
	var id: GameplayNetEntityId = _an_entity(client, 1, OWNING_PEER)

	assert_false(client.grant(id, _ability(GameplayAbility.NetExecutionPolicy.LOCAL_ONLY)))
	assert_eq(sent.size(), 0, "and nothing went out")


func test_the_authority_grants_and_the_client_hears_it() -> void:
	var scene: PackedScene = _ability(GameplayAbility.NetExecutionPolicy.LOCAL_ONLY)
	var id: GameplayNetEntityId = _an_entity(server, 1, OWNING_PEER)
	_an_entity(client, 1, OWNING_PEER)
	client.registry.register_definition(scene)

	assert_true(server.grant(id, scene), "the authority may")
	assert_eq(sent.size(), 1, "and says so")

	var heard: Array[Resource] = []
	client.ability_granted_by_authority.connect(
		func(_entity: GameplayNetEntityId, definition: Resource) -> void: heard.append(definition)
	)
	assert_true(client.receive(sent[0]))
	assert_eq(heard.size(), 1, "the client acted on it")
	assert_same(heard[0], scene, "and knows which ability")


## What the authority sends about a grant, with the client already knowing the
## definition or not, as the two refusals below need it.
func _a_grant_the_server_sent(scene: PackedScene, client_knows_the_entity: bool) -> GameplayNetMessage:
	var id: GameplayNetEntityId = _an_entity(server, 1, OWNING_PEER)
	if client_knows_the_entity:
		_an_entity(client, 1, OWNING_PEER)
	client.registry.register_definition(scene)
	server.grant(id, scene)
	return sent[0]


## The same message twice is one message. Whether it was repeated by the
## transport, reordered around something else, or retried because its answer
## was lost, acting on it again is the double grant nobody asked for.
func test_the_same_message_arriving_twice_is_acted_on_once() -> void:
	var grant: GameplayNetMessage = _a_grant_the_server_sent(
		_ability(GameplayAbility.NetExecutionPolicy.LOCAL_ONLY), true
	)

	assert_true(client.receive(grant), "the first time")
	assert_false(client.receive(grant), "and not the second")
	assert_true(refusals.has(GameplayNetworkRuntime.REASON_ALREADY_APPLIED))


func test_a_message_about_somebody_this_machine_has_never_heard_of_is_dropped() -> void:
	var grant: GameplayNetMessage = _a_grant_the_server_sent(
		_ability(GameplayAbility.NetExecutionPolicy.LOCAL_ONLY), false
	)

	assert_false(client.receive(grant), "the client has no such entity")
	assert_true(refusals.has(GameplayNetworkRuntime.REASON_UNKNOWN_ENTITY))


## The two ways a request is refused, which are the two halves of one rule: a
## client may act for its own character, and only for abilities a client is
## allowed to ask for at all.
##
##     [what is wrong with it, who owns the entity, the policy, the refusal]
func _refused_requests() -> Array:
	return [
		[
			"somebody else's character",
			OTHER_PEER,
			GameplayAbility.NetExecutionPolicy.SERVER_INITIATED,
			GameplayNetworkRuntime.REASON_NOT_OWNED,
		],
		[
			"an ability nobody may ask for",
			OWNING_PEER,
			GameplayAbility.NetExecutionPolicy.SERVER_ONLY,
			GameplayNetworkRuntime.REASON_POLICY,
		],
	]


func test_a_request_the_authority_will_not_honour_is_refused() -> void:
	var rows: Array = _refused_requests()
	var checked: int = 0
	for row: Array in rows:
		var described: String = row[0]
		var owner_peer: int = row[1]
		var policy: GameplayAbility.NetExecutionPolicy = row[2]
		var refusal: StringName = row[3]

		before_each()
		var scene: PackedScene = _ability(policy)
		var id: GameplayNetEntityId = _an_entity(server, 1, owner_peer)
		server.registry.register_definition(scene)
		var asking: GameplayNetMessage = GameplayNetMessage.of(
			GameplayNetMessage.Kind.ACTIVATION_REQUEST, id
		)
		asking.definition = GameplayNetDefinitionId.of_resource(scene)
		asking.prediction_key = GameplayPredictionKey.of(OWNING_PEER, 1)

		assert_false(server.receive(asking), described)
		assert_true(refusals.has(refusal), "%s: %s" % [described, refusal])
		checked += 1
	assert_eq(checked, rows.size(), "both refusals were offered")


##     [what the grant says, whether the client sends anything]
func _starting() -> Array:
	return [
		[GameplayAbility.NetExecutionPolicy.LOCAL_ONLY, false],
		[GameplayAbility.NetExecutionPolicy.LOCAL_PREDICTED, true],
		[GameplayAbility.NetExecutionPolicy.SERVER_INITIATED, true],
		[GameplayAbility.NetExecutionPolicy.SERVER_ONLY, false],
	]


func test_a_client_asks_only_for_what_its_policy_says_it_may() -> void:
	var rows: Array = _starting()
	var checked: int = 0
	for row: Array in rows:
		var policy: GameplayAbility.NetExecutionPolicy = row[0]
		var asks: bool = row[1]

		before_each()
		var asc: AbilitySystemComponent = _asc("Asker")
		client.attach(asc, GameplayNetEntityId.of(1), OWNING_PEER)

		client.start(asc, _ability(policy))

		assert_eq(sent.size(), 1 if asks else 0, "policy %d" % policy)
		checked += 1
	assert_eq(checked, rows.size(), "every policy was started")
#endregion


#region The component's one reference
func test_attaching_gives_the_component_its_runtime_and_detaching_takes_it_back() -> void:
	var asc: AbilitySystemComponent = _asc("Attached")
	var id: GameplayNetEntityId = GameplayNetEntityId.of(1)

	assert_true(server.attach(asc, id, OWNING_PEER))
	assert_same(asc.network, server, "one reference, and it is this one")

	server.detach(asc)
	assert_null(asc.network, "and it is given back")
	assert_null(server.registry.asc_for(id), "along with the registration")


## A component being torn down lets go of the network with everything else.
func test_disposing_the_component_lets_go_of_the_runtime() -> void:
	var asc: AbilitySystemComponent = _asc("Disposed")
	server.attach(asc, GameplayNetEntityId.of(1), OWNING_PEER)

	asc.dispose()

	assert_null(asc.network)
#endregion
