## The evaluator itself: execution calculations, ambiguity and typed status.
##
## The evaluator is pure - it reads state and returns staged work. These tests
## call it directly, so what is asserted is the staging, not a value that
## happened to come out the far end of the whole pipeline.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Factory = preload("res://test/fixtures/test_effect_factory.gd")
const Evaluator = preload("res://addons/GAS_Engine/effects/gameplay_effect_evaluator.gd")

const TOLERANCE: float = 0.0001
const ATTACK: StringName = &"attack"
const HEALTH: StringName = &"health"
const DEFENSE: StringName = &"defense"

var fixture: ASCFixture = null
var asc: AbilitySystemComponent = null


## A calculation that returns a fixed delta, for asserting the ExecCalc contract
## without also testing whatever arithmetic a real one would do.
class FlatDamage extends GameplayExecutionCalculation:
	var attribute: StringName = &"health"
	var delta: float = -10.0

	func execute(
		_spec: GameplayEffectSpec, _target_asc: AbilitySystemComponent
	) -> Dictionary[StringName, float]:
		var produced: Dictionary[StringName, float] = {}
		produced[attribute] = delta
		return produced


## A calculation that reads the target's own stats, to prove it can.
class TargetDependentDamage extends GameplayExecutionCalculation:
	func execute(
		_spec: GameplayEffectSpec, target_asc: AbilitySystemComponent
	) -> Dictionary[StringName, float]:
		var produced: Dictionary[StringName, float] = {}
		produced[&"health"] = -target_asc.get_attribute_current(&"defense")
		return produced


func before_each() -> void:
	fixture = Fixture.create("Evaluated")
	add_child_autofree(fixture.owner)
	asc = fixture.asc


func after_each() -> void:
	fixture = null
	asc = null


func _request(effect: GameplayEffect, mode: int) -> GameplayEffectEvaluator.Request:
	var request: GameplayEffectEvaluator.Request = Evaluator.Request.new()
	request.spec = GameplayEffectSpec.new(effect, GameplayEffectContext.new(fixture.owner))
	request.attributes = asc.attributes
	request.owner_asc = asc
	request.application_order = 0
	request.mode = mode
	return request


func _evaluate(effect: GameplayEffect, mode: int) -> GameplayEffectEvaluationResult:
	return Evaluator.evaluate(_request(effect, mode))


#region Purity
func test_evaluation_stages_without_writing() -> void:
	fixture.set_base(ATTACK, 10.0)
	watch_signals(asc)

	var result: GameplayEffectEvaluationResult = _evaluate(
		Factory.instant([Factory.add(ATTACK, 10.0)]), Evaluator.Mode.BASE_MUTATION
	)

	assert_true(result.is_ok())
	assert_eq(result.base_mutations.size(), 1, "one attribute staged")
	# Staged, not written. The whole point of a preview sharing this code is
	# that calling it changes nothing.
	assert_almost_eq(fixture.base_of(ATTACK), 10.0, TOLERANCE, "base untouched")
	assert_signal_not_emitted(asc, "attribute_changed", "and silent")


func test_a_staged_mutation_reports_requested_against_committed() -> void:
	var result: GameplayEffectEvaluationResult = _evaluate(
		Factory.instant([Factory.add(HEALTH, -500.0)]), Evaluator.Mode.BASE_MUTATION
	)
	var staged: AttributeBaseMutation = result.base_mutations[0]
	assert_almost_eq(staged.old_base_value, 100.0, TOLERANCE, "where it started")
	assert_almost_eq(staged.requested_base_value, -400.0, TOLERANCE, "what was asked")
	assert_almost_eq(staged.committed_base_value, 0.0, TOLERANCE, "what the clamp allows")
#endregion


#region Modes
func test_contribution_mode_builds_contributions_and_no_base_writes() -> void:
	var result: GameplayEffectEvaluationResult = _evaluate(
		Factory.infinite([Factory.add(ATTACK, 5.0), Factory.multiply(ATTACK, 2.0)]),
		Evaluator.Mode.CONTRIBUTION
	)
	assert_eq(result.contributions.size(), 2, "one per modifier")
	assert_eq(result.base_mutations.size(), 0, "an active effect never writes the base")


func test_a_contribution_records_both_ordering_axes() -> void:
	var result: GameplayEffectEvaluationResult = _evaluate(
		Factory.infinite([Factory.add(ATTACK, 5.0), Factory.add(ATTACK, 7.0)]),
		Evaluator.Mode.CONTRIBUTION
	)
	assert_eq(result.contributions[0].modifier_index, 0)
	assert_eq(result.contributions[1].modifier_index, 1)
	assert_eq(result.contributions[0].application_order, result.contributions[1].application_order,
		"same application")


func test_base_mutation_mode_stages_writes_and_no_contributions() -> void:
	var result: GameplayEffectEvaluationResult = _evaluate(
		Factory.instant([Factory.add(ATTACK, 5.0)]), Evaluator.Mode.BASE_MUTATION
	)
	assert_eq(result.base_mutations.size(), 1)
	assert_eq(result.contributions.size(), 0, "an instant effect leaves nothing behind")
#endregion


#region Execution calculations
func test_an_execution_calculation_stages_a_base_mutation() -> void:
	var effect: GameplayEffect = Factory.instant([])
	effect.executions = [FlatDamage.new()] as Array[GameplayExecutionCalculation]

	var result: GameplayEffectEvaluationResult = _evaluate(effect, Evaluator.Mode.BASE_MUTATION)
	assert_true(result.is_ok())
	assert_eq(result.base_mutations.size(), 1)
	assert_almost_eq(result.base_mutations[0].requested_base_value, 90.0, TOLERANCE, "100 - 10")


func test_an_execution_calculation_can_read_the_target() -> void:
	fixture.set_base(DEFENSE, 7.0)
	var effect: GameplayEffect = Factory.instant([])
	effect.executions = [TargetDependentDamage.new()] as Array[GameplayExecutionCalculation]

	Factory.apply(asc, effect)
	assert_almost_eq(fixture.base_of(HEALTH), 93.0, TOLERANCE, "100 minus this target's defence")


func test_an_execution_calculation_writing_an_unknown_attribute_fails() -> void:
	var calculation: FlatDamage = FlatDamage.new()
	calculation.attribute = &"no_such_attribute"
	var effect: GameplayEffect = Factory.instant([])
	effect.executions = [calculation] as Array[GameplayExecutionCalculation]

	var result: GameplayEffectEvaluationResult = _evaluate(effect, Evaluator.Mode.BASE_MUTATION)
	assert_false(result.is_ok())
	assert_eq(result.status, AttributeEvaluationResult.Status.ATTRIBUTE_NOT_FOUND)
	assert_eq(result.error_attribute_name, &"no_such_attribute", "and says which one")
#endregion


#region Ambiguity
func test_an_attribute_written_by_both_mechanisms_is_refused() -> void:
	# An ExecCalc flat delta and a standard modifier on the same attribute have
	# no defined order: "add 5" then "double it" is not the same as the reverse,
	# and neither mechanism is the outer one. The engine refuses rather than
	# choosing.
	var effect: GameplayEffect = Factory.instant([Factory.multiply(HEALTH, 2.0)])
	effect.executions = [FlatDamage.new()] as Array[GameplayExecutionCalculation]

	var result: GameplayEffectEvaluationResult = _evaluate(effect, Evaluator.Mode.BASE_MUTATION)
	assert_false(result.is_ok())
	assert_eq(result.status, AttributeEvaluationResult.Status.AMBIGUOUS_ATTRIBUTE_WRITE)
	assert_eq(result.error_attribute_name, HEALTH, "and names the attribute")
	assert_eq(result.base_mutations.size(), 0, "nothing staged")


func test_the_two_mechanisms_may_write_different_attributes() -> void:
	# The rule is per attribute, not per effect. A fireball may compute damage
	# to Health while also applying a flat Defense debuff.
	var effect: GameplayEffect = Factory.instant([Factory.add(ATTACK, 5.0)])
	effect.executions = [FlatDamage.new()] as Array[GameplayExecutionCalculation]

	var result: GameplayEffectEvaluationResult = _evaluate(effect, Evaluator.Mode.BASE_MUTATION)
	assert_true(result.is_ok(), "different attributes are unambiguous")
	assert_eq(result.base_mutations.size(), 2)


func test_an_ambiguous_effect_changes_nothing_when_applied() -> void:
	var before: float = fixture.base_of(HEALTH)
	var effect: GameplayEffect = Factory.instant([Factory.multiply(HEALTH, 2.0)])
	effect.executions = [FlatDamage.new()] as Array[GameplayExecutionCalculation]

	watch_signals(asc)
	assert_null(Factory.apply(asc, effect), "refused")
	assert_almost_eq(fixture.base_of(HEALTH), before, TOLERANCE, "untouched")
	assert_signal_not_emitted(asc, "attribute_changed")
#endregion


#region Status codes
func test_a_null_spec_reports_invalid_spec() -> void:
	var request: GameplayEffectEvaluator.Request = Evaluator.Request.new()
	request.attributes = asc.attributes
	var result: GameplayEffectEvaluationResult = Evaluator.evaluate(request)
	assert_eq(result.status, AttributeEvaluationResult.Status.INVALID_SPEC)


func test_a_zero_divisor_reports_division_by_zero() -> void:
	var result: GameplayEffectEvaluationResult = _evaluate(
		Factory.infinite([Factory.divide(ATTACK, 0.0)]), Evaluator.Mode.CONTRIBUTION
	)
	assert_eq(result.status, AttributeEvaluationResult.Status.DIVISION_BY_ZERO)
	assert_eq(result.error_attribute_name, ATTACK)


func test_a_failed_evaluation_carries_no_staged_work() -> void:
	var result: GameplayEffectEvaluationResult = _evaluate(
		Factory.infinite([Factory.add(ATTACK, 5.0), Factory.divide(ATTACK, 0.0)]),
		Evaluator.Mode.CONTRIBUTION
	)
	assert_false(result.is_ok())
	# A caller that reads the arrays without checking the status must still find
	# nothing to commit.
	assert_eq(result.contributions.size(), 0, "no contributions survive a failure")
	assert_eq(result.base_mutations.size(), 0, "and no staged writes")
#endregion
