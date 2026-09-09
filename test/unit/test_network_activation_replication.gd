## Whether the middle of an activation is anybody else's business.
##
## Most abilities: no. What a melee swing is doing between starting and ending
## is nobody's business but the machine running it, and a reading that carried
## every activation would spend a packet every frame on something no other
## machine acts on. The ones whose middle matters - a channel a UI draws a bar
## for, a stance another player has to be able to see - say so on the grant,
## and that is the whole of what ReplicationPolicy decides.
##
## What crosses is never the instance. A Node on a wire is a class name the
## receiver would have to construct; what crosses is the definition both
## machines already agree about, and the receiver is told rather than made to
## act - a client that started an ability because a reading said one was
## running would be a client running what the authority never asked it to.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const AbilityFactory = preload("res://test/fixtures/test_ability_factory.gd")

const ABILITY_TAG: StringName = &"Ability.Channelled"
const A_PATH: String = "res://test_only/replicated_probe_%d.tscn"

var made: int = 0
var bench: NetBench = null
var asc: AbilitySystemComponent = null
var entity: GameplayNetEntityId = null
var authority: GameplayNetworkRuntime = null
var client: GameplayNetworkRuntime = null


func before_each() -> void:
	bench = NetBench.built(self, "Replicated")
	autofree(bench.fixture.owner)
	asc = bench.asc()
	asc.set_process(false)
	entity = bench.entity
	authority = bench.runtime
	client = bench.client()


func after_each() -> void:
	bench.dispose()
	client.dispose()
	bench = null
	authority = null
	client = null
	asc = null


#region Whether the middle of it is anybody's business
##     [what the grant says, whether the owner is told it is running]
func _replication_cases() -> Array:
	return [
		["nothing about its own state", GameplayAbility.ReplicationPolicy.REPLICATE_NO, false],
		["that its middle matters", GameplayAbility.ReplicationPolicy.REPLICATE_YES, true],
	]


## Only an ability that said so tells its owner that it is running.
##
## What a melee swing is doing between starting and ending is nobody's business
## but the machine running it, and a reading that carried every activation
## would spend a packet every frame on something no other machine acts on. The
## abilities whose middle matters - a channel a UI draws a bar for - say so.
func test_only_a_replicating_ability_is_reported_as_running() -> void:
	var rows: Array = _replication_cases()
	var checked: int = 0
	for row: Array in rows:
		var described: String = row[0]
		var policy: GameplayAbility.ReplicationPolicy = row[1]
		var told: bool = row[2]

		before_each()
		var scene: PackedScene = _channelling(policy)
		var named: GameplayNetDefinitionId = authority.registry.register_definition(scene)

		var reading: GameplayNetState = GameplayNetReplication.snapshot_of(
			asc, authority.registry, GameplayNetReplication.Mode.FULL, true
		)
		assert_eq(reading.abilities.has(named.value), true, "%s: the grant is told" % described)
		assert_eq(
			reading.running_abilities.has(named.value), told,
			"%s: whether the run is" % described
		)
		checked += 1
	assert_eq(checked, rows.size(), "both policies were offered")


## And only its owner. Somebody else watching the fight sees the grant, not the
## run: a peer that is not this character's is exactly who the policy is about.
func test_a_replicating_activation_is_told_only_to_the_owner() -> void:
	var scene: PackedScene = _channelling(GameplayAbility.ReplicationPolicy.REPLICATE_YES)
	var named: GameplayNetDefinitionId = authority.registry.register_definition(scene)

	var watching: GameplayNetState = GameplayNetReplication.snapshot_of(
		asc, authority.registry, GameplayNetReplication.Mode.FULL, false
	)

	assert_true(watching.abilities.has(named.value), "the onlooker is told about the grant")
	assert_false(watching.running_abilities.has(named.value), "and not that it is running")


## An ability that stopped is said to have stopped, once.
##
## A delta that only carried what appeared would leave a cast bar on screen for
## an ability that ended half a minute ago, which is the same bug the effect
## and tag halves of a delta already exist to prevent.
func test_a_run_that_ended_is_reported_as_stopped() -> void:
	var scene: PackedScene = _channelling(GameplayAbility.ReplicationPolicy.REPLICATE_YES)
	var named: GameplayNetDefinitionId = authority.registry.register_definition(scene)
	var before: GameplayNetState = GameplayNetReplication.snapshot_of(
		asc, authority.registry, GameplayNetReplication.Mode.FULL, true
	)

	_let_the_channel_finish()
	var after: GameplayNetState = GameplayNetReplication.snapshot_of(
		asc, authority.registry, GameplayNetReplication.Mode.FULL, true
	)
	var change: GameplayNetState = GameplayNetReplication.delta_between(before, after)

	assert_true(change.stopped_abilities.has(named.value), "the run is over")
	assert_false(change.running_abilities.has(named.value), "and is not also starting")
	assert_false(
		change.revoked_abilities.has(named.value),
		"and the grant it was a run of is still there"
	)


## The peer that is told acts on nothing: it is told, and that is the whole of
## it. A client that started an ability because a reading said one was running
## would be a client running what the authority never asked it to.
func test_the_peer_told_about_a_run_is_only_told() -> void:
	var scene: PackedScene = _channelling(GameplayAbility.ReplicationPolicy.REPLICATE_YES)
	var named: GameplayNetDefinitionId = authority.registry.register_definition(scene)
	var heard: Array = []
	client.activation_replicated.connect(
		func(_entity: GameplayNetEntityId, definition: GameplayNetDefinitionId, running: bool) -> void:
			heard.append([definition.value, running])
	)

	var reading: GameplayNetMessage = GameplayNetMessage.of(
		GameplayNetMessage.Kind.STATE_SNAPSHOT, entity
	)
	reading.state = GameplayNetReplication.snapshot_of(
		asc, authority.registry, GameplayNetReplication.Mode.FULL, true
	)
	reading.sequence = 1

	assert_true(client.receive(reading), "the reading was applied")
	assert_eq(heard, [[named.value, true]], "and the run was announced once")
#endregion


#region Getting there
## A channelled ability, granted and running, with a replication policy on it.
##
## Channelled because a run is only interesting while it lasts: an ability that
## returned from activation has already stopped, and every reading of it would
## be the reading of something that is over.
func _channelling(policy: GameplayAbility.ReplicationPolicy) -> PackedScene:
	made += 1
	var probe: ProbeAbility = ProbeAbility.build(ABILITY_TAG)
	probe.replication_policy = policy
	var scene: PackedScene = AbilityFactory.packed_at(probe, A_PATH % made)
	var handle: GameplayAbilityHandle = asc.give_ability(scene)
	var spec: GameplayAbilitySpec = asc.get_ability_spec(handle)
	var running: ProbeAbility = spec.per_actor_instance as ProbeAbility
	running.channels = true
	asc.try_activate_ability_handle(handle)
	return scene


## Let every channel on this character finish, so what was running is not.
##
## The per-actor instance rather than the active-instance list: a grant with the
## default instancing policy keeps one instance and runs it, and a loop that
## only read the other list would open no gate and prove nothing.
func _let_the_channel_finish() -> void:
	for spec: GameplayAbilitySpec in asc.get_ability_specs():
		var probe: ProbeAbility = spec.per_actor_instance as ProbeAbility
		if probe != null:
			probe.channel_gate.emit()
#endregion
