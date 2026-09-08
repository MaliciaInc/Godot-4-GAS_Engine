## Two ways of folding the same modifiers, and why both have to exist.
##
## Two +50% buffs are worth 2.25x under this engine's own rules and 2.0x under
## Unreal's. Neither is a bug: one multiplies the products, the other adds the
## bonuses and multiplies once. A game that shipped on the first and is handed
## the second as "the fix" has had every stat in it silently rebalanced, which
## is why the profile decides and the default decides nothing.
##
## Unreal's also folds in passes. Channel 0 composes, channel 1 composes over
## what channel 0 produced, and so on - which is how a game says "this
## multiplies the buffed value, not the base" without every effect having to
## know about every other one.
##
## And an override behaves oppositely in the two: this engine lets the last one
## applied win, Unreal lets the first eligible one claim the attribute. Both are
## defensible and they disagree, so each is written down.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Factory = preload("res://test/fixtures/test_effect_factory.gd")

const TOLERANCE: float = 0.0001
const ATTACK: StringName = &"attack"
const UNDEAD: StringName = &"Race.Undead"

var fixture: ASCFixture = null
var asc: AbilitySystemComponent = null


func before_each() -> void:
	fixture = Fixture.create("Fighter")
	add_child_autofree(fixture.owner)
	asc = fixture.asc
	asc.set_process(false)
	asc.set_attribute_base(ATTACK, 100.0)


func after_each() -> void:
	fixture = null
	asc = null


#region Getting there
## Put this entity on Unreal's contracts.
func _use_unreal() -> void:
	asc.compatibility_profile.mode = GameplayCompatibilityProfile.Mode.UE_5_7
	assert_true(asc.uses_ue_5_7_contracts(), "the profile took")


func _modifier(
	operation: GameplayEffectModifier.Operation, magnitude: float, channel: int = 0
) -> GameplayEffectModifier:
	var made: GameplayEffectModifier = Factory.modifier(ATTACK, operation, magnitude)
	made.evaluation_channel = channel
	return made


## Apply each modifier as its own infinite effect, so every one is a separate
## contribution the aggregate has to fold.
func _apply_each(modifiers: Array[GameplayEffectModifier]) -> void:
	for modifier: GameplayEffectModifier in modifiers:
		var one: Array[GameplayEffectModifier] = [modifier]
		assert_not_null(Factory.apply(asc, Factory.infinite(one)), "it was applied")


func _attack() -> float:
	return asc.get_attribute_current(ATTACK)
#endregion


#region The same two buffs, two answers
## Where the two profiles fold the same authoring into different numbers.
##
## The differential the whole profile exists for. Each row is one pair of
## modifiers, folded twice: once by the rules this engine has always had and
## once by Unreal's. Both columns are asserted, because a change that made them
## agree would be the silent rebalance this exists to prevent.
##
##     [what it is, godot op, ue op, first, second, godot answer, ue answer]
func _differentials() -> Array:
	return [
		[
			"two half-again buffs",
			GameplayEffectModifier.Operation.MULTIPLY,
			GameplayEffectModifier.Operation.MULTIPLY_ADDITIVE,
			1.5, 1.5, 225.0, 200.0,
		],
		[
			"two overrides competing",
			GameplayEffectModifier.Operation.OVERRIDE,
			GameplayEffectModifier.Operation.OVERRIDE,
			10.0, 20.0, 20.0, 10.0,
		],
	]


func test_the_two_profiles_fold_the_same_authoring_differently() -> void:
	var rows: Array = _differentials()
	var checked: int = 0
	for row: Array in rows:
		var described: String = row[0]
		var godot_op: GameplayEffectModifier.Operation = row[1]
		var ue_op: GameplayEffectModifier.Operation = row[2]
		var first_magnitude: float = row[3]
		var second_magnitude: float = row[4]
		var natively: float = row[5]
		var unreally: float = row[6]

		before_each()
		var legacy: Array[GameplayEffectModifier] = [
			_modifier(godot_op, first_magnitude), _modifier(godot_op, second_magnitude)
		]
		_apply_each(legacy)
		assert_almost_eq(
			_attack(), natively, TOLERANCE, "%s: Godot-native" % described
		)

		before_each()
		_use_unreal()
		var compatible: Array[GameplayEffectModifier] = [
			_modifier(ue_op, first_magnitude), _modifier(ue_op, second_magnitude)
		]
		_apply_each(compatible)
		assert_almost_eq(_attack(), unreally, TOLERANCE, "%s: Unreal" % described)
		checked += 1
	assert_eq(checked, rows.size(), "every differential was folded both ways")


## The whole formula, one arm at a time.
##
##     ((value + AddBase) * MultiplyAdditive / DivideAdditive)
##         * MultiplyCompound + AddFinal
##
## Each row is the arithmetic for one arm on a base of 100, so a mistake in any
## one of them is a wrong number rather than a wrong shape somewhere.
##
##     [what it is, operation, magnitude, magnitude, expected]
func _arms() -> Array:
	return [
		["added before the multipliers", GameplayEffectModifier.Operation.ADD, 10.0, 10.0, 120.0],
		[
			"additive multipliers", GameplayEffectModifier.Operation.MULTIPLY_ADDITIVE,
			1.5, 1.5, 200.0,
		],
		[
			"additive divisors", GameplayEffectModifier.Operation.DIVIDE_ADDITIVE,
			1.5, 1.5, 50.0,
		],
		[
			"compound multipliers", GameplayEffectModifier.Operation.MULTIPLY_COMPOUND,
			1.5, 1.5, 225.0,
		],
		[
			"added after them", GameplayEffectModifier.Operation.ADD_FINAL,
			10.0, 10.0, 120.0,
		],
	]


func test_each_arm_of_the_unreal_formula_composes_as_written() -> void:
	var rows: Array = _arms()
	var checked: int = 0
	for row: Array in rows:
		var described: String = row[0]
		var operation: GameplayEffectModifier.Operation = row[1]
		var first: float = row[2]
		var second: float = row[3]
		var expected: float = row[4]

		before_each()
		_use_unreal()
		var pair: Array[GameplayEffectModifier] = [
			_modifier(operation, first), _modifier(operation, second)
		]
		_apply_each(pair)

		assert_almost_eq(_attack(), expected, TOLERANCE, "%s: %s" % [described, expected])
		checked += 1
	assert_eq(checked, rows.size(), "every arm was folded")


## AddBase joins before the multipliers and AddFinal after them.
##
## The two additions are the same operation to anything that does not fold in
## the right order, and the order is the whole reason there are two of them.
func test_the_two_additions_land_on_opposite_sides_of_the_multiplier() -> void:
	_use_unreal()
	var mixed: Array[GameplayEffectModifier] = [
		_modifier(GameplayEffectModifier.Operation.ADD, 100.0),
		_modifier(GameplayEffectModifier.Operation.MULTIPLY_ADDITIVE, 2.0),
		_modifier(GameplayEffectModifier.Operation.ADD_FINAL, 100.0),
	]
	_apply_each(mixed)

	# (100 + 100) * 2 + 100
	assert_almost_eq(_attack(), 500.0, TOLERANCE, "not 100 + (100 + 100) * 2")
#endregion


#region Channels
## A later channel composes over what an earlier one produced.
##
## The same two modifiers on one channel add their bonuses; on two channels they
## multiply, because the second one is multiplying an already-buffed value.
func test_a_second_channel_multiplies_what_the_first_one_produced() -> void:
	_use_unreal()
	var together: Array[GameplayEffectModifier] = [
		_modifier(GameplayEffectModifier.Operation.MULTIPLY_ADDITIVE, 1.5, 0),
		_modifier(GameplayEffectModifier.Operation.MULTIPLY_ADDITIVE, 1.5, 0),
	]
	_apply_each(together)
	assert_almost_eq(_attack(), 200.0, TOLERANCE, "one channel adds the bonuses")

	before_each()
	_use_unreal()
	var apart: Array[GameplayEffectModifier] = [
		_modifier(GameplayEffectModifier.Operation.MULTIPLY_ADDITIVE, 1.5, 0),
		_modifier(GameplayEffectModifier.Operation.MULTIPLY_ADDITIVE, 1.5, 1),
	]
	_apply_each(apart)
	assert_almost_eq(_attack(), 225.0, TOLERANCE, "two channels fold one over the other")
#endregion


#region Overrides
## An override is not scaled by the stack count.
##
## It is a value rather than an amount: two stacks of "set this to 30" is still
## 30. Everything else about a stack multiplies, which is exactly why this one
## has to be said out loud.
func test_an_override_is_not_multiplied_by_the_stack_count() -> void:
	_use_unreal()
	var one: Array[GameplayEffectModifier] = [
		_modifier(GameplayEffectModifier.Operation.OVERRIDE, 30.0)
	]
	var stacking: GameplayEffect = Factory.stacked(
		Factory.infinite(one), GameplayEffect.StackingType.AGGREGATE_BY_SOURCE, 4, true
	)

	Factory.apply(asc, stacking)
	Factory.apply(asc, stacking)

	assert_almost_eq(_attack(), 30.0, TOLERANCE, "two stacks of it is still it")


## A stack scales the arm its magnitude will be folded into.
##
## The fold treats the legacy MULTIPLY as the additive arm under this profile,
## so stack scaling has to as well. Scaling it as a bare product and then
## folding it additively is two answers to one question, and the disagreement
## only ever appears on a stacking effect authored with the legacy spelling -
## which is the hardest place to notice it.
func test_a_stacked_legacy_multiplier_scales_the_arm_it_is_folded_into() -> void:
	_use_unreal()
	var one: Array[GameplayEffectModifier] = [
		_modifier(GameplayEffectModifier.Operation.MULTIPLY, 1.5)
	]
	var stacking: GameplayEffect = Factory.stacked(
		Factory.infinite(one), GameplayEffect.StackingType.AGGREGATE_BY_SOURCE, 4, true
	)

	Factory.apply(asc, stacking)
	Factory.apply(asc, stacking)

	# The bias stacks, not the factor: two stacks of x1.5 are +100%.
	assert_almost_eq(_attack(), 200.0, TOLERANCE, "two stacks of half-again is twice")
#endregion


#region Filters
## A modifier whose target requirement is unmet does not count.
##
## Both directions asserted, because "it did nothing" is also what a modifier
## nobody applied would look like: the same effect on a target that qualifies
## has to change the number.
func test_a_modifier_only_counts_where_its_target_qualifies() -> void:
	_use_unreal()
	var picky: GameplayEffectModifier = _modifier(
		GameplayEffectModifier.Operation.ADD, 50.0
	)
	picky.target_requirements = _requiring(UNDEAD)
	var only: Array[GameplayEffectModifier] = [picky]
	var effect: GameplayEffect = Factory.infinite(only)

	Factory.apply(asc, effect)
	assert_almost_eq(_attack(), 100.0, TOLERANCE, "the living are not slain harder")

	before_each()
	_use_unreal()
	asc.tags.add(UNDEAD)
	Factory.apply(asc, effect)
	assert_almost_eq(_attack(), 150.0, TOLERANCE, "and the undead are")


## And a source requirement is asked of whoever caused it.
func test_a_modifier_only_counts_where_its_source_qualifies() -> void:
	var source: ASCFixture = Fixture.create("Caster")
	add_child_autofree(source.owner)
	source.asc.set_process(false)
	_use_unreal()

	var blessed: GameplayEffectModifier = _modifier(
		GameplayEffectModifier.Operation.ADD, 50.0
	)
	blessed.source_requirements = _requiring(UNDEAD)
	var only: Array[GameplayEffectModifier] = [blessed]
	var effect: GameplayEffect = Factory.infinite(only)

	asc.apply_gameplay_effect(effect, source.asc)
	assert_almost_eq(_attack(), 100.0, TOLERANCE, "an ordinary caster does not")

	before_each()
	_use_unreal()
	source.asc.tags.add(UNDEAD)
	asc.apply_gameplay_effect(effect, source.asc)
	assert_almost_eq(_attack(), 150.0, TOLERANCE, "an undead one does")


func _requiring(tag: StringName) -> GameplayTagQuery:
	var expression: GameplayTagQueryExpression = GameplayTagQueryExpression.new()
	expression.operator = GameplayTagQueryExpression.Operator.ANY
	expression.tags = [tag] as Array[StringName]
	var query: GameplayTagQuery = GameplayTagQuery.new()
	query.root = expression
	return query
#endregion
#region The legacy names mean what the reference means by them
## `MULTIPLY` and `DIVIDE` are Unreal's own legacy spellings, and there they are
## aliases of the additive arms rather than compounding ones. Folding them as
## compound under the profile that exists to agree with Unreal produced 2.25x
## where the reference produces 2.0x, under an operation spelled the same in
## both - the worst shape a difference can take, because nothing about the
## authoring looks wrong.
##
## Godot-native keeps compounding them. That is its contract and no project
## built on it is rebalanced by this.
func test_the_legacy_multiply_name_folds_the_way_the_reference_folds_it() -> void:
	_use_unreal()
	_apply_each([
		_modifier(GameplayEffectModifier.Operation.MULTIPLY, 1.5),
		_modifier(GameplayEffectModifier.Operation.MULTIPLY, 1.5),
	])
	assert_almost_eq(_attack(), 200.0, TOLERANCE, "the bonuses add and multiply once")


func test_the_legacy_multiply_name_still_compounds_under_godot_native() -> void:
	_apply_each([
		_modifier(GameplayEffectModifier.Operation.MULTIPLY, 1.5),
		_modifier(GameplayEffectModifier.Operation.MULTIPLY, 1.5),
	])
	assert_almost_eq(_attack(), 225.0, TOLERANCE, "the products multiply")


func test_a_compound_multiplier_still_compounds_under_the_unreal_profile() -> void:
	_use_unreal()
	_apply_each([
		_modifier(GameplayEffectModifier.Operation.MULTIPLY_COMPOUND, 1.5),
		_modifier(GameplayEffectModifier.Operation.MULTIPLY_COMPOUND, 1.5),
	])
	assert_almost_eq(_attack(), 225.0, TOLERANCE, "compound is still the compounding arm")


## The legacy divisor is the same story on the other side of the fraction.
func test_the_legacy_divide_name_folds_additively_under_the_unreal_profile() -> void:
	_use_unreal()
	_apply_each([
		_modifier(GameplayEffectModifier.Operation.DIVIDE, 1.5),
		_modifier(GameplayEffectModifier.Operation.DIVIDE, 1.5),
	])
	assert_almost_eq(_attack(), 50.0, TOLERANCE, "the divisors add: 100 / 2.0")
#endregion
