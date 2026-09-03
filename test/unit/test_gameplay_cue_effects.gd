## Cues driven by GameplayEffect application, removal and inhibition.
##
## Split from `test_gameplay_cues.gd`, which covers the cue node and the
## manager's own mechanics. This file covers the other side: what the effect
## runtime asks the manager to do as an active effect is applied, joined into a
## stack, inhibited, removed or torn down with the ASC. The two grew into one
## file and one file grew past the length gate; the seam was already there in
## the region boundary.
##
## Every playback goes through the real GameplayCueManager autoload, with a
## recording cue installed under a tag by CueProbe.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Factory = preload("res://test/fixtures/test_effect_factory.gd")
const CueManagerScript = preload("res://addons/GAS_Engine/managers/gameplay_cue_manager.gd")
const CueProbe = preload("res://test/fixtures/cue_probe.gd")

const IMPACT: StringName = &"Cue.Impact"

var fixture: ASCFixture = null
var asc: AbilitySystemComponent = null
var manager: CueManagerScript = null


func before_each() -> void:
	fixture = Fixture.create("CueTarget")
	add_child_autofree(fixture.owner)
	asc = fixture.asc
	manager = asc.get_node_or_null("/root/GameplayCueManager") as CueManagerScript
	CueProbe.install(manager, IMPACT)


func after_each() -> void:
	CueProbe.uninstall(manager, IMPACT)
	fixture = null
	asc = null
	manager = null


func _infinite_persistent(tag: StringName) -> GameplayEffect:
	var no_modifiers: Array[GameplayEffectModifier] = []
	return Factory.with_persistent_cues(Factory.infinite(no_modifiers), [tag])


func test_effect_application_activates_exactly_one_persistent_cue_per_binding() -> void:
	var active: ActiveGameplayEffect = Factory.apply(asc, _infinite_persistent(IMPACT))
	assert_eq(active.persistent_cue_handles.size(), 1)
	assert_true(active.persistent_cue_handles[0].is_valid())


func test_removing_the_effect_pools_the_persistent_cue_exactly_once() -> void:
	var active: ActiveGameplayEffect = Factory.apply(asc, _infinite_persistent(IMPACT))
	var pooled_before: int = manager.get_pooled_count(IMPACT)

	asc.effects.remove(active)
	assert_eq(active.persistent_cue_handles.size(), 0, "the receipt is cleared")
	assert_eq(manager.get_pooled_count(IMPACT), pooled_before + 1, "pooled exactly once")


func test_two_effects_sharing_a_cue_tag_get_independent_handles() -> void:
	var first: ActiveGameplayEffect = Factory.apply(asc, _infinite_persistent(IMPACT))
	var second: ActiveGameplayEffect = Factory.apply(asc, _infinite_persistent(IMPACT))
	assert_false(first.persistent_cue_handles[0].id == second.persistent_cue_handles[0].id)

	asc.effects.remove(first)
	assert_eq(second.persistent_cue_handles.size(), 1, "removing one never touches the other's receipt")


func test_a_stack_reapplication_does_not_create_a_second_persistent_cue() -> void:
	var effect: GameplayEffect = _infinite_persistent(IMPACT)
	Factory.stacked(effect, GameplayEffect.StackingType.AGGREGATE_BY_TARGET, 5)
	Factory.apply(asc, effect)
	var active: ActiveGameplayEffect = Factory.apply(asc, effect)
	assert_eq(active.stack_count, 2, "the join happened")
	assert_eq(active.persistent_cue_handles.size(), 1, "one per active effect, not one per join")


func test_inhibiting_the_effect_removes_its_persistent_cue() -> void:
	asc.add_tag(&"Status.Ready")
	var effect: GameplayEffect = Factory.with_ongoing_requirement(_infinite_persistent(IMPACT), [&"Status.Ready"])
	var active: ActiveGameplayEffect = Factory.apply(asc, effect)
	assert_eq(active.persistent_cue_handles.size(), 1)

	asc.remove_tag(&"Status.Ready")
	assert_true(active.inhibited)
	assert_eq(active.persistent_cue_handles.size(), 0, "on_removed already ran, receipt cleared")


func test_uninhibiting_activates_a_fresh_handle_not_the_old_one() -> void:
	asc.add_tag(&"Status.Ready")
	var effect: GameplayEffect = Factory.with_ongoing_requirement(_infinite_persistent(IMPACT), [&"Status.Ready"])
	var active: ActiveGameplayEffect = Factory.apply(asc, effect)
	var first_id: int = active.persistent_cue_handles[0].id

	asc.remove_tag(&"Status.Ready")
	asc.add_tag(&"Status.Ready")
	assert_false(active.inhibited)
	assert_eq(active.persistent_cue_handles.size(), 1, "a new lifecycle activation")
	assert_ne(active.persistent_cue_handles[0].id, first_id, "never the old handle reused")


func test_cleanup_ends_persistent_cues_exactly_once() -> void:
	Factory.apply(asc, _infinite_persistent(IMPACT))
	var pooled_before: int = manager.get_pooled_count(IMPACT)

	asc.cleanup()
	assert_eq(manager.get_pooled_count(IMPACT), pooled_before + 1, "pooled exactly once, not per teardown path")


func test_missing_registry_activation_returns_an_invalid_handle_without_crashing() -> void:
	var handle: GameplayCueHandle = asc.activate_persistent_cue(CueProbe.params_for(&"Cue.NeverRegistered", fixture.owner))
	assert_false(handle.is_valid())
	asc.deactivate_persistent_cue(handle, CueProbe.params_for(&"Cue.NeverRegistered", fixture.owner))
	pass_test("no crash either way")


## Task 19's own "cue callback cannot mutate runtime through exposed internal
## collection": the params a cue receives carry only an opaque handle, never
## the live ActiveGameplayEffect a script could reach in and edit.
func test_cue_params_carry_an_opaque_handle_not_a_live_reference() -> void:
	var active: ActiveGameplayEffect = Factory.apply(asc, _infinite_persistent(IMPACT))
	var params: GameplayCueParams = asc.effects.cue_params_for(IMPACT, active.spec, active.handle)
	assert_true(params.effect_handle is GameplayEffectHandle, "an opaque handle, not the live effect")
	assert_true(params.effect_handle.same_as(active.handle), "the same identity, not a copy that drifted")
	var declared_fields: Array[String] = []
	for property: Dictionary in params.get_property_list():
		declared_fields.append(property.name)
	assert_false(
		declared_fields.has("active_effect"), "no live ActiveGameplayEffect field exists on GameplayCueParams"
	)
