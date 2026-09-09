## Which reading of a captured attribute an attribute-based magnitude takes.
##
## The same capture answers more than one question - what the attribute is,
## what it durably is, only the part that is not durable, and what it was
## before the later channels ran - and the interesting property is that those
## four disagree. A suite that checked one of them would pass while the other
## three quietly answered whatever the capture happened to say.
##
## Split from test_gameplay_magnitudes.gd, which covers what a magnitude does
## with the number once it has it.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Factory = preload("res://test/fixtures/test_effect_factory.gd")
const Bench = preload("res://test/fixtures/magnitude_bench.gd")

const TOLERANCE: float = 0.0001
const ATTACK: StringName = &"attack"

var source: ASCFixture = null
var target: ASCFixture = null


func before_each() -> void:
	source = Fixture.create("Source")
	target = Fixture.create("Target")
	add_child_autofree(source.owner)
	add_child_autofree(target.owner)


func after_each() -> void:
	source = null
	target = null


## An attribute-based magnitude over the source's attack, ready to configure.
func _over_source_attack() -> GameplayAttributeBasedMagnitude:
	var magnitude: GameplayAttributeBasedMagnitude = GameplayAttributeBasedMagnitude.new()
	magnitude.capture = Factory.capture_definition(
		GameplayAttributeCaptureDefinition.Actor.SOURCE, ATTACK
	)
	magnitude.capture.policy = GameplayAttributeCaptureDefinition.Policy.LIVE
	return magnitude


## Resolve `magnitude` against a spec that has registered everything it needs.
func _resolved(magnitude: GameplayAttributeBasedMagnitude) -> GameplayMagnitudeResult:
	var spec: GameplayEffectSpec = Bench.spec(source)
	for needed: GameplayAttributeCaptureDefinition in magnitude.required_captures():
		spec.register_capture(needed)
	return magnitude.resolve(Bench.context(spec, target.asc))


## The three readings that are about one attribute, off one buffed character.
##
## Together rather than apart because the interesting thing is that they
## disagree: a base of 20 buffed to 32 is three different numbers depending on
## which question was asked, and a test of one of them alone would pass while
## the other two answered whatever the capture happened to say.
##
##     [what is being asked, the calculation, the answer]
func _reading_cases() -> Array:
	return [
		["what it is now", GameplayAttributeBasedMagnitude.Calculation.MAGNITUDE, 32.0],
		["what it durably is", GameplayAttributeBasedMagnitude.Calculation.BASE_VALUE, 20.0],
		["only the buff", GameplayAttributeBasedMagnitude.Calculation.BONUS_MAGNITUDE, 12.0],
	]


func test_a_calculation_picks_which_reading_of_the_capture_is_taken(
	case: Array = use_parameters(_reading_cases())
) -> void:
	var described: String = case[0]
	var calculation: GameplayAttributeBasedMagnitude.Calculation = case[1]
	var expected: float = case[2]

	source.set_base(ATTACK, 20.0)
	Factory.apply(source.asc, Factory.infinite([Factory.add(ATTACK, 12.0)]))
	assert_almost_eq(
		source.current_of(ATTACK), 32.0, TOLERANCE, "the buff is on"
	)

	var magnitude: GameplayAttributeBasedMagnitude = _over_source_attack()
	magnitude.calculation = calculation

	var result: GameplayMagnitudeResult = _resolved(magnitude)
	assert_true(result.is_ok(), described)
	assert_almost_eq(result.value, expected, TOLERANCE, described)


## The fourth reading: the attribute as it stood before the later channels.
##
## Two contributions on two channels, and a ceiling below the second, so the
## answer can only be right if the fold actually stopped where it was told.
func test_up_to_channel_reads_the_attribute_before_the_later_channels() -> void:
	source.asc.compatibility_profile.mode = GameplayCompatibilityProfile.Mode.UE_5_7
	assert_true(source.asc.uses_ue_5_7_contracts(), "channels only exist on this profile")
	source.set_base(ATTACK, 100.0)

	var early: GameplayEffectModifier = Factory.add(ATTACK, 10.0)
	early.evaluation_channel = 0
	var late: GameplayEffectModifier = Factory.add(ATTACK, 1000.0)
	late.evaluation_channel = 3
	Factory.apply(source.asc, Factory.infinite([early, late]))
	assert_almost_eq(
		source.current_of(ATTACK), 1110.0, TOLERANCE, "both channels count normally"
	)

	var magnitude: GameplayAttributeBasedMagnitude = _over_source_attack()
	magnitude.calculation = (
		GameplayAttributeBasedMagnitude.Calculation.MAGNITUDE_UP_TO_CHANNEL
	)
	magnitude.final_channel = 1

	var result: GameplayMagnitudeResult = _resolved(magnitude)
	assert_true(result.is_ok(), "it read something")
	assert_almost_eq(
		result.value, 110.0, TOLERANCE, "and stopped before the channel it was told to"
	)


## A magnitude with requirements is worth nothing while they do not hold, and
## worth its number the moment they do - not a refusal either way, because an
## effect that failed to apply is an effect that misses everybody who is not
## on fire.
func test_requirements_make_the_magnitude_worth_nothing_rather_than_refuse() -> void:
	source.set_base(ATTACK, 40.0)
	var magnitude: GameplayAttributeBasedMagnitude = _over_source_attack()
	magnitude.target_requirements = Factory._all_tag_query(
		[&"Status.Burning"] as Array[StringName]
	)

	var refused: GameplayMagnitudeResult = _resolved(magnitude)
	assert_true(refused.is_ok(), "it resolved rather than failing")
	assert_almost_eq(refused.value, 0.0, TOLERANCE, "and counted for nothing")

	target.asc.add_tag(&"Status.Burning")
	var counted: GameplayMagnitudeResult = _resolved(magnitude)
	assert_almost_eq(counted.value, 40.0, TOLERANCE, "and its number once it holds")


## The curve is applied to the finished number, not to the reading.
##
## 40 read, +10, x2 is 100, and the curve turns 100 into 500. A curve applied
## to the reading first would sample 40, get nothing, and land on 20 - two
## answers nobody could mistake for each other, which is the point of picking
## the numbers rather than letting them fall where they may.
func test_the_attribute_curve_is_applied_to_the_finished_number() -> void:
	source.set_base(ATTACK, 40.0)
	var magnitude: GameplayAttributeBasedMagnitude = _over_source_attack()
	magnitude.pre_add = Bench.flat(10.0)
	magnitude.coefficient = Bench.flat(2.0)
	magnitude.attribute_curve = Bench.bending_curve()

	var result: GameplayMagnitudeResult = _resolved(magnitude)
	assert_almost_eq(result.value, 500.0, TOLERANCE, "bent after the arithmetic")
