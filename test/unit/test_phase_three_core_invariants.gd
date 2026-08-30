## Cross-subsystem invariants Phase 3 must not disturb.
##
## Every single-subsystem invariant this task's document lists already has an
## owner - the canonical formula in test_attribute_aggregation.gd, clamps in
## test_effect_lifecycle.gd, periodic/turn timing in test_periodic_effects.gd,
## spec isolation, event hierarchy, tag matching, target dedupe, and bridge
## availability each in their own file. Repeating their assertions here would
## be two owners for one fact, so this file holds only what needs more than
## one subsystem at once and was not already proven together:
##
##   - the transactional cleanse this task's document mandates, because a
##     refused incoming effect leaving a purge applied is exactly the kind of
##     "total refusal" violation the rest of this file's siblings exist to
##     catch, and nothing tested it before this fix existed;
##   - a Task 1 percentage cost charge composing correctly with an ordinary
##     MULTIPLY contribution on the same attribute, because Task 1 added a
##     second way to move an attribute and the canonical formula must not
##     know or care which one moved it.
##
## @meta_license: MIT
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Factory = preload("res://test/fixtures/test_effect_factory.gd")
const Probe = preload("res://test/fixtures/probe_ability.gd")

const TOLERANCE: float = 0.0001
const ATTACK: StringName = &"attack"
const HEALTH: StringName = &"health"
const BUFF_TAG: StringName = &"State.Buffed"
const PROBE_TAG: StringName = &"Ability.Probe"

var fixture: ASCFixture = null
var asc: AbilitySystemComponent = null


## Reads the target's own current Attack at evaluation time, so a test can
## tell whether that read happened before or after a purge ran.
class ReadsCurrentAttack extends GameplayExecutionCalculation:
	func execute(
		_spec: GameplayEffectSpec, target_asc: AbilitySystemComponent
	) -> Dictionary[StringName, float]:
		var produced: Dictionary[StringName, float] = {}
		produced[HEALTH] = -target_asc.get_attribute_current(ATTACK)
		return produced


func before_each() -> void:
	fixture = Fixture.create("Subject")
	add_child_autofree(fixture.owner)
	asc = fixture.asc


func after_each() -> void:
	fixture = null
	asc = null


#region The transactional cleanse
## A refused incoming effect must leave a purge it declared exactly undone:
## same object, same tag refs, same contributions, same attribute values, and
## not one signal for either side of an application that, as a whole, never
## happened.
func test_a_cleanser_whose_incoming_effect_fails_is_rolled_back() -> void:
	fixture.set_base(ATTACK, 10.0)
	var buff: ActiveGameplayEffect = Factory.apply(
		asc, Factory.granting(Factory.infinite([Factory.add(ATTACK, 5.0)]), [BUFF_TAG])
	)
	assert_almost_eq(fixture.current_of(ATTACK), 15.0, TOLERANCE, "buffed")

	var broken: GameplayEffect = Factory.instant([Factory.divide(HEALTH, 0.0)])
	broken.remove_effects_with_tags = [BUFF_TAG]

	watch_signals(asc)
	var result: ActiveGameplayEffect = Factory.apply(asc, broken)

	assert_null(result, "the incoming effect's own math refuses it")
	assert_eq(asc.get_active_effects(), [buff] as Array[ActiveGameplayEffect], "the same object")
	assert_true(asc.has_tag(BUFF_TAG), "its tag is back")
	assert_eq(buff.granted_tags, [BUFF_TAG] as Array[StringName], "same tag refs")
	assert_eq(buff.contributed_modifiers.size(), 1, "same contribution")
	assert_almost_eq(fixture.base_of(ATTACK), 10.0, TOLERANCE, "base untouched")
	assert_almost_eq(fixture.current_of(ATTACK), 15.0, TOLERANCE, "current untouched")
	assert_signal_not_emitted(asc, "active_effect_removed", "the purge never happened")
	assert_signal_not_emitted(asc, "tag_removed", "")
	assert_signal_not_emitted(asc, "attribute_changed", "")


## A cleanser that succeeds evaluates the incoming effect against the state
## the purge leaves behind, not the state before it: an execution reading the
## target's current Attack sees the purged value, not the buffed one.
func test_a_cleanser_that_succeeds_evaluates_against_the_post_purge_state() -> void:
	fixture.set_base(ATTACK, 10.0)
	fixture.set_base(HEALTH, 100.0)
	Factory.apply(asc, Factory.granting(Factory.infinite([Factory.add(ATTACK, 10.0)]), [BUFF_TAG]))
	assert_almost_eq(fixture.current_of(ATTACK), 20.0, TOLERANCE, "buffed to 20")

	var incoming: GameplayEffect = Factory.instant([])
	incoming.remove_effects_with_tags = [BUFF_TAG]
	incoming.executions = [ReadsCurrentAttack.new()] as Array[GameplayExecutionCalculation]

	var result: ActiveGameplayEffect = Factory.apply(asc, incoming)

	assert_not_null(result, "well formed, so it applies")
	assert_false(asc.has_tag(BUFF_TAG), "the buff is gone")
	# Had the execution read Attack before the purge, it would have taken 20;
	# reading the post-purge value takes exactly the unbuffed 10.
	assert_almost_eq(fixture.base_of(HEALTH), 90.0, TOLERANCE, "damage read the purged Attack")
#endregion


#region A Task 1 cost composes with the canonical formula
## An absolute cost charge is a plain base mutation like any other INSTANT
## effect: it does not bypass or reorder the canonical formula, so a MULTIPLY
## contribution already active on the same attribute still applies to the new
## base afterward.
func test_a_percentage_cost_composes_with_an_active_multiplier() -> void:
	fixture.set_base(ATTACK, 100.0)
	Factory.apply(asc, Factory.infinite([Factory.multiply(ATTACK, 2.0)]))
	assert_almost_eq(fixture.current_of(ATTACK), 200.0, TOLERANCE, "doubled before any cost")

	var cost: GameplayAbilityCost = GameplayAbilityCost.new()
	cost.mode = GameplayAbilityCost.Mode.PERCENT_OF_BASE
	cost.target_attribute = ATTACK
	cost.reference_attribute = ATTACK
	cost.amount = GameplayScalableFloat.new()
	cost.amount.value = 0.25

	var ability: ProbeAbility = Probe.build(PROBE_TAG)
	ability.costs = [cost]
	asc.grant_ability(ability)

	var committed: AbilityCommitResult = ability.commit_ability()
	assert_true(committed.is_ok(), "25% of a base of 100 is affordable")
	assert_almost_eq(fixture.base_of(ATTACK), 75.0, TOLERANCE, "25 taken from base by the cost")
	assert_almost_eq(
		fixture.current_of(ATTACK), 150.0, TOLERANCE, "the surviving multiplier still applies: 75 * 2"
	)
#endregion
