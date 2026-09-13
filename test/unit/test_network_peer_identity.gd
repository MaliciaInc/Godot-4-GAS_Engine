## Whether the authority believes what a message claims about who sent it.
##
## Every message a client asks the authority for names an entity, and until
## now the authority took the message's own word for who was asking - a
## prediction key's `peer` field, or for a few kinds nothing at all. A real
## wire carries a sender the message cannot forge, and this is the suite that
## checks the authority is asked that question and not the other one.
##
## Wired through `NetLink` rather than called directly, because the whole
## point under test is the one fact a direct call has no way to supply: who
## actually sent it. A direct call - which is every test in this addon's own
## suite before this file existed - names no sender at all and is unaffected;
## the closing case here says so.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const AbilityFactory = preload("res://test/fixtures/test_ability_factory.gd")
const Probe = preload("res://test/fixtures/probe_ability.gd")

const SERVER_PEER: int = 1
const ATTACKER_PEER: int = 2
const VICTIM_PEER: int = 3
const ATTACKER_ENTITY: int = 10
const VICTIM_ENTITY: int = 20
const ABILITY_TAG: StringName = &"Ability.Identity"
const A_PATH: String = "res://test_only/peer_identity_%d.tscn"

var made: int = 0
var link: NetLink = null
var server: GameplayNetworkRuntime = null
var attacker: GameplayNetworkRuntime = null
var victim: GameplayNetworkRuntime = null
var refusals: Array[StringName] = []
var answers: Array[GameplayNetMessage] = []


func before_each() -> void:
	link = NetLink.new()
	refusals = []
	answers = []
	server = _machine(GameplayNetAuthority.Role.AUTHORITY, SERVER_PEER)
	attacker = _machine(GameplayNetAuthority.Role.CLIENT, ATTACKER_PEER)
	victim = _machine(GameplayNetAuthority.Role.CLIENT, VICTIM_PEER)
	server.message_refused.connect(
		func(_m: GameplayNetMessage, reason: StringName) -> void: refusals.append(reason)
	)
	server.message_ready.connect(func(m: GameplayNetMessage) -> void: answers.append(m))


func after_each() -> void:
	for machine: GameplayNetworkRuntime in [server, attacker, victim]:
		machine.dispose()
	link = null
	server = null
	attacker = null
	victim = null


#region Getting there
func _machine(role: GameplayNetAuthority.Role, peer: int) -> GameplayNetworkRuntime:
	var runtime: GameplayNetworkRuntime = GameplayNetworkRuntime.new()
	runtime.role = role
	runtime.peer = peer
	link.join(runtime)
	return runtime


## The same entity id, owned by one peer, registered on all three machines -
## which is what every one of them being told about a character looks like.
func _everywhere(value: int, owner_peer: int) -> GameplayNetEntityId:
	return NetLinkEntity.everywhere(self, [server, attacker, victim], value, owner_peer)


func _ability() -> PackedScene:
	made += 1
	var scene: PackedScene = AbilityFactory.net_ability(
		GameplayAbility.NetExecutionPolicy.LOCAL_PREDICTED, A_PATH % made, ABILITY_TAG
	)
	for machine: GameplayNetworkRuntime in [server, attacker, victim]:
		machine.registry.register_definition(scene)
	return scene


func _only_answer() -> GameplayNetMessage:
	assert_eq(answers.size(), 1, "exactly one answer was published")
	return answers[0] if not answers.is_empty() else null
#endregion


#region The four cases the audit names
## A peer asking about its own entity is accepted; the same honest ask about
## somebody else's is refused for ownership rather than for a forged key - the
## key correctly names the peer that actually asked, and that peer just does
## not own what it asked about.
##
##     [described, entity value, who owns it, what answer comes back]
func _ownership_cases() -> Array:
	return [
		["its own entity", ATTACKER_ENTITY, ATTACKER_PEER, GameplayNetMessage.Kind.ACTIVATION_CONFIRM],
		["somebody else's entity", VICTIM_ENTITY, VICTIM_PEER, GameplayNetMessage.Kind.ACTIVATION_REJECT],
	]


func test_a_peer_asking_for_an_entity_it_may_or_may_not_own(
	case: Array = use_parameters(_ownership_cases())
) -> void:
	var described: String = case[0]
	var entity_value: int = case[1]
	var owner_peer: int = case[2]
	var expected: GameplayNetMessage.Kind = case[3]
	var id: GameplayNetEntityId = _everywhere(entity_value, owner_peer)
	var scene: PackedScene = _ability()

	attacker.start(attacker.registry.asc_for(id), scene)
	link.drain()

	assert_eq(_only_answer().kind, expected, described)
	if expected == GameplayNetMessage.Kind.ACTIVATION_REJECT:
		assert_true(refusals.has(GameplayNetworkRuntime.REASON_NOT_OWNED), described)
	assert_false(
		refusals.has(GameplayNetworkRuntime.REASON_PEER_MISMATCH),
		"%s: the key told the truth" % described
	)


## A request whose key names a stranger is refused for the forgery, before
## anybody is asked whether the stranger owns anything - which is the
## difference between this case and the one above, and the bug AUD-02 is
## about: without it, the stranger's real ownership would have made this
## request succeed.
func test_a_forged_prediction_key_is_refused_before_ownership_is_even_asked() -> void:
	var id: GameplayNetEntityId = _everywhere(VICTIM_ENTITY, VICTIM_PEER)
	var scene: PackedScene = _ability()

	var forged: GameplayNetMessage = GameplayNetMessage.of(
		GameplayNetMessage.Kind.ACTIVATION_REQUEST, id
	)
	forged.definition = GameplayNetDefinitionId.of_resource(scene)
	forged.prediction_key = GameplayPredictionKey.of(VICTIM_PEER, 999)
	attacker.publish(forged)
	link.drain()

	assert_eq(_only_answer().kind, GameplayNetMessage.Kind.ACTIVATION_REJECT)
	assert_true(
		refusals.has(GameplayNetworkRuntime.REASON_PEER_MISMATCH),
		"the wire said the attacker sent it and the key said the victim did"
	)


## The named peer asking for its own entity is still accepted - the check
## above falls on a forged key, not on the peer the key names.
func test_the_named_peer_asking_for_its_own_entity_is_still_accepted() -> void:
	var id: GameplayNetEntityId = _everywhere(VICTIM_ENTITY, VICTIM_PEER)
	var scene: PackedScene = _ability()

	victim.start(victim.registry.asc_for(id), scene)
	link.drain()

	assert_eq(_only_answer().kind, GameplayNetMessage.Kind.ACTIVATION_CONFIRM)
#endregion


#region The same rule, for what is not a request
## An aim claiming somebody else's entity never reaches a provider at all -
## proved by the refusal being about identity rather than about there being
## nothing to aim at.
func test_an_aim_for_somebody_elses_entity_is_refused_before_a_provider_is_asked() -> void:
	var id: GameplayNetEntityId = _everywhere(VICTIM_ENTITY, VICTIM_PEER)
	var data: GameplayAbilityTargetData = GameplayAbilityTargetData.new()
	data.append_location(Vector3.ZERO)

	attacker.send_target_data(
		id, data, GameplayNetActivationId.of(id, 1), GameplayPredictionKey.of(ATTACKER_PEER, 1)
	)
	link.drain()

	assert_true(
		refusals.has(GameplayNetworkRuntime.REASON_PEER_MISMATCH),
		"refused for identity, not for lacking a provider"
	)
	assert_false(refusals.has(GameplayNetworkRuntime.REASON_TARGET_UNREACHABLE))


## A confirm or a cancel claiming somebody else's entity does not reach it.
##
##     [what it is, whether it is a confirm]
func _yes_or_no_cases() -> Array:
	return [["a confirm", true], ["a cancel", false]]


func test_a_confirm_or_cancel_for_somebody_elses_entity_is_refused(
	case: Array = use_parameters(_yes_or_no_cases())
) -> void:
	var described: String = case[0]
	var confirming: bool = case[1]
	var id: GameplayNetEntityId = _everywhere(VICTIM_ENTITY, VICTIM_PEER)
	var confirmed: Array[bool] = []
	var cancelled: Array[bool] = []
	var theirs: AbilitySystemComponent = server.registry.asc_for(id)
	theirs.generic_confirmed.connect(func() -> void: confirmed.append(true))
	theirs.generic_cancelled.connect(func() -> void: cancelled.append(true))

	if confirming:
		attacker.send_generic_confirm(id)
	else:
		attacker.send_generic_cancel(id)
	link.drain()

	assert_true(refusals.has(GameplayNetworkRuntime.REASON_PEER_MISMATCH), described)
	assert_eq(confirmed.size(), 0, described)
	assert_eq(cancelled.size(), 0, described)


## An input claiming somebody else's entity does not press anything.
func test_an_input_for_somebody_elses_entity_is_refused() -> void:
	var id: GameplayNetEntityId = _everywhere(VICTIM_ENTITY, VICTIM_PEER)
	var scene: PackedScene = _ability()
	server.registry.asc_for(id).give_ability(scene, 1.0, 3)

	attacker.send_input(id, scene, 3, true)
	link.drain()

	assert_true(refusals.has(GameplayNetworkRuntime.REASON_PEER_MISMATCH))
	assert_eq(
		server.registry.asc_for(id).get_held_inputs(), [] as Array[int], "nothing was pressed"
	)


## An event claiming somebody else's entity does not arrive as one.
func test_an_event_for_somebody_elses_entity_is_refused() -> void:
	var id: GameplayNetEntityId = _everywhere(VICTIM_ENTITY, VICTIM_PEER)
	var heard: Array[StringName] = []
	server.registry.asc_for(id).gameplay_event_received.connect(
		func(event: GameplayEventData) -> void: heard.append(event.event_tag)
	)
	var sent: GameplayEventData = GameplayEventData.new()
	sent.event_tag = &"Event.Identity.Probe"

	attacker.send_gameplay_event(id, sent)
	link.drain()

	assert_true(refusals.has(GameplayNetworkRuntime.REASON_PEER_MISMATCH))
	assert_eq(heard.size(), 0)
#endregion


#region What still works
## Each of those same kinds still reaches the peer's own entity.
func test_a_confirm_still_reaches_the_peers_own_entity() -> void:
	var id: GameplayNetEntityId = _everywhere(ATTACKER_ENTITY, ATTACKER_PEER)
	var confirmed: Array[bool] = []
	server.registry.asc_for(id).generic_confirmed.connect(func() -> void: confirmed.append(true))

	attacker.send_generic_confirm(id)
	link.drain()

	assert_eq(confirmed.size(), 1, "the owner's own confirm still lands")
	assert_eq(refusals, [] as Array[StringName])


## A batch with one honest member and one impersonating member is refused
## whole, exactly as a batch with any other unacceptable member is - the
## identity check runs in the same judge-before-applying pass every other
## batch refusal does.
##
## Over a real transport rather than through `link`: gathering only happens
## while a runtime has one to publish through - `publish()` sends everything
## unbatched the moment there is none - so a batch worth naming one needs a
## wire under it, the same way `test_network_batching.gd` gives its own client
## one.
func test_a_batch_carrying_one_impersonating_member_is_refused_whole() -> void:
	var authority: GameplayNetworkRuntime = GameplayNetworkRuntime.new()
	authority.role = GameplayNetAuthority.Role.AUTHORITY
	var forger: GameplayNetworkRuntime = GameplayNetworkRuntime.new()
	forger.role = GameplayNetAuthority.Role.CLIENT
	forger.peer = ATTACKER_PEER
	var wires: Array[LoopbackTransport] = LoopbackTransport.pair()
	authority.set_transport(wires[0])
	forger.set_transport(wires[1])
	var batch_refusals: Array[StringName] = []
	authority.message_refused.connect(
		func(_m: GameplayNetMessage, reason: StringName) -> void: batch_refusals.append(reason)
	)

	var mine: GameplayNetEntityId = GameplayNetEntityId.of(ATTACKER_ENTITY)
	var theirs: GameplayNetEntityId = GameplayNetEntityId.of(VICTIM_ENTITY)
	var own_fixture: ASCFixture = Fixture.create("Forger")
	add_child_autofree(own_fixture.owner)
	authority.attach(own_fixture.asc, mine, ATTACKER_PEER)
	var victim_fixture: ASCFixture = Fixture.create("Victim")
	add_child_autofree(victim_fixture.owner)
	authority.attach(victim_fixture.asc, theirs, VICTIM_PEER)

	var confirmed: Array[bool] = []
	own_fixture.asc.generic_confirmed.connect(func() -> void: confirmed.append(true))

	forger.begin_batch()
	forger.send_generic_confirm(mine)
	forger.send_generic_confirm(theirs)
	forger.end_batch()

	assert_eq(confirmed.size(), 0, "the honest member inside an atomic batch did not run either")
	assert_true(batch_refusals.has(GameplayNetBatch.REASON_MEMBER_REFUSED))
	authority.dispose()
	forger.dispose()


## Called directly, with nobody vouching for a sender, none of this applies -
## which is every test in this addon's own suite before this file existed,
## and is why they all still pass.
func test_a_direct_call_with_no_transport_is_unaffected() -> void:
	var id: GameplayNetEntityId = _everywhere(VICTIM_ENTITY, VICTIM_PEER)
	var forged: GameplayNetMessage = GameplayNetMessage.of(
		GameplayNetMessage.Kind.GENERIC_CONFIRM, id
	)
	var confirmed: Array[bool] = []
	server.registry.asc_for(id).generic_confirmed.connect(func() -> void: confirmed.append(true))

	assert_true(server.receive(forged), "a direct call names no sender to check")
	assert_eq(confirmed.size(), 1)
#endregion


#region AUD-09: routed by activation, not by whichever provider is first
## Two abilities on one entity, each aiming at once. An aim naming the second
## one's run reaches the second provider and never the first, which is the
## case "whichever provider is waiting" cannot tell apart at all.
func test_an_aim_reaches_the_provider_claimed_for_its_own_run_and_not_the_other() -> void:
	var id: GameplayNetEntityId = _everywhere(ATTACKER_ENTITY, ATTACKER_PEER)
	var owner_asc: AbilitySystemComponent = server.registry.asc_for(id)

	var spec_a: GameplayAbilitySpec = AbilityFactory.give(owner_asc, Probe.build(&"Ability.AimA"))
	var running_a: ProbeAbility = spec_a.per_actor_instance as ProbeAbility
	running_a.is_active = true
	var provider_a: GameplayLocationProvider3D = GameplayLocationProvider3D.new()
	running_a.aim_with(provider_a)
	provider_a.claim(GameplayNetActivationId.of(id, 1))

	var spec_b: GameplayAbilitySpec = AbilityFactory.give(owner_asc, Probe.build(&"Ability.AimB"))
	var running_b: ProbeAbility = spec_b.per_actor_instance as ProbeAbility
	running_b.is_active = true
	var provider_b: GameplayLocationProvider3D = GameplayLocationProvider3D.new()
	running_b.aim_with(provider_b)
	var activation_b: GameplayNetActivationId = GameplayNetActivationId.of(id, 2)
	provider_b.claim(activation_b)

	var heard_a: Array[GameplayAbilityTargetData] = []
	var heard_b: Array[GameplayAbilityTargetData] = []
	provider_a.confirmed.connect(func(d: GameplayAbilityTargetData) -> void: heard_a.append(d))
	provider_b.confirmed.connect(func(d: GameplayAbilityTargetData) -> void: heard_b.append(d))

	var data: GameplayAbilityTargetData = GameplayAbilityTargetData.new()
	data.append_location(Vector3(3.0, 0.0, 0.0))
	attacker.send_target_data(id, data, activation_b, GameplayPredictionKey.of(ATTACKER_PEER, 2))
	link.drain()

	assert_eq(heard_a.size(), 0, "the first provider never heard it")
	assert_eq(heard_b.size(), 1, "the aim named the second run and reached the second provider")


## An aim naming a run nobody claimed a provider for is refused as its own
## kind of wrong - not "nothing is aiming" and not "the aim itself is bad".
func test_an_aim_for_a_run_nobody_claimed_is_refused_as_activation_unknown() -> void:
	var id: GameplayNetEntityId = _everywhere(ATTACKER_ENTITY, ATTACKER_PEER)
	var owner_asc: AbilitySystemComponent = server.registry.asc_for(id)
	var spec: GameplayAbilitySpec = AbilityFactory.give(owner_asc, Probe.build(&"Ability.AimC"))
	var running: ProbeAbility = spec.per_actor_instance as ProbeAbility
	running.is_active = true
	var provider: GameplayLocationProvider3D = GameplayLocationProvider3D.new()
	running.aim_with(provider)
	provider.claim(GameplayNetActivationId.of(id, 1))

	var data: GameplayAbilityTargetData = GameplayAbilityTargetData.new()
	data.append_location(Vector3.ZERO)
	attacker.send_target_data(
		id, data, GameplayNetActivationId.of(id, 99), GameplayPredictionKey.of(ATTACKER_PEER, 9)
	)
	link.drain()

	assert_true(refusals.has(GameplayNetworkRuntime.REASON_ACTIVATION_UNKNOWN))
	assert_false(
		refusals.has(GameplayNetworkRuntime.REASON_TARGET_UNREACHABLE),
		"something is aiming here - just not under the run this aim named"
	)
#endregion
