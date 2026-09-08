## Task 16's activation policies: MANUAL stays passive to grant, ON_GRANTED
## tries once, ON_GAMEPLAY_EVENT can declare several triggers, and PASSIVE is
## continuously reevaluated - starting, cancelling and restarting as its
## requirements change, converging even when its own activation is what
## changed them.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const AbilityFactory = preload("res://test/fixtures/test_ability_factory.gd")
const EffectFactory = preload("res://test/fixtures/test_effect_factory.gd")
const Fixture = preload("res://test/fixtures/asc_fixture.gd")

const REQUIRED: StringName = &"Status.Ready"
const BLOCKED: StringName = &"Status.Silenced"
const BUFF: StringName = &"Status.Buffed"
const EVENT_A: StringName = &"Event.A"
const EVENT_B: StringName = &"Event.B"

var target: ASCFixture = null


func before_each() -> void:
	target = Fixture.create("Target")
	add_child_autofree(target.owner)


func after_each() -> void:
	target = null


func _query(tags: Array[StringName]) -> GameplayTagQuery:
	var expression: GameplayTagQueryExpression = GameplayTagQueryExpression.new()
	expression.operator = GameplayTagQueryExpression.Operator.ANY
	expression.tags = tags
	var q: GameplayTagQuery = GameplayTagQuery.new()
	q.root = expression
	return q


func _probe(spec: GameplayAbilitySpec) -> ProbeAbility:
	return spec.per_actor_instance as ProbeAbility


#region MANUAL
func test_manual_does_not_auto_activate_on_grant() -> void:
	var probe: ProbeAbility = ProbeAbility.build(&"Ability.Manual")
	var spec: GameplayAbilitySpec = AbilityFactory.give(target.asc, probe)
	assert_eq(_probe(spec).activations, 0, "MANUAL waits for input or an explicit call")
#endregion


#region ON_GRANTED
func test_on_granted_activates_exactly_once() -> void:
	var probe: ProbeAbility = ProbeAbility.build(&"Ability.OnGranted")
	probe.activation_policy = GameplayAbility.ActivationPolicy.ON_GRANTED
	var spec: GameplayAbilitySpec = AbilityFactory.give(target.asc, probe)
	assert_eq(_probe(spec).activations, 1)


func test_on_granted_failure_leaves_it_granted_and_idle() -> void:
	var probe: ProbeAbility = ProbeAbility.build(&"Ability.OnGrantedBlocked")
	probe.activation_policy = GameplayAbility.ActivationPolicy.ON_GRANTED
	probe.activation_blocked_query = _query([BLOCKED])
	target.asc.add_tag(BLOCKED)

	var spec: GameplayAbilitySpec = AbilityFactory.give(target.asc, probe)
	assert_eq(_probe(spec).activations, 0, "blocked at grant time, never ran")
	assert_not_null(target.asc.ability_runtime.get_spec(spec.handle), "still granted")

	target.asc.remove_tag(BLOCKED)
	assert_eq(_probe(spec).activations, 0, "ON_GRANTED never auto-retries")
#endregion


#region ON_GAMEPLAY_EVENT
func test_an_ability_can_declare_multiple_event_triggers() -> void:
	var probe: RecordingAbility = RecordingAbility.new()
	probe.activation_policy = GameplayAbility.ActivationPolicy.ON_GAMEPLAY_EVENT
	probe.gameplay_event_triggers = [
		GameplayAbilityEventTrigger.for_tag(EVENT_A), GameplayAbilityEventTrigger.for_tag(EVENT_B)
	]
	var spec: GameplayAbilitySpec = AbilityFactory.give(target.asc, probe)
	var listener: RecordingAbility = spec.per_actor_instance as RecordingAbility

	target.asc.send_gameplay_event(_event(EVENT_A))
	assert_eq(listener.activations, 1, "the first trigger woke it")
	target.asc.send_gameplay_event(_event(EVENT_B))
	assert_eq(listener.activations, 2, "the second trigger woke it too")


func _event(tag: StringName) -> GameplayEventData:
	var event: GameplayEventData = GameplayEventData.new()
	event.event_tag = tag
	event.instigator = target.owner
	event.target = target.owner
	return event
#endregion


#region PASSIVE
func test_passive_activates_immediately_when_requirements_already_hold() -> void:
	var probe: ProbeAbility = ProbeAbility.build(&"Ability.PassiveImmediate")
	probe.activation_policy = GameplayAbility.ActivationPolicy.PASSIVE
	var spec: GameplayAbilitySpec = AbilityFactory.give(target.asc, probe)
	assert_eq(_probe(spec).activations, 1, "PASSIVE tries at grant time, same as ON_GRANTED")


func test_passive_waits_for_its_required_tag() -> void:
	var probe: ProbeAbility = ProbeAbility.build(&"Ability.PassiveWaits")
	probe.activation_policy = GameplayAbility.ActivationPolicy.PASSIVE
	probe.activation_required_query = _query([REQUIRED])
	var spec: GameplayAbilitySpec = AbilityFactory.give(target.asc, probe)
	assert_eq(_probe(spec).activations, 0, "not satisfied at grant time")

	target.asc.add_tag(REQUIRED)
	assert_eq(_probe(spec).activations, 1, "the tag change woke it")


func test_passive_cancels_when_a_blocking_condition_appears() -> void:
	var probe: ChannelingAbility = ChannelingAbility.new()
	probe.ability_tags = [&"Ability.PassiveBlocked"]
	probe.activation_policy = GameplayAbility.ActivationPolicy.PASSIVE
	probe.activation_blocked_query = _query([BLOCKED])
	var spec: GameplayAbilitySpec = AbilityFactory.give(target.asc, probe)
	assert_true(spec.per_actor_instance.is_active, "nothing blocked it yet")

	target.asc.add_tag(BLOCKED)
	assert_false(spec.per_actor_instance.is_active, "the blocked condition cancelled it")


func test_passive_restarts_once_conditions_are_satisfied_again() -> void:
	var probe: ProbeAbility = ProbeAbility.build(&"Ability.PassiveRestarts")
	probe.activation_policy = GameplayAbility.ActivationPolicy.PASSIVE
	probe.activation_required_query = _query([REQUIRED])
	var spec: GameplayAbilitySpec = AbilityFactory.give(target.asc, probe)
	assert_eq(_probe(spec).activations, 0)

	target.asc.add_tag(REQUIRED)
	assert_eq(_probe(spec).activations, 1)

	target.asc.remove_tag(REQUIRED)
	target.asc.add_tag(REQUIRED)
	assert_eq(_probe(spec).activations, 2, "idle again, then restarted")


## A passive's own activation grants activation_owned_tags, which is exactly
## what a second passive's block query watches - reevaluation reenters itself
## synchronously and must still converge to the correct end state in one call.
func test_passive_reevaluation_is_reentrancy_stable() -> void:
	var blocked_probe: ChannelingAbility = ChannelingAbility.new()
	blocked_probe.ability_tags = [&"Ability.PassiveReentrantBlocked"]
	blocked_probe.activation_policy = GameplayAbility.ActivationPolicy.PASSIVE
	blocked_probe.activation_blocked_query = _query([BUFF])
	var blocked_spec: GameplayAbilitySpec = AbilityFactory.give(target.asc, blocked_probe)
	assert_true(blocked_spec.per_actor_instance.is_active, "nothing buffed yet")

	var buffing_probe: ChannelingAbility = ChannelingAbility.new()
	buffing_probe.ability_tags = [&"Ability.PassiveReentrantBuffs"]
	buffing_probe.activation_policy = GameplayAbility.ActivationPolicy.PASSIVE
	buffing_probe.activation_owned_tags = [BUFF]
	var buffing_spec: GameplayAbilitySpec = AbilityFactory.give(target.asc, buffing_probe)

	assert_true(buffing_spec.per_actor_instance.is_active, "granting it activated it")
	assert_true(target.asc.has_tag(BUFF), "its activation-owned tag is up")
	assert_false(blocked_spec.per_actor_instance.is_active, "the other passive reacted and cancelled")


func test_passive_per_execution_is_refused_as_invalid_definition() -> void:
	var probe: ProbeAbility = ProbeAbility.build(&"Ability.PassivePerExecution")
	probe.activation_policy = GameplayAbility.ActivationPolicy.PASSIVE
	probe.instancing_policy = GameplayAbility.InstancingPolicy.PER_EXECUTION

	var scene: PackedScene = PackedScene.new()
	scene.pack(probe)
	probe.free()
	var handle: GameplayAbilityHandle = target.asc.give_ability(scene)
	assert_false(handle.is_valid(), "PASSIVE + PER_EXECUTION has no stable semantics")


func test_cleanup_stops_a_running_passive_without_restarting_it() -> void:
	var probe: ChannelingAbility = ChannelingAbility.new()
	probe.ability_tags = [&"Ability.PassiveCleanup"]
	probe.activation_policy = GameplayAbility.ActivationPolicy.PASSIVE
	var spec: GameplayAbilitySpec = AbilityFactory.give(target.asc, probe)
	assert_true(spec.per_actor_instance.is_active)

	target.asc.cleanup()
	assert_false(is_instance_valid(spec.per_actor_instance) and spec.per_actor_instance.is_active)


## The suspension around teardown was a flag, and a flag is not a depth.
##
## `abort_all` raises it, aborts everything, and lowers it. Aborting fires
## `ability_ended`, which is a public signal a game listens to - "the caster
## died, stop everything" is an ordinary handler - and a handler that reaches
## `abort_all` again lowers the flag on its way out while the outer teardown is
## still running. The nested call then asks for a passive reevaluation with
## nothing suspended, and the passive the ASC is in the middle of destroying
## starts itself up again.
func test_a_nested_abort_cannot_restart_a_passive_mid_teardown() -> void:
	# Both are PASSIVE so both come up running at grant time. `try_activate()`
	# on a channelling ability never returns - it awaits an `ability_ended` that
	# is precisely what channelling does not do - so nothing here awaits it.
	var first: ChannelingAbility = ChannelingAbility.new()
	first.ability_tags = [&"Ability.NestedAbortTrigger"]
	first.activation_policy = GameplayAbility.ActivationPolicy.PASSIVE
	var first_spec: GameplayAbilitySpec = AbilityFactory.give(target.asc, first)
	assert_true(first_spec.per_actor_instance.is_active, "the first one is running")

	var passive: ChannelingAbility = ChannelingAbility.new()
	passive.ability_tags = [&"Ability.NestedAbortPassive"]
	passive.activation_policy = GameplayAbility.ActivationPolicy.PASSIVE
	var passive_spec: GameplayAbilitySpec = AbilityFactory.give(target.asc, passive)
	assert_true(passive_spec.per_actor_instance.is_active, "the passive is running before teardown")

	# A game's own reaction to something ending: tear the rest down too.
	var nested: Array[bool] = [false]
	target.asc.ability_runtime_ended.connect(
		func(
			_handle: GameplayAbilityHandle,
			_instance: GameplayAbility,
			_was_cancelled: bool,
			_reason: GameplayAbilityTask.CancelReason
		) -> void:
			if nested[0]:
				return
			nested[0] = true
			target.asc.ability_runtime.abort_all()
	)

	target.asc.cleanup()

	assert_true(nested[0], "the nested teardown really happened")
	assert_false(
		is_instance_valid(passive_spec.per_actor_instance)
			and passive_spec.per_actor_instance.is_active,
		"the passive stayed down through the whole teardown"
	)
#endregion


#region Effects granting passives
func test_an_effect_granted_passive_activates_and_removal_retires_it() -> void:
	var probe: ProbeAbility = ProbeAbility.build(&"Ability.EffectGrantedPassive")
	probe.activation_policy = GameplayAbility.ActivationPolicy.PASSIVE
	var scene: PackedScene = EffectFactory.ability_scene(probe)
	var effect: GameplayEffect = EffectFactory.granting_ability(EffectFactory.infinite([]), scene)

	var active: ActiveGameplayEffect = EffectFactory.apply(target.asc, effect)
	assert_eq(active.granted_ability_handles.size(), 1)
	var spec: GameplayAbilitySpec = target.asc.ability_runtime.get_spec(active.granted_ability_handles[0])
	assert_eq(_probe(spec).activations, 1, "the passive tried itself at grant time")

	target.asc.remove_active_effect(active)
	assert_null(
		target.asc.ability_runtime.get_spec(spec.handle),
		"CANCEL_AND_REMOVE_ON_EFFECT_END retired it with the effect"
	)
#endregion
#region Triggers that answer a tag
## A trigger of `source` over `tag`, ready to hang on an ON_GAMEPLAY_EVENT
## ability. `for_tag` builds the event kind; the two tag kinds differ from it
## only in which question they ask of the same query.
func _tag_trigger(
	source: GameplayAbilityEventTrigger.Source, tag: StringName
) -> GameplayAbilityEventTrigger:
	var trigger: GameplayAbilityEventTrigger = GameplayAbilityEventTrigger.for_tag(tag)
	trigger.source = source
	return trigger


func _triggered_by(
	source: GameplayAbilityEventTrigger.Source, tag: StringName
) -> GameplayAbilitySpec:
	var probe: ProbeAbility = ProbeAbility.build(&"Ability.Triggered")
	probe.activation_policy = GameplayAbility.ActivationPolicy.ON_GAMEPLAY_EVENT
	probe.gameplay_event_triggers = [_tag_trigger(source, tag)]
	return AbilityFactory.give(target.asc, probe)


## An edge, not a level: the tag has to arrive.
func test_owned_tag_added_fires_only_on_the_acquisition_edge() -> void:
	target.asc.add_tag(BUFF)
	var spec: GameplayAbilitySpec = _triggered_by(
		GameplayAbilityEventTrigger.Source.OWNED_TAG_ADDED, BUFF
	)

	assert_eq(_probe(spec).activations, 0, "a tag that was already there is not an arrival")

	target.asc.remove_tag(BUFF)
	target.asc.add_tag(BUFF)
	assert_eq(_probe(spec).activations, 1, "and arriving is")


## Losing the tag again is the whole difference between the two sources: an
## edge started something and has no further opinion, a level was the condition
## the ability ran under. Asserted side by side, because separately they are the
## same test with one word changed.
func test_losing_the_tag_cancels_a_level_trigger_and_not_an_edge_one() -> void:
	var edge: GameplayAbilitySpec = _triggered_by(
		GameplayAbilityEventTrigger.Source.OWNED_TAG_ADDED, BUFF
	)
	var level: GameplayAbilitySpec = _triggered_by(
		GameplayAbilityEventTrigger.Source.OWNED_TAG_PRESENT, BUFF
	)
	_probe(edge).channels = true
	_probe(level).channels = true

	target.asc.add_tag(BUFF)
	assert_true(_probe(edge).is_active, "the arrival started the edge one")
	assert_true(_probe(level).is_active, "and the condition started the level one")

	target.asc.remove_tag(BUFF)
	assert_true(_probe(edge).is_active, "losing it left the edge one running")
	assert_false(_probe(level).is_active, "and took the level one with it")

	_probe(edge).channel_gate.emit()


## A level, and the level it was granted into counts.
func test_owned_tag_present_fires_when_the_tag_is_already_present_at_grant() -> void:
	target.asc.add_tag(BUFF)
	var spec: GameplayAbilitySpec = _triggered_by(
		GameplayAbilityEventTrigger.Source.OWNED_TAG_PRESENT, BUFF
	)

	assert_eq(_probe(spec).activations, 1, "already burning at the moment it was granted")


## An ability whose own activation grants the tag that triggers it is a loop
## somebody writes by accident. It stops counting rather than recursing.
func test_trigger_reentrancy_stops_at_the_policy_pass_limit() -> void:
	var probe: ProbeAbility = ProbeAbility.build(&"Ability.Looping")
	probe.activation_policy = GameplayAbility.ActivationPolicy.ON_GAMEPLAY_EVENT
	probe.gameplay_event_triggers = [
		_tag_trigger(GameplayAbilityEventTrigger.Source.OWNED_TAG_ADDED, BUFF)
	]
	probe.retrigger_while_active = true
	var spec: GameplayAbilitySpec = AbilityFactory.give(target.asc, probe)

	# The loop: every activation drops the tag and takes it again, so the trigger
	# it just answered is waiting for it on the way out.
	var looping: ProbeAbility = _probe(spec)
	looping.ability_ended.connect(
		func(_cancelled: bool) -> void:
			target.asc.remove_tag(BUFF)
			target.asc.add_tag(BUFF)
	)

	target.asc.add_tag(BUFF)

	# It converged or it was stopped; either way the engine is still answering.
	assert_gt(looping.activations, 0, "it ran")
	assert_true(target.asc.tags.has_exact(BUFF), "and the component is still coherent")
#endregion
