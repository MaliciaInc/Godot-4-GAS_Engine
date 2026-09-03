## What a resolved ability cost actually charges.
##
## Split out of test_ability_commit.gd, which covers the transaction around a
## price - cooldown legality, rollback, the second affordability check - and
## kept that scope once this file's LOC would have pushed it over the limit.
## Nothing here is duplicated there.
##
## Every entry here is priced by GameplayAbilityCostResolver: absolute
## amounts, percentages of an attribute's base or current value, aggregation
## across several entries and several attributes, and the durable-funds rule -
## a percentage priced against a buffed current value never spends durable
## base that was never there.
##
## costs is read from the frozen definition a grant captured, and level from
## the spec a grant was given rather than from ability_level - so a test needs
## a specific price authors a fresh probe (and, for level, passes it to the
## grant) before granting, never edits `ability` afterward.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Factory = preload("res://test/fixtures/test_effect_factory.gd")
const Probe = preload("res://test/fixtures/probe_ability.gd")
const AbilityFactory = preload("res://test/fixtures/test_ability_factory.gd")

const TOLERANCE: float = 0.0001
const MANA: StringName = &"mana"
const MAX_MANA: StringName = &"max_mana"
const HEALTH: StringName = &"health"
const ATTACK: StringName = &"attack"
const PROBE_TAG: StringName = &"Ability.Probe"
const STARTING_MANA: float = 50.0
const COST_AMOUNT: float = 20.0

var fixture: ASCFixture = null
var asc: AbilitySystemComponent = null
var ability: ProbeAbility = null


func before_each() -> void:
	fixture = Fixture.create("Caster")
	add_child_autofree(fixture.owner)
	asc = fixture.asc
	fixture.set_base(MANA, STARTING_MANA)
	ability = _granted([])


func after_each() -> void:
	fixture = null
	asc = null
	ability = null


#region Builders
func _absolute(target: StringName, positive_amount: float) -> GameplayAbilityCost:
	var cost: GameplayAbilityCost = GameplayAbilityCost.new()
	cost.mode = GameplayAbilityCost.Mode.ABSOLUTE
	cost.target_attribute = target
	cost.amount = GameplayScalableFloat.new()
	cost.amount.value = positive_amount
	return cost


func _percent(
	target: StringName, reference: StringName, fraction: float, of_base: bool
) -> GameplayAbilityCost:
	var cost: GameplayAbilityCost = GameplayAbilityCost.new()
	cost.mode = (
		GameplayAbilityCost.Mode.PERCENT_OF_BASE
		if of_base
		else GameplayAbilityCost.Mode.PERCENT_OF_CURRENT
	)
	cost.target_attribute = target
	cost.reference_attribute = reference
	cost.amount = GameplayScalableFloat.new()
	cost.amount.value = fraction
	return cost


## Grant a fresh probe priced with exactly `costs`, at `level`. costs lives in
## the frozen definition a grant captures, so it is authored on the probe
## before granting, never edited on `ability` afterward.
func _granted(costs: Array[GameplayAbilityCost], level: float = 1.0) -> ProbeAbility:
	var probe: ProbeAbility = Probe.build(PROBE_TAG)
	probe.costs = costs
	var spec: GameplayAbilitySpec = AbilityFactory.give(asc, probe, level)
	return spec.per_actor_instance as ProbeAbility


## The status of committing the ability under test, for the many cases whose
## whole claim is which refusal came back.
func _status() -> AbilityCommitResult.Status:
	return ability.commit_ability().status
#endregion


#region Absolute and percentage costs
func test_an_absolute_cost_charges_the_declared_amount() -> void:
	ability = _granted([_absolute(MANA, COST_AMOUNT)])
	var result: AbilityCommitResult = ability.commit_ability()
	assert_true(result.is_ok(), "a plain absolute charge commits")
	assert_almost_eq(
		fixture.base_of(MANA), STARTING_MANA - COST_AMOUNT, TOLERANCE, "exactly the declared amount"
	)


func test_an_absolute_cost_scales_with_a_curve_and_level() -> void:
	# Godot clamps both axes to [0, 1] by default: max_domain for X, max_value
	# for Y. Without widening both, add_point(Vector2(2.0, 2.0)) silently
	# stores (2.0, 1.0) - the Y value clamped away. Sampling exactly at a
	# control point is then exact for any Bezier curve, tangents included: the
	# curve passes through its own points.
	var curve: Curve = Curve.new()
	curve.max_domain = 2.0
	curve.max_value = 2.0
	curve.add_point(Vector2(1.0, 1.0))
	curve.add_point(Vector2(2.0, 2.0))
	var cost: GameplayAbilityCost = _absolute(MANA, 10.0)
	cost.amount.scaling_curve = curve
	ability = _granted([cost], 2.0)

	var result: AbilityCommitResult = ability.commit_ability()
	assert_true(result.is_ok(), "the curve is legal")
	assert_almost_eq(
		fixture.base_of(MANA), STARTING_MANA - 20.0, TOLERANCE, "level 2 doubled the base 10"
	)


func test_ten_percent_of_base_charges_a_tenth_of_the_durable_value() -> void:
	fixture.set_base(MANA, 200.0)
	ability = _granted([_percent(MANA, MANA, 0.10, true)])

	var result: AbilityCommitResult = ability.commit_ability()
	assert_true(result.is_ok(), "10% of a full base is affordable")
	assert_almost_eq(fixture.base_of(MANA), 180.0, TOLERANCE, "20 taken, ten percent of 200 base")


func test_ten_percent_of_current_prices_against_the_derived_value() -> void:
	fixture.set_base(MANA, 200.0)
	Factory.apply(asc, Factory.infinite([Factory.add(MANA, 50.0)]))
	ability = _granted([_percent(MANA, MANA, 0.10, false)])

	var result: AbilityCommitResult = ability.commit_ability()
	assert_true(result.is_ok(), "affordable against the buffed pool")
	# 10% of current (250) is 25, taken from the base the buff sits on top of.
	assert_almost_eq(fixture.base_of(MANA), 175.0, TOLERANCE, "priced off current, taken from base")


func test_a_cost_priced_against_a_different_attribute_than_it_spends() -> void:
	fixture.set_base(MANA, 50.0)
	fixture.set_base(MAX_MANA, 100.0)
	ability = _granted([_percent(MANA, MAX_MANA, 0.10, true)])

	var result: AbilityCommitResult = ability.commit_ability()
	assert_true(result.is_ok(), "target and reference may differ")
	assert_almost_eq(fixture.base_of(MANA), 40.0, TOLERANCE, "10 percent of MaxMana, spent from Mana")


func test_five_percent_of_health_current_spends_health() -> void:
	fixture.set_base(HEALTH, 100.0)
	ability = _granted([_percent(HEALTH, HEALTH, 0.05, false)])

	var result: AbilityCommitResult = ability.commit_ability()
	assert_true(result.is_ok(), "a percentage cost on a different attribute family")
	assert_almost_eq(fixture.base_of(HEALTH), 95.0, TOLERANCE, "5 percent of 100 current health")


func test_twenty_five_percent_of_attack_base_spends_attack() -> void:
	fixture.set_base(ATTACK, 40.0)
	ability = _granted([_percent(ATTACK, ATTACK, 0.25, true)])

	var result: AbilityCommitResult = ability.commit_ability()
	assert_true(result.is_ok(), "spending a fraction of the attacker's own attack")
	assert_almost_eq(fixture.base_of(ATTACK), 30.0, TOLERANCE, "25 percent of 40 base")


func test_a_zero_percent_cost_commits_without_writing_the_attribute() -> void:
	ability = _granted([_percent(MANA, MANA, 0.0, true)])
	watch_signals(asc)

	var result: AbilityCommitResult = ability.commit_ability()
	assert_true(result.is_ok(), "0% is a legal, free declaration")
	assert_almost_eq(fixture.base_of(MANA), STARTING_MANA, TOLERANCE, "nothing was taken")
	assert_signal_not_emitted(asc, "attribute_changed", "no write for a zero charge")


func test_a_hundred_percent_cost_takes_everything() -> void:
	fixture.set_base(MANA, 30.0)
	ability = _granted([_percent(MANA, MANA, 1.0, true)])

	var result: AbilityCommitResult = ability.commit_ability()
	assert_true(result.is_ok(), "100% is the legal maximum")
	assert_almost_eq(fixture.base_of(MANA), 0.0, TOLERANCE, "every point of base was taken")


func test_a_percent_over_one_hundred_is_refused() -> void:
	ability = _granted([_percent(MANA, MANA, 1.5, true)])
	assert_eq(
		_status(), AbilityCommitResult.Status.INVALID_COST_DEFINITION, "150% is not a fraction"
	)


func test_a_negative_percent_is_refused() -> void:
	ability = _granted([_percent(MANA, MANA, -0.1, true)])
	assert_eq(
		_status(),
		AbilityCommitResult.Status.INVALID_COST_DEFINITION,
		"a negative fraction is not a percentage"
	)


func test_a_non_finite_percent_is_refused() -> void:
	ability = _granted([_percent(MANA, MANA, NAN, true)])
	assert_eq(_status(), AbilityCommitResult.Status.INVALID_COST_DEFINITION, "NaN")

	ability = _granted([_percent(MANA, MANA, INF, true)])
	assert_eq(_status(), AbilityCommitResult.Status.INVALID_COST_DEFINITION, "and INF")


func test_a_cost_naming_an_unknown_target_attribute_is_refused() -> void:
	ability = _granted([_absolute(&"unknown_attribute", 10.0)])
	assert_eq(
		_status(),
		AbilityCommitResult.Status.INVALID_COST_DEFINITION,
		"nothing to charge that attribute"
	)


func test_a_percent_cost_naming_an_unknown_reference_is_refused() -> void:
	ability = _granted([_percent(MANA, &"unknown_attribute", 0.1, true)])
	assert_eq(
		_status(), AbilityCommitResult.Status.INVALID_COST_DEFINITION, "nothing to price against"
	)


func test_two_costs_on_the_same_attribute_are_aggregated() -> void:
	fixture.set_base(MANA, 200.0)
	ability = _granted([_absolute(MANA, 30.0), _percent(MANA, MANA, 0.50, false)])

	var result: AbilityCommitResult = ability.commit_ability()
	assert_true(result.is_ok(), "affordability sees the aggregated total, 30 plus 100")
	assert_almost_eq(fixture.base_of(MANA), 70.0, TOLERANCE, "70 mana taken in one write")
	assert_eq(result.resolved_cost.absolute_effect.modifiers.size(), 1, "one modifier, one attribute")


func test_costs_on_different_attributes_charge_both() -> void:
	fixture.set_base(HEALTH, 100.0)
	ability = _granted([_absolute(MANA, COST_AMOUNT), _absolute(HEALTH, 10.0)])

	var result: AbilityCommitResult = ability.commit_ability()
	assert_true(result.is_ok(), "two attributes, two charges")
	assert_almost_eq(fixture.base_of(MANA), STARTING_MANA - COST_AMOUNT, TOLERANCE, "mana charged")
	assert_almost_eq(fixture.base_of(HEALTH), 90.0, TOLERANCE, "and health charged")
	assert_eq(result.resolved_cost.absolute_effect.modifiers.size(), 2, "one modifier per attribute")
#endregion


#region The durable-funds rule
func test_a_temporary_buff_raises_the_price_but_not_the_durable_funds() -> void:
	fixture.set_base(MANA, 20.0)
	Factory.apply(asc, Factory.infinite([Factory.add(MANA, 80.0)]))
	assert_almost_eq(fixture.current_of(MANA), 100.0, TOLERANCE, "the buff shows on screen")

	# 50% of current (100) prices the cost at 50, but only 20 is durable.
	ability = _granted([_percent(MANA, MANA, 0.5, false)])
	var resolved: GameplayResolvedCost = GameplayAbilityCostResolver.resolve(
		ability.current_spec.definition.costs, asc, ability.get_ability_level()
	)
	assert_almost_eq(resolved.entries[0].resolved_amount, 50.0, TOLERANCE, "the price is 50")
	assert_false(resolved.is_ok(), "but the buff does not create 30 mana that does not exist")
	assert_eq(_status(), AbilityCommitResult.Status.INSUFFICIENT_RESOURCES, "the commit agrees")
	assert_almost_eq(fixture.base_of(MANA), 20.0, TOLERANCE, "nothing was taken")


func test_preview_and_commit_agree_on_a_percentage_cost() -> void:
	fixture.set_base(MANA, 40.0)
	ability = _granted([_percent(MANA, MANA, 0.5, true)])

	var resolved: GameplayResolvedCost = GameplayAbilityCostResolver.resolve(
		ability.current_spec.definition.costs, asc, ability.get_ability_level()
	)
	var predicted: bool = resolved.is_ok()

	var result: AbilityCommitResult = ability.commit_ability()
	assert_eq(predicted, result.is_ok(), "the same resolver answered both questions")


func test_a_second_activation_re_resolves_against_the_current_state() -> void:
	ability = _granted([_percent(MANA, MANA, 0.5, true)])
	ability.commits = true

	var first: bool = await ability.try_activate()
	assert_true(first, "50% of 50 is affordable")
	assert_almost_eq(fixture.base_of(MANA), 25.0, TOLERANCE, "half taken")

	var second: bool = await ability.try_activate()
	assert_true(second, "and the second activation re-prices against the new base")
	assert_almost_eq(fixture.base_of(MANA), 12.5, TOLERANCE, "half of the new base, not the old one")
#endregion


#region Frozen at resolve time
func test_a_reference_changing_after_resolve_does_not_change_the_frozen_charge() -> void:
	fixture.set_base(MANA, 100.0)
	fixture.set_base(MAX_MANA, 100.0)
	ability = _granted([_percent(MANA, MAX_MANA, 0.5, true)])

	var resolved: GameplayResolvedCost = GameplayAbilityCostResolver.resolve(
		ability.current_spec.definition.costs, asc, ability.get_ability_level()
	)
	assert_almost_eq(resolved.entries[0].resolved_amount, 50.0, TOLERANCE, "priced at 50% of 100")

	# The reference moves after resolving, before anything is charged.
	fixture.set_base(MAX_MANA, 1000.0)

	assert_almost_eq(
		resolved.entries[0].resolved_amount, 50.0, TOLERANCE, "the snapshot still reads 50"
	)
	var frozen: GameplayScalableMagnitude = resolved.absolute_effect.modifiers[0].magnitude as GameplayScalableMagnitude
	assert_almost_eq(
		frozen.value.evaluate(1.0),
		-50.0,
		TOLERANCE,
		"and the frozen effect still charges 50, not the new reference"
	)
#endregion
