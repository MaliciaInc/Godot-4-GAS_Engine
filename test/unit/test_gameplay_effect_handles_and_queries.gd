## GameplayEffectHandle identity and GameplayEffectQuery matching.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Factory = preload("res://test/fixtures/test_effect_factory.gd")

const ATTACK: StringName = &"attack"
const HEALTH: StringName = &"health"
const TOLERANCE: float = 0.0001

var source: ASCFixture = null
var target: ASCFixture = null


## Declares HEALTH as its output without ever executing - matched by
## GameplayEffectQuery.modified_attribute purely on this metadata.
class DeclaresHealthOutput extends GameplayExecutionCalculation:
	func declared_output_attributes() -> Array[StringName]:
		return [&"health"]

	func execute(_spec: GameplayEffectSpec, _target_asc: AbilitySystemComponent) -> Dictionary[StringName, float]:
		return {}


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


#region Handle identity
func test_handle_ids_are_monotonic_within_one_asc() -> void:
	var first: ActiveGameplayEffect = Factory.apply(target.asc, Factory.infinite([]))
	var second: ActiveGameplayEffect = Factory.apply(target.asc, Factory.infinite([]))
	assert_true(second.handle.id > first.handle.id)


func test_an_invalid_handle_is_invalid_and_never_resolves() -> void:
	var handle: GameplayEffectHandle = GameplayEffectHandle.new()
	assert_false(handle.is_valid())
	assert_null(target.asc.get_active_effect(handle))
	assert_false(target.asc.remove_active_effect_by_handle(handle))


## Two ASCs each starting their own ids at 1 do not collide: same_as() says
## no even when both handles' local id happens to match, and a handle from
## one ASC neither resolves nor removes on the other - only on its own.
func test_a_handle_from_another_asc_neither_matches_nor_resolves_here() -> void:
	var target_b: ASCFixture = Fixture.create("TargetB")
	add_child_autofree(target_b.owner)

	var active_a: ActiveGameplayEffect = Factory.apply(target.asc, Factory.infinite([]))
	var active_b: ActiveGameplayEffect = Factory.apply(target_b.asc, Factory.infinite([]))

	assert_false(active_a.handle.same_as(active_b.handle), "same local id, different owner")
	assert_null(target_b.asc.get_active_effect(active_a.handle))
	assert_false(target_b.asc.remove_active_effect_by_handle(active_a.handle))
	assert_not_null(target.asc.get_active_effect(active_a.handle), "still resolves on its own ASC")


func test_get_resolves_the_active_effect_by_handle() -> void:
	var active: ActiveGameplayEffect = Factory.apply(target.asc, Factory.infinite([]))
	assert_same(target.asc.get_active_effect(active.handle), active)


func test_remove_by_handle_removes_exactly_that_effect() -> void:
	var active: ActiveGameplayEffect = Factory.apply(target.asc, Factory.infinite([]))
	assert_true(target.asc.remove_active_effect_by_handle(active.handle))
	assert_null(target.asc.get_active_effect(active.handle))
	assert_eq(target.asc.get_active_effects().size(), 0)


func test_cleanup_makes_every_handle_stop_resolving_without_recycling_ids() -> void:
	var first: ActiveGameplayEffect = Factory.apply(target.asc, Factory.infinite([]))
	target.asc.cleanup()
	assert_null(target.asc.get_active_effect(first.handle))

	var second: ActiveGameplayEffect = Factory.apply(target.asc, Factory.infinite([]))
	assert_true(second.handle.id > first.handle.id, "ids are never reused")


func test_a_stale_handle_does_not_affect_a_new_effect() -> void:
	var first: ActiveGameplayEffect = Factory.apply(target.asc, Factory.infinite([]))
	var stale: GameplayEffectHandle = first.handle
	target.asc.remove_active_effect_by_handle(stale)

	var second: ActiveGameplayEffect = Factory.apply(target.asc, Factory.infinite([]))
	assert_false(target.asc.remove_active_effect_by_handle(stale), "stale handle removes nothing")
	assert_not_null(target.asc.get_active_effect(second.handle), "the new effect is untouched")
#endregion


#region Query matching
func test_an_empty_query_matches_everything() -> void:
	Factory.apply(target.asc, Factory.infinite([]))
	Factory.apply(target.asc, Factory.infinite([]))
	assert_eq(target.asc.count_active_effects(GameplayEffectQuery.new()), 2)


func test_effect_definition_filters_by_the_exact_asset() -> void:
	var wanted: GameplayEffect = Factory.infinite([])
	var other: GameplayEffect = Factory.infinite([])
	Factory.apply(target.asc, wanted)
	Factory.apply(target.asc, other)

	var query: GameplayEffectQuery = GameplayEffectQuery.new()
	query.effect_definition = wanted
	assert_eq(target.asc.count_active_effects(query), 1)


func test_asset_tags_filter_by_the_effects_asset_tags_component() -> void:
	var tagged: GameplayEffect = Factory.infinite([])
	var asset_component: GameplayEffectAssetTagsComponent = GameplayEffectAssetTagsComponent.new()
	asset_component.asset_tags = [&"Asset.Fire"]
	tagged.components.append(asset_component)
	Factory.apply(target.asc, tagged)
	Factory.apply(target.asc, Factory.infinite([]))

	var query: GameplayEffectQuery = GameplayEffectQuery.new()
	query.asset_tags = _tag_query([&"Asset.Fire"])
	assert_eq(target.asc.count_active_effects(query), 1)


func test_granted_tags_filter_by_what_the_effect_actually_grants() -> void:
	Factory.apply(target.asc, Factory.granting(Factory.infinite([]), [&"Status.Buffed"]))
	Factory.apply(target.asc, Factory.infinite([]))

	var query: GameplayEffectQuery = GameplayEffectQuery.new()
	query.granted_tags = _tag_query([&"Status.Buffed"])
	assert_eq(target.asc.count_active_effects(query), 1)


func test_source_tags_filter_by_a_snapshot_taken_at_application() -> void:
	source.asc.add_tag(&"Class.Mage")
	var applied: ActiveGameplayEffect = Factory.apply(target.asc, Factory.infinite([]), source.owner)
	source.asc.remove_tag(&"Class.Mage")

	var query: GameplayEffectQuery = GameplayEffectQuery.new()
	query.source_tags = _tag_query([&"Class.Mage"])
	assert_eq(target.asc.count_active_effects(query), 1, "the snapshot survived the source losing the tag")
	assert_true(target.asc.find_active_effect_handles(query)[0].same_as(applied.handle))


func test_target_tags_are_read_live_from_the_owning_asc() -> void:
	Factory.apply(target.asc, Factory.infinite([]))
	var query: GameplayEffectQuery = GameplayEffectQuery.new()
	query.target_tags = _tag_query([&"Status.Marked"])

	assert_eq(target.asc.count_active_effects(query), 0)
	target.asc.add_tag(&"Status.Marked")
	assert_eq(target.asc.count_active_effects(query), 1, "read live, not snapshotted at match time")


func test_source_node_filters_by_who_caused_the_application() -> void:
	Factory.apply(target.asc, Factory.infinite([]), source.owner)
	Factory.apply(target.asc, Factory.infinite([]))

	var query: GameplayEffectQuery = GameplayEffectQuery.new()
	query.source = source.owner
	assert_eq(target.asc.count_active_effects(query), 1)


func test_modified_attribute_matches_a_standard_modifiers_target() -> void:
	Factory.apply(target.asc, Factory.infinite([Factory.add(ATTACK, 5.0)]))
	Factory.apply(target.asc, Factory.infinite([Factory.add(HEALTH, 5.0)]))

	var query: GameplayEffectQuery = GameplayEffectQuery.new()
	query.modified_attribute = ATTACK
	assert_eq(target.asc.count_active_effects(query), 1)


func test_modified_attribute_matches_an_executions_declared_output() -> void:
	var effect: GameplayEffect = Factory.infinite([])
	effect.executions = [DeclaresHealthOutput.new()] as Array[GameplayExecutionCalculation]
	Factory.apply(target.asc, effect)
	Factory.apply(target.asc, Factory.infinite([Factory.add(ATTACK, 5.0)]))

	var query: GameplayEffectQuery = GameplayEffectQuery.new()
	query.modified_attribute = HEALTH
	assert_eq(target.asc.count_active_effects(query), 1)


func test_multiple_conditions_are_combined_with_and() -> void:
	Factory.apply(
		target.asc, Factory.granting(Factory.infinite([Factory.add(ATTACK, 5.0)]), [&"Status.Buffed"])
	)
	Factory.apply(target.asc, Factory.granting(Factory.infinite([]), [&"Status.Buffed"]))
	Factory.apply(target.asc, Factory.infinite([Factory.add(ATTACK, 5.0)]))

	var query: GameplayEffectQuery = GameplayEffectQuery.new()
	query.granted_tags = _tag_query([&"Status.Buffed"])
	query.modified_attribute = ATTACK
	assert_eq(target.asc.count_active_effects(query), 1, "only the one satisfying both")


func test_remove_by_query_snapshots_before_removing() -> void:
	Factory.apply(target.asc, Factory.granting(Factory.infinite([]), [&"Status.Poisoned"]))
	Factory.apply(target.asc, Factory.granting(Factory.infinite([]), [&"Status.Poisoned"]))

	var query: GameplayEffectQuery = GameplayEffectQuery.new()
	query.granted_tags = _tag_query([&"Status.Poisoned"])
	var removed: int = target.asc.remove_active_effects(query)

	assert_eq(removed, 2)
	assert_eq(target.asc.get_active_effects().size(), 0)


func test_duration_and_turn_queries_answer_by_handle() -> void:
	var duration_effect: ActiveGameplayEffect = Factory.apply(target.asc, Factory.duration([], 5.0))
	assert_almost_eq(target.asc.get_effect_duration_remaining(duration_effect.handle), 5.0, TOLERANCE)
	assert_eq(target.asc.get_effect_turns_remaining(duration_effect.handle), 0)

	var turn_effect: ActiveGameplayEffect = Factory.apply(target.asc, Factory.turn_based([], 3))
	assert_eq(target.asc.get_effect_turns_remaining(turn_effect.handle), 3)
	assert_almost_eq(target.asc.get_effect_duration_remaining(turn_effect.handle), 0.0, TOLERANCE)
#endregion


#region No mutable collections exposed
func test_found_effects_and_handles_are_copies() -> void:
	Factory.apply(target.asc, Factory.infinite([]))
	var found: Array[ActiveGameplayEffect] = target.asc.find_active_effects(GameplayEffectQuery.new())
	found.clear()
	assert_eq(target.asc.get_active_effects().size(), 1, "mutating the handed-out array touched nothing")
#endregion
