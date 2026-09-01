## Typed gameplay magnitudes: attribute-based, SetByCaller, custom, and the
## LIVE reactive binding a persistent contribution needs that INSTANT and
## PERIODIC never do.
##
## Flat and curve-scaled magnitudes are GameplayScalableFloat's own concern,
## already covered in test_gameplay_scalable_float.gd and (through a real
## modifier) test_modifier_magnitudes.gd; this file does not repeat them.
##
## @meta_license: MIT
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Factory = preload("res://test/fixtures/test_effect_factory.gd")

const TOLERANCE: float = 0.0001
const ATTACK: StringName = &"attack"
const HEALTH: StringName = &"health"
const CHARGE_TAG: StringName = &"SetByCaller.Charge"

var source: ASCFixture = null
var target: ASCFixture = null


## A custom calculation is a plain Resource, not a Node, so - like
## GameplayExecutionCalculation's own test fixtures - it can be declared
## inline here without the packing concerns a Node-based fixture would raise.
class DoubleSourceAttack extends GameplayMagnitudeCalculation:
	func calculate(context: GameplayMagnitudeContext) -> GameplayMagnitudeResult:
		if context.source_asc == null:
			return GameplayMagnitudeResult.failure(GameplayMagnitudeResult.Status.CALCULATION_FAILED)
		return GameplayMagnitudeResult.ok(context.source_asc.get_attribute_current(ATTACK) * 2.0)


class AlwaysFailsCalculation extends GameplayMagnitudeCalculation:
	func calculate(_context: GameplayMagnitudeContext) -> GameplayMagnitudeResult:
		return GameplayMagnitudeResult.failure(GameplayMagnitudeResult.Status.CALCULATION_FAILED)


class ReturnsInfinity extends GameplayMagnitudeCalculation:
	func calculate(_context: GameplayMagnitudeContext) -> GameplayMagnitudeResult:
		return GameplayMagnitudeResult.ok(INF)


func before_each() -> void:
	source = Fixture.create("Source")
	target = Fixture.create("Target")
	add_child_autofree(source.owner)
	add_child_autofree(target.owner)


func after_each() -> void:
	source = null
	target = null


#region Builders
func _flat(value: float) -> GameplayScalableFloat:
	var scalable: GameplayScalableFloat = GameplayScalableFloat.new()
	scalable.value = value
	return scalable


## A throwaway spec for testing a magnitude's resolve() directly, without a
## full application.
func _spec() -> GameplayEffectSpec:
	var effect: GameplayEffect = Factory.instant([])
	var spec: GameplayEffectSpec = GameplayEffectSpec.new(effect, GameplayEffectContext.new(source.owner))
	spec.source_asc = source.asc
	return spec


func _context(spec: GameplayEffectSpec) -> GameplayMagnitudeContext:
	var context: GameplayMagnitudeContext = GameplayMagnitudeContext.new()
	context.spec = spec
	context.source_asc = spec.source_asc
	context.target_asc = target.asc
	context.level = spec.level
	return context


#endregion


#region Attribute-based
## One shape, two actors: whichever side a SNAPSHOT capture names, resolve()
## must answer with exactly what was set there.
class SnapshotActorCase extends RefCounted:
	var actor: GameplayAttributeCaptureDefinition.Actor
	var attribute_name: StringName
	var value: float
	var label: String

	func _init(
		in_actor: GameplayAttributeCaptureDefinition.Actor,
		in_attribute_name: StringName,
		in_value: float,
		in_label: String
	) -> void:
		actor = in_actor
		attribute_name = in_attribute_name
		value = in_value
		label = in_label


func _snapshot_actor_cases() -> Array[SnapshotActorCase]:
	return [
		SnapshotActorCase.new(GameplayAttributeCaptureDefinition.Actor.SOURCE, ATTACK, 20.0, "source"),
		SnapshotActorCase.new(GameplayAttributeCaptureDefinition.Actor.TARGET, HEALTH, 60.0, "target"),
	] as Array[SnapshotActorCase]


func test_attribute_based_reads_a_snapshot_from_either_actor(
	case: SnapshotActorCase = use_parameters(_snapshot_actor_cases())
) -> void:
	var per_source: bool = case.actor == GameplayAttributeCaptureDefinition.Actor.SOURCE
	if per_source:
		source.set_base(case.attribute_name, case.value)
	else:
		target.set_base(case.attribute_name, case.value)

	var magnitude: GameplayAttributeBasedMagnitude = GameplayAttributeBasedMagnitude.new()
	magnitude.capture = Factory.capture_definition(case.actor, case.attribute_name)
	var spec: GameplayEffectSpec = _spec()
	spec.register_capture(magnitude.capture)
	if per_source:
		spec.capture_source_attributes(source.asc)
	else:
		spec.capture_target_attributes(target.asc)

	var result: GameplayMagnitudeResult = magnitude.resolve(_context(spec))
	assert_true(result.is_ok(), case.label)
	assert_almost_eq(result.value, case.value, TOLERANCE, case.label)


func test_attribute_based_applies_coefficient_pre_and_post_add() -> void:
	source.set_base(ATTACK, 10.0)
	var magnitude: GameplayAttributeBasedMagnitude = GameplayAttributeBasedMagnitude.new()
	magnitude.capture = Factory.capture_definition(GameplayAttributeCaptureDefinition.Actor.SOURCE, ATTACK)
	magnitude.pre_add = _flat(2.0)
	magnitude.coefficient = _flat(3.0)
	magnitude.post_add = _flat(1.0)
	var spec: GameplayEffectSpec = _spec()
	spec.register_capture(magnitude.capture)
	spec.capture_source_attributes(source.asc)

	var result: GameplayMagnitudeResult = magnitude.resolve(_context(spec))
	assert_true(result.is_ok())
	assert_almost_eq(result.value, 37.0, TOLERANCE, "((10 + 2) * 3) + 1")


func test_attribute_based_reports_why_its_capture_could_not_resolve() -> void:
	var magnitude: GameplayAttributeBasedMagnitude = GameplayAttributeBasedMagnitude.new()
	magnitude.capture = Factory.capture_definition(GameplayAttributeCaptureDefinition.Actor.SOURCE, &"no_such_attribute")
	var spec: GameplayEffectSpec = _spec()
	spec.register_capture(magnitude.capture)
	spec.capture_source_attributes(source.asc)

	var result: GameplayMagnitudeResult = magnitude.resolve(_context(spec))
	assert_eq(result.status, GameplayMagnitudeResult.Status.ATTRIBUTE_NOT_FOUND)
#endregion


#region SetByCaller
func test_set_by_caller_reads_the_value_the_caller_supplied() -> void:
	var spec: GameplayEffectSpec = _spec()
	assert_true(spec.set_set_by_caller(CHARGE_TAG, 42.0))

	var magnitude: GameplaySetByCallerMagnitude = GameplaySetByCallerMagnitude.new()
	magnitude.data_tag = CHARGE_TAG
	var result: GameplayMagnitudeResult = magnitude.resolve(_context(spec))
	assert_true(result.is_ok())
	assert_almost_eq(result.value, 42.0, TOLERANCE)


func test_a_required_set_by_caller_never_supplied_is_refused() -> void:
	var spec: GameplayEffectSpec = _spec()
	var magnitude: GameplaySetByCallerMagnitude = GameplaySetByCallerMagnitude.new()
	magnitude.data_tag = CHARGE_TAG
	magnitude.require_value = true

	var result: GameplayMagnitudeResult = magnitude.resolve(_context(spec))
	assert_eq(result.status, GameplayMagnitudeResult.Status.MISSING_SET_BY_CALLER)


func test_an_optional_set_by_caller_falls_back_to_its_default() -> void:
	var spec: GameplayEffectSpec = _spec()
	var magnitude: GameplaySetByCallerMagnitude = GameplaySetByCallerMagnitude.new()
	magnitude.data_tag = CHARGE_TAG
	magnitude.require_value = false
	magnitude.default_value = 7.0

	var result: GameplayMagnitudeResult = magnitude.resolve(_context(spec))
	assert_true(result.is_ok())
	assert_almost_eq(result.value, 7.0, TOLERANCE)


func test_set_by_caller_is_isolated_per_target_copy() -> void:
	var spec: GameplayEffectSpec = _spec()
	spec.set_set_by_caller(CHARGE_TAG, 10.0)
	var copy_a: GameplayEffectSpec = spec.create_application_copy()
	var copy_b: GameplayEffectSpec = spec.create_application_copy()

	copy_a.set_set_by_caller(CHARGE_TAG, 999.0)

	assert_almost_eq(copy_a.get_set_by_caller(CHARGE_TAG).value, 999.0, TOLERANCE, "A's own override")
	assert_almost_eq(copy_b.get_set_by_caller(CHARGE_TAG).value, 10.0, TOLERANCE, "B untouched")
	assert_almost_eq(spec.get_set_by_caller(CHARGE_TAG).value, 10.0, TOLERANCE, "original untouched")


func test_set_by_caller_is_sealed_once_evaluation_begins() -> void:
	target.set_base(HEALTH, 100.0)
	var magnitude: GameplaySetByCallerMagnitude = GameplaySetByCallerMagnitude.new()
	magnitude.data_tag = CHARGE_TAG
	var modifier: GameplayEffectModifier = Factory.modifier(HEALTH, GameplayEffectModifier.Operation.ADD, 0.0)
	modifier.magnitude = magnitude
	var effect: GameplayEffect = Factory.instant([modifier])
	var spec: GameplayEffectSpec = GameplayEffectSpec.new(effect, GameplayEffectContext.new(source.owner))
	spec.set_set_by_caller(CHARGE_TAG, -20.0)

	target.asc.apply_effect_spec(spec)

	assert_false(spec.set_set_by_caller(CHARGE_TAG, -999.0), "refused once evaluation has begun")
	assert_almost_eq(target.base_of(HEALTH), 80.0, TOLERANCE, "the charge applied was the sealed one")
#endregion


#region Custom
func test_a_custom_calculation_produces_its_own_value() -> void:
	source.set_base(ATTACK, 15.0)
	var magnitude: GameplayCustomMagnitude = GameplayCustomMagnitude.new()
	magnitude.calculation = DoubleSourceAttack.new()

	var result: GameplayMagnitudeResult = magnitude.resolve(_context(_spec()))
	assert_true(result.is_ok())
	assert_almost_eq(result.value, 30.0, TOLERANCE)


func test_a_failing_custom_calculation_refuses() -> void:
	var magnitude: GameplayCustomMagnitude = GameplayCustomMagnitude.new()
	magnitude.calculation = AlwaysFailsCalculation.new()

	var result: GameplayMagnitudeResult = magnitude.resolve(_context(_spec()))
	assert_eq(result.status, GameplayMagnitudeResult.Status.CALCULATION_FAILED)


func test_a_non_finite_custom_result_is_refused() -> void:
	var magnitude: GameplayCustomMagnitude = GameplayCustomMagnitude.new()
	magnitude.calculation = ReturnsInfinity.new()

	var result: GameplayMagnitudeResult = magnitude.resolve(_context(_spec()))
	assert_eq(result.status, GameplayMagnitudeResult.Status.NON_FINITE_VALUE)
#endregion
