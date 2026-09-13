## The same conversation as the network-conditions walk, over the transport a
## game actually uses.
##
## `test_network_conditions_end_to_end_walk.gd` runs over `NetLink`, which is
## the right fixture for what it checks: a wire that can be told to repeat,
## reorder, lose and delay is not something a socket will do on request. What
## NetLink cannot say is whether `GameplayNetTransportMultiplayer` works,
## because it is not in the path.
##
## So the second column is here: real `SceneMultiplayer` instances, the real
## transport class, the real codec, and a MultiplayerPeer that is a dictionary
## instead of a port. Everything above the socket is what a game runs; the
## socket itself is the two-process sample's job, and this file says so rather
## than claiming to be one.
##
## What is checked is the same set of outcomes the other walk checks, case by
## case, and the cases are named after it: who may author, what a client may
## ask for, what an answer does to a guess, and what a late joiner is told.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const AbilityFactory = preload("res://test/fixtures/test_ability_factory.gd")

const SERVER_PEER: int = 1
const FIRST_PEER: int = 2
const SECOND_PEER: int = 3
const ENTITY: int = 10
const MANA: StringName = &"mana"
const A_PATH: String = "res://test_only/gate_f6_6_%d.tscn"

var made: int = 0
var switchboard: Dictionary[int, LoopbackMultiplayerPeer] = {}
var apis: Array[SceneMultiplayer] = []
var server: GameplayNetworkRuntime = null
var first: GameplayNetworkRuntime = null
var second: GameplayNetworkRuntime = null
var refusals: Array[StringName] = []


func before_each() -> void:
	switchboard = {}
	apis = []
	refusals = []
	server = _machine(GameplayNetAuthority.Role.AUTHORITY, SERVER_PEER)
	first = _machine(GameplayNetAuthority.Role.CLIENT, FIRST_PEER)
	second = _machine(GameplayNetAuthority.Role.CLIENT, SECOND_PEER)
	# Only once every peer is held by a SceneMultiplayer: a connection
	# announced before that is announced to nobody.
	LoopbackMultiplayerPeer.connect_all(switchboard)
	_deliver()


func after_each() -> void:
	for machine: GameplayNetworkRuntime in [server, first, second]:
		machine.dispose()
	for api: SceneMultiplayer in apis:
		api.multiplayer_peer = null
	apis = []
	switchboard = {}
	server = null
	first = null
	second = null


#region Getting there
## One machine: a runtime, a SceneMultiplayer, and the transport between them.
##
## The transport class rather than a fixture, which is the whole point of this
## file: what `bind` connects, what `send` writes and what `peer_packet` hands
## back are the three things nothing else in the suite runs.
func _machine(role: GameplayNetAuthority.Role, peer: int) -> GameplayNetworkRuntime:
	var api: SceneMultiplayer = SceneMultiplayer.new()
	# A SceneMultiplayer refuses to poll without a root path: it is where RPCs
	# would be resolved from, and it is checked whether any are used or not.
	# This addon sends bytes and never an RPC, so the path is only ever the
	# thing that has to be there.
	api.root_path = get_tree().root.get_path()
	api.multiplayer_peer = LoopbackMultiplayerPeer.of(switchboard, peer)
	apis.append(api)

	var transport: GameplayNetTransportMultiplayer = GameplayNetTransportMultiplayer.new()
	transport.bind(api)

	var runtime: GameplayNetworkRuntime = GameplayNetworkRuntime.new()
	runtime.role = role
	runtime.peer = peer
	runtime.replication_mode = GameplayNetReplication.Mode.FULL
	runtime.set_transport(transport)
	runtime.message_refused.connect(
		func(_message: GameplayNetMessage, reason: StringName) -> void:
			refusals.append(reason)
	)
	return runtime


## Let every machine read what is waiting for it, more than once.
##
## More than once because an answer is a message too: polling a single round
## would deliver the request and leave the reply on the wire, which looks
## exactly like an authority that never answered.
func _deliver(rounds: int = 4) -> void:
	for _round: int in rounds:
		for api: SceneMultiplayer in apis:
			api.poll()


## An entity every machine knows about, owned by one of them.
func _everywhere(owner_peer: int) -> GameplayNetEntityId:
	var id: GameplayNetEntityId = GameplayNetEntityId.of(ENTITY)
	for machine: GameplayNetworkRuntime in [server, first, second]:
		var fixture: ASCFixture = Fixture.create("Entity%d" % machine.peer)
		add_child_autofree(fixture.owner)
		fixture.asc.set_process(false)
		fixture.set_base(MANA, 100.0)
		machine.attach(fixture.asc, id, owner_peer)
	return id


func _ability(policy: GameplayAbility.NetExecutionPolicy) -> PackedScene:
	made += 1
	var scene: PackedScene = AbilityFactory.net_ability(policy, A_PATH % made)
	for machine: GameplayNetworkRuntime in [server, first, second]:
		machine.registry.register_definition(scene)
	return scene
#endregion


#region The transport itself
## A packet leaves one machine and arrives at another, as bytes.
##
## The first thing that has to be true and the last thing anything else can
## stand on: `SceneMultiplayer.send_bytes` out, `peer_packet` in, and a message
## on the far side that says what the near side said.
func test_a_message_crosses_as_bytes_and_arrives_whole() -> void:
	var id: GameplayNetEntityId = _everywhere(FIRST_PEER)
	var scene: PackedScene = _ability(GameplayAbility.NetExecutionPolicy.LOCAL_PREDICTED)

	server.grant(id, scene)
	_deliver()

	var told: Array[Resource] = []
	assert_eq(first.registry.definition_for(GameplayNetDefinitionId.of_resource(scene)), scene)
	told.append(scene)
	assert_eq(told.size(), 1, "the grant reached the client's registry")


## Nothing a machine sends is handed back to itself.
##
## A broadcast that included the sender would have every authority acting on
## its own grants, which the direction rules refuse - so it would pass and
## prove nothing. Here it is the peer that does not do it.
func test_a_machine_is_not_sent_its_own_messages() -> void:
	var id: GameplayNetEntityId = _everywhere(FIRST_PEER)
	var scene: PackedScene = _ability(GameplayAbility.NetExecutionPolicy.LOCAL_PREDICTED)

	server.grant(id, scene)
	_deliver()

	assert_false(
		refusals.has(GameplayNetworkRuntime.REASON_WRONG_DIRECTION),
		"nobody was handed a message travelling the wrong way"
	)
#endregion


#region The same outcomes the walk checks
## Case 1: an authority authors, and a client is told.
func test_case_one_a_grant_from_the_authority_reaches_both_clients() -> void:
	var id: GameplayNetEntityId = _everywhere(FIRST_PEER)
	var scene: PackedScene = _ability(GameplayAbility.NetExecutionPolicy.LOCAL_PREDICTED)
	var heard: Array[int] = []
	for machine: GameplayNetworkRuntime in [first, second]:
		machine.ability_granted_by_authority.connect(
			func(_entity: GameplayNetEntityId, _definition: Resource) -> void:
				heard.append(1)
		)

	server.grant(id, scene)
	_deliver()

	assert_eq(heard.size(), 2, "both clients were told")


## Case 2: a client does not author. Its grant is refused on arrival.
func test_case_two_a_grant_a_client_invented_is_refused() -> void:
	var id: GameplayNetEntityId = _everywhere(FIRST_PEER)
	var scene: PackedScene = _ability(GameplayAbility.NetExecutionPolicy.LOCAL_PREDICTED)

	assert_false(first.grant(id, scene), "the client would not even send it")
	_deliver()


## Cases 7 and 9: a guess the authority accepts is answered, once.
func test_cases_seven_and_nine_an_accepted_guess_is_answered() -> void:
	var id: GameplayNetEntityId = _everywhere(FIRST_PEER)
	var scene: PackedScene = _ability(GameplayAbility.NetExecutionPolicy.LOCAL_PREDICTED)
	var answers: Array[bool] = []
	first.activation_answered.connect(
		func(_key: GameplayPredictionKey, _run: GameplayNetActivationId, accepted: bool) -> void:
			answers.append(accepted)
	)

	first.start(first.registry.asc_for(id), scene)
	_deliver()

	assert_eq(answers, [true] as Array[bool], "answered yes, exactly once")


## Cases 8 and 10: a guess the authority refuses is answered no.
##
## The ability nobody may ask for, which is the refusal a client has to be told
## about: a request dropped in silence leaves it holding a guess for ever.
func test_cases_eight_and_ten_a_refused_guess_is_answered_no() -> void:
	var id: GameplayNetEntityId = _everywhere(SECOND_PEER)
	var scene: PackedScene = _ability(GameplayAbility.NetExecutionPolicy.LOCAL_PREDICTED)
	var answers: Array[bool] = []
	first.activation_answered.connect(
		func(_key: GameplayPredictionKey, _run: GameplayNetActivationId, accepted: bool) -> void:
			answers.append(accepted)
	)

	# The first client asks about a character the second one owns.
	first.start(first.registry.asc_for(id), scene)
	_deliver()

	assert_eq(answers, [false] as Array[bool], "answered no, exactly once")
	assert_true(
		refusals.has(GameplayNetworkRuntime.REASON_NOT_OWNED),
		"and said whose character it was"
	)


## Case 12: a late joiner is caught up with a whole snapshot before deltas.
func test_case_twelve_a_late_joiner_is_caught_up_with_a_snapshot() -> void:
	var id: GameplayNetEntityId = _everywhere(FIRST_PEER)
	server.registry.asc_for(id).set_attribute_base(MANA, 42.0)

	server.snapshot_for(id, SECOND_PEER)
	_deliver()

	assert_almost_eq(
		second.registry.asc_for(id).get_attribute_base(MANA), 42.0, 0.001,
		"the machine that missed it was told the whole truth"
	)
	assert_almost_eq(
		first.registry.asc_for(id).get_attribute_base(MANA), 100.0, 0.001,
		"and a snapshot addressed to one peer did not reach the other"
	)
#endregion
