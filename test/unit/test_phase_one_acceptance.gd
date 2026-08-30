## Section 13 of the phase plan, as assertions instead of prose.
##
## The plan closes by listing eight questions the engine must answer
## deterministically. Four come with exact numbers that nothing else in the
## suite asserts; the other four are already answered by tests organised around
## the mechanism. Only the first four are re-asked here.
##
## Re-asserting the rest would be duplication, and the duplication gate said so
## when the first version of this file did it. They are mapped instead, which is
## what a reader of section 13 actually needs - somewhere to go:
##
##     "three targets with different defences"
##         -> test_spec_isolation.gd::test_each_target_computes_against_its_own_attributes
##     "a tick happens three times during a long frame"
##         -> test_periodic_effects.gd::test_a_long_frame_pays_every_tick_it_owes
##     "a cost is not payable"
##         -> test_cost_preview.gd::test_the_preview_agrees_with_the_commit
##            and test_ability_input.gd::test_a_press_cannot_pay_a_cost_the_owner_cannot_afford
##     "a max-health buff expires"
##         -> test_effect_lifecycle.gd::test_losing_the_buff_discards_the_excess_permanently
##
## The numbers below are the plan's, copied from it rather than recomputed: a
## test that derived them from the same formula the engine uses would agree with
## the engine no matter what either of them did.
##
## @meta_license: MIT
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Factory = preload("res://test/fixtures/test_effect_factory.gd")

const TOLERANCE: float = 0.0001
const ATTACK: StringName = &"attack"

## The three buffs the worked example starts with, in the order applied.
const FLAT: int = 0
const HALF_AGAIN: int = 1
const DOUBLE: int = 2

var fixture: ASCFixture = null
var asc: AbilitySystemComponent = null


func before_each() -> void:
	fixture = Fixture.create("Subject")
	add_child_autofree(fixture.owner)
	asc = fixture.asc
	asc.set_process(false)


func after_each() -> void:
	fixture = null
	asc = null


## One question from the plan: what changes, and what Attack must then read.
class Step extends RefCounted:
	## The plan's own wording, so a failure quotes the document.
	var question: String = ""
	var expected: float = 0.0
	## Buffs to remove before asking, by their index in the applied order.
	var remove: Array[int] = []
	## A new base to set before asking, or NAN to leave it where it is.
	var new_base: float = NAN


func _worked_example() -> Array[Step]:
	var start: Step = Step.new()
	start.question = "100 Attack, +20 flat, x1.5 and x2"
	start.expected = 360.0

	var unflattened: Step = Step.new()
	unflattened.question = "the +20 removed while the multipliers stay active"
	unflattened.remove = [FLAT] as Array[int]
	unflattened.expected = 300.0

	var relevelled: Step = Step.new()
	relevelled.question = "the base changed to 120 while the buffs are active"
	relevelled.new_base = 120.0
	relevelled.expected = 360.0

	var stripped: Step = Step.new()
	stripped.question = "every buff removed"
	stripped.remove = [HALF_AGAIN, DOUBLE] as Array[int]
	stripped.expected = 120.0

	return [start, unflattened, relevelled, stripped] as Array[Step]


## The plan's worked example, asked step by step in its own order.
##
## A sequence rather than four tests: each answer depends on the state the
## previous one left, and that dependency is the interesting part. Rebuilding
## the state for each would prove the arithmetic and not the continuity.
func test_the_plans_worked_example_answers_exactly_as_written() -> void:
	fixture.set_base(ATTACK, 100.0)

	var applied: Array[ActiveGameplayEffect] = [
		Factory.apply(asc, Factory.infinite([Factory.add(ATTACK, 20.0)])),
		Factory.apply(asc, Factory.infinite([Factory.multiply(ATTACK, 1.5)])),
		Factory.apply(asc, Factory.infinite([Factory.multiply(ATTACK, 2.0)])),
	]

	for step: Step in _worked_example():
		if not is_nan(step.new_base):
			fixture.set_base(ATTACK, step.new_base)
		for index: int in step.remove:
			asc.remove_active_effect(applied[index])
		assert_almost_eq(fixture.current_of(ATTACK), step.expected, TOLERANCE, step.question)

	# The last answer is 120 because that is the base the third step set, not the
	# 100 it started at. A base change a buff had swallowed would read 100 here.
	assert_almost_eq(
		fixture.base_of(ATTACK), 120.0, TOLERANCE,
		"and the base carries the change, having never been moved by a buff"
	)
