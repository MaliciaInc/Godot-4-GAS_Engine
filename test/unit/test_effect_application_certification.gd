## What applying an effect no longer asks of everything already on a character.
##
## Split from test_indexed_search_performance_certification.gd, which certifies
## the effect indices and writes down what each load cost. These are the work one
## application did beyond the indices - reading which attributes a set declares,
## and asking every standing effect whether a new tag changed anything - and they
## are counted rather than timed for the same reason the indices are: a count is
## the same on every machine.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const EffectFactory = preload("res://test/fixtures/test_effect_factory.gd")

## How many times a buff comes and goes.
const ROUNDS: int = 100

## How many effects stand on a character that have nothing to do with the tag a
## new effect grants.
const BYSTANDERS: int = 50

const BURNING: StringName = &"State.Burning"
const ARMOURED: StringName = &"Status.Armoured"
const UNRELATED: StringName = &"State.Unrelated"
const HELD: StringName = &"State.Held"


## A set that counts how often anybody asks which attributes it declares.
class CountingSet extends TestAttributeSet:
	static var asked: int = 0

	func get_attribute_names() -> Array[StringName]:
		asked += 1
		return super()


## A query that counts how often it is matched against a component's tags.
class CountingQuery extends GameplayTagQuery:
	var asked: int = 0

	func matches_runtime(runtime: GameplayTagRuntime) -> bool:
		asked += 1
		return super(runtime)


#region What is asserted
## Effects coming and going never ask a set again which attributes it declares.
##
## A set is read when it arrives. Recomposition used to read every set's
## property list on every pass, and one application recomposes up to three
## times - measured at a quarter of what that application cost. Counted on the
## set rather than timed, and checked against the buff actually landing, so a
## count of nothing cannot be a recomposition that never ran.
func test_effects_do_not_reread_which_attributes_a_set_declares() -> void:
	CountingSet.asked = 0
	var counted: ASCFixture = _standing("Counted", CountingSet)
	var at_arrival: int = CountingSet.asked
	assert_gt(at_arrival, 0, "the set was read when it arrived")

	var base: float = counted.current_of(&"attack")
	var buff: GameplayEffect = EffectFactory.granting(
		EffectFactory.duration(
			[EffectFactory.add(&"attack", 2.0)] as Array[GameplayEffectModifier], 5.0
		),
		[BURNING] as Array[StringName]
	)
	var landed: int = 0
	for _round: int in ROUNDS:
		var active: ActiveGameplayEffect = counted.asc.apply_gameplay_effect(
			buff, counted.asc, 1.0
		)
		if is_equal_approx(counted.current_of(&"attack"), base + 2.0):
			landed += 1
		counted.asc.remove_active_effect(active)

	assert_eq(landed, ROUNDS, "every buff landed and was recomposed in")
	assert_eq(
		CountingSet.asked, at_arrival,
		"and the set was not asked again while they came and went"
	)


## Granting a tag asks only the effects whose requirements are about it.
##
## The reevaluation an application defers used to ask every effect already on
## the character - fifty unrelated ones were a quarter of the application. The
## one whose requirement names the tag is asked, and holds either way, so no
## transition turns the reevaluation into the full pass a transition is
## entitled to; that is what makes the zero beside it mean something.
func test_granting_a_tag_asks_only_the_effects_that_care() -> void:
	var asc: AbilitySystemComponent = _standing("Crowded").asc
	asc.add_tag(HELD)
	var bystanders: Array[CountingQuery] = []
	for _index: int in BYSTANDERS:
		var unrelated: CountingQuery = CountingQuery.new()
		GameplayTagQueryEdits.add_tag(GameplayTagQueryEdits.ensure_root(unrelated), UNRELATED)
		bystanders.append(unrelated)
		asc.apply_gameplay_effect(_requiring(unrelated), asc, 1.0)

	var caring: CountingQuery = CountingQuery.new()
	var either: GameplayTagQueryExpression = GameplayTagQueryEdits.ensure_root(caring)
	either.operator = GameplayTagQueryExpression.Operator.ANY
	GameplayTagQueryEdits.add_tag(either, ARMOURED)
	GameplayTagQueryEdits.add_tag(either, HELD)
	asc.apply_gameplay_effect(_requiring(caring), asc, 1.0)

	for unrelated: CountingQuery in bystanders:
		unrelated.asked = 0
	caring.asked = 0

	asc.apply_gameplay_effect(
		EffectFactory.granting(
			EffectFactory.infinite([] as Array[GameplayEffectModifier]),
			[ARMOURED] as Array[StringName]
		),
		asc, 1.0
	)

	var asked_bystanders: int = 0
	for unrelated: CountingQuery in bystanders:
		asked_bystanders += unrelated.asked
	assert_gt(caring.asked, 0, "the effect whose requirement names the tag was asked")
	assert_eq(asked_bystanders, 0, "and not one of the %d whose requirements do not" % BYSTANDERS)
	asc.effects.cleanup()
#endregion


#region Getting there
## A character in the tree, with nothing ticking it.
func _standing(named: String, attributes: GDScript = null) -> ASCFixture:
	var made: ASCFixture = Fixture.create(named, attributes)
	add_child_autofree(made.owner)
	made.asc.set_process(false)
	return made


## An effect that stays in force only while `query` holds.
func _requiring(query: GameplayTagQuery) -> GameplayEffect:
	var effect: GameplayEffect = EffectFactory.infinite(
		[] as Array[GameplayEffectModifier]
	)
	var requirement: GameplayEffectTargetTagRequirementsComponent = (
		GameplayEffectTargetTagRequirementsComponent.new()
	)
	requirement.ongoing_query = query
	effect.components.append(requirement)
	return effect
#endregion
