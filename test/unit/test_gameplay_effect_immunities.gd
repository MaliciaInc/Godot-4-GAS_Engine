## GameplayEffectImmunityComponent: an active effect that blocks a matching
## incoming application before anything about it becomes observable.
##
## @meta_license: MIT
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Factory = preload("res://test/fixtures/test_effect_factory.gd")
const CueManagerScript = preload("res://addons/GodotGAS/managers/gameplay_cue_manager.gd")

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


## Grants an infinite, untagged immunity effect matching `query` on `asc`.
func _grant_immunity(asc: AbilitySystemComponent, query: GameplayEffectQuery) -> ActiveGameplayEffect:
	var immunity_effect: GameplayEffect = Factory.immune_to(Factory.infinite([]), query)
	return Factory.apply(asc, immunity_effect)


func _asset_tagged(tags: Array[StringName]) -> GameplayEffect:
	var effect: GameplayEffect = Factory.infinite([])
	var asset_component: GameplayEffectAssetTagsComponent = GameplayEffectAssetTagsComponent.new()
	asset_component.asset_tags = tags
	effect.components.append(asset_component)
	return effect


func test_no_immunity_lets_the_effect_through() -> void:
	var result: GameplayEffectApplicationResult = Factory.apply_result(target.asc, Factory.infinite([]))
	assert_true(result.is_ok())


## One or more immunities are granted, then one incoming effect is applied -
## exact match, a more specific descendant tag, and a second immunity that
## still matches when the first would not all reduce to this same shape.
class ImmuneMatchCase:
	var label: String
	var granted_queries: Array[GameplayEffectQuery] = []
	var incoming_asset_tags: Array[StringName] = []


func _immune_match_cases() -> Array[ImmuneMatchCase]:
	var exact: ImmuneMatchCase = ImmuneMatchCase.new()
	exact.label = "exact asset tag"
	var exact_query: GameplayEffectQuery = GameplayEffectQuery.new()
	exact_query.asset_tags = _tag_query([&"Damage.Fire"])
	exact.granted_queries = [exact_query]
	exact.incoming_asset_tags = [&"Damage.Fire"]

	var hierarchical: ImmuneMatchCase = ImmuneMatchCase.new()
	hierarchical.label = "hierarchical asset tag"
	var hierarchical_query: GameplayEffectQuery = GameplayEffectQuery.new()
	hierarchical_query.asset_tags = _tag_query([&"Damage.Fire"])
	hierarchical.granted_queries = [hierarchical_query]
	hierarchical.incoming_asset_tags = [&"Damage.Fire.Explosive"]

	var either_of_two: ImmuneMatchCase = ImmuneMatchCase.new()
	either_of_two.label = "either of two immunities"
	var ice_query: GameplayEffectQuery = GameplayEffectQuery.new()
	ice_query.asset_tags = _tag_query([&"Damage.Ice"])
	var fire_query: GameplayEffectQuery = GameplayEffectQuery.new()
	fire_query.asset_tags = _tag_query([&"Damage.Fire"])
	either_of_two.granted_queries = [ice_query, fire_query]
	either_of_two.incoming_asset_tags = [&"Damage.Fire"]

	return [exact, hierarchical, either_of_two] as Array[ImmuneMatchCase]


func test_a_matching_incoming_effect_is_refused_as_immune(
	case: ImmuneMatchCase = use_parameters(_immune_match_cases())
) -> void:
	for query: GameplayEffectQuery in case.granted_queries:
		_grant_immunity(target.asc, query)

	var result: GameplayEffectApplicationResult = Factory.apply_result(
		target.asc, _asset_tagged(case.incoming_asset_tags)
	)
	assert_eq(result.status, GameplayEffectApplicationResult.Status.IMMUNE, case.label)
	assert_null(result.active_effect, case.label)


## `Damage.Firestorm` merely starts with the same characters as `Damage.Fire`
## - it is a sibling, not a descendant, and must not match.
func test_a_tag_sharing_only_a_string_prefix_does_not_match() -> void:
	var query: GameplayEffectQuery = GameplayEffectQuery.new()
	query.asset_tags = _tag_query([&"Damage.Fire"])
	_grant_immunity(target.asc, query)

	var result: GameplayEffectApplicationResult = Factory.apply_result(
		target.asc, _asset_tagged([&"Damage.Firestorm"])
	)
	assert_true(result.is_ok(), "a sibling tag is not a match")


func test_a_source_tag_match_is_refused() -> void:
	source.asc.add_tag(&"Class.Mage")
	var query: GameplayEffectQuery = GameplayEffectQuery.new()
	query.source_tags = _tag_query([&"Class.Mage"])
	_grant_immunity(target.asc, query)

	var result: GameplayEffectApplicationResult = Factory.apply_result(
		target.asc, Factory.infinite([]), source.owner
	)
	assert_eq(result.status, GameplayEffectApplicationResult.Status.IMMUNE)


func test_a_granted_tag_match_is_refused() -> void:
	var query: GameplayEffectQuery = GameplayEffectQuery.new()
	query.granted_tags = _tag_query([&"Status.Poisoned"])
	_grant_immunity(target.asc, query)

	var incoming: GameplayEffect = Factory.granting(Factory.infinite([]), [&"Status.Poisoned"])
	var result: GameplayEffectApplicationResult = Factory.apply_result(target.asc, incoming)
	assert_eq(result.status, GameplayEffectApplicationResult.Status.IMMUNE)


## `target_tags` reads the immune target's own current tags, not the
## incoming effect - immunity here is conditional on a second status.
func test_a_target_tag_condition_gates_the_immunity() -> void:
	var query: GameplayEffectQuery = GameplayEffectQuery.new()
	query.asset_tags = _tag_query([&"Damage.Fire"])
	query.target_tags = _tag_query([&"Status.Shielded"])
	_grant_immunity(target.asc, query)

	var first: GameplayEffectApplicationResult = Factory.apply_result(target.asc, _asset_tagged([&"Damage.Fire"]))
	assert_true(first.is_ok(), "not shielded yet")

	target.asc.tags.add(&"Status.Shielded")
	var second: GameplayEffectApplicationResult = Factory.apply_result(target.asc, _asset_tagged([&"Damage.Fire"]))
	assert_eq(second.status, GameplayEffectApplicationResult.Status.IMMUNE)


func test_an_effect_definition_match_is_refused_but_others_are_not() -> void:
	var warded_against: GameplayEffect = Factory.infinite([])
	var query: GameplayEffectQuery = GameplayEffectQuery.new()
	query.effect_definition = warded_against
	_grant_immunity(target.asc, query)

	assert_eq(
		Factory.apply_result(target.asc, warded_against).status,
		GameplayEffectApplicationResult.Status.IMMUNE
	)
	assert_true(Factory.apply_result(target.asc, Factory.infinite([])).is_ok(), "a different definition")


func test_removing_the_immunity_effect_allows_the_application_again() -> void:
	var query: GameplayEffectQuery = GameplayEffectQuery.new()
	query.asset_tags = _tag_query([&"Damage.Fire"])
	var immunity: ActiveGameplayEffect = _grant_immunity(target.asc, query)

	assert_eq(
		Factory.apply_result(target.asc, _asset_tagged([&"Damage.Fire"])).status,
		GameplayEffectApplicationResult.Status.IMMUNE
	)

	target.asc.remove_active_effect_by_handle(immunity.handle)
	assert_true(Factory.apply_result(target.asc, _asset_tagged([&"Damage.Fire"])).is_ok())


func test_an_immune_periodic_effect_is_never_registered() -> void:
	var query: GameplayEffectQuery = GameplayEffectQuery.new()
	query.asset_tags = _tag_query([&"Damage.Fire"])
	_grant_immunity(target.asc, query)

	var before: int = target.asc.get_active_effects().size()
	var periodic: GameplayEffect = _asset_tagged([&"Damage.Fire"])
	periodic.policy = GameplayEffect.DurationPolicy.INFINITE
	periodic.period = 1.0
	periodic.modifiers = [Factory.add(ATTACK, 1.0)]

	var result: GameplayEffectApplicationResult = Factory.apply_result(target.asc, periodic)
	assert_eq(result.status, GameplayEffectApplicationResult.Status.IMMUNE)
	assert_eq(target.asc.get_active_effects().size(), before, "nothing new was registered to tick")


func test_an_immune_effect_never_purges_other_active_effects() -> void:
	var immunity_query: GameplayEffectQuery = GameplayEffectQuery.new()
	immunity_query.asset_tags = _tag_query([&"Damage.Fire"])
	_grant_immunity(target.asc, immunity_query)

	var survivor: ActiveGameplayEffect = Factory.apply(
		target.asc, Factory.granting(Factory.infinite([]), [&"Status.Blessed"])
	)

	var incoming: GameplayEffect = Factory.removing_effects_with_tags(
		_asset_tagged([&"Damage.Fire"]), [&"Status.Blessed"]
	)
	var result: GameplayEffectApplicationResult = Factory.apply_result(target.asc, incoming)

	assert_eq(result.status, GameplayEffectApplicationResult.Status.IMMUNE)
	assert_true(target.asc.get_active_effects().has(survivor), "the purge this effect would have done never ran")


func test_an_immune_effect_dispatches_no_events_and_plays_no_cues() -> void:
	var query: GameplayEffectQuery = GameplayEffectQuery.new()
	query.asset_tags = _tag_query([&"Damage.Fire"])
	_grant_immunity(target.asc, query)

	var manager: CueManagerScript = target.asc.get_node_or_null("/root/GameplayCueManager") as CueManagerScript
	var incoming: GameplayEffect = Factory.with_application_cues(
		Factory.with_events(_asset_tagged([&"Damage.Fire"]), [&"Event.Damage.Taken"]),
		[&"Cue.Immunity.Test.Never"]
	)

	watch_signals(target.asc)
	var result: GameplayEffectApplicationResult = Factory.apply_result(target.asc, incoming)

	assert_eq(result.status, GameplayEffectApplicationResult.Status.IMMUNE)
	assert_signal_not_emitted(target.asc, "gameplay_event_received")
	assert_eq(manager.get_pooled_count(&"Cue.Immunity.Test.Never"), 0, "the cue was never even taken from its pool")


## Two targets share the exact same GameplayEffectImmunityComponent Resource
## (authored once, granted to both) - neither's application changes what the
## other is immune to, because the component holds no per-application state.
func test_the_shared_immunity_component_carries_no_mutable_state_between_targets() -> void:
	var query: GameplayEffectQuery = GameplayEffectQuery.new()
	query.asset_tags = _tag_query([&"Damage.Fire"])
	var immunity_effect: GameplayEffect = Factory.immune_to(Factory.infinite([]), query)

	Factory.apply(target.asc, immunity_effect)
	Factory.apply(source.asc, immunity_effect)

	assert_eq(
		Factory.apply_result(target.asc, _asset_tagged([&"Damage.Fire"])).status,
		GameplayEffectApplicationResult.Status.IMMUNE
	)
	assert_eq(
		Factory.apply_result(source.asc, _asset_tagged([&"Damage.Fire"])).status,
		GameplayEffectApplicationResult.Status.IMMUNE
	)
	assert_true(Factory.apply_result(target.asc, _asset_tagged([&"Damage.Ice"])).is_ok())
