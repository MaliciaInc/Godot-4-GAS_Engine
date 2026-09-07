## What an ability knows about the event that woke it.
##
## An event carries five things: which tag fired, who caused it, who it was
## aimed at, how much of it there was, and the effect context behind it. An
## event-triggered ability used to be handed the last of those and nothing else,
## so an ability that needed the magnitude - a counter-attack scaled to the blow
## it answers, a shield that absorbs what it was hit for - had to go and find it
## in the world. The world has moved on by then: the blow has landed, the
## attacker may be dead, and what it reads is not what happened.
##
## So the event travels with the activation. An ability activated by a call gets
## no event, because there was none, and that is worth asserting too - an
## `get_activation_event()` that returned the last event anybody raised would be
## worse than returning nothing.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const AbilityFactory = preload("res://test/fixtures/test_ability_factory.gd")
const Probe = preload("res://test/fixtures/probe_ability.gd")

const REACTS_TO: StringName = &"Event.Struck"
const ABILITY_TAG: StringName = &"Ability.Counter"

var fixture: ASCFixture = null
var asc: AbilitySystemComponent = null


func before_each() -> void:
	fixture = Fixture.create("Defender")
	add_child_autofree(fixture.owner)
	asc = fixture.asc
	asc.set_process(false)


func after_each() -> void:
	fixture = null
	asc = null


#region Getting there
## An ability that wakes when that event is raised.
func _listening() -> GameplayAbilitySpec:
	var probe: ProbeAbility = Probe.build(ABILITY_TAG)
	probe.activation_policy = GameplayAbility.ActivationPolicy.ON_GAMEPLAY_EVENT
	var triggers: Array[GameplayAbilityEventTrigger] = [
		GameplayAbilityEventTrigger.for_tag(REACTS_TO)
	]
	probe.gameplay_event_triggers = triggers
	return AbilityFactory.give(asc, probe)


## An ability nothing wakes: it is called, or it is not activated.
func _called() -> GameplayAbilitySpec:
	return AbilityFactory.give(asc, Probe.build(ABILITY_TAG))


func _blow(magnitude: float) -> GameplayEventData:
	var event: GameplayEventData = GameplayEventData.new()
	event.event_tag = REACTS_TO
	event.instigator = fixture.owner
	event.target = fixture.owner
	event.magnitude = magnitude
	return event
#endregion


#region What arrives with the activation
## The whole event reaches the ability that reacted to it.
##
## G09. Every field is asserted, not only that something arrived: what was lost
## before was specifically the four the effect context does not carry, and an
## assertion that only checked the tag would pass on a payload with the
## magnitude stripped out.
func test_the_event_that_woke_an_ability_reaches_it_whole() -> void:
	var spec: GameplayAbilitySpec = _listening()

	asc.send_gameplay_event(_blow(37.5))

	var event: GameplayEventData = spec.per_actor_instance.get_activation_event()
	assert_not_null(event, "the ability was handed the event")
	assert_eq(event.event_tag, REACTS_TO, "the tag that fired it")
	assert_almost_eq(event.magnitude, 37.5, 0.0001, "how much of it there was")
	assert_eq(event.instigator, fixture.owner, "who caused it")
	assert_eq(event.target, fixture.owner, "and who it was aimed at")


## An ability activated by a call was not activated by an event, and says so.
##
## The half that keeps the answer honest: returning whatever event happened most
## recently would satisfy every assertion above and be a lie here.
func test_an_ability_activated_by_a_call_reports_no_event() -> void:
	var spec: GameplayAbilitySpec = _called()

	asc.ability_runtime.try_activate(spec.handle)

	assert_null(
		spec.per_actor_instance.get_activation_event(),
		"nothing woke it; it was asked"
	)


## An event raised while an ability is not listening does not reach it.
func test_an_event_nothing_listens_for_reaches_nobody() -> void:
	var spec: GameplayAbilitySpec = _called()
	asc.ability_runtime.try_activate(spec.handle)

	var other: GameplayEventData = _blow(99.0)
	other.event_tag = &"Event.SomethingElse"
	asc.send_gameplay_event(other)

	assert_null(
		spec.per_actor_instance.get_activation_event(),
		"an event it never listened for is not its activation"
	)


## Activating from an event directly carries it just as far.
##
## The runtime's own door, without the event runtime in between: an ability
## woken by a script that already has the event should know as much as one woken
## by the dispatcher.
func test_activating_from_an_event_by_hand_carries_it_too() -> void:
	var spec: GameplayAbilitySpec = _called()

	var result: GameplayAbilityActivationResult = asc.ability_runtime.try_activate_from_event(
		spec.handle, _blow(12.0)
	)

	assert_eq(
		result.status, GameplayAbilityActivationResult.Status.SUCCESS, "it activated"
	)
	assert_almost_eq(
		spec.per_actor_instance.get_activation_event().magnitude,
		12.0,
		0.0001,
		"carrying what it was activated for"
	)
#endregion


#region What the context is made of
## An activation context built from an event carries both halves.
func test_a_context_from_an_event_carries_the_event_and_its_effect_context() -> void:
	var event: GameplayEventData = _blow(5.0)
	event.context = GameplayEffectContext.new(fixture.owner)

	var activation: GameplayAbilityActivationContext = (
		GameplayAbilityActivationContext.from_gameplay_event(event)
	)

	assert_eq(activation.gameplay_event, event, "the event")
	assert_eq(activation.effect_context, event.context, "and the context it carried")


## One built from an effect context carries no event, because there was none.
func test_a_context_from_a_call_carries_no_event() -> void:
	var context: GameplayEffectContext = GameplayEffectContext.new(fixture.owner)

	var activation: GameplayAbilityActivationContext = (
		GameplayAbilityActivationContext.from_effect_context(context)
	)

	assert_eq(activation.effect_context, context, "the context it was given")
	assert_null(activation.gameplay_event, "and nothing it was not")
#endregion
