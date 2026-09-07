## Naming an attribute on an entity that carries two sets declaring it.
##
## A bare `health` has one answer right up to the moment something else on the
## entity also has health - a vehicle, a shield, a mount - and from then on it
## has two, and the engine picks whichever set it walked into first. That is not
## a wrong answer so much as an arbitrary one: it changes when somebody reorders
## the list, and nothing reports it.
##
## So an attribute can be named with its set. The set is optional, because
## demanding it everywhere would rewrite every effect anybody has authored, and
## a bare name is still exactly right wherever it still means one thing. What is
## no longer allowed is a bare name that means two: that is refused rather than
## guessed.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Vehicle = preload("res://test/fixtures/vehicle_attribute_set.gd")

const HEALTH: StringName = &"health"
const FUEL: StringName = &"fuel"
const MANA: StringName = &"mana"

var fixture: ASCFixture = null
var asc: AbilitySystemComponent = null
var attributes: GameplayAttributeRuntime = null


func before_each() -> void:
	fixture = Fixture.create("Driver")
	add_child_autofree(fixture.owner)
	asc = fixture.asc
	asc.set_process(false)
	attributes = asc.attributes


func after_each() -> void:
	fixture = null
	asc = null
	attributes = null


#region Getting there
## Put a second set on the entity, so `health` means two things.
func _also_drive_a_vehicle() -> VehicleAttributeSet:
	var vehicle: VehicleAttributeSet = Vehicle.new()
	var both: Array[AttributeSet] = [fixture.attributes, vehicle]
	asc.share_attributes = true
	asc.attribute_sets = both
	return vehicle


func _ref(attribute_name: StringName, set_name: StringName = &"") -> GameplayAttributeRef:
	var made: GameplayAttributeRef = GameplayAttributeRef.new()
	made.set_name = set_name
	made.attribute_name = attribute_name
	return made
#endregion


#region One set, which is most projects
## A bare name is answered, because it still means one thing.
func test_a_bare_name_is_answered_while_it_means_one_thing() -> void:
	assert_false(attributes.is_ambiguous(HEALTH), "only one set declares it")

	var found: AttributeData = attributes.find_by_ref(_ref(HEALTH))

	assert_not_null(found, "the attribute was found")
	assert_eq(found, attributes.find(HEALTH), "and it is the one the old lookup gives")


## A name nothing declares is answered with nothing, not with a guess.
func test_a_name_nothing_declares_is_answered_with_nothing() -> void:
	assert_null(attributes.find_by_ref(_ref(&"charisma")), "no set has it")
	assert_null(attributes.find_set_by_ref(_ref(&"charisma")), "so no set is named")


## A reference with no attribute at all is not a reference.
func test_a_reference_naming_nothing_is_refused() -> void:
	var empty: GameplayAttributeRef = GameplayAttributeRef.new()

	assert_false(empty.is_valid(), "it names nothing")
	assert_null(attributes.find_by_ref(empty), "and is answered with nothing")
#endregion


#region Two sets, both with health
## A bare name that means two things is refused.
##
## G10. This is the whole reason the set exists on a reference. Answering it
## would mean choosing for the author, and the choice would be made by the order
## the sets happen to be listed in.
func test_a_bare_name_that_means_two_things_is_refused() -> void:
	_also_drive_a_vehicle()
	assert_true(attributes.is_ambiguous(HEALTH), "two sets declare health")

	assert_null(attributes.find_by_ref(_ref(HEALTH)), "so a bare name is refused")
	assert_null(attributes.find_set_by_ref(_ref(HEALTH)), "and names no set")


## Naming the set answers it, and answers it differently for each.
##
## Both halves, because either alone is satisfied by the wrong thing: returning
## the same attribute for both names would pass an assertion that only checked
## one of them.
func test_naming_the_set_answers_each_health_separately() -> void:
	var vehicle: VehicleAttributeSet = _also_drive_a_vehicle()

	var mine: AttributeData = attributes.find_by_ref(_ref(HEALTH, &"TestAttributeSet"))
	var theirs: AttributeData = attributes.find_by_ref(_ref(HEALTH, &"VehicleAttributeSet"))

	assert_not_null(mine, "the driver's health")
	assert_not_null(theirs, "and the vehicle's")
	assert_ne(mine, theirs, "which are not the same attribute")
	assert_eq(theirs, vehicle.health, "and the vehicle's is the vehicle's")


## An attribute only one of them declares is still answered by a bare name.
##
## Ambiguity is per attribute, not per entity: adding a vehicle does not force
## every reference on the entity to be rewritten, only the ones that now mean
## two things.
func test_an_attribute_only_one_set_declares_is_still_answered_bare() -> void:
	_also_drive_a_vehicle()

	assert_false(attributes.is_ambiguous(FUEL), "only the vehicle has fuel")
	assert_not_null(attributes.find_by_ref(_ref(FUEL)), "so a bare name reaches it")
	assert_false(attributes.is_ambiguous(MANA), "and only the driver has mana")
	assert_not_null(attributes.find_by_ref(_ref(MANA)), "which is reachable too")


## A set named in a reference that the entity does not carry answers nothing.
func test_naming_a_set_the_entity_does_not_carry_answers_nothing() -> void:
	_also_drive_a_vehicle()

	assert_null(
		attributes.find_by_ref(_ref(HEALTH, &"SpaceshipAttributeSet")),
		"nothing on this entity answers to that"
	)
#endregion


#region What an author may write
## A field authored the old way resolves to the same reference.
##
## Nothing has to migrate. Every effect, capture and cost written before this
## carries a bare name, and that name becomes a reference with no set - which is
## exactly the lookup it always got.
func test_a_legacy_name_becomes_a_reference_that_means_the_same() -> void:
	var resolved: GameplayAttributeRef = GameplayAttributeRef.resolved(null, HEALTH)

	assert_true(resolved.is_valid(), "it names something")
	assert_eq(resolved.attribute_name, HEALTH, "the attribute it was written with")
	assert_eq(resolved.set_name, &"", "and no set, which is what a bare name means")
	assert_eq(attributes.find_by_ref(resolved), attributes.find(HEALTH), "same answer")


## A typed reference wins wherever somebody wrote one.
func test_a_typed_reference_wins_over_the_legacy_name_beside_it() -> void:
	var authored: GameplayAttributeRef = _ref(HEALTH, &"VehicleAttributeSet")

	var resolved: GameplayAttributeRef = GameplayAttributeRef.resolved(authored, MANA)

	assert_eq(resolved, authored, "the typed one is the answer")


## An empty reference beside a legacy name falls back to the name.
##
## An author who added the field and left it blank has not said anything, and
## treating a blank as an instruction would break the effect they did author.
func test_an_empty_reference_falls_back_to_the_name_beside_it() -> void:
	var blank: GameplayAttributeRef = GameplayAttributeRef.new()

	var resolved: GameplayAttributeRef = GameplayAttributeRef.resolved(blank, MANA)

	assert_eq(resolved.attribute_name, MANA, "the name it was authored with")


## The three shapes an attribute is named in all carry one.
##
## Modifiers, captures and costs are the three places an author says which
## attribute they mean, and a reference that only reached one of them would
## leave the other two ambiguous.
func test_every_shape_that_names_an_attribute_can_carry_a_reference() -> void:
	var modifier: GameplayEffectModifier = GameplayEffectModifier.new()
	var capture: GameplayAttributeCaptureDefinition = (
		GameplayAttributeCaptureDefinition.new()
	)
	var cost: GameplayAbilityCost = GameplayAbilityCost.new()

	modifier.attribute = _ref(HEALTH, &"VehicleAttributeSet")
	capture.attribute = _ref(HEALTH, &"VehicleAttributeSet")
	cost.target = _ref(HEALTH, &"VehicleAttributeSet")
	cost.reference = _ref(FUEL, &"VehicleAttributeSet")

	assert_true(modifier.attribute.is_valid(), "a modifier names one")
	assert_true(capture.attribute.is_valid(), "a capture names one")
	assert_true(cost.target.is_valid(), "a cost names what it charges")
	assert_true(cost.reference.is_valid(), "and what it prices against")


## Two references to the same attribute are the same reference.
func test_two_references_to_one_attribute_are_equal() -> void:
	assert_true(
		_ref(HEALTH, &"VehicleAttributeSet").equals(_ref(HEALTH, &"VehicleAttributeSet")),
		"same set, same attribute"
	)
	assert_false(
		_ref(HEALTH, &"VehicleAttributeSet").equals(_ref(HEALTH)),
		"and naming the set is not the same as not naming it"
	)
#endregion
