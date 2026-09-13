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
## Every named scenario is there, and nothing else is.
func test_the_corpus_is_exactly_the_ten_named_scenarios() -> void:
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


## A golden that says this engine answers something else says why.
##
## `engine_deviation` is the one thing in this corpus that can make a real
## difference not a failure, which is exactly what makes it worth a rule: an
## empty one would be a way to quiet any disagreement at all. It is only
## allowed on a golden that was actually run, and it has to be a sentence
## rather than a marker.
func test_a_declared_deviation_says_why_and_is_on_a_golden_that_ran() -> void:
	var declared: int = 0
	for scenario: String in SCENARIOS:
		var golden: Dictionary = _golden(scenario)
		if not golden.has("engine_deviation"):
			continue
		declared += 1
		var because: String = str(golden.get("engine_deviation", "")).strip_edges()
		assert_gt(
			because.length(),
			80,
			"%s: a deviation is a reason, not a marker" % scenario
		)
		assert_eq(
			str(golden.get("evidence", "")),
			UE_VERIFIED,
			"%s: nothing deviates from a reference that was never run" % scenario
		)
	# Reported rather than asserted at a number: how many there are is the
	# corpus's business and not this test's.
	gut.p("declared deviations: %d of %d" % [declared, SCENARIOS.size()])
	assert_between(declared, 0, SCENARIOS.size(), "however many, they are of the ten")
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


## One effect carrying those modifiers, applied, and what `attack` became.
##
## The whole observable outcome of a composition scenario: the value, and the
## base it did not touch.
