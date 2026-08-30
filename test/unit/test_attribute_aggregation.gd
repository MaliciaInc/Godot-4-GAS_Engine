## The canonical formula, proved case by case.
##
##     current = ((base + sum(ADD)) * product(MULTIPLY)) / product(DIVIDE)
##
## then the last applicable OVERRIDE, then the effective clamp.
##
## The case that matters most is base 10 with +10 and x2. It is 40. A model that
## applies each modifier to the running value in declaration order gives 30, and
## upstream's delta model gave whichever of the two the array happened to
## produce.
##
## @meta_license: MIT
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Factory = preload("res://test/fixtures/test_effect_factory.gd")

const TOLERANCE: float = 0.0001
const ATTACK: StringName = &"attack"
const MANA: StringName = &"mana"

var fixture: ASCFixture = null


func before_each() -> void:
	fixture = Fixture.create("Subject")
	add_child_autofree(fixture.owner)


func after_each() -> void:
	fixture = null


func _apply(effect: GameplayEffect) -> ActiveGameplayEffect:
	return Factory.apply(fixture.asc, effect)


#region Additive
func test_two_adds_sum_onto_the_base() -> void:
	fixture.set_base(ATTACK, 10.0)
	_apply(Factory.infinite([Factory.add(ATTACK, 5.0), Factory.add(ATTACK, 2.0)]))
	assert_almost_eq(fixture.current_of(ATTACK), 17.0, TOLERANCE, "10 + 5 + 2")


func test_adds_from_separate_effects_also_sum() -> void:
	fixture.set_base(ATTACK, 10.0)
	_apply(Factory.infinite([Factory.add(ATTACK, 5.0)]))
	_apply(Factory.infinite([Factory.add(ATTACK, 2.0)]))
	assert_almost_eq(fixture.current_of(ATTACK), 17.0, TOLERANCE, "two effects, one sum")
#endregion


#region Multiplicative
func test_multipliers_compound_with_each_other() -> void:
	fixture.set_base(ATTACK, 10.0)
	_apply(Factory.infinite([Factory.multiply(ATTACK, 1.5), Factory.multiply(ATTACK, 1.5)]))
	# x1.5 twice is x2.25, not x2.0. Multipliers are not converted into additive
	# percentages, which is the usual way this goes wrong.
	assert_almost_eq(fixture.current_of(ATTACK), 22.5, TOLERANCE, "10 * 1.5 * 1.5")
#endregion


#region Mixed
func test_add_then_multiply_is_forty_not_thirty() -> void:
	fixture.set_base(ATTACK, 10.0)
	_apply(Factory.infinite([Factory.add(ATTACK, 10.0), Factory.multiply(ATTACK, 2.0)]))
	assert_almost_eq(fixture.current_of(ATTACK), 40.0, TOLERANCE, "((10 + 10) * 2)")


func test_declaration_order_does_not_change_the_result() -> void:
	fixture.set_base(ATTACK, 10.0)
	# The multiply is declared first here. The formula sums adds before applying
	# multipliers regardless, so the answer is still 40.
	_apply(Factory.infinite([Factory.multiply(ATTACK, 2.0), Factory.add(ATTACK, 10.0)]))
	assert_almost_eq(fixture.current_of(ATTACK), 40.0, TOLERANCE, "still 40")
#endregion


#region Division
func test_divisors_compound() -> void:
	fixture.set_base(ATTACK, 100.0)
	_apply(Factory.infinite([Factory.divide(ATTACK, 2.0), Factory.divide(ATTACK, 5.0)]))
	assert_almost_eq(fixture.current_of(ATTACK), 10.0, TOLERANCE, "100 / 2 / 5")


func test_dividing_by_zero_refuses_the_whole_application() -> void:
	fixture.set_base(ATTACK, 100.0)
	var before_base: float = fixture.base_of(ATTACK)
	var before_current: float = fixture.current_of(ATTACK)

	watch_signals(fixture.asc)
	var applied: ActiveGameplayEffect = _apply(
		Factory.infinite([Factory.add(ATTACK, 10.0), Factory.divide(ATTACK, 0.0)])
	)

	assert_null(applied, "the application is refused")
	assert_almost_eq(fixture.base_of(ATTACK), before_base, TOLERANCE, "base untouched")
	assert_almost_eq(fixture.current_of(ATTACK), before_current, TOLERANCE, "current untouched")
	# The valid +10 in the same effect must not land either: the transaction is
	# atomic, so a partial application is not a lesser failure, it is a worse one.
	assert_signal_not_emitted(fixture.asc, "attribute_changed", "no partial signal")
	assert_signal_not_emitted(fixture.asc, "active_effect_added", "nothing registered")
	assert_eq(fixture.asc.get_active_effects().size(), 0, "no active effect")
#endregion


#region Override
func test_last_override_wins_and_earlier_ones_survive_underneath() -> void:
	fixture.set_base(ATTACK, 10.0)
	var first: ActiveGameplayEffect = _apply(Factory.infinite([Factory.override(ATTACK, 50.0)]))
	var second: ActiveGameplayEffect = _apply(Factory.infinite([Factory.override(ATTACK, 100.0)]))
	assert_almost_eq(fixture.current_of(ATTACK), 100.0, TOLERANCE, "later override wins")

	fixture.asc.remove_active_effect(second)
	# The first override was never destroyed, only outranked, so it becomes
	# visible again rather than the attribute falling back to its base.
	assert_almost_eq(fixture.current_of(ATTACK), 50.0, TOLERANCE, "earlier override returns")

	fixture.asc.remove_active_effect(first)
	assert_almost_eq(fixture.current_of(ATTACK), 10.0, TOLERANCE, "back to base")


func test_within_one_effect_the_higher_modifier_index_wins() -> void:
	fixture.set_base(ATTACK, 10.0)
	_apply(Factory.infinite([Factory.override(ATTACK, 50.0), Factory.override(ATTACK, 100.0)]))
	assert_almost_eq(fixture.current_of(ATTACK), 100.0, TOLERANCE, "index 1 beats index 0")
#endregion


#region Removal order independence
func test_removing_the_add_first_leaves_the_multiplier_correct() -> void:
	fixture.set_base(ATTACK, 100.0)
	var adder: ActiveGameplayEffect = _apply(Factory.infinite([Factory.add(ATTACK, 20.0)]))
	var doubler: ActiveGameplayEffect = _apply(Factory.infinite([Factory.multiply(ATTACK, 2.0)]))
	assert_almost_eq(fixture.current_of(ATTACK), 240.0, TOLERANCE, "(100 + 20) * 2")

	fixture.asc.remove_active_effect(adder)
	assert_almost_eq(fixture.current_of(ATTACK), 200.0, TOLERANCE, "100 * 2")

	fixture.asc.remove_active_effect(doubler)
	assert_almost_eq(fixture.current_of(ATTACK), 100.0, TOLERANCE, "base")


func test_removing_the_multiplier_first_ends_at_the_same_place() -> void:
	fixture.set_base(ATTACK, 100.0)
	var adder: ActiveGameplayEffect = _apply(Factory.infinite([Factory.add(ATTACK, 20.0)]))
	var doubler: ActiveGameplayEffect = _apply(Factory.infinite([Factory.multiply(ATTACK, 2.0)]))

	# The reverse order. A delta model cannot do this: the +20 it recorded was
	# worth 20 when applied and 40 once doubled, and reversing either number is
	# wrong. Recomposition has no such problem because it keeps no history.
	fixture.asc.remove_active_effect(doubler)
	assert_almost_eq(fixture.current_of(ATTACK), 120.0, TOLERANCE, "100 + 20")

	fixture.asc.remove_active_effect(adder)
	assert_almost_eq(fixture.current_of(ATTACK), 100.0, TOLERANCE, "base")
#endregion


#region Instant versus active
func test_the_same_modifiers_as_instant_commit_to_base() -> void:
	fixture.set_base(ATTACK, 10.0)
	_apply(Factory.instant([Factory.add(ATTACK, 10.0), Factory.multiply(ATTACK, 2.0)]))
	assert_almost_eq(fixture.base_of(ATTACK), 40.0, TOLERANCE, "instant writes the base")
	assert_almost_eq(fixture.current_of(ATTACK), 40.0, TOLERANCE, "current follows")
	assert_eq(fixture.asc.get_active_effects().size(), 0, "instant registers nothing")


func test_the_same_modifiers_as_active_leave_the_base_alone() -> void:
	fixture.set_base(ATTACK, 10.0)
	var active: ActiveGameplayEffect = _apply(
		Factory.infinite([Factory.add(ATTACK, 10.0), Factory.multiply(ATTACK, 2.0)])
	)
	assert_almost_eq(fixture.base_of(ATTACK), 10.0, TOLERANCE, "base untouched by an active effect")
	assert_almost_eq(fixture.current_of(ATTACK), 40.0, TOLERANCE, "same arithmetic")

	fixture.asc.remove_active_effect(active)
	assert_almost_eq(fixture.current_of(ATTACK), 10.0, TOLERANCE, "returns to base")
#endregion


#region Base changes under an active buff
func test_raising_the_base_recomposes_instead_of_dropping_the_buff() -> void:
	fixture.set_base(ATTACK, 10.0)
	var buff: ActiveGameplayEffect = _apply(Factory.infinite([Factory.multiply(ATTACK, 2.0)]))
	assert_almost_eq(fixture.current_of(ATTACK), 20.0, TOLERANCE, "10 * 2")

	# Levelling up while buffed. Upstream's base setter assigned current = base
	# here, silently deleting the buff.
	fixture.set_base(ATTACK, 15.0)
	assert_almost_eq(fixture.current_of(ATTACK), 30.0, TOLERANCE, "15 * 2")

	fixture.asc.remove_active_effect(buff)
	assert_almost_eq(fixture.current_of(ATTACK), 15.0, TOLERANCE, "the new base survives")
#endregion


#region Bootstrap
func test_a_stale_current_value_is_repaired_without_signals() -> void:
	# An authored Resource with base 100 and a stale current of 0 must come up
	# at 100/100, and the repair must not look like gameplay to a listener.
	var stale: ASCFixture = Fixture.create("Stale")
	stale.attributes.mana.base_value = 100.0
	stale.attributes.mana.current_value = 0.0

	var component: AbilitySystemComponent = stale.asc
	watch_signals(component)
	add_child_autofree(stale.owner)

	assert_almost_eq(stale.base_of(MANA), 100.0, TOLERANCE, "base preserved")
	assert_almost_eq(stale.current_of(MANA), 100.0, TOLERANCE, "current repaired")
	assert_signal_not_emitted(component, "attribute_changed", "bootstrap is silent")
#endregion
