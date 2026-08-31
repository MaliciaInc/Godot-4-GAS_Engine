## Ongoing/removal tag requirements and the inhibited/attached state they
## drive: a failed ongoing query detaches an active effect's contributions
## and tags without removing it, and a satisfied removal query removes it
## outright.
##
## @meta_license: MIT
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Factory = preload("res://test/fixtures/test_effect_factory.gd")

const ATTACK: StringName = &"attack"
const TOLERANCE: float = 0.0001

var target: ASCFixture = null


func before_each() -> void:
	target = Fixture.create("Target")
	add_child_autofree(target.owner)


func after_each() -> void:
	target = null


#region Starting state
func test_an_effect_with_no_ongoing_query_starts_uninhibited() -> void:
	var active: ActiveGameplayEffect = Factory.apply(target.asc, Factory.infinite([]))
	assert_false(active.inhibited)


func test_an_ongoing_query_already_unsatisfied_at_application_starts_inhibited() -> void:
	var effect: GameplayEffect = Factory.with_ongoing_requirement(
		Factory.granting(Factory.infinite([Factory.add(ATTACK, 5.0)]), [&"Status.Buffed"]), [&"Status.Blessed"]
	)
	var active: ActiveGameplayEffect = Factory.apply(target.asc, effect)

	assert_not_null(active, "still registers as an active effect")
	assert_true(active.inhibited)
	assert_almost_eq(target.current_of(ATTACK), 10.0, TOLERANCE, "base only, not attached, no contribution")
	assert_false(target.asc.has_tag(&"Status.Buffed"), "not attached, tag not granted")
	assert_eq(target.asc.get_active_effects().size(), 1, "registered regardless")
#endregion


#region Tag-driven transitions
## Losing the required tag inhibits an active effect; regaining it
## uninhibits the same instance again - one continuous cycle, not two
## unrelated facts.
func test_the_required_tag_inhibits_and_uninhibits_across_its_full_cycle() -> void:
	target.asc.add_tag(&"Status.Blessed")
	var effect: GameplayEffect = Factory.with_ongoing_requirement(
		Factory.granting(Factory.infinite([Factory.add(ATTACK, 5.0)]), [&"Status.Buffed"]), [&"Status.Blessed"]
	)
	var active: ActiveGameplayEffect = Factory.apply(target.asc, effect)
	assert_false(active.inhibited, "held the tag at application")

	target.asc.remove_tag(&"Status.Blessed")
	assert_true(active.inhibited, "lost the tag")

	target.asc.add_tag(&"Status.Blessed")
	assert_false(active.inhibited, "regained the tag")
#endregion


#region Signals
func test_inhibit_uninhibit_never_emits_active_effect_added_or_removed() -> void:
	target.asc.add_tag(&"Status.Blessed")
	var effect: GameplayEffect = Factory.with_ongoing_requirement(Factory.infinite([]), [&"Status.Blessed"])
	Factory.apply(target.asc, effect)

	watch_signals(target.asc)
	target.asc.remove_tag(&"Status.Blessed")
	target.asc.add_tag(&"Status.Blessed")

	assert_signal_not_emitted(target.asc, "active_effect_added")
	assert_signal_not_emitted(target.asc, "active_effect_removed")


func test_inhibition_changed_emits_exactly_once_per_real_transition() -> void:
	target.asc.add_tag(&"Status.Blessed")
	var effect: GameplayEffect = Factory.with_ongoing_requirement(Factory.infinite([]), [&"Status.Blessed"])
	var active: ActiveGameplayEffect = Factory.apply(target.asc, effect)

	watch_signals(target.asc)
	target.asc.remove_tag(&"Status.Blessed")
	assert_signal_emit_count(target.asc, "active_effect_inhibition_changed", 1)
	var first_call: Array = get_signal_parameters(target.asc, "active_effect_inhibition_changed", 0)
	var first_handle: GameplayEffectHandle = first_call[0]
	var first_inhibited: bool = first_call[1]
	assert_eq(first_handle, active.handle)
	assert_true(first_inhibited)

	target.asc.add_tag(&"Status.Blessed")
	assert_signal_emit_count(target.asc, "active_effect_inhibition_changed", 2)
	var second_call: Array = get_signal_parameters(target.asc, "active_effect_inhibition_changed", 1)
	var second_inhibited: bool = second_call[1]
	assert_false(second_inhibited)
#endregion


#region Contributions and tags
func test_a_contribution_disappears_while_inhibited_and_reappears() -> void:
	target.asc.add_tag(&"Status.Blessed")
	var effect: GameplayEffect = Factory.with_ongoing_requirement(
		Factory.infinite([Factory.add(ATTACK, 7.0)]), [&"Status.Blessed"]
	)
	Factory.apply(target.asc, effect)
	assert_almost_eq(target.current_of(ATTACK), 17.0, TOLERANCE)

	target.asc.remove_tag(&"Status.Blessed")
	assert_almost_eq(target.current_of(ATTACK), 10.0, TOLERANCE)

	target.asc.add_tag(&"Status.Blessed")
	assert_almost_eq(target.current_of(ATTACK), 17.0, TOLERANCE)


func test_target_granted_tags_disappear_while_inhibited_and_reappear() -> void:
	target.asc.add_tag(&"Status.Blessed")
	var effect: GameplayEffect = Factory.with_ongoing_requirement(
		Factory.granting(Factory.infinite([]), [&"Status.Buffed"]), [&"Status.Blessed"]
	)
	Factory.apply(target.asc, effect)
	assert_true(target.asc.has_tag(&"Status.Buffed"))

	target.asc.remove_tag(&"Status.Blessed")
	assert_false(target.asc.has_tag(&"Status.Buffed"))

	target.asc.add_tag(&"Status.Blessed")
	assert_true(target.asc.has_tag(&"Status.Buffed"))
#endregion


#region Duration
func test_duration_continues_counting_down_while_inhibited() -> void:
	target.asc.add_tag(&"Status.Blessed")
	var effect: GameplayEffect = Factory.with_ongoing_requirement(Factory.duration([], 10.0), [&"Status.Blessed"])
	var active: ActiveGameplayEffect = Factory.apply(target.asc, effect)

	target.asc.remove_tag(&"Status.Blessed")
	assert_true(active.inhibited)
	target.asc.scheduler.advance_time(4.0)
	assert_almost_eq(active.time_remaining, 6.0, TOLERANCE, "duration keeps counting down while inhibited")


func test_an_inhibited_effect_is_removed_normally_when_its_duration_expires() -> void:
	target.asc.add_tag(&"Status.Blessed")
	var effect: GameplayEffect = Factory.with_ongoing_requirement(Factory.duration([], 2.0), [&"Status.Blessed"])
	Factory.apply(target.asc, effect)

	target.asc.remove_tag(&"Status.Blessed")
	watch_signals(target.asc)
	target.asc.scheduler.advance_time(3.0)

	assert_eq(target.asc.get_active_effects().size(), 0)
	assert_signal_emitted(target.asc, "active_effect_removed")
#endregion


#region Removal query
func test_a_removal_query_removes_the_active_effect_when_it_matches() -> void:
	var effect: GameplayEffect = Factory.with_removal_requirement(Factory.infinite([]), [&"Status.Cured"])
	Factory.apply(target.asc, effect)
	assert_eq(target.asc.get_active_effects().size(), 1)

	target.asc.add_tag(&"Status.Cured")
	assert_eq(target.asc.get_active_effects().size(), 0)


func test_a_removal_query_already_matching_refuses_the_initial_application() -> void:
	target.asc.add_tag(&"Status.Cured")
	var effect: GameplayEffect = Factory.with_removal_requirement(Factory.infinite([]), [&"Status.Cured"])
	var result: GameplayEffectApplicationResult = Factory.apply_result(target.asc, effect)

	assert_eq(result.status, GameplayEffectApplicationResult.Status.COMPONENT_REJECTED)
	assert_eq(target.asc.get_active_effects().size(), 0)
#endregion


#region Reentrancy and oscillation
## An effect that grants the exact tag its own ongoing_query excludes would
## oscillate forever without the reentrancy guard: granting the tag inhibits
## it, which drops the tag, which would uninhibit it again, forever. The
## fail-safe stabilizes it inhibited instead of hanging or flip-flopping.
func test_a_self_oscillating_ongoing_query_stabilizes_inhibited_without_hanging() -> void:
	var none_self: GameplayTagQueryExpression = GameplayTagQueryExpression.new()
	none_self.operator = GameplayTagQueryExpression.Operator.NONE
	none_self.tags = [&"Status.SelfLock"]
	var ongoing: GameplayTagQuery = GameplayTagQuery.new()
	ongoing.root = none_self

	var effect: GameplayEffect = Factory.granting(Factory.infinite([]), [&"Status.SelfLock"])
	var requirements: GameplayEffectTargetTagRequirementsComponent = GameplayEffectTargetTagRequirementsComponent.new()
	requirements.ongoing_query = ongoing
	effect.components.append(requirements)

	watch_signals(target.asc)
	var active: ActiveGameplayEffect = Factory.apply(target.asc, effect)

	assert_not_null(active)
	assert_true(active.inhibited, "left inhibited as the fail-safe")
	assert_signal_emitted(target.asc, "effect_requirement_cycle_aborted")
	assert_false(target.asc.has_tag(&"Status.SelfLock"), "detached, so never actually held")
#endregion


#region Periodic policies
class PeriodicPolicyCase:
	var label: String
	var policy: GameplayEffect.PeriodInhibitionPolicy
	var ticks_right_after_uninhibit: int


func _periodic_policy_cases() -> Array[PeriodicPolicyCase]:
	var skip: PeriodicPolicyCase = PeriodicPolicyCase.new()
	skip.label = "SKIP_MISSED_TICKS"
	skip.policy = GameplayEffect.PeriodInhibitionPolicy.SKIP_MISSED_TICKS
	skip.ticks_right_after_uninhibit = 0

	var execute_immediately: PeriodicPolicyCase = PeriodicPolicyCase.new()
	execute_immediately.label = "EXECUTE_IMMEDIATELY_ON_UNINHIBIT"
	execute_immediately.policy = GameplayEffect.PeriodInhibitionPolicy.EXECUTE_IMMEDIATELY_ON_UNINHIBIT
	execute_immediately.ticks_right_after_uninhibit = 1

	var reset: PeriodicPolicyCase = PeriodicPolicyCase.new()
	reset.label = "RESET_PERIOD_ON_UNINHIBIT"
	reset.policy = GameplayEffect.PeriodInhibitionPolicy.RESET_PERIOD_ON_UNINHIBIT
	reset.ticks_right_after_uninhibit = 0

	return [skip, execute_immediately, reset] as Array[PeriodicPolicyCase]


## All three policies skip ticks silently while inhibited - they only differ
## in what happens at the moment of uninhibit, and in when the next tick
## after that lands.
func test_periodic_policies_govern_what_happens_at_uninhibit(
	case: PeriodicPolicyCase = use_parameters(_periodic_policy_cases())
) -> void:
	target.asc.add_tag(&"Status.Blessed")
	var effect: GameplayEffect = Factory.with_ongoing_requirement(
		Factory.infinite_periodic([Factory.add(ATTACK, 1.0)], 1.0), [&"Status.Blessed"]
	)
	effect.period_inhibition_policy = case.policy
	Factory.apply(target.asc, effect)

	var base: float = target.current_of(ATTACK)

	target.asc.scheduler.advance_time(0.5)
	target.asc.remove_tag(&"Status.Blessed")
	target.asc.scheduler.advance_time(5.0)
	assert_almost_eq(target.current_of(ATTACK), base, TOLERANCE, case.label + ": nothing ticked while inhibited")

	target.asc.add_tag(&"Status.Blessed")
	assert_almost_eq(
		target.current_of(ATTACK), base + float(case.ticks_right_after_uninhibit), TOLERANCE, case.label
	)

	target.asc.scheduler.advance_time(1.0)
	assert_almost_eq(
		target.current_of(ATTACK), base + float(case.ticks_right_after_uninhibit) + 1.0, TOLERANCE,
		case.label + ": one more tick a full period later"
	)
#endregion


#region Cleanup and queries
func test_cleanup_removes_an_inhibited_effect_cleanly() -> void:
	target.asc.add_tag(&"Status.Blessed")
	var effect: GameplayEffect = Factory.with_ongoing_requirement(
		Factory.granting(Factory.infinite([Factory.add(ATTACK, 5.0)]), [&"Status.Buffed"]), [&"Status.Blessed"]
	)
	Factory.apply(target.asc, effect)
	target.asc.remove_tag(&"Status.Blessed")
	assert_eq(target.asc.get_active_effects().size(), 1)

	target.asc.cleanup()
	assert_eq(target.asc.get_active_effects().size(), 0)
	assert_almost_eq(target.current_of(ATTACK), 10.0, TOLERANCE, "base only")
	assert_false(target.asc.has_tag(&"Status.Buffed"))


func test_a_query_can_filter_by_inhibition_state() -> void:
	target.asc.add_tag(&"Status.Blessed")
	var inhibitable: GameplayEffect = Factory.with_ongoing_requirement(Factory.infinite([]), [&"Status.Blessed"])
	Factory.apply(target.asc, inhibitable)
	Factory.apply(target.asc, Factory.infinite([]))
	target.asc.remove_tag(&"Status.Blessed")

	var active_only: GameplayEffectQuery = GameplayEffectQuery.new()
	active_only.inhibition = GameplayEffectQuery.InhibitionFilter.ACTIVE_ONLY
	assert_eq(target.asc.count_active_effects(active_only), 1)

	var inhibited_only: GameplayEffectQuery = GameplayEffectQuery.new()
	inhibited_only.inhibition = GameplayEffectQuery.InhibitionFilter.INHIBITED_ONLY
	assert_eq(target.asc.count_active_effects(inhibited_only), 1)
#endregion
