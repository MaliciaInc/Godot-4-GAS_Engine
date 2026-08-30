## Hierarchical event dispatch and the typed payload.
##
## Matching runs in one direction only: a listener asks for a subtree, never for
## an ancestor. `Event.Damage` receives `Event.Damage.Critical`;
## `Event.Damage.Critical` does not receive the broader `Event.Damage`.
##
## @meta_license: MIT
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Factory = preload("res://test/fixtures/test_effect_factory.gd")
const AbilityFactory = preload("res://test/fixtures/test_ability_factory.gd")

const DAMAGE: StringName = &"Event.Damage"
const CRITICAL: StringName = &"Event.Damage.Critical"
const CRITICAL_FIRE: StringName = &"Event.Damage.Critical.Fire"
const DAMAGES: StringName = &"Event.Damages"
const DAMAGEABLE: StringName = &"Event.Damageable"

var fixture: ASCFixture = null
var asc: AbilitySystemComponent = null


func before_each() -> void:
	fixture = Fixture.create("Listener")
	add_child_autofree(fixture.owner)
	asc = fixture.asc


func after_each() -> void:
	fixture = null
	asc = null


func _event(tag: StringName) -> GameplayEventData:
	var event: GameplayEventData = GameplayEventData.new()
	event.event_tag = tag
	event.instigator = fixture.owner
	event.target = fixture.owner
	event.magnitude = 7.0
	return event


func _listener(trigger: StringName) -> RecordingAbility:
	var probe: RecordingAbility = RecordingAbility.new()
	probe.trigger_event_tag = trigger
	probe.ability_tag = &"Ability.Recorder"
	var spec: GameplayAbilitySpec = AbilityFactory.give(asc, probe)
	return spec.per_actor_instance as RecordingAbility


#region Matching
func test_an_exact_tag_reaches_its_listener() -> void:
	var listener: RecordingAbility = _listener(DAMAGE)
	asc.send_gameplay_event(_event(DAMAGE))
	assert_eq(listener.activations, 1)


func test_a_child_reaches_a_listener_on_the_parent() -> void:
	var listener: RecordingAbility = _listener(DAMAGE)
	asc.send_gameplay_event(_event(CRITICAL))
	assert_eq(listener.activations, 1, "Event.Damage hears Event.Damage.Critical")


func test_a_deep_child_reaches_it_too() -> void:
	var listener: RecordingAbility = _listener(DAMAGE)
	asc.send_gameplay_event(_event(CRITICAL_FIRE))
	assert_eq(listener.activations, 1, "two levels down still matches")


func test_a_false_prefix_does_not_match() -> void:
	var listener: RecordingAbility = _listener(DAMAGE)
	asc.send_gameplay_event(_event(DAMAGES))
	asc.send_gameplay_event(_event(DAMAGEABLE))
	# The separator is part of the rule. Without it, a listener on Event.Damage
	# would wake for Event.Damageable, which is a different thing entirely.
	assert_eq(listener.activations, 0, "Damages and Damageable are not under Damage")


func test_a_listener_does_not_hear_its_own_ancestor() -> void:
	var listener: RecordingAbility = _listener(CRITICAL_FIRE)
	asc.send_gameplay_event(_event(CRITICAL))
	assert_eq(listener.activations, 0, "a listener asks for a subtree, not a parent")
#endregion


#region Payload
func test_the_payload_arrives_intact() -> void:
	var received: Array[GameplayEventData] = []
	asc.gameplay_event_received.connect(func(event: GameplayEventData) -> void: received.append(event))

	var sent: GameplayEventData = _event(CRITICAL)
	asc.send_gameplay_event(sent)

	assert_eq(received.size(), 1)
	assert_eq(received[0].event_tag, CRITICAL, "tag")
	assert_eq(received[0].instigator, fixture.owner, "instigator")
	assert_eq(received[0].target, fixture.owner, "target")
	assert_almost_eq(received[0].magnitude, 7.0, 0.0001, "magnitude")


func test_an_empty_tag_is_not_dispatched() -> void:
	var listener: RecordingAbility = _listener(DAMAGE)
	watch_signals(asc)
	asc.send_gameplay_event(_event(&""))
	assert_eq(listener.activations, 0)
	assert_signal_not_emitted(asc, "gameplay_event_received")
#endregion


#region Several listeners
func test_two_listeners_each_receive_once() -> void:
	var first: RecordingAbility = _listener(DAMAGE)
	var second: RecordingAbility = _listener(CRITICAL)
	asc.send_gameplay_event(_event(CRITICAL))
	assert_eq(first.activations, 1, "the parent listener")
	assert_eq(second.activations, 1, "the exact listener")


func test_a_listener_granted_during_dispatch_does_not_receive_this_event() -> void:
	var late_probe: RecordingAbility = RecordingAbility.new()
	late_probe.trigger_event_tag = DAMAGE
	late_probe.ability_tag = &"Ability.Late"
	# A lambda captures an outer local by value: reassigning `late` inside the
	# callback would rebind only its own copy, and the ability actually granted
	# would never reach this scope. A one-element array is captured by the same
	# reference on both sides, so writing into slot 0 is visible out here too.
	var late: Array[RecordingAbility] = [null]

	var granter: RecordingAbility = _listener(DAMAGE)
	granter.ability_ended.connect(func(_cancelled: bool) -> void:
		late[0] = AbilityFactory.give(asc, late_probe).per_actor_instance as RecordingAbility
	)

	asc.send_gameplay_event(_event(DAMAGE))
	# Eligible listeners are snapshotted before the first callback runs, so an
	# ability granted mid-dispatch joins the next event, not this one.
	assert_eq(granter.activations, 1)
	assert_eq(late[0].activations, 0, "the newcomer waits for the next event")


func test_dispatch_survives_a_listener_removing_another() -> void:
	var first: RecordingAbility = _listener(DAMAGE)
	var second: RecordingAbility = _listener(DAMAGE)
	var third: RecordingAbility = _listener(DAMAGE)

	# The first listener removes the second while the dispatch is running.
	# Without a snapshot, erasing from the live array would make the loop skip
	# the third.
	first.ability_ended.connect(func(_cancelled: bool) -> void: asc.remove_ability(second))

	asc.send_gameplay_event(_event(DAMAGE))
	assert_eq(first.activations, 1, "the remover ran")
	assert_eq(third.activations, 1, "and its neighbour was not skipped")
#endregion


#region Effects broadcast events
func test_an_effect_broadcasts_its_declared_event_tags() -> void:
	var listener: RecordingAbility = _listener(DAMAGE)
	var effect: GameplayEffect = Factory.with_events(
		Factory.instant([Factory.add(&"health", -5.0)]), [CRITICAL] as Array[StringName]
	)
	Factory.apply(asc, effect)
	assert_eq(listener.activations, 1, "the effect woke the passive")
#endregion
