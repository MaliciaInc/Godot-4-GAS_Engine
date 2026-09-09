## Hierarchical event dispatch and the typed payload.
##
## Matching runs in one direction only: a listener asks for a subtree, never for
## an ancestor. `Event.Damage` receives `Event.Damage.Critical`;
## `Event.Damage.Critical` does not receive the broader `Event.Damage`.
##
## @meta_license: GAS_Engine Community Use License 1.0
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
	probe.activation_policy = GameplayAbility.ActivationPolicy.ON_GAMEPLAY_EVENT
	probe.gameplay_event_triggers = [GameplayAbilityEventTrigger.for_tag(trigger)]
	probe.ability_tags = [&"Ability.Recorder"]
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
	late_probe.activation_policy = GameplayAbility.ActivationPolicy.ON_GAMEPLAY_EVENT
	late_probe.gameplay_event_triggers = [GameplayAbilityEventTrigger.for_tag(DAMAGE)]
	late_probe.ability_tags = [&"Ability.Late"]
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
#region The whole payload, and the shape a wire can carry
## Ten pieces, because a hit is not describable in five: what was struck, what
## struck with, and what either of them was at the moment it happened.
func test_an_event_carries_all_ten_payload_fields() -> void:
	var weapon: GameplayEffect = Factory.infinite([] as Array[GameplayEffectModifier])
	var event: GameplayEventData = GameplayEventData.new()
	event.event_tag = DAMAGE
	event.instigator = fixture.owner
	event.target = fixture.owner
	event.magnitude = 7.0
	event.context = GameplayEffectContext.new(fixture.owner)
	event.optional_object = weapon
	event.optional_object2 = weapon
	event.instigator_tags = [&"Caster.Undead"] as Array[StringName]
	event.target_tags = [&"Victim.Living"] as Array[StringName]
	event.target_data = GameplayAbilityTargetData.new()

	assert_eq(event.event_tag, DAMAGE, "the tag")
	assert_eq(event.instigator, fixture.owner, "who caused it")
	assert_eq(event.target, fixture.owner, "who it is about")
	assert_eq(event.magnitude, 7.0, "the one number")
	assert_not_null(event.context, "where it came from")
	assert_eq(event.optional_object, weapon, "the first slot")
	assert_eq(event.optional_object2, weapon, "and the second")
	assert_eq(event.instigator_tags.size(), 1, "what the instigator was")
	assert_eq(event.target_tags.size(), 1, "what the target was")
	assert_not_null(event.target_data, "and what it was aimed at")


## The snapshots are of the moment it was sent. A listener woken later is about
## that moment, and re-reading the world would answer a different question.
func test_event_tag_snapshots_do_not_change_after_dispatch() -> void:
	asc.add_tag(&"Caster.Undead")

	var event: GameplayEventData = _event(DAMAGE)
	asc.send_gameplay_event(event)

	assert_true(event.instigator_tags.has(&"Caster.Undead"), "frozen as it was")

	asc.remove_tag(&"Caster.Undead")
	asc.add_tag(&"Caster.Living")

	assert_true(event.instigator_tags.has(&"Caster.Undead"), "and it stays that way")
	assert_false(event.instigator_tags.has(&"Caster.Living"), "the world moved on without it")


## A sender that filled the snapshot in itself knew something dispatch does not,
## so dispatch leaves it alone.
func test_a_sender_that_said_what_the_tags_were_is_believed() -> void:
	asc.add_tag(&"Caster.Living")

	var event: GameplayEventData = _event(DAMAGE)
	event.instigator_tags = [&"Caster.Undead"] as Array[StringName]
	asc.send_gameplay_event(event)

	assert_eq(event.instigator_tags, [&"Caster.Undead"] as Array[StringName], "as it was told")


func test_gameplay_event_wire_round_trips_without_object_references() -> void:
	var said: GameplayEventWire = GameplayEventWire.new()
	said.event_tag = CRITICAL
	said.instigator = GameplayNetEntityId.of(7)
	said.target = GameplayNetEntityId.of(9)
	said.instigator_tags = [&"Caster.Undead"] as Array[StringName]
	said.target_tags = [&"Victim.Living"] as Array[StringName]
	said.magnitude = 3.5

	var wire: Dictionary = said.to_wire()
	for key: Variant in wire:
		var carried: Variant = wire[key]
		assert_false(carried is Object, "`%s` crosses as a value, not a reference" % key)

	# Through JSON, because that is what this addon's wire is. Handing the
	# dictionary straight back proved the shape and nothing about the crossing:
	# JSON has one number type, every integer comes back a float, and a reader
	# comparing against TYPE_INT refused every event that had actually crossed.
	var read: Variant = JSON.parse_string(JSON.stringify(wire))
	assert_true(read is Dictionary, "it is still a dictionary after JSON")
	var crossed: Dictionary = read if read is Dictionary else {}

	var back: GameplayEventWire = GameplayEventWire.from_wire(crossed)
	assert_not_null(back, "it came back")
	assert_eq(back.event_tag, CRITICAL, "the tag survived")
	assert_eq(back.instigator.value, 7, "and who caused it")
	assert_eq(back.target.value, 9, "and who it was about")
	assert_eq(back.instigator_tags, said.instigator_tags, "and both snapshots")
	assert_eq(back.target_tags, said.target_tags, "both of them")
	assert_almost_eq(back.magnitude, 3.5, 0.0001, "and the number")


## A malformed wire is refused rather than repaired: it came from a machine that
## disagrees about this contract, and guessing what it meant is how one bad
## sender becomes two.
func test_a_malformed_wire_is_refused_rather_than_repaired() -> void:
	var wire: Dictionary = GameplayEventWire.new().to_wire()
	wire[GameplayEventWire.MAGNITUDE_KEY] = "not a number"

	assert_null(GameplayEventWire.from_wire(wire), "a field of the wrong type is a refusal")
	assert_null(GameplayEventWire.from_wire({}), "and so is nothing at all")


## An object with no place to live has no name another machine could resolve, so
## it is left out - not sent as its address, and not as its class.
func test_an_unregistered_optional_object_is_omitted_not_stringified() -> void:
	var registry: GameplayNetRegistry = GameplayNetRegistry.new()

	var event: GameplayEventData = _event(DAMAGE)
	event.optional_object = GameplayEffect.new()

	var said: GameplayEventWire = GameplayEventTranslator.to_wire(event, registry)

	assert_not_null(said, "the event still crosses")
	assert_null(said.optional_definition, "the nameless object did not")
	var wire: Dictionary = said.to_wire()
	# Compared as a bool rather than handed to assert_eq: a Dictionary answers
	# Variant, tests are not excluded from this project's warnings, and an
	# untyped argument to a typed parameter is one of them.
	var says_none: bool = wire[GameplayEventWire.OPTIONAL_KEY] == GameplayNetDefinitionId.NONE
	assert_true(says_none, "the wire says there was none rather than describing it")
#endregion
