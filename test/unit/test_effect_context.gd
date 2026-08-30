## The effect context: who cast this, with what, and at what level.
##
## Split from test_spec_isolation.gd so the plan's file list is real rather
## than approximated. The tests moved; none were duplicated, because two
## copies of an assertion drift the first time either is tuned.
##
## @meta_license: MIT
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Factory = preload("res://test/fixtures/test_effect_factory.gd")

const TOLERANCE: float = 0.0001
const ATTACK: StringName = &"attack"

var source: ASCFixture = null
var target_a: ASCFixture = null


func before_each() -> void:
	source = Fixture.create("Caster")
	target_a = Fixture.create("TargetA")
	add_child_autofree(source.owner)
	add_child_autofree(target_a.owner)


func after_each() -> void:
	source = null
	target_a = null


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
	assert_ne(source.asc, target_a.asc)
#endregion
