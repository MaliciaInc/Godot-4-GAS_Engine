## How several contributions of one kind combine on one attribute.
##
## The default is all of them, which is what stacking has always meant here.
## The other two exist for the case that default gets wrong: a character who
## walked into four slows should move at the speed of the worst one, not at a
## quarter of a quarter of a quarter of it.
##
## Every case here is the same four modifiers - two slows and two buffs - read
## under each policy in turn, because the property worth proving is that they
## disagree. A policy tested on its own passes while the other two answer
## whatever the aggregate happened to do.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Factory = preload("res://test/fixtures/test_effect_factory.gd")
const PolicySet = preload("res://test/fixtures/policy_attribute_set.gd")

const TOLERANCE: float = 0.0001

var fixture: ASCFixture = null
var declared: PolicyAttributeSet = null


func before_each() -> void:
	fixture = Fixture.create("Runner", PolicySet)
	add_child_autofree(fixture.owner)
	declared = fixture.attributes as PolicyAttributeSet
	fixture.asc.set_process(false)


func after_each() -> void:
	fixture = null
	declared = null


## Two slows and two buffs, each its own lasting effect, all on speed.
##
## Separate effects rather than one with four modifiers, because that is how a
## character actually collects them and because the policy is about what is on
## the attribute rather than about what one effect said.
func _four_effects_on_speed() -> void:
	for amount: float in [-30.0, -10.0, 20.0, 5.0]:
		Factory.apply(
			fixture.asc,
			Factory.infinite([Factory.add(PolicyAttributeSet.SPEED, amount)])
		)


##     [what the policy is, which of the four survives, what speed reads]
func _policy_cases() -> Array:
	return [
		["all of them", AttributeSet.AggregatorPolicy.ALL, 85.0],
		["only the worst", AttributeSet.AggregatorPolicy.MOST_NEGATIVE, 70.0],
		["only the best", AttributeSet.AggregatorPolicy.MOST_POSITIVE, 120.0],
	]


func test_a_policy_decides_how_many_of_one_kind_count(
	case: Array = use_parameters(_policy_cases())
) -> void:
	var described: String = case[0]
	var policy: AttributeSet.AggregatorPolicy = case[1]
	var expected: float = case[2]

	declared.speed_policy = policy
	_four_effects_on_speed()

	assert_almost_eq(
		fixture.current_of(PolicyAttributeSet.SPEED), expected, TOLERANCE, described
	)


## The selection happens inside one kind and never across two.
##
## An ADD of -30 and a MULTIPLY of 0.5 both lower the value, and under
## MOST_NEGATIVE a selection that spanned them would keep one and drop the
## other. It keeps one of each: comparing "thirty points" against "half" is not
## a comparison, and an author who wrote both meant both.
func test_the_policy_never_chooses_between_two_kinds() -> void:
	declared.speed_policy = AttributeSet.AggregatorPolicy.MOST_NEGATIVE
	Factory.apply(
		fixture.asc, Factory.infinite([Factory.add(PolicyAttributeSet.SPEED, -30.0)])
	)
	Factory.apply(
		fixture.asc, Factory.infinite([Factory.multiply(PolicyAttributeSet.SPEED, 0.5)])
	)

	assert_almost_eq(
		fixture.current_of(PolicyAttributeSet.SPEED),
		35.0,
		TOLERANCE,
		"both kinds applied: (100 - 30) x 0.5"
	)


## An attribute the set says nothing special about is unaffected.
##
## The policy is per attribute, so a set that owns both a speed nobody may
## stack slows on and a health that stacks everything is an ordinary set.
func test_an_attribute_with_no_policy_still_takes_all_of_them() -> void:
	declared.speed_policy = AttributeSet.AggregatorPolicy.MOST_NEGATIVE
	for amount: float in [-30.0, -10.0]:
		Factory.apply(
			fixture.asc,
			Factory.infinite([Factory.add(PolicyAttributeSet.HEALTH, amount)])
		)

	assert_almost_eq(
		fixture.current_of(PolicyAttributeSet.HEALTH),
		60.0,
		TOLERANCE,
		"health is not the attribute the policy was about"
	)
