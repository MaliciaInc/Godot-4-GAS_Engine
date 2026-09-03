## Attribute captures: what an execution calculation reads, from whom, and
## when it is frozen.
##
## SOURCE/TARGET and BASE/CURRENT are exercised directly against
## GameplayEffectSpec's own capture API - precise, and needs no full
## application. SNAPSHOT-vs-LIVE-across-an-AoE and "a failed capture refuses
## everything" need the real pipeline, so those go through Factory.apply()
## and apply_effect_spec_to_target() instead.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Factory = preload("res://test/fixtures/test_effect_factory.gd")

const TOLERANCE: float = 0.0001
const ATTACK: StringName = &"attack"
const HEALTH: StringName = &"health"

var source: ASCFixture = null
var target: ASCFixture = null


## Records what resolve_capture actually answered for each definition it was
## asked about, so a test can inspect them after execute() has already run -
## proof that preparation happened before execute(), not lazily inside it.
class CapturingCalculation extends GameplayExecutionCalculation:
	var definitions: Array[GameplayAttributeCaptureDefinition] = []
	var last_results: Dictionary[GameplayAttributeCaptureDefinition, AttributeCaptureResult] = {}

	func required_captures() -> Array[GameplayAttributeCaptureDefinition]:
		return definitions

	func execute(
		spec: GameplayEffectSpec, target_asc: AbilitySystemComponent
	) -> Dictionary[StringName, float]:
		for definition: GameplayAttributeCaptureDefinition in definitions:
			last_results[definition] = spec.resolve_capture(definition, spec.source_asc, target_asc)
		return {}


func before_each() -> void:
	source = Fixture.create("Source")
	target = Fixture.create("Target")
	add_child_autofree(source.owner)
	add_child_autofree(target.owner)


func after_each() -> void:
	source = null
	target = null


func _spec() -> GameplayEffectSpec:
	var effect: GameplayEffect = Factory.instant([])
	var context: GameplayEffectContext = GameplayEffectContext.new(source.owner)
	var spec: GameplayEffectSpec = GameplayEffectSpec.new(effect, context)
	spec.source_asc = source.asc
	return spec


#region Snapshot: BASE and CURRENT, SOURCE and TARGET
## One shape, four questions: which actor and which of its two values a
## SNAPSHOT capture reads. Both source and target carry a base value and an
## active buff over it, so BASE and CURRENT can only agree by coincidence.
class SnapshotCase extends RefCounted:
	var actor: GameplayAttributeCaptureDefinition.Actor
	var value: GameplayAttributeCaptureDefinition.Value
	var expected: float
	var label: String

	func _init(
		in_actor: GameplayAttributeCaptureDefinition.Actor,
		in_value: GameplayAttributeCaptureDefinition.Value,
		in_expected: float,
		in_label: String
	) -> void:
		actor = in_actor
		value = in_value
		expected = in_expected
		label = in_label


func _snapshot_cases() -> Array[SnapshotCase]:
	return [
		SnapshotCase.new(
			GameplayAttributeCaptureDefinition.Actor.SOURCE,
			GameplayAttributeCaptureDefinition.Value.BASE,
			40.0,
			"source base"
		),
		SnapshotCase.new(
			GameplayAttributeCaptureDefinition.Actor.SOURCE,
			GameplayAttributeCaptureDefinition.Value.CURRENT,
			140.0,
			"source current: base plus the buff"
		),
		SnapshotCase.new(
			GameplayAttributeCaptureDefinition.Actor.TARGET,
			GameplayAttributeCaptureDefinition.Value.BASE,
			60.0,
			"target base"
		),
		SnapshotCase.new(
			GameplayAttributeCaptureDefinition.Actor.TARGET,
			GameplayAttributeCaptureDefinition.Value.CURRENT,
			90.0,
			"target current: base plus the buff"
		),
	] as Array[SnapshotCase]


func test_a_snapshot_captures_the_named_actors_named_value(
	case: SnapshotCase = use_parameters(_snapshot_cases())
) -> void:
	source.set_base(ATTACK, 40.0)
	Factory.apply(source.asc, Factory.infinite([Factory.add(ATTACK, 100.0)]))
	target.set_base(HEALTH, 60.0)
	Factory.apply(target.asc, Factory.infinite([Factory.add(HEALTH, 30.0)]))

	var per_source: bool = case.actor == GameplayAttributeCaptureDefinition.Actor.SOURCE
	var attribute_name: StringName = ATTACK if per_source else HEALTH
	var definition: GameplayAttributeCaptureDefinition = Factory.capture_definition(case.actor, attribute_name, case.value)
	var spec: GameplayEffectSpec = _spec()
	spec.register_capture(definition)
	if per_source:
		spec.capture_source_attributes(source.asc)
	else:
		spec.capture_target_attributes(target.asc)

	var result: AttributeCaptureResult = spec.resolve_capture(definition, source.asc, target.asc)
	assert_true(result.is_ok(), case.label)
	assert_almost_eq(result.value, case.expected, TOLERANCE, case.label)


func test_a_snapshot_does_not_change_after_the_source_moves_on() -> void:
	source.set_base(ATTACK, 40.0)
	var definition: GameplayAttributeCaptureDefinition = Factory.capture_definition(
		GameplayAttributeCaptureDefinition.Actor.SOURCE, ATTACK, GameplayAttributeCaptureDefinition.Value.BASE
	)
	var spec: GameplayEffectSpec = _spec()
	spec.register_capture(definition)
	spec.capture_source_attributes(source.asc)

	source.set_base(ATTACK, 999.0)

	var result: AttributeCaptureResult = spec.resolve_capture(definition, source.asc, null)
	assert_almost_eq(result.value, 40.0, TOLERANCE, "frozen at the moment it was taken")
#endregion


#region Live: never frozen
func test_a_source_live_capture_tracks_the_source_as_it_changes() -> void:
	source.set_base(ATTACK, 40.0)
	var definition: GameplayAttributeCaptureDefinition = Factory.capture_definition(
		GameplayAttributeCaptureDefinition.Actor.SOURCE,
		ATTACK,
		GameplayAttributeCaptureDefinition.Value.BASE,
		GameplayAttributeCaptureDefinition.Policy.LIVE
	)
	var spec: GameplayEffectSpec = _spec()
	spec.register_capture(definition)

	var before: AttributeCaptureResult = spec.resolve_capture(definition, source.asc, null)
	source.set_base(ATTACK, 999.0)
	var after: AttributeCaptureResult = spec.resolve_capture(definition, source.asc, null)

	assert_almost_eq(before.value, 40.0, TOLERANCE)
	assert_almost_eq(after.value, 999.0, TOLERANCE, "re-read fresh, not snapshotted")


func test_a_target_live_capture_tracks_the_target_as_it_changes() -> void:
	target.set_base(HEALTH, 60.0)
	var definition: GameplayAttributeCaptureDefinition = Factory.capture_definition(
		GameplayAttributeCaptureDefinition.Actor.TARGET,
		HEALTH,
		GameplayAttributeCaptureDefinition.Value.BASE,
		GameplayAttributeCaptureDefinition.Policy.LIVE
	)
	var spec: GameplayEffectSpec = _spec()
	spec.register_capture(definition)

	var before: AttributeCaptureResult = spec.resolve_capture(definition, null, target.asc)
	target.set_base(HEALTH, 15.0)
	var after: AttributeCaptureResult = spec.resolve_capture(definition, null, target.asc)

	assert_almost_eq(before.value, 60.0, TOLERANCE)
	assert_almost_eq(after.value, 15.0, TOLERANCE, "re-read fresh, not snapshotted")
#endregion


#region Refusals
## One shape, three reasons resolve_capture can refuse without ever reaching
## an ASC's own attribute lookup: no source, no target, or a name neither
## carries.
class RefusalCase extends RefCounted:
	var actor: GameplayAttributeCaptureDefinition.Actor
	var attribute_name: StringName
	var pass_source: bool
	var pass_target: bool
	var expected_status: AttributeCaptureResult.Status

	func _init(
		in_actor: GameplayAttributeCaptureDefinition.Actor,
		in_attribute_name: StringName,
		in_pass_source: bool,
		in_pass_target: bool,
		in_expected_status: AttributeCaptureResult.Status
	) -> void:
		actor = in_actor
		attribute_name = in_attribute_name
		pass_source = in_pass_source
		pass_target = in_pass_target
		expected_status = in_expected_status


func _refusal_cases() -> Array[RefusalCase]:
	return [
		RefusalCase.new(
			GameplayAttributeCaptureDefinition.Actor.SOURCE,
			ATTACK,
			false,
			true,
			AttributeCaptureResult.Status.SOURCE_MISSING
		),
		RefusalCase.new(
			GameplayAttributeCaptureDefinition.Actor.TARGET,
			HEALTH,
			true,
			false,
			AttributeCaptureResult.Status.TARGET_MISSING
		),
		RefusalCase.new(
			GameplayAttributeCaptureDefinition.Actor.SOURCE,
			&"no_such_attribute",
			true,
			true,
			AttributeCaptureResult.Status.ATTRIBUTE_NOT_FOUND
		),
	] as Array[RefusalCase]


func test_a_capture_reports_why_it_could_not_resolve(
	case: RefusalCase = use_parameters(_refusal_cases())
) -> void:
	var definition: GameplayAttributeCaptureDefinition = Factory.capture_definition(
		case.actor, case.attribute_name, GameplayAttributeCaptureDefinition.Value.CURRENT
	)
	var spec: GameplayEffectSpec = _spec()
	spec.register_capture(definition)

	var result: AttributeCaptureResult = spec.resolve_capture(
		definition,
		source.asc if case.pass_source else null,
		target.asc if case.pass_target else null
	)
	assert_eq(result.status, case.expected_status)


func test_a_non_finite_value_is_refused() -> void:
	# set_base itself refuses to ever store a non-finite value - the same
	# defence the canonical formula has elsewhere - so reaching around it
	# directly is the only way to exercise the capture's own guard.
	source.asc.get_attribute(ATTACK).base_value = INF
	var definition: GameplayAttributeCaptureDefinition = Factory.capture_definition(
		GameplayAttributeCaptureDefinition.Actor.SOURCE, ATTACK, GameplayAttributeCaptureDefinition.Value.BASE
	)
	var spec: GameplayEffectSpec = _spec()
	spec.register_capture(definition)

	var result: AttributeCaptureResult = spec.resolve_capture(definition, source.asc, null)
	assert_eq(result.status, AttributeCaptureResult.Status.NON_FINITE_VALUE)
#endregion


#region Through the real pipeline
func test_an_execution_calculation_receives_already_resolved_captures() -> void:
	source.set_base(ATTACK, 25.0)
	var definition: GameplayAttributeCaptureDefinition = Factory.capture_definition(
		GameplayAttributeCaptureDefinition.Actor.SOURCE, ATTACK, GameplayAttributeCaptureDefinition.Value.CURRENT
	)
	var calculation: CapturingCalculation = CapturingCalculation.new()
	calculation.definitions = [definition]
	var effect: GameplayEffect = Factory.instant([])
	effect.executions = [calculation] as Array[GameplayExecutionCalculation]

	Factory.apply(target.asc, effect, source.owner)

	var result: AttributeCaptureResult = calculation.last_results.get(definition)
	assert_not_null(result, "execute() asked for it and got an answer")
	assert_true(result.is_ok())
	assert_almost_eq(result.value, 25.0, TOLERANCE)


## One spec, copied for two targets - the way a real AoE hands it out. The
## SOURCE snapshot is taken once, on the shared spec, before either copy
## exists: changing the source between the two applications must not move
## it. Each copy takes its own TARGET snapshot, so those two do differ.
func test_target_a_and_b_get_independent_snapshots_from_one_shared_source() -> void:
	var target_b: ASCFixture = Fixture.create("TargetB")
	add_child_autofree(target_b.owner)
	source.set_base(ATTACK, 25.0)
	target.set_base(HEALTH, 60.0)
	target_b.set_base(HEALTH, 90.0)

	var source_capture: GameplayAttributeCaptureDefinition = Factory.capture_definition(
		GameplayAttributeCaptureDefinition.Actor.SOURCE, ATTACK, GameplayAttributeCaptureDefinition.Value.CURRENT
	)
	var target_capture: GameplayAttributeCaptureDefinition = Factory.capture_definition(
		GameplayAttributeCaptureDefinition.Actor.TARGET, HEALTH, GameplayAttributeCaptureDefinition.Value.CURRENT
	)
	var calculation: CapturingCalculation = CapturingCalculation.new()
	calculation.definitions = [source_capture, target_capture]
	var effect: GameplayEffect = Factory.instant([])
	effect.executions = [calculation] as Array[GameplayExecutionCalculation]
	var context: GameplayEffectContext = GameplayEffectContext.new(source.owner)
	var spec: GameplayEffectSpec = GameplayEffectSpec.new(effect, context)

	source.asc.apply_effect_spec_to_target(spec, target.asc)
	var source_reading_a: float = calculation.last_results[source_capture].value
	var health_reading_a: float = calculation.last_results[target_capture].value

	# Between the two applications, the source's Attack moves. The shared
	# SOURCE snapshot must not follow it - only a fresh per-target TARGET
	# reading is supposed to differ.
	source.set_base(ATTACK, 999.0)
	source.asc.apply_effect_spec_to_target(spec, target_b.asc)
	var source_reading_b: float = calculation.last_results[source_capture].value
	var health_reading_b: float = calculation.last_results[target_capture].value

	assert_almost_eq(source_reading_a, 25.0, TOLERANCE)
	assert_almost_eq(source_reading_b, 25.0, TOLERANCE, "the same shared snapshot, unmoved by the later change")
	assert_almost_eq(health_reading_a, 60.0, TOLERANCE)
	assert_almost_eq(health_reading_b, 90.0, TOLERANCE, "each target snapshotted its own")


func test_a_failed_capture_refuses_the_whole_application() -> void:
	var definition: GameplayAttributeCaptureDefinition = Factory.capture_definition(
		GameplayAttributeCaptureDefinition.Actor.SOURCE,
		&"no_such_attribute",
		GameplayAttributeCaptureDefinition.Value.CURRENT
	)
	var calculation: CapturingCalculation = CapturingCalculation.new()
	calculation.definitions = [definition]
	var effect: GameplayEffect = Factory.instant([Factory.add(HEALTH, -50.0)])
	effect.executions = [calculation] as Array[GameplayExecutionCalculation]

	var before: float = target.base_of(HEALTH)
	watch_signals(target.asc)
	var applied: ActiveGameplayEffect = Factory.apply(target.asc, effect, source.owner)

	assert_null(applied, "the missing attribute refuses the whole thing")
	assert_almost_eq(target.base_of(HEALTH), before, TOLERANCE, "the modifier never landed either")
	assert_signal_not_emitted(target.asc, "attribute_changed")
	assert_eq(calculation.last_results.size(), 0, "execute() never even ran")
#endregion
