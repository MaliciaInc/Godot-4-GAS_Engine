## The corpus that is allowed to be called parity, kept honest, and what this
## engine produces for it.
##
## The rule F6.5.3 states is a rule about words: evidence is `UE_VERIFIED` or
## `NOT_UE_VERIFIED`, and something authored from documentation is not parity.
## Nothing can check that a number came from a real Unreal run - the only thing
## standing between the corpus and a comfortable lie is whoever edits it - but
## what can be checked is that a golden claiming to be verified carries what a
## run produces, and that nothing invents a third word.
##
## The other half is written here too: what this engine produces for each
## scenario, into the file `tooling/parity_diff.py` compares against. A
## comparison with only one side is not a comparison, and the side this repo can
## produce is this one.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const EffectFactory = preload("res://test/fixtures/test_effect_factory.gd")

const GOLDENS: String = "res://test/parity/goldens"
const RESULTS: String = "res://artifacts/parity/results/ue_scenarios.json"

const UE_VERIFIED: String = "UE_VERIFIED"
const NOT_UE_VERIFIED: String = "NOT_UE_VERIFIED"

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

## Every field the phase names on a golden.
const REQUIRED: Array[String] = [
	"scenario",
	"ue_version",
	"changelist",
	"evidence",
	"inputs",
	"outputs",
	"numeric_tolerance",
	"execution_order_observable",
	"execution_order",
]

const ATTACK: StringName = &"attack"
const TOLERANCE: float = 0.0001

## What the goldens say the attribute starts at, and what the fixture declares.
## A scenario run against a different base is a scenario about something else.
const BASE_ATTACK: float = 10.0
const HEALTH: StringName = &"health"
const MAX_HEALTH: StringName = &"max_health"
const BASE_HEALTH: float = 100.0

var fixture: ASCFixture = null
var asc: AbilitySystemComponent = null


func before_each() -> void:
	fixture = Fixture.create("Referenced")
	add_child_autofree(fixture.owner)
	asc = fixture.asc
	asc.set_process(false)
	# Every golden says `profile: UE_5_7`, so every scenario is produced under
	# it. Produced under the other one, legacy MULTIPLY compounds and the
	# UE-only arms are refused outright - which is correct behaviour and a
	# different question from the one the corpus asks.
	asc.compatibility_profile.mode = GameplayCompatibilityProfile.Mode.UE_5_7
	assert_true(asc.uses_ue_5_7_contracts(), "the profile the goldens name took")


func after_each() -> void:
	fixture = null
	asc = null


#region The corpus
## Every scenario the phase names is there, and nothing else is.
func test_the_corpus_is_the_ten_scenarios_the_phase_names() -> void:
	var found: Array[String] = []
	for name: String in DirAccess.get_files_at(GOLDENS):
		if name.ends_with(".json"):
			found.append(name.get_basename())
	found.sort()

	var expected: Array[String] = SCENARIOS.duplicate()
	expected.sort()
	assert_eq(found, expected, "the corpus is exactly the ten")


## Every golden says all nine things, and says its evidence in one of two words.
##
## `AUTHORED` is not one of them, and neither is anything else. A third word is
## how a corpus comes to hold a claim nobody has to defend.
func test_every_golden_says_everything_and_invents_no_third_word() -> void:
	for scenario: String in SCENARIOS:
		var golden: Dictionary = _golden(scenario)
		for field: String in REQUIRED:
			assert_true(golden.has(field), "%s carries `%s`" % [scenario, field])

		var evidence: String = str(golden.get("evidence", ""))
		assert_true(
			evidence == UE_VERIFIED or evidence == NOT_UE_VERIFIED,
			"%s says %s, which is one of the two states" % [scenario, evidence]
		)


## A golden claiming to be verified carries what a run produces.
##
## The one thing about this corpus a machine can check. Nothing can tell whether
## a number came out of Unreal; what it can tell is that a scenario saying it
## was run has the outputs a run would have left, and - where the order is
## observable - the order it was observed in.
func test_a_verified_golden_carries_what_a_run_produces() -> void:
	var verified: int = 0
	for scenario: String in SCENARIOS:
		var golden: Dictionary = _golden(scenario)
		if str(golden.get("evidence", "")) != UE_VERIFIED:
			continue
		verified += 1
		var outputs: Variant = golden.get("outputs")
		assert_false(
			outputs == null,
			"%s says it was run and carries what the run produced" % scenario
		)
		var observable: Variant = golden.get("execution_order_observable", false)
		if observable == true:
			var order: Variant = golden.get("execution_order")
			assert_false(
				order == null,
				"%s has an observable order and says what it was" % scenario
			)

	# Reported rather than asserted: zero is the honest state today, and a test
	# that failed for it would be a test demanding a machine nobody here has.
	gut.p("UE_VERIFIED scenarios: %d of %d" % [verified, SCENARIOS.size()])
	assert_between(
		verified, 0, SCENARIOS.size(), "however many are verified, they are of the ten"
	)
#endregion


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
func _golden(scenario: String) -> Dictionary:
	var path: String = "%s/%s.json" % [GOLDENS, scenario]
	var text: String = FileAccess.get_file_as_string(path)
	assert_false(text.is_empty(), "%s is where it says it is" % scenario)

	var parser: JSON = JSON.new()
	assert_eq(parser.parse(text), OK, "%s is readable JSON" % scenario)
	var parsed: Variant = parser.data
	if parsed is Dictionary:
		var golden: Dictionary = parsed
		return golden
	return {}


func _modifier(
	operation: GameplayEffectModifier.Operation, magnitude: float, channel: int = 0
) -> GameplayEffectModifier:
	var made: GameplayEffectModifier = EffectFactory.modifier(ATTACK, operation, magnitude)
	made.evaluation_channel = channel
	return made


## One effect carrying those modifiers, applied, and what `attack` became.
##
## The whole observable outcome of a composition scenario: the value, and the
## base it did not touch.
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
