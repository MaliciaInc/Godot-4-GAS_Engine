## The canonical formula, proved case by case.
##
##     current = ((base + sum(ADD)) * product(MULTIPLY)) / product(DIVIDE)
##
## then the last applicable OVERRIDE, then the effective clamp.
##
## The case that matters most is base 10 with +10 and x2. It is 40. A model that
## applies each modifier to the running value in declaration order gives 30, and
## upstream's delta model gave whichever of the two the array happened to
## produce.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Factory = preload("res://test/fixtures/test_effect_factory.gd")

const TOLERANCE: float = 0.0001
const ATTACK: StringName = &"attack"
const MANA: StringName = &"mana"

var fixture: ASCFixture = null


func before_each() -> void:
	fixture = Fixture.create("Subject")
	add_child_autofree(fixture.owner)


func after_each() -> void:
	fixture = null


func _apply(effect: GameplayEffect) -> ActiveGameplayEffect:
	return Factory.apply(fixture.asc, effect)


#region Additive
func test_two_adds_sum_onto_the_base() -> void:
	fixture.set_base(ATTACK, 10.0)
	_apply(Factory.infinite([Factory.add(ATTACK, 5.0), Factory.add(ATTACK, 2.0)]))
	assert_almost_eq(fixture.current_of(ATTACK), 17.0, TOLERANCE, "10 + 5 + 2")


func test_adds_from_separate_effects_also_sum() -> void:
	fixture.set_base(ATTACK, 10.0)
	_apply(Factory.infinite([Factory.add(ATTACK, 5.0)]))
	_apply(Factory.infinite([Factory.add(ATTACK, 2.0)]))
	assert_almost_eq(fixture.current_of(ATTACK), 17.0, TOLERANCE, "two effects, one sum")
#endregion


#region Multiplicative
func test_multipliers_compound_with_each_other() -> void:
	fixture.set_base(ATTACK, 10.0)
	_apply(Factory.infinite([Factory.multiply(ATTACK, 1.5), Factory.multiply(ATTACK, 1.5)]))
	# x1.5 twice is x2.25, not x2.0. Multipliers are not converted into additive
	# percentages, which is the usual way this goes wrong.
	assert_almost_eq(fixture.current_of(ATTACK), 22.5, TOLERANCE, "10 * 1.5 * 1.5")
#endregion


#region Mixed
func test_add_then_multiply_is_forty_not_thirty() -> void:
	fixture.set_base(ATTACK, 10.0)
	_apply(Factory.infinite([Factory.add(ATTACK, 10.0), Factory.multiply(ATTACK, 2.0)]))
	assert_almost_eq(fixture.current_of(ATTACK), 40.0, TOLERANCE, "((10 + 10) * 2)")


func test_declaration_order_does_not_change_the_result() -> void:
	fixture.set_base(ATTACK, 10.0)
	# The multiply is declared first here. The formula sums adds before applying
	# multipliers regardless, so the answer is still 40.
	_apply(Factory.infinite([Factory.multiply(ATTACK, 2.0), Factory.add(ATTACK, 10.0)]))
	assert_almost_eq(fixture.current_of(ATTACK), 40.0, TOLERANCE, "still 40")
#endregion


#region Division
func test_divisors_compound() -> void:
	fixture.set_base(ATTACK, 100.0)
	_apply(Factory.infinite([Factory.divide(ATTACK, 2.0), Factory.divide(ATTACK, 5.0)]))
	assert_almost_eq(fixture.current_of(ATTACK), 10.0, TOLERANCE, "100 / 2 / 5")


func test_dividing_by_zero_refuses_the_whole_application() -> void:
	fixture.set_base(ATTACK, 100.0)
	var before_base: float = fixture.base_of(ATTACK)
	var before_current: float = fixture.current_of(ATTACK)

	watch_signals(fixture.asc)
	var applied: ActiveGameplayEffect = _apply(
		Factory.infinite([Factory.add(ATTACK, 10.0), Factory.divide(ATTACK, 0.0)])
	)

	assert_null(applied, "the application is refused")
	assert_almost_eq(fixture.base_of(ATTACK), before_base, TOLERANCE, "base untouched")
	assert_almost_eq(fixture.current_of(ATTACK), before_current, TOLERANCE, "current untouched")
	# The valid +10 in the same effect must not land either: the transaction is
	# atomic, so a partial application is not a lesser failure, it is a worse one.
	assert_signal_not_emitted(fixture.asc, "attribute_changed", "no partial signal")
	assert_signal_not_emitted(fixture.asc, "active_effect_added", "nothing registered")
	assert_eq(fixture.asc.get_active_effects().size(), 0, "no active effect")
#endregion


#region Removing one of two contributions
## One case of "apply two contributions, remove them in a stated order".
##
## Named fields rather than a positional array: `case[7]` told a reader nothing,
## and an untyped array makes every value a Variant, which the strict typing
## policy rejects outright. The policy pushed this towards being readable.
class RemovalCase extends RefCounted:
	var label: String = ""
	var base: float = 0.0
	var first_kind: String = ""
	var first_magnitude: float = 0.0
	var second_kind: String = ""
	var second_magnitude: float = 0.0
	var with_both: float = 0.0
	## 0 removes the first-applied effect, 1 removes the second.
	var remove_index: int = 0
	var after_first_removal: float = 0.0
	var after_both_removals: float = 0.0


## Build one case. Six positional values would be worse than the array was.
static func _case(label: String, base: float, with_both: float) -> RemovalCase:
	var built: RemovalCase = RemovalCase.new()
	built.label = label
	built.base = base
	built.with_both = with_both
	return built


func _removal_cases() -> Array[RemovalCase]:
	var outranked: RemovalCase = _case("an override outranks, then yields", 10.0, 100.0)
	outranked.first_kind = "override"
	outranked.first_magnitude = 50.0
	outranked.second_kind = "override"
	outranked.second_magnitude = 100.0
	outranked.remove_index = 1
	outranked.after_first_removal = 50.0
	outranked.after_both_removals = 10.0

	var add_first: RemovalCase = _case("the add removed before the multiply", 100.0, 240.0)
	add_first.first_kind = "add"
	add_first.first_magnitude = 20.0
	add_first.second_kind = "multiply"
	add_first.second_magnitude = 2.0
	add_first.remove_index = 0
	add_first.after_first_removal = 200.0
	add_first.after_both_removals = 100.0

	var multiply_first: RemovalCase = _case("the multiply removed before the add", 100.0, 240.0)
	multiply_first.first_kind = "add"
	multiply_first.first_magnitude = 20.0
	multiply_first.second_kind = "multiply"
	multiply_first.second_magnitude = 2.0
	multiply_first.remove_index = 1
	multiply_first.after_first_removal = 120.0
	multiply_first.after_both_removals = 100.0

	return [outranked, add_first, multiply_first] as Array[RemovalCase]


func _modifier(kind: String, magnitude: float) -> GameplayEffectModifier:
	match kind:
		"add":
			return Factory.add(ATTACK, magnitude)
		"multiply":
			return Factory.multiply(ATTACK, magnitude)
		"override":
			return Factory.override(ATTACK, magnitude)
	fail_test("unknown modifier kind: " + kind)
	return null


## Two contributions, removed in a stated order, land on stated values.
##
## The reverse-order case is what a delta model cannot do: a `+20` recorded at
## application was worth 20 then and 40 once doubled, and reversing either
## number is wrong. Recomposition keeps no history, so there is nothing to get
## wrong. An outranked OVERRIDE is the same story: it was never destroyed, so it
## becomes visible again rather than the attribute falling back to its base.
##
## One procedure, three cases. It was three near-identical tests, which the
## duplication gate reported and was right to: the shape was the assertion, and
## writing it three times meant three places to fix when the shape changed.
func test_removing_either_contribution_recomposes_correctly(
	scenario: RemovalCase = use_parameters(_removal_cases())
) -> void:
	fixture.set_base(ATTACK, scenario.base)

	var first: ActiveGameplayEffect = _apply(
		Factory.infinite([_modifier(scenario.first_kind, scenario.first_magnitude)])
	)
	var second: ActiveGameplayEffect = _apply(
		Factory.infinite([_modifier(scenario.second_kind, scenario.second_magnitude)])
	)
	assert_almost_eq(
		fixture.current_of(ATTACK), scenario.with_both, TOLERANCE, scenario.label + ": both active"
	)

	var applied: Array[ActiveGameplayEffect] = [first, second]
	fixture.asc.remove_active_effect(applied[scenario.remove_index])
	assert_almost_eq(
		fixture.current_of(ATTACK),
		scenario.after_first_removal,
		TOLERANCE,
		scenario.label + ": one removed"
	)

	fixture.asc.remove_active_effect(applied[1 - scenario.remove_index])
	assert_almost_eq(
		fixture.current_of(ATTACK),
		scenario.after_both_removals,
		TOLERANCE,
		scenario.label + ": both removed"
	)


func test_within_one_effect_the_higher_modifier_index_wins() -> void:
	fixture.set_base(ATTACK, 10.0)
	_apply(Factory.infinite([Factory.override(ATTACK, 50.0), Factory.override(ATTACK, 100.0)]))
	assert_almost_eq(fixture.current_of(ATTACK), 100.0, TOLERANCE, "index 1 beats index 0")
#endregion


#region Instant versus active
func test_the_same_modifiers_as_instant_commit_to_base() -> void:
	fixture.set_base(ATTACK, 10.0)
	_apply(Factory.instant([Factory.add(ATTACK, 10.0), Factory.multiply(ATTACK, 2.0)]))
	assert_almost_eq(fixture.base_of(ATTACK), 40.0, TOLERANCE, "instant writes the base")
	assert_almost_eq(fixture.current_of(ATTACK), 40.0, TOLERANCE, "current follows")
	assert_eq(fixture.asc.get_active_effects().size(), 0, "instant registers nothing")


func test_the_same_modifiers_as_active_leave_the_base_alone() -> void:
	fixture.set_base(ATTACK, 10.0)
	var active: ActiveGameplayEffect = _apply(
		Factory.infinite([Factory.add(ATTACK, 10.0), Factory.multiply(ATTACK, 2.0)])
	)
	assert_almost_eq(fixture.base_of(ATTACK), 10.0, TOLERANCE, "base untouched by an active effect")
	assert_almost_eq(fixture.current_of(ATTACK), 40.0, TOLERANCE, "same arithmetic")

	fixture.asc.remove_active_effect(active)
	assert_almost_eq(fixture.current_of(ATTACK), 10.0, TOLERANCE, "returns to base")
#endregion


#region Base changes under an active buff
func test_raising_the_base_recomposes_instead_of_dropping_the_buff() -> void:
	fixture.set_base(ATTACK, 10.0)
	var buff: ActiveGameplayEffect = _apply(Factory.infinite([Factory.multiply(ATTACK, 2.0)]))
	assert_almost_eq(fixture.current_of(ATTACK), 20.0, TOLERANCE, "10 * 2")

	# Levelling up while buffed. Upstream's base setter assigned current = base
	# here, silently deleting the buff.
	fixture.set_base(ATTACK, 15.0)
	assert_almost_eq(fixture.current_of(ATTACK), 30.0, TOLERANCE, "15 * 2")

	fixture.asc.remove_active_effect(buff)
	assert_almost_eq(fixture.current_of(ATTACK), 15.0, TOLERANCE, "the new base survives")
#endregion


#region Bootstrap
func test_a_stale_current_value_is_repaired_without_signals() -> void:
	# An authored Resource with base 100 and a stale current of 0 must come up
	# at 100/100, and the repair must not look like gameplay to a listener.
	var stale: ASCFixture = Fixture.create("Stale")
	stale.attributes.mana.base_value = 100.0
	stale.attributes.mana.current_value = 0.0

	var component: AbilitySystemComponent = stale.asc
	watch_signals(component)
	add_child_autofree(stale.owner)

	assert_almost_eq(stale.base_of(MANA), 100.0, TOLERANCE, "base preserved")
	assert_almost_eq(stale.current_of(MANA), 100.0, TOLERANCE, "current repaired")
	assert_signal_not_emitted(component, "attribute_changed", "bootstrap is silent")
#endregion


#region Attribute sets handed over after the component is running
## `_ready()` isolates the authored sets and hands them to the runtime. A
## component given its sets after that used to keep neither: the runtime held
## the array it was wired with, so the new sets were never read, and the
## isolation never ran, so two components handed the same authored resource
## shared one pool of health.
##
## Both failures are silent, and the second is the worse one - it looks like a
## working game until the whole party dies at once.
func test_sets_assigned_after_ready_reach_the_runtime() -> void:
	var late: ASCFixture = Fixture.create("Late")
	add_child_autofree(late.owner)
	late.asc.attribute_sets = [] as Array[AttributeSet]
	assert_eq(late.asc.get_attribute_current(&"health"), 0.0, "nothing to read yet")

	var authored: TestAttributeSet = TestAttributeSet.new()
	late.asc.attribute_sets = [authored] as Array[AttributeSet]

	assert_almost_eq(
		late.asc.get_attribute_current(&"health"), 100.0, 0.0001,
		"the runtime reads what it was handed, whenever it was handed over"
	)


func test_sets_assigned_after_ready_are_still_isolated() -> void:
	var one: ASCFixture = Fixture.create("One")
	var two: ASCFixture = Fixture.create("Two")
	add_child_autofree(one.owner)
	add_child_autofree(two.owner)

	# The fixture turns sharing on so a test can reach the same set object;
	# isolation is exactly what is under test here, so it goes back off.
	one.asc.share_attributes = false
	two.asc.share_attributes = false

	# The same authored resource, handed to both after each is running.
	var authored: TestAttributeSet = TestAttributeSet.new()
	one.asc.attribute_sets = [authored] as Array[AttributeSet]
	two.asc.attribute_sets = [authored] as Array[AttributeSet]

	# Asked of the objects, not of a number. Reading health would pass while
	# each component quietly went on using the set its fixture built - which
	# is what this test did at first, and proved nothing.
	#
	# Asked of the live sets rather than of the export, which is the second
	# thing this got wrong: it read the export being overwritten with the
	# copies as proof of isolation, and that overwrite was itself the bug
	# below. The export holds what was authored; the copies live in the
	# runtime that works on them.
	assert_eq(one.asc.attribute_sets[0], authored, "the export still holds the original")
	assert_ne(one.asc.attributes.find_set(&"health"), authored, "one works on a copy")
	assert_ne(two.asc.attributes.find_set(&"health"), authored, "and so does two")
	assert_ne(
		one.asc.attributes.find_set(&"health"), two.asc.attributes.find_set(&"health"),
		"and not the same copy as each other, or one pool serves both"
	)

	one.asc.apply_attribute_base_delta(&"health", -40.0)
	assert_almost_eq(one.asc.get_attribute_current(&"health"), 60.0, 0.0001, "one took the hit")
	assert_almost_eq(
		two.asc.get_attribute_current(&"health"), 100.0, 0.0001,
		"and the other did not feel it"
	)


## Isolation used to replace the elements of the array it was handed, and that
## array belongs to the game. One array assigned to two components left the
## second holding the first's live copies - a battler built after its twin had
## taken a hit started the fight already wounded - and left the game's own
## variable no longer holding what it authored.
func test_one_array_handed_to_two_components_is_not_rewritten() -> void:
	var one: ASCFixture = Fixture.create("First")
	var two: ASCFixture = Fixture.create("Second")
	add_child_autofree(one.owner)
	add_child_autofree(two.owner)
	one.asc.share_attributes = false
	two.asc.share_attributes = false

	var authored: TestAttributeSet = TestAttributeSet.new()
	var roster: Array[AttributeSet] = [authored] as Array[AttributeSet]

	one.asc.attribute_sets = roster
	assert_eq(roster[0], authored, "the game's array still holds what it authored")

	one.asc.apply_attribute_base_delta(&"health", -40.0)
	two.asc.attribute_sets = roster

	assert_almost_eq(
		two.asc.get_attribute_current(&"health"), 100.0, 0.0001,
		"the second copies the authored set, not the first's wounded one"
	)


## The policy is read at the handover, so assigning it to a running component
## used to be ignored in silence - the same ordering trap the sets themselves
## had, one export over. It is reversible now only because the export keeps the
## authored resources instead of being overwritten with the copies.
func test_share_attributes_set_after_ready_takes_effect() -> void:
	var late: ASCFixture = Fixture.create("Sharer")
	add_child_autofree(late.owner)

	var authored: TestAttributeSet = TestAttributeSet.new()
	late.asc.share_attributes = false
	late.asc.attribute_sets = [authored] as Array[AttributeSet]
	assert_ne(late.asc.attributes.find_set(&"health"), authored, "copied, as asked")

	late.asc.share_attributes = true
	assert_eq(
		late.asc.attributes.find_set(&"health"), authored,
		"and asked again the other way, it works on the authored set itself"
	)
#endregion
