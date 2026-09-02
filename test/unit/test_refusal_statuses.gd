## The refusals this engine can report that no test ever observed.
##
## Counting which enum values the addon produces against which ones any test
## names turned up nine failure statuses with no coverage at all. A refusal
## nothing exercises is worse than an untested success: it only ever runs on
## the day something is already wrong, which is the worst moment to discover
## the guard itself is broken.
##
## Two of these guard against non-termination - a self-referencing effect chain
## and a modifier that reads the attribute it writes. If either guard were
## gone, the failure mode is a hang rather than a wrong answer, so these tests
## are also the thing that would notice.
##
## @meta_license: MIT
extends GutTest

const EffectFactory = preload("res://test/fixtures/test_effect_factory.gd")
const Fixture = preload("res://test/fixtures/asc_fixture.gd")

const ATTACK: StringName = &"attack"
const HEALTH: StringName = &"health"
const ABSENT: StringName = &"no_such_attribute"

var target: ASCFixture = null


func before_each() -> void:
	target = Fixture.create("Refused")
	add_child_autofree(target.owner)
	target.asc.set_process(false)


func after_each() -> void:
	target = null


func _cost(mode: GameplayAbilityCost.Mode, reference: StringName, amount: float) -> GameplayAbilityCost:
	var cost: GameplayAbilityCost = GameplayAbilityCost.new()
	cost.mode = mode
	cost.target_attribute = HEALTH
	cost.reference_attribute = reference
	cost.amount = GameplayScalableFloat.new()
	cost.amount.value = amount
	return cost


#region Cost resolution
## A percent cost has to name an attribute that exists to be a percent OF
## anything. Reported rather than silently treated as zero.
func test_a_percent_cost_against_an_attribute_that_does_not_exist_is_refused() -> void:
	var costs: Array[GameplayAbilityCost] = [
		_cost(GameplayAbilityCost.Mode.PERCENT_OF_BASE, ABSENT, 0.5)
	]
	var resolved: GameplayResolvedCost = GameplayAbilityCostResolver.resolve(costs, target.asc, 1.0)

	assert_eq(resolved.status, GameplayResolvedCost.Status.REFERENCE_ATTRIBUTE_NOT_FOUND)
	assert_false(resolved.is_ok())


## The fraction is checked before it is multiplied, so a 200% cost is illegal
## at any reference value rather than only at the ones that overdraw.
func test_a_percent_cost_outside_zero_to_one_is_refused_before_it_is_scaled() -> void:
	for illegal: float in [1.5, -0.25, INF] as Array[float]:
		var costs: Array[GameplayAbilityCost] = [
			_cost(GameplayAbilityCost.Mode.PERCENT_OF_BASE, HEALTH, illegal)
		]
		var resolved: GameplayResolvedCost = GameplayAbilityCostResolver.resolve(costs, target.asc, 1.0)
		assert_eq(
			resolved.status, GameplayResolvedCost.Status.PERCENT_OUT_OF_RANGE,
			"a %f fraction is out of range whatever it is a fraction of" % illegal
		)


func test_a_percent_cost_inside_the_range_still_resolves() -> void:
	# The negative case above is only worth something if the positive one works.
	var costs: Array[GameplayAbilityCost] = [
		_cost(GameplayAbilityCost.Mode.PERCENT_OF_BASE, HEALTH, 0.5)
	]
	var resolved: GameplayResolvedCost = GameplayAbilityCostResolver.resolve(costs, target.asc, 1.0)
	assert_eq(resolved.status, GameplayResolvedCost.Status.OK)
#endregion


#region Effect chain depth
## The chain guard, asked directly at the boundary it defends.
func test_an_effect_past_the_chain_depth_ceiling_is_refused() -> void:
	var spec: GameplayEffectSpec = GameplayEffectSpec.new()
	spec.effect_def = EffectFactory.instant([] as Array[GameplayEffectModifier])
	spec.chain_depth = GameplayEffectRuntime.MAX_EFFECT_CHAIN_DEPTH + 1

	var result: GameplayEffectApplicationResult = target.asc.effects.apply(spec)
	assert_eq(result.status, GameplayEffectApplicationResult.Status.CHAIN_DEPTH_EXCEEDED)
	assert_eq(target.asc.effects.active_count(), 0, "and nothing was registered")


func test_an_effect_at_the_ceiling_is_still_applied() -> void:
	# Off-by-one in the other direction: the ceiling itself is legal, so the
	# guard cannot be read as "refuse at the limit".
	var spec: GameplayEffectSpec = GameplayEffectSpec.new()
	spec.effect_def = EffectFactory.infinite([] as Array[GameplayEffectModifier])
	spec.chain_depth = GameplayEffectRuntime.MAX_EFFECT_CHAIN_DEPTH

	var result: GameplayEffectApplicationResult = target.asc.effects.apply(spec)
	assert_ne(result.status, GameplayEffectApplicationResult.Status.CHAIN_DEPTH_EXCEEDED)


## An effect whose additional-effects chain applies itself. Without the depth
## ceiling this recurses until the stack gives out; the assertion that matters
## is that this test returns at all.
func test_a_self_applying_chain_terminates_instead_of_recursing_forever() -> void:
	var loop: GameplayEffect = EffectFactory.instant([] as Array[GameplayEffectModifier])
	EffectFactory.with_additional_effects(
		loop, [EffectFactory.conditional_effect(loop)] as Array[GameplayEffectConditionalEffect]
	)

	var result: GameplayEffectApplicationResult = EffectFactory.apply_result(target.asc, loop)
	assert_not_null(result, "it came back, which is the point")
#endregion


#region Live magnitude self-reference
## A modifier whose magnitude reads, live, the very attribute it writes. Each
## write would change its own input, so it is refused outright rather than
## evaluated once and left to loop the moment anything reacts to it.
func test_a_modifier_reading_the_attribute_it_writes_live_is_refused() -> void:
	var magnitude: GameplayAttributeBasedMagnitude = GameplayAttributeBasedMagnitude.new()
	magnitude.capture = EffectFactory.capture_definition(
		GameplayAttributeCaptureDefinition.Actor.TARGET,
		ATTACK,
		GameplayAttributeCaptureDefinition.Value.CURRENT,
		GameplayAttributeCaptureDefinition.Policy.LIVE
	)

	var modifier: GameplayEffectModifier = GameplayEffectModifier.new()
	modifier.attribute_name = ATTACK
	modifier.operation = GameplayEffectModifier.Operation.ADD
	modifier.magnitude = magnitude

	var before: float = target.current_of(ATTACK)
	var result: GameplayEffectApplicationResult = EffectFactory.apply_result(
		target.asc, EffectFactory.infinite([modifier] as Array[GameplayEffectModifier])
	)

	assert_false(result.is_ok(), "the whole application is refused, not just the modifier")
	assert_eq(target.asc.effects.active_count(), 0)
	assert_almost_eq(target.current_of(ATTACK), before, 0.0001, "and nothing was written")


## The same magnitude reading a DIFFERENT attribute is legal, so the refusal is
## about the self-reference and not about LIVE captures in general.
func test_a_live_magnitude_reading_another_attribute_is_allowed() -> void:
	var magnitude: GameplayAttributeBasedMagnitude = GameplayAttributeBasedMagnitude.new()
	magnitude.capture = EffectFactory.capture_definition(
		GameplayAttributeCaptureDefinition.Actor.TARGET,
		HEALTH,
		GameplayAttributeCaptureDefinition.Value.CURRENT,
		GameplayAttributeCaptureDefinition.Policy.LIVE
	)

	var modifier: GameplayEffectModifier = GameplayEffectModifier.new()
	modifier.attribute_name = ATTACK
	modifier.operation = GameplayEffectModifier.Operation.ADD
	modifier.magnitude = magnitude

	var result: GameplayEffectApplicationResult = EffectFactory.apply_result(
		target.asc, EffectFactory.infinite([modifier] as Array[GameplayEffectModifier])
	)
	assert_true(result.is_ok())
#endregion


#region Unknown modifier operation
## The `_:` branch of the operation match, in both the evaluator and the
## composer. It only fires for an Operation value neither knows - which a
## designer cannot author, but a migration that renumbers the enum, or a
## resource saved by a newer version of the addon, can produce. A guard for a
## state that "cannot happen" is exactly the kind nothing exercises.
func test_a_modifier_carrying_an_unknown_operation_is_refused() -> void:
	var modifier: GameplayEffectModifier = GameplayEffectModifier.new()
	modifier.attribute_name = ATTACK
	modifier.operation = 99 as GameplayEffectModifier.Operation
	modifier.magnitude = EffectFactory.scalable_magnitude(5.0)

	var before: float = target.current_of(ATTACK)
	var result: GameplayEffectApplicationResult = EffectFactory.apply_result(
		target.asc, EffectFactory.infinite([modifier] as Array[GameplayEffectModifier])
	)

	assert_false(result.is_ok(), "an operation nothing can apply is not applied")
	assert_almost_eq(target.current_of(ATTACK), before, 0.0001, "and nothing was written")
	assert_eq(target.asc.effects.active_count(), 0, "and it is not registered")

	# The damage the refusal prevents: a contribution carrying an unknown
	# operation makes `_compose()` bail on the first one it meets, so the
	# attribute stops recomposing for EVERY effect - not just the malformed
	# one. A perfectly ordinary effect applied afterwards has to still work.
	var ordinary: ActiveGameplayEffect = EffectFactory.apply(
		target.asc, EffectFactory.infinite([EffectFactory.add(ATTACK, 7.0)] as Array[GameplayEffectModifier])
	)
	assert_not_null(ordinary)
	assert_almost_eq(target.current_of(ATTACK), before + 7.0, 0.0001, "the attribute still composes")
#endregion


#region Capture that never resolves
## A magnitude reading an attribute the target does not have. The capture
## fails, and the whole application fails with it rather than treating the
## missing attribute as zero.
func test_a_magnitude_capturing_an_attribute_that_does_not_exist_is_refused() -> void:
	var magnitude: GameplayAttributeBasedMagnitude = GameplayAttributeBasedMagnitude.new()
	magnitude.capture = EffectFactory.capture_definition(
		GameplayAttributeCaptureDefinition.Actor.TARGET, ABSENT
	)

	var modifier: GameplayEffectModifier = GameplayEffectModifier.new()
	modifier.attribute_name = ATTACK
	modifier.operation = GameplayEffectModifier.Operation.ADD
	modifier.magnitude = magnitude

	var before: float = target.current_of(ATTACK)
	var result: GameplayEffectApplicationResult = EffectFactory.apply_result(
		target.asc, EffectFactory.infinite([modifier] as Array[GameplayEffectModifier])
	)

	assert_false(result.is_ok())
	assert_almost_eq(target.current_of(ATTACK), before, 0.0001)
	assert_eq(target.asc.effects.active_count(), 0)
#endregion


#region Clocks that are not numbers
## `duration` and `period` are public and meant to be scaled per application, so
## `base / stat` with the stat at zero is how INF arrives. It does not make a
## long effect: an INF duration never counts down, so a DURATION effect silently
## becomes a permanent one, and an INF period is periodic and never ticks. Both
## used to apply and look like a working game.
func test_a_spec_whose_clocks_are_not_numbers_is_refused() -> void:
	# Typed loops rather than a list of pairs: an untyped element reaches the
	# assertions as Variant, which this project treats as an error.
	for field: StringName in [&"duration", &"period"] as Array[StringName]:
		for value: float in [INF, NAN] as Array[float]:
			var spec: GameplayEffectSpec = GameplayEffectSpec.new()
			spec.effect_def = EffectFactory.duration([] as Array[GameplayEffectModifier], 5.0)
			spec.duration = 5.0
			spec.set(field, value)

			var result: GameplayEffectApplicationResult = target.asc.effects.apply(spec)

			assert_eq(
				result.status, GameplayEffectApplicationResult.Status.INVALID_SPEC,
				"%s = %s is refused, not applied" % [field, value]
			)
			assert_eq(target.asc.effects.active_count(), 0, "and nothing was registered")


func test_a_spec_whose_clocks_are_numbers_still_applies() -> void:
	# The refusal must not have eaten the ordinary case - and this is the same
	# spec shape as above with the one field left alone.
	var spec: GameplayEffectSpec = GameplayEffectSpec.new()
	spec.effect_def = EffectFactory.duration([] as Array[GameplayEffectModifier], 5.0)
	spec.duration = 5.0

	var result: GameplayEffectApplicationResult = target.asc.effects.apply(spec)

	assert_true(result.is_ok(), "a finite duration applies")
	assert_eq(target.asc.effects.active_count(), 1, "and is registered")
#endregion
