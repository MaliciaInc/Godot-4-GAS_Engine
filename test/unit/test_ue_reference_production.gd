## What this engine answers for each of the ten reference scenarios.
##
## Split from test_ue_reference_corpus.gd, which checks that the corpus says
## everything it must. That is a different question from running this engine
## through it, and the second one grew a great deal when the UE 5.7.4 run gave
## the last five scenarios a shape to answer in.
##
## Everything here is produced under the UE_5_7 compatibility profile, which
## is what every golden names. Under the other one the legacy names compound
## and the UE-only arms are refused outright - correct behaviour, and a
## different question from the one the corpus asks.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const EffectFactory = preload("res://test/fixtures/test_effect_factory.gd")

## The ten the phase names, so a scenario quietly deleted is noticed.
const SCENARIOS: Array[String] = [
	"legacy_multiply_one_and_a_half_twice",
	"multiply_compound_one_and_a_half_twice",
	"legacy_divide",
	"double_override_same_channel",
	"override_across_channels",
	"short_inhibition_with_execute_and_reset_period",
	"stack_count_factor_off_and_on",
	"modifier_source_and_target_tag_qualification",
	"bonus_magnitude",
	"magnitude_up_to_channel",
]

const RESULTS: String = "res://artifacts/parity/results/ue_scenarios.json"

const ATTACK: StringName = &"attack"
const HEALTH: StringName = &"health"
const MAX_HEALTH: StringName = &"max_health"
const BASE_ATTACK: float = 10.0
const BASE_HEALTH: float = 100.0
const TOLERANCE: float = 0.0001

var fixture: ASCFixture = null
var asc: AbilitySystemComponent = null


func before_each() -> void:
	fixture = Fixture.create("Produced")
	add_child_autofree(fixture.owner)
	asc = fixture.asc
	asc.set_process(false)
	asc.compatibility_profile.mode = GameplayCompatibilityProfile.Mode.UE_5_7
	assert_true(asc.uses_ue_5_7_contracts(), "the profile the goldens name took")


func after_each() -> void:
	fixture = null
	asc = null


#region What this engine produces
## What this engine does for each scenario, written where the diff reads it.
##
## Five of the ten are one application of one effect and are produced here. The
## other five need a timeline, a capture or a stack the reference decides the
## shape of, and are written as null with the reason - a produced number that
## was a guess would be the same lie the corpus exists to refuse, told on this
## side of it.
func test_what_this_engine_produces_is_written_where_the_diff_reads_it() -> void:
	var produced: Dictionary = {}
	produced["legacy_multiply_one_and_a_half_twice"] = _composed(
		[
			_modifier(GameplayEffectModifier.Operation.MULTIPLY, 1.5),
			_modifier(GameplayEffectModifier.Operation.MULTIPLY, 1.5),
		]
	)
	produced["multiply_compound_one_and_a_half_twice"] = _composed(
		[
			_modifier(GameplayEffectModifier.Operation.MULTIPLY_COMPOUND, 1.5),
			_modifier(GameplayEffectModifier.Operation.MULTIPLY_COMPOUND, 1.5),
		]
	)
	produced["legacy_divide"] = _composed(
		[_modifier(GameplayEffectModifier.Operation.DIVIDE, 2.0)]
	)
	produced["double_override_same_channel"] = _composed(
		[
			_modifier(GameplayEffectModifier.Operation.OVERRIDE, 40.0),
			_modifier(GameplayEffectModifier.Operation.OVERRIDE, 70.0),
		]
	)
	produced["override_across_channels"] = _composed(
		[
			_modifier(GameplayEffectModifier.Operation.OVERRIDE, 40.0, 0),
			_modifier(GameplayEffectModifier.Operation.OVERRIDE, 70.0, 1),
		]
	)
	produced["stack_count_factor_off_and_on"] = _stacked()
	produced["bonus_magnitude"] = _bonus_magnitude()
	produced["magnitude_up_to_channel"] = _up_to_channel()
	produced["modifier_source_and_target_tag_qualification"] = _qualified()
	produced["short_inhibition_with_execute_and_reset_period"] = _inhibited()
	for scenario: String in SCENARIOS:
		if not produced.has(scenario):
			produced[scenario] = null

	for scenario: String in SCENARIOS:
		assert_true(produced.has(scenario), "%s has a place in the results" % scenario)
	var decides_d11: Variant = produced["double_override_same_channel"]
	assert_false(
		decides_d11 == null,
		"the scenario that decides D-11 is one this engine can answer for"
	)
	# Every scenario this engine answered for landed. A produced entry whose
	# application was refused says nothing about arithmetic.
	for scenario: String in SCENARIOS:
		var entry: Variant = produced[scenario]
		if entry == null:
			continue
		var outcome: Dictionary = entry
		# A scenario with variants says `applied` once per variant. Reading
		# only the top level called every one of them a refusal.
		var readings: Array = []
		if outcome.has("variants"):
			var listed: Array = outcome["variants"]
			readings.assign(listed)
		else:
			readings.append(outcome)
		for one: Variant in readings:
			var reading: Dictionary = one
			var landed: bool = reading.get("applied", false)
			assert_true(landed, "%s was applied rather than refused" % scenario)

	produced["_about"] = (
		"What this engine produces, written by "
		+ "test/unit/test_ue_reference_corpus.gd, under the UE_5_7 compatibility "
		+ "profile, which is what every golden names: under the other one the "
		+ "legacy names compound and the UE-only arms are refused outright, "
		+ "which is correct behaviour and a different question. A null is a "
		+ "scenario this engine cannot answer for without deciding something "
		+ "the reference is supposed to decide."
	)
	_write(produced)
	assert_true(FileAccess.file_exists(RESULTS), "and the results are written down")
#endregion

#region Getting there
func _modifier(
	operation: GameplayEffectModifier.Operation, magnitude: float, channel: int = 0
) -> GameplayEffectModifier:
	var made: GameplayEffectModifier = EffectFactory.modifier(ATTACK, operation, magnitude)
	made.evaluation_channel = channel
	return made

func _composed(modifiers: Array[GameplayEffectModifier]) -> Dictionary:
	# From nothing, every time. Five scenarios sharing one character composed on
	# top of each other, and a divide by two came back as 11.25 - a number that
	# looks like a measurement and is the sum of five scenarios.
	asc.effects.cleanup()
	assert_eq(asc.effects.active_count(), 0, "nothing is left from the last scenario")
	assert_almost_eq(
		asc.get_attribute_current(ATTACK), BASE_ATTACK, TOLERANCE,
		"and the attribute is back where it started"
	)

	var typed: Array[GameplayEffectModifier] = []
	typed.assign(modifiers)
	var applied: ActiveGameplayEffect = asc.apply_gameplay_effect(
		EffectFactory.infinite(typed), asc, 1.0
	)
	# Whether it landed, not only what the attribute reads. An application the
	# engine refused leaves the attribute exactly where it was, and recording
	# that as an outcome is recording a refusal as a measurement - which the
	# first version of this did, and it read as "compound multiplication does
	# nothing".
	return {
		"applied": applied != null,
		"attack_current": asc.get_attribute_current(ATTACK),
		"attack_base": asc.get_attribute_base(ATTACK),
	}


## Three applications of one effect, with the stack count out and then in.
##
## Produced now that the reference has decided the shape, which is what these
## three were waiting for rather than anything this engine could not do.
func _stacked() -> Dictionary:
	var variants: Array = []
	for factored: bool in [false, true]:
		_from_nothing()
		var typed: Array[GameplayEffectModifier] = []
		typed.append(_modifier(GameplayEffectModifier.Operation.ADD, 5.0))
		var effect: GameplayEffect = EffectFactory.infinite(typed)
		effect.stacking_type = GameplayEffect.StackingType.AGGREGATE_BY_TARGET
		effect.stack_limit_count = 3
		effect.factor_in_stack_count = factored
		var applied: ActiveGameplayEffect = null
		for again: int in 3:
			applied = asc.apply_gameplay_effect(effect, asc, 1.0)
		variants.append(_attack_reading(applied != null))
	return {"variants": variants}


## A captured magnitude composing its coefficients.
func _bonus_magnitude() -> Dictionary:
	_from_nothing()
	var typed: Array[GameplayEffectModifier] = []
	# Through the factory, which is where a modifier is built in these tests.
	var carried: GameplayEffectModifier = EffectFactory.modifier(
		HEALTH, GameplayEffectModifier.Operation.ADD, 0.0
	)
	carried.magnitude = _reading_of_attack(
		GameplayAttributeBasedMagnitude.Calculation.BONUS_MAGNITUDE, 2.0, 1.0, 3.0, 0
	)
	typed.append(carried)
	var applied: ActiveGameplayEffect = asc.apply_gameplay_effect(
		EffectFactory.infinite(typed), asc, 1.0
	)
	return _health_reading(applied != null)


## A captured magnitude read only as far as one channel.
func _up_to_channel() -> Dictionary:
	_from_nothing()
	var typed: Array[GameplayEffectModifier] = []
	typed.append(_modifier(GameplayEffectModifier.Operation.ADD, 5.0, 0))
	typed.append(_modifier(GameplayEffectModifier.Operation.ADD, 100.0, 2))
	var carried: GameplayEffectModifier = EffectFactory.modifier(
		HEALTH, GameplayEffectModifier.Operation.ADD, 0.0
	)
	carried.magnitude = _reading_of_attack(
		GameplayAttributeBasedMagnitude.Calculation.MAGNITUDE_UP_TO_CHANNEL,
		-1.0,
		0.0,
		0.0,
		1
	)
	carried.evaluation_channel = 3
	typed.append(carried)
	var applied: ActiveGameplayEffect = asc.apply_gameplay_effect(
		EffectFactory.infinite(typed), asc, 1.0
	)
	var said: Dictionary = _health_reading(applied != null)
	said["attack_current"] = asc.get_attribute_current(ATTACK)
	said["attack_base"] = asc.get_attribute_base(ATTACK)
	return said


## Two modifiers, each counting only when one side carries a tag.
##
## Under an infinite effect, which is what every scenario in this corpus
## applies. That matters here more than anywhere else: Unreal recomputes a
## persistent aggregator with no source or target tags at all - its own
## GameplayEffect.cpp says so where it does it, `this is not an execution, so
## there are no 'source' and 'target' tags to fill out` - so neither
## qualified modifier ever counts there, whatever either side is wearing.
## Asked as an execution the reference answers 10, 15, 17 and 22.
func _qualified() -> Dictionary:
	var variants: Array = []
	for wearing: Array in [
		[false, false], [true, false], [false, true], [true, true]
	]:
		var on_target: bool = wearing[0]
		var on_source: bool = wearing[1]
		var caster: ASCFixture = Fixture.create("Caster")
		add_child_autofree(caster.owner)
		_from_nothing()
		if on_target:
			asc.add_tag(&"Status.Burning")
		if on_source:
			caster.asc.add_tag(&"Status.Empowered")

		var needs_burning: GameplayEffectModifier = EffectFactory.modifier(
			ATTACK, GameplayEffectModifier.Operation.ADD, 5.0
		)
		needs_burning.target_requirements = _needing(&"Status.Burning")
		var needs_empowered: GameplayEffectModifier = EffectFactory.modifier(
			ATTACK, GameplayEffectModifier.Operation.ADD, 7.0
		)
		needs_empowered.source_requirements = _needing(&"Status.Empowered")
		var typed: Array[GameplayEffectModifier] = [needs_burning, needs_empowered]

		var applied: ActiveGameplayEffect = asc.apply_gameplay_effect(
			EffectFactory.infinite(typed), caster.asc, 1.0
		)
		variants.append(_attack_reading(applied != null))
		asc.remove_tag(&"Status.Burning")
	return {"variants": variants}


## A query that is met only by holding that one tag.
func _needing(tag: StringName) -> GameplayTagQuery:
	var expression: GameplayTagQueryExpression = GameplayTagQueryExpression.new()
	expression.operator = GameplayTagQueryExpression.Operator.ALL
	var held: Array[StringName] = [tag]
	expression.tags = held
	var query: GameplayTagQuery = GameplayTagQuery.new()
	query.root = expression
	return query


## A periodic effect inhibited for part of one period.
##
## The golden's timeline, each event once: applied at 0, inhibited at 0.4,
## uninhibited at 0.7, read at 2.5. Inhibition is a requirement the target
## stops meeting, because that is the only way a test can turn it on and off.
func _inhibited() -> Dictionary:
	_from_nothing()
	asc.add_tag(&"Status.Uninhibited")
	var typed: Array[GameplayEffectModifier] = []
	typed.append(EffectFactory.modifier(
		HEALTH, GameplayEffectModifier.Operation.ADD, -5.0
	))
	var effect: GameplayEffect = EffectFactory.with_ongoing_requirement(
		EffectFactory.infinite_periodic(typed, 1.0), [&"Status.Uninhibited"]
	)
	effect.period_inhibition_policy = (
		GameplayEffect.PeriodInhibitionPolicy.EXECUTE_IMMEDIATELY_ON_UNINHIBIT
	)
	# On, because Unreal's is on by default and this scenario is about what
	# Unreal did. This engine's default is off - the first tick comes a full
	# period later - and its own header says so.
	effect.execute_periodic_on_application = true

	var applied: ActiveGameplayEffect = asc.apply_gameplay_effect(effect, asc, 1.0)
	asc.scheduler.advance_time(0.4)
	asc.remove_tag(&"Status.Uninhibited")
	asc.scheduler.advance_time(0.3)
	asc.add_tag(&"Status.Uninhibited")
	asc.scheduler.advance_time(1.8)
	return _health_reading(applied != null)

## A reading of attack, composed the way the goldens describe one.
func _reading_of_attack(
	calculation: GameplayAttributeBasedMagnitude.Calculation,
	coefficient: float,
	pre_add: float,
	post_add: float,
	final_channel: int
) -> GameplayAttributeBasedMagnitude:
	var capture: GameplayAttributeCaptureDefinition = (
		GameplayAttributeCaptureDefinition.new()
	)
	capture.actor = GameplayAttributeCaptureDefinition.Actor.TARGET
	capture.attribute_name = ATTACK
	capture.value = GameplayAttributeCaptureDefinition.Value.CURRENT
	capture.policy = GameplayAttributeCaptureDefinition.Policy.LIVE

	var reading: GameplayAttributeBasedMagnitude = (
		GameplayAttributeBasedMagnitude.new()
	)
	reading.capture = capture
	reading.calculation = calculation
	reading.final_channel = final_channel
	reading.coefficient = _number(coefficient)
	reading.pre_add = _number(pre_add)
	reading.post_add = _number(post_add)
	return reading



func _number(value: float) -> GameplayScalableFloat:
	var made: GameplayScalableFloat = GameplayScalableFloat.new()
	made.value = value
	return made


## Back to a character nothing has been applied to.
func _from_nothing() -> void:
	asc.effects.cleanup()
	asc.set_attribute_base(ATTACK, BASE_ATTACK)
	# The fixture's health is clamped to its max_health, and the goldens have
	# no such attribute: a scenario that added five to a full character
	# measured the clamp and was recorded as a parity difference. Lifted so
	# the reading is of the arithmetic the scenario is about.
	asc.set_attribute_base(MAX_HEALTH, 100000.0)
	asc.set_attribute_base(HEALTH, BASE_HEALTH)


func _attack_reading(landed: bool) -> Dictionary:
	return {
		"applied": landed,
		"attack_current": asc.get_attribute_current(ATTACK),
		"attack_base": asc.get_attribute_base(ATTACK),
	}


func _health_reading(landed: bool) -> Dictionary:
	return {
		"applied": landed,
		"health_current": asc.get_attribute_current(HEALTH),
		"health_base": asc.get_attribute_base(HEALTH),
	}

## What this engine produced, and what it did not produce and why.
func _write(produced: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(RESULTS.get_base_dir())
	var file: FileAccess = FileAccess.open(RESULTS, FileAccess.WRITE)
	assert_not_null(file, "the results file opened for writing")
	if file == null:
		return
	file.store_string(JSON.stringify(produced, "  ", false))
	file.close()
#endregion
