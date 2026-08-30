## Modifier identity: two modifiers that write the same attribute stay distinct.
##
## Upstream keyed runtime magnitudes by attribute name, so an effect with
## `Attack ADD +10` and `Attack MULTIPLY 2` had one slot for both. The second
## overwrote the first and the effect silently did half its job. The key is the
## modifier's index inside `effect_def.modifiers`, stable for the spec's life.
##
## @meta_license: MIT
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Factory = preload("res://test/fixtures/test_effect_factory.gd")

const TOLERANCE: float = 0.0001
const ATTACK: StringName = &"attack"

var fixture: ASCFixture = null


func before_each() -> void:
	fixture = Fixture.create("Modifiers")
	add_child_autofree(fixture.owner)
	fixture.set_base(ATTACK, 10.0)


func after_each() -> void:
	fixture = null
	restore_error_reporting()


## Declare that the engine is expected to report an error in this test.
##
## The engine refuses invalid input loudly, which is right: a caller passing a
## bad modifier index or a negative delta has a bug. GUT counts any push_error
## during a test as a failure, so a test that deliberately provokes one says so
## here. Lowering the engine's own severity to keep the suite quiet would trade
## a real diagnostic for a green tick.
func expect_engine_error() -> void:
	GutUtils.get_error_tracker().treat_push_error_as = GutUtils.TREAT_AS.NOTHING


## Restore the default so the next test still fails on an unexpected error.
func restore_error_reporting() -> void:
	GutUtils.get_error_tracker().treat_push_error_as = GutUtils.TREAT_AS.FAILURE


func _spec(effect: GameplayEffect) -> GameplayEffectSpec:
	return GameplayEffectSpec.new(effect, GameplayEffectContext.new(fixture.owner))


#region Distinct storage
func test_an_add_and_a_multiply_on_one_attribute_keep_separate_magnitudes() -> void:
	var spec: GameplayEffectSpec = _spec(
		Factory.infinite([Factory.add(ATTACK, 10.0), Factory.multiply(ATTACK, 2.0)])
	)
	assert_almost_eq(spec.get_magnitude(0), 10.0, TOLERANCE, "the add")
	assert_almost_eq(spec.get_magnitude(1), 2.0, TOLERANCE, "the multiply")


func test_two_adds_on_one_attribute_keep_separate_magnitudes() -> void:
	var spec: GameplayEffectSpec = _spec(
		Factory.infinite([Factory.add(ATTACK, 3.0), Factory.add(ATTACK, 7.0)])
	)
	assert_almost_eq(spec.get_magnitude(0), 3.0, TOLERANCE)
	assert_almost_eq(spec.get_magnitude(1), 7.0, TOLERANCE)


func test_two_multiplies_on_one_attribute_keep_separate_magnitudes() -> void:
	var spec: GameplayEffectSpec = _spec(
		Factory.infinite([Factory.multiply(ATTACK, 1.5), Factory.multiply(ATTACK, 3.0)])
	)
	assert_almost_eq(spec.get_magnitude(0), 1.5, TOLERANCE)
	assert_almost_eq(spec.get_magnitude(1), 3.0, TOLERANCE)


func test_mutating_one_modifier_leaves_the_other_alone() -> void:
	var spec: GameplayEffectSpec = _spec(
		Factory.infinite([Factory.add(ATTACK, 3.0), Factory.add(ATTACK, 7.0)])
	)
	spec.set_magnitude(0, 99.0)
	assert_almost_eq(spec.get_magnitude(0), 99.0, TOLERANCE, "the one that was set")
	assert_almost_eq(spec.get_magnitude(1), 7.0, TOLERANCE, "the other is untouched")
#endregion


#region Both magnitudes reach the aggregator
func test_both_modifiers_of_one_effect_are_applied() -> void:
	# If the two shared one slot, the result would be 10 * 2 = 20 or 10 + 10 = 20
	# depending which survived. Both surviving gives ((10 + 10) * 2) = 40.
	Factory.apply(fixture.asc, Factory.infinite([Factory.add(ATTACK, 10.0), Factory.multiply(ATTACK, 2.0)]))
	assert_almost_eq(fixture.current_of(ATTACK), 40.0, TOLERANCE, "both landed")


func test_two_adds_of_one_effect_both_count() -> void:
	Factory.apply(fixture.asc, Factory.infinite([Factory.add(ATTACK, 3.0), Factory.add(ATTACK, 7.0)]))
	assert_almost_eq(fixture.current_of(ATTACK), 20.0, TOLERANCE, "10 + 3 + 7")
#endregion


#region Invalid index
func test_an_invalid_index_is_recorded_rather_than_answered_with_zero() -> void:
	var spec: GameplayEffectSpec = _spec(Factory.infinite([Factory.add(ATTACK, 3.0)]))
	assert_false(spec.had_invalid_magnitude_access(), "clean to begin with")

	spec.get_magnitude(5)
	assert_true(spec.had_invalid_magnitude_access(), "the spec remembers the bad access")


func test_an_invalid_index_refuses_the_application_instead_of_weakening_it() -> void:
	var before: float = fixture.current_of(ATTACK)
	var spec: GameplayEffectSpec = _spec(Factory.infinite([Factory.add(ATTACK, 3.0)]))
	expect_engine_error()
	spec.set_magnitude(9, 100.0)

	watch_signals(fixture.asc)
	var applied: ActiveGameplayEffect = fixture.asc.apply_effect_spec(spec)

	# The policy lives in the engine, not at the call site: a typo in an
	# execution calculation must not ship as a quietly weaker ability.
	assert_null(applied, "refused")
	assert_almost_eq(fixture.current_of(ATTACK), before, TOLERANCE, "nothing changed")
	assert_signal_not_emitted(fixture.asc, "attribute_changed")
#endregion


#region Level scaling
func test_magnitudes_are_snapshotted_at_the_application_level() -> void:
	var effect: GameplayEffect = Factory.infinite([Factory.add(ATTACK, 5.0)])
	var spec: GameplayEffectSpec = GameplayEffectSpec.new(
		effect, GameplayEffectContext.new(fixture.owner), 3.0
	)
	# No curve is attached, so the level does not scale a flat magnitude. The
	# point is that the value was captured once, at application.
	assert_almost_eq(spec.get_magnitude(0), 5.0, TOLERANCE)
	assert_almost_eq(spec.level, 3.0, TOLERANCE, "the level travelled with the spec")
#endregion
