## AbilityCommitContract, tested directly rather than through an ability.
##
## GameplayAbility no longer accepts a hand-authored cost effect: it declares a
## list of GameplayAbilityCost entries, and GameplayAbilityCostResolver is the
## only code that ever builds what is_reversible_charge validates. None of the
## shapes this file proves illegal - non-instant, an execution, MULTIPLY,
## DIVIDE, OVERRIDE, a positive payout, a tag, an event, a cue - can be
## expressed through that authoring surface any more.
##
## They are tested here anyway, directly against the contract function, for
## the same reason they were tested at all: is_reversible_charge is the one
## place a broken resolver would be caught, and a function nothing calls with
## a bad shape is not the same as a function that cannot be called with one.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Factory = preload("res://test/fixtures/test_effect_factory.gd")

const MANA: StringName = &"mana"
const COOLDOWN_TAG: StringName = &"Cooldown.Probe"
const COOLDOWN_SECONDS: float = 5.0
const LEVEL: float = 1.0


## An execution that never runs. Exists only so the executions array can be
## non-empty: the base class is abstract and cannot be instantiated directly.
class NeverRuns extends GameplayExecutionCalculation:
	func execute(
		_spec: GameplayEffectSpec, _target_asc: AbilitySystemComponent
	) -> Dictionary[StringName, float]:
		var nothing: Dictionary[StringName, float] = {}
		return nothing


#region Cost: what is legal
func test_null_is_a_legal_cost() -> void:
	assert_true(AbilityCommitContract.is_reversible_charge(null, LEVEL), "an ability may be free")


func test_a_negative_add_is_a_legal_cost() -> void:
	var effect: GameplayEffect = Factory.instant([Factory.add(MANA, -20.0)])
	assert_true(AbilityCommitContract.is_reversible_charge(effect, LEVEL), "the ordinary shape")


func test_an_effect_with_no_modifiers_is_a_legal_cost() -> void:
	# Unlike the F2 contract, an empty modifier list is legal: a resolver
	# output where every declared cost resolved to zero owed is a real,
	# declared cost that happens to be free, not a missing one.
	var no_modifiers: Array[GameplayEffectModifier] = []
	var effect: GameplayEffect = Factory.instant(no_modifiers)
	assert_true(AbilityCommitContract.is_reversible_charge(effect, LEVEL), "zero owed is legal")


func test_several_negative_adds_are_a_legal_cost() -> void:
	var effect: GameplayEffect = Factory.instant(
		[Factory.add(MANA, -20.0), Factory.add(&"health", -5.0)]
	)
	assert_true(AbilityCommitContract.is_reversible_charge(effect, LEVEL), "one per attribute")
#endregion


#region Cost: what is not
func test_a_non_instant_cost_is_refused() -> void:
	var effect: GameplayEffect = Factory.duration([Factory.add(MANA, -20.0)], COOLDOWN_SECONDS)
	assert_false(
		AbilityCommitContract.is_reversible_charge(effect, LEVEL), "a cost is paid, not sustained"
	)


func test_a_cost_with_an_execution_is_refused() -> void:
	var effect: GameplayEffect = Factory.instant([Factory.add(MANA, -20.0)])
	effect.executions = [NeverRuns.new()] as Array[GameplayExecutionCalculation]
	assert_false(
		AbilityCommitContract.is_reversible_charge(effect, LEVEL), "an execution cannot be previewed"
	)


func test_multiply_reads_the_value_and_is_refused() -> void:
	var effect: GameplayEffect = Factory.instant([Factory.multiply(MANA, 0.9)])
	assert_false(AbilityCommitContract.is_reversible_charge(effect, LEVEL), "multiply reads the value")


func test_divide_reads_the_value_and_is_refused() -> void:
	var effect: GameplayEffect = Factory.instant([Factory.divide(MANA, 2.0)])
	assert_false(AbilityCommitContract.is_reversible_charge(effect, LEVEL), "divide reads the value")


func test_override_discards_the_value_and_is_refused() -> void:
	var effect: GameplayEffect = Factory.instant([Factory.override(MANA, 0.0)])
	assert_false(
		AbilityCommitContract.is_reversible_charge(effect, LEVEL), "override discards the value"
	)


func test_a_positive_magnitude_is_refused() -> void:
	var effect: GameplayEffect = Factory.instant([Factory.add(MANA, 10.0)])
	assert_false(
		AbilityCommitContract.is_reversible_charge(effect, LEVEL), "a cost that pays out is not one"
	)


func test_a_cost_that_grants_a_tag_is_refused() -> void:
	var effect: GameplayEffect = Factory.granting(
		Factory.instant([Factory.add(MANA, -20.0)]), [COOLDOWN_TAG]
	)
	assert_false(AbilityCommitContract.is_reversible_charge(effect, LEVEL), "a cost grants nothing")


func test_a_cost_that_dispatches_an_event_is_refused() -> void:
	var effect: GameplayEffect = Factory.with_events(
		Factory.instant([Factory.add(MANA, -20.0)]), [COOLDOWN_TAG]
	)
	assert_false(AbilityCommitContract.is_reversible_charge(effect, LEVEL), "a cost dispatches nothing")


func test_a_cost_that_plays_a_cue_is_refused() -> void:
	var effect: GameplayEffect = Factory.with_application_cues(
		Factory.instant([Factory.add(MANA, -20.0)]), [COOLDOWN_TAG]
	)
	assert_false(AbilityCommitContract.is_reversible_charge(effect, LEVEL), "a cost plays nothing")


func test_a_null_modifier_is_refused() -> void:
	var effect: GameplayEffect = Factory.instant([null])
	assert_false(AbilityCommitContract.is_reversible_charge(effect, LEVEL), "nothing to evaluate")
#endregion


#region Cooldown
func test_null_is_a_legal_cooldown() -> void:
	assert_true(AbilityCommitContract.is_legal_cooldown(null), "an ability may have none")


func test_a_cooldown_with_a_modifier_is_refused() -> void:
	var effect: GameplayEffect = Factory.granting(
		Factory.duration([Factory.add(MANA, -1.0)], COOLDOWN_SECONDS), [COOLDOWN_TAG]
	)
	assert_false(AbilityCommitContract.is_legal_cooldown(effect), "a cooldown is not a debuff")


func test_a_cooldown_with_no_granted_tag_is_refused() -> void:
	var no_modifiers: Array[GameplayEffectModifier] = []
	var effect: GameplayEffect = Factory.duration(no_modifiers, COOLDOWN_SECONDS)
	assert_false(AbilityCommitContract.is_legal_cooldown(effect), "nothing could observe it")


func test_a_zero_duration_cooldown_is_refused() -> void:
	var no_modifiers: Array[GameplayEffectModifier] = []
	var effect: GameplayEffect = Factory.granting(Factory.duration(no_modifiers, 0.0), [COOLDOWN_TAG])
	assert_false(AbilityCommitContract.is_legal_cooldown(effect), "over before it started")


func test_a_well_formed_duration_cooldown_is_legal() -> void:
	var no_modifiers: Array[GameplayEffectModifier] = []
	var effect: GameplayEffect = Factory.granting(
		Factory.duration(no_modifiers, COOLDOWN_SECONDS), [COOLDOWN_TAG]
	)
	assert_true(AbilityCommitContract.is_legal_cooldown(effect), "the ordinary shape")


func test_a_well_formed_turn_based_cooldown_is_legal() -> void:
	var no_modifiers: Array[GameplayEffectModifier] = []
	var effect: GameplayEffect = Factory.granting(Factory.turn_based(no_modifiers, 3), [COOLDOWN_TAG])
	assert_true(AbilityCommitContract.is_legal_cooldown(effect), "turns count as a cooldown too")
#endregion


#region Unique cooldowns
func test_a_shared_resource_listed_in_both_is_one_cooldown() -> void:
	var no_modifiers: Array[GameplayEffectModifier] = []
	var shared: GameplayEffect = Factory.granting(
		Factory.duration(no_modifiers, COOLDOWN_SECONDS), [COOLDOWN_TAG]
	)
	var unique: Array[GameplayEffect] = AbilityCommitContract.unique_cooldowns(shared, [shared])
	assert_eq(unique.size(), 1, "one Resource, one application")


func test_the_own_cooldown_comes_before_the_shared_ones() -> void:
	var no_modifiers: Array[GameplayEffectModifier] = []
	var own: GameplayEffect = Factory.granting(
		Factory.duration(no_modifiers, COOLDOWN_SECONDS), [&"Cooldown.Own"]
	)
	var other: GameplayEffect = Factory.granting(
		Factory.duration(no_modifiers, COOLDOWN_SECONDS), [&"Cooldown.Other"]
	)
	var unique: Array[GameplayEffect] = AbilityCommitContract.unique_cooldowns(own, [other])
	assert_eq(unique, [own, other] as Array[GameplayEffect], "own first, then declaration order")


func test_a_null_own_cooldown_contributes_nothing() -> void:
	var no_modifiers: Array[GameplayEffectModifier] = []
	var shared: GameplayEffect = Factory.granting(
		Factory.duration(no_modifiers, COOLDOWN_SECONDS), [COOLDOWN_TAG]
	)
	var unique: Array[GameplayEffect] = AbilityCommitContract.unique_cooldowns(null, [shared])
	assert_eq(unique, [shared] as Array[GameplayEffect], "nothing to add for a free ability")
#endregion
