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


#region What a cue is told about the thing that fired it
## An effect with one application cue, and the binding it is played through.
func _cued(effect: GameplayEffect) -> GameplayCueBinding:
	Factory.with_application_cues(effect, [IMPACT] as Array[StringName])
	return effect.cues[0]


func _played() -> int:
	return CueProbe.executions(manager, fixture.owner, IMPACT)


## An effect that changed no number can be told to make no noise.
##
## Off by default, because an effect that only grants a tag is a real
## application whose cue should play - both arms are here because the default
## is the half that would silently change behaviour if it moved.
##
##     [what the effect asks for, whether the cue plays]
func _modifier_requirement_cases() -> Array:
	return [["asking for nothing", false, 1], ["requiring a number", true, 0]]


func test_cue_can_require_a_successful_modifier(
	case: Array = use_parameters(_modifier_requirement_cases())
) -> void:
	var described: String = case[0]
	var requiring: bool = case[1]
	var expected: int = case[2]

	# Granting a tag and nothing else: an application that happens, and moves
	# no attribute at all.
	var no_modifiers: Array[GameplayEffectModifier] = []
	var effect: GameplayEffect = Factory.granting(
		Factory.infinite(no_modifiers), [&"Status.Marked"] as Array[StringName]
	)
	_cued(effect)
	effect.require_modifier_success_to_trigger_cues = requiring

	Factory.apply(asc, effect)

	assert_true(asc.has_tag(&"Status.Marked"), "%s: it did apply" % described)
	assert_eq(_played(), expected, "%s: and the cue" % described)


## Ten arrows in a second is ten reapplications and, with this on, one sound.
##
## The first is not a reapplication - it is an application, and applications
## never come through the stacking path at all - so it plays either way.
func test_stacking_cue_can_be_suppressed_after_the_first_stack() -> void:
	var no_modifiers: Array[GameplayEffectModifier] = []
	var effect: GameplayEffect = Factory.infinite(no_modifiers)
	_cued(effect)
	Factory.stacked(effect, GameplayEffect.StackingType.AGGREGATE_BY_TARGET, 5)
	effect.suppress_stacking_cues = true

	Factory.apply(asc, effect)
	assert_eq(_played(), 1, "the first one is an application and it plays")

	var joined: ActiveGameplayEffect = Factory.apply(asc, effect)
	assert_eq(joined.stack_count, 2, "the second one joined the stack")
	assert_eq(_played(), 1, "and made no second sound")


## A cue can read itself off the target rather than off whatever fired it.
##
## Both numbers, because they answer different questions: the raw value is
## what a damage figure shows, and the normalised one is what a particle
## scales by - a cue that scaled by the raw number would be authored against
## this game's numbers and would break the day somebody rebalanced them.
func test_cue_magnitude_attribute_produces_raw_and_normalized_values() -> void:
	var no_modifiers: Array[GameplayEffectModifier] = []
	var effect: GameplayEffect = Factory.infinite(no_modifiers)
	var binding: GameplayCueBinding = _cued(effect)
	var reference: GameplayAttributeRef = GameplayAttributeRef.new()
	reference.attribute_name = TestAttributeSet.HEALTH
	binding.magnitude_attribute = reference
	binding.min_level = 0.0
	binding.max_level = 200.0

	asc.set_attribute_base(TestAttributeSet.HEALTH, 50.0)
	Factory.apply(asc, effect)
	var params: GameplayCueParams = _last_params()

	assert_eq(params.raw_magnitude, 50.0, "the reading itself")
	assert_eq(params.magnitude, 50.0, "under the old name too")
	assert_eq(params.normalized_magnitude, 0.25, "and where it sits in the range")


## Nothing that is a Node or an Object survives the trip.
##
## An ObjectID is a slot in one process's table: a peer resolving one would
## get whatever happens to be in that slot on its machine, which is worse than
## getting nothing. What crosses is the identity of the entity behind it.
func test_cue_params_wire_contains_ids_not_nodes() -> void:
	var registry: GameplayNetRegistry = GameplayNetRegistry.new()
	var named: GameplayNetEntityId = GameplayNetEntityId.of(7)
	registry.register_entity(named, asc)

	var params: GameplayCueParams = GameplayCueParams.new()
	params.cue_tag = IMPACT
	params.instigator = fixture.owner
	params.target = fixture.owner
	params.causer = fixture.owner
	params.source_object = fixture.owner
	params.set_magnitude(30.0, 0.0, 60.0)

	var wire: Dictionary = GameplayCueTranslator.to_wire(params, registry).to_wire()

	for key: Variant in wire:
		var kind: int = typeof(wire[key])
		assert_ne(kind, TYPE_OBJECT, "%s carries no object" % key)
		assert_ne(kind, TYPE_NODE_PATH, "%s carries no path either" % key)
	var crossed_causer: int = wire[GameplayCueWire.CAUSER_KEY]
	var crossed_fraction: float = wire[GameplayCueWire.NORMALIZED_KEY]
	assert_eq(
		crossed_causer,
		named.value,
		"the causer crossed as the identity of the entity behind it"
	)
	assert_eq(crossed_fraction, 0.5, "and the fraction crossed as a number")

	var back: GameplayCueParams = GameplayCueTranslator.from_wire(
		GameplayCueWire.from_wire(wire), registry
	)
	assert_eq(back.raw_magnitude, 30.0, "and the cue is the same cue on the far side")
	assert_eq(back.causer, fixture.owner, "resolved back to a node this machine has")


## The params of the most recent playback, read off the recording cue.
func _last_params() -> GameplayCueParams:
	return CueProbe.last_params(manager, fixture.owner, IMPACT)
#endregion


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
