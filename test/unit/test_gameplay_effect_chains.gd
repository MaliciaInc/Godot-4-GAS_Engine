## GameplayEffectAdditionalEffectsComponent: effects applied at declared
## lifecycle points - on_application, on_natural_expiration,
## on_premature_removal, on_any_removal - and the chain_depth guard they
## share with Task 12's overflow_effects.
##
## @meta_license: MIT
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Factory = preload("res://test/fixtures/test_effect_factory.gd")

const ATTACK: StringName = &"attack"
const TOLERANCE: float = 0.0001

var source: ASCFixture = null
var target: ASCFixture = null


func before_each() -> void:
	source = Fixture.create("Source")
	target = Fixture.create("Target")
	add_child_autofree(source.owner)
	add_child_autofree(target.owner)


func after_each() -> void:
	source = null
	target = null


func _tag_query(tags: Array[StringName]) -> GameplayTagQuery:
	var expression: GameplayTagQueryExpression = GameplayTagQueryExpression.new()
	expression.operator = GameplayTagQueryExpression.Operator.ALL
	expression.tags = tags
	var query: GameplayTagQuery = GameplayTagQuery.new()
	query.root = expression
	return query


#region Application chain
func test_on_application_applies_the_child_to_the_same_target() -> void:
	var child: GameplayEffect = Factory.infinite([Factory.add(ATTACK, 3.0)])
	var parent: GameplayEffect = Factory.with_additional_effects(
		Factory.infinite([]), [Factory.conditional_effect(child)]
	)
	var base: float = target.current_of(ATTACK)

	Factory.apply(target.asc, parent)
	assert_almost_eq(target.current_of(ATTACK), base + 3.0, TOLERANCE)
	assert_eq(target.asc.get_active_effects().size(), 2, "parent and child both registered")


func test_on_application_respects_the_target_query() -> void:
	var child: GameplayEffect = Factory.infinite([Factory.add(ATTACK, 3.0)])
	var parent: GameplayEffect = Factory.with_additional_effects(
		Factory.infinite([]), [Factory.conditional_effect(child, _tag_query([&"Status.Wet"]))]
	)
	var base: float = target.current_of(ATTACK)

	Factory.apply(target.asc, parent)
	assert_almost_eq(target.current_of(ATTACK), base, TOLERANCE, "target lacks the tag, child never applied")

	target.asc.add_tag(&"Status.Wet")
	Factory.apply(target.asc, parent)
	assert_almost_eq(target.current_of(ATTACK), base + 3.0, TOLERANCE, "now it matches")


func test_on_application_respects_the_source_query() -> void:
	var child: GameplayEffect = Factory.infinite([Factory.add(ATTACK, 3.0)])
	var parent: GameplayEffect = Factory.with_additional_effects(
		Factory.infinite([]), [Factory.conditional_effect(child, null, _tag_query([&"Class.Mage"]))]
	)
	var base: float = target.current_of(ATTACK)

	Factory.apply(target.asc, parent, source.owner)
	assert_almost_eq(target.current_of(ATTACK), base, TOLERANCE, "source lacks the tag")

	source.asc.add_tag(&"Class.Mage")
	Factory.apply(target.asc, parent, source.owner)
	assert_almost_eq(target.current_of(ATTACK), base + 3.0, TOLERANCE)
#endregion


#region Removal chains
func test_natural_expiration_fires_its_own_chain_and_any_removal() -> void:
	var on_natural: GameplayEffect = Factory.infinite([Factory.add(ATTACK, 3.0)])
	var on_any: GameplayEffect = Factory.granting(Factory.infinite([]), [&"Status.EverRemoved"])
	var parent: GameplayEffect = Factory.with_additional_effects(
		Factory.duration([], 1.0), [], [Factory.conditional_effect(on_natural)], [], [Factory.conditional_effect(on_any)]
	)
	var base: float = target.current_of(ATTACK)

	Factory.apply(target.asc, parent)
	target.asc.scheduler.advance_time(2.0)

	assert_almost_eq(target.current_of(ATTACK), base + 3.0, TOLERANCE, "on_natural_expiration fired")
	assert_true(target.asc.has_tag(&"Status.EverRemoved"), "on_any_removal fired too")


func test_premature_removal_fires_its_own_chain_and_any_removal_but_not_natural() -> void:
	var on_natural: GameplayEffect = Factory.infinite([Factory.add(ATTACK, 3.0)])
	var on_premature: GameplayEffect = Factory.infinite([Factory.add(ATTACK, 7.0)])
	var on_any: GameplayEffect = Factory.granting(Factory.infinite([]), [&"Status.EverRemoved"])
	var parent: GameplayEffect = Factory.with_additional_effects(
		Factory.infinite([]),
		[], [Factory.conditional_effect(on_natural)], [Factory.conditional_effect(on_premature)], [Factory.conditional_effect(on_any)]
	)
	var base: float = target.current_of(ATTACK)
	var active: ActiveGameplayEffect = Factory.apply(target.asc, parent)

	target.asc.effects.remove(active)
	assert_almost_eq(target.current_of(ATTACK), base + 7.0, TOLERANCE, "on_premature_removal fired, on_natural did not")
	assert_true(target.asc.has_tag(&"Status.EverRemoved"), "on_any_removal fired too")


func test_asc_cleanup_fires_no_additional_effects_chain() -> void:
	var on_any: GameplayEffect = Factory.granting(Factory.infinite([]), [&"Status.EverRemoved"])
	var parent: GameplayEffect = Factory.with_additional_effects(
		Factory.infinite([]), [], [], [], [Factory.conditional_effect(on_any)]
	)
	Factory.apply(target.asc, parent)

	target.asc.cleanup()
	assert_false(target.asc.has_tag(&"Status.EverRemoved"), "ASC_CLEANUP never fires a chain")
#endregion


#region Child context
func test_the_child_copies_instigator_causer_and_source_tags() -> void:
	source.asc.add_tag(&"Class.Mage")
	var captured_source: ASCFixture = null
	var probe: GameplayEffect = Factory.infinite([])
	var parent: GameplayEffect = Factory.with_additional_effects(
		Factory.infinite([]), [Factory.conditional_effect(probe)]
	)

	var result: ActiveGameplayEffect = Factory.apply(target.asc, parent, source.owner)
	var child: ActiveGameplayEffect = null
	for active: ActiveGameplayEffect in target.asc.get_active_effects():
		if active.get_effect_def() == probe:
			child = active
	assert_not_null(child, "the child registered")
	assert_eq(child.get_instigator(), source.owner)
	assert_eq(child.spec.source_asc, source.asc)
	assert_true(child.spec.source_tags_snapshot.has(&"Class.Mage"))


## Task 21: ability handle, source object and context payloads carry into an
## Additional Effects child the same way instigator/causer already do -
## GameplayEffectChainRuntime._build_child() routes through
## GameplayEffectContext.create_application_copy() rather than
## reconstructing a bare context by hand.
func test_the_child_inherits_ability_handle_source_object_and_payloads() -> void:
	var probe: GameplayEffect = Factory.infinite([])
	var parent_effect: GameplayEffect = Factory.with_additional_effects(
		Factory.infinite([]), [Factory.conditional_effect(probe)]
	)

	var handle: GameplayAbilityHandle = GameplayAbilityHandle.new()
	handle.owner_instance_id = 1
	handle.id = 1
	var weapon: Node = Node.new()
	add_child_autofree(weapon)
	var payload: GameplayHitContextPayload = GameplayHitContextPayload.new()
	payload.hit = GameplayTargetHit.new()

	var context: GameplayEffectContext = GameplayEffectContext.new(source.owner)
	context.ability_handle = handle
	context.source_object = weapon
	context.add_payload(payload)
	var parent_spec: GameplayEffectSpec = GameplayEffectSpec.new(parent_effect, context)

	target.asc.apply_effect_spec_result(parent_spec)
	var child: ActiveGameplayEffect = null
	for active: ActiveGameplayEffect in target.asc.get_active_effects():
		if active.get_effect_def() == probe:
			child = active

	assert_not_null(child, "the child registered")
	assert_eq(child.spec.context.ability_handle, handle)
	assert_eq(child.spec.context.source_object, weapon)
	assert_eq(child.spec.context.payloads.size(), 1)
	assert_ne(child.spec.context.payloads[0], payload, "deep-copied, not shared")
#endregion


#region Chaining and cycles
func test_a_three_level_chain_applies_all_three() -> void:
	var c: GameplayEffect = Factory.granting(Factory.infinite([]), [&"Status.C"])
	var b: GameplayEffect = Factory.with_additional_effects(
		Factory.granting(Factory.infinite([]), [&"Status.B"]), [Factory.conditional_effect(c)]
	)
	var a: GameplayEffect = Factory.with_additional_effects(
		Factory.granting(Factory.infinite([]), [&"Status.A"]), [Factory.conditional_effect(b)]
	)

	Factory.apply(target.asc, a)
	assert_true(target.asc.has_tag(&"Status.A"))
	assert_true(target.asc.has_tag(&"Status.B"))
	assert_true(target.asc.has_tag(&"Status.C"))


func test_a_self_referencing_chain_stops_at_the_depth_limit() -> void:
	var cycle: GameplayEffect = Factory.instant([])
	var component: GameplayEffectAdditionalEffectsComponent = GameplayEffectAdditionalEffectsComponent.new()
	component.on_application = [Factory.conditional_effect(cycle)]
	cycle.components.append(component)

	# Never hangs and never blows the call stack - the only observable proof
	# from outside is that this returns at all within a normal test timeout.
	var result: GameplayEffectApplicationResult = Factory.apply_result(target.asc, cycle)
	assert_true(result.is_ok(), "the root application itself is never the one refused")


func test_a_refused_child_leaves_the_committed_parent_untouched() -> void:
	var broken_child: GameplayEffect = Factory.infinite([Factory.divide(ATTACK, 0.0)])
	var parent: GameplayEffect = Factory.with_additional_effects(
		Factory.infinite([Factory.add(ATTACK, 5.0)]), [Factory.conditional_effect(broken_child)]
	)
	var base: float = target.current_of(ATTACK)

	var result: GameplayEffectApplicationResult = Factory.apply_result(target.asc, parent)
	assert_true(result.is_ok(), "the parent's own application still succeeded")
	assert_almost_eq(target.current_of(ATTACK), base + 5.0, TOLERANCE, "the parent's own contribution landed")
	assert_eq(target.asc.get_active_effects().size(), 1, "the broken child never registered")
#endregion


#region Stacking and inhibition interaction
func test_a_stack_that_fully_expires_naturally_fires_the_chain() -> void:
	var on_natural: GameplayEffect = Factory.granting(Factory.infinite([]), [&"Status.StackExpired"])
	var parent: GameplayEffect = Factory.with_additional_effects(
		Factory.stacked(Factory.duration([], 1.0), GameplayEffect.StackingType.AGGREGATE_BY_TARGET, 0),
		[], [Factory.conditional_effect(on_natural)]
	)
	var active: ActiveGameplayEffect = Factory.apply(target.asc, parent)
	Factory.apply(target.asc, parent)
	assert_eq(active.stack_count, 2)

	target.asc.effects.expire(active)
	assert_true(target.asc.has_tag(&"Status.StackExpired"), "CLEAR_ENTIRE_STACK expiration is still NATURAL_EXPIRATION")


func test_an_inhibited_parents_natural_expiration_still_fires_the_chain() -> void:
	target.asc.add_tag(&"Status.Blessed")
	var on_natural: GameplayEffect = Factory.granting(Factory.infinite([]), [&"Status.ExpiredWhileInhibited"])
	var parent: GameplayEffect = Factory.with_ongoing_requirement(
		Factory.with_additional_effects(Factory.duration([], 1.0), [], [Factory.conditional_effect(on_natural)]),
		[&"Status.Blessed"]
	)
	var active: ActiveGameplayEffect = Factory.apply(target.asc, parent)
	target.asc.remove_tag(&"Status.Blessed")
	assert_true(active.inhibited)

	target.asc.scheduler.advance_time(2.0)
	assert_true(target.asc.has_tag(&"Status.ExpiredWhileInhibited"), "the chain still fired for an inhibited parent")
#endregion
