## Gate F5.5 — the thirteen cases, over a wire that misbehaves.
##
## Three machines in one process and a link between them that can be told to
## repeat, reorder, lose and delay. None of those are reachable from a suite
## that hands messages straight across, and every one of them is a thing a real
## socket does without being asked.
##
## Each test is one of the thirteen the phase lists, in its order. What they
## have in common is the shape of the failure they guard: something arrives
## twice, or late, or not at all, and the character ends up paying twice,
## holding a cooldown for a cast that never happened, or watching a cue for an
## ability that was refused.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const AbilityFactory = preload("res://test/fixtures/test_ability_factory.gd")
const EffectFactory = preload("res://test/fixtures/test_effect_factory.gd")
const CueProbe = preload("res://test/fixtures/cue_probe.gd")
const CueManagerScript = preload("res://addons/GAS_Engine/managers/gameplay_cue_manager.gd")

const SERVER_PEER: int = 1
const FIRST_PEER: int = 2
const SECOND_PEER: int = 3
const FIRST_ENTITY: int = 10
const SECOND_ENTITY: int = 20
const MANA: StringName = &"mana"
const HEALTH: StringName = &"health"
const IMPACT: StringName = &"Cue.Gate.Impact"
const A_PATH: String = "res://test_only/gate_f5_5_%d.tscn"
const AN_EFFECT_PATH: String = "res://test_only/gate_f5_5_effect_%d.tres"

var made: int = 0
var link: NetLink = null
var server: GameplayNetworkRuntime = null
var first: GameplayNetworkRuntime = null
var second: GameplayNetworkRuntime = null
var manager: CueManagerScript = null
var _bound: Array[StringName] = []


func before_each() -> void:
	link = NetLink.new()
	server = _machine(GameplayNetAuthority.Role.AUTHORITY, SERVER_PEER)
	first = _machine(GameplayNetAuthority.Role.CLIENT, FIRST_PEER)
	second = _machine(GameplayNetAuthority.Role.CLIENT, SECOND_PEER)
	manager = null


func after_each() -> void:
	for tag: StringName in _bound:
		CueProbe.uninstall(manager, tag)
	_bound = []
	for machine: GameplayNetworkRuntime in [server, first, second]:
		machine.dispose()
	link = null
	server = null
	first = null
	second = null
	manager = null


#region Getting there
func _machine(role: GameplayNetAuthority.Role, peer: int) -> GameplayNetworkRuntime:
	var runtime: GameplayNetworkRuntime = GameplayNetworkRuntime.new()
	runtime.role = role
	runtime.peer = peer
	runtime.replication_mode = GameplayNetReplication.Mode.FULL
	link.join(runtime)
	return runtime


## An entity every machine knows about, owned by one of them.
func _everywhere(value: int, owner_peer: int) -> GameplayNetEntityId:
	var id: GameplayNetEntityId = GameplayNetEntityId.of(value)
	for machine: GameplayNetworkRuntime in [server, first, second]:
		var fixture: ASCFixture = Fixture.create("Entity%d" % value)
		add_child_autofree(fixture.owner)
		fixture.asc.set_process(false)
		fixture.set_base(MANA, 100.0)
		fixture.set_base(HEALTH, 100.0)
		machine.attach(fixture.asc, id, owner_peer)
	return id


func _ability(policy: GameplayAbility.NetExecutionPolicy) -> PackedScene:
	made += 1
	var scene: PackedScene = AbilityFactory.net_ability(policy, A_PATH % made)
	for machine: GameplayNetworkRuntime in [server, first, second]:
		machine.registry.register_definition(scene)
	return scene


func _asc(machine: GameplayNetworkRuntime, id: GameplayNetEntityId) -> AbilitySystemComponent:
	return machine.registry.asc_for(id)
#endregion


#region 0: what the wire actually carries
## Everything below crosses as bytes, and this is the case that says so.
##
## Not a claim about the engine but about the fixture every other case here
## stands on, which is worth one test because the whole walk is only as honest
## as it. A link that handed the message object between runtimes would pass all
## thirteen and prove nothing about a crossing - and that is not hypothetical:
## two defects in this addon's wire readers survived a whole phase behind
## exactly that, because JSON has one number type and no vectors and nothing
## that never serialised could see it.
##
## A message that will not encode is handed to nobody. That is the observable
## end of it: it is not delivered as the object it already was.
func test_case_zero_the_wire_carries_bytes_and_nothing_else() -> void:
	var id: GameplayNetEntityId = _everywhere(FIRST_ENTITY, FIRST_PEER)
	var before: int = link.delivered

	# A grant with no definition: complete enough to build, not enough to send.
	server.publish(GameplayNetMessage.of(GameplayNetMessage.Kind.GRANT, id))
	link.drain()

	assert_eq(link.unsendable, 1, "it never became bytes")
	assert_eq(link.delivered, before, "so nobody was handed it")

	# And one that does encode still arrives, so the refusal above is about the
	# message rather than about the link having stopped working.
	server.grant(id, _ability(GameplayAbility.NetExecutionPolicy.LOCAL_PREDICTED))
	link.drain()

	assert_gt(link.delivered, before, "a message that encodes crosses")
#endregion


#region 1-2: who is at the table
## 1. A listen server is an authority that also owns a character.
##
## Which is a fact about ownership rather than about what the machine may do -
## and the whole reason the roles are two and not three.
func test_case_one_a_listen_server_owns_a_character_and_still_authors() -> void:
	var mine: GameplayNetEntityId = _everywhere(FIRST_ENTITY, SERVER_PEER)
	var theirs: GameplayNetEntityId = _everywhere(SECOND_ENTITY, SECOND_PEER)

	assert_true(server.registry.is_owned_by(mine, SERVER_PEER), "the host plays too")
	assert_true(server.grant(mine, _ability(GameplayAbility.NetExecutionPolicy.LOCAL_ONLY)))
	assert_true(server.grant(theirs, _ability(GameplayAbility.NetExecutionPolicy.LOCAL_ONLY)))
	assert_false(first.grant(theirs, _ability(GameplayAbility.NetExecutionPolicy.LOCAL_ONLY)))


## 2. A dedicated server owns nobody, and the two clients own one each.
func test_case_two_a_dedicated_server_owns_nobody() -> void:
	var mine: GameplayNetEntityId = _everywhere(FIRST_ENTITY, FIRST_PEER)
	var theirs: GameplayNetEntityId = _everywhere(SECOND_ENTITY, SECOND_PEER)

	assert_false(server.registry.is_owned_by(mine, SERVER_PEER))
	assert_true(server.registry.is_owned_by(mine, FIRST_PEER))
	assert_true(server.registry.is_owned_by(theirs, SECOND_PEER))
	assert_false(
		server.registry.is_owned_by(theirs, FIRST_PEER),
		"and neither client owns the other's"
	)
#endregion


#region 3-6: what the wire does to what it carries
## 3-5. What a wire does to what it carries, and what survives each of it.
##
## Latency is nothing having arrived yet. A duplicate is the same reading
## twice, which is harmless because a reading carries values rather than
## increments. A reorder is the older reading arriving last, which is not
## harmless at all - applied, it would put a character back the way it was and
## leave it there until that same attribute happened to change again.
##
##     [what the wire does, held, duplicated, reordered, where health ends up]
func _wire_conditions() -> Array:
	return [
		["a wire with latency on it", true, false, false, 40.0],
		["a wire that repeats itself", false, true, false, 40.0],
		["a wire that delivers backwards", true, false, true, 40.0],
	]


func test_cases_three_to_five_a_misbehaving_wire_lands_the_newest_reading() -> void:
	var rows: Array = _wire_conditions()
	var checked: int = 0
	for row: Array in rows:
		var described: String = row[0]
		var held: bool = row[1]
		var duplicated: bool = row[2]
		var reordered: bool = row[3]
		var ends_at: float = row[4]

		before_each()
		var id: GameplayNetEntityId = _everywhere(FIRST_ENTITY, FIRST_PEER)
		link.holds = held
		link.duplicates = duplicated
		link.reorders = reordered

		_asc(server, id).set_attribute_base(HEALTH, 70.0)
		server.snapshot_for(id, FIRST_PEER)
		_asc(server, id).set_attribute_base(HEALTH, 40.0)
		server.snapshot_for(id, FIRST_PEER)

		if held:
			assert_almost_eq(
				_asc(first, id).get_attribute_base(HEALTH), 100.0, 0.001,
				"%s: sent, and nobody has received" % described
			)
		link.drain()

		assert_almost_eq(_asc(first, id).get_attribute_base(HEALTH), ends_at, 0.001, described)
		checked += 1
	assert_eq(checked, rows.size(), "every condition was carried")


## 6. A request the wire lost, asked again.
##
## The retry is a second request with its own key, and the answer to it is the
## only answer: the first ask never reached anybody.
func test_case_six_a_dropped_request_is_asked_again_and_answered_once() -> void:
	var id: GameplayNetEntityId = _everywhere(FIRST_ENTITY, FIRST_PEER)
	var scene: PackedScene = _ability(GameplayAbility.NetExecutionPolicy.LOCAL_PREDICTED)
	var answers: Array[GameplayNetMessage] = []
	server.message_ready.connect(func(m: GameplayNetMessage) -> void: answers.append(m))

	link.drops_next = 1
	first.start(_asc(first, id), scene)
	assert_eq(link.dropped, 1, "the wire ate it")
	assert_eq(answers.size(), 0, "so nobody answered")

	first.start(_asc(first, id), scene)
	assert_eq(answers.size(), 1, "the retry was answered")
	assert_eq(answers[0].kind, GameplayNetMessage.Kind.ACTIVATION_CONFIRM)
#endregion


#region 7-11: guessing, and what it must not cost twice
## Ask, with the wire holding the answer.
##
## Held because a client predicts and then finds out, in that order. A wire
## that answered inside the asking would be a client told no before it had
## made the guess, which is not a thing that happens and not what this is
## about.
func _predicting(id: GameplayNetEntityId, scene: PackedScene) -> GameplayPredictionKey:
	var asking: Array[GameplayNetMessage] = []
	first.message_ready.connect(func(m: GameplayNetMessage) -> void: asking.append(m))
	link.holds = true
	first.start(_asc(first, id), scene)
	return asking[0].prediction_key


## 7-9. A guess that is accepted stays, and is not charged a second time.
func test_cases_seven_and_nine_an_accepted_guess_is_paid_for_once() -> void:
	var id: GameplayNetEntityId = _everywhere(FIRST_ENTITY, FIRST_PEER)
	var scene: PackedScene = _ability(GameplayAbility.NetExecutionPolicy.LOCAL_PREDICTED)
	var mine: AbilitySystemComponent = _asc(first, id)

	var key: GameplayPredictionKey = _predicting(id, scene)
	mine.set_attribute_base(MANA, 70.0)
	first.journal.record(GameplayPredictionOperation.cost(key, MANA, 30.0))
	assert_eq(first.journal.size(), 1, "the guess is owed while the answer travels")

	link.drain()

	assert_almost_eq(mine.get_attribute_base(MANA), 70.0, 0.001, "spent once, and once only")
	assert_true(first.journal.is_empty(), "the answer came back and bound it")


## 8, 10. A guess that is refused is put back, cooldown and all.
func test_cases_eight_and_ten_a_refused_guess_takes_its_cooldown_with_it() -> void:
	var id: GameplayNetEntityId = _everywhere(FIRST_ENTITY, SECOND_PEER)
	var scene: PackedScene = _ability(GameplayAbility.NetExecutionPolicy.LOCAL_PREDICTED)
	var mine: AbilitySystemComponent = _asc(first, id)

	var key: GameplayPredictionKey = _predicting(id, scene)
	mine.set_attribute_base(MANA, 70.0)
	first.journal.record(GameplayPredictionOperation.cost(key, MANA, 30.0))
	made += 1
	var cooldown: GameplayEffect = EffectFactory.infinite(
		[] as Array[GameplayEffectModifier]
	)
	cooldown.take_over_path(AN_EFFECT_PATH % made)
	var applied: ActiveGameplayEffect = EffectFactory.apply(mine, cooldown)
	first.journal.record(
		GameplayPredictionOperation.cooldown(first.journal.next_key(FIRST_PEER, key), applied.handle)
	)

	link.drain()

	assert_almost_eq(mine.get_attribute_base(MANA), 100.0, 0.001, "the mana came back")
	assert_null(mine.get_active_effect(applied.handle), "and the cooldown came off with it")
	assert_true(first.journal.is_empty())


## 11. No ghost cue: a persistent cue started on a guess that was refused is
## not still playing afterwards.
func test_case_eleven_a_refused_guess_leaves_no_cue_playing() -> void:
	var id: GameplayNetEntityId = _everywhere(FIRST_ENTITY, SECOND_PEER)
	var scene: PackedScene = _ability(GameplayAbility.NetExecutionPolicy.LOCAL_PREDICTED)
	var mine: AbilitySystemComponent = _asc(first, id)
	manager = mine.get_node_or_null("/root/GameplayCueManager") as CueManagerScript
	CueProbe.install(manager, IMPACT)
	_bound.append(IMPACT)

	var key: GameplayPredictionKey = _predicting(id, scene)
	var playing: GameplayCueHandle = mine.activate_persistent_cue(
		CueProbe.params_for(IMPACT, mine.get_effect_target())
	)
	first.journal.record(GameplayPredictionOperation.cue(key, IMPACT, playing))
	assert_eq(manager.get_pooled_count(IMPACT), 0, "the cue is out and playing")

	link.drain()

	assert_eq(manager.get_pooled_count(IMPACT), 1, "and the refusal put it away")
#endregion


#region 12-13: joining late, and coming back
## 12. A late joiner is caught up by a snapshot and kept up by deltas.
func test_case_twelve_a_late_joiner_is_caught_up_before_it_is_kept_up() -> void:
	var id: GameplayNetEntityId = _everywhere(FIRST_ENTITY, FIRST_PEER)
	var refused: Array[StringName] = []
	second.message_refused.connect(
		func(_m: GameplayNetMessage, reason: StringName) -> void: refused.append(reason)
	)
	_asc(server, id).set_attribute_base(HEALTH, 80.0)

	# The second client is not listening yet, which is the whole of what a late
	# joiner is: it missed what everybody else was told.
	link.leave(second)
	server.snapshot_for(id, FIRST_PEER)
	link.join(second)
	_asc(server, id).set_attribute_base(HEALTH, 30.0)
	server.delta_for(id, FIRST_PEER)

	assert_almost_eq(
		_asc(first, id).get_attribute_base(HEALTH), 30.0, 0.001, "the one that was here kept up"
	)
	assert_almost_eq(
		_asc(second, id).get_attribute_base(HEALTH), 100.0, 0.001,
		"and the one that was not has moved nowhere: a delta is not something to "
		+ "apply to a character you have never been told about"
	)
	assert_true(
		refused.has(GameplayNetworkRuntime.REASON_NOTHING_TO_UPDATE),
		"which is refused rather than applied halfway"
	)

	server.snapshot_for(id, SECOND_PEER)

	assert_almost_eq(
		_asc(second, id).get_attribute_base(HEALTH), 30.0, 0.001,
		"and a snapshot is what catches it up - state before deltas, which is the "
		+ "whole of what joining late means"
	)


## 13. A respawn swaps the body and keeps everything the component owns.
func test_case_thirteen_a_respawn_keeps_the_grants_and_the_state() -> void:
	var id: GameplayNetEntityId = _everywhere(FIRST_ENTITY, FIRST_PEER)
	var scene: PackedScene = _ability(GameplayAbility.NetExecutionPolicy.LOCAL_ONLY)
	var mine: AbilitySystemComponent = _asc(server, id)
	mine.give_ability(scene)
	mine.set_attribute_base(HEALTH, 55.0)
	var before: GameplayNetState = GameplayNetReplication.snapshot_of(mine, server.registry)

	var reborn: Node = Node.new()
	add_child_autofree(reborn)
	mine.init_ability_actor_info(mine.get_parent(), reborn)

	assert_same(mine.actor_info.avatar, reborn, "a new body")
	assert_true(
		GameplayNetReplication.delta_between(
			before, GameplayNetReplication.snapshot_of(mine, server.registry)
		).is_empty(),
		"and nothing the component owns moved with it"
	)
#endregion
