## GameplayAbilityCostResolver: the structural edge of resolve(), directly.
##
## test_ability_commit.gd proves the resolver's business behaviour - what a
## percentage charges, aggregation, the durable-funds rule, the frozen
## snapshot. This file proves the boundary each GameplayAbilityCost entry has
## to clear before any of that arithmetic runs at all.
##
## @meta_license: MIT
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")

const MANA: StringName = &"mana"
const MAX_MANA: StringName = &"max_mana"
const UNKNOWN: StringName = &"unknown_attribute"

var fixture: ASCFixture = null
var asc: AbilitySystemComponent = null


func before_each() -> void:
	fixture = Fixture.create("Spender")
	add_child_autofree(fixture.owner)
	asc = fixture.asc


func after_each() -> void:
	fixture = null
	asc = null


#region Builders
func _absolute(target: StringName, positive_amount: float) -> GameplayAbilityCost:
	var cost: GameplayAbilityCost = GameplayAbilityCost.new()
	cost.mode = GameplayAbilityCost.Mode.ABSOLUTE
	cost.target_attribute = target
	cost.amount = GameplayScalableFloat.new()
	cost.amount.value = positive_amount
	return cost


func _resolve(costs: Array[GameplayAbilityCost]) -> GameplayResolvedCost:
	return GameplayAbilityCostResolver.resolve(costs, asc, 1.0)
#endregion


#region The ASC and the list itself
func test_a_null_asc_is_invalid() -> void:
	var costs: Array[GameplayAbilityCost] = [_absolute(MANA, 10.0)]
	var resolved: GameplayResolvedCost = GameplayAbilityCostResolver.resolve(costs, null, 1.0)
	assert_eq(resolved.status, GameplayResolvedCost.Status.INVALID_DEFINITION, "nobody to charge")


func test_a_non_finite_level_is_invalid() -> void:
	var costs: Array[GameplayAbilityCost] = [_absolute(MANA, 10.0)]
	var resolved: GameplayResolvedCost = GameplayAbilityCostResolver.resolve(costs, asc, NAN)
	assert_eq(resolved.status, GameplayResolvedCost.Status.INVALID_DEFINITION, "NaN cannot scale a curve")


func test_an_empty_list_resolves_to_nothing_owed() -> void:
	var no_costs: Array[GameplayAbilityCost] = []
	var resolved: GameplayResolvedCost = _resolve(no_costs)
	assert_true(resolved.is_ok(), "no costs declared is a free ability")
	assert_null(resolved.absolute_effect, "nothing to charge")
	assert_eq(resolved.entries.size(), 0, "nothing to account for")
#endregion


#region One malformed entry
func test_a_null_entry_is_invalid() -> void:
	var costs: Array[GameplayAbilityCost] = [null]
	var resolved: GameplayResolvedCost = _resolve(costs)
	assert_eq(resolved.status, GameplayResolvedCost.Status.INVALID_DEFINITION, "nothing to read")
	assert_eq(resolved.entries.size(), 0, "a structural failure keeps no partial entries")


func test_an_entry_with_no_amount_is_invalid() -> void:
	var cost: GameplayAbilityCost = GameplayAbilityCost.new()
	cost.target_attribute = MANA
	var resolved: GameplayResolvedCost = _resolve([cost])
	assert_eq(
		resolved.status, GameplayResolvedCost.Status.INVALID_DEFINITION, "nothing to evaluate"
	)


func test_an_entry_with_no_target_attribute_is_invalid() -> void:
	var cost: GameplayAbilityCost = _absolute(&"", 10.0)
	var resolved: GameplayResolvedCost = _resolve([cost])
	assert_eq(
		resolved.status, GameplayResolvedCost.Status.INVALID_DEFINITION, "nothing to charge"
	)


func test_an_absolute_entry_carrying_a_reference_is_invalid() -> void:
	var cost: GameplayAbilityCost = _absolute(MANA, 10.0)
	cost.reference_attribute = MAX_MANA
	var resolved: GameplayResolvedCost = _resolve([cost])
	assert_eq(
		resolved.status,
		GameplayResolvedCost.Status.INVALID_DEFINITION,
		"nothing is a fraction here, so nothing should be referenced"
	)


func test_a_percent_entry_missing_a_reference_is_invalid() -> void:
	var cost: GameplayAbilityCost = GameplayAbilityCost.new()
	cost.mode = GameplayAbilityCost.Mode.PERCENT_OF_BASE
	cost.target_attribute = MANA
	cost.amount = GameplayScalableFloat.new()
	cost.amount.value = 0.1
	var resolved: GameplayResolvedCost = _resolve([cost])
	assert_eq(
		resolved.status,
		GameplayResolvedCost.Status.INVALID_DEFINITION,
		"a fraction of nothing named is meaningless"
	)


func test_one_bad_entry_invalidates_the_whole_list() -> void:
	fixture.set_base(MANA, 100.0)
	var good: GameplayAbilityCost = _absolute(MANA, 10.0)
	var bad: GameplayAbilityCost = _absolute(UNKNOWN, 10.0)
	var resolved: GameplayResolvedCost = _resolve([good, bad])
	assert_eq(
		resolved.status,
		GameplayResolvedCost.Status.TARGET_ATTRIBUTE_NOT_FOUND,
		"the whole declaration is refused, not just its bad half"
	)
	assert_null(resolved.absolute_effect, "nothing built from a refused list")
#endregion


#region Status coverage
func test_status_ok_carries_a_usable_effect() -> void:
	fixture.set_base(MANA, 100.0)
	var resolved: GameplayResolvedCost = _resolve([_absolute(MANA, 10.0)])
	assert_eq(resolved.status, GameplayResolvedCost.Status.OK, "affordable and well formed")
	assert_not_null(resolved.absolute_effect, "there is something to charge")
	assert_eq(resolved.entries.size(), 1, "one entry for one declared cost")


func test_insufficient_resources_still_carries_the_frozen_effect_and_entries() -> void:
	fixture.set_base(MANA, 1.0)
	var resolved: GameplayResolvedCost = _resolve([_absolute(MANA, 10.0)])
	assert_eq(resolved.status, GameplayResolvedCost.Status.INSUFFICIENT_RESOURCES, "one short")
	assert_not_null(resolved.absolute_effect, "the price is still known")
	assert_eq(resolved.entries.size(), 1, "and so is why")
	assert_false(resolved.is_ok(), "but it is not affordable")
#endregion
