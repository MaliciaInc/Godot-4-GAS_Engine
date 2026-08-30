## Base mutation, clamps, cleanup, refresh and stacking.
##
## These are the consumers that could each skip the aggregator if they wrote
## `current_value` themselves. Every one of them goes through the safe API here,
## and the tests say what happens when they do.
##
## @meta_license: MIT
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Factory = preload("res://test/fixtures/test_effect_factory.gd")

const TOLERANCE: float = 0.0001
const HEALTH: StringName = &"health"
const MAX_HEALTH: StringName = &"max_health"
const ATTACK: StringName = &"attack"
const MANA: StringName = &"mana"
const BUFFED: StringName = &"Status.Buffed"

var fixture: ASCFixture = null
var asc: AbilitySystemComponent = null


func before_each() -> void:
	fixture = Fixture.create("Subject")
	add_child_autofree(fixture.owner)
	asc = fixture.asc


func after_each() -> void:
	fixture = null
	asc = null


#region Damage underflow and heal
func test_overkill_floors_the_base_instead_of_going_negative() -> void:
	# 500 damage against 100 health. With only an effective clamp the base would
	# sit at -400 while the display read 0, and the character would need 430
	# healing to move at all.
	asc.apply_attribute_base_delta(HEALTH, -500.0)
	assert_almost_eq(fixture.base_of(HEALTH), 0.0, TOLERANCE, "base floors at zero")
	assert_almost_eq(fixture.current_of(HEALTH), 0.0, TOLERANCE, "current follows")


func test_healing_after_overkill_starts_from_zero() -> void:
	asc.apply_attribute_base_delta(HEALTH, -500.0)
	asc.apply_attribute_base_delta(HEALTH, 30.0)
	assert_almost_eq(fixture.base_of(HEALTH), 30.0, TOLERANCE, "30, not -370")
	assert_almost_eq(fixture.current_of(HEALTH), 30.0, TOLERANCE)


func test_a_clamped_mutation_reports_requested_against_committed() -> void:
	var result: AttributeMutationResult = asc.apply_attribute_base_delta(HEALTH, -500.0)
	assert_true(result.was_clamped, "the clamp intervened")
	assert_almost_eq(result.requested_base_value, -400.0, TOLERANCE, "what was asked for")
	assert_almost_eq(result.new_base_value, 0.0, TOLERANCE, "what was allowed")


func test_healing_above_the_maximum_is_clamped_in_base() -> void:
	var result: AttributeMutationResult = asc.apply_attribute_base_delta(HEALTH, 500.0)
	assert_almost_eq(result.requested_base_value, 600.0, TOLERANCE)
	assert_almost_eq(fixture.base_of(HEALTH), 100.0, TOLERANCE, "capped at max_health")
	assert_true(result.was_clamped)
#endregion


#region Base changes under a buff
func test_a_base_change_preserves_an_active_contribution() -> void:
	fixture.set_base(ATTACK, 10.0)
	var buff: ActiveGameplayEffect = Factory.apply(asc, Factory.infinite([Factory.multiply(ATTACK, 2.0)]))
	assert_almost_eq(fixture.current_of(ATTACK), 20.0, TOLERANCE)

	asc.set_attribute_base(ATTACK, 15.0)
	assert_almost_eq(fixture.current_of(ATTACK), 30.0, TOLERANCE, "levelling up keeps the buff")

	asc.remove_active_effect(buff)
	assert_almost_eq(fixture.current_of(ATTACK), 15.0, TOLERANCE)


func test_initialising_overrides_replaces_the_base_and_keeps_buffs() -> void:
	fixture.set_base(ATTACK, 10.0)
	Factory.apply(asc, Factory.infinite([Factory.multiply(ATTACK, 2.0)]))

	var overrides: Dictionary[StringName, float] = {ATTACK: 50.0}
	asc.initialize_attribute_overrides(overrides)

	# 100, not 80 and not 50. Initialisation replaces the base; it is not an
	# OVERRIDE modifier competing with the buff, and it is not an effect reset.
	assert_almost_eq(fixture.current_of(ATTACK), 100.0, TOLERANCE, "50 * 2")
	assert_almost_eq(fixture.base_of(ATTACK), 50.0, TOLERANCE)
#endregion


#region Max-health dependency
func test_a_max_health_buff_raises_the_ceiling() -> void:
	Factory.apply(asc, Factory.infinite([Factory.add(MAX_HEALTH, 50.0)]))
	assert_almost_eq(fixture.current_of(MAX_HEALTH), 150.0, TOLERANCE)

	asc.apply_attribute_base_delta(HEALTH, 40.0)
	assert_almost_eq(fixture.base_of(HEALTH), 140.0, TOLERANCE, "the new ceiling allows it")


func test_losing_the_buff_discards_the_excess_permanently() -> void:
	var buff: ActiveGameplayEffect = Factory.apply(asc, Factory.infinite([Factory.add(MAX_HEALTH, 50.0)]))
	asc.apply_attribute_base_delta(HEALTH, 40.0)

	asc.remove_active_effect(buff)
	assert_almost_eq(fixture.current_of(MAX_HEALTH), 100.0, TOLERANCE)
	assert_almost_eq(fixture.base_of(HEALTH), 100.0, TOLERANCE, "trimmed in base, not only on screen")

	# Reapplying does not resurrect the 40 that was lost. Health that was only
	# ever borrowed does not become durable.
	Factory.apply(asc, Factory.infinite([Factory.add(MAX_HEALTH, 50.0)]))
	assert_almost_eq(fixture.base_of(HEALTH), 100.0, TOLERANCE, "still 100, not 140")
#endregion


#region Cleanup
func test_cleanup_reverts_to_base_and_drops_everything() -> void:
	fixture.set_base(ATTACK, 10.0)
	Factory.apply(
		asc, Factory.granting(Factory.infinite([Factory.add(ATTACK, 5.0)]), [BUFFED] as Array[StringName])
	)
	assert_almost_eq(fixture.current_of(ATTACK), 15.0, TOLERANCE)

	asc.cleanup()
	assert_eq(asc.get_active_effects().size(), 0, "no active effects")
	assert_almost_eq(fixture.current_of(ATTACK), 10.0, TOLERANCE, "back to base")
	assert_false(asc.has_tag_exact(BUFFED), "granted tags released")


func test_cleanup_is_idempotent() -> void:
	fixture.set_base(ATTACK, 10.0)
	Factory.apply(asc, Factory.infinite([Factory.add(ATTACK, 5.0)]))
	asc.cleanup()

	watch_signals(asc)
	asc.cleanup()
	# A second cleanup on an already-clean component announces nothing. A UI
	# listening for removals must not be told twice about the same effect.
	assert_signal_not_emitted(asc, "active_effect_removed", "nothing left to remove")
	assert_signal_not_emitted(asc, "attribute_changed", "nothing left to change")
	assert_almost_eq(fixture.current_of(ATTACK), 10.0, TOLERANCE)


func test_cleanup_announces_each_effect_exactly_once() -> void:
	Factory.apply(asc, Factory.infinite([Factory.add(ATTACK, 1.0)]))
	Factory.apply(asc, Factory.infinite([Factory.add(ATTACK, 2.0)]))

	watch_signals(asc)
	asc.cleanup()
	assert_signal_emit_count(asc, "active_effect_removed", 2, "one per effect, not per recomposition")
#endregion


#region Refresh
func test_refreshing_replaces_the_snapshot_and_keeps_one_instance() -> void:
	fixture.set_base(ATTACK, 10.0)
	var effect: GameplayEffect = Factory.refreshing(
		Factory.granting(Factory.duration([Factory.add(ATTACK, 10.0)], 5.0), [BUFFED] as Array[StringName])
	)

	var first: ActiveGameplayEffect = Factory.apply(asc, effect)
	assert_almost_eq(fixture.current_of(ATTACK), 20.0, TOLERANCE)

	# Reapply with a mutated magnitude standing in for a higher level.
	var stronger: GameplayEffectSpec = GameplayEffectSpec.new(
		effect, GameplayEffectContext.new(fixture.owner), 5.0
	)
	stronger.set_magnitude(0, 50.0)
	var second: ActiveGameplayEffect = asc.apply_effect_spec(stronger)

	assert_eq(second, first, "the same logical instance")
	assert_eq(asc.get_active_effects().size(), 1, "not two stacks")
	assert_almost_eq(fixture.current_of(ATTACK), 60.0, TOLERANCE, "the new magnitude replaced the old")
	assert_eq(asc.tags.count(BUFFED), 1, "the tag refcount stays at one")


func test_a_refresh_emits_neither_a_removal_nor_an_addition() -> void:
	var effect: GameplayEffect = Factory.refreshing(
		Factory.duration([Factory.add(ATTACK, 10.0)], 5.0)
	)
	Factory.apply(asc, effect)

	watch_signals(asc)
	Factory.apply(asc, effect)
	# A remove/add pair would make a UI tear down and rebuild an icon that never
	# went away.
	assert_signal_not_emitted(asc, "active_effect_removed")
	assert_signal_not_emitted(asc, "active_effect_added")
	assert_signal_emitted(asc, "active_effect_refreshed")


func test_a_refresh_restarts_the_duration() -> void:
	var effect: GameplayEffect = Factory.refreshing(Factory.duration([Factory.add(ATTACK, 1.0)], 5.0))
	var active: ActiveGameplayEffect = Factory.apply(asc, effect)
	active.time_remaining = 0.5

	Factory.apply(asc, effect)
	assert_almost_eq(active.time_remaining, 5.0, TOLERANCE, "the clock went back to full")
#endregion


#region Free stacking
func test_free_stacking_keeps_instances_independent() -> void:
	fixture.set_base(ATTACK, 10.0)
	var effect: GameplayEffect = Factory.duration([Factory.add(ATTACK, 5.0)], 5.0)

	var first: ActiveGameplayEffect = Factory.apply(asc, effect)
	var second: ActiveGameplayEffect = Factory.apply(asc, effect)

	assert_eq(asc.get_active_effects().size(), 2, "two independent stacks")
	assert_ne(first.application_order, second.application_order, "each has its own order")
	assert_almost_eq(fixture.current_of(ATTACK), 20.0, TOLERANCE, "10 + 5 + 5")

	asc.remove_active_effect(first)
	assert_almost_eq(fixture.current_of(ATTACK), 15.0, TOLERANCE, "the other survives")
#endregion


#region Cost preview
func test_an_affordable_cost_is_affordable() -> void:
	fixture.set_base(MANA, 10.0)
	assert_true(asc.can_afford_cost(Factory.instant([Factory.add(MANA, -10.0)])), "exactly enough")


func test_a_cost_larger_than_the_base_is_not_affordable() -> void:
	fixture.set_base(MANA, 10.0)
	assert_false(asc.can_afford_cost(Factory.instant([Factory.add(MANA, -11.0)])), "one short")


func test_a_temporary_buff_does_not_subsidise_a_durable_cost() -> void:
	fixture.set_base(MANA, 10.0)
	Factory.apply(asc, Factory.infinite([Factory.add(MANA, 20.0)]))
	assert_almost_eq(fixture.current_of(MANA), 30.0, TOLERANCE, "the buff shows")

	# The displayed 30 is not spendable: paying 20 would drive the base to -10
	# and the clamp would shrink the payment. A cost the clamp had to shrink was
	# not affordable, only survivable.
	assert_false(asc.can_afford_cost(Factory.instant([Factory.add(MANA, -20.0)])), "borrowed mana")


func test_a_preview_mutates_nothing() -> void:
	fixture.set_base(MANA, 10.0)
	watch_signals(asc)
	asc.can_afford_cost(Factory.instant([Factory.add(MANA, -5.0)]))

	assert_almost_eq(fixture.base_of(MANA), 10.0, TOLERANCE, "base untouched")
	assert_almost_eq(fixture.current_of(MANA), 10.0, TOLERANCE, "current untouched")
	assert_eq(asc.get_active_effects().size(), 0, "nothing registered")
	assert_signal_not_emitted(asc, "attribute_changed", "silent")


func test_the_preview_agrees_with_the_commit() -> void:
	fixture.set_base(MANA, 10.0)
	var cost: GameplayEffect = Factory.instant([Factory.add(MANA, -10.0)])
	var predicted: bool = asc.can_afford_cost(cost)

	Factory.apply(asc, cost)
	var actually_paid: bool = is_equal_approx(fixture.base_of(MANA), 0.0)
	assert_eq(predicted, actually_paid, "preview and commit run the same evaluator")
#endregion
