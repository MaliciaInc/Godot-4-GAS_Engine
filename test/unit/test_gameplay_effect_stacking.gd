## Advanced stacking: identity, growth limits, overflow, factor_in_stack_count,
## and the three expiration policies.
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Factory = preload("res://test/fixtures/test_effect_factory.gd")

const ATTACK: StringName = &"attack"
const TOLERANCE: float = 0.0001

var source: ASCFixture = null
var source_b: ASCFixture = null
var target: ASCFixture = null


## Fixed, ignoring stack_count - proves the engine never auto-multiplies.
class FixedDeltaExecution extends GameplayExecutionCalculation:
	func execute(_spec: GameplayEffectSpec, _target_asc: AbilitySystemComponent) -> Dictionary[StringName, float]:
		return {&"attack": 5.0}


## Reads spec.stack_count itself and scales explicitly - proves it can.
class StackAwareExecution extends GameplayExecutionCalculation:
	func execute(spec: GameplayEffectSpec, _target_asc: AbilitySystemComponent) -> Dictionary[StringName, float]:
		return {&"attack": 5.0 * float(spec.stack_count)}


func before_each() -> void:
	source = Fixture.create("Source")
	source_b = Fixture.create("SourceB")
	target = Fixture.create("Target")
	add_child_autofree(source.owner)
	add_child_autofree(source_b.owner)
	add_child_autofree(target.owner)


func after_each() -> void:
	source = null
	source_b = null
	target = null


#region Stack identity
func test_stacking_type_none_creates_independent_active_effects() -> void:
	var effect: GameplayEffect = Factory.infinite([])
	Factory.apply(target.asc, effect)
	Factory.apply(target.asc, effect)
	assert_eq(target.asc.get_active_effects().size(), 2, "NONE never joins")


func test_aggregate_by_target_joins_regardless_of_source() -> void:
	var effect: GameplayEffect = Factory.stacked(
		Factory.infinite([]), GameplayEffect.StackingType.AGGREGATE_BY_TARGET
	)
	var first: ActiveGameplayEffect = Factory.apply(target.asc, effect, source.owner)
	var second: ActiveGameplayEffect = Factory.apply(target.asc, effect, source_b.owner)
	assert_eq(target.asc.get_active_effects().size(), 1)
	assert_same(first, second, "same logical instance")
	assert_eq(second.stack_count, 2)


func test_aggregate_by_source_joins_only_the_same_source() -> void:
	var effect: GameplayEffect = Factory.stacked(
		Factory.infinite([]), GameplayEffect.StackingType.AGGREGATE_BY_SOURCE
	)
	var first: ActiveGameplayEffect = Factory.apply(target.asc, effect, source.owner)
	var second: ActiveGameplayEffect = Factory.apply(target.asc, effect, source.owner)
	assert_same(first, second)
	assert_eq(second.stack_count, 2)


func test_aggregate_by_source_keeps_two_sources_as_two_stacks() -> void:
	var effect: GameplayEffect = Factory.stacked(
		Factory.infinite([]), GameplayEffect.StackingType.AGGREGATE_BY_SOURCE
	)
	Factory.apply(target.asc, effect, source.owner)
	Factory.apply(target.asc, effect, source_b.owner)
	assert_eq(target.asc.get_active_effects().size(), 2, "different sources never join")
#endregion


#region Limits and overflow
func test_an_unlimited_stack_keeps_growing() -> void:
	var effect: GameplayEffect = Factory.stacked(Factory.infinite([]), GameplayEffect.StackingType.AGGREGATE_BY_TARGET, 0)
	var active: ActiveGameplayEffect = null
	for _i: int in 5:
		active = Factory.apply(target.asc, effect)
	assert_eq(active.stack_count, 5)


func test_a_limited_stack_stops_growing_at_its_limit() -> void:
	var effect: GameplayEffect = Factory.stacked(Factory.infinite([]), GameplayEffect.StackingType.AGGREGATE_BY_TARGET, 2)
	Factory.apply(target.asc, effect)
	Factory.apply(target.asc, effect)
	var active: ActiveGameplayEffect = Factory.apply(target.asc, effect)
	assert_eq(active.stack_count, 2, "the third never grew past the limit")


func test_stack_changed_reports_the_exact_old_and_new_count() -> void:
	var effect: GameplayEffect = Factory.stacked(Factory.infinite([]), GameplayEffect.StackingType.AGGREGATE_BY_TARGET, 0)
	var active: ActiveGameplayEffect = Factory.apply(target.asc, effect)

	watch_signals(target.asc)
	Factory.apply(target.asc, effect)
	assert_signal_emit_count(target.asc, "active_effect_stack_changed", 1)
	var call: Array = get_signal_parameters(target.asc, "active_effect_stack_changed", 0)
	var handle: GameplayEffectHandle = call[0]
	var old_count: int = call[1]
	var new_count: int = call[2]
	assert_eq(handle, active.handle)
	assert_eq(old_count, 1)
	assert_eq(new_count, 2)


func test_deny_overflow_application_refuses_past_the_limit() -> void:
	var effect: GameplayEffect = Factory.with_overflow_effects(
		Factory.stacked(Factory.infinite([]), GameplayEffect.StackingType.AGGREGATE_BY_TARGET, 1), [], true
	)
	Factory.apply(target.asc, effect)
	var result: GameplayEffectApplicationResult = Factory.apply_result(target.asc, effect)
	assert_eq(result.status, GameplayEffectApplicationResult.Status.STACK_OVERFLOW_DENIED)
	assert_eq(target.asc.get_active_effects()[0].stack_count, 1, "the existing stack is untouched")


func test_overflow_fires_the_configured_overflow_effects() -> void:
	var burst: GameplayEffect = Factory.infinite([Factory.add(ATTACK, 3.0)])
	var effect: GameplayEffect = Factory.with_overflow_effects(
		Factory.stacked(Factory.infinite([]), GameplayEffect.StackingType.AGGREGATE_BY_TARGET, 1), [burst]
	)
	var base: float = target.current_of(ATTACK)
	Factory.apply(target.asc, effect)
	watch_signals(target.asc)
	Factory.apply(target.asc, effect)

	assert_signal_emitted(target.asc, "active_effect_stack_overflowed")
	assert_almost_eq(target.current_of(ATTACK), base + 3.0, TOLERANCE, "the overflow effect actually applied")


func test_clear_stack_on_overflow_removes_the_whole_stack() -> void:
	var effect: GameplayEffect = Factory.with_overflow_effects(
		Factory.stacked(Factory.infinite([]), GameplayEffect.StackingType.AGGREGATE_BY_TARGET, 1), [], false, true
	)
	Factory.apply(target.asc, effect)
	Factory.apply(target.asc, effect)
	assert_eq(target.asc.get_active_effects().size(), 0, "cleared after the overflow decision")
#endregion


#region factor_in_stack_count
func test_persistent_contribution_is_not_scaled_when_factor_is_false() -> void:
	var effect: GameplayEffect = Factory.stacked(
		Factory.infinite([Factory.add(ATTACK, 5.0)]), GameplayEffect.StackingType.AGGREGATE_BY_TARGET, 0, false
	)
	var base: float = target.current_of(ATTACK)
	Factory.apply(target.asc, effect)
	Factory.apply(target.asc, effect)
	assert_almost_eq(target.current_of(ATTACK), base + 5.0, TOLERANCE, "one logical stack's magnitude, count ignored")


func test_persistent_contribution_is_scaled_when_factor_is_true() -> void:
	var effect: GameplayEffect = Factory.stacked(
		Factory.infinite([Factory.add(ATTACK, 5.0)]), GameplayEffect.StackingType.AGGREGATE_BY_TARGET, 0, true
	)
	var base: float = target.current_of(ATTACK)
	Factory.apply(target.asc, effect)
	Factory.apply(target.asc, effect)
	Factory.apply(target.asc, effect)
	assert_almost_eq(target.current_of(ATTACK), base + 15.0, TOLERANCE, "5.0 * 3 stacks, recomposed, not summed")


func test_periodic_standard_modifier_is_not_scaled_when_factor_is_false() -> void:
	var effect: GameplayEffect = Factory.stacked(
		Factory.infinite_periodic([Factory.add(ATTACK, 2.0)], 1.0), GameplayEffect.StackingType.AGGREGATE_BY_TARGET, 0, false
	)
	var base: float = target.current_of(ATTACK)
	Factory.apply(target.asc, effect)
	Factory.apply(target.asc, effect)
	target.asc.scheduler.advance_time(1.0)
	assert_almost_eq(target.current_of(ATTACK), base + 2.0, TOLERANCE)


func test_periodic_standard_modifier_is_scaled_when_factor_is_true() -> void:
	var effect: GameplayEffect = Factory.stacked(
		Factory.infinite_periodic([Factory.add(ATTACK, 2.0)], 1.0), GameplayEffect.StackingType.AGGREGATE_BY_TARGET, 0, true
	)
	var base: float = target.current_of(ATTACK)
	Factory.apply(target.asc, effect)
	Factory.apply(target.asc, effect)
	target.asc.scheduler.advance_time(1.0)
	assert_almost_eq(target.current_of(ATTACK), base + 4.0, TOLERANCE, "2.0 * 2 stacks, one tick")


func test_execution_calculation_is_never_auto_multiplied_by_stack_count() -> void:
	var effect: GameplayEffect = Factory.stacked(
		Factory.infinite([]), GameplayEffect.StackingType.AGGREGATE_BY_TARGET, 0, true
	)
	effect.executions = [FixedDeltaExecution.new()] as Array[GameplayExecutionCalculation]

	var base: float = target.current_of(ATTACK)
	Factory.apply(target.asc, effect)
	assert_almost_eq(target.current_of(ATTACK), base + 5.0, TOLERANCE, "first: +5")
	Factory.apply(target.asc, effect)
	assert_almost_eq(target.current_of(ATTACK), base + 10.0, TOLERANCE, "second: +5 again, not +10")


func test_execution_calculation_can_read_stack_count_explicitly() -> void:
	var effect: GameplayEffect = Factory.stacked(Factory.infinite([]), GameplayEffect.StackingType.AGGREGATE_BY_TARGET)
	effect.executions = [StackAwareExecution.new()] as Array[GameplayExecutionCalculation]

	var base: float = target.current_of(ATTACK)
	Factory.apply(target.asc, effect)
	Factory.apply(target.asc, effect)
	assert_almost_eq(target.current_of(ATTACK), base + 15.0, TOLERANCE, "5*1 then 5*2, both real writes")


func test_modifier_recomposes_from_the_authored_magnitude_going_up_and_down() -> void:
	var effect: GameplayEffect = Factory.with_stack_expiration_policy(
		Factory.stacked(
			Factory.duration([Factory.add(ATTACK, 5.0)], 10.0), GameplayEffect.StackingType.AGGREGATE_BY_TARGET, 0, true
		),
		GameplayEffect.StackExpirationPolicy.REMOVE_SINGLE_STACK_AND_REFRESH_DURATION
	)
	var base: float = target.current_of(ATTACK)
	var active: ActiveGameplayEffect = Factory.apply(target.asc, effect)
	Factory.apply(target.asc, effect)
	Factory.apply(target.asc, effect)
	assert_almost_eq(target.current_of(ATTACK), base + 15.0, TOLERANCE, "3 stacks")

	target.asc.effects.expire(active)
	assert_eq(active.stack_count, 2)
	assert_almost_eq(target.current_of(ATTACK), base + 10.0, TOLERANCE, "recomposed to 2 stacks, not 15-5=10 by luck")
#endregion


#region Duration/period refresh policies
class DurationPolicyCase:
	var label: String
	var policy: GameplayEffect.StackDurationRefreshPolicy
	var expected_remaining: float


func _duration_policy_cases() -> Array[DurationPolicyCase]:
	var never: DurationPolicyCase = DurationPolicyCase.new()
	never.label = "NEVER"
	never.policy = GameplayEffect.StackDurationRefreshPolicy.NEVER
	never.expected_remaining = 6.0

	var on_success: DurationPolicyCase = DurationPolicyCase.new()
	on_success.label = "ON_SUCCESSFUL_APPLICATION"
	on_success.policy = GameplayEffect.StackDurationRefreshPolicy.ON_SUCCESSFUL_APPLICATION
	on_success.expected_remaining = 10.0

	return [never, on_success] as Array[DurationPolicyCase]


func test_stack_duration_refresh_policy_governs_whether_reapplication_restarts_the_clock(
	case: DurationPolicyCase = use_parameters(_duration_policy_cases())
) -> void:
	var effect: GameplayEffect = Factory.with_stack_clock_policies(
		Factory.stacked(Factory.duration([], 10.0), GameplayEffect.StackingType.AGGREGATE_BY_TARGET, 0), case.policy
	)
	var active: ActiveGameplayEffect = Factory.apply(target.asc, effect)
	target.asc.scheduler.advance_time(4.0)
	Factory.apply(target.asc, effect)
	assert_almost_eq(active.time_remaining, case.expected_remaining, TOLERANCE, case.label)


class PeriodPolicyCase:
	var label: String
	var policy: GameplayEffect.StackPeriodResetPolicy
	var expected_delta: float


func _period_policy_cases() -> Array[PeriodPolicyCase]:
	var never: PeriodPolicyCase = PeriodPolicyCase.new()
	never.label = "NEVER"
	never.policy = GameplayEffect.StackPeriodResetPolicy.NEVER
	never.expected_delta = 1.0

	var on_success: PeriodPolicyCase = PeriodPolicyCase.new()
	on_success.label = "ON_SUCCESSFUL_APPLICATION"
	on_success.policy = GameplayEffect.StackPeriodResetPolicy.ON_SUCCESSFUL_APPLICATION
	on_success.expected_delta = 0.0

	return [never, on_success] as Array[PeriodPolicyCase]


func test_stack_period_reset_policy_governs_whether_reapplication_restarts_the_clock(
	case: PeriodPolicyCase = use_parameters(_period_policy_cases())
) -> void:
	var effect: GameplayEffect = Factory.with_stack_clock_policies(
		Factory.stacked(
			Factory.infinite_periodic([Factory.add(ATTACK, 1.0)], 1.0), GameplayEffect.StackingType.AGGREGATE_BY_TARGET, 0
		),
		GameplayEffect.StackDurationRefreshPolicy.NEVER, case.policy
	)
	var base: float = target.current_of(ATTACK)
	Factory.apply(target.asc, effect)
	target.asc.scheduler.advance_time(0.7)
	Factory.apply(target.asc, effect)
	target.asc.scheduler.advance_time(0.3)
	assert_almost_eq(target.current_of(ATTACK), base + case.expected_delta, TOLERANCE, case.label)
#endregion


#region Expiration policies
class ExpirationCase:
	var label: String
	var policy: GameplayEffect.StackExpirationPolicy
	var survives: bool
	var expected_count: int


func _expiration_cases() -> Array[ExpirationCase]:
	var clear_all: ExpirationCase = ExpirationCase.new()
	clear_all.label = "CLEAR_ENTIRE_STACK"
	clear_all.policy = GameplayEffect.StackExpirationPolicy.CLEAR_ENTIRE_STACK
	clear_all.survives = false

	var remove_one: ExpirationCase = ExpirationCase.new()
	remove_one.label = "REMOVE_SINGLE_STACK_AND_REFRESH_DURATION"
	remove_one.policy = GameplayEffect.StackExpirationPolicy.REMOVE_SINGLE_STACK_AND_REFRESH_DURATION
	remove_one.survives = true
	remove_one.expected_count = 2

	var keep_all: ExpirationCase = ExpirationCase.new()
	keep_all.label = "REFRESH_DURATION"
	keep_all.policy = GameplayEffect.StackExpirationPolicy.REFRESH_DURATION
	keep_all.survives = true
	keep_all.expected_count = 3

	return [clear_all, remove_one, keep_all] as Array[ExpirationCase]


func test_the_three_expiration_policies_govern_what_survives(
	case: ExpirationCase = use_parameters(_expiration_cases())
) -> void:
	var effect: GameplayEffect = Factory.with_stack_expiration_policy(
		Factory.stacked(Factory.duration([], 5.0), GameplayEffect.StackingType.AGGREGATE_BY_TARGET, 0), case.policy
	)
	var active: ActiveGameplayEffect = Factory.apply(target.asc, effect)
	Factory.apply(target.asc, effect)
	Factory.apply(target.asc, effect)
	assert_eq(active.stack_count, 3, case.label)

	target.asc.effects.expire(active)
	if not case.survives:
		assert_eq(target.asc.get_active_effects().size(), 0, case.label)
	else:
		assert_eq(target.asc.get_active_effects().size(), 1, case.label)
		assert_eq(active.stack_count, case.expected_count, case.label)
		assert_almost_eq(active.time_remaining, 5.0, TOLERANCE, case.label + ": duration restarted")


func test_turn_based_expiration_uses_remaining_turns_not_seconds(
	case: ExpirationCase = use_parameters(_expiration_cases())
) -> void:
	var effect: GameplayEffect = Factory.with_stack_expiration_policy(
		Factory.stacked(Factory.turn_based([], 3), GameplayEffect.StackingType.AGGREGATE_BY_TARGET, 0), case.policy
	)
	var active: ActiveGameplayEffect = Factory.apply(target.asc, effect)
	Factory.apply(target.asc, effect)
	Factory.apply(target.asc, effect)

	target.asc.effects.expire(active)
	if not case.survives:
		assert_eq(target.asc.get_active_effects().size(), 0, case.label)
	else:
		assert_eq(active.stack_count, case.expected_count, case.label)
		assert_eq(active.spec.remaining_turns, 3, case.label + ": turns restarted, not converted from seconds")
#endregion


#region Inhibition interaction
func test_growing_a_stack_while_inhibited_updates_the_receipt_without_attaching() -> void:
	target.asc.add_tag(&"Status.Blessed")
	var effect: GameplayEffect = Factory.with_ongoing_requirement(
		Factory.stacked(
			Factory.infinite([Factory.add(ATTACK, 5.0)]), GameplayEffect.StackingType.AGGREGATE_BY_TARGET, 0, true
		),
		[&"Status.Blessed"]
	)
	var active: ActiveGameplayEffect = Factory.apply(target.asc, effect)
	target.asc.remove_tag(&"Status.Blessed")
	assert_true(active.inhibited)
	var base: float = target.current_of(ATTACK)

	Factory.apply(target.asc, effect)
	assert_eq(active.stack_count, 2)
	assert_almost_eq(target.current_of(ATTACK), base, TOLERANCE, "still detached")

	target.asc.add_tag(&"Status.Blessed")
	assert_almost_eq(target.current_of(ATTACK), base + 10.0, TOLERANCE, "attaches with the full grown stack")
#endregion


#region Removal, queries, cleanup
func test_removing_a_stack_drops_its_tag_refcount_exactly_once() -> void:
	var effect: GameplayEffect = Factory.granting(
		Factory.stacked(Factory.infinite([]), GameplayEffect.StackingType.AGGREGATE_BY_TARGET, 0), [&"Status.Stacked"]
	)
	var active: ActiveGameplayEffect = Factory.apply(target.asc, effect)
	Factory.apply(target.asc, effect)
	Factory.apply(target.asc, effect)
	assert_eq(active.stack_count, 3)
	assert_true(target.asc.has_tag(&"Status.Stacked"))

	target.asc.effects.remove(active)
	assert_false(target.asc.has_tag(&"Status.Stacked"), "clean removal, no residual refcount")


func test_stack_count_is_readable_through_the_active_effect() -> void:
	var effect: GameplayEffect = Factory.stacked(Factory.infinite([]), GameplayEffect.StackingType.AGGREGATE_BY_TARGET, 0)
	var active: ActiveGameplayEffect = Factory.apply(target.asc, effect)
	Factory.apply(target.asc, effect)

	var resolved: ActiveGameplayEffect = target.asc.get_active_effect(active.handle)
	assert_eq(resolved.stack_count, 2)


func test_cleanup_removes_a_grown_stack_cleanly() -> void:
	var effect: GameplayEffect = Factory.granting(
		Factory.stacked(Factory.infinite([Factory.add(ATTACK, 5.0)]), GameplayEffect.StackingType.AGGREGATE_BY_TARGET, 0, true),
		[&"Status.Stacked"]
	)
	var base: float = target.current_of(ATTACK)
	Factory.apply(target.asc, effect)
	Factory.apply(target.asc, effect)

	target.asc.cleanup()
	assert_eq(target.asc.get_active_effects().size(), 0)
	assert_almost_eq(target.current_of(ATTACK), base, TOLERANCE)
	assert_false(target.asc.has_tag(&"Status.Stacked"))


func test_no_drift_after_a_long_stack_and_unstack_sequence() -> void:
	var effect: GameplayEffect = Factory.stacked(
		Factory.infinite([Factory.add(ATTACK, 1.0)]), GameplayEffect.StackingType.AGGREGATE_BY_TARGET, 0, true
	)
	var base: float = target.current_of(ATTACK)
	var active: ActiveGameplayEffect = null
	for _i: int in 20:
		active = Factory.apply(target.asc, effect)
	assert_eq(active.stack_count, 20)
	assert_almost_eq(target.current_of(ATTACK), base + 20.0, TOLERANCE)

	target.asc.effects.remove(active)
	assert_almost_eq(target.current_of(ATTACK), base, TOLERANCE, "exactly back to base, no float drift")
#endregion
