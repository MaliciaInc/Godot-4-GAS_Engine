## Instancing policies: PER_ACTOR reuses one instance for as long as it is
## granted; PER_EXECUTION makes a fresh one per activation, so several casts
## of the same ability can run at once without sharing state.
##
## @meta_license: MIT
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Probe = preload("res://test/fixtures/probe_ability.gd")
const AbilityFactory = preload("res://test/fixtures/test_ability_factory.gd")

const PROBE_TAG: StringName = &"Ability.Probe"
const EVENT_TAG: StringName = &"Event.Cast"
const SLOT: int = 4

var fixture: ASCFixture = null
var asc: AbilitySystemComponent = null


func before_each() -> void:
	fixture = Fixture.create("Subject")
	add_child_autofree(fixture.owner)
	asc = fixture.asc


func after_each() -> void:
	fixture = null
	asc = null


#region Builders
## A fresh, non-channelling probe, configured before the grant so exports the
## grant freezes reach the definition the spec actually reads.
func _granted(configure: Callable) -> GameplayAbilitySpec:
	var probe: ProbeAbility = Probe.build(PROBE_TAG)
	if configure.is_valid():
		configure.call(probe)
	return AbilityFactory.give(asc, probe)


## A ChannelingAbility grant, for anything that needs an activation to stay
## open while the test inspects it. `ProbeAbility.channels` cannot do this for
## PER_EXECUTION: it is not `@export`ed, so it never survives the pack-then-
## instantiate round trip a fresh execution goes through, and every execution
## would come back with the class default, `false` - already ended by the
## time the test could look at it.
func _grant_channeling(
	policy: GameplayAbility.InstancingPolicy, input_id: int = -1
) -> GameplayAbilitySpec:
	var probe: ChannelingAbility = ChannelingAbility.new()
	probe.ability_tags = [PROBE_TAG]
	probe.instancing_policy = policy
	return AbilityFactory.give(asc, probe, 1.0, input_id)


## Start one more execution directly through the runtime, bypassing input and
## events - the policy under test, not the routing that reaches it.
func _start_execution(spec: GameplayAbilitySpec) -> ChannelingAbility:
	var instance: ChannelingAbility = (
		asc.ability_runtime.instancing.instance_for_activation(spec) as ChannelingAbility
	)
	instance.try_activate()
	return instance
#endregion


#region PER_ACTOR: unchanged by this task
func test_per_actor_reuses_the_one_instance_across_activations() -> void:
	var spec: GameplayAbilitySpec = _granted(Callable())
	var instance: ProbeAbility = spec.per_actor_instance as ProbeAbility

	# Not channelling, so each try_activate() ends itself before returning -
	# the second call below is a genuine second activation, not a refusal.
	instance.try_activate()
	instance.try_activate()

	assert_eq(spec.per_actor_instance, instance, "still the same Node")
	assert_eq(instance.activations, 2, "both activations ran on it")


func test_per_actor_refuses_a_second_activation_while_the_first_runs() -> void:
	var spec: GameplayAbilitySpec = _grant_channeling(GameplayAbility.InstancingPolicy.PER_ACTOR)
	var instance: ChannelingAbility = spec.per_actor_instance as ChannelingAbility

	instance.try_activate()

	assert_eq(
		asc.ability_runtime.activation_error(spec),
		AbilityRuntime.ActivationError.ALREADY_ACTIVE,
		"per actor's one instance is busy"
	)
	assert_eq(spec.active_count, 1, "one activation, not two")
	instance.channel_gate.emit()
#endregion


#region PER_EXECUTION: a fresh instance every time
func test_per_execution_grants_no_persistent_instance() -> void:
	var spec: GameplayAbilitySpec = _grant_channeling(GameplayAbility.InstancingPolicy.PER_EXECUTION)
	assert_null(spec.per_actor_instance, "nothing to reuse - there is no template Node left alive")
	assert_eq(spec.active_count, 0, "granting is not activating")


func test_per_execution_gives_each_activation_a_distinct_node_id() -> void:
	var spec: GameplayAbilitySpec = _grant_channeling(GameplayAbility.InstancingPolicy.PER_EXECUTION)
	var first: ChannelingAbility = _start_execution(spec)
	var second: ChannelingAbility = _start_execution(spec)

	assert_ne(first.get_instance_id(), second.get_instance_id(), "two separate Nodes")
	assert_eq(spec.active_instances.size(), 2)
	assert_eq(spec.active_count, 2, "both are running at once")

	first.channel_gate.emit()
	second.channel_gate.emit()


func test_simultaneous_executions_share_no_fields_tasks_or_context() -> void:
	var spec: GameplayAbilitySpec = _grant_channeling(GameplayAbility.InstancingPolicy.PER_EXECUTION)
	var context_a: GameplayEffectContext = GameplayEffectContext.new(fixture.owner)
	var context_b: GameplayEffectContext = GameplayEffectContext.new(fixture.owner)

	var a: ChannelingAbility = (
		asc.ability_runtime.instancing.instance_for_activation(spec) as ChannelingAbility
	)
	a.try_activate(context_a)
	var b: ChannelingAbility = (
		asc.ability_runtime.instancing.instance_for_activation(spec) as ChannelingAbility
	)
	b.try_activate(context_b)

	a.presses_while_active += 1

	assert_eq(a.presses_while_active, 1)
	assert_eq(b.presses_while_active, 0, "b's own field, untouched by a's")
	assert_ne(a.current_context, b.current_context, "each kept the context it was given")
	assert_eq(a.current_context, context_a)
	assert_eq(b.current_context, context_b)

	a.channel_gate.emit()
	b.channel_gate.emit()


func test_ending_one_execution_leaves_its_sibling_running() -> void:
	var spec: GameplayAbilitySpec = _grant_channeling(GameplayAbility.InstancingPolicy.PER_EXECUTION)
	var a: ChannelingAbility = _start_execution(spec)
	var b: ChannelingAbility = _start_execution(spec)

	a.end_ability()

	assert_false(a.is_active)
	assert_true(b.is_active, "terminating a did not touch b")
	assert_eq(spec.active_count, 1)
	assert_eq(spec.active_instances, [b] as Array[GameplayAbility])

	b.channel_gate.emit()


func test_removing_the_spec_cancels_every_execution() -> void:
	var spec: GameplayAbilitySpec = _grant_channeling(GameplayAbility.InstancingPolicy.PER_EXECUTION)
	var handle: GameplayAbilityHandle = spec.handle
	var a: ChannelingAbility = _start_execution(spec)
	var b: ChannelingAbility = _start_execution(spec)

	var removed: bool = asc.ability_runtime.remove_ability(handle)

	assert_true(removed)
	assert_false(a.is_active, "aborted along with the spec")
	assert_false(b.is_active)
	assert_eq(spec.active_instances.size(), 0)
	assert_null(asc.ability_runtime.get_spec(handle))


func test_cleanup_cancels_every_execution_across_every_spec() -> void:
	var spec: GameplayAbilitySpec = _grant_channeling(GameplayAbility.InstancingPolicy.PER_EXECUTION)
	_start_execution(spec)
	_start_execution(spec)
	assert_eq(spec.active_count, 2)

	asc.cleanup()

	assert_eq(spec.active_instances.size(), 0)
	assert_eq(asc.ability_runtime.specs().size(), 0, "cleanup drops the grant too")
#endregion


#region Input: a snapshot, not a live list
func test_a_press_starts_one_more_execution_alongside_those_already_running() -> void:
	var spec: GameplayAbilitySpec = _grant_channeling(GameplayAbility.InstancingPolicy.PER_EXECUTION, SLOT)
	var already_running: ChannelingAbility = _start_execution(spec)

	asc.ability_local_input_pressed(SLOT)

	assert_eq(spec.active_instances.size(), 2, "the press added one more, not replaced the first")
	assert_true(already_running.is_active, "the press did not disturb it")

	for instance: GameplayAbility in spec.active_instances.duplicate():
		(instance as ChannelingAbility).channel_gate.emit()


## Two executions of the same PER_EXECUTION spec are both live and both bound
## to the same slot. A press must reach both - snapshotted first, so the
## first one ending itself as a direct result of the transition it just
## received cannot make the loop skip its neighbour.
func test_a_press_reaches_every_running_execution_even_when_the_first_ends_itself() -> void:
	var template: SelfEndingAbility = SelfEndingAbility.new()
	template.ability_tags = [PROBE_TAG]
	template.instancing_policy = GameplayAbility.InstancingPolicy.PER_EXECUTION
	var spec: GameplayAbilitySpec = AbilityFactory.give(asc, template, 1.0, SLOT)

	var a: SelfEndingAbility = asc.ability_runtime.instancing.instance_for_activation(spec) as SelfEndingAbility
	a.try_activate()
	var b: SelfEndingAbility = asc.ability_runtime.instancing.instance_for_activation(spec) as SelfEndingAbility
	b.try_activate()

	asc.ability_local_input_pressed(SLOT)

	assert_eq(a.active_input_presses, 1, "the one that ended itself still heard the press")
	assert_eq(b.active_input_presses, 1, "its neighbour was not skipped")
#endregion


#region Events: PER_EXECUTION needs no per-actor template
func _event(tag: StringName) -> GameplayEventData:
	var event: GameplayEventData = GameplayEventData.new()
	event.event_tag = tag
	event.instigator = fixture.owner
	event.target = fixture.owner
	return event


func test_an_event_activates_a_per_execution_listener_with_no_per_actor_template() -> void:
	var probe: ChannelingAbility = ChannelingAbility.new()
	probe.ability_tags = [PROBE_TAG]
	probe.instancing_policy = GameplayAbility.InstancingPolicy.PER_EXECUTION
	probe.activation_policy = GameplayAbility.ActivationPolicy.ON_GAMEPLAY_EVENT
	probe.gameplay_event_triggers = [GameplayAbilityEventTrigger.for_tag(EVENT_TAG)]
	var spec: GameplayAbilitySpec = AbilityFactory.give(asc, probe)
	assert_null(spec.per_actor_instance, "nothing was ever kept as a template")

	asc.send_gameplay_event(_event(EVENT_TAG))

	assert_eq(spec.active_instances.size(), 1, "the event started exactly one execution")
	# Guarded rather than indexed unconditionally: an assertion failing above
	# does not stop this function, and an empty array here must fail loudly
	# through GUT, not crash the run through an unguarded index.
	if spec.active_instances.size() > 0:
		var instance: ChannelingAbility = spec.active_instances[0] as ChannelingAbility
		assert_eq(instance.activations, 1)
		instance.channel_gate.emit()
#endregion
