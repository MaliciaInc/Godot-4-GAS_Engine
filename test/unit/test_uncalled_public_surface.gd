## The public functions this addon ships that nothing inside it ever calls.
##
## GAS_Engine is a reusable addon, so its caller is somebody else's game: a
## function with no call site here is not dead code, it is untested code, and
## nothing proved any of these worked. Five were found by asking, of every
## public function, how many references exist anywhere in the repository -
## these are the ones whose only reference was their own declaration.
##
## The sixth and seventh found that way were the ability-task factories, and
## covering those turned up a real defect: removal was announced to subscribers
## after the effect had already been emptied. So this file is not a formality.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const EffectFactory = preload("res://test/fixtures/test_effect_factory.gd")
const AbilityFactory = preload("res://test/fixtures/test_ability_factory.gd")
const Fixture = preload("res://test/fixtures/asc_fixture.gd")

const ATTACK: StringName = &"attack"
const DAMAGE: StringName = &"Data.Damage"

var target: ASCFixture = null


func before_each() -> void:
	target = Fixture.create("Surface")
	add_child_autofree(target.owner)
	target.asc.set_process(false)


func after_each() -> void:
	target = null


func _any_of(tag: StringName) -> GameplayTagQuery:
	var expression: GameplayTagQueryExpression = GameplayTagQueryExpression.new()
	expression.operator = GameplayTagQueryExpression.Operator.ANY
	expression.tags = [tag] as Array[StringName]
	var query: GameplayTagQuery = GameplayTagQuery.new()
	query.root = expression
	return query


#region GameplayAttributeRuntime.contribution_count()
## Counts every contribution, not every effect: one effect with two modifiers
## is two. Nothing in the addon reads it - it exists for a game's own HUD or
## for a test like this one.
func test_contribution_count_counts_modifiers_and_not_effects() -> void:
	assert_eq(target.asc.attributes.contribution_count(), 0, "nothing applied yet")

	var two: Array[GameplayEffectModifier] = [
		EffectFactory.add(ATTACK, 5.0), EffectFactory.add(ATTACK, 3.0)
	]
	var active: ActiveGameplayEffect = EffectFactory.apply(target.asc, EffectFactory.infinite(two))
	assert_eq(target.asc.attributes.contribution_count(), 2, "one effect, two modifiers")

	target.asc.remove_active_effect(active)
	assert_eq(target.asc.attributes.contribution_count(), 0, "and removal takes both back")
#endregion


#region AbilityRuntime.can_activate()
## The boolean shorthand for `activation_error(spec) == NONE`. The ASC's own
## `can_activate_ability()` takes an instance and can emit a failure signal;
## this one takes a spec and is silent, which is why both exist.
func test_can_activate_agrees_with_the_error_it_is_shorthand_for() -> void:
	var spec: GameplayAbilitySpec = AbilityFactory.give(
		target.asc, ProbeAbility.build(&"Ability.SurfaceCanActivate")
	)
	assert_true(target.asc.ability_runtime.can_activate(spec), "a granted, ungated ability")

	# A blocked-tag gate, which is a real ActivationError rather than a
	# contrived one. Set on the ability before it is given: the definition the
	# spec carries is a snapshot taken at grant time.
	var probe: ProbeAbility = ProbeAbility.build(&"Ability.SurfaceBlocked")
	probe.activation_blocked_query = _any_of(&"Status.Silenced")
	var blocked: GameplayAbilitySpec = AbilityFactory.give(target.asc, probe)
	target.asc.add_tag(&"Status.Silenced")

	assert_false(target.asc.ability_runtime.can_activate(blocked))
	assert_ne(
		target.asc.ability_runtime.activation_error(blocked),
		AbilityRuntime.ActivationError.NONE,
		"and it is false for the same reason the error reports"
	)
#endregion


#region GameplayEffectSpec.has_set_by_caller()
## Asks whether a magnitude was supplied without evaluating it, so a caller can
## branch before `get_set_by_caller()` turns a missing one into a failure.
func test_has_set_by_caller_answers_before_the_value_is_asked_for() -> void:
	var spec: GameplayEffectSpec = GameplayEffectSpec.new()
	spec.effect_def = EffectFactory.instant([] as Array[GameplayEffectModifier])
	assert_false(spec.has_set_by_caller(DAMAGE), "nothing supplied it yet")
	assert_eq(
		spec.get_set_by_caller(DAMAGE).status,
		GameplayMagnitudeResult.Status.MISSING_SET_BY_CALLER,
		"which is exactly what asking for it would have reported"
	)

	assert_true(spec.set_set_by_caller(DAMAGE, 12.0))
	assert_true(spec.has_set_by_caller(DAMAGE))
	assert_almost_eq(spec.get_set_by_caller(DAMAGE).value, 12.0, 0.0001)
#endregion


#region ActiveGameplayEffect.tick_time()
## When the Nth tick was due, for a cue that wants to say when something
## happened rather than when it was processed. Zero for a non-periodic effect,
## which is why the check is `is_periodic()` and not a division.
func test_tick_time_reports_the_instant_a_tick_was_due() -> void:
	var periodic: GameplayEffect = EffectFactory.infinite_periodic(
		[EffectFactory.add(ATTACK, 1.0)] as Array[GameplayEffectModifier], 2.0
	)
	var active: ActiveGameplayEffect = EffectFactory.apply(target.asc, periodic)
	assert_true(active.is_periodic())

	assert_almost_eq(active.tick_time(0), active.period_origin_elapsed, 0.0001)
	assert_almost_eq(active.tick_time(1), active.period_origin_elapsed + 2.0, 0.0001)
	assert_almost_eq(active.tick_time(3), active.period_origin_elapsed + 6.0, 0.0001)


## Restarting the period moves the origin; it does not wind the total clock
## back. GameplayEffectStackingRuntime used to zero elapsed_time, so tick_time()
## - the public "when did this happen" - answered from zero after a stack reset
## and from the true instant after an inhibition one. Same question, two answers.
func test_restarting_the_period_clock_keeps_the_total_clock() -> void:
	var periodic: GameplayEffect = EffectFactory.infinite_periodic(
		[EffectFactory.add(ATTACK, 1.0)] as Array[GameplayEffectModifier], 2.0
	)
	var active: ActiveGameplayEffect = EffectFactory.apply(target.asc, periodic)
	active.consume_ticks(active.advance_clock(30.0))
	assert_eq(active.completed_ticks, 15, "fifteen ticks were paid")

	active.restart_period_clock()

	assert_almost_eq(active.elapsed_time, 30.0, 0.0001, "the total clock is untouched")
	assert_eq(active.completed_ticks, 0, "while the tick count starts over")
	assert_almost_eq(
		active.tick_time(1), 32.0, 0.0001,
		"so the next tick reports its real instant, not one period from zero"
	)


func test_tick_time_is_zero_for_an_effect_that_never_ticks() -> void:
	var active: ActiveGameplayEffect = EffectFactory.apply(
		target.asc, EffectFactory.infinite([] as Array[GameplayEffectModifier])
	)
	assert_false(active.is_periodic())
	assert_almost_eq(active.tick_time(4), 0.0, 0.0001)
#endregion


#region GameplayAssetValidationResult.warning()
## The severity is the only difference from `error()`, and it is built by
## calling `error()` rather than repeating its four assignments - so the test
## that matters is that the severity actually differs.
func test_warning_differs_from_error_only_in_severity() -> void:
	var asset: GameplayEffect = EffectFactory.instant([] as Array[GameplayEffectModifier])
	var code: GameplayAssetValidationResult.Code = GameplayAssetValidationResult.Code.OK

	var raised: GameplayAssetValidationResult = GameplayAssetValidationResult.error(asset, "modifiers[0]", code)
	var noted: GameplayAssetValidationResult = GameplayAssetValidationResult.warning(asset, "modifiers[0]", code)

	assert_eq(raised.severity, GameplayAssetValidationResult.Severity.ERROR)
	assert_eq(noted.severity, GameplayAssetValidationResult.Severity.WARNING)
	assert_same(noted.asset, raised.asset)
	assert_eq(noted.field, raised.field)
	assert_eq(noted.code, raised.code)
#endregion
