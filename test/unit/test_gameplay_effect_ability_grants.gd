## GameplayEffectGrantAbilitiesComponent: an effect that grants abilities
## while it is active, retiring them per grant's own removal policy - reusing
## Task 4's grant pipeline exactly, never a second validator.
##
## @meta_license: MIT
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Factory = preload("res://test/fixtures/test_effect_factory.gd")

var target: ASCFixture = null


func before_each() -> void:
	target = Fixture.create("Target")
	add_child_autofree(target.owner)


func after_each() -> void:
	target = null


func _invalid_scene() -> PackedScene:
	var node: Node = Node.new()
	var scene: PackedScene = PackedScene.new()
	scene.pack(node)
	node.free()
	return scene


#region Grant and receipt
func test_granting_one_ability_makes_it_resolvable_on_the_target() -> void:
	var scene: PackedScene = Factory.ability_scene(ProbeAbility.build(&"Ability.Granted"))
	var effect: GameplayEffect = Factory.granting_ability(Factory.infinite([]), scene)

	var active: ActiveGameplayEffect = Factory.apply(target.asc, effect)
	assert_eq(active.granted_ability_handles.size(), 1)
	var spec: GameplayAbilitySpec = target.asc.ability_runtime.get_spec(active.granted_ability_handles[0])
	assert_not_null(spec, "resolvable through the real ability runtime")


func test_granting_multiple_abilities_grants_all_of_them() -> void:
	var scene_a: PackedScene = Factory.ability_scene(ProbeAbility.build(&"Ability.A"))
	var scene_b: PackedScene = Factory.ability_scene(ProbeAbility.build(&"Ability.B"))
	var effect: GameplayEffect = Factory.granting_ability(
		Factory.granting_ability(Factory.infinite([]), scene_a), scene_b
	)

	var active: ActiveGameplayEffect = Factory.apply(target.asc, effect)
	assert_eq(active.granted_ability_handles.size(), 2)
	assert_not_null(target.asc.ability_runtime.get_spec(active.granted_ability_handles[0]))
	assert_not_null(target.asc.ability_runtime.get_spec(active.granted_ability_handles[1]))


func test_an_invalid_ability_scene_refuses_the_whole_parent_application() -> void:
	var effect: GameplayEffect = Factory.granting_ability(Factory.infinite([Factory.add(&"attack", 5.0)]), _invalid_scene())
	var base: float = target.current_of(&"attack")

	var result: GameplayEffectApplicationResult = Factory.apply_result(target.asc, effect)
	assert_eq(result.status, GameplayEffectApplicationResult.Status.COMPONENT_REJECTED)
	assert_almost_eq(target.current_of(&"attack"), base, 0.0001, "nothing about the parent landed either")
	assert_eq(target.asc.get_active_effects().size(), 0)


func test_one_bad_grant_rolls_back_every_grant_already_prepared() -> void:
	var good_scene: PackedScene = Factory.ability_scene(ProbeAbility.build(&"Ability.Good"))
	var effect: GameplayEffect = Factory.granting_ability(
		Factory.granting_ability(Factory.infinite([]), good_scene), _invalid_scene()
	)

	var result: GameplayEffectApplicationResult = Factory.apply_result(target.asc, effect)
	assert_false(result.is_ok())
	assert_eq(target.asc.ability_runtime.specs().size(), 0, "the good grant never committed either")


func test_the_receipt_matches_exactly_what_was_granted() -> void:
	var scene: PackedScene = Factory.ability_scene(ProbeAbility.build(&"Ability.Receipt"))
	var effect: GameplayEffect = Factory.granting_ability(Factory.infinite([]), scene)

	var active: ActiveGameplayEffect = Factory.apply(target.asc, effect)
	assert_eq(active.granted_ability_handles.size(), 1)
	assert_eq(target.asc.ability_runtime.specs().size(), 1)
	assert_eq(target.asc.ability_runtime.specs()[0].handle, active.granted_ability_handles[0])


func test_the_granted_specs_source_names_the_granting_effect() -> void:
	var scene: PackedScene = Factory.ability_scene(ProbeAbility.build(&"Ability.Sourced"))
	var effect: GameplayEffect = Factory.granting_ability(Factory.infinite([]), scene)

	var active: ActiveGameplayEffect = Factory.apply(target.asc, effect)
	var spec: GameplayAbilitySpec = target.asc.ability_runtime.get_spec(active.granted_ability_handles[0])
	var source: GameplayAbilityEffectSource = spec.source as GameplayAbilityEffectSource
	assert_not_null(source, "GameplayAbilityEffectSource, not a bare Variant")
	assert_true(source.effect_handle.same_as(active.handle))
#endregion


#region Removal policies
## Same setup, opposite question: does removing the granting effect cut off
## a still-channelling activation, or let it finish first? `channels` is a
## test-only field, not @export - it does not survive packing (see
## TestAbilityFactory.give()'s own doc comment) and must be set on the real
## running instance the grant produced, not the template.
class RemovalPolicyCase:
	var label: String
	var policy: GameplayEffectAbilityGrant.RemovalPolicy
	var cuts_off_immediately: bool


func _removal_policy_cases() -> Array[RemovalPolicyCase]:
	var cancel: RemovalPolicyCase = RemovalPolicyCase.new()
	cancel.label = "CANCEL_AND_REMOVE_ON_EFFECT_END"
	cancel.policy = GameplayEffectAbilityGrant.RemovalPolicy.CANCEL_AND_REMOVE_ON_EFFECT_END
	cancel.cuts_off_immediately = true

	var pending: RemovalPolicyCase = RemovalPolicyCase.new()
	pending.label = "REMOVE_ON_ACTIVE_END"
	pending.policy = GameplayEffectAbilityGrant.RemovalPolicy.REMOVE_ON_ACTIVE_END
	pending.cuts_off_immediately = false

	return [cancel, pending] as Array[RemovalPolicyCase]


func test_removal_policy_governs_whether_removal_cuts_off_a_running_activation(
	case: RemovalPolicyCase = use_parameters(_removal_policy_cases())
) -> void:
	var scene: PackedScene = Factory.ability_scene(ProbeAbility.build(&"Ability.Policy"))
	var effect: GameplayEffect = Factory.granting_ability(Factory.infinite([]), scene, case.policy)

	var active: ActiveGameplayEffect = Factory.apply(target.asc, effect)
	var handle: GameplayAbilityHandle = active.granted_ability_handles[0]
	var spec: GameplayAbilitySpec = target.asc.ability_runtime.get_spec(handle)
	var instance: ProbeAbility = spec.per_actor_instance as ProbeAbility
	instance.channels = true
	instance.try_activate()
	assert_true(instance.is_active, case.label + ": channelling, still active")

	target.asc.effects.remove(active)
	if case.cuts_off_immediately:
		assert_null(target.asc.ability_runtime.get_spec(handle), case.label + ": retired immediately, cancelled mid-channel")
		return

	assert_not_null(target.asc.ability_runtime.get_spec(handle), case.label + ": still running, not retired yet")
	assert_eq(
		target.asc.ability_runtime.activation_error(spec), AbilityRuntime.ActivationError.PENDING_REMOVAL,
		case.label + ": no new activation while pending"
	)
	instance.channel_gate.emit()
	assert_null(target.asc.ability_runtime.get_spec(handle), case.label + ": retired the moment it ended")


func test_keep_after_effect_end_never_retires_the_ability() -> void:
	var scene: PackedScene = Factory.ability_scene(ProbeAbility.build(&"Ability.Kept"))
	var effect: GameplayEffect = Factory.granting_ability(
		Factory.infinite([]), scene, GameplayEffectAbilityGrant.RemovalPolicy.KEEP_AFTER_EFFECT_END
	)

	var active: ActiveGameplayEffect = Factory.apply(target.asc, effect)
	var handle: GameplayAbilityHandle = active.granted_ability_handles[0]

	target.asc.effects.remove(active)
	assert_not_null(target.asc.ability_runtime.get_spec(handle), "the effect ending never touches it")
#endregion


#region Stacking interaction
func test_a_stack_grants_the_ability_exactly_once() -> void:
	var scene: PackedScene = Factory.ability_scene(ProbeAbility.build(&"Ability.Stacked"))
	var effect: GameplayEffect = Factory.granting_ability(
		Factory.stacked(Factory.infinite([]), GameplayEffect.StackingType.AGGREGATE_BY_TARGET, 0), scene
	)

	var active: ActiveGameplayEffect = Factory.apply(target.asc, effect)
	Factory.apply(target.asc, effect)
	assert_eq(active.stack_count, 2)
	assert_eq(active.granted_ability_handles.size(), 1, "granted once per active effect, not once per join")
	assert_eq(target.asc.ability_runtime.specs().size(), 1)


func test_removing_a_stack_retires_the_ability_exactly_once() -> void:
	var scene: PackedScene = Factory.ability_scene(ProbeAbility.build(&"Ability.StackRemoved"))
	var effect: GameplayEffect = Factory.granting_ability(
		Factory.stacked(Factory.infinite([]), GameplayEffect.StackingType.AGGREGATE_BY_TARGET, 0), scene
	)

	var active: ActiveGameplayEffect = Factory.apply(target.asc, effect)
	Factory.apply(target.asc, effect)
	var handle: GameplayAbilityHandle = active.granted_ability_handles[0]

	target.asc.effects.remove(active)
	assert_null(target.asc.ability_runtime.get_spec(handle))
	assert_eq(target.asc.ability_runtime.specs().size(), 0)
#endregion


#region Cleanup
func test_cleanup_retires_every_active_effects_granted_abilities() -> void:
	var scene: PackedScene = Factory.ability_scene(ProbeAbility.build(&"Ability.CleanedUp"))
	var effect: GameplayEffect = Factory.granting_ability(Factory.infinite([]), scene)
	Factory.apply(target.asc, effect)
	assert_eq(target.asc.ability_runtime.specs().size(), 1)

	target.asc.cleanup()
	assert_eq(target.asc.get_active_effects().size(), 0)
	assert_eq(target.asc.ability_runtime.specs().size(), 0)
#endregion
