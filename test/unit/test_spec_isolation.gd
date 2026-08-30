## One application, one spec. An AoE must not let one target's evaluation
## change what another receives.
##
## A GameplayEffectSpec is RefCounted and holds mutable state - duration,
## runtime magnitudes, dynamic tags, the context. Upstream built one and passed
## it to every target, so target A's execution calculation mutating a magnitude
## changed the damage target B took.
##
## @meta_license: MIT
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Factory = preload("res://test/fixtures/test_effect_factory.gd")

const TOLERANCE: float = 0.0001
const ATTACK: StringName = &"attack"
const CRITICAL: StringName = &"Hit.Critical"

var source: ASCFixture = null
var target_a: ASCFixture = null
var target_b: ASCFixture = null


func before_each() -> void:
	source = Fixture.create("Caster")
	target_a = Fixture.create("TargetA")
	target_b = Fixture.create("TargetB")
	add_child_autofree(source.owner)
	add_child_autofree(target_a.owner)
	add_child_autofree(target_b.owner)


func after_each() -> void:
	source = null
	target_a = null
	target_b = null


func _shared_spec(effect: GameplayEffect) -> GameplayEffectSpec:
	return GameplayEffectSpec.new(effect, GameplayEffectContext.new(source.owner))


#region Context
func test_the_instigator_arrives_intact() -> void:
	var context: GameplayEffectContext = GameplayEffectContext.new(source.owner)
	assert_eq(context.instigator, source.owner)


func test_the_causer_defaults_to_the_instigator() -> void:
	var context: GameplayEffectContext = GameplayEffectContext.new(source.owner)
	assert_eq(context.causer, source.owner, "no separate causer means the instigator caused it")


func test_a_distinct_causer_is_preserved() -> void:
	var projectile: Node = Node.new()
	add_child_autofree(projectile)
	var context: GameplayEffectContext = GameplayEffectContext.new(source.owner, projectile)
	assert_eq(context.instigator, source.owner, "who cast it")
	assert_eq(context.causer, projectile, "what hit them")


func test_the_level_travels_with_the_spec() -> void:
	var spec: GameplayEffectSpec = GameplayEffectSpec.new(
		Factory.infinite([Factory.add(ATTACK, 1.0)]), GameplayEffectContext.new(source.owner), 7.0
	)
	assert_almost_eq(spec.level, 7.0, TOLERANCE)


func test_source_and_target_are_different_nodes() -> void:
	# A suite where both sides are the same node can pass while the engine
	# conflates them, so this is asserted rather than assumed.
	assert_ne(source.owner, target_a.owner)
	assert_ne(target_a.owner, target_b.owner)
	assert_ne(source.asc, target_a.asc)
#endregion


#region Copy contract
func test_a_copy_shares_the_definition_and_nothing_mutable() -> void:
	var effect: GameplayEffect = Factory.infinite([Factory.add(ATTACK, 10.0)])
	var original: GameplayEffectSpec = _shared_spec(effect)
	var copy: GameplayEffectSpec = original.create_application_copy()

	assert_eq(copy.effect_def, original.effect_def, "the definition is immutable and shared")
	assert_ne(copy, original, "the spec is not")
	assert_ne(copy.context, original.context, "the context is mutable, so it is not shared")
	# Two empty arrays compare equal by value, so identity is shown by mutating
	# one and reading the other. `assert_ne` on the arrays themselves would
	# pass for the wrong reason the moment either held an element.
	copy.inject_tag(&"Probe")
	assert_true(copy.has_tag(&"Probe"), "the copy took the tag")
	assert_false(original.has_tag(&"Probe"), "the original did not")


func test_the_copy_carries_the_logical_origin() -> void:
	var copy: GameplayEffectSpec = _shared_spec(
		Factory.infinite([Factory.add(ATTACK, 10.0)])
	).create_application_copy()
	assert_eq(copy.context.instigator, source.owner, "who cast it survives the copy")


func test_mutating_a_copy_is_invisible_to_the_original() -> void:
	var original: GameplayEffectSpec = _shared_spec(
		Factory.infinite([Factory.add(ATTACK, 10.0), Factory.multiply(ATTACK, 2.0)])
	)
	var copy: GameplayEffectSpec = original.create_application_copy()

	copy.set_magnitude(0, 999.0)
	copy.inject_tag(CRITICAL)
	copy.duration = 42.0

	assert_almost_eq(original.get_magnitude(0), 10.0, TOLERANCE, "magnitude untouched")
	assert_false(original.has_tag(CRITICAL), "tag untouched")
	assert_almost_eq(original.duration, 0.0, TOLERANCE, "duration untouched")
#endregion


#region Multi-target application
func test_two_targets_receive_independent_specs() -> void:
	var effect: GameplayEffect = Factory.infinite([Factory.add(ATTACK, 10.0)])
	var spec: GameplayEffectSpec = _shared_spec(effect)

	var applied_a: ActiveGameplayEffect = source.asc.apply_effect_spec_to_target(spec, target_a.asc)
	var applied_b: ActiveGameplayEffect = source.asc.apply_effect_spec_to_target(spec, target_b.asc)

	assert_not_null(applied_a)
	assert_not_null(applied_b)
	assert_ne(applied_a.spec, applied_b.spec, "each target owns its spec")
	assert_ne(applied_a.spec, spec, "and neither is the one the caller built")
	assert_ne(applied_a.spec.context, applied_b.spec.context, "contexts are separate too")


func test_mutating_one_target_runtime_state_leaves_the_other_alone() -> void:
	var effect: GameplayEffect = Factory.duration([Factory.add(ATTACK, 10.0)], 5.0)
	var spec: GameplayEffectSpec = _shared_spec(effect)

	var applied_a: ActiveGameplayEffect = source.asc.apply_effect_spec_to_target(spec, target_a.asc)
	var applied_b: ActiveGameplayEffect = source.asc.apply_effect_spec_to_target(spec, target_b.asc)

	# Reach in and change A's runtime state the way an execution calculation
	# would, then check B.
	applied_a.spec.set_magnitude(0, 500.0)
	applied_a.spec.inject_tag(CRITICAL)
	applied_a.time_remaining = 0.25
	applied_a.elapsed_time = 3.0

	assert_almost_eq(applied_b.spec.get_magnitude(0), 10.0, TOLERANCE, "B keeps its magnitude")
	assert_false(applied_b.spec.has_tag(CRITICAL), "B did not gain A's tag")
	assert_almost_eq(applied_b.time_remaining, 5.0, TOLERANCE, "B keeps its duration")
	assert_almost_eq(applied_b.elapsed_time, 0.0, TOLERANCE, "B keeps its clock")


func test_each_target_computes_against_its_own_attributes() -> void:
	target_a.set_base(ATTACK, 10.0)
	target_b.set_base(ATTACK, 100.0)

	var spec: GameplayEffectSpec = _shared_spec(
		Factory.infinite([Factory.add(ATTACK, 10.0), Factory.multiply(ATTACK, 2.0)])
	)
	source.asc.apply_effect_spec_to_target(spec, target_a.asc)
	source.asc.apply_effect_spec_to_target(spec, target_b.asc)

	assert_almost_eq(target_a.current_of(ATTACK), 40.0, TOLERANCE, "(10 + 10) * 2")
	assert_almost_eq(target_b.current_of(ATTACK), 220.0, TOLERANCE, "(100 + 10) * 2")


func test_removing_one_targets_effect_leaves_the_other_running() -> void:
	target_a.set_base(ATTACK, 10.0)
	target_b.set_base(ATTACK, 10.0)
	var spec: GameplayEffectSpec = _shared_spec(Factory.infinite([Factory.add(ATTACK, 10.0)]))

	var applied_a: ActiveGameplayEffect = source.asc.apply_effect_spec_to_target(spec, target_a.asc)
	source.asc.apply_effect_spec_to_target(spec, target_b.asc)

	target_a.asc.remove_active_effect(applied_a)
	assert_almost_eq(target_a.current_of(ATTACK), 10.0, TOLERANCE, "A reverted")
	assert_almost_eq(target_b.current_of(ATTACK), 20.0, TOLERANCE, "B unaffected")
#endregion


#region Attacker notification
func test_the_attacker_hears_about_its_own_hit() -> void:
	watch_signals(source.asc)
	var spec: GameplayEffectSpec = _shared_spec(Factory.infinite([Factory.add(ATTACK, 10.0)]))
	source.asc.apply_effect_spec_to_target(spec, target_a.asc)
	assert_signal_emitted(source.asc, "effect_applied_to_target")


func test_the_defender_hears_that_it_was_hit() -> void:
	watch_signals(target_a.asc)
	var spec: GameplayEffectSpec = _shared_spec(Factory.infinite([Factory.add(ATTACK, 10.0)]))
	source.asc.apply_effect_spec_to_target(spec, target_a.asc)
	assert_signal_emitted(target_a.asc, "effect_received")
#endregion
