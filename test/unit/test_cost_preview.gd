## Cost preview: the prediction and the commit are the same computation.
##
## A cost consumes durable base state. A
## temporary contribution raises the number on screen; it does not create
## spendable resource. A cost the clamp had to shrink was not affordable, only
## survivable.
##
## Split from test_effect_lifecycle.gd so the plan's file list is real. The
## tests moved; none were duplicated.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Factory = preload("res://test/fixtures/test_effect_factory.gd")

const TOLERANCE: float = 0.0001
const MANA: StringName = &"mana"

var fixture: ASCFixture = null
var asc: AbilitySystemComponent = null


func before_each() -> void:
	fixture = Fixture.create("Spender")
	add_child_autofree(fixture.owner)
	asc = fixture.asc


func after_each() -> void:
	fixture = null
	asc = null


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
	# not affordable, only survivable. Priced through the resolver, the same way
	# an ability's percentage cost is: 100% of the displayed 30 is 30, but the
	# resolver's own affordability check refuses it.
	var cost: GameplayAbilityCost = GameplayAbilityCost.new()
	cost.mode = GameplayAbilityCost.Mode.PERCENT_OF_CURRENT
	cost.target_attribute = MANA
	cost.reference_attribute = MANA
	cost.amount = GameplayScalableFloat.new()
	cost.amount.value = 1.0
	var costs: Array[GameplayAbilityCost] = [cost]
	var resolved: GameplayResolvedCost = GameplayAbilityCostResolver.resolve(costs, asc, 1.0)
	assert_almost_eq(resolved.entries[0].resolved_amount, 30.0, TOLERANCE, "priced at the full 30")
	assert_false(resolved.is_ok(), "borrowed mana does not pay for itself")


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
