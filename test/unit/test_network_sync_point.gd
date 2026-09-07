## The point in an ability where it must not run any further alone.
##
## A predicted ability runs ahead on the machine that pressed the button and
## behind on the one that owns the game, and there are places in the middle
## where running ahead is not allowed: before it spends something, before it
## decides what it hit. A sync point is that place.
##
## It used to be told by hand that the server had arrived, which is a test's way
## of saying it. Given the key of the request the ability actually sent, it
## waits for the answer to that request - and a refusal ends it rather than
## leaving it waiting for a confirm that is never coming.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const AbilityFactory = preload("res://test/fixtures/test_ability_factory.gd")
const Probe = preload("res://test/fixtures/probe_ability.gd")

const OWNING_PEER: int = 2
const ENTITY: int = 1

var fixture: ASCFixture = null
var asc: AbilitySystemComponent = null
var ability: GameplayAbility = null
var client: GameplayNetworkRuntime = null


func before_each() -> void:
	fixture = Fixture.create("Predictor")
	add_child_autofree(fixture.owner)
	asc = fixture.asc
	asc.set_process(false)
	ability = AbilityFactory.give(asc, Probe.build(&"Ability.Synced")).per_actor_instance
	ability.is_active = true
	client = GameplayNetworkRuntime.new()
	client.role = GameplayNetAuthority.Role.CLIENT
	client.peer = OWNING_PEER
	client.attach(asc, GameplayNetEntityId.of(ENTITY), OWNING_PEER)


func after_each() -> void:
	client.dispose()
	client = null
	fixture = null
	asc = null
	ability = null


func _answer(key: GameplayPredictionKey, kind: GameplayNetMessage.Kind) -> GameplayNetMessage:
	var message: GameplayNetMessage = GameplayNetMessage.of(kind, GameplayNetEntityId.of(ENTITY))
	message.activation = GameplayNetActivationId.of(GameplayNetEntityId.of(ENTITY), 7)
	message.prediction_key = key
	return message


#region Waiting on a real answer
## The machine that owns the game arriving is the confirm arriving.
func test_a_confirm_is_the_server_arriving() -> void:
	var key: GameplayPredictionKey = client.journal.next_key(OWNING_PEER)
	var point: AbilityTaskNetworkSyncPoint = AbilityTaskFactory.network_sync_point(
		ability, AbilityTaskNetworkSyncPoint.Wait.ONLY_SERVER, 0.0, key
	)
	assert_false(point.is_finished(), "nothing has answered yet")

	client.receive(_answer(key, GameplayNetMessage.Kind.ACTIVATION_CONFIRM))

	assert_true(point.server_arrived, "the authority arrived")
	assert_eq(point.state, GameplayAbilityTask.State.SUCCEEDED)
	assert_eq(point.confirmed_activation.sequence, 7, "and it says which run it confirmed")


## A refusal is not a late arrival. An ability whose request was refused is not
## going to be confirmed afterwards, and a point that kept waiting would hold
## the ability open for its whole timeout and then let it carry on as though
## nothing had been refused.
func test_a_refusal_ends_the_point_rather_than_leaving_it_waiting() -> void:
	var key: GameplayPredictionKey = client.journal.next_key(OWNING_PEER)
	var point: AbilityTaskNetworkSyncPoint = AbilityTaskFactory.network_sync_point(
		ability, AbilityTaskNetworkSyncPoint.Wait.ONLY_SERVER, 0.0, key
	)

	client.receive(_answer(key, GameplayNetMessage.Kind.ACTIVATION_REJECT))

	assert_eq(point.state, GameplayAbilityTask.State.CANCELLED)
	assert_false(point.server_arrived, "nobody arrived - it was called off")


## What is not enough on its own, and there are two of those.
##
## An answer to somebody else's request is not this point's answer at all. And
## its own answer is not enough either when the point is a rendezvous and the
## local half has not got there yet - which is the whole difference between
## waiting for the authority and waiting for both.
##
##     [what is not enough, which side it waits for, whose answer arrives]
func _not_enough() -> Array:
	return [
		["an answer to another request", AbilityTaskNetworkSyncPoint.Wait.ONLY_SERVER, false],
		["a rendezvous with only one side", AbilityTaskNetworkSyncPoint.Wait.BOTH, true],
	]


func test_a_point_waits_on_until_what_it_is_waiting_for_has_happened() -> void:
	var rows: Array = _not_enough()
	var checked: int = 0
	for row: Array in rows:
		var described: String = row[0]
		var waits_for: AbilityTaskNetworkSyncPoint.Wait = row[1]
		var answer_is_its_own: bool = row[2]

		before_each()
		var mine: GameplayPredictionKey = client.journal.next_key(OWNING_PEER)
		var theirs: GameplayPredictionKey = client.journal.next_key(OWNING_PEER)
		var point: AbilityTaskNetworkSyncPoint = AbilityTaskFactory.network_sync_point(
			ability, waits_for, 0.0, mine
		)

		client.receive(
			_answer(
				mine if answer_is_its_own else theirs,
				GameplayNetMessage.Kind.ACTIVATION_CONFIRM
			)
		)

		assert_false(point.is_finished(), described)
		checked += 1
	assert_eq(checked, rows.size(), "both were offered")


## And a rendezvous whose local half then arrives is done.
func test_a_rendezvous_ends_once_both_sides_are_there() -> void:
	var key: GameplayPredictionKey = client.journal.next_key(OWNING_PEER)
	var point: AbilityTaskNetworkSyncPoint = AbilityTaskFactory.network_sync_point(
		ability, AbilityTaskNetworkSyncPoint.Wait.BOTH, 0.0, key
	)
	client.receive(_answer(key, GameplayNetMessage.Kind.ACTIVATION_CONFIRM))

	point.client_arrives()

	assert_eq(point.state, GameplayAbilityTask.State.SUCCEEDED)
#endregion


#region Letting go
## The listening stops when the point does, whichever way it ended.
func test_a_point_that_ended_is_no_longer_listening() -> void:
	var key: GameplayPredictionKey = client.journal.next_key(OWNING_PEER)
	var point: AbilityTaskNetworkSyncPoint = AbilityTaskFactory.network_sync_point(
		ability, AbilityTaskNetworkSyncPoint.Wait.ONLY_SERVER, 0.0, key
	)
	assert_eq(
		client.activation_answered.get_connections().size(), 1, "it was listening"
	)

	ability.end_ability(true)

	assert_true(point.is_finished())
	assert_eq(
		client.activation_answered.get_connections().size(), 0,
		"and a cancelled ability leaves nothing connected to the network"
	)


## A point nobody gave a key to is the one every existing caller builds: the
## game drives it, and it listens for nothing.
func test_a_point_with_no_key_listens_for_nothing() -> void:
	AbilityTaskFactory.network_sync_point(ability, AbilityTaskNetworkSyncPoint.Wait.BOTH)

	assert_eq(client.activation_answered.get_connections().size(), 0)
#endregion
