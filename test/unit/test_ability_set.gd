## A loadout goes on as one thing, and comes off leaving no trace.
##
## The state that must be unreachable is a half-granted kit: an ability given, an
## effect applied, and then a failure nobody unwinds. So the receipt records
## every publication the moment it succeeds, and retirement walks that exact
## sequence backwards.
##
## Backwards, not grouped by kind. Grouping would be the inverse of a sequence
## nobody performed, and it breaks the first time a set publishes an effect that
## grants an ability of its own.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Factory = preload("res://test/fixtures/test_effect_factory.gd")
const Probe = preload("res://test/fixtures/probe_ability.gd")

const HEALTH: StringName = &"health"
const TOLERANCE: float = 0.0001

var fixture: ASCFixture = null
var asc: AbilitySystemComponent = null


func before_each() -> void:
	fixture = Fixture.create("Recruit")
	add_child_autofree(fixture.owner)
	asc = fixture.asc
	asc.set_process(false)


func after_each() -> void:
	fixture = null
	asc = null


#region Getting there
func _scene(tag: StringName) -> PackedScene:
	var probe: ProbeAbility = Probe.build(tag)
	var scene: PackedScene = PackedScene.new()
	scene.pack(probe)
	probe.free()
	return scene


func _entry(tag: StringName, input_id: int = -1) -> GameplayAbilitySetEntry:
	var entry: GameplayAbilitySetEntry = GameplayAbilitySetEntry.new()
	entry.ability_scene = _scene(tag)
	entry.input_id = input_id
	return entry


## A kit that publishes all three kinds, which is what makes the round trip
## worth asserting: two of the three would not prove the order matters.
func _full_kit() -> GameplayAbilitySet:
	var kit: GameplayAbilitySet = GameplayAbilitySet.new()
	kit.abilities = [
		_entry(&"Ability.One"), _entry(&"Ability.Two", 1), _entry(&"Ability.Three")
	] as Array[GameplayAbilitySetEntry]
	kit.effects = [
		Factory.granting(
			Factory.infinite([] as Array[GameplayEffectModifier]),
			[&"Kit.Worn"] as Array[StringName]
		)
	] as Array[GameplayEffect]
	kit.attribute_sets = [VehicleAttributeSet.new()] as Array[AttributeSet]
	return kit
#region On and off
func test_a_kit_publishes_all_three_kinds() -> void:
	var receipt: GameplayAbilitySetHandles = _full_kit().grant(asc)

	assert_eq(receipt.ability_handles.size(), 3, "three abilities")
	assert_eq(receipt.effect_handles.size(), 1, "one effect")
	assert_eq(receipt.attribute_set_handles.size(), 1, "one attribute set")
	assert_eq(receipt.undo_steps.size(), 5, "and five things to undo")
	assert_true(asc.has_tag(&"Kit.Worn"), "the effect is on")


## The critical one: identical before and after, in every way a loadout could
## have changed it.
func test_granting_and_taking_back_leaves_the_component_as_it_was() -> void:
	var before: Dictionary = fixture.snapshot()

	var receipt: GameplayAbilitySetHandles = _full_kit().grant(asc)
	assert_false(asc.get_ability_specs().is_empty(), "it went on")

	assert_true(receipt.take_back(), "and came off")

	assert_eq(fixture.snapshot(), before, "leaving nothing behind")


## Retirement is the reverse of what was published, not a grouping by kind.
func test_take_back_walks_the_published_sequence_backwards() -> void:
	var receipt: GameplayAbilitySetHandles = _full_kit().grant(asc)

	var published: Array[int] = []
	for step: Dictionary in receipt.undo_steps:
		published.append(step[GameplayAbilitySetHandles.STEP_KIND])

	assert_eq(
		published,
		[
			GameplayAbilitySetHandles.Kind.ATTRIBUTE_SET,
			GameplayAbilitySetHandles.Kind.EFFECT,
			GameplayAbilitySetHandles.Kind.ABILITY,
			GameplayAbilitySetHandles.Kind.ABILITY,
			GameplayAbilitySetHandles.Kind.ABILITY,
		] as Array[int],
		"sets, then effects, then abilities - each recorded as it landed"
	)


func test_taking_a_kit_back_twice_is_a_no_op() -> void:
	var receipt: GameplayAbilitySetHandles = _full_kit().grant(asc)

	assert_true(receipt.take_back(), "once")
	assert_true(receipt.take_back(), "and again, harmlessly")
	assert_true(asc.get_ability_specs().is_empty(), "still nothing on")


## A game is allowed to remove one ability of a kit. Retirement continues past
## it rather than stopping and leaving the rest on.
func test_take_back_continues_past_something_already_removed() -> void:
	var receipt: GameplayAbilitySetHandles = _full_kit().grant(asc)
	asc.remove_ability_handle(receipt.ability_handles[1])

	assert_true(receipt.take_back(), "it finished")
	assert_true(asc.get_ability_specs().is_empty(), "and took the rest with it")
	assert_false(asc.has_tag(&"Kit.Worn"), "including the effect")


## A malformed kit publishes nothing rather than most of itself.
func test_a_kit_with_an_empty_entry_publishes_nothing() -> void:
	var kit: GameplayAbilitySet = _full_kit()
	kit.abilities.append(GameplayAbilitySetEntry.new())

	GutUtils.get_error_tracker().treat_push_error_as = GutUtils.TREAT_AS.NOTHING
	var receipt: GameplayAbilitySetHandles = kit.grant(asc)

	assert_true(receipt.undo_steps.is_empty(), "nothing was published")
	assert_true(asc.get_ability_specs().is_empty(), "and nothing is on")
#endregion


#region Whose receipt it is
## A loadout Resource is granted to every character in a game, so a receipt from
## one of them must not retire anything on another.
func test_a_receipt_from_another_component_retires_nothing_here() -> void:
	var other: ASCFixture = Fixture.create("Somebody else")
	add_child_autofree(other.owner)

	var mine: GameplayAbilitySetHandles = _full_kit().grant(asc)
	var theirs: RegisteredAttributeSetHandle = other.asc.register_attribute_set(
		VehicleAttributeSet.new()
	)

	assert_false(
		asc.unregister_attribute_set(theirs), "their receipt does not work here"
	)
	assert_true(mine.take_back(), "and mine still does")
#endregion
