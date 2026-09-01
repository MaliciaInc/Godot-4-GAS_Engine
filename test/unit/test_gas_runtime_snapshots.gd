## The runtime debugger's read layer: snapshot DTOs, the effect refusal log,
## and GameplayAbilitySpec.last_activation_result. All of it is a reader over
## public runtime state - these tests exist to prove the reader never drifts
## from what the runtime actually holds, not to test the runtime itself
## again.
##
## @meta_license: MIT
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Factory = preload("res://test/fixtures/test_effect_factory.gd")
const AbilityFactory = preload("res://test/fixtures/test_ability_factory.gd")
const TaskProbe = preload("res://test/fixtures/task_probe_ability.gd")
const ProbeAbilityScript = preload("res://test/fixtures/probe_ability.gd")

const TOLERANCE: float = 0.0001
const ATTACK: StringName = TestAttributeSet.ATTACK
const HEALTH: StringName = TestAttributeSet.HEALTH

var fixture: ASCFixture = null
var asc: AbilitySystemComponent = null


func before_each() -> void:
	fixture = Fixture.create("Snapshotted")
	add_child_autofree(fixture.owner)
	asc = fixture.asc


func after_each() -> void:
	fixture = null
	asc = null


func expect_engine_error() -> void:
	GutUtils.get_error_tracker().treat_push_error_as = GutUtils.TREAT_AS.NOTHING


func restore_error_reporting() -> void:
	GutUtils.get_error_tracker().treat_push_error_as = GutUtils.TREAT_AS.FAILURE


#region Attribute snapshot
func test_attribute_snapshot_reports_base_current_and_a_joined_contribution() -> void:
	var effect: GameplayEffect = Factory.stacked(
		Factory.infinite([Factory.add(ATTACK, 5.0)]), GameplayEffect.StackingType.AGGREGATE_BY_TARGET, 0, true
	)
	var active: ActiveGameplayEffect = Factory.apply(asc, effect)
	Factory.apply(asc, effect)

	var snapshots: Array[GasAttributeSnapshot] = GasAttributeSnapshot.capture_all(asc)
	var attack: GasAttributeSnapshot = null
	for snapshot: GasAttributeSnapshot in snapshots:
		if snapshot.attribute_name == ATTACK:
			attack = snapshot
	assert_not_null(attack)
	assert_almost_eq(attack.current_value, asc.get_attribute_current(ATTACK), TOLERANCE)
	assert_eq(attack.contributions.size(), 1)

	var contribution: GasAttributeSnapshot.Contribution = attack.contributions[0]
	assert_eq(contribution.effect_handle, active.handle)
	assert_eq(contribution.effect_definition, effect)
	assert_eq(contribution.operation, GameplayEffectModifier.Operation.ADD)
	assert_eq(contribution.stack_factor, 2, "factor_in_stack_count true, stack grew to 2")


func test_inhibited_contributions_never_appear_attached() -> void:
	asc.add_tag(&"Buff.Active")
	var effect: GameplayEffect = Factory.with_ongoing_requirement(
		Factory.infinite([Factory.add(ATTACK, 5.0)]), [&"Buff.Active"]
	)
	Factory.apply(asc, effect)
	asc.remove_tag(&"Buff.Active")

	var snapshots: Array[GasAttributeSnapshot] = GasAttributeSnapshot.capture_all(asc)
	for snapshot: GasAttributeSnapshot in snapshots:
		if snapshot.attribute_name == ATTACK:
			assert_true(snapshot.contributions.is_empty(), "inhibited, so detached, so absent")
#endregion


#region Tag snapshot
func test_tag_snapshot_reports_count_and_granting_effect() -> void:
	var effect: GameplayEffect = Factory.granting(Factory.infinite([]), [&"Status.Marked"])
	var active: ActiveGameplayEffect = Factory.apply(asc, effect)

	var snapshots: Array[GasTagSnapshot] = GasTagSnapshot.capture_all(asc)
	var marked: GasTagSnapshot = null
	for snapshot: GasTagSnapshot in snapshots:
		if snapshot.tag == &"Status.Marked":
			marked = snapshot
	assert_not_null(marked)
	assert_eq(marked.count, 1)
	assert_eq(marked.granting_effect_handles, [active.handle] as Array[GameplayEffectHandle])
	assert_false(marked.is_activation_owned)


## An inhibited effect is not granting anything, and the debugger exists to say
## where a tag came from. Attribution read `granted_tags`, which stays populated
## while inhibited because it is the receipt uninhibiting puts back - so a tag
## held once by one effect was reported as granted by two, one of which was not
## granting it at all. The count and the list contradicted each other on screen.
func test_an_inhibited_effect_is_not_named_as_granting_a_tag() -> void:
	var live: ActiveGameplayEffect = Factory.apply(
		asc, Factory.granting(Factory.infinite([]), [&"Status.Marked"])
	)
	asc.add_tag(&"Status.Blessed")
	Factory.apply(asc, Factory.with_ongoing_requirement(
		Factory.granting(Factory.infinite([]), [&"Status.Marked"]), [&"Status.Blessed"]
	))
	asc.remove_tag(&"Status.Blessed")

	var marked: GasTagSnapshot = _snapshot_of(&"Status.Marked")
	assert_not_null(marked, "the tag is still held by the uninhibited effect")
	if marked == null:
		return
	assert_eq(marked.count, 1, "one effect is actually granting it")
	assert_eq(
		marked.granting_effect_handles, [live.handle] as Array[GameplayEffectHandle],
		"and that is the one named"
	)


## The tag with this name, or null when nothing holds it.
func _snapshot_of(tag: StringName) -> GasTagSnapshot:
	for snapshot: GasTagSnapshot in GasTagSnapshot.capture_all(asc):
		if snapshot.tag == tag:
			return snapshot
	return null
#endregion


#region Effect snapshot
func test_effect_snapshot_maps_active_effect_fields() -> void:
	var effect: GameplayEffect = Factory.granting(
		Factory.duration([Factory.add(ATTACK, 4.0)], 12.0), [&"Status.Buffed"]
	)
	var active: ActiveGameplayEffect = Factory.apply(asc, effect, fixture.owner)

	var snapshots: Array[GasEffectSnapshot] = GasEffectSnapshot.capture_all(asc)
	assert_eq(snapshots.size(), 1)
	var snapshot: GasEffectSnapshot = snapshots[0]
	assert_eq(snapshot.handle, active.handle)
	assert_eq(snapshot.definition, effect)
	assert_eq(snapshot.source, fixture.owner)
	assert_almost_eq(snapshot.duration, 12.0, TOLERANCE)
	assert_false(snapshot.inhibited)
	assert_eq(snapshot.stack_count, 1)
	assert_true(snapshot.granted_tags.has(&"Status.Buffed"))
	assert_eq(snapshot.modifiers.size(), 1)
#endregion


#region Ability snapshot
func test_ability_snapshot_reports_effective_tags_and_cooldown() -> void:
	var probe: ProbeAbility = ProbeAbilityScript.new()
	probe.ability_tags = [&"Ability.Probe"]
	probe.cooldown_effect = Factory.duration([], 5.0)
	var spec: GameplayAbilitySpec = AbilityFactory.give(asc, probe)

	var snapshots: Array[GasAbilitySnapshot] = GasAbilitySnapshot.capture_all(asc)
	assert_eq(snapshots.size(), 1)
	var snapshot: GasAbilitySnapshot = snapshots[0]
	assert_eq(snapshot.handle, spec.handle)
	assert_true(snapshot.effective_tags.has(&"Ability.Probe"))
	assert_false(snapshot.cooldown.active, "never committed, so no cooldown yet")
	assert_null(snapshot.last_activation_result, "never attempted yet")


func test_ability_snapshot_retains_the_last_activation_result() -> void:
	var probe: ProbeAbility = ProbeAbilityScript.new()
	probe.ability_tags = [&"Ability.Probe"]
	var spec: GameplayAbilitySpec = AbilityFactory.give(asc, probe)
	# channels is not @export, so it never survives AbilityFactory.give()'s
	# pack/instantiate - set on the granted instance itself, same rule
	# TestAbilityFactory's own doc comment states.
	(spec.per_actor_instance as ProbeAbility).channels = true

	asc.ability_runtime.try_activate(spec.handle)
	var second: GameplayAbilityActivationResult = asc.ability_runtime.try_activate(spec.handle)
	assert_eq(second.status, GameplayAbilityActivationResult.Status.ALREADY_ACTIVE)

	var snapshots: Array[GasAbilitySnapshot] = GasAbilitySnapshot.capture_all(asc)
	assert_eq(snapshots[0].last_activation_result.status, GameplayAbilityActivationResult.Status.ALREADY_ACTIVE)
#endregion


#region Task snapshot
func test_task_snapshot_reports_a_running_task() -> void:
	var probe: TaskProbe = TaskProbe.build(&"Ability.Task")
	var spec: GameplayAbilitySpec = AbilityFactory.give(asc, probe)
	var instance: TaskProbe = spec.per_actor_instance as TaskProbe
	var task: TaskProbe.ProbeTask = instance.register_loose_task()

	var snapshots: Array[GasTaskSnapshot] = GasTaskSnapshot.capture_all(asc)
	assert_eq(snapshots.size(), 1)
	assert_eq(snapshots[0].ability_handle, instance.get_ability_handle())
	assert_eq(snapshots[0].state, GameplayAbilityTask.State.RUNNING)
	var same_script: bool = snapshots[0].task_type == task.get_script()
	assert_true(same_script, "the task's own script")
#endregion


#region Refusal log
func test_refusal_log_records_a_component_rejection_and_an_evaluation_failure() -> void:
	expect_engine_error()
	fixture.set_base(ATTACK, 10.0)

	# COMPONENT_REJECTED - an application tag requirement never satisfied.
	var blocked: GameplayEffect = Factory.requiring(Factory.instant([Factory.add(ATTACK, 1.0)]), [&"Never.Held"])
	Factory.apply_result(asc, blocked)

	# EVALUATION_FAILED, DIVISION_BY_ZERO underneath.
	Factory.apply_result(asc, Factory.instant([Factory.divide(ATTACK, 0.0)]))

	var recent: Array[GameplayEffectRefusalRecord] = asc.effects.refusal_log.recent()
	assert_eq(recent.size(), 2)
	assert_eq(recent[0].result.status, GameplayEffectApplicationResult.Status.COMPONENT_REJECTED)
	assert_eq(recent[1].result.status, GameplayEffectApplicationResult.Status.EVALUATION_FAILED)
	assert_eq(recent[1].result.evaluation_status, AttributeEvaluationResult.Status.DIVISION_BY_ZERO)
	assert_eq(recent[1].order, recent[0].order + 1, "monotonic even across different refusal kinds")
	restore_error_reporting()


func test_refusal_log_is_a_bounded_ring_buffer() -> void:
	expect_engine_error()
	var over_capacity: int = GameplayEffectRefusalLog.DEFAULT_CAPACITY + 5
	for _i: int in over_capacity:
		Factory.apply_result(asc, Factory.instant([Factory.divide(ATTACK, 0.0)]))

	var recent: Array[GameplayEffectRefusalRecord] = asc.effects.refusal_log.recent()
	assert_eq(recent.size(), GameplayEffectRefusalLog.DEFAULT_CAPACITY)
	assert_eq(recent[0].order, 5, "the oldest 5 aged out")
	restore_error_reporting()


func test_refusal_log_disabled_records_nothing() -> void:
	expect_engine_error()
	asc.effects.refusal_log.enabled = false
	Factory.apply_result(asc, Factory.instant([Factory.divide(ATTACK, 0.0)]))
	assert_true(asc.effects.refusal_log.recent().is_empty())
	restore_error_reporting()


func test_refusal_log_shrinks_immediately_when_capacity_is_reduced() -> void:
	var log: GameplayEffectRefusalLog = GameplayEffectRefusalLog.new()
	for index: int in 5:
		var result: GameplayEffectApplicationResult = GameplayEffectApplicationResult.new()
		result.status = GameplayEffectApplicationResult.Status.COMPONENT_REJECTED
		log.record(result)
	assert_eq(log.recent().size(), 5)

	log.capacity = 2
	assert_eq(log.recent().size(), 2)
	assert_eq(log.recent()[0].order, 3)
	assert_eq(log.recent()[1].order, 4)


func test_refusal_log_capacity_zero_retains_nothing() -> void:
	var log: GameplayEffectRefusalLog = GameplayEffectRefusalLog.new()
	log.capacity = 0
	var result: GameplayEffectApplicationResult = GameplayEffectApplicationResult.new()
	result.status = GameplayEffectApplicationResult.Status.COMPONENT_REJECTED
	log.record(result)
	assert_true(log.recent().is_empty())
#endregion


#region Runtime snapshot
func test_runtime_snapshot_aggregates_every_domain() -> void:
	Factory.apply(asc, Factory.granting(Factory.infinite([Factory.add(ATTACK, 1.0)]), [&"Status.Marked"]))

	var snapshot: GasRuntimeSnapshot = GasRuntimeSnapshot.capture(asc)
	assert_eq(snapshot.asc, asc)
	assert_false(snapshot.attributes.is_empty())
	assert_false(snapshot.tags.is_empty())
	assert_eq(snapshot.effects.size(), 1)


func test_runtime_snapshot_of_null_asc_never_crashes() -> void:
	var snapshot: GasRuntimeSnapshot = GasRuntimeSnapshot.capture(null)
	assert_null(snapshot.asc)
	assert_true(snapshot.attributes.is_empty())
#endregion
