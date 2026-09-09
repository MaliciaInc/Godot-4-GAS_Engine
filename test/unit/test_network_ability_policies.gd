## What an ability accepts from another machine, which is not where it runs.
##
## Two policies that look like one. `NetExecutionPolicy` says where and when an
## ability executes; `NetSecurityPolicy` says what the authority acts on when
## somebody else asks for it. They are different questions with different
## answers, and the way they go wrong is that one gets derived from the other -
## at which point an ability the server alone executes stops accepting the
## request from the client whose character it is, and nobody can say why.
##
## So what is checked here is mostly difference: the same grant answering yes to
## a start and no to an end, and two grants with identical execution policies
## answering differently because their security policies differ.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const AbilityFactory = preload("res://test/fixtures/test_ability_factory.gd")

const OWNING_PEER: int = NetBench.OWNING_PEER
const ABILITY_TAG: StringName = &"Ability.Policed"
const A_PATH: String = "res://test_only/policy_probe_%d.tscn"
const A_SLOT: int = 7

var made: int = 0
var bench: NetBench = null
var asc: AbilitySystemComponent = null
var entity: GameplayNetEntityId = null
var authority: GameplayNetworkRuntime = null
var client: GameplayNetworkRuntime = null
var sent: Array[GameplayNetMessage] = []
var refusals: Array[StringName] = []


func before_each() -> void:
	sent = []
	refusals = []
	bench = NetBench.built(self, "Policed")
	autofree(bench.fixture.owner)
	asc = bench.asc()
	asc.set_process(false)
	entity = bench.entity
	authority = bench.runtime
	authority.message_refused.connect(
		func(_message: GameplayNetMessage, reason: StringName) -> void:
			refusals.append(reason)
	)

	client = bench.client()
	client.message_ready.connect(func(message: GameplayNetMessage) -> void: sent.append(message))


func after_each() -> void:
	bench.dispose()
	client.dispose()
	bench = null
	authority = null
	client = null
	asc = null


#region Asking to start
##     [what the grant says, whether a remote request is acted on]
func _start_cases() -> Array:
	return [
		[
			"either machine may ask",
			GameplayAbility.NetSecurityPolicy.CLIENT_OR_SERVER,
			true,
		],
		[
			"only the authority starts it",
			GameplayAbility.NetSecurityPolicy.SERVER_ONLY_EXECUTION,
			false,
		],
		[
			"only the authority ends it",
			GameplayAbility.NetSecurityPolicy.SERVER_ONLY_TERMINATION,
			true,
		],
		[
			"neither, about anything",
			GameplayAbility.NetSecurityPolicy.SERVER_ONLY,
			false,
		],
	]


## A request to activate is asked of the security policy, and refused by name.
##
## Every row here has the same execution policy - LOCAL_PREDICTED, which a
## client is always allowed to ask under - so the only thing separating the
## honoured rows from the refused ones is what the ability accepts from
## somebody else. A rule that read the execution policy would honour all four.
func test_a_remote_request_is_asked_of_the_security_policy() -> void:
	var rows: Array = _start_cases()
	var checked: int = 0
	for row: Array in rows:
		var described: String = row[0]
		var security: GameplayAbility.NetSecurityPolicy = row[1]
		var honoured: bool = row[2]

		before_each()
		var scene: PackedScene = _authored(security)
		authority.registry.register_definition(scene)

		assert_eq(authority.receive(_a_request_for(scene)), honoured, described)
		assert_eq(
			refusals.has(GameplayNetworkRuntime.REASON_POLICY), not honoured,
			"%s: refused by policy" % described
		)
		checked += 1
	assert_eq(checked, rows.size(), "every security policy was asked")


## The two policies are two questions, proved by disagreeing about one grant.
##
## SERVER_ONLY_EXECUTION on an ability a client may otherwise predict: the
## execution policy says the client runs it locally and asks, and the security
## policy says the authority does not act on the asking. Both are true at once,
## and neither is derivable from the other.
func test_the_execution_policy_does_not_decide_what_the_authority_accepts() -> void:
	var predicted: PackedScene = _authored(
		GameplayAbility.NetSecurityPolicy.SERVER_ONLY_EXECUTION
	)
	authority.registry.register_definition(predicted)

	assert_eq(
		GameplayNetAuthority.client_start(GameplayAbility.NetExecutionPolicy.LOCAL_PREDICTED),
		GameplayNetAuthority.Start.PREDICT_AND_ASK,
		"the client runs it and asks"
	)
	assert_false(authority.receive(_a_request_for(predicted)), "and the authority says no")
	assert_true(refusals.has(GameplayNetworkRuntime.REASON_POLICY), "on policy grounds")
#endregion


#region Asking to stop
##     [what the grant says, whether it honours one, whether a release lands]
func _end_cases() -> Array:
	return [
		[
			"nothing said about cancellation",
			GameplayAbility.NetSecurityPolicy.CLIENT_OR_SERVER,
			false,
			false,
		],
		[
			"a grant that honours one",
			GameplayAbility.NetSecurityPolicy.CLIENT_OR_SERVER,
			true,
			true,
		],
		[
			"only the authority ends it",
			GameplayAbility.NetSecurityPolicy.SERVER_ONLY_TERMINATION,
			true,
			false,
		],
		[
			"neither, about anything",
			GameplayAbility.NetSecurityPolicy.SERVER_ONLY,
			true,
			false,
		],
		[
			"only the authority starts it",
			GameplayAbility.NetSecurityPolicy.SERVER_ONLY_EXECUTION,
			true,
			true,
		],
	]


## Letting go of an ability from another machine goes through two gates.
##
## The policy first - whether a remote machine may end it at all - and then
## whether this ability said it honours one, which is false unless authored
## otherwise. The last row is the one worth reading: an ability only the
## authority may start is still one a client may let go of.
func test_a_remote_release_is_asked_of_both_gates() -> void:
	var rows: Array = _end_cases()
	var checked: int = 0
	for row: Array in rows:
		var described: String = row[0]
		var security: GameplayAbility.NetSecurityPolicy = row[1]
		var respects: bool = row[2]
		var lands: bool = row[3]

		before_each()
		var scene: PackedScene = _authored(security, respects)
		authority.registry.register_definition(scene)

		assert_eq(
			authority.receive(_an_input_for(scene, false)), lands, described
		)
		assert_eq(
			refusals.has(GameplayNetworkRuntime.REASON_POLICY), not lands,
			"%s: refused by policy" % described
		)
		checked += 1
	assert_eq(checked, rows.size(), "every ending was asked")


## One grant, one moment, two different answers.
##
## SERVER_ONLY_TERMINATION accepts the press and refuses the release, and it
## says so about the same scene in the same test - which is the shape no
## implementation that mapped one policy onto the other could produce.
func test_one_grant_accepts_a_press_and_refuses_the_release() -> void:
	var scene: PackedScene = _authored(
		GameplayAbility.NetSecurityPolicy.SERVER_ONLY_TERMINATION, true
	)
	authority.registry.register_definition(scene)

	assert_true(authority.receive(_an_input_for(scene, true)), "the press landed")
	assert_false(authority.receive(_an_input_for(scene, false)), "the release did not")
	assert_eq(
		refusals, [GameplayNetworkRuntime.REASON_POLICY] as Array[StringName],
		"and only the release was refused"
	)
#endregion


#region The generic no
## A no that arrived over a wire does not reach an ability that refuses one.
##
## The generic cancel names no ability, so the refusal cannot be the message -
## it is per-activation, and what it governs is the tasks. A task waiting on
## confirm-or-cancel inside an ability whose grant reserves termination to the
## authority stays waiting.
func test_a_remote_no_does_not_reach_an_ability_that_refuses_one() -> void:
	var task: AbilityTaskWaitConfirmCancel = _waiting(
		GameplayAbility.NetSecurityPolicy.SERVER_ONLY_TERMINATION, true
	)

	assert_true(
		authority.receive(
			GameplayNetMessage.of(GameplayNetMessage.Kind.GENERIC_CANCEL, entity)
		),
		"the message was acted on"
	)
	assert_false(task.is_finished(), "and the task did not hear it")


## Nor one whose grant never said it honours a remote cancellation.
##
## The default, and deliberately so: a client that can end an ability after the
## authority has committed its cost has taken the cost and given nothing back.
func test_a_remote_no_is_ignored_unless_the_grant_says_otherwise() -> void:
	var task: AbilityTaskWaitConfirmCancel = _waiting(
		GameplayAbility.NetSecurityPolicy.CLIENT_OR_SERVER, false
	)

	authority.receive(GameplayNetMessage.of(GameplayNetMessage.Kind.GENERIC_CANCEL, entity))

	assert_false(task.is_finished(), "the task did not hear it")


## And it does reach one whose grant says it should.
func test_a_remote_no_reaches_an_ability_that_honours_one() -> void:
	var task: AbilityTaskWaitConfirmCancel = _waiting(
		GameplayAbility.NetSecurityPolicy.CLIENT_OR_SERVER, true
	)

	authority.receive(GameplayNetMessage.of(GameplayNetMessage.Kind.GENERIC_CANCEL, entity))

	assert_true(task.is_finished(), "the task heard it")
	assert_eq(task.decision, AbilityTaskWaitConfirmCancel.Decision.CANCELLED, "as a no")


## A no said on this machine still reaches everybody.
##
## The policy is about what another machine may ask for. A player pressing
## cancel on their own client, on an ability running there, is not another
## machine - and an implementation that filtered every cancel would have made
## the flag mean "this ability cannot be cancelled", which is a different
## thing that already has a name.
func test_a_local_no_reaches_an_ability_that_refuses_a_remote_one() -> void:
	var task: AbilityTaskWaitConfirmCancel = _waiting(
		GameplayAbility.NetSecurityPolicy.SERVER_ONLY, false
	)

	asc.input_cancel()

	assert_true(task.is_finished(), "the task heard it")
#endregion


#region The input that crosses instead
## An ability that replicates its input directly sends the press, not a request.
##
## The whole reason the input crosses is that letting go has to be able to end
## the run the press started, and an activation request has no opposite. So the
## press is what leaves, carrying the slot this machine's own grant was bound
## to and no handle of any kind.
func test_a_press_crosses_for_an_ability_that_replicates_its_input() -> void:
	var scene: PackedScene = _authored(
		GameplayAbility.NetSecurityPolicy.CLIENT_OR_SERVER, false, true
	)
	asc.give_ability(scene, 1.0, A_SLOT)

	client.start(asc, scene)

	assert_eq(sent.size(), 1, "one message left")
	assert_eq(sent[0].kind, GameplayNetMessage.Kind.INPUT_PRESSED, "and it is the press")
	assert_eq(_slot_named_by(sent[0]), A_SLOT, "naming the slot the grant was bound to")
	assert_true(sent[0].definition.is_valid(), "and the definition it is about")
	assert_null(sent[0].activation, "and no handle of any kind")


## Letting go sends the release, for that ability and no other.
func test_letting_go_sends_the_release_only_where_the_input_crosses() -> void:
	var crossing: PackedScene = _authored(
		GameplayAbility.NetSecurityPolicy.CLIENT_OR_SERVER, false, true
	)
	var ordinary: PackedScene = _authored(GameplayAbility.NetSecurityPolicy.CLIENT_OR_SERVER)
	asc.give_ability(crossing, 1.0, A_SLOT)

	assert_false(client.release(asc, ordinary), "an ordinary ability has no release to send")
	assert_eq(sent.size(), 0, "so nothing left")

	assert_true(client.release(asc, crossing), "and this one does")
	assert_eq(sent.size(), 1, "one message left")
	assert_eq(sent[0].kind, GameplayNetMessage.Kind.INPUT_RELEASED, "and it is the release")


## An ordinary ability still asks to be activated.
func test_an_ordinary_ability_still_asks_to_be_activated() -> void:
	var scene: PackedScene = _authored(GameplayAbility.NetSecurityPolicy.CLIENT_OR_SERVER)

	client.start(asc, scene)

	assert_eq(sent.size(), 1, "one message left")
	assert_eq(sent[0].kind, GameplayNetMessage.Kind.ACTIVATION_REQUEST, "and it is the request")
#endregion


#region What the grant froze
## All four fields survive the grant, which is what makes them policy.
##
## An ability whose network policy could be rewritten on the running instance
## is one a client could argue its way past by changing the answer after the
## question. The snapshot is taken once, and it is what every gate above reads.
func test_the_four_fields_are_frozen_at_grant_time() -> void:
	var probe: ProbeAbility = ProbeAbility.build(ABILITY_TAG)
	probe.net_security_policy = GameplayAbility.NetSecurityPolicy.SERVER_ONLY
	probe.replication_policy = GameplayAbility.ReplicationPolicy.REPLICATE_YES
	probe.server_respects_remote_cancellation = true
	probe.replicate_input_directly = true
	var spec: GameplayAbilitySpec = AbilityFactory.give(asc, probe)

	var frozen: GameplayAbilityDefinitionSnapshot = spec.definition
	assert_eq(
		frozen.net_security_policy, GameplayAbility.NetSecurityPolicy.SERVER_ONLY,
		"what it accepts from elsewhere"
	)
	assert_eq(
		frozen.replication_policy, GameplayAbility.ReplicationPolicy.REPLICATE_YES,
		"whether its own state travels"
	)
	assert_true(frozen.server_respects_remote_cancellation, "whether a remote no is honoured")
	assert_true(frozen.replicate_input_directly, "and whether the input crosses instead")

	var running: ProbeAbility = spec.per_actor_instance as ProbeAbility
	running.net_security_policy = GameplayAbility.NetSecurityPolicy.CLIENT_OR_SERVER
	running.server_respects_remote_cancellation = false
	assert_false(
		frozen.accepts_remote_termination(),
		"and rewriting the instance changes none of it"
	)
#endregion


#region Getting there
## An ability scene with F6.6.5's fields authored on it.
##
## Always LOCAL_PREDICTED, because every gate under test is the security one
## and an execution policy that refused first would hide it.
func _authored(
	security: GameplayAbility.NetSecurityPolicy,
	respects: bool = false,
	replicates_input: bool = false
) -> PackedScene:
	made += 1
	var probe: ProbeAbility = ProbeAbility.build(ABILITY_TAG)
	probe.net_execution_policy = GameplayAbility.NetExecutionPolicy.LOCAL_PREDICTED
	probe.net_security_policy = security
	probe.server_respects_remote_cancellation = respects
	probe.replicate_input_directly = replicates_input
	return AbilityFactory.packed_at(probe, A_PATH % made)


## The slot a message names, read as an int rather than as whatever came back
## out of an untyped dictionary.
func _slot_named_by(message: GameplayNetMessage) -> int:
	var named: int = message.payload.get(GameplayNetMessage.INPUT_KEY, -1)
	return named


func _a_request_for(scene: PackedScene) -> GameplayNetMessage:
	var asking: GameplayNetMessage = GameplayNetMessage.of(
		GameplayNetMessage.Kind.ACTIVATION_REQUEST, entity
	)
	asking.definition = GameplayNetDefinitionId.of_resource(scene)
	asking.prediction_key = GameplayPredictionKey.of(OWNING_PEER, 1)
	return asking


func _an_input_for(scene: PackedScene, pressed: bool) -> GameplayNetMessage:
	var message: GameplayNetMessage = GameplayNetMessage.of(
		GameplayNetMessage.Kind.INPUT_PRESSED if pressed
		else GameplayNetMessage.Kind.INPUT_RELEASED,
		entity
	)
	message.definition = GameplayNetDefinitionId.of_resource(scene)
	message.payload[GameplayNetMessage.INPUT_KEY] = A_SLOT
	return message


## A channelled ability running on the authority, with a task waiting on a yes
## or a no. The channel is what keeps the instance alive to be cancelled at
## all: an ability that returned from activation is already over.
func _waiting(
	security: GameplayAbility.NetSecurityPolicy, respects: bool
) -> AbilityTaskWaitConfirmCancel:
	var probe: ProbeAbility = ProbeAbility.build(ABILITY_TAG)
	probe.net_security_policy = security
	probe.server_respects_remote_cancellation = respects
	var spec: GameplayAbilitySpec = AbilityFactory.give(asc, probe)
	var running: ProbeAbility = spec.per_actor_instance as ProbeAbility
	running.channels = true
	asc.try_activate_ability_handle(spec.handle)

	var task: AbilityTaskWaitConfirmCancel = AbilityTaskWaitConfirmCancel.create(running)
	asc.register_ability_task(task)
	return task
#endregion
